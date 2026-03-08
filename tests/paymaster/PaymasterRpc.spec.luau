--!strict
local serde = require("@lune/serde")

local PaymasterRpc = require("../../src/paymaster/PaymasterRpc")
local MockPromise = require("../helpers/MockPromise")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Mock RPC layer (shared infrastructure from TestUtils)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

--- Install paymaster-specific default handlers (called after rpc.resetHandlers())
local function resetHandlers()
	rpc.resetHandlers()

	mockHandlers["paymaster_isAvailable"] = function(_params)
		return true
	end

	mockHandlers["paymaster_getSupportedTokens"] = function(_params)
		return {
			{
				token_address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				decimals = 18,
				price_in_strk = "0x3e8",
			},
			{
				token_address = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
				decimals = 18,
				price_in_strk = "0x1",
			},
		}
	end

	mockHandlers["paymaster_buildTypedData"] = function(params: any)
		local transaction = params[1]
		local _parameters = params[2]
		local userAddr = if transaction.invoke then transaction.invoke.user_address else transaction.deploy_and_invoke.user_address

		return {
			typed_data = {
				types = {
					StarknetDomain = {
						{ name = "name", type = "shortstring" },
						{ name = "version", type = "shortstring" },
						{ name = "chainId", type = "shortstring" },
						{ name = "revision", type = "shortstring" },
					},
					OutsideExecution = {
						{ name = "Caller", type = "ContractAddress" },
						{ name = "Nonce", type = "felt" },
						{ name = "Execute After", type = "u128" },
						{ name = "Execute Before", type = "u128" },
						{ name = "Calls", type = "Call*" },
					},
					Call = {
						{ name = "To", type = "ContractAddress" },
						{ name = "Selector", type = "selector" },
						{ name = "Calldata", type = "felt*" },
					},
				},
				primaryType = "OutsideExecution",
				domain = {
					name = "Account.execute_from_outside",
					version = "2",
					chainId = "SN_SEPOLIA",
					revision = "1",
				},
				message = {
					Caller = "0x414e595f43414c4c4552",
					Nonce = "0x1",
					["Execute After"] = "0x0",
					["Execute Before"] = "0xffffffffffffffff",
					Calls = {},
				},
			},
			fee_estimate = {
				gas_token_price = "0x3e8",
				estimated_fee_in_strk = "0x2710",
				estimated_fee_in_gas_token = "0x9c40",
				suggested_max_fee_in_strk = "0x3a98",
				suggested_max_fee_in_gas_token = "0xea60",
			},
		}
	end

	mockHandlers["paymaster_executeTransaction"] = function(params: any)
		return {
			tracking_id = "track-12345",
			transaction_hash = "0xabc123def456",
		}
	end

	mockHandlers["paymaster_trackingIdToLatestHash"] = function(params: any)
		return {
			transaction_hash = "0xabc123def456",
			status = "accepted",
		}
	end
end

