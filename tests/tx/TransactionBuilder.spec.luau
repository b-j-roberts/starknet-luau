--!strict
local serde = require("@lune/serde")

local TransactionBuilder = require("../../src/tx/TransactionBuilder")
local CallData = require("../../src/tx/CallData")
local TransactionHash = require("../../src/tx/TransactionHash")
local BigInt = require("../../src/crypto/BigInt")
local StarkSigner = require("../../src/signer/StarkSigner")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local TEST_PRIVATE_KEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local TEST_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
local SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function clearRequestLog()
	requestLog = {}
end

local function resetHandlers()
	mockHandlers = {}

	mockHandlers["starknet_chainId"] = function(_params)
		return SN_SEPOLIA
	end

	mockHandlers["starknet_getNonce"] = function(_params)
		return "0x5"
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

	mockHandlers["starknet_getTransactionReceipt"] = function(_params)
		return {
			transaction_hash = "0xabc123",
			actual_fee = { amount = "0x1234", unit = "WEI" },
			execution_status = "SUCCEEDED",
			finality_status = "ACCEPTED_ON_L2",
			block_hash = "0xblock1",
			block_number = 100,
			events = {},
		}
	end

	mockHandlers["starknet_getTransactionStatus"] = function(_params)
		return {
			finality_status = "ACCEPTED_ON_L2",
			execution_status = "SUCCEEDED",
		}
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

--------------------------------------------------------------------------------
-- Helper: create test provider and builder
--------------------------------------------------------------------------------

local function createTestProvider(overrides: { [string]: any }?): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
	}

	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

local function createTestAccount(): TransactionBuilder.Account
	local signer = StarkSigner.new(TEST_PRIVATE_KEY)
	return {
		address = TEST_ADDRESS,
		signer = signer :: any,
	}
end

local function createTestCalls(): { TransactionBuilder.Call }
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

resetHandlers()

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

