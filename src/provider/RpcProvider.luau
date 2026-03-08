--!strict
-- RpcProvider: JSON-RPC client for Starknet using Roblox HttpService with Promise-based API
-- Features: rate limiting, retry with exponential backoff, configurable endpoints
-- All public methods return Promises for async operation
-- Delegates core JSON-RPC transport to JsonRpcClient

local RpcTypes = require("./RpcTypes")
local JsonRpcClient = require("./JsonRpcClient")
local RequestQueue = require("./RequestQueue")
local ResponseCache = require("./ResponseCache")
local NonceManager = require("./NonceManager")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

export type RpcProvider = {
	getChainId: (self: RpcProvider) -> RpcTypes.Promise<string>,
	getBlockNumber: (self: RpcProvider) -> RpcTypes.Promise<number>,
	getSpecVersion: (self: RpcProvider) -> RpcTypes.Promise<string>,
	getNonce: (self: RpcProvider, contractAddress: string, blockId: string?) -> RpcTypes.Promise<string>,
	call: (self: RpcProvider, request: RpcTypes.CallRequest, blockId: string?) -> RpcTypes.Promise<{ string }>,
	estimateFee: (
		self: RpcProvider,
		transactions: { RpcTypes.InvokeTransactionV3 },
		simulationFlags: { string }?
	) -> RpcTypes.Promise<{ RpcTypes.FeeEstimate }>,
	addInvokeTransaction: (
		self: RpcProvider,
		invokeTx: RpcTypes.InvokeTransactionV3
	) -> RpcTypes.Promise<RpcTypes.InvokeResult>,
	addDeployAccountTransaction: (
		self: RpcProvider,
		deployTx: RpcTypes.DeployAccountTransactionV3
	) -> RpcTypes.Promise<RpcTypes.DeployAccountResult>,
	getTransactionReceipt: (self: RpcProvider, txHash: string) -> RpcTypes.Promise<RpcTypes.TransactionReceipt>,
	getTransactionStatus: (self: RpcProvider, txHash: string) -> RpcTypes.Promise<RpcTypes.TransactionStatus>,
	getBlockWithTxHashes: (self: RpcProvider, blockId: string?) -> RpcTypes.Promise<RpcTypes.Block>,
	getBlockWithTxs: (self: RpcProvider, blockId: string?) -> RpcTypes.Promise<RpcTypes.BlockWithTxs>,
	getBlockWithReceipts: (self: RpcProvider, blockId: string?) -> RpcTypes.Promise<RpcTypes.BlockWithReceipts>,
	getTransactionByHash: (self: RpcProvider, txHash: string) -> RpcTypes.Promise<RpcTypes.Transaction>,
	getClassHashAt: (self: RpcProvider, contractAddress: string, blockId: string?) -> RpcTypes.Promise<string>,
	getStorageAt: (
		self: RpcProvider,
		contractAddress: string,
		key: string,
		blockId: string?
	) -> RpcTypes.Promise<string>,
	getClass: (
		self: RpcProvider,
		classHash: string,
		blockId: string?
	) -> RpcTypes.Promise<RpcTypes.ContractClass>,
	getClassAt: (
		self: RpcProvider,
		contractAddress: string,
		blockId: string?
	) -> RpcTypes.Promise<RpcTypes.ContractClass>,
	estimateMessageFee: (
		self: RpcProvider,
		message: RpcTypes.MessageFromL1,
		blockId: string?
	) -> RpcTypes.Promise<RpcTypes.FeeEstimate>,
	getSyncingStats: (self: RpcProvider) -> RpcTypes.Promise<any>,
	getEvents: (self: RpcProvider, filter: RpcTypes.EventFilter) -> RpcTypes.Promise<RpcTypes.EventsChunk>,
	getAllEvents: (self: RpcProvider, filter: RpcTypes.EventFilter) -> RpcTypes.Promise<{ RpcTypes.EmittedEvent }>,
	waitForTransaction: (
		self: RpcProvider,
		txHash: string,
		options: RpcTypes.WaitOptions?
	) -> RpcTypes.Promise<RpcTypes.TransactionReceipt>,
	fetch: (self: RpcProvider, method: string, params: any, options: RpcTypes.FetchOptions?) -> RpcTypes.Promise<any>,
	getNodeUrl: (self: RpcProvider) -> string,
	getMetrics: (self: RpcProvider) -> RpcTypes.ProviderMetrics,
	flushCache: (self: RpcProvider) -> (),
	getNonceManager: (self: RpcProvider) -> any,
	getPromise: (self: RpcProvider) -> any,
	fetchSync: (self: RpcProvider, method: string, params: any) -> any,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Format a block ID parameter for RPC calls.
--- Accepts a convenience string shorthand: "latest", "pending", "0x<hash>", or a decimal
--- block number string. This differs from the RpcTypes.BlockId structured type which uses
--- explicit fields (block_hash, block_number, block_tag). The string shorthand is used in
--- all public RpcProvider methods for ergonomics; formatBlockId converts it to the structured
--- format expected by the JSON-RPC wire protocol.
local function formatBlockId(blockId: string?): any
	if blockId == nil or blockId == "latest" then
		return "latest"
	elseif blockId == "pending" then
		return "pending"
	elseif string.sub(blockId, 1, 2) == "0x" then
		return { block_hash = blockId }
	else
		local num = tonumber(blockId)
		if num then
			return { block_number = num }
		end
		return blockId
	end
end

--------------------------------------------------------------------------------
-- RpcProvider class
--------------------------------------------------------------------------------

local RpcProviderClass = {}
RpcProviderClass.__index = RpcProviderClass

--- Create a new RpcProvider.
--- @param config -- RpcProviderConfig with nodeUrl and optional settings
function RpcProviderClass.new(config: RpcTypes.RpcProviderConfig): RpcProvider
	if not config.nodeUrl or config.nodeUrl == "" then
		error(StarknetError.validation("RpcProvider: nodeUrl is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local queueConfig = config.queueConfig or {}

	-- Create the shared JSON-RPC transport client
	local client = JsonRpcClient.new({
		nodeUrl = config.nodeUrl,
		headers = config.headers,
		maxRequestsPerMinute = config.maxRequestsPerMinute or 450,
		rateLimitTimeout = config.rateLimitTimeout,
		retryAttempts = config.retryAttempts,
		retryDelay = config.retryDelay,
		clientName = "RpcProvider",
		_httpRequest = config._httpRequest,
		_sleep = config._sleep,
		_clock = config._clock,
	})

	local self = setmetatable({
		_client = client,
		-- Expose fields needed by external consumers (EventPoller, NonceManager, tests)
		_nodeUrl = config.nodeUrl,
		_PromiseModule = client._PromiseModule,
		_sleep = client._sleep,
		_clock = client._clock,
		_queue = nil :: any,
		_cache = nil :: any,
		_nonceManager = nil :: any,
		_lastKnownBlockNumber = 0,
		_drainScheduled = false,
		_defer = config._defer or function(fn: () -> ())
			task.defer(fn)
		end,
		_maxBatchSize = queueConfig.maxBatchSize or 20,
		_enableBatching = if queueConfig.enableBatching ~= nil then queueConfig.enableBatching else true,
	}, RpcProviderClass)

	if config.enableQueue then
		self._queue = RequestQueue.new(queueConfig.maxQueueDepth)
	end

	if config.enableCache then
		local clockFn = config._clock or os.clock
		self._cache = ResponseCache.new(config.cacheConfig or {}, clockFn)
	end

	if config.enableNonceManager then
		self._nonceManager = NonceManager.new(self, config.nonceManagerConfig or {})
	end

	return self :: any
end

--- Get the configured node URL
function RpcProviderClass:getNodeUrl(): string
	return self._client:getNodeUrl()
end

--------------------------------------------------------------------------------
-- Delegate to JsonRpcClient for infrastructure
-- These methods forward to the internal client, preserving the interface
-- that EventPoller and other consumers depend on.
--------------------------------------------------------------------------------

--- Get the Promise constructor.
--- Syncs externally-injected _PromiseModule (test pattern) to the internal client.
function RpcProviderClass:getPromise(): any
	if self._PromiseModule and self._PromiseModule ~= self._client._PromiseModule then
		self._client._PromiseModule = self._PromiseModule
	end
	return self._client:getPromise()
end

--- Internal: JSON encode (used by _dispatchBatch)
function RpcProviderClass:_jsonEncode(value: any): string
	return self._client:_jsonEncode(value)
end

--- Internal: Build a cache key for RPC params.
--- Fast path for simple params (arrays of strings/numbers/booleans) avoids full JSON serialization.
--- Falls back to _jsonEncode for nested tables.
--- Always preserves "method:" prefix so invalidateByPrefix() continues to work.
function RpcProviderClass:_buildCacheKey(method: string, params: any): string
	if type(params) ~= "table" then
		return method .. ":" .. tostring(params)
	end
	-- Fast path: check if all elements are simple scalars
	local parts: { string } = {}
	for _, v in params :: { any } do
		local t = type(v)
		if t == "string" then
			table.insert(parts, v)
		elseif t == "number" or t == "boolean" then
			table.insert(parts, tostring(v))
		else
			-- Nested table: fall back to full JSON encode
			return method .. ":" .. self:_jsonEncode(params)
		end
	end
	return method .. ":" .. table.concat(parts, "\0")
end

--- Internal: JSON decode (used by _dispatchBatch)
function RpcProviderClass:_jsonDecode(json: string): any
	return self._client:_jsonDecode(json)
end

--- Internal: Perform an HTTP request (used by _dispatchBatch)
function RpcProviderClass:_doHttpRequest(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
	return self._client:_doHttpRequest(request)
end

--- Internal: Perform a single JSON-RPC request with retry (delegates to client)
function RpcProviderClass:_requestWithRetry(method: string, params: any): any
	return self._client:_requestWithRetry(method, params)
end

--- Synchronous RPC call with retry. Returns the raw result (not a Promise).
--- Suitable for use inside Promise executors where blocking is acceptable
--- (e.g., EventPoller polling loops, waitForTransaction, getAllEvents).
function RpcProviderClass:fetchSync(method: string, params: any): any
	return self._client:_requestWithRetry(method, params)
end

--- Raw RPC call for custom/unsupported methods.
--- Returns a Promise that resolves to the raw JSON-RPC result.
--- When cache is enabled, checks cache first and stores successful results.
--- When queue is enabled, requests are enqueued and drained on the next defer cycle.
function RpcProviderClass:fetch(method: string, params: any, options: RpcTypes.FetchOptions?): any
	local Promise = self:getPromise()
	local cache = self._cache
	local bypassCache = options and options.bypassCache

	-- Cache check: return cached result immediately on hit
	if cache and not bypassCache then
		local ttl = cache:getTTLForMethod(method)
		if ttl ~= nil then
			local cacheKey = self:_buildCacheKey(method, params)
			local cached = cache:get(cacheKey)
			if cached ~= nil then
				return Promise.resolve(cached)
			end

			-- Cache miss: proceed to network, store result on success
			local networkPromise = self:_fetchNetwork(method, params)
			return networkPromise:andThen(function(result: any)
				cache:set(cacheKey, result, ttl)
				return result
			end)
		end
	end

	-- Uncacheable or cache disabled: go straight to network
	return self:_fetchNetwork(method, params)
end

--- Internal: perform the actual network fetch (queue or direct path).
function RpcProviderClass:_fetchNetwork(method: string, params: any): any
	local Promise = self:getPromise()

	-- Queue path: enqueue + schedule drain
	if self._queue then
		return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
			self._queue:enqueue(method, params, resolve, reject)
			self:_scheduleDrain()
		end)
	end

	-- Direct path (no queue): delegate to client's fetch
	return self._client:fetch(method, params)
end

--------------------------------------------------------------------------------
-- Queue drain and batch dispatch
--------------------------------------------------------------------------------

--- Schedule a drain on the next defer cycle (idempotent).
function RpcProviderClass:_scheduleDrain()
	if self._drainScheduled then
		return
	end
	self._drainScheduled = true
	self._defer(function()
		self._drainScheduled = false
		self:_drainQueue()
	end)
end

--- Drain the queue: HIGH items dispatched individually, batchable NORMAL/LOW grouped.
function RpcProviderClass:_drainQueue()
	local queue = self._queue
	if not queue then
		return
	end

	while not queue:isEmpty() do
		local priority = queue:peekPriority()

		-- HIGH priority: always dispatch individually
		if priority == "high" then
			local item = queue:dequeue()
			if item then
				self:_dispatchSingle(item)
			end
			continue
		end

		-- NORMAL/LOW: collect batchable items
		if self._enableBatching then
			local batchItems: { any } = {}
			local nonBatchItems: { any } = {}

			-- Collect items at the current priority level (and below)
			while not queue:isEmpty() and #batchItems < self._maxBatchSize do
				local nextPriority = queue:peekPriority()
				-- Stop if we see a high-priority item (it should go first)
				if nextPriority == "high" then
					break
				end
				local item = queue:dequeue()
				if item then
					if RequestQueue.isBatchable(item.method) then
						table.insert(batchItems, item)
					else
						table.insert(nonBatchItems, item)
					end
				end
			end

			-- Dispatch batch
			if #batchItems > 1 then
				self:_dispatchBatch(batchItems)
			elseif #batchItems == 1 then
				-- Single item: dispatch individually (no batching overhead)
				self:_dispatchSingle(batchItems[1])
			end

			-- Dispatch non-batchable items individually
			for _, item in nonBatchItems do
				self:_dispatchSingle(item)
			end
		else
			-- Batching disabled: dispatch everything individually
			local item = queue:dequeue()
			if item then
				self:_dispatchSingle(item)
			end
		end
	end
end

--- Dispatch a single queue item through the retry pipeline.
function RpcProviderClass:_dispatchSingle(item: any)
	local queue = self._queue
	local ok, result = pcall(function()
		return self:fetchSync(item.method, item.params)
	end)
	if ok then
		if queue then
			queue:recordCompleted()
		end
		item.resolve(result)
	else
		if queue then
			queue:recordFailed()
		end
		item.reject(result)
	end
end

--- Dispatch a batch of items as a single JSON-RPC batch request.
function RpcProviderClass:_dispatchBatch(items: { any })
	local queue = self._queue
	local client = self._client

	-- Acquire a single rate limit token for the batch
	local okAcquire, acquireErr = pcall(function()
		client:_acquireRateLimitToken()
	end)
	if not okAcquire then
		for _, item in items do
			if queue then
				queue:recordFailed()
			end
			item.reject(acquireErr)
		end
		return
	end

	-- Build JSON-RPC batch array
	local batchRequest: { any } = {}
	local idToItem: { [number]: any } = {}
	for _, item in items do
		client._requestId += 1
		local rpcReq = {
			jsonrpc = "2.0",
			method = item.method,
			params = item.params,
			id = client._requestId,
		}
		table.insert(batchRequest, rpcReq)
		idToItem[client._requestId] = item
	end

	local body = client:_jsonEncode(batchRequest)
	local headers = client:_buildHeaders()

	local httpRequest: RpcTypes.HttpRequest = {
		Url = client._nodeUrl,
		Method = "POST",
		Headers = headers,
		Body = body,
	}

	local ok, response = pcall(function()
		return client:_doHttpRequest(httpRequest)
	end)

	if not ok then
		local err = StarknetError.rpc(`Batch HTTP request failed: {tostring(response)}`, ErrorCodes.BATCH_ERROR.code)
		for _, item in items do
			if queue then
				queue:recordFailed()
			end
			item.reject(err)
		end
		return
	end

	if not response.Success and response.StatusCode ~= 200 then
		local err = StarknetError.rpc(
			`Batch HTTP {response.StatusCode}: {response.Body}`,
			ErrorCodes.BATCH_ERROR.code,
			response.StatusCode
		)
		for _, item in items do
			if queue then
				queue:recordFailed()
			end
			item.reject(err)
		end
		return
	end

	local decodeOk, decoded = pcall(function()
		return client:_jsonDecode(response.Body)
	end)

	if not decodeOk then
		local err = StarknetError.rpc(`Batch response decode failed: {tostring(decoded)}`, ErrorCodes.BATCH_ERROR.code)
		for _, item in items do
			if queue then
				queue:recordFailed()
			end
			item.reject(err)
		end
		return
	end

	-- Distribute responses by id
	if queue then
		queue:recordBatchSent()
		queue:recordBatched(#items)
	end

	local responseMap: { [number]: any } = {}
	if type(decoded) == "table" then
		for _, resp in decoded do
			if type(resp) == "table" and resp.id then
				responseMap[resp.id] = resp
			end
		end
	end

	for id, item in idToItem do
		local resp = responseMap[id]
		if not resp then
			if queue then
				queue:recordFailed()
			end
			item.reject(
				StarknetError.rpc("No response for batch request id " .. tostring(id), ErrorCodes.BATCH_ERROR.code)
			)
		elseif resp.error then
			if queue then
				queue:recordFailed()
			end
			item.reject(
				StarknetError.rpc(
					resp.error.message or "Unknown RPC error",
					ErrorCodes.RPC_ERROR.code,
					resp.error.code,
					resp.error.data
				)
			)
		else
			if queue then
				queue:recordCompleted()
			end
			item.resolve(resp.result)
		end
	end
end

--- Get the nonce manager instance (nil if not enabled).
function RpcProviderClass:getNonceManager(): any
	return self._nonceManager
end

--- Flush all cached responses.
function RpcProviderClass:flushCache()
	if self._cache then
		self._cache:flush()
	end
end

--- Get a snapshot of provider metrics (queue + rate limiter + cache + nonce).
function RpcProviderClass:getMetrics(): RpcTypes.ProviderMetrics
	local rateLimiter = self._client:getRateLimiter()

	local cacheHits = 0
	local cacheMisses = 0
	local cacheEvictions = 0
	local cacheSize = 0
	if self._cache then
		local cm = self._cache:getMetrics()
		cacheHits = cm.cacheHits
		cacheMisses = cm.cacheMisses
		cacheEvictions = cm.cacheEvictions
		cacheSize = cm.cacheSize
	end

	local nonceReserved = 0
	local nonceConfirmed = 0
	local nonceRejected = 0
	local nonceResyncs = 0
	if self._nonceManager then
		local nm = self._nonceManager:getMetrics()
		nonceReserved = nm.totalReserved
		nonceConfirmed = nm.totalConfirmed
		nonceRejected = nm.totalRejected
		nonceResyncs = nm.totalResyncs
	end

	local qm = if self._queue then self._queue:getMetrics() else nil

	return {
		totalRequests = if qm then qm.totalRequests else 0,
		totalCompleted = if qm then qm.totalCompleted else 0,
		totalFailed = if qm then qm.totalFailed else 0,
		totalBatched = if qm then qm.totalBatched else 0,
		totalDropped = if qm then qm.totalDropped else 0,
		currentQueueDepth = if qm then qm.currentQueueDepth else 0,
		rateLimitTokens = math.floor(rateLimiter.tokens),
		rateLimitMax = rateLimiter.maxTokens,
		batchesSent = if qm then qm.batchesSent else 0,
		cacheHits = cacheHits,
		cacheMisses = cacheMisses,
		cacheEvictions = cacheEvictions,
		cacheSize = cacheSize,
		nonceReserved = nonceReserved,
		nonceConfirmed = nonceConfirmed,
		nonceRejected = nonceRejected,
		nonceResyncs = nonceResyncs,
	}
end

--------------------------------------------------------------------------------
-- Public RPC methods
--------------------------------------------------------------------------------

--- Get the chain ID of the connected network.
--- Returns hex-encoded chain ID (e.g. "0x534e5f5345504f4c4941" for Sepolia).
function RpcProviderClass:getChainId(): any
	return self:fetch("starknet_chainId", {})
end

--- Get the latest block number.
--- When caching is enabled, detects new blocks and invalidates storage/call/block caches.
function RpcProviderClass:getBlockNumber(): any
	return self:fetch("starknet_blockNumber", {}):andThen(function(result: any)
		local blockNum: number
		if type(result) == "number" then
			blockNum = result
		else
			blockNum = tonumber(result) or 0
		end

		-- Block-based cache invalidation: only on block transitions (not first discovery)
		if self._cache and blockNum > self._lastKnownBlockNumber then
			local isFirstDiscovery = self._lastKnownBlockNumber == 0
			self._lastKnownBlockNumber = blockNum
			if not isFirstDiscovery then
				-- Invalidate block-sensitive caches (NOT chainId/classHash/specVersion/blockNumber)
				self._cache:invalidateByPrefix("starknet_getStorageAt:")
				self._cache:invalidateByPrefix("starknet_call:")
				self._cache:invalidateByPrefix("starknet_getBlockWithTxHashes:")
				self._cache:invalidateByPrefix("starknet_getBlockWithTxs:")
				self._cache:invalidateByPrefix("starknet_getBlockWithReceipts:")
			end
		end

		return blockNum
	end)
end

--- Get the Starknet JSON-RPC spec version.
function RpcProviderClass:getSpecVersion(): any
	return self:fetch("starknet_specVersion", {})
end

--- Get the nonce for a contract address.
--- @param contractAddress -- hex address
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getNonce(contractAddress: string, blockId: string?): any
	return self:fetch("starknet_getNonce", {
		formatBlockId(blockId),
		contractAddress,
	})
end

--- Call a contract function (read-only, no state change).
--- @param request -- CallRequest with contract_address, entry_point_selector, calldata
--- @param blockId -- optional block identifier
function RpcProviderClass:call(request: RpcTypes.CallRequest, blockId: string?): any
	return self:fetch("starknet_call", {
		{
			contract_address = request.contract_address,
			entry_point_selector = request.entry_point_selector,
			calldata = request.calldata,
		},
		formatBlockId(blockId),
	})
end

--- Estimate the fee for a set of transactions.
--- @param transactions -- array of invoke transactions
--- @param simulationFlags -- optional simulation flags (e.g. {"SKIP_VALIDATE"})
function RpcProviderClass:estimateFee(transactions: { RpcTypes.InvokeTransactionV3 }, simulationFlags: { string }?): any
	local params: { any } = {
		transactions,
		simulationFlags or {},
		"latest",
	}
	return self:fetch("starknet_estimateFee", params)
end

--- Submit a signed invoke transaction.
--- Returns a Promise resolving to { transaction_hash: string }.
function RpcProviderClass:addInvokeTransaction(invokeTx: RpcTypes.InvokeTransactionV3): any
	return self:fetch("starknet_addInvokeTransaction", { invokeTx }):andThen(function(result: any)
		if type(result) == "table" and result.transaction_hash then
			return { transaction_hash = result.transaction_hash }
		end
		return { transaction_hash = result }
	end)
end

--- Submit a signed deploy account transaction.
--- Returns a Promise resolving to { transaction_hash, contract_address }.
function RpcProviderClass:addDeployAccountTransaction(deployTx: RpcTypes.DeployAccountTransactionV3): any
	return self:fetch("starknet_addDeployAccountTransaction", { deployTx }):andThen(function(result: any)
		if type(result) == "table" and result.transaction_hash then
			return {
				transaction_hash = result.transaction_hash,
				contract_address = result.contract_address or "",
			}
		end
		return result
	end)
end

--- Get the receipt for a transaction.
function RpcProviderClass:getTransactionReceipt(txHash: string): any
	return self:fetch("starknet_getTransactionReceipt", {
		txHash,
	})
end

--- Get the status of a transaction.
function RpcProviderClass:getTransactionStatus(txHash: string): any
	return self:fetch("starknet_getTransactionStatus", {
		txHash,
	})
end

--- Get a block with transaction hashes.
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getBlockWithTxHashes(blockId: string?): any
	return self:fetch("starknet_getBlockWithTxHashes", {
		formatBlockId(blockId),
	})
end

--- Get the class hash deployed at a contract address.
function RpcProviderClass:getClassHashAt(contractAddress: string, blockId: string?): any
	return self:fetch("starknet_getClassHashAt", {
		formatBlockId(blockId),
		contractAddress,
	})
end

--- Get the storage value at a given key for a contract.
function RpcProviderClass:getStorageAt(contractAddress: string, key: string, blockId: string?): any
	return self:fetch("starknet_getStorageAt", {
		contractAddress,
		key,
		formatBlockId(blockId),
	})
end

--- Get a block with full transaction objects.
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getBlockWithTxs(blockId: string?): any
	return self:fetch("starknet_getBlockWithTxs", {
		formatBlockId(blockId),
	})
end

--- Get a block with transaction receipts.
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getBlockWithReceipts(blockId: string?): any
	return self:fetch("starknet_getBlockWithReceipts", {
		formatBlockId(blockId),
	})
end

--- Get full transaction details by hash.
--- @param txHash -- the transaction hash
function RpcProviderClass:getTransactionByHash(txHash: string): any
	return self:fetch("starknet_getTransactionByHash", {
		txHash,
	})
end

--- Get the contract class definition for a given class hash.
--- @param classHash -- the class hash
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getClass(classHash: string, blockId: string?): any
	return self:fetch("starknet_getClass", {
		formatBlockId(blockId),
		classHash,
	})
end

--- Get the contract class at a given address.
--- @param contractAddress -- hex address
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:getClassAt(contractAddress: string, blockId: string?): any
	return self:fetch("starknet_getClassAt", {
		formatBlockId(blockId),
		contractAddress,
	})
end

--- Estimate the fee for an L1→L2 message.
--- @param message -- MessageFromL1 with from_address, to_address, entry_point_selector, payload
--- @param blockId -- optional block identifier (default: "latest")
function RpcProviderClass:estimateMessageFee(message: RpcTypes.MessageFromL1, blockId: string?): any
	return self:fetch("starknet_estimateMessageFee", {
		{
			from_address = message.from_address,
			to_address = message.to_address,
			entry_point_selector = message.entry_point_selector,
			payload = message.payload,
		},
		formatBlockId(blockId),
	})
end

--- Get the syncing status of the node.
--- Returns false if not syncing, or a SyncingStatus object with block progress.
function RpcProviderClass:getSyncingStats(): any
	return self:fetch("starknet_syncing", {})
end

--- Get events matching a filter.
function RpcProviderClass:getEvents(filter: RpcTypes.EventFilter): any
	local filterParam: { [string]: any } = {}
	if filter.from_block then
		filterParam.from_block = filter.from_block
	end
	if filter.to_block then
		filterParam.to_block = filter.to_block
	end
	if filter.address then
		filterParam.address = filter.address
	end
	if filter.keys then
		filterParam.keys = filter.keys
	end
	filterParam.chunk_size = filter.chunk_size or 100
	if filter.continuation_token then
		filterParam.continuation_token = filter.continuation_token
	end
	return self:fetch("starknet_getEvents", {
		{ filter = filterParam },
	})
end

--- Get all events matching a filter, automatically paginating through continuation tokens.
--- Returns a Promise resolving to a flat array of all matching EmittedEvents.
function RpcProviderClass:getAllEvents(filter: RpcTypes.EventFilter): any
	local Promise = self:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local allEvents: { RpcTypes.EmittedEvent } = {}
		local continuationToken: string? = filter.continuation_token

		local maxPages = 1000 -- safety limit to avoid infinite loops
		for _ = 1, maxPages do
			local pageFilter: RpcTypes.EventFilter = {
				from_block = filter.from_block,
				to_block = filter.to_block,
				address = filter.address,
				keys = filter.keys,
				chunk_size = filter.chunk_size,
				continuation_token = continuationToken,
			}

			local ok, chunk = pcall(function()
				return self:fetchSync("starknet_getEvents", {
					{
						filter = {
							from_block = pageFilter.from_block,
							to_block = pageFilter.to_block,
							address = pageFilter.address,
							keys = pageFilter.keys,
							chunk_size = pageFilter.chunk_size or 100,
							continuation_token = pageFilter.continuation_token,
						},
					},
				})
			end)

			if not ok then
				reject(chunk)
				return
			end

			local events = chunk.events or {}
			for _, event in events do
				table.insert(allEvents, event)
			end

			continuationToken = chunk.continuation_token
			if not continuationToken or continuationToken == "" then
				break
			end
		end

		resolve(allEvents)
	end)
end

--- Poll until a transaction is confirmed (ACCEPTED_ON_L2 or ACCEPTED_ON_L1).
--- Rejects if the transaction is REJECTED or max attempts exceeded.
function RpcProviderClass:waitForTransaction(txHash: string, options: RpcTypes.WaitOptions?): any
	local Promise = self:getPromise()
	local retryInterval = if options and options.retryInterval then options.retryInterval else 5
	local maxAttempts = if options and options.maxAttempts then options.maxAttempts else 30

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		for attempt = 1, maxAttempts do
			local statusOk, statusResult = pcall(function()
				-- Use _requestWithRetry directly to get synchronous result within this Promise executor
				return self:fetchSync("starknet_getTransactionStatus", { txHash })
			end)

			if statusOk and statusResult then
				local finality = statusResult.finality_status
				local execution = statusResult.execution_status

				if finality == "ACCEPTED_ON_L2" or finality == "ACCEPTED_ON_L1" then
					-- Transaction is confirmed, fetch the full receipt
					local receiptOk, receipt = pcall(function()
						return self:fetchSync("starknet_getTransactionReceipt", { txHash })
					end)
					if receiptOk then
						if execution == "REVERTED" then
							reject(
								StarknetError.transaction(
									`Transaction {txHash} reverted: {receipt.revert_reason or "unknown reason"}`,
									ErrorCodes.TRANSACTION_REVERTED.code,
									receipt.revert_reason,
									nil,
									receipt
								)
							)
						else
							resolve(receipt)
						end
					else
						reject(receipt)
					end
					return
				elseif finality == "REJECTED" then
					reject(
						StarknetError.transaction(
							`Transaction {txHash} was rejected`,
							ErrorCodes.TRANSACTION_REJECTED.code,
							nil,
							nil,
							statusResult
						)
					)
					return
				end
				-- Still pending, continue polling
			end

			if attempt < maxAttempts then
				self._sleep(retryInterval)
			end
		end

		reject(
			StarknetError.rpc(
				`Transaction {txHash} not confirmed after {maxAttempts} attempts`,
				ErrorCodes.TIMEOUT.code
			)
		)
	end)
end

return RpcProviderClass
