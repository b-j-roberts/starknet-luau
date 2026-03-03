--!strict
local PaymasterBudget = require("../../src/paymaster/PaymasterBudget")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local passed = 0
local failed = 0
local errors: { string } = {}

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		local msg = tostring(err)
		table.insert(errors, name .. ": " .. msg)
		print("  ✗ " .. name .. " — " .. msg)
	end
end

local function describe(name: string, fn: () -> ())
	print("\n" .. name)
	fn()
end

local function expect(val: any)
	return {
		toBe = function(expected: any)
			if val ~= expected then
				error("Expected " .. tostring(expected) .. " but got " .. tostring(val), 2)
			end
		end,
		toEqual = function(expected: any)
			if val ~= expected then
				error("Expected " .. tostring(expected) .. " but got " .. tostring(val), 2)
			end
		end,
		toBeTruthy = function()
			if not val then
				error("Expected truthy but got " .. tostring(val), 2)
			end
		end,
		toBeFalsy = function()
			if val then
				error("Expected falsy but got " .. tostring(val), 2)
			end
		end,
		toBeNil = function()
			if val ~= nil then
				error("Expected nil but got " .. tostring(val), 2)
			end
		end,
		toContain = function(substring: string)
			if type(val) ~= "string" or not string.find(val, substring, 1, true) then
				error("Expected string containing '" .. substring .. "' but got " .. tostring(val), 2)
			end
		end,
		toBeGreaterThan = function(expected: number)
			if type(val) ~= "number" or val <= expected then
				error("Expected > " .. tostring(expected) .. " but got " .. tostring(val), 2)
			end
		end,
		toBeGreaterThanOrEqual = function(expected: number)
			if type(val) ~= "number" or val < expected then
				error("Expected >= " .. tostring(expected) .. " but got " .. tostring(val), 2)
			end
		end,
	}
end

local function expectError(fn: () -> (), pattern: string?)
	local ok, err = pcall(fn)
	if ok then
		error("Expected error but none was thrown", 2)
	end
	if pattern then
		local msg = tostring(err)
		if not string.find(msg, pattern, 1, true) then
			error("Expected error containing '" .. pattern .. "' but got: " .. msg, 2)
		end
	end
end

--- Create a mock clock with controllable time.
local function makeClock(startTime: number): (() -> number, (number) -> ())
	local time = startTime
	return function(): number
		return time
	end, function(newTime: number)
		time = newTime
	end
end

--- Create a mock DataStore for testing.
local function createMockDataStore(): (any, { [string]: any })
	local data: { [string]: any } = {}
	local store = {}

	function store:GetAsync(key: string): any?
		return data[key]
	end

	function store:SetAsync(key: string, value: any): ()
		data[key] = value
	end

	return store, data
end

--- Create a mock DataStore that errors on operations.
local function createFailingDataStore(failGet: boolean?, failSet: boolean?): any
	local store = {}

	function store:GetAsync(_key: string): any?
		if failGet then
			error("DataStore GetAsync failed: service unavailable")
		end
		return nil
	end

	function store:SetAsync(_key: string, _value: any): ()
		if failSet then
			error("DataStore SetAsync failed: service unavailable")
		end
	end

	return store
end

