--!strict
-- ResponseCache: LRU cache with per-method TTL for JSON-RPC responses
-- Intercepts at the fetch() level to eliminate redundant HTTP calls.
-- O(1) get/set/evict via doubly-linked list + hash map (pure Luau tables).

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type CacheEntry = {
	key: string,
	value: any, -- wrapped as {value=result} to distinguish nil from miss
	expiresAt: number, -- 0 = never expires
	prev: CacheEntry?,
	next: CacheEntry?,
}

export type CacheMetrics = {
	cacheHits: number,
	cacheMisses: number,
	cacheEvictions: number,
	cacheSize: number,
}

export type ResponseCache = {
	get: (self: ResponseCache, key: string) -> any?,
	set: (self: ResponseCache, key: string, value: any, ttl: number) -> (),
	invalidate: (self: ResponseCache, key: string) -> (),
	invalidateByPrefix: (self: ResponseCache, prefix: string) -> (),
	flush: (self: ResponseCache) -> (),
	getTTLForMethod: (self: ResponseCache, method: string) -> number?,
	getMetrics: (self: ResponseCache) -> CacheMetrics,
	size: (self: ResponseCache) -> number,
}

--------------------------------------------------------------------------------
-- Per-method TTL policy
--------------------------------------------------------------------------------

-- Methods that should NEVER be cached (returns nil from getTTLForMethod)
local UNCACHEABLE: { [string]: boolean } = {
	["starknet_addInvokeTransaction"] = true,
	["starknet_estimateFee"] = true,
	["starknet_estimateMessageFee"] = true,
	["starknet_getNonce"] = true,
	["starknet_getTransactionReceipt"] = true,
	["starknet_getTransactionStatus"] = true,
	["starknet_getTransactionByHash"] = true,
	["starknet_getEvents"] = true,
	["starknet_syncing"] = true,
}

-- Config key mapping for methods with configurable TTLs
local METHOD_TTL_CONFIG_KEY: { [string]: string } = {
	["starknet_chainId"] = "chainIdTTL",
	["starknet_specVersion"] = "specVersionTTL",
	["starknet_blockNumber"] = "blockNumberTTL",
	["starknet_getBlockWithTxHashes"] = "blockTTL",
	["starknet_getBlockWithTxs"] = "blockTTL",
	["starknet_getBlockWithReceipts"] = "blockTTL",
	["starknet_getClassHashAt"] = "classHashTTL",
	["starknet_getClass"] = "classTTL",
	["starknet_getClassAt"] = "classTTL",
	["starknet_getStorageAt"] = "storageTTL",
	["starknet_call"] = "callTTL",
}

-- Default TTLs (seconds, 0 = indefinite)
local DEFAULT_TTLS: { [string]: number } = {
	chainIdTTL = 0,
	specVersionTTL = 0,
	blockNumberTTL = 10,
	blockTTL = 10,
	classHashTTL = 0,
	classTTL = 0,
	storageTTL = 30,
	callTTL = 30,
}

--------------------------------------------------------------------------------
-- ResponseCache class
--------------------------------------------------------------------------------

local ResponseCacheClass = {}
ResponseCacheClass.__index = ResponseCacheClass

--- Create a new ResponseCache.
--- @param config -- CacheConfig with optional TTL overrides and maxEntries
--- @param clockFn -- injectable clock for testability (defaults to os.clock)
function ResponseCacheClass.new(config: { [string]: any }?, clockFn: (() -> number)?): ResponseCache
	local cfg = config or {}

	-- Resolve TTLs: user config overrides defaults
	local ttls: { [string]: number } = {}
	for key, defaultVal in DEFAULT_TTLS do
		local userVal = (cfg :: any)[key]
		if userVal ~= nil then
			ttls[key] = userVal
		else
			ttls[key] = defaultVal
		end
	end

	local self = setmetatable({
		_map = {} :: { [string]: CacheEntry }, -- key -> entry
		_head = nil :: CacheEntry?, -- most recently used
		_tail = nil :: CacheEntry?, -- least recently used
		_size = 0,
		_maxEntries = cfg.maxEntries or 256,
		_clock = clockFn or os.clock,
		_ttls = ttls,
		_metrics = {
			cacheHits = 0,
			cacheMisses = 0,
			cacheEvictions = 0,
		},
	}, ResponseCacheClass)

	return self :: any
end

--------------------------------------------------------------------------------
-- Internal linked-list operations
--------------------------------------------------------------------------------

