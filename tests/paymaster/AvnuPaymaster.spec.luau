--!strict
local serde = require("@lune/serde")

local AvnuPaymaster = require("../../src/paymaster/AvnuPaymaster")
local MockPromise = require("../helpers/MockPromise")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Shared mock RPC layer
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers

--------------------------------------------------------------------------------
-- Paymaster-specific handler defaults
--------------------------------------------------------------------------------

local function resetPaymasterHandlers()
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
			{
				token_address = "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8",
				decimals = 6,
				price_in_strk = "0x500",
			},
		}
	end

	mockHandlers["paymaster_buildTypedData"] = function(params: any)
		local transaction = params[1]
		local _userAddr = if transaction.invoke
			then transaction.invoke.user_address
			else transaction.deploy_and_invoke.user_address

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

	mockHandlers["paymaster_executeTransaction"] = function(_params)
		return {
			tracking_id = "track-avnu-123",
			transaction_hash = "0xavnu456",
		}
	end

	mockHandlers["paymaster_trackingIdToLatestHash"] = function(_params)
		return {
			transaction_hash = "0xavnu456",
			status = "accepted",
		}
	end
end

--------------------------------------------------------------------------------
-- Paymaster-specific mock HTTP (captures headers in requestLog)
--------------------------------------------------------------------------------

local function createMockPaymasterHttpRequest(): (request: any) -> any
	return function(request: any): any
		local body = serde.decode("json", request.Body or "{}") :: any
		local method: string = body.method or ""
		local params: any = body.params
		local id: number = body.id or 0

		table.insert(rpc.requestLog, { method = method, params = params, headers = request.Headers })

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
-- Helper: create a test AvnuPaymaster
--------------------------------------------------------------------------------

local function createTestAvnuPaymaster(overrides: { [string]: any }?): any
	local config: any = {
		network = "sepolia",
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

	local pm = AvnuPaymaster.new(config);
	(pm :: any)._inner._PromiseModule = MockPromise
	return pm
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

resetPaymasterHandlers()

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("AvnuPaymaster - constructor", function()
	it("creates an AVNU paymaster with sepolia network", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		expect(pm):toBeTruthy()
		expect(pm:getNetwork()):toBe("sepolia")
	end)

	it("creates an AVNU paymaster with mainnet network", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		expect(pm):toBeTruthy()
		expect(pm:getNetwork()):toBe("mainnet")
	end)

	it("auto-selects sepolia endpoint URL", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		expect(pm:getNodeUrl()):toBe("https://sepolia.paymaster.avnu.fi")
	end)

	it("auto-selects mainnet endpoint URL", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		expect(pm:getNodeUrl()):toBe("https://starknet.paymaster.avnu.fi")
	end)

	it("allows custom nodeUrl override", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ nodeUrl = "https://custom-paymaster.example.com" })
		expect(pm:getNodeUrl()):toBe("https://custom-paymaster.example.com")
	end)

	it("errors on missing network", function()
		expect(function()
			AvnuPaymaster.new({ _httpRequest = createMockPaymasterHttpRequest() } :: any)
		end):toThrowType("ValidationError")
	end)

	it("errors on empty network", function()
		expect(function()
			AvnuPaymaster.new({ network = "", _httpRequest = createMockPaymasterHttpRequest() } :: any)
		end):toThrowType("ValidationError")
	end)

	it("errors on unknown network without custom nodeUrl", function()
		expect(function()
			AvnuPaymaster.new({ network = "goerli", _httpRequest = createMockPaymasterHttpRequest() } :: any)
		end):toThrowType("ValidationError")
	end)

	it("allows unknown network with custom nodeUrl", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
			network = "custom-devnet",
			nodeUrl = "http://localhost:5050/paymaster",
		})
		expect(pm:getNetwork()):toBe("custom-devnet")
		expect(pm:getNodeUrl()):toBe("http://localhost:5050/paymaster")
	end)
end)

