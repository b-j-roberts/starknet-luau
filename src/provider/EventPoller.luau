--!strict
-- EventPoller: Periodically polls for new Starknet events matching a filter
-- Since Roblox lacks WebSockets, polling is the only option for "real-time" events
-- Configurable interval with rate-limit awareness

local RpcTypes = require("./RpcTypes")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type EventPoller = {
	start: (self: EventPoller) -> (),
	stop: (self: EventPoller) -> (),
	isRunning: (self: EventPoller) -> boolean,
}

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
		_running = false,
		_lastBlockNumber = nil :: number?,
		_sleep = config._sleep or function(seconds: number)
			task.wait(seconds)
		end,
		_clock = config._clock or os.clock,
	}, EventPollerClass)

	return self :: any
end

--- Start polling for events. Runs in a loop until stop() is called.
function EventPollerClass:start()
	if self._running then
		return
	end
	self._running = true

	-- Initialize from_block if not set — start from current block
	local filter: RpcTypes.EventFilter = self._filter
	if not filter.from_block then
		local ok, blockNum = pcall(function()
			return self._provider:_requestWithRetry("starknet_blockNumber", {})
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

	while self._running do
		local pollFilter: RpcTypes.EventFilter = {
			from_block = filter.from_block,
			to_block = filter.to_block or ({ block_tag = "latest" } :: any),
			address = filter.address,
			keys = filter.keys,
			chunk_size = filter.chunk_size or 100,
		}

		local ok, result = pcall(function()
			-- Use getAllEvents to get all pages in one go
			local allEvents: { RpcTypes.EmittedEvent } = {}
			local continuationToken: string? = nil

			for _ = 1, 100 do -- safety limit per poll cycle
				local pageFilter: { [string]: any } = {
					from_block = pollFilter.from_block,
					to_block = pollFilter.to_block,
					address = pollFilter.address,
					keys = pollFilter.keys,
					chunk_size = pollFilter.chunk_size or 100,
				}
				if continuationToken then
					pageFilter.continuation_token = continuationToken
				end

				local chunk = self._provider:_requestWithRetry("starknet_getEvents", {
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

return EventPollerClass
