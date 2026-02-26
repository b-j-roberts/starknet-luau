--!strict
local RequestQueue = require("../../src/provider/RequestQueue")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Create a simple resolve/reject pair that captures the value
local function makeCallbacks(): ((any) -> (), (any) -> (), () -> any?, () -> any?)
	local resolvedValue: any = nil
	local rejectedValue: any = nil
	local function resolve(val: any)
		resolvedValue = val
	end
	local function reject(val: any)
		rejectedValue = val
	end
	local function getResolved(): any?
		return resolvedValue
	end
	local function getRejected(): any?
		return rejectedValue
	end
	return resolve, reject, getResolved, getRejected
end

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("RequestQueue - constructor", function()
	it("creates an empty queue", function()
		local q = RequestQueue.new()
		expect(q:depth()):toBe(0)
		expect(q:isEmpty()):toBe(true)
	end)

	it("accepts custom maxQueueDepth", function()
		local q = RequestQueue.new(5)
		expect(q:isEmpty()):toBe(true)
	end)

	it("defaults maxQueueDepth to 100", function()
		local q = RequestQueue.new()
		-- Enqueue 100 items — should all succeed
		for i = 1, 100 do
			local resolve, reject = makeCallbacks()
			q:enqueue("starknet_chainId", {}, resolve, reject)
		end
		expect(q:depth()):toBe(100)
		-- 101st should be rejected
		local _, reject, _, getRejected = makeCallbacks()
		q:enqueue("starknet_chainId", {}, function() end, reject)
		expect(getRejected() ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Priority classification
--------------------------------------------------------------------------------

describe("RequestQueue - priority classification", function()
	it("classifies addInvokeTransaction as high", function()
		expect(RequestQueue.getPriority("starknet_addInvokeTransaction")):toBe("high")
	end)

	it("classifies estimateFee as high", function()
		expect(RequestQueue.getPriority("starknet_estimateFee")):toBe("high")
	end)

	it("classifies getEvents as low", function()
		expect(RequestQueue.getPriority("starknet_getEvents")):toBe("low")
	end)

	it("classifies chainId as normal", function()
		expect(RequestQueue.getPriority("starknet_chainId")):toBe("normal")
	end)

	it("classifies blockNumber as normal", function()
		expect(RequestQueue.getPriority("starknet_blockNumber")):toBe("normal")
	end)

	it("classifies getNonce as normal", function()
		expect(RequestQueue.getPriority("starknet_getNonce")):toBe("normal")
	end)

	it("classifies call as normal", function()
		expect(RequestQueue.getPriority("starknet_call")):toBe("normal")
	end)

	it("classifies unknown methods as normal", function()
		expect(RequestQueue.getPriority("starknet_unknownMethod")):toBe("normal")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Batchable classification
--------------------------------------------------------------------------------

describe("RequestQueue - batchable methods", function()
	it("chainId is batchable", function()
		expect(RequestQueue.isBatchable("starknet_chainId")):toBe(true)
	end)

	it("blockNumber is batchable", function()
		expect(RequestQueue.isBatchable("starknet_blockNumber")):toBe(true)
	end)

	it("specVersion is batchable", function()
		expect(RequestQueue.isBatchable("starknet_specVersion")):toBe(true)
	end)

	it("getNonce is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getNonce")):toBe(true)
	end)

	it("call is batchable", function()
		expect(RequestQueue.isBatchable("starknet_call")):toBe(true)
	end)

	it("getBlockWithTxHashes is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getBlockWithTxHashes")):toBe(true)
	end)

	it("getClassHashAt is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getClassHashAt")):toBe(true)
	end)

	it("getStorageAt is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getStorageAt")):toBe(true)
	end)

	it("getTransactionReceipt is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getTransactionReceipt")):toBe(true)
	end)

	it("getTransactionStatus is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getTransactionStatus")):toBe(true)
	end)

	it("getEvents is batchable", function()
		expect(RequestQueue.isBatchable("starknet_getEvents")):toBe(true)
	end)

	it("addInvokeTransaction is NOT batchable", function()
		expect(RequestQueue.isBatchable("starknet_addInvokeTransaction")):toBe(false)
	end)

	it("estimateFee is NOT batchable", function()
		expect(RequestQueue.isBatchable("starknet_estimateFee")):toBe(false)
	end)

	it("unknown methods are NOT batchable", function()
		expect(RequestQueue.isBatchable("starknet_unknown")):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Enqueue and dequeue
--------------------------------------------------------------------------------

describe("RequestQueue - enqueue/dequeue", function()
	it("enqueues and dequeues a single item", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", { "test" }, resolve, reject)
		expect(q:depth()):toBe(1)
		local item = q:dequeue()
		expect(item ~= nil):toBe(true)
		expect((item :: any).method):toBe("starknet_chainId")
		expect(q:depth()):toBe(0)
	end)

	it("dequeue returns nil on empty queue", function()
		local q = RequestQueue.new()
		local item = q:dequeue()
		expect(item == nil):toBe(true)
	end)

	it("preserves params and callbacks", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getNonce", { "0xaddr", "latest" }, resolve, reject)
		local item = q:dequeue()
		expect(item ~= nil):toBe(true)
		local i = item :: any
		expect(i.params[1]):toBe("0xaddr")
		expect(i.params[2]):toBe("latest")
		-- Verify callbacks work
		i.resolve("0x5")
	end)

	it("assigns unique IDs to items", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_blockNumber", {}, resolve, reject)
		local item1 = q:dequeue() :: any
		local item2 = q:dequeue() :: any
		expect(item1.id ~= item2.id):toBe(true)
	end)

	it("auto-classifies priority from method name", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_addInvokeTransaction", {}, resolve, reject)
		local item = q:dequeue() :: any
		expect(item.priority):toBe("high")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Priority ordering
--------------------------------------------------------------------------------

describe("RequestQueue - priority ordering", function()
	it("dequeues HIGH before NORMAL", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject) -- normal
		q:enqueue("starknet_addInvokeTransaction", {}, resolve, reject) -- high
		local first = q:dequeue() :: any
		expect(first.method):toBe("starknet_addInvokeTransaction")
		local second = q:dequeue() :: any
		expect(second.method):toBe("starknet_chainId")
	end)

	it("dequeues NORMAL before LOW", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getEvents", {}, resolve, reject) -- low
		q:enqueue("starknet_chainId", {}, resolve, reject) -- normal
		local first = q:dequeue() :: any
		expect(first.method):toBe("starknet_chainId")
		local second = q:dequeue() :: any
		expect(second.method):toBe("starknet_getEvents")
	end)

	it("dequeues HIGH before LOW", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getEvents", {}, resolve, reject) -- low
		q:enqueue("starknet_estimateFee", {}, resolve, reject) -- high
		local first = q:dequeue() :: any
		expect(first.method):toBe("starknet_estimateFee")
		local second = q:dequeue() :: any
		expect(second.method):toBe("starknet_getEvents")
	end)

	it("dequeues all three priorities in correct order", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getEvents", {}, resolve, reject) -- low
		q:enqueue("starknet_chainId", {}, resolve, reject) -- normal
		q:enqueue("starknet_addInvokeTransaction", {}, resolve, reject) -- high
		local first = q:dequeue() :: any
		expect(first.priority):toBe("high")
		local second = q:dequeue() :: any
		expect(second.priority):toBe("normal")
		local third = q:dequeue() :: any
		expect(third.priority):toBe("low")
	end)

	it("FIFO within same priority level", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", { "first" }, resolve, reject) -- normal
		q:enqueue("starknet_blockNumber", { "second" }, resolve, reject) -- normal
		q:enqueue("starknet_specVersion", { "third" }, resolve, reject) -- normal
		local first = q:dequeue() :: any
		expect(first.params[1]):toBe("first")
		local second = q:dequeue() :: any
		expect(second.params[1]):toBe("second")
		local third = q:dequeue() :: any
		expect(third.params[1]):toBe("third")
	end)

	it("FIFO within HIGH priority", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_addInvokeTransaction", { "tx1" }, resolve, reject)
		q:enqueue("starknet_estimateFee", { "fee1" }, resolve, reject)
		local first = q:dequeue() :: any
		expect(first.params[1]):toBe("tx1")
		local second = q:dequeue() :: any
		expect(second.params[1]):toBe("fee1")
	end)

	it("FIFO within LOW priority", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getEvents", { "e1" }, resolve, reject)
		q:enqueue("starknet_getEvents", { "e2" }, resolve, reject)
		local first = q:dequeue() :: any
		expect(first.params[1]):toBe("e1")
		local second = q:dequeue() :: any
		expect(second.params[1]):toBe("e2")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: peekPriority
--------------------------------------------------------------------------------

describe("RequestQueue - peekPriority", function()
	it("returns nil for empty queue", function()
		local q = RequestQueue.new()
		expect(q:peekPriority() == nil):toBe(true)
	end)

	it("returns high when high items exist", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject) -- normal
		q:enqueue("starknet_addInvokeTransaction", {}, resolve, reject) -- high
		expect(q:peekPriority()):toBe("high")
	end)

	it("returns normal when only normal items exist", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject) -- normal
		expect(q:peekPriority()):toBe("normal")
	end)

	it("returns low when only low items exist", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_getEvents", {}, resolve, reject) -- low
		expect(q:peekPriority()):toBe("low")
	end)

	it("does not remove items", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:peekPriority()
		expect(q:depth()):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Backpressure
--------------------------------------------------------------------------------

describe("RequestQueue - backpressure", function()
	it("rejects when queue is full", function()
		local q = RequestQueue.new(3)
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_chainId", {}, resolve, reject)
		expect(q:depth()):toBe(3)

		local _, rejectFn, _, getRejected = makeCallbacks()
		q:enqueue("starknet_chainId", {}, function() end, rejectFn)
		local rejected = getRejected()
		expect(rejected ~= nil):toBe(true)
		expect((rejected :: any).code):toBe(2010) -- QUEUE_FULL
	end)

	it("accepts after dequeue frees space", function()
		local q = RequestQueue.new(2)
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:dequeue()
		-- Now should accept
		q:enqueue("starknet_chainId", {}, resolve, reject)
		expect(q:depth()):toBe(2)
	end)

	it("increments totalDropped on rejection", function()
		local q = RequestQueue.new(1)
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_chainId", {}, resolve, reject) -- dropped
		local metrics = q:getMetrics()
		expect(metrics.totalDropped):toBe(1)
	end)

	it("QUEUE_FULL error is an RpcError", function()
		local q = RequestQueue.new(0)
		local _, rejectFn, _, getRejected = makeCallbacks()
		q:enqueue("starknet_chainId", {}, function() end, rejectFn)
		local rejected = getRejected() :: any
		expect(rejected ~= nil):toBe(true)
		expect(rejected._type):toBe("RpcError")
	end)

	it("does not count dropped items in totalRequests", function()
		local q = RequestQueue.new(1)
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject) -- enqueued
		q:enqueue("starknet_chainId", {}, resolve, reject) -- dropped
		local metrics = q:getMetrics()
		expect(metrics.totalRequests):toBe(1)
		expect(metrics.totalDropped):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Metrics
--------------------------------------------------------------------------------

describe("RequestQueue - metrics", function()
	it("initializes all metrics to zero", function()
		local q = RequestQueue.new()
		local m = q:getMetrics()
		expect(m.totalRequests):toBe(0)
		expect(m.totalCompleted):toBe(0)
		expect(m.totalFailed):toBe(0)
		expect(m.totalBatched):toBe(0)
		expect(m.totalDropped):toBe(0)
		expect(m.currentQueueDepth):toBe(0)
		expect(m.batchesSent):toBe(0)
	end)

	it("tracks totalRequests on enqueue", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_blockNumber", {}, resolve, reject)
		expect(q:getMetrics().totalRequests):toBe(2)
	end)

	it("tracks currentQueueDepth", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:enqueue("starknet_blockNumber", {}, resolve, reject)
		expect(q:getMetrics().currentQueueDepth):toBe(2)
		q:dequeue()
		expect(q:getMetrics().currentQueueDepth):toBe(1)
	end)

	it("tracks recordCompleted", function()
		local q = RequestQueue.new()
		q:recordCompleted()
		q:recordCompleted()
		expect(q:getMetrics().totalCompleted):toBe(2)
	end)

	it("tracks recordFailed", function()
		local q = RequestQueue.new()
		q:recordFailed()
		expect(q:getMetrics().totalFailed):toBe(1)
	end)

	it("tracks recordBatched", function()
		local q = RequestQueue.new()
		q:recordBatched(5)
		expect(q:getMetrics().totalBatched):toBe(5)
	end)

	it("tracks recordBatchSent", function()
		local q = RequestQueue.new()
		q:recordBatchSent()
		q:recordBatchSent()
		expect(q:getMetrics().batchesSent):toBe(2)
	end)

	it("returns a snapshot (not a live reference)", function()
		local q = RequestQueue.new()
		local m1 = q:getMetrics()
		q:recordCompleted()
		local m2 = q:getMetrics()
		expect(m1.totalCompleted):toBe(0)
		expect(m2.totalCompleted):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Edge cases
--------------------------------------------------------------------------------

describe("RequestQueue - edge cases", function()
	it("handles interleaved enqueue and dequeue", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", { "a" }, resolve, reject)
		local first = q:dequeue() :: any
		expect(first.params[1]):toBe("a")
		q:enqueue("starknet_blockNumber", { "b" }, resolve, reject)
		local second = q:dequeue() :: any
		expect(second.params[1]):toBe("b")
		expect(q:isEmpty()):toBe(true)
	end)

	it("handles all items at same priority", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		for i = 1, 5 do
			q:enqueue("starknet_chainId", { tostring(i) }, resolve, reject)
		end
		for i = 1, 5 do
			local item = q:dequeue() :: any
			expect(item.params[1]):toBe(tostring(i))
		end
	end)

	it("isEmpty returns false when items exist", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		expect(q:isEmpty()):toBe(false)
	end)

	it("isEmpty returns true after draining all items", function()
		local q = RequestQueue.new()
		local resolve, reject = makeCallbacks()
		q:enqueue("starknet_chainId", {}, resolve, reject)
		q:dequeue()
		expect(q:isEmpty()):toBe(true)
	end)

	it("maxQueueDepth of 0 rejects all items", function()
		local q = RequestQueue.new(0)
		local _, rejectFn, _, getRejected = makeCallbacks()
		q:enqueue("starknet_chainId", {}, function() end, rejectFn)
		expect(getRejected() ~= nil):toBe(true)
	end)
end)