local PLAYER_1 = 12345
local PLAYER_2 = 67890
local PLAYER_3 = 11111

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("PaymasterBudget.new", function()
	test("creates budget with default config", function()
		local budget = PaymasterBudget.new({})
		expect(budget).toBeTruthy()
	end)

	test("creates budget with nil config", function()
		local budget = PaymasterBudget.new()
		expect(budget).toBeTruthy()
	end)

	test("creates budget with all options", function()
		local mockDS, _ = createMockDataStore()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			dataStoreName = "MyGameBudget",
			defaultTokenBalance = 10,
			costPerTransaction = 2,
			costPerGasUnit = 0.001,
			flushInterval = 60,
			maxDirtyEntries = 50,
			_dataStore = mockDS,
			_clock = clock,
		})
		expect(budget).toBeTruthy()
	end)

	test("rejects negative costPerTransaction", function()
		expectError(function()
			PaymasterBudget.new({ costPerTransaction = -1 })
		end, "costPerTransaction must be non-negative")
	end)

	test("rejects negative costPerGasUnit", function()
		expectError(function()
			PaymasterBudget.new({ costPerGasUnit = -0.5 })
		end, "costPerGasUnit must be non-negative")
	end)

	test("rejects negative defaultTokenBalance", function()
		expectError(function()
			PaymasterBudget.new({ defaultTokenBalance = -10 })
		end, "defaultTokenBalance must be non-negative")
	end)

	test("rejects non-positive flushInterval", function()
		expectError(function()
			PaymasterBudget.new({ flushInterval = 0 })
		end, "flushInterval must be a positive number")
	end)

	test("rejects negative flushInterval", function()
		expectError(function()
			PaymasterBudget.new({ flushInterval = -5 })
		end, "flushInterval must be a positive number")
	end)

	test("rejects non-positive maxDirtyEntries", function()
		expectError(function()
			PaymasterBudget.new({ maxDirtyEntries = 0 })
		end, "maxDirtyEntries must be a positive number")
	end)

	test("allows costPerTransaction of 0", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 0 })
		expect(budget).toBeTruthy()
	end)

	test("allows costPerGasUnit of 0", function()
		local budget = PaymasterBudget.new({ costPerGasUnit = 0 })
		expect(budget).toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getBalance
--------------------------------------------------------------------------------

describe("PaymasterBudget:getBalance", function()
	test("returns 0 for new player with default config", function()
		local budget = PaymasterBudget.new({})
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)

	test("returns defaultTokenBalance for new player", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 100 })
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)

	test("returns balance after granting tokens", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 50)
		expect(budget:getBalance(PLAYER_1)).toBe(50)
	end)

	test("returns balance from DataStore on first access", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = {
			balance = 75,
			totalTxCount = 5,
			totalTokensSpent = 25,
			lastTxTime = 999,
		}
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		expect(budget:getBalance(PLAYER_1)).toBe(75)
	end)

	test("uses cache after first DataStore load", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = {
			balance = 75,
			totalTxCount = 5,
			totalTokensSpent = 25,
			lastTxTime = 999,
		}
		local budget = PaymasterBudget.new({ _dataStore = mockDS })

		-- First access loads from DataStore
		expect(budget:getBalance(PLAYER_1)).toBe(75)

		-- Modify DataStore directly — cache should still return 75
		data["player_12345"] = {
			balance = 200,
			totalTxCount = 10,
			totalTokensSpent = 50,
			lastTxTime = 1500,
		}
		expect(budget:getBalance(PLAYER_1)).toBe(75)
	end)

	test("tracks players independently", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		budget:grantTokens(PLAYER_2, 200)
		expect(budget:getBalance(PLAYER_1)).toBe(100)
		expect(budget:getBalance(PLAYER_2)).toBe(200)
		expect(budget:getBalance(PLAYER_3)).toBe(0)
	end)

	test("gracefully handles DataStore GetAsync failure", function()
		local failingDS = createFailingDataStore(true, false)
		local budget = PaymasterBudget.new({
			_dataStore = failingDS,
			defaultTokenBalance = 5,
		})
		-- Should fall back to default balance instead of crashing
		expect(budget:getBalance(PLAYER_1)).toBe(5)
		-- Should have recorded the error
		local flushErrors = budget:getFlushErrors()
		expect(#flushErrors).toBeGreaterThan(0)
	end)

	test("ignores invalid DataStore data", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = "not a table" -- invalid data
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			defaultTokenBalance = 10,
		})
		-- Should use default balance since stored data is invalid
		expect(budget:getBalance(PLAYER_1)).toBe(10)
	end)

	test("ignores DataStore data with missing fields", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = { balance = 50 } -- missing other fields
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			defaultTokenBalance = 10,
		})
		-- Invalid shape — use default
		expect(budget:getBalance(PLAYER_1)).toBe(10)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: grantTokens
--------------------------------------------------------------------------------

