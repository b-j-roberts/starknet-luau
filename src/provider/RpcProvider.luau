--!strict
-- RpcProvider: JSON-RPC client for Starknet using Roblox HttpService with Promise-based API
-- Features: rate limiting, retry with exponential backoff, configurable endpoints
-- All public methods return Promises for async operation

local RpcTypes = require("./RpcTypes")
local RequestQueue = require("./RequestQueue")
local ResponseCache = require("./ResponseCache")
local NonceManager = require("./NonceManager")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--- Promise-like type for return annotations
--- In Roblox runtime, this is evaera/promise; in tests, a compatible mock is injected
export type Promise<T> = {
	andThen: (self: Promise<T>, onResolve: (value: T) -> any) -> Promise<any>,
	catch: (self: Promise<T>, onReject: (err: any) -> any) -> Promise<any>,
	expect: (self: Promise<T>) -> T,
}

export type RpcProvider = {
	getChainId: (self: RpcProvider) -> Promise<string>,
	getBlockNumber: (self: RpcProvider) -> Promise<number>,
	getSpecVersion: (self: RpcProvider) -> Promise<string>,
	getNonce: (self: RpcProvider, contractAddress: string, blockId: string?) -> Promise<string>,
	call: (self: RpcProvider, request: RpcTypes.CallRequest, blockId: string?) -> Promise<{ string }>,
	estimateFee: (
		self: RpcProvider,
		transactions: { RpcTypes.InvokeTransactionV3 },
		simulationFlags: { string }?
	) -> Promise<{ RpcTypes.FeeEstimate }>,
	addInvokeTransaction: (self: RpcProvider, invokeTx: RpcTypes.InvokeTransactionV3) -> Promise<string>,
	getTransactionReceipt: (self: RpcProvider, txHash: string) -> Promise<RpcTypes.TransactionReceipt>,
	getTransactionStatus: (self: RpcProvider, txHash: string) -> Promise<RpcTypes.TransactionStatus>,
	getBlockWithTxHashes: (self: RpcProvider, blockId: string?) -> Promise<RpcTypes.Block>,
	getClassHashAt: (self: RpcProvider, contractAddress: string, blockId: string?) -> Promise<string>,
	getStorageAt: (self: RpcProvider, contractAddress: string, key: string, blockId: string?) -> Promise<string>,
	getEvents: (self: RpcProvider, filter: RpcTypes.EventFilter) -> Promise<RpcTypes.EventsChunk>,
	getAllEvents: (self: RpcProvider, filter: RpcTypes.EventFilter) -> Promise<{ RpcTypes.EmittedEvent }>,
	waitForTransaction: (
		self: RpcProvider,
		txHash: string,
		options: RpcTypes.WaitOptions?
	) -> Promise<RpcTypes.TransactionReceipt>,
	fetch: (self: RpcProvider, method: string, params: any, options: RpcTypes.FetchOptions?) -> Promise<any>,
	getNodeUrl: (self: RpcProvider) -> string,
	getMetrics: (self: RpcProvider) -> RpcTypes.ProviderMetrics,
	flushCache: (self: RpcProvider) -> (),
}

--------------------------------------------------------------------------------
-- Rate limiter: token bucket algorithm
--------------------------------------------------------------------------------

type RateLimiter = {
	tokens: number,
	maxTokens: number,
	refillRate: number, -- tokens per second
	lastRefill: number, -- os.clock() timestamp
}

local function createRateLimiter(maxPerMinute: number, clockFn: () -> number): RateLimiter
	return {
		tokens = maxPerMinute,
		maxTokens = maxPerMinute,
		refillRate = maxPerMinute / 60,
		lastRefill = clockFn(),
	}
end