describe("AvnuPaymaster - API key and sponsored mode", function()
	it("is not sponsored without apiKey", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		expect(pm:isSponsored()):toBe(false)
	end)

	it("is sponsored with apiKey", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ apiKey = "my-avnu-api-key" })
		expect(pm:isSponsored()):toBe(true)
	end)

	it("is not sponsored with empty apiKey", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ apiKey = "" })
		expect(pm:isSponsored()):toBe(false)
	end)

	it("sends x-paymaster-api-key header when apiKey is set", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster({ apiKey = "secret-key-123" })
		pm:isAvailable():expect()

		expect(#rpc.requestLog >= 1):toBe(true)
		local lastHeaders = rpc.requestLog[#rpc.requestLog].headers
		expect(lastHeaders["x-paymaster-api-key"]):toBe("secret-key-123")
	end)

	it("does not send x-paymaster-api-key header without apiKey", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster()
		pm:isAvailable():expect()

		local lastHeaders = rpc.requestLog[#rpc.requestLog].headers
		expect(lastHeaders["x-paymaster-api-key"]):toBe(nil)
	end)

	it("always includes Content-Type header", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster({ apiKey = "key" })
		pm:isAvailable():expect()

		local lastHeaders = rpc.requestLog[#rpc.requestLog].headers
		expect(lastHeaders["Content-Type"]):toBe("application/json")
	end)
end)

describe("AvnuPaymaster - known token addresses", function()
	it("returns known mainnet tokens", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens = pm:getKnownTokens()
		expect(tokens.ETH):toBeTruthy()
		expect(tokens.STRK):toBeTruthy()
		expect(tokens.USDC):toBeTruthy()
		expect(tokens.USDT):toBeTruthy()
	end)

	it("returns known sepolia tokens", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "sepolia" })
		local tokens = pm:getKnownTokens()
		expect(tokens.ETH):toBeTruthy()
		expect(tokens.STRK):toBeTruthy()
	end)

	it("sepolia does not have USDC/USDT", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "sepolia" })
		local tokens = pm:getKnownTokens()
		expect(tokens.USDC):toBe(nil)
		expect(tokens.USDT):toBe(nil)
	end)

	it("returns correct ETH address", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens = pm:getKnownTokens()
		expect(tokens.ETH.address):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
		expect(tokens.ETH.decimals):toBe(18)
		expect(tokens.ETH.symbol):toBe("ETH")
	end)

	it("returns correct STRK address", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens = pm:getKnownTokens()
		expect(tokens.STRK.address):toBe("0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d")
		expect(tokens.STRK.decimals):toBe(18)
	end)

	it("returns correct USDC address", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens = pm:getKnownTokens()
		expect(tokens.USDC.address):toBe("0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8")
		expect(tokens.USDC.decimals):toBe(6)
	end)

	it("returns correct USDT address", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens = pm:getKnownTokens()
		expect(tokens.USDT.address):toBe("0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8")
		expect(tokens.USDT.decimals):toBe(6)
	end)

	it("returns empty table for unknown network", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
			network = "custom-devnet",
			nodeUrl = "http://localhost:5050",
		})
		local tokens = pm:getKnownTokens()
		expect(next(tokens)):toBe(nil)
	end)

	it("returned table is a copy (not mutable)", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local tokens1 = pm:getKnownTokens()
		tokens1.ETH = nil :: any
		local tokens2 = pm:getKnownTokens()
		expect(tokens2.ETH):toBeTruthy()
	end)
end)

describe("AvnuPaymaster - getTokenAddress", function()
	it("returns ETH address for 'ETH'", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local addr = pm:getTokenAddress("ETH")
		expect(addr):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)

	it("returns STRK address for 'STRK'", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "sepolia" })
		local addr = pm:getTokenAddress("STRK")
		expect(addr):toBe("0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d")
	end)

	it("returns USDC address for mainnet", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local addr = pm:getTokenAddress("USDC")
		expect(addr):toBe("0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8")
	end)

	it("returns nil for unknown symbol", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local addr = pm:getTokenAddress("DOGE")
		expect(addr):toBe(nil)
	end)

	it("returns nil for USDC on sepolia", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({ network = "sepolia" })
		local addr = pm:getTokenAddress("USDC")
		expect(addr):toBe(nil)
	end)

	it("returns nil for unknown network", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
			network = "devnet",
			nodeUrl = "http://localhost:5050",
		})
		local addr = pm:getTokenAddress("ETH")
		expect(addr):toBe(nil)
	end)
end)