describe("PaymasterBudget:grantTokens", function()
	test("adds tokens to player balance", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)

	test("accumulates multiple grants", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 50)
		budget:grantTokens(PLAYER_1, 30)
		budget:grantTokens(PLAYER_1, 20)
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)

	test("adds to existing balance", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 10 })
		budget:grantTokens(PLAYER_1, 25)
		expect(budget:getBalance(PLAYER_1)).toBe(35)
	end)

	test("rejects negative amount", function()
		local budget = PaymasterBudget.new({})
		expectError(function()
			budget:grantTokens(PLAYER_1, -10)
		end, "amount must be non-negative")
	end)

	test("no-op for zero amount", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 10 })
		budget:grantTokens(PLAYER_1, 0)
		expect(budget:getBalance(PLAYER_1)).toBe(10)
		expect(budget:getDirtyCount()).toBe(0) -- should not mark dirty
	end)

	test("handles large amounts", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 1000000)
		expect(budget:getBalance(PLAYER_1)).toBe(1000000)
	end)

	test("handles fractional amounts", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 0.5)
		budget:grantTokens(PLAYER_1, 0.3)
		-- Floating point: 0.5 + 0.3 = 0.8
		local bal = budget:getBalance(PLAYER_1)
		expect(bal > 0.79 and bal < 0.81).toBe(true)
	end)

	test("marks player data as dirty", function()
		local budget = PaymasterBudget.new({})
		expect(budget:getDirtyCount()).toBe(0)
		budget:grantTokens(PLAYER_1, 10)
		expect(budget:getDirtyCount()).toBe(1)
	end)

	test("grants to different players independently", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		budget:grantTokens(PLAYER_2, 200)
		expect(budget:getBalance(PLAYER_1)).toBe(100)
		expect(budget:getBalance(PLAYER_2)).toBe(200)
		expect(budget:getDirtyCount()).toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: revokeTokens
--------------------------------------------------------------------------------

describe("PaymasterBudget:revokeTokens", function()
	test("removes tokens from player balance", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		budget:revokeTokens(PLAYER_1, 30)
		expect(budget:getBalance(PLAYER_1)).toBe(70)
	end)

	test("clamps balance to zero (does not go negative)", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 10)
		budget:revokeTokens(PLAYER_1, 50)
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)

	test("revoke from default balance clamps to zero", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 5 })
		budget:revokeTokens(PLAYER_1, 10)
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)

	test("rejects negative amount", function()
		local budget = PaymasterBudget.new({})
		expectError(function()
			budget:revokeTokens(PLAYER_1, -5)
		end, "amount must be non-negative")
	end)

	test("no-op for zero amount", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 10 })
		budget:revokeTokens(PLAYER_1, 0)
		expect(budget:getBalance(PLAYER_1)).toBe(10)
	end)

	test("full revoke leaves balance at zero", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		budget:revokeTokens(PLAYER_1, 100)
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: canAfford
--------------------------------------------------------------------------------

describe("PaymasterBudget:canAfford", function()
	test("returns false for new player with 0 balance", function()
		local budget = PaymasterBudget.new({})
		expect(budget:canAfford(PLAYER_1)).toBe(false)
	end)

	test("returns true when balance >= default cost", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 5 })
		budget:grantTokens(PLAYER_1, 10)
		expect(budget:canAfford(PLAYER_1)).toBe(true)
	end)

	test("returns true when balance exactly equals cost", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 10)
		expect(budget:canAfford(PLAYER_1)).toBe(true)
	end)

	test("returns false when balance < default cost", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 5)
		expect(budget:canAfford(PLAYER_1)).toBe(false)
	end)

	test("uses custom txCost override", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 1 })
		budget:grantTokens(PLAYER_1, 5)
		expect(budget:canAfford(PLAYER_1, 5)).toBe(true)
		expect(budget:canAfford(PLAYER_1, 6)).toBe(false)
	end)

	test("returns true with zero-cost transactions", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 0 })
		expect(budget:canAfford(PLAYER_1)).toBe(true)
	end)

	test("works with defaultTokenBalance", function()
		local budget = PaymasterBudget.new({
			defaultTokenBalance = 50,
			costPerTransaction = 10,
		})
		expect(budget:canAfford(PLAYER_1)).toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: calculateCost
--------------------------------------------------------------------------------

describe("PaymasterBudget:calculateCost", function()
	test("returns costPerTransaction when no gas", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 5 })
		expect(budget:calculateCost()).toBe(5)
	end)

	test("returns costPerTransaction when gas provided but no costPerGasUnit", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 5 })
		expect(budget:calculateCost(1000)).toBe(5)
	end)

	test("adds gas cost when costPerGasUnit is set", function()
		local budget = PaymasterBudget.new({
			costPerTransaction = 2,
			costPerGasUnit = 0.01,
		})
		-- 2 + (1000 * 0.01) = 2 + 10 = 12
		expect(budget:calculateCost(1000)).toBe(12)
	end)

	test("returns base cost when gas is nil and costPerGasUnit set", function()
		local budget = PaymasterBudget.new({
			costPerTransaction = 3,
			costPerGasUnit = 0.5,
		})
		expect(budget:calculateCost()).toBe(3)
	end)

	test("handles zero gas used", function()
		local budget = PaymasterBudget.new({
			costPerTransaction = 5,
			costPerGasUnit = 0.01,
		})
		expect(budget:calculateCost(0)).toBe(5)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: consumeTransaction
--------------------------------------------------------------------------------

describe("PaymasterBudget:consumeTransaction", function()
	test("deducts default costPerTransaction", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 5 })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(95)
	end)

	test("deducts custom txCost", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 1 })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1, 25)
		expect(budget:getBalance(PLAYER_1)).toBe(75)
	end)

	test("returns the actual cost deducted", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 7 })
		budget:grantTokens(PLAYER_1, 100)
		local cost = budget:consumeTransaction(PLAYER_1)
		expect(cost).toBe(7)
	end)

	test("returns custom txCost when provided", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 1 })
		budget:grantTokens(PLAYER_1, 100)
		local cost = budget:consumeTransaction(PLAYER_1, 15)
		expect(cost).toBe(15)
	end)

	test("errors when insufficient balance", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 5)
		expectError(function()
			budget:consumeTransaction(PLAYER_1)
		end, "Insufficient paymaster tokens")
	end)

	test("error message includes cost and balance", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 3)
		expectError(function()
			budget:consumeTransaction(PLAYER_1)
		end, "need 10")
	end)

	test("error message includes player ID", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		expectError(function()
			budget:consumeTransaction(PLAYER_1)
		end, tostring(PLAYER_1))
	end)

	test("allows exact balance consumption", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 50 })
		budget:grantTokens(PLAYER_1, 50)
		budget:consumeTransaction(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)

	test("supports multiple consecutive transactions", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(70)
	end)

	test("updates totalTxCount", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 1, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1)
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(3)
	end)

	test("updates totalTokensSpent", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 5, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1, 10)
		-- 5 + 10 = 15
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTokensSpent).toBe(15)
	end)

	test("updates lastTxTime", function()
		local clock, setClock = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 1, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		local stats1 = budget:getUsageStats(PLAYER_1)
		expect(stats1.lastTxTime).toBe(1000)

		setClock(2000)
		budget:consumeTransaction(PLAYER_1)
		local stats2 = budget:getUsageStats(PLAYER_1)
		expect(stats2.lastTxTime).toBe(2000)
	end)

	test("rejects negative txCost", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		expectError(function()
			budget:consumeTransaction(PLAYER_1, -5)
		end, "transaction cost must be non-negative")
	end)

	test("allows zero-cost transaction", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 0 })
		local cost = budget:consumeTransaction(PLAYER_1)
		expect(cost).toBe(0)
		expect(budget:getBalance(PLAYER_1)).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: refundTransaction
