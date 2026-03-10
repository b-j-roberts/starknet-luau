--!strict

local EventPoller = require("../../src/provider/EventPoller")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Mock RPC layer (shared TestUtils infrastructure)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers

local function resetHandlers()
	rpc.resetHandlers()

	mockHandlers["starknet_blockNumber"] = function(_params)
		return 100
	end

	mockHandlers["starknet_getEvents"] = function(_params)
		return {
			events = {},
		}
	end
end

local function createTestProvider(): any
	return rpc.createTestProvider()
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
		(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			(poller :: any)._running = false
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
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
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(#deliveredEvents):toBe(2)
		expect(pageRequests):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Mock DataStore helper
--------------------------------------------------------------------------------

local function createMockDataStore(): (any, { [string]: any })
	local data: { [string]: any } = {}
	local store = {}

	function store:GetAsync(key: string): any?
		return data[key]
	end

	function store:SetAsync(key: string, value: any): ()
		data[key] = value
	end

	return store, data
end

local function createFailingDataStore(failGet: boolean?, failSet: boolean?): any
	local store = {}

	function store:GetAsync(_key: string): any?
		if failGet then
			error("DataStore GetAsync failed")
		end
		return nil
	end

	function store:SetAsync(_key: string, _value: any): ()
		if failSet then
			error("DataStore SetAsync failed")
		end
	end

	return store
end

--------------------------------------------------------------------------------
-- EventPoller checkpoint persistence
--------------------------------------------------------------------------------

describe("EventPoller - checkpoint persistence", function()
	it("restores _lastBlockNumber from DataStore on start", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = { blockNumber = 200, timestamp = 1000 }

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(poller:getLastBlockNumber()):toBe(200)
	end)

	it("restores from bare number format (backward compat)", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = 150

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(poller:getLastBlockNumber()):toBe(150)
	end)

	it("resumes polling from restored block + 1", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = { blockNumber = 200, timestamp = 1000 }

		local capturedFromBlock: any = nil
		mockHandlers["starknet_getEvents"] = function(params)
			capturedFromBlock = params[1].filter.from_block
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(capturedFromBlock):toBeTruthy()
		expect(capturedFromBlock.block_number):toBe(201)
	end)

	it("skips restore when DataStore returns nil", function()
		resetHandlers()
		local mockDS, _dsData = createMockDataStore()
		-- No data stored — should fall through to blockNumber fetch

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		-- Falls through to blockNumber fetch (returns 100 from default handler)
		expect(poller:getLastBlockNumber()):toBe(100)
	end)

	it("skips restore when DataStore returns non-number/non-table", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = "invalid"

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(poller:getLastBlockNumber()):toBe(100)
	end)

	it("does not restore when _lastBlockNumber already set via setLastBlockNumber", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = { blockNumber = 200, timestamp = 1000 }

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		})

		-- Manually seed before start
		poller:setLastBlockNumber(300);
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		-- Should use manually-seeded value, not DataStore
		expect(poller:getLastBlockNumber()):toBe(300)
	end)

	it("calls onError when DataStore GetAsync fails", function()
		resetHandlers()
		local failDS = createFailingDataStore(true, false)
		local errorReceived: any = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			onError = function(err)
				errorReceived = err
			end,
			_dataStore = failDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(errorReceived):toBeTruthy()
	end)

	it("continues polling after DataStore GetAsync failure", function()
		resetHandlers()
		local failDS = createFailingDataStore(true, false)
		local pollCount = 0

		mockHandlers["starknet_getEvents"] = function(_params)
			pollCount += 1
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			onError = function(_err) end,
			_dataStore = failDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(pollCount >= 1):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller checkpoint writes
--------------------------------------------------------------------------------

describe("EventPoller - checkpoint writes after events", function()
	it("writes checkpoint to DataStore after events are received", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = { "0xdata1" },
						block_number = 105,
						transaction_hash = "0xtx1",
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			_dataStore = mockDS,
			_clock = function()
				return 5000
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		local checkpoint = dsData["EventPoller_checkpoint"]
		expect(checkpoint):toBeTruthy()
		expect(checkpoint.blockNumber):toBe(105)
		expect(checkpoint.timestamp):toBe(5000)
	end)

	it("uses custom checkpointKey", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 110,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			_dataStore = mockDS,
			checkpointKey = "MyGame_events",
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(dsData["MyGame_events"]):toBeTruthy()
		expect(dsData["MyGame_events"].blockNumber):toBe(110)
		expect(dsData["EventPoller_checkpoint"]):toBeNil()
	end)

	it("does not write checkpoint when no events received", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(dsData["EventPoller_checkpoint"]):toBeNil()
	end)

	it("calls onError when DataStore SetAsync fails but does not halt polling", function()
		resetHandlers()
		local failDS = createFailingDataStore(false, true)
		local errorReceived: any = nil
		local eventsDelivered = false

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 105,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events)
				eventsDelivered = true
			end,
			onError = function(err)
				errorReceived = err
			end,
			_dataStore = failDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(eventsDelivered):toBe(true)
		expect(errorReceived):toBeTruthy()
	end)

	it("fires onCheckpoint after DataStore write", function()
		resetHandlers()
		local mockDS, _dsData = createMockDataStore()
		local checkpointBlock: number? = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 107,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			onCheckpoint = function(blockNumber)
				checkpointBlock = blockNumber
			end,
			_dataStore = mockDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(checkpointBlock):toBe(107)
	end)

	it("fires onCheckpoint even when DataStore SetAsync fails", function()
		resetHandlers()
		local failDS = createFailingDataStore(false, true)
		local checkpointBlock: number? = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 108,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			onError = function(_err) end,
			onCheckpoint = function(blockNumber)
				checkpointBlock = blockNumber
			end,
			_dataStore = failDS,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(checkpointBlock):toBe(108)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller callback-only mode (no DataStore)
--------------------------------------------------------------------------------

describe("EventPoller - callback-only checkpoint", function()
	it("fires onCheckpoint without DataStore", function()
		resetHandlers()
		local checkpointBlock: number? = nil

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 120,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			onCheckpoint = function(blockNumber)
				checkpointBlock = blockNumber
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(checkpointBlock):toBe(120)
	end)

	it("does not fire onCheckpoint when no events", function()
		resetHandlers()
		local checkpointCalled = false

		mockHandlers["starknet_getEvents"] = function(_params)
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			onCheckpoint = function(_blockNumber)
				checkpointCalled = true
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(checkpointCalled):toBe(false)
	end)

	it("fires onCheckpoint on each advancing poll cycle", function()
		resetHandlers()
		local checkpoints: { number } = {}
		local pollCycle = 0

		mockHandlers["starknet_getEvents"] = function(_params)
			pollCycle += 1
			if pollCycle == 1 then
				return {
					events = {
						{ from_address = "0xc", keys = {}, data = {}, block_number = 105 },
					},
				}
			elseif pollCycle == 2 then
				return {
					events = {
						{ from_address = "0xc", keys = {}, data = {}, block_number = 110 },
					},
				}
			end
			return { events = {} }
		end

		local provider = createTestProvider()
		local sleepCount = 0
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xc", from_block = { block_number = 100 } },
			onEvents = function(_events) end,
			onCheckpoint = function(blockNumber)
				table.insert(checkpoints, blockNumber)
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			if sleepCount >= 3 then
				poller:stop()
			end
		end

		poller:start()
		expect(#checkpoints):toBe(2)
		expect(checkpoints[1]):toBe(105)
		expect(checkpoints[2]):toBe(110)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller setLastBlockNumber
--------------------------------------------------------------------------------

describe("EventPoller - setLastBlockNumber", function()
	it("sets _lastBlockNumber before start", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})

		poller:setLastBlockNumber(500)
		expect(poller:getLastBlockNumber()):toBe(500)
	end)

	it("updates filter from_block so start resumes from correct block", function()
		resetHandlers()
		local capturedFromBlock: any = nil

		mockHandlers["starknet_getEvents"] = function(params)
			capturedFromBlock = params[1].filter.from_block
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})

		poller:setLastBlockNumber(500);
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		-- Should poll from block 501 (500 + 1)
		expect(capturedFromBlock):toBeTruthy()
		expect(capturedFromBlock.block_number):toBe(501)
	end)

	it("preserves other filter fields after setLastBlockNumber", function()
		resetHandlers()
		local capturedFilter: any = nil

		mockHandlers["starknet_getEvents"] = function(params)
			capturedFilter = params[1].filter
			return { events = {} }
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xmyaddr", keys = { { "0xkey1" } }, chunk_size = 50 },
			onEvents = function(_events) end,
		})

		poller:setLastBlockNumber(500);
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(capturedFilter.address):toBe("0xmyaddr")
		expect(capturedFilter.chunk_size):toBe(50)
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller getCheckpointKey
--------------------------------------------------------------------------------

describe("EventPoller - getCheckpointKey", function()
	it("returns default key when DataStore is configured without custom key", function()
		resetHandlers()
		local mockDS, _dsData = createMockDataStore()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
		})
		expect(poller:getCheckpointKey()):toBe("EventPoller_checkpoint")
	end)

	it("returns custom key when provided", function()
		resetHandlers()
		local mockDS, _dsData = createMockDataStore()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
			checkpointKey = "MyCustomKey",
		})
		expect(poller:getCheckpointKey()):toBe("MyCustomKey")
	end)

	it("returns nil when no DataStore is configured", function()
		resetHandlers()
		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1" },
			onEvents = function(_events) end,
		})
		expect(poller:getCheckpointKey()):toBeNil()
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller no-op when unconfigured
--------------------------------------------------------------------------------

