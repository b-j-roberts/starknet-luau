--!strict
local serde = require("@lune/serde")

local NonceManager = require("../../src/provider/NonceManager")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local Account = require("../../src/wallet/Account")
local StarkSigner = require("../../src/signer/StarkSigner")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local SN_SEPOLIA = "0x534e5f5345504f4c4941"
local TEST_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
local TEST_ADDRESS_2 = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

-- Private key from StarkSigner tests (must be < curve order N)
local PRIVKEY_1 = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"

--------------------------------------------------------------------------------
-- Mock infrastructure
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}
local onChainNonce = "0x5"

local function resetMocks()
	mockHandlers = {}
	requestLog = {}
	onChainNonce = "0x5"

	mockHandlers["starknet_chainId"] = function(_params)
		return SN_SEPOLIA
	end

	mockHandlers["starknet_getNonce"] = function(_params)
		return onChainNonce
	end

	mockHandlers["starknet_estimateFee"] = function(_params)
		return {
			{
				gas_consumed = "0x1000",
				gas_price = "0x100",
				overall_fee = "0x100000",
				data_gas_consumed = "0x200",
				data_gas_price = "0x50",
				unit = "WEI",
			},
		}
	end

	mockHandlers["starknet_addInvokeTransaction"] = function(_params)
		return { transaction_hash = "0xabc123" }
	end
end

local function createMockHttpRequest(): (request: RpcTypes.HttpRequest) -> RpcTypes.HttpResponse
	return function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
		local body = serde.decode("json", request.Body or "{}") :: any
		local method: string = body.method or ""
		local params: any = body.params
		local id: number = body.id or 0

		table.insert(requestLog, { method = method, params = params })

		local handler = mockHandlers[method]
		if handler then
			local ok, result = pcall(handler, params)
			if ok then
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						result = result,
					}),
					Success = true,
				}
			else
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						error = {
							code = -32000,
							message = tostring(result),
						},
					}),
					Success = true,
				}
			end
		end

		return {
			StatusCode = 200,
			Body = serde.encode("json", {
				jsonrpc = "2.0",
				id = id,
				error = {
					code = -32601,
					message = `Method not found: {method}`,
				},
			}),
			Success = true,
		}
	end
end

local function createTestProvider(enableNonceManager: boolean?, nmConfig: any?): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
		enableNonceManager = enableNonceManager or false,
		nonceManagerConfig = nmConfig,
	}

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

local function createTestCalls(): { any }
	return {
		{
			contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			entrypoint = "transfer",
			calldata = {
				"0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
				"0x3e8",
				"0x0",
			},
		},
	}
end