--------------------------------------------------------------------------------

describe("PaymasterBudget:refundTransaction", function()
	test("adds cost back to balance", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 10 })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1) -- 100 - 10 = 90
		budget:refundTransaction(PLAYER_1) -- 90 + 10 = 100
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)

	test("refunds custom txCost", function()
		local budget = PaymasterBudget.new({ costPerTransaction = 1 })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1, 25) -- 100 - 25 = 75
		budget:refundTransaction(PLAYER_1, 25) -- 75 + 25 = 100
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)

	test("decrements totalTxCount", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 1, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_1)
		budget:refundTransaction(PLAYER_1)
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(1)
	end)

	test("decrements totalTokensSpent", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 5, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:consumeTransaction(PLAYER_1) -- spent 5
		budget:refundTransaction(PLAYER_1) -- refund 5
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTokensSpent).toBe(0)
	end)

	test("totalTxCount does not go below 0", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 1, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:refundTransaction(PLAYER_1) -- refund without prior consume
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(0)
	end)

	test("totalTokensSpent does not go below 0", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 10, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)
		budget:refundTransaction(PLAYER_1) -- refund without prior consume
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTokensSpent).toBe(0)
	end)

	test("rejects negative refund amount", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		expectError(function()
			budget:refundTransaction(PLAYER_1, -5)
		end, "refund amount must be non-negative")
	end)

	test("atomic consume-then-refund restores original state", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 15, _clock = clock })
		budget:grantTokens(PLAYER_1, 100)

		-- Consume
		local cost = budget:consumeTransaction(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(85)

		-- Simulate paymaster failure → refund
		budget:refundTransaction(PLAYER_1, cost)
		expect(budget:getBalance(PLAYER_1)).toBe(100)

		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(0)
		expect(stats.totalTokensSpent).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getUsageStats
--------------------------------------------------------------------------------

describe("PaymasterBudget:getUsageStats", function()
	test("returns default stats for new player", function()
		local budget = PaymasterBudget.new({})
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.balance).toBe(0)
		expect(stats.totalTxCount).toBe(0)
		expect(stats.totalTokensSpent).toBe(0)
		expect(stats.lastTxTime).toBe(0)
	end)

	test("returns stats with defaultTokenBalance", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 50 })
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.balance).toBe(50)
		expect(stats.totalTxCount).toBe(0)
	end)

	test("reflects grant and consume operations", function()
		local clock, setClock = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 5,
			_clock = clock,
		})

		budget:grantTokens(PLAYER_1, 100)

		setClock(1500)
		budget:consumeTransaction(PLAYER_1) -- -5
		setClock(2000)
		budget:consumeTransaction(PLAYER_1) -- -5
		setClock(2500)
		budget:consumeTransaction(PLAYER_1, 10) -- -10

		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.balance).toBe(80) -- 100 - 5 - 5 - 10
		expect(stats.totalTxCount).toBe(3)
		expect(stats.totalTokensSpent).toBe(20) -- 5 + 5 + 10
		expect(stats.lastTxTime).toBe(2500)
	end)

	test("returns independent stats per player", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({ costPerTransaction = 1, _clock = clock })
		budget:grantTokens(PLAYER_1, 50)
		budget:grantTokens(PLAYER_2, 100)
		budget:consumeTransaction(PLAYER_1)
		budget:consumeTransaction(PLAYER_2)
		budget:consumeTransaction(PLAYER_2)

		local stats1 = budget:getUsageStats(PLAYER_1)
		local stats2 = budget:getUsageStats(PLAYER_2)

		expect(stats1.balance).toBe(49)
		expect(stats1.totalTxCount).toBe(1)
		expect(stats2.balance).toBe(98)
		expect(stats2.totalTxCount).toBe(2)
	end)

	test("stats from DataStore are preserved", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = {
			balance = 75,
			totalTxCount = 10,
			totalTokensSpent = 25,
			lastTxTime = 999,
		}
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.balance).toBe(75)
		expect(stats.totalTxCount).toBe(10)
		expect(stats.totalTokensSpent).toBe(25)
		expect(stats.lastTxTime).toBe(999)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: DataStore flush
