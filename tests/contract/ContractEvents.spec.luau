--!strict
local serde = require("@lune/serde")

local Contract = require("../../src/contract/Contract")
local Keccak = require("../../src/crypto/Keccak")
local StarkField = require("../../src/crypto/StarkField")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local CONTRACT_ADDR = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

-- Compute selectors for test events
local TRANSFER_SELECTOR = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))
local APPROVAL_SELECTOR = StarkField.toHex(Keccak.getSelectorFromName("Approval"))

--------------------------------------------------------------------------------
-- Test ABIs
--------------------------------------------------------------------------------

-- ABI with modern Cairo events (kind="struct" with key/data members)
local MODERN_EVENT_ABI: Contract.Abi = {
	{
		type = "function",
		name = "balance_of",
		inputs = { { name = "account", type = "core::starknet::contract_address::ContractAddress" } },
		outputs = { { name = "balance", type = "core::integer::u256" } },
		state_mutability = "view",
	} :: any,
	{
		type = "event",
		name = "Transfer",
		kind = "struct",
		members = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "value", type = "core::integer::u256", kind = "data" },
		},
	} :: any,
	{
		type = "event",
		name = "Approval",
		kind = "struct",
		members = {
			{ name = "owner", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "spender", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "value", type = "core::integer::u256", kind = "data" },
		},
	} :: any,
}

-- ABI with legacy events (inputs array, no kind annotations)
local LEGACY_EVENT_ABI: Contract.Abi = {
	{
		type = "function",
		name = "name",
		inputs = {},
		outputs = { { name = "name", type = "core::felt252" } },
		state_mutability = "view",
	},
	{
		type = "event",
		name = "Transfer",
		inputs = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "value", type = "core::integer::u256" },
		},
	} :: any,
}

-- ABI with bool event field
local BOOL_EVENT_ABI: Contract.Abi = {
	{
		type = "event",
		name = "StatusChanged",
		kind = "struct",
		members = {
			{ name = "id", type = "core::felt252", kind = "key" },
			{ name = "active", type = "core::bool", kind = "data" },
		},
	} :: any,
}

-- ABI with nested interface events
local INTERFACE_EVENT_ABI: Contract.Abi = {
	{
		type = "interface",
		name = "IERC20",
		items = {
			{
				type = "function",
				name = "balance_of",
				inputs = { { name = "account", type = "core::felt252" } },
				outputs = { { name = "balance", type = "core::felt252" } },
				state_mutability = "view",
			},
			{
				type = "event",
				name = "Transfer",
				kind = "struct",
				members = {
					{ name = "from", type = "core::felt252", kind = "key" },
					{ name = "to", type = "core::felt252", kind = "key" },
					{ name = "amount", type = "core::felt252", kind = "data" },
				},
			},
		},
	} :: any,
}

--------------------------------------------------------------------------------
-- Mock RPC
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function resetHandlers()
	mockHandlers = {}
	requestLog = {}

	mockHandlers["starknet_call"] = function(_params)
		return { "0x1" }
	end

	mockHandlers["starknet_getEvents"] = function(_params)
		return { events = {} }
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
						error = { code = -32000, message = tostring(result) },
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
				error = { code = -32601, message = `Method not found: {method}` },
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

resetHandlers()

--------------------------------------------------------------------------------
-- Event ABI parsing
--------------------------------------------------------------------------------

