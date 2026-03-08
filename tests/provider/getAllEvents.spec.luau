--!strict

local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Mock RPC layer (shared TestUtils infrastructure)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

local function resetHandlers()
	rpc.resetHandlers()
end

local function createTestProvider(): any
	return rpc.createTestProvider()
end

resetHandlers()

--------------------------------------------------------------------------------
-- getAllEvents - single page
--------------------------------------------------------------------------------

describe("RpcProvider:getAllEvents - single page", function()
	it("returns all events from a single page", function()
		resetHandlers()
		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = { "0xdata1" },
						block_hash = "0xblock1",
						block_number = 100,
						transaction_hash = "0xtx1",
					},
					{
						from_address = "0xcontract1",
						keys = { "0xkey2" },
						data = { "0xdata2" },
						block_hash = "0xblock1",
						block_number = 100,
						transaction_hash = "0xtx2",
					},
				},
			}
		end

		local provider = createTestProvider()
		local events = provider
			:getAllEvents({
				address = "0xcontract1",
				chunk_size = 100,
			})
			:expect()

		expect(#events):toBe(2)
		expect(events[1].from_address):toBe("0xcontract1")
		expect(events[2].keys[1]):toBe("0xkey2")
	end)

	it("returns empty array when no events match", function()
		resetHandlers()
		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local events = provider
			:getAllEvents({
				address = "0xcontract1",
			})
			:expect()

		expect(#events):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- getAllEvents - multi-page pagination
--------------------------------------------------------------------------------

describe("RpcProvider:getAllEvents - pagination", function()
	it("follows continuation tokens across pages", function()
		resetHandlers()
		local pageCount = 0

		mockHandlers["starknet_getEvents"] = function(params)
			pageCount += 1
			local filter = params[1].filter

			if not filter.continuation_token then
				return {
					events = {
						{
							from_address = "0xc1",
							keys = { "0xk1" },
							data = { "0xd1" },
							block_number = 100,
						},
					},
					continuation_token = "token_page2",
				}
			elseif filter.continuation_token == "token_page2" then
				return {
					events = {
						{
							from_address = "0xc1",
							keys = { "0xk2" },
							data = { "0xd2" },
							block_number = 101,
						},
					},
					continuation_token = "token_page3",
				}
			elseif filter.continuation_token == "token_page3" then
				return {
					events = {
						{
							from_address = "0xc1",
							keys = { "0xk3" },
							data = { "0xd3" },
							block_number = 102,
						},
					},
				}
			end

			return { events = {} }
		end

		local provider = createTestProvider()
		local events = provider
			:getAllEvents({
				address = "0xc1",
				chunk_size = 1,
			})
			:expect()

		expect(#events):toBe(3)
		expect(pageCount):toBe(3)
		expect(events[1].keys[1]):toBe("0xk1")
		expect(events[2].keys[1]):toBe("0xk2")
		expect(events[3].keys[1]):toBe("0xk3")
	end)

	it("passes filter parameters to each page request", function()
		resetHandlers()
		rpc.clearRequestLog()

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		provider
			:getAllEvents({
				address = "0xcontract1",
				from_block = { block_number = 50 },
				to_block = { block_number = 200 },
				keys = { { "0xselector" } },
				chunk_size = 25,
			})
			:expect()

		expect(#requestLog >= 1):toBe(true)
		local params = requestLog[1].params
		local filter = params[1].filter
		expect(filter.address):toBe("0xcontract1")
		expect(filter.chunk_size):toBe(25)
		expect(filter.from_block.block_number):toBe(50)
		expect(filter.to_block.block_number):toBe(200)
	end)

	it("uses default chunk_size of 100", function()
		resetHandlers()
		rpc.clearRequestLog()

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		provider
			:getAllEvents({
				address = "0xcontract1",
			})
			:expect()

		local filter = requestLog[1].params[1].filter
		expect(filter.chunk_size):toBe(100)
	end)
end)

--------------------------------------------------------------------------------
-- getAllEvents - error handling
--------------------------------------------------------------------------------

describe("RpcProvider:getAllEvents - error handling", function()
	it("rejects when RPC returns error", function()
		resetHandlers()
		mockHandlers["starknet_getEvents"] = function(_params)
			error("Page size too large")
		end

		local provider = createTestProvider()
		expect(function()
			provider
				:getAllEvents({
					address = "0xcontract1",
				})
				:expect()
		end):toThrowType("RpcError")
	end)

	it("rejects on network error during pagination", function()
		resetHandlers()
		local callCount = 0

		mockHandlers["starknet_getEvents"] = function(_params)
			callCount += 1
			if callCount == 1 then
				return {
					events = { { from_address = "0xc1", keys = { "0xk1" }, data = {}, block_number = 100 } },
					continuation_token = "page2",
				}
			end
			error("Network timeout")
		end

		local provider = createTestProvider()
		expect(function()
			provider
				:getAllEvents({
					address = "0xc1",
				})
				:expect()
		end):toThrowType("RpcError")
	end)
end)

--------------------------------------------------------------------------------
-- getAllEvents - continuation_token passthrough
--------------------------------------------------------------------------------

describe("RpcProvider:getAllEvents - initial continuation token", function()
	it("starts from provided continuation_token", function()
		resetHandlers()
		rpc.clearRequestLog()

		mockHandlers["starknet_getEvents"] = function(params)
			local filter = params[1].filter
			if filter.continuation_token == "start_here" then
				return {
					events = {
						{ from_address = "0xc1", keys = { "0xk1" }, data = {}, block_number = 100 },
					},
				}
			end
			return { events = {} }
		end

		local provider = createTestProvider()
		local events = provider
			:getAllEvents({
				address = "0xc1",
				continuation_token = "start_here",
			})
			:expect()

		expect(#events):toBe(1)
		local filter = requestLog[1].params[1].filter
		expect(filter.continuation_token):toBe("start_here")
	end)
end)