--------------------------------------------------------------------------------

describe("PaymasterBudget:flush", function()
	test("writes dirty entries to DataStore", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		budget:grantTokens(PLAYER_1, 100)
		budget:grantTokens(PLAYER_2, 200)

		budget:flush()

		-- Verify data was written
		local p1Data = data["player_12345"]
		expect(p1Data).toBeTruthy()
		expect(p1Data.balance).toBe(100)

		local p2Data = data["player_67890"]
		expect(p2Data).toBeTruthy()
		expect(p2Data.balance).toBe(200)
	end)

	test("clears dirty count after flush", function()
		local mockDS, _ = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		budget:grantTokens(PLAYER_1, 100)
		expect(budget:getDirtyCount()).toBe(1)

		budget:flush()
		expect(budget:getDirtyCount()).toBe(0)
	end)

	test("does not error without DataStore", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		-- Should not error
		budget:flush()
		expect(budget:getDirtyCount()).toBe(0)
	end)

	test("handles DataStore SetAsync failure gracefully", function()
		local failingDS = createFailingDataStore(false, true)
		local budget = PaymasterBudget.new({ _dataStore = failingDS })
		budget:grantTokens(PLAYER_1, 100)

		-- Should not crash
		budget:flush()

		-- Should have logged the error
		local flushErrors = budget:getFlushErrors()
		expect(#flushErrors).toBeGreaterThan(0)
	end)

	test("only writes dirty entries (not clean ones)", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })

		budget:grantTokens(PLAYER_1, 100)
		budget:flush() -- flush player 1

		-- Player 1 is now clean, modify player 2 only
		budget:grantTokens(PLAYER_2, 200)
		data["player_12345"] = nil -- clear player 1's stored data

		budget:flush()

		-- Player 1 should NOT have been re-written (it was clean)
		expect(data["player_12345"]).toBeNil()
		-- Player 2 should have been written
		expect(data["player_67890"]).toBeTruthy()
	end)
end)

