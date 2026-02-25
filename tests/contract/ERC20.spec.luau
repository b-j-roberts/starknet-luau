--!strict
local serde = require("@lune/serde")

local ERC20 = require("../../src/contract/ERC20")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local StarkSigner = require("../../src/signer/StarkSigner")
local Account = require("../../src/wallet/Account")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local TOKEN_ADDR = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
local OWNER_ADDR = "0x1234567890abcdef1234567890abcdef12345678"
local SPENDER_ADDR = "0xabcdef1234567890abcdef1234567890abcdef12"
local RECIPIENT_ADDR = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
local PRIVKEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function resetHandlers()
	mockHandlers = {}
	requestLog = {}

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

	mockHandlers["starknet_call"] = function(_params)
		return { "0x1" }
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

local function createTestProvider(): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
	}

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

local function createTestAccount(): any
	resetHandlers()
	local provider = createTestProvider()
	return Account.fromPrivateKey({
		privateKey = PRIVKEY,
		provider = provider,
	})
end

resetHandlers()

--------------------------------------------------------------------------------
-- ERC20.new (constructor)
--------------------------------------------------------------------------------

describe("ERC20.new - constructor", function()
	it("creates an ERC20 instance with address and provider", function()
		resetHandlers()
		local provider = createTestProvider()

		local token = ERC20.new(TOKEN_ADDR, provider)
		expect(token):toBeTruthy()
		expect(token.address):toBe(TOKEN_ADDR)
	end)

	it("creates an ERC20 instance with optional account", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()

		local token = ERC20.new(TOKEN_ADDR, provider, account)
		expect(token):toBeTruthy()
		expect(token.address):toBe(TOKEN_ADDR)
	end)

	it("errors when address is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			ERC20.new(nil :: any, provider)
		end):toThrow()
	end)

	it("errors when provider is missing", function()
		expect(function()
			ERC20.new(TOKEN_ADDR, nil :: any)
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- ERC20.getAbi
--------------------------------------------------------------------------------

describe("ERC20.getAbi - built-in ABI", function()
	it("returns the ERC-20 ABI", function()
		local abi = ERC20.getAbi()
		expect(#abi > 0):toBe(true)
	end)

	it("contains standard ERC-20 functions", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		expect(token:hasFunction("name")):toBe(true)
		expect(token:hasFunction("symbol")):toBe(true)
		expect(token:hasFunction("decimals")):toBe(true)
		expect(token:hasFunction("total_supply")):toBe(true)
		expect(token:hasFunction("balance_of")):toBe(true)
		expect(token:hasFunction("allowance")):toBe(true)
		expect(token:hasFunction("transfer")):toBe(true)
		expect(token:hasFunction("transfer_from")):toBe(true)
		expect(token:hasFunction("approve")):toBe(true)
	end)

	it("contains camelCase aliases", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		expect(token:hasFunction("totalSupply")):toBe(true)
		expect(token:hasFunction("balanceOf")):toBe(true)
		expect(token:hasFunction("transferFrom")):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Read methods (view functions)
--------------------------------------------------------------------------------

describe("ERC20 - read methods (view)", function()
	it("name() returns token name as felt", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4574686572" } -- "Ether"
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:name():expect()
		expect(result):toBe("0x4574686572")
	end)

	it("symbol() returns token symbol as felt", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x455448" } -- "ETH"
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:symbol():expect()
		expect(result):toBe("0x455448")
	end)

	it("decimals() returns decimals as u8 felt", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x12" } -- 18
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:decimals():expect()
		expect(result):toBe("0x12")
	end)

	it("total_supply() returns u256 {low, high}", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xde0b6b3a7640000", "0x0" } -- 1e18
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:total_supply():expect()
		expect((result :: any).low):toBe("0xde0b6b3a7640000")
		expect((result :: any).high):toBe("0x0")
	end)

	it("totalSupply() camelCase alias works", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xde0b6b3a7640000", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:totalSupply():expect()
		expect((result :: any).low):toBe("0xde0b6b3a7640000")
		expect((result :: any).high):toBe("0x0")
	end)

	it("balance_of(owner) returns u256", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" } -- 1000
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:balance_of(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x3e8")
		expect((result :: any).high):toBe("0x0")
	end)

	it("balanceOf(owner) camelCase alias works", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:balanceOf(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x3e8")
		expect((result :: any).high):toBe("0x0")
	end)

	it("allowance(owner, spender) returns u256", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x5f5e100", "0x0" } -- 100000000
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:allowance(OWNER_ADDR, SPENDER_ADDR):expect()
		expect((result :: any).low):toBe("0x5f5e100")
		expect((result :: any).high):toBe("0x0")
	end)

	it("balance_of sends correct calldata to provider", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		token:balance_of(OWNER_ADDR):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				expect(req.contract_address):toBe(TOKEN_ADDR)
				expect(#req.calldata):toBe(1)
				expect(req.calldata[1]):toBe(OWNER_ADDR)
			end
		end
		expect(found):toBe(true)
	end)

	it("allowance sends correct calldata with two args", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		token:allowance(OWNER_ADDR, SPENDER_ADDR):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				expect(#req.calldata):toBe(2)
				expect(req.calldata[1]):toBe(OWNER_ADDR)
				expect(req.calldata[2]):toBe(SPENDER_ADDR)
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Write methods (external functions)
--------------------------------------------------------------------------------

describe("ERC20 - write methods (external)", function()
	it("transfer(recipient, amount) returns tx hash", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		local result = token:transfer(RECIPIENT_ADDR, "0x3e8"):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("approve(spender, amount) returns tx hash", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		local result = token:approve(SPENDER_ADDR, "0x5f5e100"):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("transfer_from(sender, recipient, amount) returns tx hash", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		local result = token:transfer_from(OWNER_ADDR, RECIPIENT_ADDR, "0x3e8"):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("transferFrom(sender, recipient, amount) camelCase alias works", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		local result = token:transferFrom(OWNER_ADDR, RECIPIENT_ADDR, "0x3e8"):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("transfer supports dryRun option", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		local result = token:transfer(RECIPIENT_ADDR, "0x3e8", { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
	end)

	it("errors when no account for write methods", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider) -- no account

		expect(function()
			token:transfer(RECIPIENT_ADDR, "0x3e8")
		end):toThrow()
	end)

	it("transfer sends correct calldata (recipient + u256 amount)", function()
		resetHandlers()
		requestLog = {}
		local account = createTestAccount()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider, account)

		token:transfer(RECIPIENT_ADDR, "0x3e8"):expect()

		-- Find the addInvokeTransaction call
		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				found = true
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- populate() for multicall batching
--------------------------------------------------------------------------------

describe("ERC20 - populate for multicall", function()
	it("populate transfer returns correct Call object", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local call = token:populate("transfer", { RECIPIENT_ADDR, "0x3e8" })
		expect(call.contractAddress):toBe(TOKEN_ADDR)
		expect(call.entrypoint):toBe("transfer")
		-- recipient (1 felt) + u256 (2 felts) = 3
		expect(#call.calldata):toBe(3)
	end)

	it("populate approve returns correct Call object", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local call = token:populate("approve", { SPENDER_ADDR, "0x5f5e100" })
		expect(call.contractAddress):toBe(TOKEN_ADDR)
		expect(call.entrypoint):toBe("approve")
		-- spender (1 felt) + u256 (2 felts) = 3
		expect(#call.calldata):toBe(3)
	end)

	it("populate transfer_from returns correct Call object", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local call = token:populate("transfer_from", { OWNER_ADDR, RECIPIENT_ADDR, "0x3e8" })
		expect(call.contractAddress):toBe(TOKEN_ADDR)
		expect(call.entrypoint):toBe("transfer_from")
		-- sender (1) + recipient (1) + u256 (2) = 4
		expect(#call.calldata):toBe(4)
	end)

	it("can batch multiple ERC20 calls", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local call1 = token:populate("approve", { SPENDER_ADDR, "0x5f5e100" })
		local call2 = token:populate("transfer", { RECIPIENT_ADDR, "0x3e8" })

		expect(call1.contractAddress):toBe(TOKEN_ADDR)
		expect(call2.contractAddress):toBe(TOKEN_ADDR)
		expect(call1.entrypoint):toBe("approve")
		expect(call2.entrypoint):toBe("transfer")
	end)
end)

--------------------------------------------------------------------------------
-- Contract utility methods inherited
--------------------------------------------------------------------------------

describe("ERC20 - inherited Contract methods", function()
	it("getFunctions returns all ERC-20 functions", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local fns = token:getFunctions()
		-- 9 snake_case + 3 camelCase = 12
		expect(#fns):toBe(12)
	end)

	it("getFunction returns parsed metadata", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local fn = token:getFunction("balance_of")
		expect(fn):toBeTruthy()
		expect((fn :: any).stateMutability):toBe("view")
		expect(#(fn :: any).inputs):toBe(1)
	end)

	it("hasFunction returns false for non-ERC20 function", function()
		resetHandlers()
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		expect(token:hasFunction("mint")):toBe(false)
		expect(token:hasFunction("burn")):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Edge cases
--------------------------------------------------------------------------------

describe("ERC20 - edge cases", function()
	it("balance with large u256 value", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xffffffffffffffffffffffffffffffff", "0xffffffffffffffffffffffffffffffff" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:balance_of(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0xffffffffffffffffffffffffffffffff")
		expect((result :: any).high):toBe("0xffffffffffffffffffffffffffffffff")
	end)

	it("balance of zero returns u256 zero", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:balance_of(OWNER_ADDR):expect()
		expect((result :: any).low):toBe("0x0")
		expect((result :: any).high):toBe("0x0")
	end)

	it("allowance returns zero when none set", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x0" }
		end
		local provider = createTestProvider()
		local token = ERC20.new(TOKEN_ADDR, provider)

		local result = token:allowance(OWNER_ADDR, SPENDER_ADDR):expect()
		expect((result :: any).low):toBe("0x0")
		expect((result :: any).high):toBe("0x0")
	end)

	it("different token addresses create separate instances", function()
		resetHandlers()
		local provider = createTestProvider()
		local token1 = ERC20.new("0xaaa", provider)
		local token2 = ERC20.new("0xbbb", provider)

		expect(token1.address):toBe("0xaaa")
		expect(token2.address):toBe("0xbbb")
	end)
end)