describe("AvnuPaymaster - delegated methods", function()
	it("isAvailable delegates to inner PaymasterRpc", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		local result = pm:isAvailable():expect()
		expect(result):toBe(true)
	end)

	it("isAvailable returns false when unavailable", function()
		resetPaymasterHandlers()
		mockHandlers["paymaster_isAvailable"] = function(_params)
			return false
		end
		local pm = createTestAvnuPaymaster()
		local result = pm:isAvailable():expect()
		expect(result):toBe(false)
	end)

	it("buildTypedData delegates correctly", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster()
		local result = pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "transfer", calldata = { "0x1" } } },
			"0x049d"
		):expect()

		expect(result.typedData):toBeTruthy()
		expect(result.typedData.primaryType):toBe("OutsideExecution")
		expect(result.feeEstimate):toBeTruthy()
		expect(result.feeEstimate.gasTokenPrice):toBe("0x3e8")
	end)

	it("executeTransaction delegates correctly", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		local result = pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" }
		):expect()

		expect(result.transactionHash):toBe("0xavnu456")
		expect(result.trackingId):toBe("track-avnu-123")
	end)

	it("trackingIdToLatestHash delegates correctly", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster()
		local result = pm:trackingIdToLatestHash("track-avnu-123"):expect()
		expect(result.transactionHash):toBe("0xavnu456")
		expect(result.status):toBe("accepted")
	end)

	it("fetch delegates correctly", function()
		resetPaymasterHandlers()
		mockHandlers["paymaster_customMethod"] = function(_params)
			return { custom = "avnu-result" }
		end
		local pm = createTestAvnuPaymaster()
		local result = pm:fetch("paymaster_customMethod", {}):expect()
		expect(result.custom):toBe("avnu-result")
	end)

	it("buildTypedData passes deployment data through", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster()
		pm:buildTypedData("0xuser", { { contractAddress = "0xc", entrypoint = "fn", calldata = {} } }, "0x049d", {
			deploymentData = {
				classHash = "0xclass",
				calldata = { "0xpk" },
				salt = "0xsalt",
			},
		}):expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[1].type):toBe("DEPLOY_AND_INVOKE")
		expect(params[1].deploy_and_invoke.deployment_data.class_hash):toBe("0xclass")
	end)

	it("executeTransaction passes deployment data through", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster()
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
				},
			}
		):expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[1].type):toBe("DEPLOY_AND_INVOKE")
	end)

	it("executeTransaction passes gasTokenAddress through for default fee mode", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster()
		pm:executeTransaction(
			"0xuser",
			{ types = {}, primaryType = "OE", domain = {}, message = {} },
			{ "0xr", "0xs" },
			"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		):expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[2].fee_mode.mode):toBe("default")
		expect(params[2].fee_mode.gas_token):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)
end)

