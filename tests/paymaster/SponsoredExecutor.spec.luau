--!strict
local SponsoredExecutor = require("../../src/paymaster/SponsoredExecutor")
local StarknetError = require("../../src/errors/StarknetError")
local ErrorCodes = require("../../src/errors/ErrorCodes")

--------------------------------------------------------------------------------
-- Test helpers
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
		toBeGreaterThan = function(n: number)
			if type(val) ~= "number" or val <= n then
				error("Expected > " .. tostring(n) .. " but got " .. tostring(val), 2)
			end
		end,
		toBeGreaterThanOrEqual = function(n: number)
			if type(val) ~= "number" or val < n then
				error("Expected >= " .. tostring(n) .. " but got " .. tostring(val), 2)
			end
		end,
	}
end

--------------------------------------------------------------------------------
-- MockPromise: synchronous Promise shim for Lune tests
--------------------------------------------------------------------------------

local MockPromise = {}
MockPromise.__index = MockPromise

function MockPromise.new(executor: (resolve: (any) -> (), reject: (any) -> ()) -> ())
	local self = setmetatable({ _status = "pending", _value = nil :: any }, MockPromise)
	executor(function(value)
		self._status = "resolved"
		self._value = value
	end, function(err)
		self._status = "rejected"
		self._value = err
	end)
	return self
end

function MockPromise.resolve(value: any)
	return MockPromise.new(function(resolve, _)
		resolve(value)
	end)
end

function MockPromise.reject(err: any)
	return MockPromise.new(function(_, reject)
		reject(err)
	end)
end

function MockPromise:expect(): any
	if self._status == "resolved" then
		return self._value
	end
	if self._status == "rejected" then
		error(self._value)
	end
	error("Promise not settled")
end

function MockPromise:andThen(fn: (any) -> any)
	if self._status == "resolved" then
		local ok, result = pcall(fn, self._value)
		if ok then
			return MockPromise.resolve(result)
		end
		return MockPromise.reject(result)
	end
	return self
end

function MockPromise:catch(fn: (any) -> any)
	if self._status == "rejected" then
		local ok, result = pcall(fn, self._value)
		if ok then
			return MockPromise.resolve(result)
		end
		return MockPromise.reject(result)
	end
	return self
end

--------------------------------------------------------------------------------
-- Mock factories
--------------------------------------------------------------------------------

local noopSleep = function(_seconds: number) end
local noopClock = function()
	return 0
end

local function createMockProvider(overrides: { [string]: any }?)
	local o = overrides or {}
	return {
		_getPromise = function()
			return MockPromise
		end,
		waitForTransaction = o.waitForTransaction,
	}
end

local function createMockAccount(overrides: { [string]: any }?)
	local o = overrides or {}
	local account: { [string]: any } = {
		address = o.address or "0x123abc",
		_provider = o._provider or createMockProvider(o),
	}
	if o.executePaymaster then
		account.executePaymaster = o.executePaymaster
	else
		account.executePaymaster = function(_self: any, _calls: any, _pd: any)
			return MockPromise.resolve({
				transactionHash = "0xdeadbeef",
				trackingId = "track-001",
			})
		end
	end
	return account
end

local function createMockPaymaster()
	return { _nodeUrl = "https://mock.paymaster" }
end

local function createMockPolicy(overrides: { [string]: any }?)
	local o = overrides or {}
	local policy: { [string]: any } = {
		_usageRecorded = {} :: { number },
	}
	if o.validate then
		policy.validate = o.validate
	else
		policy.validate = function(_self: any, _playerId: number, _calls: any)
			return { allowed = true }
		end
	end
	if o.validateFee then
		policy.validateFee = o.validateFee
	else
		policy.validateFee = function(_self: any, _playerId: number, _feeAmount: any)
			return { allowed = true }
		end
	end
	policy.recordUsage = function(self: any, playerId: number)
		table.insert(self._usageRecorded, playerId)
	end
	return policy
end