--- Remove an entry from the doubly-linked list (does NOT remove from _map).
function ResponseCacheClass:_unlink(entry: CacheEntry)
	local prev = entry.prev
	local nxt = entry.next

	if prev then
		prev.next = nxt
	else
		-- entry was the head
		self._head = nxt
	end

	if nxt then
		nxt.prev = prev
	else
		-- entry was the tail
		self._tail = prev
	end

	entry.prev = nil
	entry.next = nil
end

--- Push an entry to the front (head) of the list.
function ResponseCacheClass:_pushFront(entry: CacheEntry)
	entry.prev = nil
	entry.next = self._head

	if self._head then
		self._head.prev = entry
	end
	self._head = entry

	if not self._tail then
		self._tail = entry
	end
end

--- Move an existing entry to the front (most recently used).
function ResponseCacheClass:_moveToFront(entry: CacheEntry)
	if self._head == entry then
		return -- already at front
	end
	self:_unlink(entry)
	self:_pushFront(entry)
end

--- Evict the least recently used entry (tail).
function ResponseCacheClass:_evictTail()
	local tail = self._tail
	if not tail then
		return
	end
	self:_unlink(tail)
	self._map[tail.key] = nil
	self._size -= 1
	self._metrics.cacheEvictions += 1
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Get a cached value by key. Returns the cached result or nil on miss.
--- Expired entries are treated as misses and removed.
function ResponseCacheClass:get(key: string): any?
	local entry = self._map[key]
	if not entry then
		self._metrics.cacheMisses += 1
		return nil
	end

	-- Check TTL expiration (0 = never expires)
	if entry.expiresAt > 0 and self._clock() >= entry.expiresAt then
		-- Expired: remove and return miss
		self:_unlink(entry)
		self._map[key] = nil
		self._size -= 1
		self._metrics.cacheMisses += 1
		return nil
	end

	-- Hit: move to front and return value
	self:_moveToFront(entry)
	self._metrics.cacheHits += 1
	return entry.value
end

--- Store a value in the cache with a given TTL (seconds, 0 = indefinite).
--- Evicts LRU tail if at capacity.
function ResponseCacheClass:set(key: string, value: any, ttl: number)
	local now = self._clock()
	local expiresAt = if ttl > 0 then now + ttl else 0

	-- Update existing entry
	local existing = self._map[key]
	if existing then
		existing.value = value
		existing.expiresAt = expiresAt
		self:_moveToFront(existing)
		return
	end

	-- Evict if at capacity
	if self._size >= self._maxEntries then
		self:_evictTail()
	end

	-- Create new entry
	local entry: CacheEntry = {
		key = key,
		value = value,
		expiresAt = expiresAt,
		prev = nil,
		next = nil,
	}

	self._map[key] = entry
	self:_pushFront(entry)
	self._size += 1
end

--- Remove a single entry by exact key.
function ResponseCacheClass:invalidate(key: string)
	local entry = self._map[key]
	if not entry then
		return
	end
	self:_unlink(entry)
	self._map[key] = nil
	self._size -= 1
end

--- Remove all entries whose keys start with the given prefix.
function ResponseCacheClass:invalidateByPrefix(prefix: string)
	local keysToRemove: { string } = {}
	for key, _ in self._map do
		if string.sub(key, 1, #prefix) == prefix then
			table.insert(keysToRemove, key)
		end
	end
	for _, key in keysToRemove do
		self:invalidate(key)
	end
end

--- Clear all cached entries.
function ResponseCacheClass:flush()
	self._map = {}
	self._head = nil
	self._tail = nil
	self._size = 0
end

--- Get the TTL for an RPC method. Returns nil if the method is not cacheable.
function ResponseCacheClass:getTTLForMethod(method: string): number?
	if UNCACHEABLE[method] then
		return nil
	end

	local configKey = METHOD_TTL_CONFIG_KEY[method]
	if configKey then
		return self._ttls[configKey]
	end

	-- Unknown method: not cacheable
	return nil
end

--- Get current cache size.
function ResponseCacheClass:size(): number
	return self._size
end

--- Get a snapshot of cache metrics.
function ResponseCacheClass:getMetrics(): CacheMetrics
	return {
		cacheHits = self._metrics.cacheHits,
		cacheMisses = self._metrics.cacheMisses,
		cacheEvictions = self._metrics.cacheEvictions,
		cacheSize = self._size,
	}
end

return ResponseCacheClass