local function tryAcquire(limiter: RateLimiter, clockFn: () -> number): boolean
	local now = clockFn()
	local elapsed = now - limiter.lastRefill
	local newTokens = elapsed * limiter.refillRate
	limiter.tokens = math.min(limiter.maxTokens, limiter.tokens + newTokens)
	limiter.lastRefill = now

	if limiter.tokens >= 1 then
		limiter.tokens -= 1
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Format a block ID parameter for RPC calls
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

	local clockFn = config._clock or os.clock
	local maxRpm = config.maxRequestsPerMinute or 450

	local queueConfig = config.queueConfig or {}

	local self = setmetatable({
		_nodeUrl = config.nodeUrl,
		_headers = config.headers or {},
		_retryAttempts = config.retryAttempts or 3,
		_retryDelay = config.retryDelay or 1,
		_requestId = 0,
		_rateLimiter = createRateLimiter(maxRpm, clockFn),
		_httpRequest = config._httpRequest,
		_sleep = config._sleep or function(seconds: number)
			task.wait(seconds)
		end,
		_clock = clockFn,
		_PromiseModule = nil :: any,
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
		self._cache = ResponseCache.new(config.cacheConfig or {}, clockFn)
	end

	if config.enableNonceManager then
		self._nonceManager = NonceManager.new(self, config.nonceManagerConfig or {})
	end

	-- Load Promise module (skip in test mode where _httpRequest is injected)
	if not config._httpRequest then
		local ok, promiseMod = pcall(function()
			return require("@Packages/Promise") :: any
		end)
		if ok then
			self._PromiseModule = promiseMod
		end
	end

	return self :: any
end

--- Get the configured node URL
function RpcProviderClass:getNodeUrl(): string
	return self._nodeUrl
end

--- Internal: Get the Promise constructor
function RpcProviderClass:_getPromise(): any
	if self._PromiseModule then
		return self._PromiseModule
	end
	error(
		StarknetError.validation(
			"RpcProvider: Promise module not available. In tests, set _PromiseModule on the provider instance.",
			ErrorCodes.REQUIRED_FIELD.code
		)
	)
end

--- Internal: Perform an HTTP request (with injection point for testing)
function RpcProviderClass:_doHttpRequest(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
	if self._httpRequest then
		return self._httpRequest(request)
	end
	-- Default: use Roblox HttpService
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:RequestAsync(request)
end

--- Internal: JSON encode
function RpcProviderClass:_jsonEncode(value: any): string
	if self._httpRequest then
		-- In test/Lune environment, use the injected serde
		local serde = require("@lune/serde") :: any
		return serde.encode("json", value)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONEncode(value)
end

--- Internal: JSON decode
function RpcProviderClass:_jsonDecode(json: string): any
	if self._httpRequest then
		local serde = require("@lune/serde") :: any
		return serde.decode("json", json)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONDecode(json)
end

--- Internal: Wait for rate limit token, then perform a single JSON-RPC request
function RpcProviderClass:_rawRequest(method: string, params: any): any
	-- Rate limiting: spin-wait for a token
	local maxWait = 10 -- seconds
	local startTime = self._clock()
	while not tryAcquire(self._rateLimiter, self._clock) do
		if self._clock() - startTime > maxWait then
			error(
				StarknetError.rpc(
					"Rate limit exceeded: could not acquire token within timeout",
					ErrorCodes.RATE_LIMIT.code
				)
			)
		end
		self._sleep(0.05)
	end

	-- Build JSON-RPC request
	self._requestId += 1
	local rpcRequest: RpcTypes.JsonRpcRequest = {
		jsonrpc = "2.0",
		method = method,
		params = params,
		id = self._requestId,
	}

	local body = self:_jsonEncode(rpcRequest)
	local headers: { [string]: string } = {
		["Content-Type"] = "application/json",
	}
	for k, v in self._headers do
		headers[k] = v
	end

	local httpRequest: RpcTypes.HttpRequest = {
		Url = self._nodeUrl,
		Method = "POST",
		Headers = headers,
		Body = body,
	}

	local response = self:_doHttpRequest(httpRequest)

	if not response.Success and response.StatusCode ~= 200 then
		error(
			StarknetError.rpc(
				`HTTP {response.StatusCode}: {response.Body}`,
				ErrorCodes.NETWORK_ERROR.code,
				response.StatusCode
			)
		)
	end

	local decoded = self:_jsonDecode(response.Body)

	if decoded.error then
		error(
			StarknetError.rpc(
				decoded.error.message or "Unknown RPC error",
				ErrorCodes.RPC_ERROR.code,
				decoded.error.code,
				decoded.error.data
			)
		)
	end

	return decoded.result
end

--- Internal: Perform a JSON-RPC request with retry logic
function RpcProviderClass:_requestWithRetry(method: string, params: any): any
	local lastErr: any = nil
	for attempt = 1, self._retryAttempts do
		local ok, result = pcall(function()
			return self:_rawRequest(method, params)
		end)
		if ok then
			return result
		end

		lastErr = result

		-- Don't retry on RPC errors (they're deterministic)
		if typeof(result) == "table" and result._type == "RpcError" and result.code == ErrorCodes.RPC_ERROR.code then
			error(result)
		end

		-- Retry on transient errors (network, rate limit) with exponential backoff
		if attempt < self._retryAttempts then
			local delay = self._retryDelay * math.pow(2, attempt - 1)
			self._sleep(delay)
		end
	end

	error(lastErr)
end

--- Raw RPC call for custom/unsupported methods.
--- Returns a Promise that resolves to the raw JSON-RPC result.
--- When cache is enabled, checks cache first and stores successful results.
--- When queue is enabled, requests are enqueued and drained on the next defer cycle.
function RpcProviderClass:fetch(method: string, params: any, options: RpcTypes.FetchOptions?): any
	local Promise = self:_getPromise()
	local cache = self._cache
	local bypassCache = options and options.bypassCache

	-- Cache check: return cached result immediately on hit
	if cache and not bypassCache then
		local ttl = cache:getTTLForMethod(method)
		if ttl ~= nil then
			local cacheKey = method .. ":" .. self:_jsonEncode(params)
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
	local Promise = self:_getPromise()

	-- Queue path: enqueue + schedule drain
	if self._queue then
		return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
			self._queue:enqueue(method, params, resolve, reject)
			self:_scheduleDrain()
		end)
	end

	-- Direct path (no queue)
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local ok, result = pcall(function()
			return self:_requestWithRetry(method, params)
		end)
		if ok then
			resolve(result)
		else
			reject(result)
		end
	end)
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
		return self:_requestWithRetry(item.method, item.params)
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

	-- Acquire a single rate limit token for the batch
	local maxWait = 10
	local startTime = self._clock()
	while not tryAcquire(self._rateLimiter, self._clock) do
		if self._clock() - startTime > maxWait then
			local err = StarknetError.rpc(
				"Rate limit exceeded: could not acquire token within timeout",
				ErrorCodes.RATE_LIMIT.code
			)
			for _, item in items do
				if queue then
					queue:recordFailed()
				end
				item.reject(err)
			end
			return
		end
		self._sleep(0.05)
	end

	-- Build JSON-RPC batch array
	local batchRequest: { any } = {}
	local idToItem: { [number]: any } = {}
	for _, item in items do
		self._requestId += 1
		local rpcReq = {
			jsonrpc = "2.0",
			method = item.method,
			params = item.params,
			id = self._requestId,
		}
		table.insert(batchRequest, rpcReq)
		idToItem[self._requestId] = item
	end

	local body = self:_jsonEncode(batchRequest)
	local headers: { [string]: string } = {
		["Content-Type"] = "application/json",
	}
	for k, v in self._headers do
		headers[k] = v
	end

	local httpRequest: RpcTypes.HttpRequest = {
		Url = self._nodeUrl,
		Method = "POST",
		Headers = headers,
		Body = body,
	}

	local ok, response = pcall(function()
		return self:_doHttpRequest(httpRequest)
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
		return self:_jsonDecode(response.Body)
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

	if self._queue then
		local qm = self._queue:getMetrics()
		return {
			totalRequests = qm.totalRequests,
			totalCompleted = qm.totalCompleted,
			totalFailed = qm.totalFailed,
			totalBatched = qm.totalBatched,
			totalDropped = qm.totalDropped,
			currentQueueDepth = qm.currentQueueDepth,
			rateLimitTokens = math.floor(self._rateLimiter.tokens),
			rateLimitMax = self._rateLimiter.maxTokens,
			batchesSent = qm.batchesSent,
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

	return {
		totalRequests = 0,
		totalCompleted = 0,
		totalFailed = 0,
		totalBatched = 0,
		totalDropped = 0,
		currentQueueDepth = 0,
		rateLimitTokens = math.floor(self._rateLimiter.tokens),
		rateLimitMax = self._rateLimiter.maxTokens,
		batchesSent = 0,
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
--- Returns a Promise resolving to the transaction hash.
function RpcProviderClass:addInvokeTransaction(invokeTx: RpcTypes.InvokeTransactionV3): any
	return self:fetch("starknet_addInvokeTransaction", {
		{
			type = invokeTx.type,
			version = invokeTx.version,
			sender_address = invokeTx.sender_address,
			calldata = invokeTx.calldata,
			signature = invokeTx.signature,
			nonce = invokeTx.nonce,
			resource_bounds = invokeTx.resource_bounds,
			tip = invokeTx.tip,
			paymaster_data = invokeTx.paymaster_data,
			nonce_data_availability_mode = invokeTx.nonce_data_availability_mode,
			fee_data_availability_mode = invokeTx.fee_data_availability_mode,
			account_deployment_data = invokeTx.account_deployment_data,
		},
	}):andThen(function(result: any)
		if type(result) == "table" and result.transaction_hash then
			return result.transaction_hash
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
	local Promise = self:_getPromise()
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
				return self:_requestWithRetry("starknet_getEvents", {
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
	local Promise = self:_getPromise()
	local retryInterval = if options and options.retryInterval then options.retryInterval else 5
	local maxAttempts = if options and options.maxAttempts then options.maxAttempts else 30

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		for attempt = 1, maxAttempts do
			local statusOk, statusResult = pcall(function()
				-- Use _requestWithRetry directly to get synchronous result within this Promise executor
				return self:_requestWithRetry("starknet_getTransactionStatus", { txHash })
			end)

			if statusOk and statusResult then
				local finality = statusResult.finality_status
				local execution = statusResult.execution_status

				if finality == "ACCEPTED_ON_L2" or finality == "ACCEPTED_ON_L1" then
					-- Transaction is confirmed, fetch the full receipt
					local receiptOk, receipt = pcall(function()
						return self:_requestWithRetry("starknet_getTransactionReceipt", { txHash })
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