describe("PaymasterBudget:flushPlayer", function()
	test("flushes a single player to DataStore", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		budget:grantTokens(PLAYER_1, 100)
		budget:grantTokens(PLAYER_2, 200)

		budget:flushPlayer(PLAYER_1)

		-- Player 1 should be written
		expect(data["player_12345"]).toBeTruthy()
		expect(data["player_12345"].balance).toBe(100)

		-- Player 2 should NOT be written yet
		expect(data["player_67890"]).toBeNil()

		-- Dirty count should decrease by 1
		expect(budget:getDirtyCount()).toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Lazy flush triggers
--------------------------------------------------------------------------------

describe("PaymasterBudget — lazy flush", function()
	test("flushes when maxDirtyEntries reached", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			maxDirtyEntries = 3,
			flushInterval = 9999, -- don't trigger time-based flush
		})

		-- Grant to 2 players — no flush yet
		budget:grantTokens(PLAYER_1, 10)
		budget:grantTokens(PLAYER_2, 20)
		expect(data["player_12345"]).toBeNil() -- not flushed yet

		-- Grant to 3rd player — triggers flush (dirtyCount reaches 3)
		budget:grantTokens(PLAYER_3, 30)
		-- After flush, data should be written
		expect(data["player_12345"]).toBeTruthy()
		expect(data["player_67890"]).toBeTruthy()
		expect(data["player_11111"]).toBeTruthy()
		expect(budget:getDirtyCount()).toBe(0)
	end)

	test("flushes when flushInterval elapsed", function()
		local clock, setClock = makeClock(1000)
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			flushInterval = 30,
			maxDirtyEntries = 9999, -- don't trigger count-based flush
			_clock = clock,
		})

		budget:grantTokens(PLAYER_1, 10)
		expect(data["player_12345"]).toBeNil() -- not flushed yet

		-- Advance time past flushInterval
		setClock(1031)
		budget:grantTokens(PLAYER_2, 20) -- triggers _markDirty → _maybeFlush

		-- Should have flushed
		expect(data["player_12345"]).toBeTruthy()
		expect(budget:getDirtyCount()).toBe(0)
	end)

	test("does not flush before interval elapsed", function()
		local clock, setClock = makeClock(1000)
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			flushInterval = 30,
			maxDirtyEntries = 9999,
			_clock = clock,
		})

		budget:grantTokens(PLAYER_1, 10)

		-- Advance time but not past interval
		setClock(1020)
		budget:grantTokens(PLAYER_2, 20)

		-- Should NOT have flushed
		expect(data["player_12345"]).toBeNil()
		expect(budget:getDirtyCount()).toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: loadPlayer / unloadPlayer
--------------------------------------------------------------------------------

describe("PaymasterBudget:loadPlayer", function()
	test("loads player data from DataStore", function()
		local mockDS, data = createMockDataStore()
		data["player_12345"] = {
			balance = 500,
			totalTxCount = 20,
			totalTokensSpent = 100,
			lastTxTime = 5000,
		}
		local budget = PaymasterBudget.new({ _dataStore = mockDS })

		budget:loadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(true)
		expect(budget:getBalance(PLAYER_1)).toBe(500)
	end)

	test("creates default data when not in DataStore", function()
		local mockDS, _ = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			defaultTokenBalance = 25,
		})

		budget:loadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(true)
		expect(budget:getBalance(PLAYER_1)).toBe(25)
	end)

	test("creates default data when no DataStore", function()
		local budget = PaymasterBudget.new({ defaultTokenBalance = 15 })
		budget:loadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(true)
		expect(budget:getBalance(PLAYER_1)).toBe(15)
	end)

	test("handles DataStore failure gracefully", function()
		local failingDS = createFailingDataStore(true, false)
		local budget = PaymasterBudget.new({
			_dataStore = failingDS,
			defaultTokenBalance = 10,
		})

		-- Should not crash
		budget:loadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(true)
		expect(budget:getBalance(PLAYER_1)).toBe(10)
	end)
end)

describe("PaymasterBudget:unloadPlayer", function()
	test("removes player from cache", function()
		local budget = PaymasterBudget.new({})
		budget:grantTokens(PLAYER_1, 100)
		expect(budget:isCached(PLAYER_1)).toBe(true)

		budget:unloadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(false)
	end)

	test("flushes dirty data before unloading", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		budget:grantTokens(PLAYER_1, 100)
		expect(data["player_12345"]).toBeNil() -- not flushed yet

		budget:unloadPlayer(PLAYER_1)

		-- Should have flushed before removing from cache
		expect(data["player_12345"]).toBeTruthy()
		expect(data["player_12345"].balance).toBe(100)
		expect(budget:isCached(PLAYER_1)).toBe(false)
		expect(budget:getDirtyCount()).toBe(0)
	end)

	test("decrements dirty count on unload", function()
		local mockDS, _ = createMockDataStore()
		local budget = PaymasterBudget.new({ _dataStore = mockDS })
		budget:grantTokens(PLAYER_1, 100)
		budget:grantTokens(PLAYER_2, 200)
		expect(budget:getDirtyCount()).toBe(2)

		budget:unloadPlayer(PLAYER_1)
		expect(budget:getDirtyCount()).toBe(1)
	end)

	test("no-op for non-cached player", function()
		local budget = PaymasterBudget.new({})
		-- Should not error
		budget:unloadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(false)
	end)

	test("player data reloads from DataStore after unload", function()
		local mockDS, data = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			defaultTokenBalance = 0,
		})
		budget:grantTokens(PLAYER_1, 100)
		budget:unloadPlayer(PLAYER_1) -- flushes 100 to DataStore

		-- Next access should reload from DataStore
		expect(budget:getBalance(PLAYER_1)).toBe(100)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: isCached / getDirtyCount / getFlushErrors