describe("AvnuPaymaster - getSupportedTokens caching", function()
	it("returns tokens from network on first call", function()
		resetPaymasterHandlers()
		local clock, _setClock = TestUtils.makeClock(0)
		local pm = createTestAvnuPaymaster({ _clock = clock })
		local tokens = pm:getSupportedTokens():expect()
		expect(type(tokens)):toBe("table")
		expect(#tokens):toBe(3)
	end)

	it("returns cached tokens on second call within TTL", function()
		resetPaymasterHandlers()
		local callCount = 0
		local clock, setClock = TestUtils.makeClock(0)

		local originalHandler = mockHandlers["paymaster_getSupportedTokens"]
		mockHandlers["paymaster_getSupportedTokens"] = function(params)
			callCount += 1
			return originalHandler(params)
		end

		local pm = createTestAvnuPaymaster({ _clock = clock })

		-- First call: network
		local tokens1 = pm:getSupportedTokens():expect()
		expect(#tokens1):toBe(3)
		expect(callCount):toBe(1)

		-- Advance 60 seconds (within default 300s TTL)
		setClock(60)

		-- Second call: should be cached
		local tokens2 = pm:getSupportedTokens():expect()
		expect(#tokens2):toBe(3)
		expect(callCount):toBe(1) -- no additional network call
	end)

	it("refetches after cache TTL expires", function()
		resetPaymasterHandlers()
		local callCount = 0
		local clock, setClock = TestUtils.makeClock(0)

		local originalHandler = mockHandlers["paymaster_getSupportedTokens"]
		mockHandlers["paymaster_getSupportedTokens"] = function(params)
			callCount += 1
			return originalHandler(params)
		end

		local pm = createTestAvnuPaymaster({ _clock = clock, tokenCacheTtl = 60 })

		-- First call
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- Advance past TTL
		setClock(61)

		-- Second call: should refetch
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(2)
	end)

	it("uses custom tokenCacheTtl", function()
		resetPaymasterHandlers()
		local callCount = 0
		local clock, setClock = TestUtils.makeClock(0)

		local originalHandler = mockHandlers["paymaster_getSupportedTokens"]
		mockHandlers["paymaster_getSupportedTokens"] = function(params)
			callCount += 1
			return originalHandler(params)
		end

		local pm = createTestAvnuPaymaster({ _clock = clock, tokenCacheTtl = 10 })

		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- Within TTL
		setClock(5)
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- Past TTL
		setClock(11)
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(2)
	end)

	it("clearTokenCache forces refetch", function()
		resetPaymasterHandlers()
		local callCount = 0
		local clock, _setClock = TestUtils.makeClock(0)

		local originalHandler = mockHandlers["paymaster_getSupportedTokens"]
		mockHandlers["paymaster_getSupportedTokens"] = function(params)
			callCount += 1
			return originalHandler(params)
		end

		local pm = createTestAvnuPaymaster({ _clock = clock })

		-- First call
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- Clear cache
		pm:clearTokenCache()

		-- Should refetch
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(2)
	end)

	it("default tokenCacheTtl is 300 seconds", function()
		resetPaymasterHandlers()
		local callCount = 0
		local clock, setClock = TestUtils.makeClock(0)

		local originalHandler = mockHandlers["paymaster_getSupportedTokens"]
		mockHandlers["paymaster_getSupportedTokens"] = function(params)
			callCount += 1
			return originalHandler(params)
		end

		local pm = createTestAvnuPaymaster({ _clock = clock })

		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- 299 seconds: still cached
		setClock(299)
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(1)

		-- 301 seconds total: expired
		setClock(301)
		pm:getSupportedTokens():expect()
		expect(callCount):toBe(2)
	end)

	it("cached result has correct data", function()
		resetPaymasterHandlers()
		local clock, setClock = TestUtils.makeClock(0)
		local pm = createTestAvnuPaymaster({ _clock = clock })

		-- Fetch and cache
		local tokens1 = pm:getSupportedTokens():expect()

		setClock(10)

		-- Get from cache
		local tokens2 = pm:getSupportedTokens():expect()

		-- Same data
		expect(#tokens2):toBe(#tokens1)
		expect(tokens2[1].tokenAddress):toBe(tokens1[1].tokenAddress)
		expect(tokens2[1].decimals):toBe(tokens1[1].decimals)
	end)
end)

describe("AvnuPaymaster - static methods", function()
	it("getEndpoint returns sepolia URL", function()
		local url = AvnuPaymaster.getEndpoint("sepolia")
		expect(url):toBe("https://sepolia.paymaster.avnu.fi")
	end)

	it("getEndpoint returns mainnet URL", function()
		local url = AvnuPaymaster.getEndpoint("mainnet")
		expect(url):toBe("https://starknet.paymaster.avnu.fi")
	end)

	it("getEndpoint returns nil for unknown network", function()
		local url = AvnuPaymaster.getEndpoint("goerli")
		expect(url):toBe(nil)
	end)

	it("getEndpoints returns all endpoints", function()
		local endpoints = AvnuPaymaster.getEndpoints()
		expect(endpoints.mainnet):toBe("https://starknet.paymaster.avnu.fi")
		expect(endpoints.sepolia):toBe("https://sepolia.paymaster.avnu.fi")
	end)

	it("getEndpoints returns a copy", function()
		local e1 = AvnuPaymaster.getEndpoints()
		e1.mainnet = "mutated"
		local e2 = AvnuPaymaster.getEndpoints()
		expect(e2.mainnet):toBe("https://starknet.paymaster.avnu.fi")
	end)

	it("getTokensForNetwork returns mainnet tokens", function()
		local tokens = AvnuPaymaster.getTokensForNetwork("mainnet")
		expect(tokens.ETH):toBeTruthy()
		expect(tokens.STRK):toBeTruthy()
		expect(tokens.USDC):toBeTruthy()
		expect(tokens.USDT):toBeTruthy()
	end)

	it("getTokensForNetwork returns sepolia tokens", function()
		local tokens = AvnuPaymaster.getTokensForNetwork("sepolia")
		expect(tokens.ETH):toBeTruthy()
		expect(tokens.STRK):toBeTruthy()
		expect(tokens.USDC):toBe(nil)
	end)

	it("getTokensForNetwork returns empty for unknown", function()
		local tokens = AvnuPaymaster.getTokensForNetwork("goerli")
		expect(next(tokens)):toBe(nil)
	end)

	it("getTokensForNetwork returns a copy", function()
		local t1 = AvnuPaymaster.getTokensForNetwork("mainnet")
		t1.ETH = nil :: any
		local t2 = AvnuPaymaster.getTokensForNetwork("mainnet")
		expect(t2.ETH):toBeTruthy()
	end)
end)

describe("AvnuPaymaster - error propagation", function()
	it("propagates RPC errors from inner paymaster", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
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
		expect(err.code):toBe(7002) -- PAYMASTER_TOKEN_NOT_SUPPORTED
		expect(err:is("RpcError")):toBe(true)
	end)

	it("propagates network errors from inner paymaster", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
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

	it("isAvailable returns false on error (does not throw)", function()
		resetPaymasterHandlers()
		local pm = createTestAvnuPaymaster({
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

	it("does not cache failed getSupportedTokens results", function()
		resetPaymasterHandlers()
		local callCount = 0
		local shouldFail = true
		local clock, _setClock = TestUtils.makeClock(0)

		local pm = createTestAvnuPaymaster({
			_clock = clock,
			_httpRequest = function(request: any)
				callCount += 1
				if shouldFail then
					return {
						StatusCode = 500,
						Body = "Server Error",
						Success = false,
					}
				end
				local body = serde.decode("json", request.Body or "{}") :: any
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						result = {
							{
								token_address = "0x049d",
								decimals = 18,
								price_in_strk = "0x1",
							},
						},
					}),
					Success = true,
				}
			end,
		})

		-- First call fails
		local promise1 = pm:getSupportedTokens()
		expect(promise1:getStatus()):toBe("Rejected")
		expect(callCount):toBe(1)

		-- Fix the error
		shouldFail = false

		-- Second call should try network again (not return cached error)
		local tokens = pm:getSupportedTokens():expect()
		expect(callCount):toBe(2)
		expect(#tokens):toBe(1)
	end)
end)

describe("AvnuPaymaster - integration with fee modes", function()
	it("sponsored mode with apiKey uses 0x0 gas token", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster({ apiKey = "game-dev-key" })
		pm:buildTypedData(
			"0xuser",
			{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
			"0x0" -- sponsored
		):expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[2].fee_mode.mode):toBe("sponsored")
	end)

	it("gasless mode without apiKey uses token address", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster() -- no apiKey
		local ethAddr = pm:getTokenAddress("ETH")
		pm
			:buildTypedData(
				"0xuser",
				{ { contractAddress = "0xc", entrypoint = "fn", calldata = {} } },
				ethAddr :: string
			)
			:expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[2].fee_mode.mode):toBe("default")
		expect(params[2].fee_mode.gas_token):toBe("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)

	it("can use getTokenAddress to resolve symbol for buildTypedData", function()
		resetPaymasterHandlers()
		rpc.clearRequestLog()
		local pm = createTestAvnuPaymaster({ network = "mainnet" })
		local usdcAddr = pm:getTokenAddress("USDC")
		expect(usdcAddr):toBeTruthy()

		pm:buildTypedData(
			"0xplayer",
			{ { contractAddress = "0xgame", entrypoint = "mint", calldata = { "0x1" } } },
			usdcAddr :: string
		):expect()

		local params = rpc.requestLog[#rpc.requestLog].params
		expect(params[2].fee_mode.mode):toBe("default")
		expect(params[2].fee_mode.gas_token):toBe("0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8")
	end)
end)