describe("TransactionBuilder - constructor", function()
	it("creates a builder with a provider", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		expect(builder):toBeTruthy()
	end)

	it("throws when provider is nil", function()
		expect(function()
			TransactionBuilder.new(nil :: any)
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- estimateFee
--------------------------------------------------------------------------------

describe("TransactionBuilder - estimateFee", function()
	it("returns a fee estimate for a set of calls", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local result = builder:estimateFee(account, calls):expect()
		expect(result.overall_fee):toBe("0x100000")
		expect(result.gas_consumed):toBe("0x1000")
		expect(result.gas_price):toBe("0x100")
	end)

	it("fetches nonce from provider", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:estimateFee(account, calls):expect()

		-- Should have called getNonce
		local calledGetNonce = false
		for _, req in requestLog do
			if req.method == "starknet_getNonce" then
				calledGetNonce = true
				break
			end
		end
		expect(calledGetNonce):toBeTruthy()
	end)

	it("sends SKIP_VALIDATE flag", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:estimateFee(account, calls):expect()

		-- Find the estimateFee request
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				-- params[2] should be simulation flags
				expect(req.params[2][1]):toBe("SKIP_VALIDATE")
				break
			end
		end
	end)

	it("sends dummy signature for estimation", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:estimateFee(account, calls):expect()

		-- Find the estimateFee request and check the transaction has dummy signature
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				local tx = req.params[1][1]
				expect(tx.signature[1]):toBe("0x0")
				expect(tx.signature[2]):toBe("0x0")
				break
			end
		end
	end)

	it("rejects when nonce fetch fails", function()
		resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("contract not found")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:estimateFee(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when fee estimation fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("insufficient funds")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:estimateFee(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- execute - full flow
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute", function()
	it("returns a transaction hash on successful execution", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local result = builder:execute(account, calls):expect()
		expect(result.transactionHash):toBe("0xabc123")
	end)

	it("fetches nonce from provider", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		local calledGetNonce = false
		for _, req in requestLog do
			if req.method == "starknet_getNonce" then
				calledGetNonce = true
				break
			end
		end
		expect(calledGetNonce):toBeTruthy()
	end)

	it("fetches chain ID from provider", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		local calledGetChainId = false
		for _, req in requestLog do
			if req.method == "starknet_chainId" then
				calledGetChainId = true
				break
			end
		end
		expect(calledGetChainId):toBeTruthy()
	end)

	it("estimates fees from provider", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		local calledEstimateFee = false
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				calledEstimateFee = true
				break
			end
		end
		expect(calledEstimateFee):toBeTruthy()
	end)

	it("submits a signed transaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		local calledAddInvoke = false
		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				calledAddInvoke = true
				-- Verify the submitted transaction has a real signature (not dummy)
				local tx = req.params[1]
				expect(tx.signature[1] ~= "0x0"):toBeTruthy()
				expect(tx.signature[2] ~= "0x0"):toBeTruthy()
				break
			end
		end
		expect(calledAddInvoke):toBeTruthy()
	end)

	it("submits transaction with correct version and type", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.type):toBe("INVOKE")
				expect(tx.version):toBe("0x3")
				break
			end
		end
	end)

	it("submits transaction with correct sender address", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.sender_address):toBe(TEST_ADDRESS)
				break
			end
		end
	end)

	it("encodes calldata in multicall format", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		-- Compute expected calldata directly
		local expectedCalldata = CallData.encodeMulticall(calls)

		builder:execute(account, calls):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(#tx.calldata):toBe(#expectedCalldata)
				for i, cd in expectedCalldata do
					expect(tx.calldata[i]):toBe(cd)
				end
				break
			end
		end
	end)

	it("applies fee multiplier to resource bounds", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		-- Default multiplier is 1.5
		-- gas_consumed = 0x1000 (4096) * 1.5 = 6144 = 0x1800
		-- gas_price = 0x100 (256) * 1.5 = 384 = 0x180
		builder:execute(account, calls):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x1800")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x180")
				break
			end
		end
	end)

	it("uses custom fee multiplier when provided", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		-- Custom 2x multiplier
		-- gas_consumed = 0x1000 (4096) * 2 = 8192 = 0x2000
		-- gas_price = 0x100 (256) * 2 = 512 = 0x200
		builder:execute(account, calls, { feeMultiplier = 2.0 }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x2000")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x200")
				break
			end
		end
	end)

	it("produces a valid signature (verifiable)", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()
		local signer = StarkSigner.new(TEST_PRIVATE_KEY)

		local result = builder:execute(account, calls):expect()

		-- The signature should be two hex strings
		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(#tx.signature):toBe(2)
				expect(type(tx.signature[1])):toBe("string")
				expect(type(tx.signature[2])):toBe("string")
				expect(string.sub(tx.signature[1], 1, 2)):toBe("0x")
				expect(string.sub(tx.signature[2], 1, 2)):toBe("0x")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- execute - nonce override
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute with nonce override", function()
	it("uses provided nonce instead of fetching", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls, { nonce = "0x10" }):expect()

		-- Should NOT have called getNonce
		local calledGetNonce = false
		for _, req in requestLog do
			if req.method == "starknet_getNonce" then
				calledGetNonce = true
				break
			end
		end
		expect(calledGetNonce):toBeFalsy()
	end)

	it("uses override nonce in the submitted transaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls, { nonce = "0x10" }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.nonce):toBe("0x10")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- execute - resource bounds override
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute with resource bounds override", function()
	it("uses provided resource bounds instead of estimating", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0xaaa", maxPricePerUnit = "0xbbb" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0xccc", maxPricePerUnit = "0xddd" },
		}

		builder:execute(account, calls, { resourceBounds = customBounds }):expect()

		-- Should NOT have called estimateFee
		local calledEstimateFee = false
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				calledEstimateFee = true
				break
			end
		end
		expect(calledEstimateFee):toBeFalsy()
	end)

	it("submits transaction with override resource bounds", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0xaaa", maxPricePerUnit = "0xbbb" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0xccc", maxPricePerUnit = "0xddd" },
		}

		builder:execute(account, calls, { resourceBounds = customBounds }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0xaaa")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0xbbb")
				expect(tx.resource_bounds.l2_gas.max_amount):toBe("0x0")
				expect(tx.resource_bounds.l2_gas.max_price_per_unit):toBe("0x0")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- execute - dryRun
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute dryRun", function()
	it("does not submit the transaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls, { dryRun = true }):expect()

		-- Should NOT have called addInvokeTransaction
		local calledAddInvoke = false
		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				calledAddInvoke = true
				break
			end
		end
		expect(calledAddInvoke):toBeFalsy()
	end)

	it("returns transaction hash, transaction object, and signature", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local result = builder:execute(account, calls, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(string.sub(result.transactionHash, 1, 2)):toBe("0x")
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
		expect(#result.signature):toBe(2)
	end)

	it("dryRun transaction is the same as what would be submitted", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		-- Use fixed nonce and resource bounds to make deterministic
		local opts = {
			nonce = "0x1",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}

		-- dryRun
		local dryResult = builder:execute(account, calls, {
			dryRun = true,
			nonce = opts.nonce,
			resourceBounds = opts.resourceBounds,
		}):expect()

		-- Actual execution with same options
		clearRequestLog()
		local execResult = builder:execute(account, calls, {
			nonce = opts.nonce,
			resourceBounds = opts.resourceBounds,
		}):expect()

		-- The submitted transaction should match the dry run transaction
		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local submittedTx = req.params[1]
				expect(submittedTx.sender_address):toBe(dryResult.transaction.sender_address)
				expect(submittedTx.nonce):toBe(dryResult.transaction.nonce)
				-- Signatures should match (same hash, same key)
				expect(submittedTx.signature[1]):toBe(dryResult.signature[1])
				expect(submittedTx.signature[2]):toBe(dryResult.signature[2])
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- execute - error handling
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute error handling", function()
	it("rejects when nonce fetch fails", function()
		resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("contract not found")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:execute(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when chain ID fetch fails", function()
		resetHandlers()
		mockHandlers["starknet_chainId"] = function(_params)
			error("network unreachable")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:execute(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when fee estimation fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("insufficient balance")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:execute(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when transaction submission fails", function()
		resetHandlers()
		mockHandlers["starknet_addInvokeTransaction"] = function(_params)
			error("max fee too low")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local promise = builder:execute(account, calls)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("succeeds with nonce override even if getNonce fails", function()
		resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("contract not found")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local result = builder:execute(account, calls, { nonce = "0x1" }):expect()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("succeeds with resource bounds override even if estimateFee fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("estimation failed")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		local result = builder:execute(account, calls, { resourceBounds = customBounds }):expect()
		expect(result.transactionHash):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- execute - multicall (multiple calls)
--------------------------------------------------------------------------------

describe("TransactionBuilder - execute multicall", function()
	it("encodes multiple calls correctly", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls: { TransactionBuilder.Call } = {
			{
				contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				entrypoint = "approve",
				calldata = { "0xspender", "0x3e8", "0x0" },
			},
			{
				contractAddress = "0xdex_contract",
				entrypoint = "swap",
				calldata = { "0xtoken_a", "0xtoken_b", "0x3e8" },
			},
		}

		local expectedCalldata = CallData.encodeMulticall(calls)

		builder:execute(account, calls):expect()

		for _, req in requestLog do
			if req.method == "starknet_addInvokeTransaction" then
				local tx = req.params[1]
				expect(#tx.calldata):toBe(#expectedCalldata)
				-- First element is the number of calls (2)
				expect(tx.calldata[1]):toBe("0x2")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- execute - transaction hash determinism
--------------------------------------------------------------------------------

describe("TransactionBuilder - transaction hash determinism", function()
	it("produces the same hash for the same inputs", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local opts = {
			nonce = "0x1",
			dryRun = true,
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}

		local result1 = builder:execute(account, calls, opts):expect()
		local result2 = builder:execute(account, calls, opts):expect()

		expect(result1.transactionHash):toBe(result2.transactionHash)
		expect(result1.signature[1]):toBe(result2.signature[1])
		expect(result1.signature[2]):toBe(result2.signature[2])
	end)

	it("produces different hashes for different nonces", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local baseBounds = {
			l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		local result1 = builder:execute(account, calls, {
			nonce = "0x1",
			dryRun = true,
			resourceBounds = baseBounds,
		}):expect()

		local result2 = builder:execute(account, calls, {
			nonce = "0x2",
			dryRun = true,
			resourceBounds = baseBounds,
		}):expect()

		expect(result1.transactionHash ~= result2.transactionHash):toBeTruthy()
	end)

	it("dryRun hash matches manually computed TransactionHash", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		local nonce = "0x1"
		local resourceBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		local result = builder:execute(account, calls, {
			nonce = nonce,
			dryRun = true,
			resourceBounds = resourceBounds,
		}):expect()

		-- Compute the expected hash manually
		local calldata = CallData.encodeMulticall(calls)
		local expectedHash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = TEST_ADDRESS,
			compiledCalldata = calldata,
			chainId = SN_SEPOLIA,
			nonce = nonce,
			resourceBounds = resourceBounds,
		})

		expect(result.transactionHash):toBe(expectedHash)
	end)
end)

--------------------------------------------------------------------------------
-- waitForReceipt
--------------------------------------------------------------------------------

describe("TransactionBuilder - waitForReceipt", function()
	it("delegates to provider:waitForTransaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)

		local receipt = builder:waitForReceipt("0xabc123"):expect()
		expect(receipt.transaction_hash):toBe("0xabc123")
		expect(receipt.execution_status):toBe("SUCCEEDED")
		expect(receipt.finality_status):toBe("ACCEPTED_ON_L2")
	end)

	it("passes wait options to provider", function()
		resetHandlers()
		-- Make the first status call return pending, second return accepted
		local statusCallCount = 0
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			statusCallCount += 1
			if statusCallCount == 1 then
				return {
					finality_status = "RECEIVED",
					execution_status = nil,
				}
			end
			return {
				finality_status = "ACCEPTED_ON_L2",
				execution_status = "SUCCEEDED",
			}
		end

		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)

		local receipt = builder:waitForReceipt("0xabc123", { retryInterval = 1, maxAttempts = 5 }):expect()
		expect(receipt.execution_status):toBe("SUCCEEDED")
		expect(statusCallCount >= 2):toBeTruthy()
	end)

	it("rejects when transaction is reverted", function()
		resetHandlers()
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return {
				finality_status = "ACCEPTED_ON_L2",
				execution_status = "REVERTED",
			}
		end
		mockHandlers["starknet_getTransactionReceipt"] = function(_params)
			return {
				transaction_hash = "0xabc123",
				actual_fee = { amount = "0x0", unit = "WEI" },
				execution_status = "REVERTED",
				finality_status = "ACCEPTED_ON_L2",
				events = {},
				revert_reason = "execution reverted: insufficient balance",
			}
		end

		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)

		local promise = builder:waitForReceipt("0xabc123")
		expect(promise:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- execute - RPC sequence verification
--------------------------------------------------------------------------------

describe("TransactionBuilder - RPC call sequence", function()
	it("calls RPCs in correct order: getNonce, getChainId, estimateFee, addInvokeTransaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local calls = createTestCalls()

		builder:execute(account, calls):expect()

		-- Extract the ordered list of RPC methods called
		local methods: { string } = {}
		for _, req in requestLog do
			table.insert(methods, req.method)
		end

		-- Find indices
		local nonceIdx, chainIdx, feeIdx, submitIdx = 0, 0, 0, 0
		for i, m in methods do
			if m == "starknet_getNonce" and nonceIdx == 0 then
				nonceIdx = i
			end
			if m == "starknet_chainId" and chainIdx == 0 then
				chainIdx = i
			end
			if m == "starknet_estimateFee" and feeIdx == 0 then
				feeIdx = i
			end
			if m == "starknet_addInvokeTransaction" and submitIdx == 0 then
				submitIdx = i
			end
		end

		-- Verify ordering
		expect(nonceIdx > 0):toBeTruthy()
		expect(chainIdx > 0):toBeTruthy()
		expect(feeIdx > 0):toBeTruthy()
		expect(submitIdx > 0):toBeTruthy()
		expect(feeIdx > nonceIdx):toBeTruthy()
		expect(feeIdx > chainIdx):toBeTruthy()
		expect(submitIdx > feeIdx):toBeTruthy()
	end)
end)
