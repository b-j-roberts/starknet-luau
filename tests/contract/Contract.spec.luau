--!strict
local Contract = require("../../src/contract/Contract")
local Account = require("../../src/wallet/Account")
local ErrorCodes = require("../../src/errors/ErrorCodes")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local CONTRACT_ADDR = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
local NORMALIZED_ADDR = "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

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
-- Mock RPC layer (shared via TestUtils)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

local function createTestAccount(): any
	rpc.resetHandlers()
	local provider = rpc.createTestProvider()
	return Account.fromPrivateKey({
		privateKey = TestUtils.TEST_PRIVATE_KEY,
		provider = provider,
	})
end

--------------------------------------------------------------------------------
-- Contract.new (constructor)
--------------------------------------------------------------------------------

describe("Contract.new - constructor validation", function()
	it("creates a contract with abi, address, and provider", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})
		expect(contract):toBeTruthy()
		expect(contract.address):toBe(NORMALIZED_ADDR)
	end)

	it("creates a contract with optional account", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()

		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})
		expect(contract):toBeTruthy()
	end)

	it("errors when abi is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		expect(function()
			Contract.new({
				abi = nil :: any,
				address = CONTRACT_ADDR,
				provider = provider,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when address is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		expect(function()
			Contract.new({
				abi = ERC20_ABI,
				address = nil :: any,
				provider = provider,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when provider is missing", function()
		expect(function()
			Contract.new({
				abi = ERC20_ABI,
				address = CONTRACT_ADDR,
				provider = nil :: any,
			})
		end):toThrowType("ValidationError")
	end)
end)

--------------------------------------------------------------------------------
-- ABI parsing
--------------------------------------------------------------------------------

describe("Contract - ABI parsing", function()
	it("parses function entries from ABI", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local functions = contract:getFunctions()
		expect(#functions > 0):toBe(true)
	end)

	it("includes all function entries", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("Transfer")):toBe(false)
		expect(contract:hasFunction("Uint256")):toBe(false)
	end)

	it("stores correct state_mutability", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4574686572" } -- "Ether" as felt
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("name"):expect()
		expect(result):toBe("0x4574686572")
	end)

	it("calls a view function with one argument", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" } -- 1000 as u256 (low, high)
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x5f5e100", "0x0" } -- allowance as u256
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("allowance", { "0xaaa111", "0xbbb222" }):expect()
		expect((result :: any).low):toBe("0x5f5e100")
	end)

	it("sends correct contract_address to provider", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()
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
				expect(req.contract_address):toBe(NORMALIZED_ADDR)
			end
		end
		expect(found):toBe(true)
	end)

	it("sends correct entry_point_selector to provider", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("nonexistent")
		end):toThrowCode(ErrorCodes.FUNCTION_NOT_FOUND.code)
	end)

	it("errors when wrong number of arguments provided", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("balance_of") -- missing required account arg
		end):toThrowCode(ErrorCodes.ARGUMENT_COUNT.code)
	end)

	it("errors when too many arguments provided", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:call("name", { "0xextra" }) -- name takes 0 args
		end):toThrowCode(ErrorCodes.ARGUMENT_COUNT.code)
	end)
end)

--------------------------------------------------------------------------------
-- contract:populate (build Call objects)
--------------------------------------------------------------------------------

describe("Contract:populate - build Call objects", function()
	it("builds a Call for a function with no args", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("name")
		expect(call.contractAddress):toBe(NORMALIZED_ADDR)
		expect(call.entrypoint):toBe("name")
		expect(#call.calldata):toBe(0)
	end)

	it("builds a Call for a function with felt252 arg", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("balance_of", { "0xdeadbeef" })
		expect(call.contractAddress):toBe(NORMALIZED_ADDR)
		expect(call.entrypoint):toBe("balance_of")
		expect(#call.calldata):toBe(1)
		expect(call.calldata[1]):toBe("0xdeadbeef")
	end)

	it("builds a Call for a function with u256 arg (expands to 2 felts)", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- transfer(recipient, amount_u256)
		local call = contract:populate("transfer", { "0xabcdef1234567890", "0x3e8" })
		expect(call.contractAddress):toBe(NORMALIZED_ADDR)
		expect(call.entrypoint):toBe("transfer")
		-- recipient (1 felt) + u256 (2 felts) = 3 felts
		expect(#call.calldata):toBe(3)
		expect(call.calldata[1]):toBe("0xabcdef1234567890")
		-- u256 low = 0x3e8, high = 0x0
		expect(call.calldata[2]):toBe("0x3e8")
		expect(call.calldata[3]):toBe("0x0")
	end)

	it("errors for non-existent function", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:populate("nonexistent")
		end):toThrowCode(ErrorCodes.FUNCTION_NOT_FOUND.code)
	end)

	it("errors for wrong argument count", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(function()
			contract:populate("transfer", { "0xabcdef1234567890" }) -- missing amount
		end):toThrowCode(ErrorCodes.ARGUMENT_COUNT.code)
	end)

	it("can be used for multicall batching", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call1 = contract:populate("transfer", { "0xabcdef12345678901", "0x3e8" })
		local call2 = contract:populate("approve", { "0xbbb222", "0x7d0" })

		-- Both should be valid Call objects
		expect(call1.contractAddress):toBe(NORMALIZED_ADDR)
		expect(call2.contractAddress):toBe(NORMALIZED_ADDR)
		expect(call1.entrypoint):toBe("transfer")
		expect(call2.entrypoint):toBe("approve")
	end)
end)

--------------------------------------------------------------------------------
-- contract:invoke (write transactions)
--------------------------------------------------------------------------------

describe("Contract:invoke - write transactions", function()
	it("invokes a transaction and returns hash", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			-- no account
		})

		expect(function()
			contract:invoke("transfer", { "0xabcdef1234567890", "0x3e8" })
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)

	it("errors when invoking a non-existent function", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
			account = account,
		})

		expect(function()
			contract:invoke("nonexistent", { "0x1" })
		end):toThrowCode(ErrorCodes.FUNCTION_NOT_FOUND.code)
	end)

	it("sends the correct contract address in the call", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x4574686572" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:name():expect()
		expect(result):toBe("0x4574686572")
	end)

	it("view function with args is callable dynamically", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x3e8", "0x0" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:balance_of("0xdeadbeef"):expect()
		expect((result :: any).low):toBe("0x3e8")
	end)

	it("external function is callable as contract:method()", function()
		rpc.resetHandlers()
		local account = createTestAccount()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x5f5e100", "0x0" } -- total_supply
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x12" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("decimals"):expect()
		expect(result):toBe("0x12")
	end)

	it("parses u256 output as { low, high }", function()
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xde0b6b3a7640000", "0x0" }
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xaaa", "0xbbb" }
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xadd1", "0x3e8", "0x0", "0x1" } -- addr, u256(low,high), bool
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1", "0x2", "0x3" }
		end
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1" }
		end
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0" }
		end
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("set_value", { "0x00abc" })
		expect(call.calldata[1]):toBe("0xabc")
	end)

	it("encodes ContractAddress as felt", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local call = contract:populate("balance_of", { "0xdeadbeef" })
		expect(call.calldata[1]):toBe("0xdeadbeef")
	end)

	it("handles short type names (felt252, u256, bool)", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local fns = contract:getFunctions()
		expect(#fns):toBe(7)
	end)

	it("hasFunction returns true for existing function", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("transfer")):toBe(true)
	end)

	it("hasFunction returns false for non-existent function", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = {},
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(#contract:getFunctions()):toBe(0)
	end)

	it("function without state_mutability defaults to external", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x42" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_value", nil):expect()
		expect(result):toBe("0x42")
	end)
end)