describe("Contract - event ABI parsing", function()
	it("parses modern Cairo events with key/data members", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasEvent("Transfer")):toBe(true)
		expect(contract:hasEvent("Approval")):toBe(true)
	end)

	it("parses legacy events with inputs array", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = LEGACY_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasEvent("Transfer")):toBe(true)
	end)

	it("parses events from interface entries", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = INTERFACE_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasEvent("Transfer")):toBe(true)
	end)

	it("returns false for non-existent events", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(contract:hasEvent("NonExistent")):toBe(false)
	end)

	it("getEvents returns sorted event names", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local events = contract:getEvents()
		expect(#events):toBe(2)
		expect(events[1]):toBe("Approval")
		expect(events[2]):toBe("Transfer")
	end)

	it("empty ABI has no events", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = {},
			address = CONTRACT_ADDR,
			provider = provider,
		})

		expect(#contract:getEvents()):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - modern events with key/data
--------------------------------------------------------------------------------

describe("Contract:parseEvents - modern events", function()
	it("decodes Transfer event from receipt", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" }, -- u256(1000)
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].name):toBe("Transfer")
		expect(parsed[1].fields.from):toBe("0xsender")
		expect(parsed[1].fields.to):toBe("0xrecipient")
		expect(parsed[1].fields.value.low):toBe("0x3e8")
		expect(parsed[1].fields.value.high):toBe("0x0")
	end)

	it("decodes Approval event from receipt", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { APPROVAL_SELECTOR, "0xowner", "0xspender" },
					data = { "0x7d0", "0x0" }, -- u256(2000)
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].name):toBe("Approval")
		expect(parsed[1].fields.owner):toBe("0xowner")
		expect(parsed[1].fields.spender):toBe("0xspender")
		expect(parsed[1].fields.value.low):toBe("0x7d0")
	end)

	it("decodes multiple events from a single receipt", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender1", "0xrecipient1" },
					data = { "0x3e8", "0x0" },
				},
				{
					from_address = CONTRACT_ADDR,
					keys = { APPROVAL_SELECTOR, "0xowner1", "0xspender1" },
					data = { "0x7d0", "0x0" },
				},
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender2", "0xrecipient2" },
					data = { "0x1", "0x0" },
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(3)
		expect(parsed[1].name):toBe("Transfer")
		expect(parsed[2].name):toBe("Approval")
		expect(parsed[3].name):toBe("Transfer")
	end)

	it("preserves raw event in parsed output", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local rawEvent = {
			from_address = CONTRACT_ADDR,
			keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
			data = { "0x3e8", "0x0" },
		}

		local receipt = { transaction_hash = "0xabc", events = { rawEvent } }
		local parsed = contract:parseEvents(receipt)
		expect(parsed[1].raw):toBeTruthy()
		expect(parsed[1].raw.from_address):toBe(CONTRACT_ADDR)
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - filtering
--------------------------------------------------------------------------------

describe("Contract:parseEvents - address filtering", function()
	it("filters out events from other contracts", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" },
				},
				{
					from_address = "0xother_contract",
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" },
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].fields.from):toBe("0xsender")
	end)

	it("skips events with unknown selectors", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { "0xdeadbeefunknown", "0xsender" },
					data = { "0x3e8" },
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(0)
	end)

	it("returns empty array for receipt with no events", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = { transaction_hash = "0xabc", events = {} }
		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(0)
	end)

	it("handles receipt with nil events field", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = { transaction_hash = "0xabc" }
		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(0)
	end)

	it("handles events with empty keys array", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{ from_address = CONTRACT_ADDR, keys = {}, data = { "0x1" } },
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - legacy events
--------------------------------------------------------------------------------

describe("Contract:parseEvents - legacy events", function()
	it("decodes legacy Transfer event (all fields as data)", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = LEGACY_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR },
					data = { "0xsender", "0xrecipient", "0x3e8", "0x0" }, -- from, to, u256(value)
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].name):toBe("Transfer")
		expect(parsed[1].fields.from):toBe("0xsender")
		expect(parsed[1].fields.to):toBe("0xrecipient")
		expect(parsed[1].fields.value.low):toBe("0x3e8")
		expect(parsed[1].fields.value.high):toBe("0x0")
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - bool decoding
--------------------------------------------------------------------------------

describe("Contract:parseEvents - bool event fields", function()
	it("decodes bool data field correctly (true)", function()
		resetHandlers()
		local provider = createTestProvider()
		local statusSelector = StarkField.toHex(Keccak.getSelectorFromName("StatusChanged"))
		local contract = Contract.new({
			abi = BOOL_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { statusSelector, "0x42" }, -- selector + id key
					data = { "0x1" }, -- active = true
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].name):toBe("StatusChanged")
		expect(parsed[1].fields.id):toBe("0x42")
		expect(parsed[1].fields.active):toBe(true)
	end)

	it("decodes bool data field correctly (false)", function()
		resetHandlers()
		local provider = createTestProvider()
		local statusSelector = StarkField.toHex(Keccak.getSelectorFromName("StatusChanged"))
		local contract = Contract.new({
			abi = BOOL_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { statusSelector, "0x42" },
					data = { "0x0" }, -- active = false
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
		expect(parsed[1].fields.active):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- queryEvents
--------------------------------------------------------------------------------

describe("Contract:queryEvents", function()
	it("queries events with contract address pre-filled", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = CONTRACT_ADDR,
						keys = { TRANSFER_SELECTOR },
						data = { "0x1" },
						block_number = 100,
					},
				},
			}
		end

		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local result = contract:queryEvents():expect()
		expect(#result.events):toBe(1)

		-- Verify the address was sent in the filter
		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_getEvents" then
				found = true
				local filter = entry.params[1].filter
				expect(filter.address):toBe(CONTRACT_ADDR)
			end
		end
		expect(found):toBe(true)
	end)

	it("passes through filter options", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:queryEvents({
			from_block = { block_number = 50 },
			to_block = { block_number = 100 },
			chunk_size = 25,
		}):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_getEvents" then
				found = true
				local filter = entry.params[1].filter
				expect(filter.from_block.block_number):toBe(50)
				expect(filter.to_block.block_number):toBe(100)
				expect(filter.chunk_size):toBe(25)
			end
		end
		expect(found):toBe(true)
	end)

	it("uses default chunk_size of 100", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:queryEvents():expect()

		for _, entry in requestLog do
			if entry.method == "starknet_getEvents" then
				expect(entry.params[1].filter.chunk_size):toBe(100)
			end
		end
	end)

	it("can filter by event keys", function()
		resetHandlers()
		requestLog = {}
		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		contract:queryEvents({
			keys = { { TRANSFER_SELECTOR } },
		}):expect()

		for _, entry in requestLog do
			if entry.method == "starknet_getEvents" then
				local filter = entry.params[1].filter
				expect(filter.keys[1][1]):toBe(TRANSFER_SELECTOR)
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - case-insensitive address matching
--------------------------------------------------------------------------------

describe("Contract:parseEvents - address normalization", function()
	it("matches events with different address casing", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = "0x049D36570D4E46F48E99674BD3FCC84644DDD6B96F7C741B1562B82F9E004DC7",
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" },
				},
			},
		}

		local parsed = contract:parseEvents(receipt)
		expect(#parsed):toBe(1)
	end)
end)