--------------------------------------------------------------------------------

describe("PaymasterBudget — cache utilities", function()
	test("isCached returns false for unknown player", function()
		local budget = PaymasterBudget.new({})
		expect(budget:isCached(PLAYER_1)).toBe(false)
	end)

	test("isCached returns true after first access", function()
		local budget = PaymasterBudget.new({})
		budget:getBalance(PLAYER_1) -- triggers cache load
		expect(budget:isCached(PLAYER_1)).toBe(true)
	end)

	test("getDirtyCount tracks dirty entries correctly", function()
		local budget = PaymasterBudget.new({ maxDirtyEntries = 999, flushInterval = 9999 })
		expect(budget:getDirtyCount()).toBe(0)

		budget:grantTokens(PLAYER_1, 10)
		expect(budget:getDirtyCount()).toBe(1)

		budget:grantTokens(PLAYER_2, 20)
		expect(budget:getDirtyCount()).toBe(2)

		-- Same player again — should not increase dirty count
		budget:grantTokens(PLAYER_1, 5)
		expect(budget:getDirtyCount()).toBe(2)
	end)

	test("getFlushErrors returns empty array initially", function()
		local budget = PaymasterBudget.new({})
		expect(#budget:getFlushErrors()).toBe(0)
	end)

	test("clearFlushErrors clears all errors", function()
		local failingDS = createFailingDataStore(true, false)
		local budget = PaymasterBudget.new({
			_dataStore = failingDS,
			defaultTokenBalance = 0,
		})
		budget:getBalance(PLAYER_1) -- triggers failed GetAsync
		expect(#budget:getFlushErrors()).toBeGreaterThan(0)

		budget:clearFlushErrors()
		expect(#budget:getFlushErrors()).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Integration scenarios
--------------------------------------------------------------------------------

describe("PaymasterBudget — integration: game onboarding flow", function()
	test("new player signup: grant → transactions → stats", function()
		local clock, setClock = makeClock(1000)
		local mockDS, _ = createMockDataStore()
		local budget = PaymasterBudget.new({
			costPerTransaction = 2,
			_dataStore = mockDS,
			_clock = clock,
		})

		-- Player joins game and receives signup bonus
		budget:grantTokens(PLAYER_1, 20)
		expect(budget:getBalance(PLAYER_1)).toBe(20)
		expect(budget:canAfford(PLAYER_1)).toBe(true)

		-- Player makes 5 transactions
		for i = 1, 5 do
			setClock(1000 + i * 100)
			budget:consumeTransaction(PLAYER_1)
		end

		expect(budget:getBalance(PLAYER_1)).toBe(10) -- 20 - (5 * 2)
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(5)
		expect(stats.totalTokensSpent).toBe(10)
		expect(stats.lastTxTime).toBe(1500)

		-- Player earns reward tokens
		budget:grantTokens(PLAYER_1, 50)
		expect(budget:getBalance(PLAYER_1)).toBe(60)

		-- Flush to DataStore
		budget:flush()
	end)

	test("multiple players with independent budgets", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 1,
			defaultTokenBalance = 10,
			_clock = clock,
		})

		-- All players start with 10 tokens
		expect(budget:canAfford(PLAYER_1)).toBe(true)
		expect(budget:canAfford(PLAYER_2)).toBe(true)
		expect(budget:canAfford(PLAYER_3)).toBe(true)

		-- Player 1 uses all tokens
		for _ = 1, 10 do
			budget:consumeTransaction(PLAYER_1)
		end
		expect(budget:canAfford(PLAYER_1)).toBe(false)
		expect(budget:canAfford(PLAYER_2)).toBe(true) -- unaffected

		-- Player 2 gets extra tokens
		budget:grantTokens(PLAYER_2, 100)
		expect(budget:getBalance(PLAYER_2)).toBe(110)
	end)

	test("atomic consume → paymaster fail → refund", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 5,
			_clock = clock,
		})
		budget:grantTokens(PLAYER_1, 50)

		-- Step 1: Check affordability
		expect(budget:canAfford(PLAYER_1)).toBe(true)

		-- Step 2: Deduct tokens BEFORE paymaster submit
		local cost = budget:consumeTransaction(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(45)

		-- Step 3: Paymaster submission fails (simulated)
		local paymasterFailed = true

		-- Step 4: Refund on failure
		if paymasterFailed then
			budget:refundTransaction(PLAYER_1, cost)
		end

		-- Player should be back to original state
		expect(budget:getBalance(PLAYER_1)).toBe(50)
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(0)
		expect(stats.totalTokensSpent).toBe(0)
	end)

	test("consume → paymaster success → no refund", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 5,
			_clock = clock,
		})
		budget:grantTokens(PLAYER_1, 50)

		-- Deduct and submit
		budget:consumeTransaction(PLAYER_1)
		-- Paymaster succeeds — no refund needed
		expect(budget:getBalance(PLAYER_1)).toBe(45)
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(1)
		expect(stats.totalTokensSpent).toBe(5)
	end)

	test("variable gas cost with calculateCost", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 1,
			costPerGasUnit = 0.01,
			_clock = clock,
		})
		budget:grantTokens(PLAYER_1, 100)

		-- Calculate cost based on gas used
		local gasUsed = 500
		local cost = budget:calculateCost(gasUsed) -- 1 + 500*0.01 = 6
		expect(cost).toBe(6)

		-- Consume with calculated cost
		expect(budget:canAfford(PLAYER_1, cost)).toBe(true)
		budget:consumeTransaction(PLAYER_1, cost)
		expect(budget:getBalance(PLAYER_1)).toBe(94)
	end)
