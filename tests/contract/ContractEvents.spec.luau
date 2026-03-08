--!strict
local Contract = require("../../src/contract/Contract")
local Keccak = require("../../src/crypto/Keccak")
local StarkField = require("../../src/crypto/StarkField")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local CONTRACT_ADDR = TestUtils.TEST_ADDRESS
local NORMALIZED_ADDR = "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

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

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

-- Override defaults with event-specific handlers
local function resetHandlers()
	rpc.resetHandlers()

	mockHandlers["starknet_getEvents"] = function(_params)
		return { events = {} }
	end
end

local function createTestProvider(): any
	return rpc.createTestProvider()
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("Transfer")
		expect(result.events[1].fields.from):toBe("0xsender")
		expect(result.events[1].fields.to):toBe("0xrecipient")
		expect(result.events[1].fields.value.low):toBe("0x3e8")
		expect(result.events[1].fields.value.high):toBe("0x0")
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("Approval")
		expect(result.events[1].fields.owner):toBe("0xowner")
		expect(result.events[1].fields.spender):toBe("0xspender")
		expect(result.events[1].fields.value.low):toBe("0x7d0")
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(3)
		expect(result.events[1].name):toBe("Transfer")
		expect(result.events[2].name):toBe("Approval")
		expect(result.events[3].name):toBe("Transfer")
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
		local result = contract:parseEvents(receipt)
		expect(result.events[1].raw):toBeTruthy()
		expect(result.events[1].raw.from_address):toBe(CONTRACT_ADDR)
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].fields.from):toBe("0xsender")
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
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
		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
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
		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("Transfer")
		expect(result.events[1].fields.from):toBe("0xsender")
		expect(result.events[1].fields.to):toBe("0xrecipient")
		expect(result.events[1].fields.value.low):toBe("0x3e8")
		expect(result.events[1].fields.value.high):toBe("0x0")
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("StatusChanged")
		expect(result.events[1].fields.id):toBe("0x42")
		expect(result.events[1].fields.active):toBe(true)
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].fields.active):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- queryEvents
--------------------------------------------------------------------------------

describe("Contract:queryEvents", function()
	it("queries events with contract address pre-filled", function()
		resetHandlers()
		rpc.clearRequestLog()
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
				expect(filter.address):toBe(NORMALIZED_ADDR)
			end
		end
		expect(found):toBe(true)
	end)

	it("passes through filter options", function()
		resetHandlers()
		rpc.clearRequestLog()
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
		rpc.clearRequestLog()
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
		rpc.clearRequestLog()
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

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
	end)

	it("matches events with leading-zero mismatch (0x049d vs 0x49d)", function()
		resetHandlers()
		local provider = createTestProvider()
		-- Contract created with leading zero in address
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					-- RPC returns address WITHOUT leading zero
					from_address = "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" },
				},
			},
		}

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("Transfer")
	end)

	it("matches events when contract has no leading zero but event does", function()
		resetHandlers()
		local provider = createTestProvider()
		-- Contract created WITHOUT leading zero
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			provider = provider,
		})

		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					-- RPC returns address WITH leading zero
					from_address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" },
				},
			},
		}

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(result.events[1].name):toBe("Transfer")
	end)

	it("normalizes contract address on construction", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			provider = provider,
		})

		-- Public address should be normalized (leading zero stripped)
		expect(contract.address):toBe("0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)
end)

--------------------------------------------------------------------------------
-- parseEvents - error handling (R.3.3)
--------------------------------------------------------------------------------

describe("Contract:parseEvents - error handling", function()
	it("returns ParseEventsResult with events and errors fields", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = { transaction_hash = "0xabc", events = {} }
		local result = contract:parseEvents(receipt)
		expect(result.events):toBeTruthy()
		expect(result.errors):toBeTruthy()
		expect(#result.events):toBe(0)
		expect(#result.errors):toBe(0)
	end)

	it("collects decode errors in errors array by default", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		-- Transfer event with truncated data (u256 needs 2 felts, only 1 provided)
		local receipt = {
			transaction_hash = "0xabc",
			events = {
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8" }, -- missing high word for u256
				},
			},
		}

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
		expect(#result.errors):toBe(1)
		expect(result.errors[1].event):toBeTruthy()
		expect(type(result.errors[1].error)):toBe("string")
	end)

	it("preserves raw event reference in error entry", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local badEvent = {
			from_address = CONTRACT_ADDR,
			keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
			data = {}, -- completely empty data for u256 event
		}
		local receipt = { transaction_hash = "0xabc", events = { badEvent } }

		local result = contract:parseEvents(receipt)
		expect(#result.errors):toBe(1)
		expect(result.errors[1].event.from_address):toBe(CONTRACT_ADDR)
	end)

	it("in strict mode, re-throws decode errors", function()
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
					data = { "0x3e8" }, -- truncated u256
				},
			},
		}

		expect(function()
			contract:parseEvents(receipt, { strict = true })
		end):toThrow()
	end)

	it("mixes successful and failed events correctly", function()
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
				-- Good event
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender", "0xrecipient" },
					data = { "0x3e8", "0x0" }, -- valid u256
				},
				-- Bad event (truncated data)
				{
					from_address = CONTRACT_ADDR,
					keys = { TRANSFER_SELECTOR, "0xsender2", "0xrecipient2" },
					data = { "0x1" }, -- truncated u256
				},
				-- Good event
				{
					from_address = CONTRACT_ADDR,
					keys = { APPROVAL_SELECTOR, "0xowner", "0xspender" },
					data = { "0x7d0", "0x0" }, -- valid u256
				},
			},
		}

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(2)
		expect(#result.errors):toBe(1)
		expect(result.events[1].name):toBe("Transfer")
		expect(result.events[2].name):toBe("Approval")
	end)

	it("returns empty errors when all events decode successfully", function()
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
			},
		}

		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(1)
		expect(#result.errors):toBe(0)
	end)

	it("returns events and errors as empty arrays for nil events field", function()
		resetHandlers()
		local provider = createTestProvider()
		local contract = Contract.new({
			abi = MODERN_EVENT_ABI,
			address = CONTRACT_ADDR,
			provider = provider,
		})

		local receipt = { transaction_hash = "0xabc" }
		local result = contract:parseEvents(receipt)
		expect(#result.events):toBe(0)
		expect(#result.errors):toBe(0)
	end)
end)