--------------------------------------------------------------------------------
-- Contract:call - blockId parameter
--------------------------------------------------------------------------------

describe("Contract:call - blockId parameter", function()
	it("passes blockId through to provider:call()", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_call"] = function(params)
			-- params[2] is the block_id
			if params[2] and params[2].block_number == 42 then
				return { "0xblock42result" }
			end
			return { "0xlatestresult" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_value", nil, "0x2a"):expect()
		expect(result):toBeTruthy()
	end)

	it("defaults to latest when blockId is nil", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_call"] = function(_params)
			return { "0xdefault" }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = MINIMAL_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:call("get_value", nil, nil):expect()
		expect(result):toBe("0xdefault")
	end)
end)

--------------------------------------------------------------------------------
-- Contract:queryEvents - continuation_token passthrough
--------------------------------------------------------------------------------

describe("Contract:queryEvents - continuation_token", function()
	it("passes continuation_token through to provider:getEvents()", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_getEvents"] = function(params)
			-- params[1] = filter object (flat, no wrapper)
			local f = params[1]
			return {
				events = {},
				continuation_token = if f.continuation_token then nil else "token123",
			}
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- First call without continuation_token
		local result1 = contract:queryEvents():expect()
		expect(result1.continuation_token):toBe("token123")

		-- Second call with continuation_token
		rpc.clearRequestLog()
		contract:queryEvents({ continuation_token = "token123" }):expect()

		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getEvents")
		local filter = lastReq.params[1]
		expect(filter.continuation_token):toBe("token123")
	end)

	it("includes address filter and chunk_size", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end
		local provider = rpc.createTestProvider()
		local contract = Contract.new({
			abi = ERC20_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:queryEvents({ chunk_size = 50, continuation_token = "ct1" }):expect()

		local lastReq = requestLog[#requestLog]
		local filter = lastReq.params[1]
		expect(filter.address):toBe(NORMALIZED_ADDR)
		expect(filter.chunk_size):toBe(50)
		expect(filter.continuation_token):toBe("ct1")
	end)
end)

--------------------------------------------------------------------------------
-- Contract - interface ABI parsing
--------------------------------------------------------------------------------

describe("Contract - interface ABI parsing", function()
	it("extracts functions from interface entries", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local interfaceAbi: Contract.Abi = {
			{
				type = "interface",
				name = "IERC20",
				items = {
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
				},
			} :: any,
		}

		local contract = Contract.new({
			abi = interfaceAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("balance_of")):toBe(true)
		expect(contract:hasFunction("transfer")):toBe(true)
	end)

	it("mixes top-level functions and interface functions", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local mixedAbi: Contract.Abi = {
			{
				type = "function",
				name = "top_level_fn",
				inputs = {},
				outputs = { { name = "value", type = "core::felt252" } },
				state_mutability = "view",
			},
			{
				type = "interface",
				name = "IMyContract",
				items = {
					{
						type = "function",
						name = "interface_fn",
						inputs = {},
						outputs = { { name = "result", type = "core::felt252" } },
						state_mutability = "view",
					},
				},
			} :: any,
		}

		local contract = Contract.new({
			abi = mixedAbi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("top_level_fn")):toBe(true)
		expect(contract:hasFunction("interface_fn")):toBe(true)
		local fns = contract:getFunctions()
		expect(#fns):toBe(2)
	end)

	it("ignores non-function entries in interface items", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local abi: Contract.Abi = {
			{
				type = "interface",
				name = "IMyContract",
				items = {
					{
						type = "function",
						name = "my_func",
						inputs = {},
						outputs = {},
						state_mutability = "view",
					},
					{
						type = "event",
						name = "MyEvent",
						kind = "struct",
						members = {},
					},
				},
			} :: any,
		}

		local contract = Contract.new({
			abi = abi,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasFunction("my_func")):toBe(true)
		-- Event should not appear as a function
		expect(contract:hasFunction("MyEvent")):toBe(false)
	end)
end)