local function createMockBudget(overrides: { [string]: any }?)
	local o = overrides or {}
	local budget: { [string]: any } = {
		_balance = o.balance or 100,
		_costPerTx = o.costPerTransaction or 1,
		_costPerGas = o.costPerGasUnit or 0,
		_consumed = {} :: { { playerId: number, cost: number } },
		_refunded = {} :: { { playerId: number, cost: number } },
	}
	budget.getBalance = function(self: any, _playerId: number)
		return self._balance
	end
	budget.calculateCost = function(self: any, gasUsed: number?)
		local cost = self._costPerTx
		if gasUsed and self._costPerGas > 0 then
			cost = cost + (gasUsed * self._costPerGas)
		end
		return cost
	end
	budget.canAfford = function(self: any, _playerId: number, txCost: number?)
		local cost = txCost or self._costPerTx
		return self._balance >= cost
	end
	budget.consumeTransaction = function(self: any, playerId: number, txCost: number?)
		local cost = txCost or self._costPerTx
		self._balance -= cost
		table.insert(self._consumed, { playerId = playerId, cost = cost })
		return cost
	end
	budget.refundTransaction = function(self: any, playerId: number, txCost: number?)
		local cost = txCost or self._costPerTx
		self._balance += cost
		table.insert(self._refunded, { playerId = playerId, cost = cost })
	end
	return budget
end

--- Standard sample calls used across tests.
local function sampleCalls()
	return {
		{
			contractAddress = "0xtoken123",
			entrypoint = "transfer",
			calldata = { "0xrecipient", "0x64" },
		},
	}
end

