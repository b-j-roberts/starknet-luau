--!strict
-- NonceManager: Intelligent nonce management for sequential transaction submission
-- Tracks local nonces per account address, supports parallel reservation,
-- auto-increments on success, and re-syncs with on-chain state on failure.
-- Critical for games that submit multiple transactions in quick succession.

local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type NonceState = {
	nextNonce: number, -- Next nonce to reserve (0-indexed)
	pending: { [number]: boolean }, -- Set of reserved-but-unconfirmed nonces
	initialized: boolean, -- Whether we've fetched from chain at least once
	dirty: boolean, -- Needs re-sync before next reserve
}

export type NonceManagerMetrics = {
	totalReserved: number,
	totalConfirmed: number,
	totalRejected: number,
	totalResyncs: number,
}

--------------------------------------------------------------------------------
-- NonceManager class
--------------------------------------------------------------------------------

local NonceManager = {}
NonceManager.__index = NonceManager

--- Create a new NonceManager.
--- @param provider -- RpcProvider instance (used for on-chain nonce fetching)
--- @param config -- optional NonceManagerConfig
function NonceManager.new(provider: any, config: { maxPendingNonces: number?, autoResyncOnError: boolean? }?): any
	local cfg = config or {}

	local self = setmetatable({
		_provider = provider,
		_states = {} :: { [string]: NonceState },
		_maxPendingNonces = cfg.maxPendingNonces or 10,
		_autoResync = if cfg.autoResyncOnError ~= nil then cfg.autoResyncOnError else true,
		_metrics = {
			totalReserved = 0,
			totalConfirmed = 0,
			totalRejected = 0,
			totalResyncs = 0,
		} :: NonceManagerMetrics,
	}, NonceManager)

	return self
end

--- Internal: Count pending nonces for an address state.
local function countPending(state: NonceState): number
	local count = 0
	for _ in state.pending do
		count += 1
	end
	return count
end

--- Internal: Fetch the on-chain nonce for an address.
--- Uses "pending" block tag to include sequencer-accepted but not-yet-included transactions.
function NonceManager:_fetchOnChainNonce(address: string): string
	local result = self._provider:getNonce(address, "pending"):expect()
	return result
end

--- Reserve the next available nonce for an address.
--- Returns a Promise resolving to a hex string nonce.
--- On first call per address, fetches the on-chain nonce.
--- Subsequent calls return locally tracked nonces.
function NonceManager:reserve(address: string): any
	local Promise = self._provider:_getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local state = self._states[address]

		-- Initialize or re-sync if dirty
		if not state or not state.initialized or state.dirty then
			local ok, result = pcall(function()
				return self:_fetchOnChainNonce(address)
			end)
			if not ok then
				reject(
					StarknetError.rpc(
						`NonceManager: failed to fetch nonce for {address}: {tostring(result)}`,
						ErrorCodes.NONCE_FETCH_ERROR.code
					)
				)
				return
			end

			local onChainNonce = tonumber(result, 16)
			if not onChainNonce then
				-- Try decimal parsing as fallback
				onChainNonce = tonumber(result) or 0
			end

			if state and state.dirty then
				self._metrics.totalResyncs += 1
			end

			state = {
				nextNonce = onChainNonce,
				pending = {},
				initialized = true,
				dirty = false,
			}
			self._states[address] = state
		end

		-- Check backpressure
		local pendingCount = countPending(state)
		if pendingCount >= self._maxPendingNonces then
			reject(
				StarknetError.transaction(
					`NonceManager: too many pending nonces ({pendingCount}) for {address}`,
					ErrorCodes.NONCE_EXHAUSTED.code,
					nil,
					nil,
					{ address = address, pendingCount = pendingCount, maxPending = self._maxPendingNonces }
				)
			)
			return
		end

		-- Reserve the next nonce
		local nonce = state.nextNonce
		state.nextNonce += 1
		state.pending[nonce] = true

		self._metrics.totalReserved += 1

		-- Return as hex string
		resolve("0x" .. string.format("%x", nonce))
	end)
end

--- Confirm that a nonce was used successfully (transaction accepted by sequencer).
--- Call this after a successful addInvokeTransaction.
function NonceManager:confirm(address: string, nonceHex: string)
	local state = self._states[address]
	if not state then
		return
	end

	local nonce = tonumber(nonceHex, 16)
	if not nonce then
		nonce = tonumber(nonceHex) or 0
	end

	if state.pending[nonce] then
		state.pending[nonce] = nil
		self._metrics.totalConfirmed += 1
	end
end

--- Reject a nonce (transaction failed or was reverted).
--- If autoResyncOnError is enabled, marks the address as dirty for re-sync on next reserve.
function NonceManager:reject(address: string, nonceHex: string)
	local state = self._states[address]
	if not state then
		return
	end

	local nonce = tonumber(nonceHex, 16)
	if not nonce then
		nonce = tonumber(nonceHex) or 0
	end

	if state.pending[nonce] then
		state.pending[nonce] = nil
		self._metrics.totalRejected += 1
	end

	if self._autoResync then
		state.dirty = true
	end
end

--- Force re-sync with on-chain nonce for an address.
--- Returns a Promise resolving to the fresh on-chain nonce hex string.
--- Clears all local tracking for the address.
function NonceManager:resync(address: string): any
	local Promise = self._provider:_getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local ok, result = pcall(function()
			return self:_fetchOnChainNonce(address)
		end)
		if not ok then
			reject(
				StarknetError.rpc(
					`NonceManager: failed to resync nonce for {address}: {tostring(result)}`,
					ErrorCodes.NONCE_FETCH_ERROR.code
				)
			)
			return
		end

		local onChainNonce = tonumber(result, 16)
		if not onChainNonce then
			onChainNonce = tonumber(result) or 0
		end

		self._states[address] = {
			nextNonce = onChainNonce,
			pending = {},
			initialized = true,
			dirty = false,
		}

		self._metrics.totalResyncs += 1

		resolve(result)
	end)
end

--- Reset local nonce tracking.
--- If address is provided, reset only that address. Otherwise reset all.
function NonceManager:reset(address: string?)
	if address then
		self._states[address] = nil
	else
		self._states = {}
	end
end

--- Get the number of pending (reserved but unconfirmed) nonces for an address.
function NonceManager:getPendingCount(address: string): number
	local state = self._states[address]
	if not state then
		return 0
	end
	return countPending(state)
end

--- Get a snapshot of nonce manager metrics.
function NonceManager:getMetrics(): NonceManagerMetrics
	return {
		totalReserved = self._metrics.totalReserved,
		totalConfirmed = self._metrics.totalConfirmed,
		totalRejected = self._metrics.totalRejected,
		totalResyncs = self._metrics.totalResyncs,
	}
end

--- Check if an address has been initialized (has local nonce tracking).
function NonceManager:isInitialized(address: string): boolean
	local state = self._states[address]
	return state ~= nil and state.initialized
end

--- Check if an address needs re-sync (dirty state).
function NonceManager:isDirty(address: string): boolean
	local state = self._states[address]
	return state ~= nil and state.dirty
end

--- Get the next nonce that would be reserved (without actually reserving it).
--- Returns nil if the address hasn't been initialized.
function NonceManager:peekNextNonce(address: string): string?
	local state = self._states[address]
	if not state or not state.initialized then
		return nil
	end
	return "0x" .. string.format("%x", state.nextNonce)
end

return NonceManager
