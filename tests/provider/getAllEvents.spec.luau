--!strict
local serde = require("@lune/serde")

local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function resetHandlers()
	mockHandlers = {}
	requestLog = {}
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
		local events = provider:getAllEvents({
			address = "0xcontract1",
			chunk_size = 100,
		}):expect()

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
		local events = provider:getAllEvents({
			address = "0xcontract1",
		}):expect()

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
		local events = provider:getAllEvents({
			address = "0xc1",
			chunk_size = 1,
		}):expect()

		expect(#events):toBe(3)
		expect(pageCount):toBe(3)
		expect(events[1].keys[1]):toBe("0xk1")
		expect(events[2].keys[1]):toBe("0xk2")
		expect(events[3].keys[1]):toBe("0xk3")
	end)

	it("passes filter parameters to each page request", function()
		resetHandlers()
		requestLog = {}

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		provider:getAllEvents({
			address = "0xcontract1",
			from_block = { block_number = 50 },
			to_block = { block_number = 200 },
			keys = { { "0xselector" } },
			chunk_size = 25,
		}):expect()

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
		requestLog = {}

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		provider:getAllEvents({
			address = "0xcontract1",
		}):expect()

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
			provider:getAllEvents({
				address = "0xcontract1",
			}):expect()
		end):toThrow()
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
			provider:getAllEvents({
				address = "0xc1",
			}):expect()
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- getAllEvents - continuation_token passthrough
--------------------------------------------------------------------------------

describe("RpcProvider:getAllEvents - initial continuation token", function()
	it("starts from provided continuation_token", function()
		resetHandlers()
		requestLog = {}

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
		local events = provider:getAllEvents({
			address = "0xc1",
			continuation_token = "start_here",
		}):expect()

		expect(#events):toBe(1)
		local filter = requestLog[1].params[1].filter
		expect(filter.continuation_token):toBe("start_here")
	end)
end)
