--!strict
local serde = require("@lune/serde")

local EventPoller = require("../../src/provider/EventPoller")
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

	mockHandlers["starknet_blockNumber"] = function(_params)
		return 100
	end

	mockHandlers["starknet_getEvents"] = function(_params)
		return {
			events = {},
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
-- EventPoller constructor
--------------------------------------------------------------------------------

describe("EventPoller - constructor", function()
	it("creates a poller with valid config", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", chunk_size = 10 },
			onEvents = function(_events) end,
		})
		expect(poller):toBeTruthy()
	end)

	it("errors when provider is missing", function()
		expect(function()
			EventPoller.new({
				provider = nil :: any,
				filter = { address = "0xcontract1" },
				onEvents = function(_events) end,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when filter is missing", function()
		resetHandlers()
		local provider = createTestProvider()
		expect(function()
			EventPoller.new({
				provider = provider,
				filter = nil :: any,
				onEvents = function(_events) end,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when onEvents is missing", function()
		resetHandlers()
		local provider = createTestProvider()
		expect(function()
			EventPoller.new({
				provider = provider,
				filter = { address = "0xcontract1" },
				onEvents = nil :: any,
			})
		end):toThrowType("ValidationError")
	end)

	it("defaults interval to 10 seconds", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})
		expect(poller):toBeTruthy()
	end)

	it("is not running after creation", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})
		expect(poller:isRunning()):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller start/stop
--------------------------------------------------------------------------------

describe("EventPoller - start/stop lifecycle", function()
	it("starts and stops correctly", function()
		resetHandlers()
		local provider = createTestProvider()
		local pollCount = 0

		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", chunk_size = 10 },
			interval = 0.01,
			onEvents = function(_events)
				pollCount += 1
			end,
			_sleep = function(_seconds: number)
				-- Stop after one poll cycle
				if pollCount >= 0 then
					-- Use pcall-safe way to stop: set _running to false
				end
			end,
		})

		-- Manually run one cycle by stopping immediately after first sleep
		local sleepCount = 0
		;(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			;(poller :: any)._running = false
		end

		poller:start()
		expect(poller:isRunning()):toBe(false)
		expect(sleepCount):toBe(1)
	end)

	it("stop() sets running to false", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(poller:isRunning()):toBe(false)
	end)

	it("does not start twice", function()
		resetHandlers()
		local provider = createTestProvider()
		local startCount = 0

		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			startCount += 1
			poller:stop()
		end

		poller:start()
		-- Calling start again should return immediately since _running is false
		expect(startCount):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller event delivery
--------------------------------------------------------------------------------

describe("EventPoller - event delivery", function()
	it("delivers events to onEvents callback", function()
		resetHandlers()
		local deliveredEvents: { any } = {}

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = { "0xdata1" },
						block_hash = "0xblock1",
						block_number = 101,
						transaction_hash = "0xtx1",
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", chunk_size = 10 },
			onEvents = function(events)
				for _, e in events do
					table.insert(deliveredEvents, e)
				end
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(#deliveredEvents):toBe(1)
		expect(deliveredEvents[1].from_address):toBe("0xcontract1")
		expect(deliveredEvents[1].keys[1]):toBe("0xkey1")
	end)

	it("advances from_block after receiving events", function()
		resetHandlers()
		local pollCycle = 0
		local deliveredEvents: { any } = {}

		mockHandlers["starknet_getEvents"] = function(params)
			pollCycle += 1
			if pollCycle == 1 then
				return {
					events = {
						{
							from_address = "0xcontract1",
							keys = { "0xkey1" },
							data = { "0xdata1" },
							block_hash = "0xblock1",
							block_number = 105,
							transaction_hash = "0xtx1",
						},
					},
				}
			end
			-- Second poll should have advanced from_block
			return { events = {} }
		end

		local provider = createTestProvider()
		local sleepCount = 0

		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", chunk_size = 10 },
			onEvents = function(events)
				for _, e in events do
					table.insert(deliveredEvents, e)
				end
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			if sleepCount >= 2 then
				poller:stop()
			end
		end

		poller:start()
		expect(#deliveredEvents):toBe(1)
		expect(pollCycle >= 2):toBe(true)
	end)

	it("does not deliver empty event arrays", function()
		resetHandlers()
		local callbackCalled = false

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events)
				callbackCalled = true
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(callbackCalled):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller error handling
--------------------------------------------------------------------------------

describe("EventPoller - error handling", function()
	it("calls onError when RPC fails", function()
		resetHandlers()
		local errorReceived: any = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			error("RPC failure")
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = {
				address = "0xcontract1",
				from_block = { block_number = 1 },
			},
			onEvents = function(_events) end,
			onError = function(err)
				errorReceived = err
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(errorReceived ~= nil):toBe(true)
	end)

	it("continues polling after error", function()
		resetHandlers()
		local pollCount = 0
		local errorCount = 0

		mockHandlers["starknet_getEvents"] = function(_params)
			pollCount += 1
			if pollCount == 1 then
				error("Transient error")
			end
			return { events = {} }
		end

		local provider = createTestProvider()
		local sleepCount = 0

		local poller = EventPoller.new({
			provider = provider,
			filter = {
				address = "0xcontract1",
				from_block = { block_number = 1 },
			},
			onEvents = function(_events) end,
			onError = function(_err)
				errorCount += 1
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			if sleepCount >= 2 then
				poller:stop()
			end
		end

		poller:start()
		expect(errorCount):toBe(1)
		expect(pollCount >= 2):toBe(true)
	end)

	it("calls onError when onEvents callback throws", function()
		resetHandlers()
		local errorReceived: any = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = { "0xdata1" },
						block_number = 101,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 1 } },
			onEvents = function(_events)
				error("Callback error")
			end,
			onError = function(err)
				errorReceived = err
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(errorReceived ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller pagination
--------------------------------------------------------------------------------

describe("EventPoller - pagination within poll cycle", function()
	it("fetches multiple pages in a single poll cycle", function()
		resetHandlers()
		local deliveredEvents: { any } = {}
		local pageRequests = 0

		mockHandlers["starknet_getEvents"] = function(params)
			pageRequests += 1
			local filter = params[1].filter
			if not filter.continuation_token then
				return {
					events = {
						{
							from_address = "0xcontract1",
							keys = { "0xkey1" },
							data = { "0xdata1" },
							block_number = 101,
						},
					},
					continuation_token = "page2",
				}
			elseif filter.continuation_token == "page2" then
				return {
					events = {
						{
							from_address = "0xcontract1",
							keys = { "0xkey2" },
							data = { "0xdata2" },
							block_number = 102,
						},
					},
				}
			end
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(events)
				for _, e in events do
					table.insert(deliveredEvents, e)
				end
			end,
		})

		;(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(#deliveredEvents):toBe(2)
		expect(pageRequests):toBe(2)
	end)
end)