--- Create a paymaster-specific mock HTTP function that also logs headers
local function createMockPaymasterHttpRequest(): (request: any) -> any
	local baseHttpRequest = rpc.createMockHttpRequest()
	return function(request: any): any
		-- Capture headers in requestLog (the base mock already logs method/params)
		local response = baseHttpRequest(request)
		-- Patch the last requestLog entry to include headers
		if #requestLog > 0 then
			requestLog[#requestLog].headers = request.Headers
		end
		return response
	end
end

--------------------------------------------------------------------------------
-- Helper: create a test paymaster
--------------------------------------------------------------------------------

local function createTestPaymaster(overrides: { [string]: any }?): any
	local config: any = {
		nodeUrl = "http://mock-paymaster.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockPaymasterHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
	}

	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local paymaster = PaymasterRpc.new(config)
	;(paymaster :: any)._PromiseModule = MockPromise
	return paymaster
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

resetHandlers()

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("PaymasterRpc - constructor", function()
	it("creates a paymaster client with valid nodeUrl", function()
		local pm = createTestPaymaster()
		expect(pm):toBeTruthy()
	end)

	it("stores the configured nodeUrl", function()
		local pm = createTestPaymaster()
		expect(pm:getNodeUrl()):toBe("http://mock-paymaster.test")
	end)

	it("errors on empty nodeUrl", function()
		expect(function()
			PaymasterRpc.new({ nodeUrl = "" } :: any)
		end):toThrowType("ValidationError")
	end)

	it("errors on missing nodeUrl", function()
		expect(function()
			PaymasterRpc.new({} :: any)
		end):toThrowType("ValidationError")
	end)

	it("accepts custom headers", function()
		local pm = createTestPaymaster({ headers = { ["x-paymaster-api-key"] = "test-key" } })
		expect(pm):toBeTruthy()
	end)

	it("defaults retryAttempts to 3", function()
		local config: any = {
			nodeUrl = "http://mock-paymaster.test",
			_httpRequest = createMockPaymasterHttpRequest(),
			_sleep = function(_s: number) end,
			_clock = os.clock,
		}
		local pm = PaymasterRpc.new(config)
		expect((pm :: any)._client._retryAttempts):toBe(3)
	end)

	it("defaults retryDelay to 1", function()
		local config: any = {
			nodeUrl = "http://mock-paymaster.test",
			_httpRequest = createMockPaymasterHttpRequest(),
			_sleep = function(_s: number) end,
			_clock = os.clock,
		}
		local pm = PaymasterRpc.new(config)
		expect((pm :: any)._client._retryDelay):toBe(1)
	end)
end)

describe("PaymasterRpc - isAvailable", function()
	it("returns true when paymaster is available", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:isAvailable():expect()
		expect(result):toBe(true)
	end)

	it("returns false when paymaster returns false", function()
		resetHandlers()
		mockHandlers["paymaster_isAvailable"] = function(_params)
			return false
		end
		local pm = createTestPaymaster()
		local result = pm:isAvailable():expect()
		expect(result):toBe(false)
	end)

	it("returns false when paymaster is unreachable", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 503,
					Body = "Service Unavailable",
					Success = false,
				}
			end,
		})
		local result = pm:isAvailable():expect()
		expect(result):toBe(false)
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:isAvailable():expect()
		expect(#requestLog >= 1):toBe(true)
		expect(requestLog[#requestLog].method):toBe("paymaster_isAvailable")
	end)
end)

describe("PaymasterRpc - getSupportedTokens", function()
	it("returns a list of supported tokens", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local tokens = pm:getSupportedTokens():expect()
		expect(type(tokens)):toBe("table")
		expect(#tokens):toBe(2)
	end)

	it("normalizes snake_case response to camelCase", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local tokens = pm:getSupportedTokens():expect()
		local eth = tokens[1]
		expect(eth.tokenAddress):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
		expect(eth.decimals):toBe(18)
		expect(eth.priceInStrk):toBe("0x3e8")
	end)

	it("handles second token correctly", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local tokens = pm:getSupportedTokens():expect()
		local strk = tokens[2]
		expect(strk.tokenAddress):toBe("0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d")
		expect(strk.decimals):toBe(18)
		expect(strk.priceInStrk):toBe("0x1")
	end)

	it("handles empty token list", function()
		resetHandlers()
		mockHandlers["paymaster_getSupportedTokens"] = function(_params)
			return {}
		end
		local pm = createTestPaymaster()
		local tokens = pm:getSupportedTokens():expect()
		expect(#tokens):toBe(0)
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:getSupportedTokens():expect()
		expect(requestLog[#requestLog].method):toBe("paymaster_getSupportedTokens")
	end)

	it("handles camelCase response format", function()
		resetHandlers()
		mockHandlers["paymaster_getSupportedTokens"] = function(_params)
			return {
				{
					tokenAddress = "0x049d",
					decimals = 6,
					priceInStrk = "0x100",
				},
			}
		end
		local pm = createTestPaymaster()
		local tokens = pm:getSupportedTokens():expect()
		expect(tokens[1].tokenAddress):toBe("0x049d")
		expect(tokens[1].decimals):toBe(6)
		expect(tokens[1].priceInStrk):toBe("0x100")
	end)
end)

describe("PaymasterRpc - buildTypedData", function()
	it("returns typed data for invoke transaction", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser123",
			{
				{
					contractAddress = "0xcontract",
					entrypoint = "transfer",
					calldata = { "0x1", "0x2" },
				},
			},
			"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		):expect()

		expect(result):toBeTruthy()
		expect(result.typedData):toBeTruthy()
	end)

	it("returns fee estimate", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser123",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		expect(result.feeEstimate):toBeTruthy()
		expect(result.feeEstimate.gasTokenPrice):toBe("0x3e8")
		expect(result.feeEstimate.estimatedFeeInStrk):toBe("0x2710")
		expect(result.feeEstimate.estimatedFeeInGasToken):toBe("0x9c40")
		expect(result.feeEstimate.suggestedMaxFeeInStrk):toBe("0x3a98")
		expect(result.feeEstimate.suggestedMaxFeeInGasToken):toBe("0xea60")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser123",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()
		expect(requestLog[#requestLog].method):toBe("paymaster_buildTypedData")
	end)

	it("formats calls correctly in request params", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData("0xuser123", {
			{
				contractAddress = "0xcontract1",
				entrypoint = "transfer",
				calldata = { "0xa", "0xb" },
			},
			{
				contractAddress = "0xcontract2",
				entrypoint = "approve",
				calldata = { "0xc" },
			},
		}, "0x049d"):expect()

		local params = requestLog[#requestLog].params
		local transaction = params[1]
		expect(transaction.type):toBe("INVOKE")
		local calls = transaction.invoke.calls
		expect(#calls):toBe(2)
		expect(calls[1].contract_address):toBe("0xcontract1")
		expect(calls[1].entry_point):toBe("transfer")
		expect(calls[2].contract_address):toBe("0xcontract2")
		expect(calls[2].entry_point):toBe("approve")
	end)

	it("sets default fee mode for non-zero gas token", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		local params = requestLog[#requestLog].params
		local parameters = params[2]
		expect(parameters.fee_mode.mode):toBe("default")
		expect(parameters.fee_mode.gas_token):toBe("0x049d")
	end)

	it("sets sponsored fee mode for zero gas token", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x0"
		):expect()

		local params = requestLog[#requestLog].params
		local parameters = params[2]
		expect(parameters.fee_mode.mode):toBe("sponsored")
	end)

	it("sets sponsored fee mode for empty gas token", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			""
		):expect()

		local params = requestLog[#requestLog].params
		local parameters = params[2]
		expect(parameters.fee_mode.mode):toBe("sponsored")
	end)

	it("includes deployment data for deploy-via-paymaster", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xclass1",
					calldata = { "0xpubkey" },
					salt = "0xsalt1",
					unique = true,
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local transaction = params[1]
		expect(transaction.type):toBe("DEPLOY_AND_INVOKE")
		local dd = transaction.deploy_and_invoke.deployment_data
		expect(dd.class_hash):toBe("0xclass1")
		expect(dd.salt):toBe("0xsalt1")
		expect(dd.unique):toBe(true)
		expect(dd.version):toBe(1)
	end)

	it("includes account class hash when provided without deployment data", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{ accountClassHash = "0xclass123" }
		):expect()

		local params = requestLog[#requestLog].params
		local transaction = params[1]
		expect(transaction.type):toBe("INVOKE")
		expect(transaction.invoke.account_class_hash):toBe("0xclass123")
	end)

	it("includes typed data domain and types in response", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		local td = result.typedData
		expect(td.primaryType):toBe("OutsideExecution")
		expect(td.domain.name):toBe("Account.execute_from_outside")
		expect(td.domain.version):toBe("2")
		expect(td.domain.chainId):toBe("SN_SEPOLIA")
	end)

	it("sets version parameter to 0x1", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		local params = requestLog[#requestLog].params
		expect(params[2].version):toBe("0x1")
	end)

	it("handles nil options gracefully", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			nil
		):expect()
		expect(result.typedData):toBeTruthy()
	end)
end)

describe("PaymasterRpc - executeTransaction", function()
	it("returns transaction hash and tracking id", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:executeTransaction(
			"0xuser123",
			{ types = {}, primaryType = "OutsideExecution", domain = {}, message = {} },
			{ "0xr", "0xs" }
		):expect()

		expect(result.transactionHash):toBe("0xabc123def456")
		expect(result.trackingId):toBe("track-12345")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		):expect()
		expect(requestLog[#requestLog].method):toBe("paymaster_executeTransaction")
	end)

	it("passes user address and signature correctly", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser456",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xsigR", "0xsigS" }
		):expect()

		local params = requestLog[#requestLog].params
		local transaction = params[1]
		expect(transaction.type):toBe("INVOKE")
		expect(transaction.invoke.user_address):toBe("0xuser456")
		expect(transaction.invoke.signature[1]):toBe("0xsigR")
		expect(transaction.invoke.signature[2]):toBe("0xsigS")
	end)

	it("includes typed data in request", function()
		resetHandlers()
		rpc.clearRequestLog()
		local typedData = { types = { Foo = {} }, primaryType = "Foo", domain = { name = "test" }, message = {} }
		local pm = createTestPaymaster()
		pm:executeTransaction("0xuser", typedData, { "0xr", "0xs" }):expect()

		local params = requestLog[#requestLog].params
		expect(params[1].invoke.typed_data.primaryType):toBe("Foo")
	end)

	it("includes deployment data for deploy-via-paymaster", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			nil,
			{
				deploymentData = {
					classHash = "0xclass99",
					calldata = { "0xpk" },
					salt = "0xsalt99",
					unique = false,
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local transaction = params[1]
		expect(transaction.type):toBe("DEPLOY_AND_INVOKE")
		local dd = transaction.deploy_and_invoke.deployment_data
		expect(dd.class_hash):toBe("0xclass99")
		expect(dd.salt):toBe("0xsalt99")
	end)

	it("sets sponsored fee mode when gasTokenAddress is nil", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		):expect()

		local params = requestLog[#requestLog].params
		expect(params[2].fee_mode.mode):toBe("sponsored")
	end)

	it("sets sponsored fee mode when gasTokenAddress is 0x0", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			"0x0"
		):expect()

		local params = requestLog[#requestLog].params
		expect(params[2].fee_mode.mode):toBe("sponsored")
	end)

	it("sets default fee mode with gas token when gasTokenAddress is provided", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		):expect()

		local params = requestLog[#requestLog].params
		expect(params[2].fee_mode.mode):toBe("default")
		expect(params[2].fee_mode.gas_token):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)

	it("passes gasTokenAddress with deployment data options", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			{
				deploymentData = {
					classHash = "0xclass",
					calldata = { "0xpk" },
					salt = "0xsalt",
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		expect(params[1].type):toBe("DEPLOY_AND_INVOKE")
		expect(params[2].fee_mode.mode):toBe("default")
		expect(params[2].fee_mode.gas_token):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)
end)

describe("PaymasterRpc - trackingIdToLatestHash", function()
	it("returns transaction hash and status", function()
		resetHandlers()
		local pm = createTestPaymaster()
		local result = pm:trackingIdToLatestHash("track-12345"):expect()
		expect(result.transactionHash):toBe("0xabc123def456")
		expect(result.status):toBe("accepted")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:trackingIdToLatestHash("track-99"):expect()
		expect(requestLog[#requestLog].method):toBe("paymaster_trackingIdToLatestHash")
	end)

	it("passes tracking id in params", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:trackingIdToLatestHash("track-xyz"):expect()
		local params = requestLog[#requestLog].params
		expect(params[1]):toBe("track-xyz")
	end)

	it("handles active status", function()
		resetHandlers()
		mockHandlers["paymaster_trackingIdToLatestHash"] = function(_params)
			return { transaction_hash = "0x111", status = "active" }
		end
		local pm = createTestPaymaster()
		local result = pm:trackingIdToLatestHash("track-1"):expect()
		expect(result.status):toBe("active")
	end)

	it("handles dropped status", function()
		resetHandlers()
		mockHandlers["paymaster_trackingIdToLatestHash"] = function(_params)
			return { transaction_hash = "0x222", status = "dropped" }
		end
		local pm = createTestPaymaster()
		local result = pm:trackingIdToLatestHash("track-2"):expect()
		expect(result.status):toBe("dropped")
	end)
end)

describe("PaymasterRpc - error handling", function()
	it("maps INVALID_ADDRESS (150) to PAYMASTER_INVALID_ADDRESS", function()
		resetHandlers()
		mockHandlers["paymaster_buildTypedData"] = function(_params)
			error("should not reach here")
		end
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 150, message = "Invalid user address" },
					}),
					Success = true,
				}
			end,
		})

		local ok, err = pcall(function()
			pm:buildTypedData(
				"0xbad",
				{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
				"0x049d"
			):expect()
		end)
		expect(ok):toBe(false)
	end)

	it("maps TOKEN_NOT_SUPPORTED (151) to PAYMASTER_TOKEN_NOT_SUPPORTED", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 151, message = "Token not supported" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:getSupportedTokens()
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7002)
		expect(err:is("RpcError")):toBe(true)
	end)

	it("maps INVALID_SIGNATURE (153) to PAYMASTER_INVALID_SIGNATURE", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 153, message = "Invalid signature" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xbad" }
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7003)
	end)

	it("maps MAX_AMOUNT_TOO_LOW (154) to PAYMASTER_MAX_AMOUNT_TOO_LOW", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 154, message = "Max amount too low" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7004)
	end)

	it("maps CLASS_HASH_NOT_SUPPORTED (155) to PAYMASTER_CLASS_HASH_NOT_SUPPORTED", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 155, message = "Class hash not supported" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{ accountClassHash = "0xbadclass" }
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7008)
	end)

	it("maps TRANSACTION_EXECUTION_ERROR (156) to PAYMASTER_EXECUTION_ERROR", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 156, message = "Execution error", data = "revert reason" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7006)
	end)

	it("maps INVALID_DEPLOYMENT_DATA (158) to PAYMASTER_INVALID_DEPLOYMENT_DATA", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 158, message = "Invalid deployment data" },
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xbad",
					calldata = {},
					salt = "0x0",
				},
			}
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7005)
	end)

	it("maps unknown error code to PAYMASTER_ERROR", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = { code = 999, message = "Something weird happened" },
					}),
					Success = true,
				}
			end,
		})

		-- Use fetch instead of isAvailable (which swallows errors)
		local promise = pm:fetch("paymaster_getSupportedTokens", {})
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7000)
	end)

	it("handles HTTP-level errors", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 500,
					Body = "Internal Server Error",
					Success = false,
				}
			end,
		})

		-- isAvailable returns false on error instead of throwing
		local result = pm:isAvailable():expect()
		expect(result):toBe(false)
	end)

	it("HTTP errors propagate for non-isAvailable methods", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 500,
					Body = "Internal Server Error",
					Success = false,
				}
			end,
		})

		local promise = pm:getSupportedTokens()
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err:is("RpcError")):toBe(true)
		expect(err.code):toBe(2001) -- NETWORK_ERROR
	end)

	it("preserves error data from paymaster", function()
		resetHandlers()
		local pm = createTestPaymaster({
			_httpRequest = function(_request: any)
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						error = {
							code = 156,
							message = "Execution failed",
							data = { revert_reason = "insufficient balance" },
						},
					}),
					Success = true,
				}
			end,
		})

		local promise = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		)
		expect(promise:getStatus()):toBe("Rejected")
		local err = (promise :: any)._value
		expect(err.code):toBe(7006)
		expect(err.data):toBeTruthy()
		expect(err.data.revert_reason):toBe("insufficient balance")
	end)
