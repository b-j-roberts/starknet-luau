--!strict
local serde = require("@lune/serde")

local TransactionBuilder = require("../../src/tx/TransactionBuilder")
local TransactionHash = require("../../src/tx/TransactionHash")
local BigInt = require("../../src/crypto/BigInt")
local StarkSigner = require("../../src/signer/StarkSigner")
local Account = require("../../src/wallet/Account")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local TEST_PRIVATE_KEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local SN_SEPOLIA = "0x534e5f5345504f4c4941"
local OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

-- Derive the public key and address for deploy tests
local TEST_SIGNER = StarkSigner.new(TEST_PRIVATE_KEY)
local TEST_PUBLIC_KEY = TEST_SIGNER:getPublicKeyHex()
local TEST_DEPLOY_ADDRESS = Account.computeAddress({
	classHash = OZ_CLASS_HASH,
	publicKey = TEST_PUBLIC_KEY,
})

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
		-- Simulate CONTRACT_NOT_FOUND for non-deployed accounts
		error("Contract not found")
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

	mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
		return { transaction_hash = "0xdeploy123", contract_address = TEST_DEPLOY_ADDRESS }
	end

	mockHandlers["starknet_addInvokeTransaction"] = function(_params)
		return { transaction_hash = "0xabc123" }
	end

	mockHandlers["starknet_getTransactionReceipt"] = function(_params)
		return {
			transaction_hash = "0xdeploy123",
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
		address = TEST_DEPLOY_ADDRESS,
		signer = signer :: any,
	}
end

local function createTestDeployParams(): TransactionBuilder.DeployAccountParams
	return {
		classHash = OZ_CLASS_HASH,
		constructorCalldata = { TEST_PUBLIC_KEY },
		addressSalt = TEST_PUBLIC_KEY,
		contractAddress = TEST_DEPLOY_ADDRESS,
	}
end

resetHandlers()

