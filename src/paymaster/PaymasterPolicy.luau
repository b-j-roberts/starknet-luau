--!strict
-- PaymasterPolicy: Pure validation module for paymaster usage rules
-- Defines allowed contracts, methods, players, fee limits, and rate limits
-- Prevents abuse by restricting which calls can use sponsored gas
-- No persistence — all tracking is in-memory and composable with PaymasterBudget

local BigInt = require("../crypto/BigInt")
local Keccak = require("../crypto/Keccak")
local StarkField = require("../crypto/StarkField")
local HexUtils = require("../shared/HexUtils")
local Interfaces = require("../shared/interfaces")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes
local Defaults = require("../shared/TestableDefaults")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type PolicyConfig = {
	allowedContracts: { { address: string } }?,
	allowedMethods: { { contract: string, selector: string } }?,
	allowedPlayers: { { playerId: number } }?,
	maxFeePerTx: (string | buffer)?,
	maxTxPerPlayer: number?,
	timeWindow: number?,
	-- Testing injection
	_clock: (() -> number)?,
}

export type ValidationResult = {
	allowed: boolean,
	reason: string?,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local normalizeHex = HexUtils.normalizeHex

--- Normalize a selector: if it starts with "0x", normalize the hex; otherwise treat as
--- a function name and compute the Starknet selector via Keccak.
local function normalizeSelector(selector: string): string
	if string.sub(selector, 1, 2) == "0x" or string.sub(selector, 1, 2) == "0X" then
		return normalizeHex(selector)
	end
	-- Function name — compute selector hash
	return StarkField.toHex(Keccak.getSelectorFromName(selector))
end

--------------------------------------------------------------------------------
-- PaymasterPolicy
--------------------------------------------------------------------------------

--- Public interface for PaymasterPolicy instances.
export type PaymasterPolicy = {
	validate: (self: PaymasterPolicy, playerId: number, calls: { Interfaces.Call }) -> ValidationResult,
	validateFee: (self: PaymasterPolicy, playerId: number, feeAmount: string | buffer) -> ValidationResult,
	recordUsage: (self: PaymasterPolicy, playerId: number) -> (),
	resetUsage: (self: PaymasterPolicy, playerId: number?) -> (),
	getUsageCount: (self: PaymasterPolicy, playerId: number) -> number,
}

local PaymasterPolicyModule = {}
local PolicyProto = {}
PolicyProto.__index = PolicyProto

--- Create a new PaymasterPolicy with the given configuration.
--- @param config PolicyConfig — usage rules for the paymaster
--- @return PaymasterPolicy instance
function PaymasterPolicyModule.new(config: PolicyConfig): PaymasterPolicy
	if config == nil then
		error(StarknetError.validation("PaymasterPolicy config is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	-- Build allowed contracts lookup
	local allowedContracts: { [string]: boolean } = {}
	local contractsRestricted = false
	if config.allowedContracts and #config.allowedContracts > 0 then
		contractsRestricted = true
		for _, entry in config.allowedContracts do
			if not entry.address or entry.address == "" then
				error(
					StarknetError.validation(
						"allowedContracts entry must have an address",
						ErrorCodes.INVALID_ARGUMENT.code
					)
				)
			end
			allowedContracts[normalizeHex(entry.address)] = true
		end
	end

	-- Build allowed methods lookup (key = "normalizedAddr:selector")
	local allowedMethods: { [string]: boolean } = {}
	local methodsRestricted = false
	if config.allowedMethods and #config.allowedMethods > 0 then
		methodsRestricted = true
		for _, entry in config.allowedMethods do
			if not entry.contract or entry.contract == "" then
				error(
					StarknetError.validation(
						"allowedMethods entry must have a contract address",
						ErrorCodes.INVALID_ARGUMENT.code
					)
				)
			end
			if not entry.selector or entry.selector == "" then
				error(
					StarknetError.validation(
						"allowedMethods entry must have a selector",
						ErrorCodes.INVALID_ARGUMENT.code
					)
				)
			end
			local key = normalizeHex(entry.contract) .. ":" .. normalizeSelector(entry.selector)
			allowedMethods[key] = true
		end
	end

	-- Build allowed players lookup
	local allowedPlayers: { [number]: boolean } = {}
	local playersRestricted = false
	if config.allowedPlayers and #config.allowedPlayers > 0 then
		playersRestricted = true
		for _, entry in config.allowedPlayers do
			if not entry.playerId then
				error(
					StarknetError.validation(
						"allowedPlayers entry must have a playerId",
						ErrorCodes.INVALID_ARGUMENT.code
					)
				)
			end
			allowedPlayers[entry.playerId] = true
		end
	end

	-- Parse maxFeePerTx into BigInt buffer
	local maxFeePerTx: buffer? = nil
	if config.maxFeePerTx then
		if type(config.maxFeePerTx) == "string" then
			maxFeePerTx = BigInt.fromHex(config.maxFeePerTx :: string)
		elseif type(config.maxFeePerTx) == "buffer" then
			maxFeePerTx = config.maxFeePerTx :: buffer
		else
			error(
				StarknetError.validation(
					"maxFeePerTx must be a hex string or BigInt buffer",
					ErrorCodes.INVALID_ARGUMENT.code
				)
			)
		end
	end

	-- Validate rate limit config
	if config.maxTxPerPlayer and config.maxTxPerPlayer <= 0 then
		error(StarknetError.validation("maxTxPerPlayer must be a positive number", ErrorCodes.INVALID_ARGUMENT.code))
	end
	if config.timeWindow and config.timeWindow <= 0 then
		error(StarknetError.validation("timeWindow must be a positive number", ErrorCodes.INVALID_ARGUMENT.code))
	end
	if config.maxTxPerPlayer and not config.timeWindow then
		error(
			StarknetError.validation(
				"timeWindow is required when maxTxPerPlayer is set",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local self = setmetatable({
		_allowedContracts = allowedContracts,
		_allowedMethods = allowedMethods,
		_allowedPlayers = allowedPlayers,
		_contractsRestricted = contractsRestricted,
		_methodsRestricted = methodsRestricted,
		_playersRestricted = playersRestricted,
		_maxFeePerTx = maxFeePerTx,
		_maxTxPerPlayer = config.maxTxPerPlayer,
		_timeWindow = config.timeWindow,
		_playerRecords = {} :: { [number]: { timestamps: { number } } },
		_clock = config._clock or Defaults.clock,
	}, PolicyProto)

	return self :: any
end

--- Check player whitelist. Returns a rejection result if blocked, or nil if allowed.
function PolicyProto:_checkPlayerWhitelist(playerId: number): ValidationResult?
	if self._playersRestricted and not self._allowedPlayers[playerId] then
		return {
			allowed = false,
			reason = "Player " .. tostring(playerId) .. " is not in the allowed players list",
		}
	end
	return nil
end

--- Check if a set of calls is allowed for a given player.
--- Validates player whitelist, contract whitelist, method whitelist, and rate limits.
--- Does NOT record usage — call recordUsage() after a successful transaction.
--- @param playerId number — Roblox player ID
--- @param calls table — array of Call objects ({ contractAddress, entrypoint, calldata })
--- @return ValidationResult — { allowed: boolean, reason: string? }
function PolicyProto:validate(playerId: number, calls: { Interfaces.Call }): ValidationResult
	local playerCheck = self:_checkPlayerWhitelist(playerId)
	if playerCheck then
		return playerCheck
	end

	-- Require at least one call
	if not calls or #calls == 0 then
		return { allowed = false, reason = "At least one call is required" }
	end

	for i, call in calls do
		if not call.contractAddress or call.contractAddress == "" then
			return { allowed = false, reason = "Call " .. tostring(i) .. " is missing contractAddress" }
		end

		local normalizedAddr = normalizeHex(call.contractAddress)

		-- Check contract whitelist
		if self._contractsRestricted then
			if not self._allowedContracts[normalizedAddr] then
				return {
					allowed = false,
					reason = "Contract " .. call.contractAddress .. " is not in the allowed contracts list",
				}
			end
		end

		-- Check method whitelist
		if self._methodsRestricted then
			if not call.entrypoint or call.entrypoint == "" then
				return { allowed = false, reason = "Call " .. tostring(i) .. " is missing entrypoint" }
			end
			local normalizedEntrypoint = normalizeSelector(call.entrypoint)
			local key = normalizedAddr .. ":" .. normalizedEntrypoint
			if not self._allowedMethods[key] then
				return {
					allowed = false,
					reason = "Method "
						.. call.entrypoint
						.. " on contract "
						.. call.contractAddress
						.. " is not allowed",
				}
			end
		end
	end

	-- Check rate limit
	if self._maxTxPerPlayer and self._timeWindow then
		local now = self._clock()
		local record = self._playerRecords[playerId]
		if record then
			local cutoff = now - self._timeWindow
			local count = 0
			for _, ts in record.timestamps do
				if ts > cutoff then
					count += 1
				end
			end
			if count >= self._maxTxPerPlayer then
				return {
					allowed = false,
					reason = "Player "
						.. tostring(playerId)
						.. " has exceeded "
						.. tostring(self._maxTxPerPlayer)
						.. " transactions in the current time window",
				}
			end
		end
	end

	return { allowed = true }
end

--- Check if a fee amount is within the allowed limit for a given player.
--- @param playerId number — Roblox player ID
--- @param feeAmount string|buffer — fee amount as hex string or BigInt buffer
--- @return ValidationResult — { allowed: boolean, reason: string? }
function PolicyProto:validateFee(playerId: number, feeAmount: string | buffer): ValidationResult
	local playerCheck = self:_checkPlayerWhitelist(playerId)
	if playerCheck then
		return playerCheck
	end

	-- Check fee against maxFeePerTx
	if self._maxFeePerTx then
		local fee: buffer
		if type(feeAmount) == "string" then
			fee = BigInt.fromHex(feeAmount :: string)
		else
			fee = feeAmount :: buffer
		end

		if BigInt.cmp(fee, self._maxFeePerTx) > 0 then
			return {
				allowed = false,
				reason = "Fee amount exceeds maximum allowed fee per transaction",
			}
		end
	end

	return { allowed = true }
end

--- Record a transaction for rate limiting purposes.
--- Call this after a successful sponsored transaction.
--- Prunes expired timestamps to prevent unbounded growth.
--- @param playerId number — Roblox player ID
function PolicyProto:recordUsage(playerId: number): ()
	if not self._maxTxPerPlayer or not self._timeWindow then
		return
	end

	local now = self._clock()
	local record = self._playerRecords[playerId]
	if not record then
		record = { timestamps = {} }
		self._playerRecords[playerId] = record
	end
	table.insert(record.timestamps, now)

	-- Prune expired timestamps to prevent unbounded growth
	local cutoff = now - self._timeWindow
	local pruned = {}
	for _, ts in record.timestamps do
		if ts > cutoff then
			table.insert(pruned, ts)
		end
	end
	record.timestamps = pruned
end

--- Reset usage records for a specific player or all players.
--- @param playerId number? — if nil, resets all players
function PolicyProto:resetUsage(playerId: number?): ()
	if playerId then
		self._playerRecords[playerId] = nil
	else
		self._playerRecords = {}
	end
end

--- Get the current usage count for a player within the active time window.
--- @param playerId number — Roblox player ID
--- @return number — count of transactions in current window
function PolicyProto:getUsageCount(playerId: number): number
	if not self._maxTxPerPlayer or not self._timeWindow then
		return 0
	end

	local record = self._playerRecords[playerId]
	if not record then
		return 0
	end

	local now = self._clock()
	local cutoff = now - self._timeWindow
	local count = 0
	for _, ts in record.timestamps do
		if ts > cutoff then
			count += 1
		end
	end
	return count
end

return PaymasterPolicyModule