--- Create a minimal valid executor config.
local function minimalConfig(overrides: { [string]: any }?)
	local o = overrides or {}
	return {
		account = o.account or createMockAccount(),
		paymaster = o.paymaster or createMockPaymaster(),
		feeMode = o.feeMode or { mode = "sponsored" },
		policy = o.policy,
		budget = o.budget,
		callbacks = o.callbacks,
		retryAttempts = o.retryAttempts,
		retryDelay = o.retryDelay,
		deploymentData = o.deploymentData,
		_sleep = o._sleep or noopSleep,
		_clock = o._clock or noopClock,
	}
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("SponsoredExecutor — Constructor validation", function()
	test("throws on nil config", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new(nil :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.REQUIRED_FIELD.code)
	end)

	test("throws on missing account", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new({
				paymaster = createMockPaymaster(),
				feeMode = { mode = "sponsored" },
				_sleep = noopSleep,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.REQUIRED_FIELD.code)
	end)

	test("throws on missing paymaster", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new({
				account = createMockAccount(),
				feeMode = { mode = "sponsored" },
				_sleep = noopSleep,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.REQUIRED_FIELD.code)
	end)

	test("throws on missing feeMode", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new({
				account = createMockAccount(),
				paymaster = createMockPaymaster(),
				_sleep = noopSleep,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.REQUIRED_FIELD.code)
	end)

	test("throws on invalid feeMode.mode", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new({
				account = createMockAccount(),
				paymaster = createMockPaymaster(),
				feeMode = { mode = "invalid" },
				_sleep = noopSleep,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	test("throws on default mode without gasToken", function()
		local ok, err = pcall(function()
			SponsoredExecutor.new({
				account = createMockAccount(),
				paymaster = createMockPaymaster(),
				feeMode = { mode = "default" },
				_sleep = noopSleep,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.REQUIRED_FIELD.code)
	end)

	test("succeeds with minimal config (sponsored)", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		expect(executor).toBeTruthy()
	end)

	test("succeeds with default mode and gasToken", function()
		local executor = SponsoredExecutor.new(minimalConfig({
			feeMode = { mode = "default", gasToken = "0xstrk" },
		}))
		expect(executor).toBeTruthy()
	end)

	test("succeeds with all optional fields", function()
		local executor = SponsoredExecutor.new(minimalConfig({
			policy = createMockPolicy(),
			budget = createMockBudget(),
			callbacks = {
				onTransactionSubmitted = function() end,
				onTransactionConfirmed = function() end,
				onTransactionFailed = function() end,
			},
			retryAttempts = 5,
			retryDelay = 2,
			deploymentData = { classHash = "0xclass" },
		}))
		expect(executor).toBeTruthy()
	end)
end)

describe("SponsoredExecutor — Execute input validation", function()
	test("throws on non-number playerId", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, err = pcall(function()
			executor:execute("abc" :: any, sampleCalls())
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	test("throws on empty calls", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, err = pcall(function()
			executor:execute(123, {})
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	test("throws on nil calls", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, err = pcall(function()
			executor:execute(123, nil :: any)
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.INVALID_ARGUMENT.code)
	end)
end)

describe("SponsoredExecutor — Basic execution success", function()
	test("successful execution returns transactionHash and trackingId", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
		expect(result.trackingId).toBe("track-001")
		expect(result.tokensCost).toBe(0)
		expect(result.retryCount).toBe(0)
	end)

	test("forwards feeMode to account:executePaymaster", function()
		local capturedPd: any = nil
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, pd: any)
				capturedPd = pd
				return MockPromise.resolve({ transactionHash = "0x1", trackingId = nil })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			feeMode = { mode = "default", gasToken = "0xstrk" },
		}))
		executor:execute(123, sampleCalls()):expect()
		expect(capturedPd.feeMode.mode).toBe("default")
		expect(capturedPd.feeMode.gasToken).toBe("0xstrk")
	end)

	test("forwards config deploymentData to paymasterDetails", function()
		local capturedPd: any = nil
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, pd: any)
				capturedPd = pd
				return MockPromise.resolve({ transactionHash = "0x1" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			deploymentData = { classHash = "0xclass", calldata = { "0x1" }, salt = "0xsalt" },
		}))
		executor:execute(123, sampleCalls()):expect()
		expect(capturedPd.deploymentData.classHash).toBe("0xclass")
	end)

	test("options deploymentData overrides config deploymentData", function()
		local capturedPd: any = nil
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, pd: any)
				capturedPd = pd
				return MockPromise.resolve({ transactionHash = "0x1" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			deploymentData = { classHash = "0xold" },
		}))
		executor:execute(123, sampleCalls(), { deploymentData = { classHash = "0xnew" } }):expect()
		expect(capturedPd.deploymentData.classHash).toBe("0xnew")
	end)
end)

describe("SponsoredExecutor — Policy integration", function()
	test("policy rejection prevents execution and fires onTransactionFailed", function()
		local failedCalled = false
		local policy = createMockPolicy({
			validate = function(_self: any, _pid: number, _calls: any)
				return { allowed = false, reason = "Contract not whitelisted" }
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			policy = policy,
			callbacks = {
				onTransactionFailed = function(_info: any)
					failedCalled = true
				end,
			},
		}))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.PAYMASTER_POLICY_REJECTED.code)
		expect(failedCalled).toBe(true)
	end)

	test("policy rejection error includes reason", function()
		local policy = createMockPolicy({
			validate = function(_self: any, _pid: number, _calls: any)
				return { allowed = false, reason = "Rate limit exceeded" }
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ policy = policy }))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(false)
		expect(tostring(err)).toContain("Rate limit exceeded")
	end)

	test("policy allows → proceeds to execution", function()
		local policy = createMockPolicy()
		local executor = SponsoredExecutor.new(minimalConfig({ policy = policy }))
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
	end)

	test("policy records usage on successful execution", function()
		local policy = createMockPolicy()
		local executor = SponsoredExecutor.new(minimalConfig({ policy = policy }))
		executor:execute(123, sampleCalls()):expect()
		expect(#policy._usageRecorded).toBe(1)
		expect(policy._usageRecorded[1]).toBe(123)
	end)

	test("policy does NOT record usage on failed execution", function()
		local policy = createMockPolicy()
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			policy = policy,
			retryAttempts = 1,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(#policy._usageRecorded).toBe(0)
	end)

	test("no policy → skips check, executes normally", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
	end)
end)

describe("SponsoredExecutor — Budget integration", function()
	test("insufficient budget prevents execution", function()
		local budget = createMockBudget({ balance = 0 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.INSUFFICIENT_BUDGET.code)
	end)

	test("insufficient budget fires onTransactionFailed", function()
		local failedInfo: any = nil
		local budget = createMockBudget({ balance = 0 })
		local executor = SponsoredExecutor.new(minimalConfig({
			budget = budget,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(failedInfo).toBeTruthy()
		expect(failedInfo.playerId).toBe(123)
		expect(failedInfo.tokensRefunded).toBe(0)
	end)

	test("budget consumed before execution", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		executor:execute(123, sampleCalls()):expect()
		expect(#budget._consumed).toBe(1)
		expect(budget._consumed[1].cost).toBe(5)
		expect(budget._balance).toBe(95)
	end)

	test("budget NOT refunded on success", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		executor:execute(123, sampleCalls()):expect()
		expect(#budget._refunded).toBe(0)
	end)

	test("budget refunded on execution failure", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			retryAttempts = 1,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(#budget._refunded).toBe(1)
		expect(budget._refunded[1].cost).toBe(5)
		expect(budget._balance).toBe(100) -- consumed then refunded
	end)

	test("custom txCost option overrides calculated cost", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		local result = executor:execute(123, sampleCalls(), { txCost = 10 }):expect()
		expect(result.tokensCost).toBe(10)
		expect(budget._consumed[1].cost).toBe(10)
		expect(budget._balance).toBe(90)
	end)

	test("gasUsed option calculates variable cost", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 1, costPerGasUnit = 0.5 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		local result = executor:execute(123, sampleCalls(), { gasUsed = 10 }):expect()
		-- cost = 1 + (10 * 0.5) = 6
		expect(result.tokensCost).toBe(6)
	end)

	test("no budget → tokensCost is 0", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.tokensCost).toBe(0)
	end)

	test("policy rejection does NOT consume budget", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local policy = createMockPolicy({
			validate = function(_self: any, _pid: number, _calls: any)
				return { allowed = false, reason = "denied" }
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			policy = policy,
			budget = budget,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(#budget._consumed).toBe(0)
		expect(budget._balance).toBe(100)
	end)
end)

describe("SponsoredExecutor — Retry logic", function()
	test("transient error (502) triggers retry", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(StarknetError.rpc("HTTP 502", ErrorCodes.NETWORK_ERROR.code, 502))
				end
				return MockPromise.resolve({ transactionHash = "0xretried" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.transactionHash).toBe("0xretried")
		expect(result.retryCount).toBe(1)
		expect(attemptCount).toBe(2)
	end)

	test("succeeds on 3rd attempt → retryCount=2", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount < 3 then
					return MockPromise.reject(StarknetError.rpc("HTTP 503", ErrorCodes.NETWORK_ERROR.code, 503))
				end
				return MockPromise.resolve({ transactionHash = "0xthird" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.transactionHash).toBe("0xthird")
		expect(result.retryCount).toBe(2)
	end)

	test("deterministic error does NOT retry", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				return MockPromise.reject(
					StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(attemptCount).toBe(1) -- no retries
	end)

	test("all retries exhausted → wraps error with SPONSORED_EXECUTION_FAILED", function()
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 502", ErrorCodes.NETWORK_ERROR.code, 502))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 3,
		}))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.SPONSORED_EXECUTION_FAILED.code)
		expect(err.data.attempts).toBe(3)
	end)

	test("single attempt failure (retryAttempts=1) returns original error", function()
		local originalErr = StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(originalErr)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 1,
		}))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code)
	end)

	test("exponential backoff timing", function()
		local sleepCalls: { number } = {}
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 502", ErrorCodes.NETWORK_ERROR.code, 502))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 4,
			retryDelay = 1,
			_sleep = function(seconds: number)
				table.insert(sleepCalls, seconds)
			end,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		-- Backoff: attempt 2 → 1*2^0=1, attempt 3 → 1*2^1=2, attempt 4 → 1*2^2=4
		expect(#sleepCalls).toBe(3)
		expect(sleepCalls[1]).toBe(1)
		expect(sleepCalls[2]).toBe(2)
		expect(sleepCalls[3]).toBe(4)
	end)

	test("custom retryDelay scales backoff", function()
		local sleepCalls: { number } = {}
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 502", ErrorCodes.NETWORK_ERROR.code, 502))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 3,
			retryDelay = 0.5,
			_sleep = function(seconds: number)
				table.insert(sleepCalls, seconds)
			end,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(sleepCalls[1]).toBe(0.5)
		expect(sleepCalls[2]).toBe(1)
	end)

	test("network error triggers retry", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(StarknetError.rpc("Connection refused", ErrorCodes.NETWORK_ERROR.code))
				end
				return MockPromise.resolve({ transactionHash = "0xrecovered" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.transactionHash).toBe("0xrecovered")
	end)

	test("rate limit error triggers retry", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(StarknetError.rpc("Rate limited", ErrorCodes.RATE_LIMIT.code))
				end
				return MockPromise.resolve({ transactionHash = "0xunlimited" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.transactionHash).toBe("0xunlimited")
	end)

	test("paymaster unavailable triggers retry", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(
						StarknetError.rpc("Service down", ErrorCodes.PAYMASTER_UNAVAILABLE.code)
					)
				end
				return MockPromise.resolve({ transactionHash = "0xback" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local result = executor:execute(123, sampleCalls()):expect()
		expect(result.transactionHash).toBe("0xback")
	end)

	test("budget refunded after all retries exhausted", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 10 })
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 503", ErrorCodes.NETWORK_ERROR.code, 503))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			retryAttempts = 2,
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(#budget._refunded).toBe(1)
		expect(budget._balance).toBe(100) -- consumed then refunded
	end)
end)

describe("SponsoredExecutor — Callbacks", function()
	test("onTransactionSubmitted fires on success with correct info", function()
		local submittedInfo: any = nil
		local executor = SponsoredExecutor.new(minimalConfig({
			callbacks = {
				onTransactionSubmitted = function(info: any)
					submittedInfo = info
				end,
			},
		}))
		executor:execute(42, sampleCalls()):expect()
		expect(submittedInfo).toBeTruthy()
		expect(submittedInfo.playerId).toBe(42)
		expect(submittedInfo.transactionHash).toBe("0xdeadbeef")
		expect(submittedInfo.trackingId).toBe("track-001")
		expect(submittedInfo.tokensCost).toBe(0)
		expect(#submittedInfo.calls).toBe(1)
	end)

	test("onTransactionFailed fires on execution failure", function()
		local failedInfo: any = nil
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 1,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		pcall(function()
			executor:execute(99, sampleCalls()):expect()
		end)
		expect(failedInfo).toBeTruthy()
		expect(failedInfo.playerId).toBe(99)
		expect(failedInfo.retryCount).toBe(0)
	end)

	test("onTransactionFailed includes tokensRefunded", function()
		local failedInfo: any = nil
		local budget = createMockBudget({ balance = 100, costPerTransaction = 7 })
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("fail", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			retryAttempts = 1,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		pcall(function()
			executor:execute(99, sampleCalls()):expect()
		end)
		expect(failedInfo.tokensRefunded).toBe(7)
	end)

	test("callback error does not crash executor", function()
		local executor = SponsoredExecutor.new(minimalConfig({
			callbacks = {
				onTransactionSubmitted = function(_info: any)
					error("callback crashed!")
				end,
			},
		}))
		-- Should not throw despite callback error
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
	end)

	test("no callbacks → no crash", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls()):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
	end)

	test("onTransactionFailed fires on policy rejection", function()
		local failedInfo: any = nil
		local policy = createMockPolicy({
			validate = function(_self: any, _pid: number, _calls: any)
				return { allowed = false, reason = "blocked" }
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			policy = policy,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(failedInfo).toBeTruthy()
		expect(failedInfo.retryCount).toBe(0)
		expect(failedInfo.tokensRefunded).toBe(0)
	end)

	test("onTransactionFailed fires on budget rejection", function()
		local failedInfo: any = nil
		local budget = createMockBudget({ balance = 0 })
		local executor = SponsoredExecutor.new(minimalConfig({
			budget = budget,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		pcall(function()
			executor:execute(123, sampleCalls()):expect()
		end)
		expect(failedInfo).toBeTruthy()
		expect(failedInfo.playerId).toBe(123)
	end)
end)

describe("SponsoredExecutor — waitForConfirmation", function()
	test("waitForConfirmation=true waits and fires onTransactionConfirmed", function()
		local confirmedInfo: any = nil
		local provider = createMockProvider({
			waitForTransaction = function(_self: any, _txHash: string)
				return MockPromise.resolve({ status = "ACCEPTED_ON_L2" })
			end,
		})
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			callbacks = {
				onTransactionConfirmed = function(info: any)
					confirmedInfo = info
				end,
			},
		}))
		local result = executor:execute(123, sampleCalls(), { waitForConfirmation = true }):expect()
		expect(result.transactionHash).toBe("0xdeadbeef")
		expect(confirmedInfo).toBeTruthy()
		expect(confirmedInfo.playerId).toBe(123)
		expect(confirmedInfo.transactionHash).toBe("0xdeadbeef")
	end)

	test("waitForConfirmation=true + revert → refunds budget and rejects", function()
		local failedInfo: any = nil
		local budget = createMockBudget({ balance = 100, costPerTransaction = 5 })
		local provider = createMockProvider({
			waitForTransaction = function(_self: any, _txHash: string)
				return MockPromise.reject(
					StarknetError.transaction("Reverted", ErrorCodes.TRANSACTION_REVERTED.code, "Execution failed")
				)
			end,
		})
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			callbacks = {
				onTransactionFailed = function(info: any)
					failedInfo = info
				end,
			},
		}))
		local ok, err = pcall(function()
			return executor:execute(123, sampleCalls(), { waitForConfirmation = true }):expect()
		end)
		expect(ok).toBe(false)
		expect(err.code).toBe(ErrorCodes.TRANSACTION_REVERTED.code)
		expect(failedInfo).toBeTruthy()
		expect(failedInfo.tokensRefunded).toBe(5)
		expect(budget._balance).toBe(100) -- consumed then refunded
	end)

	test("waitForConfirmation=false resolves immediately without waiting", function()
		local waitCalled = false
		local provider = createMockProvider({
			waitForTransaction = function(_self: any, _txHash: string)
				waitCalled = true
				return MockPromise.resolve({})
			end,
		})
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		executor:execute(123, sampleCalls()):expect()
		expect(waitCalled).toBe(false)
	end)

	test("waitForConfirmation=true + no waitForTransaction method → resolves immediately", function()
		-- Provider without waitForTransaction
		local provider = createMockProvider()
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local ok, result = pcall(function()
			return executor:execute(123, sampleCalls(), { waitForConfirmation = true }):expect()
		end)
		expect(ok).toBe(true)
		expect(result.transactionHash).toBe("0xdeadbeef")
	end)

	test("waitForConfirmation + policy records usage only after confirmation", function()
		local policy = createMockPolicy()
		local provider = createMockProvider({
			waitForTransaction = function(_self: any, _txHash: string)
				return MockPromise.resolve({ status = "ACCEPTED_ON_L2" })
			end,
		})
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			policy = policy,
		}))
		executor:execute(123, sampleCalls(), { waitForConfirmation = true }):expect()
		expect(#policy._usageRecorded).toBe(1)
	end)

	test("waitForConfirmation + revert → policy does NOT record usage", function()
		local policy = createMockPolicy()
		local provider = createMockProvider({
			waitForTransaction = function(_self: any, _txHash: string)
				return MockPromise.reject(StarknetError.transaction("Reverted", ErrorCodes.TRANSACTION_REVERTED.code))
			end,
		})
		local account = createMockAccount({ _provider = provider })
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			policy = policy,
		}))
		pcall(function()
			executor:execute(123, sampleCalls(), { waitForConfirmation = true }):expect()
		end)
		expect(#policy._usageRecorded).toBe(0)
	end)
end)

describe("SponsoredExecutor — Metrics", function()
	test("totalExecutions incremented per call", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(1, sampleCalls()):expect()
		executor:execute(2, sampleCalls()):expect()
		expect(executor:getMetrics().totalExecutions).toBe(2)
	end)

	test("totalSuccessful incremented on success", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(1, sampleCalls()):expect()
		expect(executor:getMetrics().totalSuccessful).toBe(1)
	end)

	test("totalFailed incremented on failure", function()
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("fail", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 1,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(executor:getMetrics().totalFailed).toBe(1)
	end)

	test("totalRetries tracked across attempts", function()
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 502", ErrorCodes.NETWORK_ERROR.code, 502))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 4,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(executor:getMetrics().totalRetries).toBe(3) -- 4 attempts - 1 = 3 retries
	end)

	test("totalTokensConsumed and totalTokensRefunded tracked", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 8 })
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("fail", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			retryAttempts = 1,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		local m = executor:getMetrics()
		expect(m.totalTokensConsumed).toBe(8)
		expect(m.totalTokensRefunded).toBe(8)
	end)

	test("per-player metrics tracked", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(100, sampleCalls()):expect()
		executor:execute(100, sampleCalls()):expect()
		executor:execute(200, sampleCalls()):expect()
		local m = executor:getMetrics()
		expect(m.byPlayer[100].executions).toBe(2)
		expect(m.byPlayer[100].successful).toBe(2)
		expect(m.byPlayer[200].executions).toBe(1)
	end)

	test("per-contract metrics tracked", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(1, {
			{ contractAddress = "0xaaa", entrypoint = "transfer", calldata = {} },
			{ contractAddress = "0xbbb", entrypoint = "approve", calldata = {} },
		}):expect()
		local m = executor:getMetrics()
		expect(m.byContract["0xaaa"]).toBe(1)
		expect(m.byContract["0xbbb"]).toBe(1)
	end)

	test("per-method metrics tracked", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(1, {
			{ contractAddress = "0xaaa", entrypoint = "transfer", calldata = {} },
		}):expect()
		local m = executor:getMetrics()
		expect(m.byMethod["0xaaa:transfer"]).toBe(1)
	end)

	test("resetMetrics clears all metrics", function()
		local executor = SponsoredExecutor.new(minimalConfig())
		executor:execute(1, sampleCalls()):expect()
		executor:resetMetrics()
		local m = executor:getMetrics()
		expect(m.totalExecutions).toBe(0)
		expect(m.totalSuccessful).toBe(0)
		expect(m.totalFailed).toBe(0)
		expect(m.totalRetries).toBe(0)
		expect(m.totalTokensConsumed).toBe(0)
		expect(m.totalTokensRefunded).toBe(0)
	end)

	test("per-player tokensSpent tracked on success", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 3 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		executor:execute(1, sampleCalls()):expect()
		expect(executor:getMetrics().byPlayer[1].tokensSpent).toBe(3)
	end)

	test("failed execution increments player failed count", function()
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(
					StarknetError.rpc("fail", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 1,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(executor:getMetrics().byPlayer[1].failed).toBe(1)
	end)
end)

describe("SponsoredExecutor — Integration scenarios", function()
	test("full flow: policy + budget + execute", function()
		local policy = createMockPolicy()
		local budget = createMockBudget({ balance = 50, costPerTransaction = 5 })
		local submittedInfo: any = nil
		local executor = SponsoredExecutor.new(minimalConfig({
			policy = policy,
			budget = budget,
			callbacks = {
				onTransactionSubmitted = function(info: any)
					submittedInfo = info
				end,
			},
		}))
		local result = executor:execute(42, sampleCalls()):expect()
		-- Execution succeeded
		expect(result.transactionHash).toBe("0xdeadbeef")
		expect(result.tokensCost).toBe(5)
		-- Policy usage recorded
		expect(#policy._usageRecorded).toBe(1)
		-- Budget consumed
		expect(budget._balance).toBe(45)
		-- Callback fired
		expect(submittedInfo).toBeTruthy()
		expect(submittedInfo.tokensCost).toBe(5)
	end)

	test("multiple sequential executions", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 10 })
		local executor = SponsoredExecutor.new(minimalConfig({ budget = budget }))
		executor:execute(1, sampleCalls()):expect()
		executor:execute(1, sampleCalls()):expect()
		executor:execute(1, sampleCalls()):expect()
		expect(budget._balance).toBe(70)
		expect(executor:getMetrics().totalExecutions).toBe(3)
		expect(executor:getMetrics().totalSuccessful).toBe(3)
	end)

	test("retry with budget: consumed once, refunded once on final failure", function()
		local budget = createMockBudget({ balance = 100, costPerTransaction = 10 })
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				return MockPromise.reject(StarknetError.rpc("HTTP 504", ErrorCodes.NETWORK_ERROR.code, 504))
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			budget = budget,
			retryAttempts = 3,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		-- Budget consumed once, refunded once
		expect(#budget._consumed).toBe(1)
		expect(#budget._refunded).toBe(1)
		expect(budget._balance).toBe(100)
	end)

	test("multiple calls forwarded to account", function()
		local capturedCalls: any = nil
		local account = createMockAccount({
			executePaymaster = function(_self: any, calls: any, _pd: any)
				capturedCalls = calls
				return MockPromise.resolve({ transactionHash = "0xmulti" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		local calls = {
			{ contractAddress = "0xaaa", entrypoint = "transfer", calldata = { "0x1" } },
			{ contractAddress = "0xbbb", entrypoint = "approve", calldata = { "0x2" } },
		}
		executor:execute(1, calls):expect()
		expect(#capturedCalls).toBe(2)
		expect(capturedCalls[1].entrypoint).toBe("transfer")
		expect(capturedCalls[2].entrypoint).toBe("approve")
	end)

	test("mixed success and failure across calls", function()
		local callCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				callCount += 1
				if callCount == 2 then
					return MockPromise.reject(
						StarknetError.rpc("fail", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
					)
				end
				return MockPromise.resolve({ transactionHash = "0x" .. tostring(callCount) })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 1,
		}))
		-- First call succeeds
		local r1 = executor:execute(1, sampleCalls()):expect()
		expect(r1.transactionHash).toBe("0x1")
		-- Second call fails
		local ok2, _ = pcall(function()
			return executor:execute(1, sampleCalls()):expect()
		end)
		expect(ok2).toBe(false)
		-- Third call succeeds
		local r3 = executor:execute(1, sampleCalls()):expect()
		expect(r3.transactionHash).toBe("0x3")
		local m = executor:getMetrics()
		expect(m.totalSuccessful).toBe(2)
		expect(m.totalFailed).toBe(1)
	end)
end)

describe("SponsoredExecutor — Transient error detection", function()
	test("HTTP 502 is transient (retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(StarknetError.rpc("Bad Gateway", ErrorCodes.NETWORK_ERROR.code, 502))
				end
				return MockPromise.resolve({ transactionHash = "0x1" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		executor:execute(1, sampleCalls()):expect()
		expect(attemptCount).toBe(2)
	end)

	test("HTTP 503 is transient (retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(
						StarknetError.rpc("Service Unavailable", ErrorCodes.NETWORK_ERROR.code, 503)
					)
				end
				return MockPromise.resolve({ transactionHash = "0x1" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		executor:execute(1, sampleCalls()):expect()
		expect(attemptCount).toBe(2)
	end)

	test("HTTP 504 is transient (retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject(StarknetError.rpc("Gateway Timeout", ErrorCodes.NETWORK_ERROR.code, 504))
				end
				return MockPromise.resolve({ transactionHash = "0x1" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		executor:execute(1, sampleCalls()):expect()
		expect(attemptCount).toBe(2)
	end)

	test("PAYMASTER_INVALID_SIGNATURE is deterministic (not retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				return MockPromise.reject(
					StarknetError.rpc("invalid sig", ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code, 153)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 3,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(attemptCount).toBe(1)
	end)

	test("PAYMASTER_EXECUTION_ERROR is deterministic (not retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				return MockPromise.reject(
					StarknetError.rpc("exec failed", ErrorCodes.PAYMASTER_EXECUTION_ERROR.code, 156)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 3,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(attemptCount).toBe(1)
	end)

	test("PAYMASTER_CALL_VALIDATION_FAILED is deterministic (not retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				return MockPromise.reject(
					StarknetError.new("calls mismatch", ErrorCodes.PAYMASTER_CALL_VALIDATION_FAILED.code)
				)
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({
			account = account,
			retryAttempts = 3,
		}))
		pcall(function()
			executor:execute(1, sampleCalls()):expect()
		end)
		expect(attemptCount).toBe(1)
	end)

	test("raw string error is treated as transient (retried)", function()
		local attemptCount = 0
		local account = createMockAccount({
			executePaymaster = function(_self: any, _calls: any, _pd: any)
				attemptCount += 1
				if attemptCount == 1 then
					return MockPromise.reject("connection reset")
				end
				return MockPromise.resolve({ transactionHash = "0xrecovered" })
			end,
		})
		local executor = SponsoredExecutor.new(minimalConfig({ account = account }))
		executor:execute(1, sampleCalls()):expect()
		expect(attemptCount).toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

print("\n=============================")
if failed > 0 then
	print(`  {passed} passed, {failed} FAILED`)
	for _, e in errors do
		print("  " .. e)
	end
else
	print(`  All {passed} tests passed!`)
end
print("=============================\n")