--------------------------------------------------------------------------------
-- TransactionBuilder.deployAccount - full flow
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount full flow", function()
	it("returns a transaction hash on successful deployment", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local result = builder:deployAccount(account, params):expect()
		expect(result.transactionHash):toBe("0xdeploy123")
	end)

	it("returns contract address on successful deployment", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local result = builder:deployAccount(account, params):expect()
		expect(result.contractAddress):toBe(TEST_DEPLOY_ADDRESS)
	end)

	it("fetches chain ID from provider", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

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
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		local calledEstimateFee = false
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				calledEstimateFee = true
				break
			end
		end
		expect(calledEstimateFee):toBeTruthy()
	end)

	it("submits a signed deploy account transaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		local calledAddDeploy = false
		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				calledAddDeploy = true
				local tx = req.params[1]
				-- Verify real signature (not dummy)
				expect(tx.signature[1] ~= "0x0"):toBeTruthy()
				expect(tx.signature[2] ~= "0x0"):toBeTruthy()
				break
			end
		end
		expect(calledAddDeploy):toBeTruthy()
	end)

	it("submits transaction with correct type and version", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.type):toBe("DEPLOY_ACCOUNT")
				expect(tx.version):toBe("0x3")
				break
			end
		end
	end)

	it("submits transaction with correct class hash", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.class_hash):toBe(OZ_CLASS_HASH)
				break
			end
		end
	end)

	it("submits transaction with correct constructor calldata", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(#tx.constructor_calldata):toBe(1)
				expect(tx.constructor_calldata[1]):toBe(TEST_PUBLIC_KEY)
				break
			end
		end
	end)

	it("submits transaction with correct salt", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.contract_address_salt):toBe(TEST_PUBLIC_KEY)
				break
			end
		end
	end)

	it("uses nonce 0x0 by default for new account deployments", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.nonce):toBe("0x0")
				break
			end
		end
	end)

	it("does NOT fetch nonce from provider (uses default 0x0)", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		local calledGetNonce = false
		for _, req in requestLog do
			if req.method == "starknet_getNonce" then
				calledGetNonce = true
				break
			end
		end
		expect(calledGetNonce):toBeFalsy()
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - fee estimation
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount fee estimation", function()
	it("applies default fee multiplier (1.5x)", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		-- gas_consumed = 0x1000 (4096) * 1.5 = 6144 = 0x1800
		-- gas_price = 0x100 (256) * 1.5 = 384 = 0x180
		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x1800")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x180")
				break
			end
		end
	end)

	it("applies custom fee multiplier", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		-- 2x: gas_consumed = 0x1000 * 2 = 0x2000, gas_price = 0x100 * 2 = 0x200
		builder:deployAccount(account, params, { feeMultiplier = 2.0 }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x2000")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x200")
				break
			end
		end
	end)

	it("sends DEPLOY_ACCOUNT type in fee estimation", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				local tx = req.params[1][1]
				expect(tx.type):toBe("DEPLOY_ACCOUNT")
				expect(tx.version):toBe("0x3")
				break
			end
		end
	end)

	it("sends SKIP_VALIDATE flag for estimation", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
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
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				local tx = req.params[1][1]
				expect(tx.signature[1]):toBe("0x0")
				expect(tx.signature[2]):toBe("0x0")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - resource bounds override
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount resource bounds override", function()
	it("uses provided resource bounds instead of estimating", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0xaaa", maxPricePerUnit = "0xbbb" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0xccc", maxPricePerUnit = "0xddd" },
		}

		builder:deployAccount(account, params, { resourceBounds = customBounds }):expect()

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
		local params = createTestDeployParams()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0xaaa", maxPricePerUnit = "0xbbb" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0xccc", maxPricePerUnit = "0xddd" },
		}

		builder:deployAccount(account, params, { resourceBounds = customBounds }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
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
-- deployAccount - nonce override
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount nonce override", function()
	it("uses provided nonce instead of default 0x0", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params, { nonce = "0x5" }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.nonce):toBe("0x5")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - dryRun
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount dryRun", function()
	it("does not submit the transaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params, { dryRun = true }):expect()

		local calledAddDeploy = false
		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				calledAddDeploy = true
				break
			end
		end
		expect(calledAddDeploy):toBeFalsy()
	end)

	it("returns transaction hash, transaction object, and signature", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local result = builder:deployAccount(account, params, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(string.sub(result.transactionHash, 1, 2)):toBe("0x")
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
		expect(#result.signature):toBe(2)
	end)

	it("dryRun transaction matches what would be submitted", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local opts = {
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}

		-- dryRun
		local dryResult = builder:deployAccount(account, params, {
			dryRun = true,
			nonce = opts.nonce,
			resourceBounds = opts.resourceBounds,
		}):expect()

		-- Actual execution with same options
		clearRequestLog()
		local execResult = builder:deployAccount(account, params, {
			nonce = opts.nonce,
			resourceBounds = opts.resourceBounds,
		}):expect()

		-- The submitted transaction should match the dry run
		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local submittedTx = req.params[1]
				expect(submittedTx.class_hash):toBe(dryResult.transaction.class_hash)
				expect(submittedTx.nonce):toBe(dryResult.transaction.nonce)
				expect(submittedTx.signature[1]):toBe(dryResult.signature[1])
				expect(submittedTx.signature[2]):toBe(dryResult.signature[2])
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - hash determinism
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount hash determinism", function()
	it("produces the same hash for the same inputs", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local opts = {
			nonce = "0x0",
			dryRun = true,
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}

		local result1 = builder:deployAccount(account, params, opts):expect()
		local result2 = builder:deployAccount(account, params, opts):expect()

		expect(result1.transactionHash):toBe(result2.transactionHash)
		expect(result1.signature[1]):toBe(result2.signature[1])
		expect(result1.signature[2]):toBe(result2.signature[2])
	end)

	it("dryRun hash matches manually computed TransactionHash", function()
		resetHandlers()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local nonce = "0x0"
		local resourceBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		local result = builder:deployAccount(account, params, {
			nonce = nonce,
			dryRun = true,
			resourceBounds = resourceBounds,
		}):expect()

		-- Compute expected hash manually
		local expectedHash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { TEST_PUBLIC_KEY },
			contractAddress = TEST_DEPLOY_ADDRESS,
			salt = TEST_PUBLIC_KEY,
			chainId = SN_SEPOLIA,
			nonce = nonce,
			resourceBounds = resourceBounds,
		})

		expect(result.transactionHash):toBe(expectedHash)
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - error handling
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount error handling", function()
	it("rejects when chain ID fetch fails", function()
		resetHandlers()
		mockHandlers["starknet_chainId"] = function(_params)
			error("network unreachable")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local promise = builder:deployAccount(account, params)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when fee estimation fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("insufficient balance for deploy")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local promise = builder:deployAccount(account, params)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("rejects when transaction submission fails", function()
		resetHandlers()
		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			error("class hash not declared")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local promise = builder:deployAccount(account, params)
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("succeeds with resource bounds override even if estimateFee fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("estimation failed")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		local result = builder:deployAccount(account, params, { resourceBounds = customBounds }):expect()
		expect(result.transactionHash):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- deployAccount - RPC call sequence
--------------------------------------------------------------------------------

describe("TransactionBuilder - deployAccount RPC call sequence", function()
	it("calls RPCs in correct order: getChainId, estimateFee, addDeployAccountTransaction", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:deployAccount(account, params):expect()

		local methods: { string } = {}
		for _, req in requestLog do
			table.insert(methods, req.method)
		end

		local chainIdx, feeIdx, submitIdx = 0, 0, 0
		for i, m in methods do
			if m == "starknet_chainId" and chainIdx == 0 then
				chainIdx = i
			end
			if m == "starknet_estimateFee" and feeIdx == 0 then
				feeIdx = i
			end
			if m == "starknet_addDeployAccountTransaction" and submitIdx == 0 then
				submitIdx = i
			end
		end

		expect(chainIdx > 0):toBeTruthy()
		expect(feeIdx > 0):toBeTruthy()
		expect(submitIdx > 0):toBeTruthy()
		expect(feeIdx > chainIdx):toBeTruthy()
		expect(submitIdx > feeIdx):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- estimateDeployAccountFee
--------------------------------------------------------------------------------

describe("TransactionBuilder - estimateDeployAccountFee", function()
	it("returns a fee estimate for deploy account", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local result = builder:estimateDeployAccountFee(account, params):expect()
		expect(result.overall_fee):toBe("0x100000")
		expect(result.gas_consumed):toBe("0x1000")
		expect(result.gas_price):toBe("0x100")
	end)

	it("sends DEPLOY_ACCOUNT tx type for estimation", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		builder:estimateDeployAccountFee(account, params):expect()

		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				local tx = req.params[1][1]
				expect(tx.type):toBe("DEPLOY_ACCOUNT")
				break
			end
		end
	end)

	it("rejects when fee estimation fails", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("insufficient funds")
		end
		local provider = createTestProvider()
		local builder = TransactionBuilder.new(provider)
		local account = createTestAccount()
		local params = createTestDeployParams()

		local promise = builder:estimateDeployAccountFee(account, params)
		expect(promise:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- Account.deployAccount convenience method
--------------------------------------------------------------------------------

describe("Account - deployAccount", function()
	it("deploys account via Account convenience method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.transactionHash):toBe("0xdeploy123")
	end)

	it("submits deploy with correct class hash and calldata", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount():expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.class_hash):toBe(OZ_CLASS_HASH)
				expect(#tx.constructor_calldata):toBe(1)
				expect(tx.type):toBe("DEPLOY_ACCOUNT")
				break
			end
		end
	end)

	it("supports dryRun option", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount({ dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()

		local calledAddDeploy = false
		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				calledAddDeploy = true
				break
			end
		end
		expect(calledAddDeploy):toBeFalsy()
	end)

	it("supports resource bounds override", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local customBounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x555", maxPricePerUnit = "0x666" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		account:deployAccount({ resourceBounds = customBounds }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x555")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x666")
				break
			end
		end
	end)

	it("works with Argent account type", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
			accountType = "argent",
		})

		account:deployAccount({ dryRun = true }):expect()

		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				local tx = req.params[1][1]
				-- Argent has 3-element constructor calldata: [0, pubkey, 0]
				expect(#tx.constructor_calldata):toBe(3)
				expect(tx.constructor_calldata[1]):toBe("0x0")
				expect(tx.constructor_calldata[3]):toBe("0x0")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Account.estimateDeployAccountFee
--------------------------------------------------------------------------------

describe("Account - estimateDeployAccountFee", function()
	it("returns fee estimate for deployment", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:estimateDeployAccountFee():expect()
		expect(result.overall_fee):toBe("0x100000")
		expect(result.gas_consumed):toBe("0x1000")
	end)
end)

--------------------------------------------------------------------------------
-- RpcProvider.addDeployAccountTransaction
--------------------------------------------------------------------------------

describe("RpcProvider - addDeployAccountTransaction", function()
	it("submits deploy account tx and returns transaction hash and contract address", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()

		local deployTx: RpcTypes.DeployAccountTransactionV3 = {
			type = "DEPLOY_ACCOUNT",
			version = "0x3",
			class_hash = OZ_CLASS_HASH,
			constructor_calldata = { TEST_PUBLIC_KEY },
			contract_address_salt = TEST_PUBLIC_KEY,
			signature = { "0x1", "0x2" },
			nonce = "0x0",
			resource_bounds = {
				l1_gas = { max_amount = "0x100", max_price_per_unit = "0x200" },
				l2_gas = { max_amount = "0x0", max_price_per_unit = "0x0" },
			},
			tip = "0x0",
			paymaster_data = {},
			nonce_data_availability_mode = "0x0",
			fee_data_availability_mode = "0x0",
		}

		local result = provider:addDeployAccountTransaction(deployTx):expect()
		expect(result.transaction_hash):toBe("0xdeploy123")
		expect(result.contract_address):toBe(TEST_DEPLOY_ADDRESS)
	end)

	it("sends correct RPC method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()

		local deployTx: RpcTypes.DeployAccountTransactionV3 = {
			type = "DEPLOY_ACCOUNT",
			version = "0x3",
			class_hash = OZ_CLASS_HASH,
			constructor_calldata = { TEST_PUBLIC_KEY },
			contract_address_salt = TEST_PUBLIC_KEY,
			signature = { "0x1", "0x2" },
			nonce = "0x0",
			resource_bounds = {
				l1_gas = { max_amount = "0x100", max_price_per_unit = "0x200" },
				l2_gas = { max_amount = "0x0", max_price_per_unit = "0x0" },
			},
			tip = "0x0",
			paymaster_data = {},
			nonce_data_availability_mode = "0x0",
			fee_data_availability_mode = "0x0",
		}

		provider:addDeployAccountTransaction(deployTx):expect()

		local found = false
		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				found = true
				local tx = req.params[1]
				expect(tx.type):toBe("DEPLOY_ACCOUNT")
				expect(tx.class_hash):toBe(OZ_CLASS_HASH)
				break
			end
		end
		expect(found):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Account.deployAccount - idempotency check
--------------------------------------------------------------------------------

describe("Account.deployAccount - idempotency check", function()
	it("returns early with alreadyDeployed=true when account is already deployed", function()
		resetHandlers()
		clearRequestLog()
		-- Override getNonce to succeed (simulating an already-deployed account)
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x5"
		end
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.alreadyDeployed):toBe(true)
		expect(result.contractAddress):toBe(account.address)
		expect(result.transactionHash):toBe("0x0")
	end)

	it("does not call estimateFee or addDeployAccountTransaction when already deployed", function()
		resetHandlers()
		clearRequestLog()
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x0"
		end
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount():expect()

		local calledEstimate = false
		local calledAddDeploy = false
		for _, req in requestLog do
			if req.method == "starknet_estimateFee" then
				calledEstimate = true
			end
			if req.method == "starknet_addDeployAccountTransaction" then
				calledAddDeploy = true
			end
		end
		expect(calledEstimate):toBeFalsy()
		expect(calledAddDeploy):toBeFalsy()
	end)

	it("proceeds with deployment when getNonce errors (contract not found)", function()
		resetHandlers()
		clearRequestLog()
		-- Default mock: getNonce errors → contract not deployed
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.alreadyDeployed):toBe(nil)
		expect(result.transactionHash):toBe("0xdeploy123")
		expect(result.contractAddress):toBe(account.address)
	end)

	it("idempotency check works with nonce 0x0 (freshly deployed)", function()
		resetHandlers()
		clearRequestLog()
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x0"
		end
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.alreadyDeployed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account.deployAccount - waitForConfirmation
--------------------------------------------------------------------------------

describe("Account.deployAccount - waitForConfirmation", function()
	it("waits for transaction confirmation by default", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount():expect()

		local calledGetStatus = false
		for _, req in requestLog do
			if req.method == "starknet_getTransactionStatus" then
				calledGetStatus = true
				break
			end
		end
		expect(calledGetStatus):toBeTruthy()
	end)

	it("calls getTransactionReceipt after confirmation", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount():expect()

		local calledGetReceipt = false
		for _, req in requestLog do
			if req.method == "starknet_getTransactionReceipt" then
				calledGetReceipt = true
				break
			end
		end
		expect(calledGetReceipt):toBeTruthy()
	end)

	it("does not wait when waitForConfirmation=false", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount({ waitForConfirmation = false }):expect()

		local calledGetStatus = false
		for _, req in requestLog do
			if req.method == "starknet_getTransactionStatus" then
				calledGetStatus = true
				break
			end
		end
		expect(calledGetStatus):toBeFalsy()
	end)

	it("does not wait when dryRun=true even with waitForConfirmation=true", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		account:deployAccount({ dryRun = true, waitForConfirmation = true }):expect()

		local calledGetStatus = false
		for _, req in requestLog do
			if req.method == "starknet_getTransactionStatus" then
				calledGetStatus = true
				break
			end
		end
		expect(calledGetStatus):toBeFalsy()
	end)

	it("rejects when transaction is rejected during confirmation", function()
		resetHandlers()
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return {
				finality_status = "REJECTED",
				execution_status = "REJECTED",
			}
		end
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local promise = account:deployAccount()
		expect(promise:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- Account.deployAccount - maxFee option
--------------------------------------------------------------------------------

describe("Account.deployAccount - maxFee option", function()
	it("caps resource bounds when maxFee is below estimated fee", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		-- Default estimate: gas_consumed=0x1000 * 1.5x = 0x1800, gas_price=0x100 * 1.5x = 0x180
		-- Total = 0x1800 * 0x180 = 0x240000
		-- Set maxFee = 0x100000 (below estimated total)
		-- Expected capped maxAmount = 0x100000 / 0x180 = 0xaaa (approx)
		account:deployAccount({ maxFee = "0x100000", waitForConfirmation = false }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				-- maxAmount should be less than 0x1800 (uncapped estimated amount)
				local BigIntLib = require("../../src/crypto/BigInt")
				local maxAmount = BigIntLib.fromHex(tx.resource_bounds.l1_gas.max_amount)
				local uncappedAmount = BigIntLib.fromHex("0x1800")
				expect(BigIntLib.cmp(maxAmount, uncappedAmount) < 0):toBeTruthy()
				-- maxPricePerUnit should remain 0x180 (from estimate * multiplier)
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x180")
				break
			end
		end
	end)

	it("does not cap when maxFee is above estimated fee", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		-- Total estimated fee = 0x1800 * 0x180 = 0x240000
		-- Set maxFee = 0xffffff (well above estimated total)
		account:deployAccount({ maxFee = "0xffffff", waitForConfirmation = false }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				-- Should use normal estimated bounds (not capped)
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x1800")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x180")
				break
			end
		end
	end)

	it("maxFee is ignored when resourceBounds is explicitly provided", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local customBounds = {
			l1Gas = { maxAmount = "0x9999", maxPricePerUnit = "0x8888" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}

		account:deployAccount({
			maxFee = "0x1",
			resourceBounds = customBounds,
			waitForConfirmation = false,
		}):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				-- resourceBounds takes precedence over maxFee
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x9999")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x8888")
				break
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Account.deployAccount - full orchestration flow
--------------------------------------------------------------------------------

describe("Account.deployAccount - full orchestration flow", function()
	it("executes complete flow: getNonce check, estimate, sign, submit, confirm", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.transactionHash):toBe("0xdeploy123")
		expect(result.contractAddress):toBe(account.address)

		-- Verify the full call sequence
		local methods: { string } = {}
		for _, req in requestLog do
			table.insert(methods, req.method)
		end

		-- Expected sequence: getNonce (fails), chainId, estimateFee, addDeployAccount, getStatus, getReceipt
		local getNonceIdx, chainIdx, feeIdx, submitIdx, statusIdx = 0, 0, 0, 0, 0
		for i, m in methods do
			if m == "starknet_getNonce" and getNonceIdx == 0 then
				getNonceIdx = i
			end
			if m == "starknet_chainId" and chainIdx == 0 then
				chainIdx = i
			end
			if m == "starknet_estimateFee" and feeIdx == 0 then
				feeIdx = i
			end
			if m == "starknet_addDeployAccountTransaction" and submitIdx == 0 then
				submitIdx = i
			end
			if m == "starknet_getTransactionStatus" and statusIdx == 0 then
				statusIdx = i
			end
		end

		expect(getNonceIdx > 0):toBeTruthy()
		expect(chainIdx > getNonceIdx):toBeTruthy()
		expect(feeIdx > chainIdx):toBeTruthy()
		expect(submitIdx > feeIdx):toBeTruthy()
		expect(statusIdx > submitIdx):toBeTruthy()
	end)

	it("returns contractAddress in result", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount():expect()
		expect(result.contractAddress):toBe(TEST_DEPLOY_ADDRESS)
	end)

	it("preserves dryRun result shape with contractAddress", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		local result = account:deployAccount({ dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
		expect(result.contractAddress):toBe(TEST_DEPLOY_ADDRESS)
	end)

	it("works with Argent account type end-to-end", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
			accountType = "argent",
		})

		local result = account:deployAccount({ waitForConfirmation = false }):expect()
		expect(result.transactionHash):toBe("0xdeploy123")
		expect(result.contractAddress):toBeTruthy()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				-- Argent has 3-element constructor calldata: [0, pubkey, 0]
				expect(#tx.constructor_calldata):toBe(3)
				expect(tx.constructor_calldata[1]):toBe("0x0")
				break
			end
		end
	end)

	it("works with Braavos account type end-to-end", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
			accountType = "braavos",
		})

		local result = account:deployAccount({ waitForConfirmation = false }):expect()
		expect(result.transactionHash):toBe("0xdeploy123")
		expect(result.contractAddress):toBeTruthy()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				-- Braavos has 1-element constructor calldata: [publicKey]
				expect(#tx.constructor_calldata):toBe(1)
				break
			end
		end
	end)

	it("supports feeMultiplier option", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = TEST_PRIVATE_KEY,
			provider = provider,
		})

		-- 2x: gas_consumed = 0x1000 * 2 = 0x2000, gas_price = 0x100 * 2 = 0x200
		account:deployAccount({ feeMultiplier = 2.0, waitForConfirmation = false }):expect()

		for _, req in requestLog do
			if req.method == "starknet_addDeployAccountTransaction" then
				local tx = req.params[1]
				expect(tx.resource_bounds.l1_gas.max_amount):toBe("0x2000")
				expect(tx.resource_bounds.l1_gas.max_price_per_unit):toBe("0x200")
				break
			end
		end
	end)
end)