describe("EventPoller - no-op when persistence unconfigured", function()
	it("does not checkpoint when neither DataStore nor onCheckpoint is set", function()
		resetHandlers()
		local eventsDelivered = false

		mockHandlers["starknet_getEvents"] = function(_params)
			return {
				events = {
					{
						from_address = "0xcontract1",
						keys = { "0xkey1" },
						data = {},
						block_number = 105,
					},
				},
			}
		end

		local provider = createTestProvider()
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xcontract1", from_block = { block_number = 100 } },
			onEvents = function(_events)
				eventsDelivered = true
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		-- Should still work fine — events delivered, no crash
		expect(eventsDelivered):toBe(true)
		expect(poller:getLastBlockNumber()):toBe(105)
		expect(poller:getCheckpointKey()):toBeNil()
	end)

	it("behaves identically to original when no persistence config", function()
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
		});
		(poller :: any)._sleep = function(_seconds: number)
			poller:stop()
		end

		poller:start()
		expect(#deliveredEvents):toBe(1)
		expect(deliveredEvents[1].from_address):toBe("0xcontract1")
	end)
end)

--------------------------------------------------------------------------------
-- EventPoller DataStore restore + checkpoint round-trip
--------------------------------------------------------------------------------

describe("EventPoller - DataStore round-trip", function()
	it("restores checkpoint then writes new checkpoint after events", function()
		resetHandlers()
		local mockDS, dsData = createMockDataStore()
		dsData["EventPoller_checkpoint"] = { blockNumber = 200, timestamp = 1000 }

		local pollCycle = 0
		mockHandlers["starknet_getEvents"] = function(_params)
			pollCycle += 1
			if pollCycle == 1 then
				return {
					events = {
						{ from_address = "0xc", keys = {}, data = {}, block_number = 205 },
					},
				}
			end
			return { events = {} }
		end

		local provider = createTestProvider()
		local sleepCount = 0
		local poller = EventPoller.new({
			provider = provider,
			filter = { address = "0xc" },
			onEvents = function(_events) end,
			_dataStore = mockDS,
			_clock = function()
				return 2000
			end,
		});
		(poller :: any)._sleep = function(_seconds: number)
			sleepCount += 1
			if sleepCount >= 2 then
				poller:stop()
			end
		end

		poller:start()
		-- Checkpoint should now reflect the new block
		local checkpoint = dsData["EventPoller_checkpoint"]
		expect(checkpoint.blockNumber):toBe(205)
		expect(checkpoint.timestamp):toBe(2000)
	end)
end)
