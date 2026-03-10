--!strict
-- EventPoller: Periodically polls for new Starknet events matching a filter
-- Since Roblox lacks WebSockets, polling is the only option for "real-time" events
-- Configurable interval with rate-limit awareness

local RpcTypes = require("./RpcTypes")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes
local Defaults = require("../shared/TestableDefaults")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type EventPoller = {
	start: (self: EventPoller) -> (),
	stop: (self: EventPoller) -> (),
	isRunning: (self: EventPoller) -> boolean,
	getLastBlockNumber: (self: EventPoller) -> number?,
	setLastBlockNumber: (self: EventPoller, blockNumber: number) -> (),
	getCheckpointKey: (self: EventPoller) -> string?,
}

local DEFAULT_CHECKPOINT_KEY = "EventPoller_checkpoint"

--------------------------------------------------------------------------------
-- EventPoller class
--------------------------------------------------------------------------------

local EventPollerClass = {}
EventPollerClass.__index = EventPollerClass

--- Create a new EventPoller.
--- @param config -- EventPollerConfig with provider, filter, interval, callbacks
function EventPollerClass.new(config: RpcTypes.EventPollerConfig): EventPoller
	if not config.provider then
		error(StarknetError.validation("EventPoller: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.filter then
		error(StarknetError.validation("EventPoller: filter is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.onEvents then
		error(StarknetError.validation("EventPoller: onEvents callback is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local self = setmetatable({
		_provider = config.provider,
		_filter = config.filter,
		_interval = config.interval or 10,
		_onEvents = config.onEvents,
		_onError = config.onError or function(_err: any) end,
		_onCheckpoint = config.onCheckpoint,
		_dataStore = config._dataStore,
		_checkpointKey = if config._dataStore then (config.checkpointKey or DEFAULT_CHECKPOINT_KEY) else nil,
		_running = false,
		_lastBlockNumber = nil :: number?,
		_sleep = config._sleep or Defaults.sleep,
		_clock = config._clock or Defaults.clock,
	}, EventPollerClass)

	return self :: any
end

--- Persist the current checkpoint to DataStore and fire the onCheckpoint callback.
--- DataStore write fires first (if configured), then callback (regardless of DataStore success).
function EventPollerClass:_checkpoint(blockNumber: number)
	if self._dataStore then
		local dsOk, dsErr = pcall(function()
			self._dataStore:SetAsync(self._checkpointKey, {
				blockNumber = blockNumber,
				timestamp = self._clock(),
			})
		end)
		if not dsOk then
			self._onError(dsErr)
		end
	end

	if self._onCheckpoint then
		self._onCheckpoint(blockNumber)
	end
end

--- Start polling for events. Runs in a loop until stop() is called.
function EventPollerClass:start()
	if self._running then
		return
	end
	self._running = true

	-- Restore checkpoint from DataStore if configured
	if self._dataStore and not self._lastBlockNumber then
		local dsOk, dsResult = pcall(function()
			return self._dataStore:GetAsync(self._checkpointKey)
		end)
		if dsOk and dsResult ~= nil then
			local restored: number? = nil
			if type(dsResult) == "number" then
				restored = dsResult
			elseif type(dsResult) == "table" and type(dsResult.blockNumber) == "number" then
				restored = dsResult.blockNumber
			end
			if restored then
				self:setLastBlockNumber(restored)
			end
		elseif not dsOk then
			self._onError(dsResult)
		end
	end

	-- Initialize from_block if not set — start from current block
	local filter: RpcTypes.EventFilter = self._filter
	if not filter.from_block then
		local ok, blockNum = pcall(function()
			return self._provider:fetchSync("starknet_blockNumber", {})
		end)
		if ok and blockNum then
			local num = if type(blockNum) == "number" then blockNum else (tonumber(blockNum) or 0)
			self._lastBlockNumber = num
			filter = {
				from_block = { block_number = num },
				to_block = filter.to_block or ({ block_tag = "latest" } :: any),
				address = filter.address,
				keys = filter.keys,
				chunk_size = filter.chunk_size or 100,
			}
		end
	end

	-- Build stable filter fields once (from_block is updated after events)
	local toBlock = filter.to_block or ({ block_tag = "latest" } :: any)
	local filterAddress = filter.address
	local filterKeys = filter.keys
	local filterChunkSize = filter.chunk_size or 100

	while self._running do
		local ok, result = pcall(function()
			-- Use getAllEvents to get all pages in one go
			local allEvents: { RpcTypes.EmittedEvent } = {}
			local continuationToken: string? = nil

			for _ = 1, 100 do -- safety limit per poll cycle
				local pageFilter: { [string]: any } = {
					from_block = filter.from_block,
					to_block = toBlock,
					address = filterAddress,
					keys = filterKeys,
					chunk_size = filterChunkSize,
				}
				if continuationToken then
					pageFilter.continuation_token = continuationToken
				end

				local chunk = self._provider:fetchSync("starknet_getEvents", {
					{ filter = pageFilter },
				})

				local events = chunk.events or {}
				for _, event in events do
					table.insert(allEvents, event)
				end

				continuationToken = chunk.continuation_token
				if not continuationToken or continuationToken == "" then
					break
				end
			end

			return allEvents
		end)

		if ok and result then
			local events = result :: { RpcTypes.EmittedEvent }
			if #events > 0 then
				-- Deliver events to callback
				local cbOk, cbErr = pcall(self._onEvents, events)
				if not cbOk then
					self._onError(cbErr)
				end

				-- Advance from_block past the highest block we've seen
				local maxBlock = 0
				for _, event in events do
					if event.block_number and event.block_number > maxBlock then
						maxBlock = event.block_number
					end
				end
				if maxBlock > 0 then
					self._lastBlockNumber = maxBlock
					-- Next poll starts from block after the highest seen
					filter = {
						from_block = { block_number = maxBlock + 1 },
						to_block = filter.to_block,
						address = filter.address,
						keys = filter.keys,
						chunk_size = filter.chunk_size,
					}
					-- Persist checkpoint
					self:_checkpoint(maxBlock)
				end
			end
		elseif not ok then
			self._onError(result)
		end

		if self._running then
			self._sleep(self._interval)
		end
	end
end

--- Stop the polling loop.
function EventPollerClass:stop()
	self._running = false
end

--- Check if the poller is currently running.
function EventPollerClass:isRunning(): boolean
	return self._running
end

--- Get the last block number that was polled (nil if no poll has completed yet).
function EventPollerClass:getLastBlockNumber(): number?
	return self._lastBlockNumber
end

--- Set the last block number manually (for restoring state before start()).
--- Also updates the internal filter's from_block so start() resumes from blockNumber + 1.
function EventPollerClass:setLastBlockNumber(blockNumber: number)
	self._lastBlockNumber = blockNumber
	self._filter = {
		from_block = { block_number = blockNumber + 1 },
		to_block = self._filter.to_block,
		address = self._filter.address,
		keys = self._filter.keys,
		chunk_size = self._filter.chunk_size,
	}
end

--- Get the configured checkpoint key (nil if no DataStore is configured).
function EventPollerClass:getCheckpointKey(): string?
	return self._checkpointKey
end

return EventPollerClass