end)

describe("PaymasterBudget — integration: DataStore persistence", function()
	test("full lifecycle: load → use → flush → unload → reload", function()
		local mockDS, data = createMockDataStore()
		local clock, setClock = makeClock(1000)

		-- Session 1: Create budget and use it
		local budget1 = PaymasterBudget.new({
			costPerTransaction = 1,
			_dataStore = mockDS,
			_clock = clock,
		})

		budget1:grantTokens(PLAYER_1, 100)
		setClock(1100)
		budget1:consumeTransaction(PLAYER_1)
		setClock(1200)
		budget1:consumeTransaction(PLAYER_1)
		budget1:flush()

		-- Verify DataStore state
		local stored = data["player_12345"]
		expect(stored).toBeTruthy()
		expect(stored.balance).toBe(98)
		expect(stored.totalTxCount).toBe(2)

		-- Session 2: New budget instance loads from DataStore
		setClock(2000)
		local budget2 = PaymasterBudget.new({
			costPerTransaction = 1,
			_dataStore = mockDS,
			_clock = clock,
		})

		-- Should load from DataStore
		expect(budget2:getBalance(PLAYER_1)).toBe(98)
		local stats = budget2:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(2)
		expect(stats.totalTokensSpent).toBe(2)
	end)

	test("unload and reload preserves data", function()
		local mockDS, _ = createMockDataStore()
		local budget = PaymasterBudget.new({
			_dataStore = mockDS,
			defaultTokenBalance = 0,
		})

		budget:grantTokens(PLAYER_1, 75)
		budget:unloadPlayer(PLAYER_1)
		expect(budget:isCached(PLAYER_1)).toBe(false)

		-- Reload from DataStore
		budget:loadPlayer(PLAYER_1)
		expect(budget:getBalance(PLAYER_1)).toBe(75)
	end)
end)

describe("PaymasterBudget — integration: with PaymasterPolicy", function()
	-- This test demonstrates how PaymasterBudget composes with PaymasterPolicy
	-- in a realistic game server scenario.
	test("policy check → budget check → consume → refund flow", function()
		local clock, _ = makeClock(1000)
		local budget = PaymasterBudget.new({
			costPerTransaction = 5,
			_clock = clock,
		})

		-- Grant signup bonus
		budget:grantTokens(PLAYER_1, 50)

		-- Simulate the typical flow:
		-- 1. policy:validate() → allowed (handled by PaymasterPolicy, not tested here)
		-- 2. budget:canAfford() → check balance
		expect(budget:canAfford(PLAYER_1)).toBe(true)

		-- 3. budget:consumeTransaction() → deduct BEFORE paymaster submit
		local cost = budget:consumeTransaction(PLAYER_1)
		expect(cost).toBe(5)
		expect(budget:getBalance(PLAYER_1)).toBe(45)

		-- 4. account:executePaymaster() → submit (simulated success)
		-- No refund needed — tokens stay deducted

		-- 5. Verify final state
		local stats = budget:getUsageStats(PLAYER_1)
		expect(stats.totalTxCount).toBe(1)
		expect(stats.balance).toBe(45)
	end)
end)

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

print("\n" .. string.rep("—", 60))
print("PaymasterBudget: " .. tostring(passed) .. " passed, " .. tostring(failed) .. " failed")
if #errors > 0 then
	print("\nFailed tests:")
	for _, e in errors do
		print("  • " .. e)
	end
end
print(string.rep("—", 60))
