--!strict
-- PaymasterBudget: Per-player usage tracking for sponsored transactions
-- Manages virtual "paymaster tokens" that game developers grant as rewards or purchases
-- to control sponsored transaction budgets.
-- Uses in-memory cache with periodic DataStore flush for persistence.
-- "Paymaster tokens" are NOT on-chain — purely game-managed via Roblox DataStoreService.

local StarknetError = require("../errors/StarknetError")
local ErrorCodes = require("../errors/ErrorCodes")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type DataStoreLike = {
	GetAsync: (self: DataStoreLike, key: string) -> any?,
	SetAsync: (self: DataStoreLike, key: string, value: any) -> (),
}

export type BudgetConfig = {
	dataStoreName: string?,
	defaultTokenBalance: number?,
	costPerTransaction: number?,
	costPerGasUnit: number?,
	flushInterval: number?,
	maxDirtyEntries: number?,
	-- Testing injection
	_dataStore: DataStoreLike?,
	_clock: (() -> number)?,
}

export type PlayerData = {
	balance: number,
	totalTxCount: number,
	totalTokensSpent: number,
	lastTxTime: number,
}

export type UsageStats = {
	balance: number,
	totalTxCount: number,
	totalTokensSpent: number,
	lastTxTime: number,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function defaultPlayerData(defaultBalance: number): PlayerData
	return {
		balance = defaultBalance,
		totalTxCount = 0,
		totalTokensSpent = 0,
		lastTxTime = 0,
	}
end

local function clonePlayerData(data: PlayerData): PlayerData
	return {
		balance = data.balance,
		totalTxCount = data.totalTxCount,
		totalTokensSpent = data.totalTokensSpent,
		lastTxTime = data.lastTxTime,
	}
end

local function isValidPlayerData(data: any): boolean
	return type(data) == "table"
		and type(data.balance) == "number"
		and type(data.totalTxCount) == "number"
		and type(data.totalTokensSpent) == "number"
		and type(data.lastTxTime) == "number"
end

--------------------------------------------------------------------------------
-- PaymasterBudget
--------------------------------------------------------------------------------

local PaymasterBudget = {}
local BudgetProto = {}
BudgetProto.__index = BudgetProto

--- Create a new PaymasterBudget with the given configuration.
--- @param config BudgetConfig — budget tracking options
--- @return PaymasterBudget instance
function PaymasterBudget.new(config: BudgetConfig?)
	local cfg = config or {} :: BudgetConfig

	-- Validate costPerTransaction
	if cfg.costPerTransaction ~= nil then
		if type(cfg.costPerTransaction) ~= "number" then
			error(StarknetError.validation("costPerTransaction must be a number", ErrorCodes.INVALID_ARGUMENT.code))
		end
		if cfg.costPerTransaction < 0 then
			error(StarknetError.validation("costPerTransaction must be non-negative", ErrorCodes.INVALID_ARGUMENT.code))
		end
	end

	-- Validate costPerGasUnit
	if cfg.costPerGasUnit ~= nil then
		if type(cfg.costPerGasUnit) ~= "number" then
			error(StarknetError.validation("costPerGasUnit must be a number", ErrorCodes.INVALID_ARGUMENT.code))
		end
		if cfg.costPerGasUnit < 0 then
			error(StarknetError.validation("costPerGasUnit must be non-negative", ErrorCodes.INVALID_ARGUMENT.code))
		end
	end

	-- Validate defaultTokenBalance
	if cfg.defaultTokenBalance ~= nil then
		if type(cfg.defaultTokenBalance) ~= "number" then
			error(StarknetError.validation("defaultTokenBalance must be a number", ErrorCodes.INVALID_ARGUMENT.code))
		end
		if cfg.defaultTokenBalance < 0 then
			error(
				StarknetError.validation("defaultTokenBalance must be non-negative", ErrorCodes.INVALID_ARGUMENT.code)
			)
		end
	end

	-- Validate flushInterval
	if cfg.flushInterval ~= nil then
		if type(cfg.flushInterval) ~= "number" or cfg.flushInterval <= 0 then
			error(StarknetError.validation("flushInterval must be a positive number", ErrorCodes.INVALID_ARGUMENT.code))
		end
	end

	-- Validate maxDirtyEntries
	if cfg.maxDirtyEntries ~= nil then
		if type(cfg.maxDirtyEntries) ~= "number" or cfg.maxDirtyEntries <= 0 then
			error(
				StarknetError.validation("maxDirtyEntries must be a positive number", ErrorCodes.INVALID_ARGUMENT.code)
			)
		end
	end

	local clock = cfg._clock or os.clock

	local self = setmetatable({
		_dataStoreName = cfg.dataStoreName or "StarknetPaymaster",
		_defaultTokenBalance = cfg.defaultTokenBalance or 0,
		_costPerTransaction = cfg.costPerTransaction or 1,
		_costPerGasUnit = cfg.costPerGasUnit,
		_flushInterval = cfg.flushInterval or 30,
		_maxDirtyEntries = cfg.maxDirtyEntries or 20,
		_dataStore = cfg._dataStore,
		_clock = clock,

		-- In-memory cache
		_cache = {} :: { [number]: PlayerData },
		_dirty = {} :: { [number]: boolean },
		_dirtyCount = 0,
		_lastFlushTime = clock(),
		_flushErrors = {} :: { string },
	}, BudgetProto)

	return self
end

--------------------------------------------------------------------------------
-- Private: Data access
--------------------------------------------------------------------------------

--- Get player data from cache, loading from DataStore if needed.
function BudgetProto:_getPlayerData(playerId: number): PlayerData
	local cached = self._cache[playerId]
	if cached then
		return cached
	end

	-- Try loading from DataStore
	if self._dataStore then
		local key = "player_" .. tostring(playerId)
		local ok, result = pcall(function()
			return self._dataStore:GetAsync(key)
		end)

		if ok and result ~= nil and isValidPlayerData(result) then
			local data = clonePlayerData(result)
			self._cache[playerId] = data
			return data
		end

		if not ok then
			-- Log DataStore error but don't crash — use default data
			table.insert(
				self._flushErrors,
				"GetAsync failed for player " .. tostring(playerId) .. ": " .. tostring(result)
			)
		end
	end

	-- Create default player data
	local data = defaultPlayerData(self._defaultTokenBalance)
	self._cache[playerId] = data
	return data
end

--- Mark player data as dirty (needs DataStore flush).
function BudgetProto:_markDirty(playerId: number): ()
	if not self._dirty[playerId] then
		self._dirty[playerId] = true
		self._dirtyCount += 1
	end
	self:_maybeFlush()
end

--- Check if a lazy flush should happen (elapsed time or dirty count threshold).
function BudgetProto:_maybeFlush(): ()
	if self._dirtyCount == 0 then
		return
	end

	-- Flush if dirty count exceeds threshold
	if self._dirtyCount >= self._maxDirtyEntries then
		self:flush()
		return
	end

	-- Flush if interval elapsed
	local now = self._clock()
	if now - self._lastFlushTime >= self._flushInterval then
		self:flush()
	end
end

--- Flush a single player's data to DataStore.
function BudgetProto:_flushPlayer(playerId: number): ()
	if not self._dataStore then
		return
	end

	local data = self._cache[playerId]
	if not data then
		return
	end

	local key = "player_" .. tostring(playerId)
	local ok, err = pcall(function()
		self._dataStore:SetAsync(key, clonePlayerData(data))
	end)

	if not ok then
		table.insert(self._flushErrors, "SetAsync failed for player " .. tostring(playerId) .. ": " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- Public: Balance operations
--------------------------------------------------------------------------------

--- Get the current paymaster token balance for a player.
--- @param playerId number — Roblox player ID
--- @return number — current token balance
function BudgetProto:getBalance(playerId: number): number
	local data = self:_getPlayerData(playerId)
	return data.balance
end

--- Add paymaster tokens to a player's balance (game rewards, purchases, etc.).
--- @param playerId number — Roblox player ID
--- @param amount number — tokens to add (must be positive)
function BudgetProto:grantTokens(playerId: number, amount: number): ()
	if type(amount) ~= "number" or amount ~= amount then -- NaN check
		error(StarknetError.validation("amount must be a valid number", ErrorCodes.INVALID_AMOUNT.code))
	end
	if amount < 0 then
		error(StarknetError.validation("amount must be non-negative", ErrorCodes.INVALID_AMOUNT.code))
	end
	if amount == 0 then
		return
	end

	local data = self:_getPlayerData(playerId)
	data.balance += amount
	self:_markDirty(playerId)
end

--- Remove paymaster tokens from a player's balance.
--- Balance will not go below zero.
--- @param playerId number — Roblox player ID
--- @param amount number — tokens to remove (must be positive)
function BudgetProto:revokeTokens(playerId: number, amount: number): ()
	if type(amount) ~= "number" or amount ~= amount then
		error(StarknetError.validation("amount must be a valid number", ErrorCodes.INVALID_AMOUNT.code))
	end
	if amount < 0 then
		error(StarknetError.validation("amount must be non-negative", ErrorCodes.INVALID_AMOUNT.code))
	end
	if amount == 0 then
		return
	end

	local data = self:_getPlayerData(playerId)
	data.balance = math.max(0, data.balance - amount)
	self:_markDirty(playerId)
end

--------------------------------------------------------------------------------
-- Public: Transaction operations
--------------------------------------------------------------------------------

--- Calculate the token cost for a transaction based on optional gas usage.
--- @param gasUsed number? — actual gas units consumed (optional)
--- @return number — computed token cost
function BudgetProto:calculateCost(gasUsed: number?): number
	local cost = self._costPerTransaction
	if gasUsed and self._costPerGasUnit then
		cost += gasUsed * self._costPerGasUnit
	end
	return cost
end

--- Check if a player can afford a sponsored transaction.
--- @param playerId number — Roblox player ID
--- @param txCost number? — override cost (defaults to costPerTransaction)
--- @return boolean — true if player has sufficient tokens
function BudgetProto:canAfford(playerId: number, txCost: number?): boolean
	local cost = txCost or self._costPerTransaction
	local data = self:_getPlayerData(playerId)
	return data.balance >= cost
end

--- Deduct tokens for a sponsored transaction.
--- Call this BEFORE submitting to the paymaster. If submission fails, call refundTransaction().
--- @param playerId number — Roblox player ID
--- @param txCost number? — override cost (defaults to costPerTransaction)
--- @return number — the actual cost deducted
function BudgetProto:consumeTransaction(playerId: number, txCost: number?): number
	local cost = txCost or self._costPerTransaction

	if cost < 0 then
		error(StarknetError.validation("transaction cost must be non-negative", ErrorCodes.INVALID_AMOUNT.code))
	end

	local data = self:_getPlayerData(playerId)

	if data.balance < cost then
		error(
			StarknetError.new(
				"Insufficient paymaster tokens: need "
					.. tostring(cost)
					.. " but player "
					.. tostring(playerId)
					.. " has "
					.. tostring(data.balance),
				ErrorCodes.INSUFFICIENT_BUDGET.code
			)
		)
	end

	local now = self._clock()
	data.balance -= cost
	data.totalTxCount += 1
	data.totalTokensSpent += cost
	data.lastTxTime = now
	self:_markDirty(playerId)

	return cost
end

--- Refund tokens after a failed paymaster submission.
--- Reverses a consumeTransaction: adds cost back to balance and decrements stats.
--- @param playerId number — Roblox player ID
--- @param txCost number? — amount to refund (defaults to costPerTransaction)
function BudgetProto:refundTransaction(playerId: number, txCost: number?): ()
	local cost = txCost or self._costPerTransaction

	if cost < 0 then
		error(StarknetError.validation("refund amount must be non-negative", ErrorCodes.INVALID_AMOUNT.code))
	end

	local data = self:_getPlayerData(playerId)
	data.balance += cost
	data.totalTxCount = math.max(0, data.totalTxCount - 1)
	data.totalTokensSpent = math.max(0, data.totalTokensSpent - cost)
	self:_markDirty(playerId)
end

--------------------------------------------------------------------------------
-- Public: Stats
--------------------------------------------------------------------------------

--- Get usage statistics for a player.
--- @param playerId number — Roblox player ID
--- @return UsageStats — { balance, totalTxCount, totalTokensSpent, lastTxTime }
function BudgetProto:getUsageStats(playerId: number): UsageStats
	local data = self:_getPlayerData(playerId)
	return {
		balance = data.balance,
		totalTxCount = data.totalTxCount,
		totalTokensSpent = data.totalTokensSpent,
		lastTxTime = data.lastTxTime,
	}
end

--------------------------------------------------------------------------------
-- Public: Cache management
--------------------------------------------------------------------------------

--- Flush all dirty player data to DataStore.
function BudgetProto:flush(): ()
	if not self._dataStore then
		-- No DataStore — just clear dirty flags
		self._dirty = {}
		self._dirtyCount = 0
		self._lastFlushTime = self._clock()
		return
	end

	for playerId, _ in self._dirty do
		self:_flushPlayer(playerId)
	end
	self._dirty = {}
	self._dirtyCount = 0
	self._lastFlushTime = self._clock()
end

--- Flush a single player's data to DataStore.
--- @param playerId number — Roblox player ID
function BudgetProto:flushPlayer(playerId: number): ()
	self:_flushPlayer(playerId)
	self._dirty[playerId] = nil
	-- Recount dirty entries
	local count = 0
	for _ in self._dirty do
		count += 1
	end
	self._dirtyCount = count
end

--- Explicitly load a player's data from DataStore into cache.
--- Useful for pre-loading when a player joins.
--- @param playerId number — Roblox player ID
function BudgetProto:loadPlayer(playerId: number): ()
	-- Force load from DataStore (skip cache)
	if self._dataStore then
		local key = "player_" .. tostring(playerId)
		local ok, result = pcall(function()
			return self._dataStore:GetAsync(key)
		end)

		if ok and result ~= nil and isValidPlayerData(result) then
			self._cache[playerId] = clonePlayerData(result)
			return
		end

		if not ok then
			table.insert(
				self._flushErrors,
				"GetAsync failed for player " .. tostring(playerId) .. ": " .. tostring(result)
			)
		end
	end

	-- No DataStore or no data found — use default if not already cached
	if not self._cache[playerId] then
		self._cache[playerId] = defaultPlayerData(self._defaultTokenBalance)
	end
end

--- Remove a player's data from the in-memory cache.
--- Flushes to DataStore first if dirty.
--- @param playerId number — Roblox player ID
function BudgetProto:unloadPlayer(playerId: number): ()
	if self._dirty[playerId] then
		self:_flushPlayer(playerId)
		self._dirty[playerId] = nil
		self._dirtyCount = math.max(0, self._dirtyCount - 1)
	end
	self._cache[playerId] = nil
end

--- Get the list of DataStore errors that occurred during flush operations.
--- Useful for debugging and monitoring.
--- @return { string } — array of error messages
function BudgetProto:getFlushErrors(): { string }
	return self._flushErrors
end

--- Clear recorded flush errors.
function BudgetProto:clearFlushErrors(): ()
	self._flushErrors = {}
end

--- Check if a player's data is currently cached in memory.
--- @param playerId number — Roblox player ID
--- @return boolean
function BudgetProto:isCached(playerId: number): boolean
	return self._cache[playerId] ~= nil
end

--- Get the number of dirty entries waiting to be flushed.
--- @return number
function BudgetProto:getDirtyCount(): number
	return self._dirtyCount
end

return PaymasterBudget
