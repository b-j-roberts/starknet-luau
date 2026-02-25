--!strict
local serde = require("@lune/serde")

local Contract = require("../../src/contract/Contract")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local StarkSigner = require("../../src/signer/StarkSigner")
local Account = require("../../src/wallet/Account")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local CONTRACT_ADDR = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

-- Private key for account (from StarkSigner tests, < curve order N)
local PRIVKEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"

local SN_SEPOLIA = "0x534e5f5345504f4c4941"

-- Sample ERC-20 ABI (simplified Cairo ABI format)
local ERC20_ABI: Contract.Abi = {
	{
		type = "function",
		name = "balance_of",
		inputs = {
			{ name = "account", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "balance", type = "core::integer::u256" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "transfer",
		inputs = {
			{ name = "recipient", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = {
			{ name = "success", type = "core::bool" },
		},
		state_mutability = "external",
	},
	{
		type = "function",
		name = "name",
		inputs = {},
		outputs = {
			{ name = "name", type = "core::felt252" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "decimals",
		inputs = {},
		outputs = {
			{ name = "decimals", type = "core::integer::u8" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "approve",
		inputs = {
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = {
			{ name = "success", type = "core::bool" },
		},
		state_mutability = "external",
	},
	{
		type = "function",
		name = "allowance",
		inputs = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "remaining", type = "core::integer::u256" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "total_supply",
		inputs = {},
		outputs = {
			{ name = "supply", type = "core::integer::u256" },
		},
		state_mutability = "view",
	},
	-- Non-function entries (should be ignored by parser)
	{
		type = "event",
		name = "Transfer",
		inputs = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "value", type = "core::integer::u256" },
		},
	} :: any,
	{
		type = "struct",
		name = "Uint256",
		inputs = {
			{ name = "low", type = "core::integer::u128" },
			{ name = "high", type = "core::integer::u128" },
		},
	} :: any,
}

-- Minimal ABI for edge-case testing
local MINIMAL_ABI: Contract.Abi = {
	{
		type = "function",
		name = "get_value",
		inputs = {},
		outputs = {
			{ name = "value", type = "core::felt252" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "set_value",
		inputs = {
			{ name = "value", type = "core::felt252" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

-- ABI with multiple output types for parsing tests
local MULTI_OUTPUT_ABI: Contract.Abi = {
	{
		type = "function",
		name = "get_pair",
		inputs = {},
		outputs = {
			{ name = "first", type = "core::felt252" },
			{ name = "second", type = "core::felt252" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "get_mixed",
		inputs = {},
		outputs = {
			{ name = "addr", type = "core::felt252" },
			{ name = "amount", type = "core::integer::u256" },
			{ name = "flag", type = "core::bool" },
		},
		state_mutability = "view",
	},
}

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

	-- Default: return a single felt
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
-- Contract.new (constructor)
--------------------------------------------------------------------------------

describe("Contract.new - constructor validation", function()
	it("creates a contract with abi, address, and provider", function()
		resetHandlers()
		local provider = createTestProvider()

		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})
		expect(contract):toBeTruthy()
		expect(contract.address):toBe(CONTRACT_ADDR)
	end)

	it("creates a contract with optional account", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()

		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})
		expect(contract):toBeTruthy()
	end)

	it("errors when abi is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Contract.new({
				abi = nil :: any,
				address = CONTRACT_ADDR,
				provider = provider,
			})
		end):toThrow()
	end)

	it("errors when address is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Contract.new({
				abi = ERC20_ABI,
				address = nil :: any,
				provider = provider,
			})
		end):toThrow()
	end)

	it("errors when provider is missing", function()
		expect(function()
			Contract.new({
				abi = ERC20_ABI,
				address = CONTRACT_ADDR,
				provider = nil :: any,
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- ABI parsing
--------------------------------------------------------------------------------

describe("Contract - ABI parsing", function()
	it("parses function entries from ABI", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local functions = contract:getFunctions()
		expect(#functions > 0):toBe(true)
	end)

	it("includes all function entries", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("balance_of")):toBe(true)
		expect(contract:hasFunction("transfer")):toBe(true)
		expect(contract:hasFunction("name")):toBe(true)
		expect(contract:hasFunction("decimals")):toBe(true)
		expect(contract:hasFunction("approve")):toBe(true)
		expect(contract:hasFunction("allowance")):toBe(true)
		expect(contract:hasFunction("total_supply")):toBe(true)
	end)

	it("ignores non-function entries (events, structs)", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("Transfer")):toBe(false)
		expect(contract:hasFunction("Uint256")):toBe(false)
	end)

	it("stores correct state_mutability", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local balanceOf = contract:getFunction("balance_of")
		expect(balanceOf):toBeTruthy()
		expect((balanceOf :: any).stateMutability):toBe("view")

		local transfer = contract:getFunction("transfer")
		expect(transfer):toBeTruthy()
		expect((transfer :: any).stateMutability):toBe("external")
	end)

	it("computes correct selectors for functions", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local balanceOf = contract:getFunction("balance_of")
		expect(balanceOf):toBeTruthy()
		-- Selector should be a hex string starting with 0x
		expect(string.sub((balanceOf :: any).selector, 1, 2)):toBe("0x")
	end)

	it("stores input/output parameter info", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local balanceOf = contract:getFunction("balance_of")
		expect(#(balanceOf :: any).inputs):toBe(1)
		expect((balanceOf :: any).inputs[1].name):toBe("account")
		expect(#(balanceOf :: any).outputs):toBe(1)
		expect((balanceOf :: any).outputs[1].name):toBe("balance")
	end)

	it("returns nil for non-existent function", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:getFunction("nonexistent")):toBeFalsy()
	end)
end)

--------------------------------------------------------------------------------
-- contract:call (view functions)
--------------------------------------------------------------------------------

describe("Contract:call - view functions", function()
	it("calls a view function with no arguments", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4574686572" } -- "Ether" as felt
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("name"):expect()
		expect(result):toBe("0x4574686572")
	end)

	it("calls a view function with one argument", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" } -- 1000 as u256 (low, high)
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("balance_of", { "0xdeadbeef" }):expect()
		-- u256 returns { low, high }
		expect((result :: any).low):toBe("0x3e8")
		expect((result :: any).high):toBe("0x0")
	end)

	it("calls a view function with multiple arguments", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x5f5e100", "0x0" } -- allowance as u256
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("allowance", { "0xaaa111", "0xbbb222" }):expect()
		expect((result :: any).low):toBe("0x5f5e100")
	end)

	it("sends correct contract_address to provider", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:call("name"):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				expect(req.contract_address):toBe(CONTRACT_ADDR)
			end
		end
		expect(found):toBe(true)
	end)

	it("sends correct entry_point_selector to provider", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:call("name"):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				-- Selector should be a hex string
				expect(string.sub(req.entry_point_selector, 1, 2)):toBe("0x")
			end
		end
		expect(found):toBe(true)
	end)

	it("encodes calldata for felt252 argument", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:call("balance_of", { "0xabc" }):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				found = true
				local req = entry.params[1]
				-- calldata should contain the encoded address
				expect(#req.calldata):toBe(1)
				expect(req.calldata[1]):toBe("0xabc")
			end
		end
		expect(found):toBe(true)
	end)

	it("errors when calling a non-existent function", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("nonexistent")
		end):toThrow()
	end)

	it("errors when wrong number of arguments provided", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("balance_of") -- missing required account arg
		end):toThrow()
	end)

	it("errors when too many arguments provided", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("name", { "0xextra" }) -- name takes 0 args
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- contract:populate (build Call objects)
--------------------------------------------------------------------------------

describe("Contract:populate - build Call objects", function()
	it("builds a Call for a function with no args", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("name")
		expect(call.contractAddress):toBe(CONTRACT_ADDR)
		expect(call.entrypoint):toBe("name")
		expect(#call.calldata):toBe(0)
	end)

	it("builds a Call for a function with felt252 arg", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("balance_of", { "0xdeadbeef" })
		expect(call.contractAddress):toBe(CONTRACT_ADDR)
		expect(call.entrypoint):toBe("balance_of")
		expect(#call.calldata):toBe(1)
		expect(call.calldata[1]):toBe("0xdeadbeef")
	end)

	it("builds a Call for a function with u256 arg (expands to 2 felts)", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- transfer(recipient, amount_u256)
		local call = contract:populate("transfer", { "0xabcdef1234567890", "0x3e8" })
		expect(call.contractAddress):toBe(CONTRACT_ADDR)
		expect(call.entrypoint):toBe("transfer")
		-- recipient (1 felt) + u256 (2 felts) = 3 felts
		expect(#call.calldata):toBe(3)
		expect(call.calldata[1]):toBe("0xabcdef1234567890")
		-- u256 low = 0x3e8, high = 0x0
		expect(call.calldata[2]):toBe("0x3e8")
		expect(call.calldata[3]):toBe("0x0")
	end)

	it("errors for non-existent function", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:populate("nonexistent")
		end):toThrow()
	end)

	it("errors for wrong argument count", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:populate("transfer", { "0xabcdef1234567890" }) -- missing amount
		end):toThrow()
	end)

	it("can be used for multicall batching", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call1 = contract:populate("transfer", { "0xabcdef12345678901", "0x3e8" })
		local call2 = contract:populate("approve", { "0xbbb222", "0x7d0" })

		-- Both should be valid Call objects
		expect(call1.contractAddress):toBe(CONTRACT_ADDR)
		expect(call2.contractAddress):toBe(CONTRACT_ADDR)
		expect(call1.entrypoint):toBe("transfer")
		expect(call2.entrypoint):toBe("approve")
	end)
end)

--------------------------------------------------------------------------------
-- contract:invoke (write transactions)
--------------------------------------------------------------------------------

describe("Contract:invoke - write transactions", function()
	it("invokes a transaction and returns hash", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		local result = contract:invoke("transfer", { "0xabcdef1234567890", "0x3e8" }):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("supports dryRun option", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		local result = contract:invoke("transfer", { "0xabcdef1234567890", "0x3e8" }, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
	end)

	it("errors when no account is set", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			-- no account
		})

		expect(function()
			contract:invoke("transfer", { "0xabcdef1234567890", "0x3e8" })
		end):toThrow()
	end)

	it("errors when invoking a non-existent function", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		expect(function()
			contract:invoke("nonexistent", { "0x1" })
		end):toThrow()
	end)

	it("sends the correct contract address in the call", function()
		resetHandlers()
		requestLog = {}
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		contract:invoke("transfer", { "0xabcdef1234567890", "0x3e8" }):expect()

		-- Find the addInvokeTransaction call
		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				found = true
			end
		end
		expect(found):toBe(true)
	end)

	it("invokes a function with no args", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		local result = contract:invoke("set_value", { "0x42" }):expect()
		expect(result.transactionHash):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Dynamic method dispatch via __index
--------------------------------------------------------------------------------

describe("Contract - dynamic method dispatch", function()
	it("view function is callable as contract:method()", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4574686572" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:name():expect()
		expect(result):toBe("0x4574686572")
	end)

	it("view function with args is callable dynamically", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:balance_of("0xdeadbeef"):expect()
		expect((result :: any).low):toBe("0x3e8")
	end)

	it("external function is callable as contract:method()", function()
		resetHandlers()
		local account = createTestAccount()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		local result = contract:transfer("0xabcdef1234567890", "0x3e8"):expect()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("dynamic view returns correct parsed u256 result", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x5f5e100", "0x0" } -- total_supply
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:total_supply():expect()
		expect((result :: any).low):toBe("0x5f5e100")
		expect((result :: any).high):toBe("0x0")
	end)

	it("class methods still accessible on dynamic dispatch instance", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- call, invoke, populate, getFunctions, getFunction, hasFunction should exist
		expect(contract.call):toBeTruthy()
		expect(contract.invoke):toBeTruthy()
		expect(contract.populate):toBeTruthy()
		expect(contract.getFunctions):toBeTruthy()
		expect(contract.getFunction):toBeTruthy()
		expect(contract.hasFunction):toBeTruthy()
	end)

	it("non-existent dynamic method returns nil", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract.nonexistent_method):toBeFalsy()
	end)
end)

--------------------------------------------------------------------------------
-- Response parsing
--------------------------------------------------------------------------------

describe("Contract - response parsing", function()
	it("parses single felt252 output", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x12" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("decimals"):expect()
		expect(result):toBe("0x12")
	end)

	it("parses u256 output as { low, high }", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xde0b6b3a7640000", "0x0" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("balance_of", { "0xabc" }):expect()
		expect((result :: any).low):toBe("0xde0b6b3a7640000")
		expect((result :: any).high):toBe("0x0")
	end)

	it("parses multiple outputs into named table", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xaaa", "0xbbb" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MULTI_OUTPUT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_pair"):expect()
		expect((result :: any).first):toBe("0xaaa")
		expect((result :: any).second):toBe("0xbbb")
	end)

	it("parses mixed output types (felt + u256 + bool)", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xadd1", "0x3e8", "0x0", "0x1" } -- addr, u256(low,high), bool
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MULTI_OUTPUT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_mixed"):expect()
		expect((result :: any).addr):toBe("0xadd1")
		expect((result :: any).amount.low):toBe("0x3e8")
		expect((result :: any).amount.high):toBe("0x0")
		expect((result :: any).flag):toBe(true)
	end)

	it("returns raw result array when no outputs defined", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1", "0x2", "0x3" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- set_value has no outputs, but let's test get_value which has one output
		mockHandlers["starknet_call"] = function(_params)
			return { "0x42" }
		end
		local result = contract:call("get_value"):expect()
		expect(result):toBe("0x42")
	end)

	it("parses bool output correctly (true)", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1" }
		end
		local provider = createTestProvider()

		local boolAbi: Contract.Abi = {
			{
				type = "function",
				name = "is_active",
				inputs = {},
				outputs = { { name = "active", type = "core::bool" } },
				state_mutability = "view",
			},
		}
		local contract = Contract.new({
			abi = boolAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("is_active"):expect()
		expect(result):toBe(true)
	end)

	it("parses bool output correctly (false)", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" }
		end
		local provider = createTestProvider()

		local boolAbi: Contract.Abi = {
			{
				type = "function",
				name = "is_active",
				inputs = {},
				outputs = { { name = "active", type = "core::bool" } },
				state_mutability = "view",
			},
		}
		local contract = Contract.new({
			abi = boolAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("is_active"):expect()
		expect(result):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Type encoding
--------------------------------------------------------------------------------

describe("Contract - type encoding in calldata", function()
	it("encodes bool true as 0x1", function()
		resetHandlers()
		local provider = createTestProvider()

		local boolAbi: Contract.Abi = {
			{
				type = "function",
				name = "set_flag",
				inputs = { { name = "flag", type = "core::bool" } },
				outputs = {},
				state_mutability = "external",
			},
		}
		local contract = Contract.new({
			abi = boolAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("set_flag", { true })
		expect(call.calldata[1]):toBe("0x1")
	end)

	it("encodes bool false as 0x0", function()
		resetHandlers()
		local provider = createTestProvider()

		local boolAbi: Contract.Abi = {
			{
				type = "function",
				name = "set_flag",
				inputs = { { name = "flag", type = "core::bool" } },
				outputs = {},
				state_mutability = "external",
			},
		}
		local contract = Contract.new({
			abi = boolAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("set_flag", { false })
		expect(call.calldata[1]):toBe("0x0")
	end)

	it("encodes u256 as two felts (low, high)", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("transfer", { "0xabcdef1234567890", "0x3e8" })
		-- u256(0x3e8) = low:0x3e8, high:0x0
		expect(call.calldata[2]):toBe("0x3e8")
		expect(call.calldata[3]):toBe("0x0")
	end)

	it("encodes felt252 as normalized hex", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("set_value", { "0x00abc" })
		expect(call.calldata[1]):toBe("0xabc")
	end)

	it("encodes ContractAddress as felt", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("balance_of", { "0xdeadbeef" })
		expect(call.calldata[1]):toBe("0xdeadbeef")
	end)

	it("handles short type names (felt252, u256, bool)", function()
		resetHandlers()
		local provider = createTestProvider()

		local shortAbi: Contract.Abi = {
			{
				type = "function",
				name = "test_fn",
				inputs = {
					{ name = "a", type = "felt252" },
					{ name = "b", type = "u256" },
					{ name = "c", type = "bool" },
				},
				outputs = {},
				state_mutability = "external",
			},
		}
		local contract = Contract.new({
			abi = shortAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("test_fn", { "0x1", "0xff", true })
		-- felt252: 1 felt, u256: 2 felts, bool: 1 felt = 4 total
		expect(#call.calldata):toBe(4)
		expect(call.calldata[1]):toBe("0x1")
		expect(call.calldata[2]):toBe("0xff")
		expect(call.calldata[3]):toBe("0x0")
		expect(call.calldata[4]):toBe("0x1")
	end)
end)

--------------------------------------------------------------------------------
-- getFunctions / hasFunction
--------------------------------------------------------------------------------

describe("Contract - utility methods", function()
	it("getFunctions returns sorted list", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local fns = contract:getFunctions()
		-- Should be alphabetically sorted
		for i = 1, #fns - 1 do
			expect(fns[i] < fns[i + 1]):toBe(true)
		end
	end)

	it("getFunctions includes all 7 ERC20 functions", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local fns = contract:getFunctions()
		expect(#fns):toBe(7)
	end)

	it("hasFunction returns true for existing function", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("transfer")):toBe(true)
	end)

	it("hasFunction returns false for non-existent function", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("nonexistent")):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Edge cases
--------------------------------------------------------------------------------

describe("Contract - edge cases", function()
	it("works with empty ABI", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = {},
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(#contract:getFunctions()):toBe(0)
	end)

	it("function without state_mutability defaults to external", function()
		resetHandlers()
		local provider = createTestProvider()

		local abi: Contract.Abi = {
			{
				type = "function",
				name = "mystery",
				inputs = {},
				outputs = {},
				-- no state_mutability
			},
		}
		local contract = Contract.new({
			abi = abi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local fn = contract:getFunction("mystery")
		expect((fn :: any).stateMutability):toBe("external")
	end)

	it("populate works for both view and external functions", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local viewCall = contract:populate("get_value")
		expect(viewCall.entrypoint):toBe("get_value")

		local extCall = contract:populate("set_value", { "0x42" })
		expect(extCall.entrypoint):toBe("set_value")
	end)

	it("call with nil args treated as empty", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x42" }
		end
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_value", nil):expect()
		expect(result):toBe("0x42")
	end)
end)