resetMocks()

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("NonceManager - constructor", function()
	it("creates with default config", function()
		resetMocks()
		local provider = createTestProvider()
		local nm = NonceManager.new(provider)
		expect(nm):toBeTruthy()
	end)

	it("creates with custom maxPendingNonces", function()
		resetMocks()
		local provider = createTestProvider()
		local nm = NonceManager.new(provider, { maxPendingNonces = 5 })
		expect(nm):toBeTruthy()
	end)

	it("creates with autoResyncOnError disabled", function()
		resetMocks()
		local provider = createTestProvider()
		local nm = NonceManager.new(provider, { autoResyncOnError = false })
		expect(nm):toBeTruthy()
	end)

	it("starts with empty metrics", function()
		resetMocks()
		local provider = createTestProvider()
		local nm = NonceManager.new(provider)
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(0)
		expect(m.totalConfirmed):toBe(0)
		expect(m.totalRejected):toBe(0)
		expect(m.totalResyncs):toBe(0)
	end)

	it("starts with no addresses initialized", function()
		resetMocks()
		local provider = createTestProvider()
		local nm = NonceManager.new(provider)
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: reserve()
--------------------------------------------------------------------------------

describe("NonceManager - reserve", function()
	it("fetches on-chain nonce on first reserve", function()
		resetMocks()
		onChainNonce = "0xa"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local result = nm:reserve(TEST_ADDRESS):expect()
		expect(result):toBe("0xa")
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(true)
	end)

	it("returns sequential nonces on subsequent reserves", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		local n2 = nm:reserve(TEST_ADDRESS):expect()
		local n3 = nm:reserve(TEST_ADDRESS):expect()

		expect(n1):toBe("0x5")
		expect(n2):toBe("0x6")
		expect(n3):toBe("0x7")
	end)

	it("does not re-fetch nonce after initialization", function()
		resetMocks()
		onChainNonce = "0x5"
		requestLog = {}
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		-- Should only have one getNonce RPC call
		local nonceCallCount = 0
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				nonceCallCount += 1
			end
		end
		expect(nonceCallCount):toBe(1)
	end)

	it("tracks separate nonces per address", function()
		resetMocks()
		local callCount = 0
		mockHandlers["starknet_getNonce"] = function(_params)
			callCount += 1
			if callCount == 1 then
				return "0x3"
			end
			return "0xa"
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		local n2 = nm:reserve(TEST_ADDRESS_2):expect()

		expect(n1):toBe("0x3")
		expect(n2):toBe("0xa")
	end)

	it("increments metrics on reserve", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(2)
	end)

	it("works with nonce 0x0", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local result = nm:reserve(TEST_ADDRESS):expect()
		expect(result):toBe("0x0")
	end)

	it("uses pending block tag for fetch", function()
		resetMocks()
		requestLog = {}
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				found = true
				-- First param should be "pending" block tag
				expect(entry.params[1]):toBe("pending")
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: confirm()
--------------------------------------------------------------------------------

describe("NonceManager - confirm", function()
	it("removes nonce from pending set", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(1)

		nm:confirm(TEST_ADDRESS, nonce)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)

	it("increments confirmed metrics", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:confirm(TEST_ADDRESS, nonce)

		local m = nm:getMetrics()
		expect(m.totalConfirmed):toBe(1)
	end)

	it("is idempotent (double confirm is no-op)", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:confirm(TEST_ADDRESS, nonce)
		nm:confirm(TEST_ADDRESS, nonce)

		local m = nm:getMetrics()
		expect(m.totalConfirmed):toBe(1)
	end)

	it("handles confirm for unknown address gracefully", function()
		resetMocks()
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		-- Should not error
		nm:confirm("0xunknown", "0x0")
	end)

	it("confirms out-of-order nonces correctly", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		local n2 = nm:reserve(TEST_ADDRESS):expect()
		local n3 = nm:reserve(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(3)

		-- Confirm in reverse order
		nm:confirm(TEST_ADDRESS, n3)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(2)

		nm:confirm(TEST_ADDRESS, n1)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(1)

		nm:confirm(TEST_ADDRESS, n2)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: reject()
--------------------------------------------------------------------------------

describe("NonceManager - reject", function()
	it("removes nonce from pending set", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(1)

		nm:reject(TEST_ADDRESS, nonce)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)

	it("marks state as dirty when autoResync is true", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider, { autoResyncOnError = true })

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, nonce)

		expect(nm:isDirty(TEST_ADDRESS)):toBe(true)
	end)

	it("does not mark dirty when autoResync is false", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider, { autoResyncOnError = false })

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, nonce)

		expect(nm:isDirty(TEST_ADDRESS)):toBe(false)
	end)

	it("increments rejected metrics", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, nonce)

		local m = nm:getMetrics()
		expect(m.totalRejected):toBe(1)
	end)

	it("is idempotent (double reject is no-op for metrics)", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonce = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, nonce)
		nm:reject(TEST_ADDRESS, nonce)

		local m = nm:getMetrics()
		expect(m.totalRejected):toBe(1)
	end)

	it("handles reject for unknown address gracefully", function()
		resetMocks()
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reject("0xunknown", "0x0")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Auto re-sync on error
--------------------------------------------------------------------------------

describe("NonceManager - auto resync", function()
	it("re-fetches on-chain nonce after reject + next reserve", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		expect(n1):toBe("0x5")

		-- Reject the nonce (simulating tx failure)
		nm:reject(TEST_ADDRESS, n1)
		expect(nm:isDirty(TEST_ADDRESS)):toBe(true)

		-- On-chain nonce is still 0x5 (tx failed, nonce didn't increment)
		-- Next reserve should re-sync
		local n2 = nm:reserve(TEST_ADDRESS):expect()
		expect(n2):toBe("0x5")
		expect(nm:isDirty(TEST_ADDRESS)):toBe(false)
	end)

	it("picks up incremented on-chain nonce after partial success", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		local n2 = nm:reserve(TEST_ADDRESS):expect()

		-- n1 succeeded (nonce 5 used), n2 failed
		nm:confirm(TEST_ADDRESS, n1)
		nm:reject(TEST_ADDRESS, n2)

		-- On-chain nonce advanced to 6 (nonce 5 was used)
		onChainNonce = "0x6"

		local n3 = nm:reserve(TEST_ADDRESS):expect()
		expect(n3):toBe("0x6")
	end)

	it("clears pending on resync", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(3)

		-- Reject one to mark dirty
		nm:reject(TEST_ADDRESS, "0x5")

		-- Next reserve triggers resync which clears pending
		nm:reserve(TEST_ADDRESS):expect()
		-- After resync: 1 pending (the new one just reserved)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(1)
	end)

	it("increments resync counter", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, n1)

		-- Trigger resync
		nm:reserve(TEST_ADDRESS):expect()

		local m = nm:getMetrics()
		expect(m.totalResyncs):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Parallel nonce reservation
--------------------------------------------------------------------------------

describe("NonceManager - parallel reservation", function()
	it("reserves sequential nonces for parallel transactions", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonces = {}
		for i = 1, 5 do
			nonces[i] = nm:reserve(TEST_ADDRESS):expect()
		end

		expect(nonces[1]):toBe("0x0")
		expect(nonces[2]):toBe("0x1")
		expect(nonces[3]):toBe("0x2")
		expect(nonces[4]):toBe("0x3")
		expect(nonces[5]):toBe("0x4")
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(5)
	end)

	it("allows confirming all parallel nonces", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local nonces = {}
		for i = 1, 3 do
			nonces[i] = nm:reserve(TEST_ADDRESS):expect()
		end

		for _, nonce in nonces do
			nm:confirm(TEST_ADDRESS, nonce)
		end

		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
		local m = nm:getMetrics()
		expect(m.totalConfirmed):toBe(3)
	end)

	it("handles mixed confirm/reject in parallel", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		local n2 = nm:reserve(TEST_ADDRESS):expect()
		local n3 = nm:reserve(TEST_ADDRESS):expect()

		nm:confirm(TEST_ADDRESS, n1)
		nm:reject(TEST_ADDRESS, n2)
		nm:confirm(TEST_ADDRESS, n3) -- This would fail on-chain but test local tracking

		local m = nm:getMetrics()
		expect(m.totalConfirmed):toBe(2)
		expect(m.totalRejected):toBe(1)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Backpressure
--------------------------------------------------------------------------------

describe("NonceManager - backpressure", function()
	it("rejects when maxPendingNonces is reached", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider, { maxPendingNonces = 3 })

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		-- 4th reserve should fail
		local p = nm:reserve(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("allows new reservations after confirms reduce pending count", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider, { maxPendingNonces = 2 })

		local n1 = nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		-- Can't reserve more
		local p = nm:reserve(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")

		-- Confirm one to free space
		nm:confirm(TEST_ADDRESS, n1)

		-- Now we can reserve again
		local n3 = nm:reserve(TEST_ADDRESS):expect()
		expect(n3):toBe("0x2")
	end)

	it("uses default maxPendingNonces of 10", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		for _ = 1, 10 do
			nm:reserve(TEST_ADDRESS):expect()
		end

		-- 11th should fail
		local p = nm:reserve(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: resync()
--------------------------------------------------------------------------------

describe("NonceManager - resync", function()
	it("fetches fresh on-chain nonce", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()

		-- On-chain nonce advances
		onChainNonce = "0x10"

		local result = nm:resync(TEST_ADDRESS):expect()
		expect(result):toBe("0x10")
	end)

	it("resets next nonce to on-chain value", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		-- Reserve some nonces
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		-- Resync
		onChainNonce = "0x6"
		nm:resync(TEST_ADDRESS):expect()

		-- Next reserve should start from on-chain nonce
		local next = nm:reserve(TEST_ADDRESS):expect()
		expect(next):toBe("0x6")
	end)

	it("clears all pending nonces", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(2)

		nm:resync(TEST_ADDRESS):expect()
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)

	it("clears dirty flag", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n = nm:reserve(TEST_ADDRESS):expect()
		nm:reject(TEST_ADDRESS, n)
		expect(nm:isDirty(TEST_ADDRESS)):toBe(true)

		nm:resync(TEST_ADDRESS):expect()
		expect(nm:isDirty(TEST_ADDRESS)):toBe(false)
	end)

	it("increments resync metrics", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:resync(TEST_ADDRESS):expect()
		nm:resync(TEST_ADDRESS):expect()

		local m = nm:getMetrics()
		expect(m.totalResyncs):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: reset()
--------------------------------------------------------------------------------

describe("NonceManager - reset", function()
	it("resets a specific address", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(true)

		nm:reset(TEST_ADDRESS)
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(false)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)

	it("does not affect other addresses", function()
		resetMocks()
		local callCount = 0
		mockHandlers["starknet_getNonce"] = function(_params)
			callCount += 1
			return "0x" .. string.format("%x", callCount)
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS_2):expect()

		nm:reset(TEST_ADDRESS)
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(false)
		expect(nm:isInitialized(TEST_ADDRESS_2)):toBe(true)
	end)

	it("resets all addresses when no address provided", function()
		resetMocks()
		local callCount = 0
		mockHandlers["starknet_getNonce"] = function(_params)
			callCount += 1
			return "0x" .. string.format("%x", callCount)
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS_2):expect()

		nm:reset()
		expect(nm:isInitialized(TEST_ADDRESS)):toBe(false)
		expect(nm:isInitialized(TEST_ADDRESS_2)):toBe(false)
	end)

	it("causes next reserve to re-fetch from chain", function()
		resetMocks()
		onChainNonce = "0x5"
		requestLog = {}
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()
		nm:reset(TEST_ADDRESS)

		-- Change on-chain nonce
		onChainNonce = "0xa"

		local result = nm:reserve(TEST_ADDRESS):expect()
		expect(result):toBe("0xa")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: peekNextNonce()
--------------------------------------------------------------------------------

describe("NonceManager - peekNextNonce", function()
	it("returns nil for uninitialized address", function()
		resetMocks()
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		expect(nm:peekNextNonce(TEST_ADDRESS)):toBe(nil)
	end)

	it("returns next nonce without consuming it", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()

		expect(nm:peekNextNonce(TEST_ADDRESS)):toBe("0x6")

		-- Should still return 0x6 (peek doesn't consume)
		expect(nm:peekNextNonce(TEST_ADDRESS)):toBe("0x6")

		-- Reserve should get 0x6
		local n = nm:reserve(TEST_ADDRESS):expect()
		expect(n):toBe("0x6")

		-- Now peek should show 0x7
		expect(nm:peekNextNonce(TEST_ADDRESS)):toBe("0x7")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Error handling
--------------------------------------------------------------------------------

describe("NonceManager - error handling", function()
	it("rejects reserve when getNonce RPC fails", function()
		resetMocks()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("RPC node unreachable")
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local p = nm:reserve(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("rejects resync when getNonce RPC fails", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		nm:reserve(TEST_ADDRESS):expect()

		-- Make RPC fail
		mockHandlers["starknet_getNonce"] = function(_params)
			error("connection refused")
		end

		local p = nm:resync(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("remains usable after reserve failure", function()
		resetMocks()
		local failOnce = true
		mockHandlers["starknet_getNonce"] = function(_params)
			if failOnce then
				failOnce = false
				error("temporary failure")
			end
			return "0x3"
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		-- First reserve fails
		local p1 = nm:reserve(TEST_ADDRESS)
		expect(p1:getStatus()):toBe("Rejected")

		-- Second reserve should succeed (retries fetch)
		local n = nm:reserve(TEST_ADDRESS):expect()
		expect(n):toBe("0x3")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Provider integration
--------------------------------------------------------------------------------

describe("NonceManager - provider integration", function()
	it("provider creates NonceManager when enableNonceManager is true", function()
		resetMocks()
		local provider = createTestProvider(true)
		local nm = provider:getNonceManager()
		expect(nm):toBeTruthy()
	end)

	it("provider does not create NonceManager when disabled", function()
		resetMocks()
		local provider = createTestProvider(false)
		local nm = provider:getNonceManager()
		expect(nm):toBe(nil)
	end)

	it("provider passes config to NonceManager", function()
		resetMocks()
		local provider = createTestProvider(true, { maxPendingNonces = 3 })
		;(provider :: any)._PromiseModule = MockPromise

		local nm = provider:getNonceManager()
		onChainNonce = "0x0"

		-- Reserve 3 should work
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()
		nm:reserve(TEST_ADDRESS):expect()

		-- 4th should fail (maxPendingNonces = 3)
		local p = nm:reserve(TEST_ADDRESS)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("provider metrics include nonce manager metrics", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local nm = provider:getNonceManager()
		local n = nm:reserve(TEST_ADDRESS):expect()
		nm:confirm(TEST_ADDRESS, n)

		local metrics = provider:getMetrics()
		expect(metrics.nonceReserved):toBe(1)
		expect(metrics.nonceConfirmed):toBe(1)
		expect(metrics.nonceRejected):toBe(0)
		expect(metrics.nonceResyncs):toBe(0)
	end)

	it("provider metrics show zero nonce stats when disabled", function()
		resetMocks()
		local provider = createTestProvider(false)

		local metrics = provider:getMetrics()
		expect(metrics.nonceReserved):toBe(0)
		expect(metrics.nonceConfirmed):toBe(0)
		expect(metrics.nonceRejected):toBe(0)
		expect(metrics.nonceResyncs):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Account integration
--------------------------------------------------------------------------------

describe("NonceManager - Account integration", function()
	it("Account uses NonceManager when enabled on provider", function()
		resetMocks()
		onChainNonce = "0x5"
		requestLog = {}
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()

		-- Verify that the nonce was managed
		local nm = provider:getNonceManager()
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(1)
		expect(m.totalConfirmed):toBe(1)
	end)

	it("Account increments nonces for sequential transactions", function()
		resetMocks()
		onChainNonce = "0x0"
		requestLog = {}
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()

		-- Execute 3 transactions
		account:execute(calls):expect()
		account:execute(calls):expect()
		account:execute(calls):expect()

		-- Verify nonces were sequential in submitted transactions
		local submittedNonces: { string } = {}
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				local tx = entry.params[1]
				table.insert(submittedNonces, tx.nonce)
			end
		end

		expect(#submittedNonces):toBe(3)
		expect(submittedNonces[1]):toBe("0x0")
		expect(submittedNonces[2]):toBe("0x1")
		expect(submittedNonces[3]):toBe("0x2")

		-- Should only fetch getNonce once (on first reserve)
		local nonceCallCount = 0
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				nonceCallCount += 1
			end
		end
		expect(nonceCallCount):toBe(1)
	end)

	it("Account bypasses NonceManager when explicit nonce provided", function()
		resetMocks()
		onChainNonce = "0x5"
		requestLog = {}
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls, { nonce = "0xff" }):expect()
		expect(result.transactionHash):toBeTruthy()

		-- Verify the explicit nonce was used
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				local tx = entry.params[1]
				expect(tx.nonce):toBe("0xff")
			end
		end

		-- NonceManager should not have been used
		local nm = provider:getNonceManager()
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(0)
	end)

	it("Account rejects nonce on transaction failure", function()
		resetMocks()
		onChainNonce = "0x5"
		mockHandlers["starknet_addInvokeTransaction"] = function(_params)
			error("insufficient funds")
		end
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local p = account:execute(calls)
		expect(p:getStatus()):toBe("Rejected")

		-- Verify nonce was rejected
		local nm = provider:getNonceManager()
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(1)
		expect(m.totalRejected):toBe(1)
		expect(m.totalConfirmed):toBe(0)
	end)

	it("Account resyncs after rejection and retries correctly", function()
		resetMocks()
		onChainNonce = "0x5"
		local submitCallCount = 0
		mockHandlers["starknet_addInvokeTransaction"] = function(_params)
			submitCallCount += 1
			if submitCallCount == 1 then
				error("nonce too low")
			end
			return { transaction_hash = "0xsuccess" }
		end

		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()

		-- First tx fails
		local p1 = account:execute(calls)
		expect(p1:getStatus()):toBe("Rejected")

		-- On-chain nonce may have advanced
		onChainNonce = "0x6"

		-- Second tx should resync and succeed
		local result = account:execute(calls):expect()
		expect(result.transactionHash):toBe("0xsuccess")

		-- Verify metrics
		local nm = provider:getNonceManager()
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(2)
		expect(m.totalRejected):toBe(1)
		expect(m.totalConfirmed):toBe(1)
		expect(m.totalResyncs):toBe(1) -- Resync happened on 2nd reserve because of dirty state
	end)

	it("Account works normally without NonceManager", function()
		resetMocks()
		onChainNonce = "0x5"
		requestLog = {}
		local provider = createTestProvider(false)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result.transactionHash):toBeTruthy()

		-- Should have fetched nonce from provider directly
		local nonceCallCount = 0
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				nonceCallCount += 1
			end
		end
		expect(nonceCallCount):toBe(1)
	end)

	it("Account supports dryRun with NonceManager", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider(true)
		;(provider :: any)._PromiseModule = MockPromise

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()

		-- dryRun still confirms the nonce (builder returns success)
		local nm = provider:getNonceManager()
		local m = nm:getMetrics()
		expect(m.totalReserved):toBe(1)
		expect(m.totalConfirmed):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Edge cases
--------------------------------------------------------------------------------

describe("NonceManager - edge cases", function()
	it("handles large nonce values", function()
		resetMocks()
		onChainNonce = "0xfffff"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n = nm:reserve(TEST_ADDRESS):expect()
		expect(n):toBe("0xfffff")

		local n2 = nm:reserve(TEST_ADDRESS):expect()
		expect(n2):toBe("0x100000")
	end)

	it("handles nonce 0", function()
		resetMocks()
		onChainNonce = "0x0"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n = nm:reserve(TEST_ADDRESS):expect()
		expect(n):toBe("0x0")

		nm:confirm(TEST_ADDRESS, n)
		expect(nm:getPendingCount(TEST_ADDRESS)):toBe(0)
	end)

	it("old pending confirm after resync is harmless", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local oldNonce = nm:reserve(TEST_ADDRESS):expect()

		-- Resync clears pending
		nm:resync(TEST_ADDRESS):expect()

		-- Old nonce confirm is a no-op (not in pending set)
		nm:confirm(TEST_ADDRESS, oldNonce)
		local m = nm:getMetrics()
		-- Should not increment confirmed since nonce was cleared from pending by resync
		expect(m.totalConfirmed):toBe(0)
	end)

	it("old pending reject after resync is harmless", function()
		resetMocks()
		onChainNonce = "0x5"
		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider, { autoResyncOnError = false })

		local oldNonce = nm:reserve(TEST_ADDRESS):expect()

		nm:resync(TEST_ADDRESS):expect()

		-- Old reject is a no-op
		nm:reject(TEST_ADDRESS, oldNonce)
		local m = nm:getMetrics()
		expect(m.totalRejected):toBe(0)
	end)

	it("multiple addresses can have independent nonce tracking", function()
		resetMocks()
		local addrCallCount = 0
		mockHandlers["starknet_getNonce"] = function(params)
			addrCallCount += 1
			if addrCallCount == 1 then
				return "0x1"
			end
			return "0x100"
		end

		local provider = createTestProvider()
		;(provider :: any)._PromiseModule = MockPromise
		local nm = NonceManager.new(provider)

		local n1a = nm:reserve(TEST_ADDRESS):expect()
		local n2a = nm:reserve(TEST_ADDRESS_2):expect()
		local n1b = nm:reserve(TEST_ADDRESS):expect()
		local n2b = nm:reserve(TEST_ADDRESS_2):expect()

		expect(n1a):toBe("0x1")
		expect(n1b):toBe("0x2")
		expect(n2a):toBe("0x100")
		expect(n2b):toBe("0x101")
	end)
end)