end)

describe("PaymasterRpc - retry logic", function()
	it("retries on transient network errors", function()
		resetHandlers()
		local callCount = 0
		local pm = createTestPaymaster({
			retryAttempts = 3,
			retryDelay = 0.001,
			_httpRequest = function(request: any)
				callCount += 1
				if callCount < 3 then
					return {
						StatusCode = 502,
						Body = "Bad Gateway",
						Success = false,
					}
				end
				local body = serde.decode("json", request.Body or "{}") :: any
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						result = { { token_address = "0x1", decimals = 18, price_in_strk = "0x1" } },
					}),
					Success = true,
				}
			end,
		})

		-- Use fetch (which uses _requestWithRetry) instead of isAvailable (which uses _rawRequest)
		local tokens = pm:getSupportedTokens():expect()
		expect(#tokens):toBe(1)
		expect(callCount):toBe(3)
	end)

	it("does not retry on deterministic paymaster errors", function()
		resetHandlers()
		local callCount = 0
		local pm = createTestPaymaster({
			retryAttempts = 3,
			_httpRequest = function(_request: any)
				callCount += 1
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = callCount,
						error = { code = 151, message = "Token not supported" },
					}),
					Success = true,
				}
			end,
		})

		-- This should fail immediately without retry
		local ok, _ = pcall(function()
			pm:getSupportedTokens():expect()
		end)
		expect(ok):toBe(false)
		expect(callCount):toBe(1)
	end)

	it("does not retry on invalid signature errors", function()
		resetHandlers()
		local callCount = 0
		local pm = createTestPaymaster({
			retryAttempts = 3,
			_httpRequest = function(_request: any)
				callCount += 1
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = callCount,
						error = { code = 153, message = "Invalid signature" },
					}),
					Success = true,
				}
			end,
		})

		local ok, _ = pcall(function()
			pm:executeTransaction(
				"0xuser",
				{ types = {}, primaryType = "OE", domain = {}, message = {} },
				{ "0xr", "0xs" }
			):expect()
		end)
		expect(ok):toBe(false)
		expect(callCount):toBe(1)
	end)
