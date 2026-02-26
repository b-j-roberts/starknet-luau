--!strict
-- RequestQueue: Priority queue for JSON-RPC requests with backpressure and metrics
-- 3-bucket design (high/normal/low) with FIFO within each priority level.
-- Auto-classifies methods by priority and batchability.

local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type QueueItem = {
	method: string,
	params: any,
	priority: string, -- "high" | "normal" | "low"
	resolve: (any) -> (),
	reject: (any) -> (),
	id: number,
}

export type QueueMetrics = {
	totalRequests: number,
	totalCompleted: number,
	totalFailed: number,
	totalBatched: number,
	totalDropped: number,
	currentQueueDepth: number,
	batchesSent: number,
}

export type RequestQueue = {
	enqueue: (self: RequestQueue, method: string, params: any, resolve: (any) -> (), reject: (any) -> ()) -> (),
	dequeue: (self: RequestQueue) -> QueueItem?,
	depth: (self: RequestQueue) -> number,
	isEmpty: (self: RequestQueue) -> boolean,
	peekPriority: (self: RequestQueue) -> string?,
	getMetrics: (self: RequestQueue) -> QueueMetrics,
	recordCompleted: (self: RequestQueue) -> (),
	recordFailed: (self: RequestQueue) -> (),
	recordBatched: (self: RequestQueue, count: number) -> (),
	recordBatchSent: (self: RequestQueue) -> (),
}

--------------------------------------------------------------------------------
-- Priority and batch classification
--------------------------------------------------------------------------------

local METHOD_PRIORITY: { [string]: string } = {
	["starknet_addInvokeTransaction"] = "high",
	["starknet_estimateFee"] = "high",
	["starknet_getEvents"] = "low",
}

local BATCHABLE_METHODS: { [string]: boolean } = {
	["starknet_chainId"] = true,
	["starknet_blockNumber"] = true,
	["starknet_specVersion"] = true,
	["starknet_getNonce"] = true,
	["starknet_call"] = true,
	["starknet_getBlockWithTxHashes"] = true,
	["starknet_getClassHashAt"] = true,
	["starknet_getStorageAt"] = true,
	["starknet_getTransactionReceipt"] = true,
	["starknet_getTransactionStatus"] = true,
	["starknet_getEvents"] = true,
}

--------------------------------------------------------------------------------
-- RequestQueue class
--------------------------------------------------------------------------------

local RequestQueueClass = {}
RequestQueueClass.__index = RequestQueueClass

function RequestQueueClass.new(maxQueueDepth: number?): RequestQueue
	local self = setmetatable({
		_high = {} :: { QueueItem },
		_normal = {} :: { QueueItem },
		_low = {} :: { QueueItem },
		_maxQueueDepth = maxQueueDepth or 100,
		_nextId = 0,
		_metrics = {
			totalRequests = 0,
			totalCompleted = 0,
			totalFailed = 0,
			totalBatched = 0,
			totalDropped = 0,
			batchesSent = 0,
		},
	}, RequestQueueClass)
	return self :: any
end

--- Classify a method name to its priority level
function RequestQueueClass.getPriority(method: string): string
	return METHOD_PRIORITY[method] or "normal"
end

--- Check if a method is safe to batch
function RequestQueueClass.isBatchable(method: string): boolean
	return BATCHABLE_METHODS[method] == true
end

--- Enqueue a request. Rejects with QUEUE_FULL if at capacity.
function RequestQueueClass:enqueue(method: string, params: any, resolve: (any) -> (), reject: (any) -> ())
	local currentDepth = self:depth()
	if currentDepth >= self._maxQueueDepth then
		self._metrics.totalDropped += 1
		reject(
			StarknetError.rpc(
				`Request queue full ({self._maxQueueDepth} items). Try again later.`,
				ErrorCodes.QUEUE_FULL.code
			)
		)
		return
	end

	self._nextId += 1
	local priority = RequestQueueClass.getPriority(method)
	local item: QueueItem = {
		method = method,
		params = params,
		priority = priority,
		resolve = resolve,
		reject = reject,
		id = self._nextId,
	}

	self._metrics.totalRequests += 1

	if priority == "high" then
		table.insert(self._high, item)
	elseif priority == "low" then
		table.insert(self._low, item)
	else
		table.insert(self._normal, item)
	end
end

--- Dequeue the highest-priority item (FIFO within each level).
function RequestQueueClass:dequeue(): QueueItem?
	if #self._high > 0 then
		return table.remove(self._high, 1)
	elseif #self._normal > 0 then
		return table.remove(self._normal, 1)
	elseif #self._low > 0 then
		return table.remove(self._low, 1)
	end
	return nil
end

--- Get current queue depth across all buckets.
function RequestQueueClass:depth(): number
	return #self._high + #self._normal + #self._low
end

--- Check if the queue is empty.
function RequestQueueClass:isEmpty(): boolean
	return self:depth() == 0
end

--- Peek at the priority of the next item without removing it.
function RequestQueueClass:peekPriority(): string?
	if #self._high > 0 then
		return "high"
	elseif #self._normal > 0 then
		return "normal"
	elseif #self._low > 0 then
		return "low"
	end
	return nil
end

--- Record a successful completion.
function RequestQueueClass:recordCompleted()
	self._metrics.totalCompleted += 1
end

--- Record a failure.
function RequestQueueClass:recordFailed()
	self._metrics.totalFailed += 1
end

--- Record items that were batched.
function RequestQueueClass:recordBatched(count: number)
	self._metrics.totalBatched += count
end

--- Record a batch sent.
function RequestQueueClass:recordBatchSent()
	self._metrics.batchesSent += 1
end

--- Get a snapshot of queue metrics.
function RequestQueueClass:getMetrics(): QueueMetrics
	return {
		totalRequests = self._metrics.totalRequests,
		totalCompleted = self._metrics.totalCompleted,
		totalFailed = self._metrics.totalFailed,
		totalBatched = self._metrics.totalBatched,
		totalDropped = self._metrics.totalDropped,
		currentQueueDepth = self:depth(),
		batchesSent = self._metrics.batchesSent,
	}
end

return RequestQueueClass