end)

describe("PaymasterRpc - custom headers", function()
	it("sends custom headers with every request", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster({
			headers = {
				["x-paymaster-api-key"] = "my-secret-key",
				["X-Custom"] = "custom-value",
			},
		})
		pm:isAvailable():expect()

		local lastHeaders = requestLog[#requestLog].headers
		expect(lastHeaders["x-paymaster-api-key"]):toBe("my-secret-key")
		expect(lastHeaders["X-Custom"]):toBe("custom-value")
	end)

	it("always includes Content-Type header", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:isAvailable():expect()

		local lastHeaders = requestLog[#requestLog].headers
		expect(lastHeaders["Content-Type"]):toBe("application/json")
	end)
end)

describe("PaymasterRpc - fetch (raw)", function()
	it("can call arbitrary paymaster RPC methods", function()
		resetHandlers()
		mockHandlers["paymaster_customMethod"] = function(_params)
			return { custom = "result" }
		end
		local pm = createTestPaymaster()
		local result = pm:fetch("paymaster_customMethod", {}):expect()
		expect(result.custom):toBe("result")
	end)

	it("rejects on unknown methods", function()
		resetHandlers()
		local pm = createTestPaymaster()
		expect(function()
			pm:fetch("paymaster_unknownMethod", {}):expect()
		end):toThrow()
	end)
end)

describe("PaymasterRpc - deployment data details", function()
	it("includes sigdata when provided", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xclass",
					calldata = { "0xpk" },
					salt = "0xsalt",
					sigdata = { "0xsig1", "0xsig2" },
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local dd = params[1].deploy_and_invoke.deployment_data
		expect(dd.sigdata[1]):toBe("0xsig1")
		expect(dd.sigdata[2]):toBe("0xsig2")
	end)

	it("defaults unique to false", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xclass",
					calldata = {},
					salt = "0x0",
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local dd = params[1].deploy_and_invoke.deployment_data
		expect(dd.unique):toBe(false)
	end)

	it("defaults version to 1", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xclass",
					calldata = {},
					salt = "0x0",
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local dd = params[1].deploy_and_invoke.deployment_data
		expect(dd.version):toBe(1)
	end)

	it("allows custom version", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d",
			{
				deploymentData = {
					classHash = "0xclass",
					calldata = {},
					salt = "0x0",
					version = 2,
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local dd = params[1].deploy_and_invoke.deployment_data
		expect(dd.version):toBe(2)
	end)

	it("executeTransaction includes deployment data with sigdata", function()
		resetHandlers()
		rpc.clearRequestLog()
		local pm = createTestPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			nil,
			{
				deploymentData = {
					classHash = "0xc",
					calldata = {},
					salt = "0x0",
					sigdata = { "0xsd" },
				},
			}
		):expect()

		local params = requestLog[#requestLog].params
		local dd = params[1].deploy_and_invoke.deployment_data
		expect(dd.sigdata[1]):toBe("0xsd")
	end)
end)

describe("PaymasterRpc - response normalization", function()
	it("handles camelCase typed_data response", function()
		resetHandlers()
		mockHandlers["paymaster_buildTypedData"] = function(_params)
			return {
				typedData = { primaryType = "OutsideExecution", types = {}, domain = {}, message = {} },
				feeEstimate = {
					gasTokenPrice = "0x1",
					estimatedFeeInStrk = "0x2",
					estimatedFeeInGasToken = "0x3",
					suggestedMaxFeeInStrk = "0x4",
					suggestedMaxFeeInGasToken = "0x5",
				},
			}
		end
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		expect(result.typedData.primaryType):toBe("OutsideExecution")
		expect(result.feeEstimate.gasTokenPrice):toBe("0x1")
	end)

	it("handles missing fee estimate gracefully", function()
		resetHandlers()
		mockHandlers["paymaster_buildTypedData"] = function(_params)
			return {
				typed_data = { primaryType = "OutsideExecution", types = {}, domain = {}, message = {} },
			}
		end
		local pm = createTestPaymaster()
		local result = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x049d"
		):expect()

		expect(result.typedData):toBeTruthy()
		expect(result.feeEstimate == nil):toBe(true)
	end)

	it("handles camelCase executeTransaction response", function()
		resetHandlers()
		mockHandlers["paymaster_executeTransaction"] = function(_params)
			return {
				trackingId = "track-camel",
				transactionHash = "0xcamel123",
			}
		end
		local pm = createTestPaymaster()
		local result = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		):expect()

		expect(result.trackingId):toBe("track-camel")
		expect(result.transactionHash):toBe("0xcamel123")
	end)

	it("handles camelCase trackingIdToLatestHash response", function()
		resetHandlers()
		mockHandlers["paymaster_trackingIdToLatestHash"] = function(_params)
			return {
				transactionHash = "0xcamel456",
				status = "active",
			}
		end
		local pm = createTestPaymaster()
		local result = pm:trackingIdToLatestHash("t1"):expect()
		expect(result.transactionHash):toBe("0xcamel456")
	end)
end)
