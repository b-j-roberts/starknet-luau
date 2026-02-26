--!strict
local ResponseCache = require("../../src/provider/ResponseCache")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local currentTime = 0

local function mockClock(): number
	return currentTime
end

local function advanceTime(seconds: number)
	currentTime += seconds
end

local function resetTime()
	currentTime = 0
end

local function createCache(config: { [string]: any }?): any
	return ResponseCache.new(config, mockClock)
end

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("ResponseCache - constructor", function()
	it("creates an empty cache", function()
		resetTime()
		local cache = createCache()
		expect(cache:size()):toBe(0)
	end)

	it("accepts custom maxEntries", function()
		resetTime()
		local cache = createCache({ maxEntries = 10 })
		expect(cache:size()):toBe(0)
	end)

	it("defaults maxEntries to 256", function()
		resetTime()
		local cache = createCache()
		-- Fill 256 entries
		for i = 1, 256 do
			cache:set("key" .. tostring(i), "val" .. tostring(i), 0)
		end
		expect(cache:size()):toBe(256)
		-- 257th should cause eviction, not grow beyond 256
		cache:set("key257", "val257", 0)
		expect(cache:size()):toBe(256)
	end)

	it("accepts custom TTL overrides", function()
		resetTime()
		local cache = createCache({ storageTTL = 60 })
		local ttl = cache:getTTLForMethod("starknet_getStorageAt")
		expect(ttl):toBe(60)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: get/set basics
--------------------------------------------------------------------------------

describe("ResponseCache - get/set basics", function()
	it("returns nil for missing key", function()
		resetTime()
		local cache = createCache()
		expect(cache:get("missing")):toBe(nil)
	end)

	it("stores and retrieves a string value", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "hello", 0)
		expect(cache:get("key1")):toBe("hello")
	end)

	it("stores and retrieves a table value", function()
		resetTime()
		local cache = createCache()
		local val = { "0x1", "0x2" }
		cache:set("key1", val, 0)
		local result = cache:get("key1")
		expect(result):toEqual(val)
	end)

	it("stores and retrieves a number value", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", 42, 0)
		expect(cache:get("key1")):toBe(42)
	end)

	it("stores and retrieves a boolean value", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", true, 0)
		expect(cache:get("key1")):toBe(true)
	end)

	it("overwrites existing entry with same key", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "old", 0)
		cache:set("key1", "new", 0)
		expect(cache:get("key1")):toBe("new")
		expect(cache:size()):toBe(1)
	end)

	it("stores multiple distinct keys", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		expect(cache:get("a")):toBe(1)
		expect(cache:get("b")):toBe(2)
		expect(cache:get("c")):toBe(3)
		expect(cache:size()):toBe(3)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: TTL expiration
--------------------------------------------------------------------------------

describe("ResponseCache - TTL expiration", function()
	it("returns value before TTL expires", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 10)
		advanceTime(9)
		expect(cache:get("key1")):toBe("val")
	end)

	it("returns nil after TTL expires", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 10)
		advanceTime(10)
		expect(cache:get("key1")):toBe(nil)
	end)

	it("indefinite TTL (0) never expires", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 0)
		advanceTime(999999)
		expect(cache:get("key1")):toBe("val")
	end)

	it("expired entry is removed from cache", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 5)
		expect(cache:size()):toBe(1)
		advanceTime(5)
		cache:get("key1") -- triggers removal
		expect(cache:size()):toBe(0)
	end)

	it("updating entry resets TTL", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val1", 10)
		advanceTime(8)
		cache:set("key1", "val2", 10) -- reset TTL
		advanceTime(5)
		-- 13s total, but only 5s since reset — should still be valid
		expect(cache:get("key1")):toBe("val2")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: LRU eviction
--------------------------------------------------------------------------------

describe("ResponseCache - LRU eviction", function()
	it("evicts least recently used when at capacity", function()
		resetTime()
		local cache = createCache({ maxEntries = 3 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		-- Cache full: a(tail), b, c(head)
		cache:set("d", 4, 0) -- evicts "a"
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(2)
		expect(cache:get("c")):toBe(3)
		expect(cache:get("d")):toBe(4)
		expect(cache:size()):toBe(3)
	end)

	it("accessing entry moves it to front (prevents eviction)", function()
		resetTime()
		local cache = createCache({ maxEntries = 3 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		-- Access "a" to move it to front
		cache:get("a")
		-- Now: b(tail), c, a(head)
		cache:set("d", 4, 0) -- evicts "b" (new tail)
		expect(cache:get("a")):toBe(1) -- still alive
		expect(cache:get("b")):toBe(nil) -- evicted
		expect(cache:get("d")):toBe(4)
	end)

	it("updating entry moves it to front (prevents eviction)", function()
		resetTime()
		local cache = createCache({ maxEntries = 3 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		-- Update "a" to move it to front
		cache:set("a", 10, 0)
		-- Now: b(tail), c, a(head)
		cache:set("d", 4, 0) -- evicts "b"
		expect(cache:get("a")):toBe(10)
		expect(cache:get("b")):toBe(nil)
	end)

	it("evicts multiple entries to make room", function()
		resetTime()
		local cache = createCache({ maxEntries = 2 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0) -- evicts "a"
		cache:set("d", 4, 0) -- evicts "b"
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(nil)
		expect(cache:get("c")):toBe(3)
		expect(cache:get("d")):toBe(4)
		expect(cache:size()):toBe(2)
	end)

	it("capacity of 1 always holds the latest entry", function()
		resetTime()
		local cache = createCache({ maxEntries = 1 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(2)
		expect(cache:size()):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: invalidate
--------------------------------------------------------------------------------

describe("ResponseCache - invalidate", function()
	it("removes an existing entry", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 0)
		cache:invalidate("key1")
		expect(cache:get("key1")):toBe(nil)
		expect(cache:size()):toBe(0)
	end)

	it("no-ops on non-existent key", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 0)
		cache:invalidate("missing")
		expect(cache:size()):toBe(1)
	end)

	it("removes head entry correctly", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:set("b", 2, 0) -- head
		cache:invalidate("b")
		expect(cache:get("a")):toBe(1)
		expect(cache:get("b")):toBe(nil)
		expect(cache:size()):toBe(1)
	end)

	it("removes tail entry correctly", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0) -- tail
		cache:set("b", 2, 0)
		cache:invalidate("a")
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(2)
		expect(cache:size()):toBe(1)
	end)

	it("removes middle entry correctly", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		cache:invalidate("b")
		expect(cache:get("a")):toBe(1)
		expect(cache:get("b")):toBe(nil)
		expect(cache:get("c")):toBe(3)
		expect(cache:size()):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: invalidateByPrefix
--------------------------------------------------------------------------------

describe("ResponseCache - invalidateByPrefix", function()
	it("removes all entries matching prefix", function()
		resetTime()
		local cache = createCache()
		cache:set("starknet_getStorageAt:a", 1, 0)
		cache:set("starknet_getStorageAt:b", 2, 0)
		cache:set("starknet_chainId:c", 3, 0)
		cache:invalidateByPrefix("starknet_getStorageAt:")
		expect(cache:get("starknet_getStorageAt:a")):toBe(nil)
		expect(cache:get("starknet_getStorageAt:b")):toBe(nil)
		expect(cache:get("starknet_chainId:c")):toBe(3)
		expect(cache:size()):toBe(1)
	end)

	it("no-ops when no entries match prefix", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", 1, 0)
		cache:set("key2", 2, 0)
		cache:invalidateByPrefix("missing:")
		expect(cache:size()):toBe(2)
	end)

	it("removes all entries when prefix matches everything", function()
		resetTime()
		local cache = createCache()
		cache:set("starknet_a", 1, 0)
		cache:set("starknet_b", 2, 0)
		cache:invalidateByPrefix("starknet_")
		expect(cache:size()):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: flush
--------------------------------------------------------------------------------

describe("ResponseCache - flush", function()
	it("clears all entries", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0)
		cache:flush()
		expect(cache:size()):toBe(0)
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(nil)
		expect(cache:get("c")):toBe(nil)
	end)

	it("flush on empty cache is safe", function()
		resetTime()
		local cache = createCache()
		cache:flush()
		expect(cache:size()):toBe(0)
	end)

	it("cache is usable after flush", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:flush()
		cache:set("b", 2, 0)
		expect(cache:get("b")):toBe(2)
		expect(cache:size()):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getTTLForMethod
--------------------------------------------------------------------------------

describe("ResponseCache - getTTLForMethod", function()
	it("returns 0 (indefinite) for chainId", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_chainId")):toBe(0)
	end)

	it("returns 0 (indefinite) for specVersion", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_specVersion")):toBe(0)
	end)

	it("returns 10 for blockNumber", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_blockNumber")):toBe(10)
	end)

	it("returns 10 for getBlockWithTxHashes", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getBlockWithTxHashes")):toBe(10)
	end)

	it("returns 0 (indefinite) for getClassHashAt", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getClassHashAt")):toBe(0)
	end)

	it("returns 30 for getStorageAt", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getStorageAt")):toBe(30)
	end)

	it("returns 30 for call", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_call")):toBe(30)
	end)

	it("returns nil for addInvokeTransaction (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_addInvokeTransaction")):toBe(nil)
	end)

	it("returns nil for estimateFee (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_estimateFee")):toBe(nil)
	end)

	it("returns nil for getNonce (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getNonce")):toBe(nil)
	end)

	it("returns nil for getTransactionReceipt (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getTransactionReceipt")):toBe(nil)
	end)

	it("returns nil for getTransactionStatus (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getTransactionStatus")):toBe(nil)
	end)

	it("returns nil for getEvents (uncacheable)", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_getEvents")):toBe(nil)
	end)

	it("returns nil for unknown methods", function()
		resetTime()
		local cache = createCache()
		expect(cache:getTTLForMethod("starknet_unknownMethod")):toBe(nil)
	end)

	it("respects custom TTL overrides", function()
		resetTime()
		local cache = createCache({ storageTTL = 120, callTTL = 5 })
		expect(cache:getTTLForMethod("starknet_getStorageAt")):toBe(120)
		expect(cache:getTTLForMethod("starknet_call")):toBe(5)
		-- Non-overridden methods keep defaults
		expect(cache:getTTLForMethod("starknet_blockNumber")):toBe(10)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: metrics
--------------------------------------------------------------------------------

describe("ResponseCache - metrics", function()
	it("starts with zero metrics", function()
		resetTime()
		local cache = createCache()
		local m = cache:getMetrics()
		expect(m.cacheHits):toBe(0)
		expect(m.cacheMisses):toBe(0)
		expect(m.cacheEvictions):toBe(0)
		expect(m.cacheSize):toBe(0)
	end)

	it("tracks cache misses", function()
		resetTime()
		local cache = createCache()
		cache:get("missing1")
		cache:get("missing2")
		local m = cache:getMetrics()
		expect(m.cacheMisses):toBe(2)
		expect(m.cacheHits):toBe(0)
	end)

	it("tracks cache hits", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 0)
		cache:get("key1")
		cache:get("key1")
		local m = cache:getMetrics()
		expect(m.cacheHits):toBe(2)
	end)

	it("tracks evictions", function()
		resetTime()
		local cache = createCache({ maxEntries = 2 })
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		cache:set("c", 3, 0) -- evicts "a"
		local m = cache:getMetrics()
		expect(m.cacheEvictions):toBe(1)
	end)

	it("tracks current cache size", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:set("b", 2, 0)
		expect(cache:getMetrics().cacheSize):toBe(2)
		cache:invalidate("a")
		expect(cache:getMetrics().cacheSize):toBe(1)
	end)

	it("expired entry counts as miss", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "val", 5)
		advanceTime(5)
		cache:get("key1") -- expired = miss
		local m = cache:getMetrics()
		expect(m.cacheMisses):toBe(1)
		expect(m.cacheHits):toBe(0)
	end)

	it("metrics persist across flush", function()
		resetTime()
		local cache = createCache()
		cache:set("a", 1, 0)
		cache:get("a") -- hit
		cache:get("b") -- miss
		cache:flush()
		local m = cache:getMetrics()
		expect(m.cacheHits):toBe(1)
		expect(m.cacheMisses):toBe(1)
		expect(m.cacheSize):toBe(0) -- flushed
	end)
end)

--------------------------------------------------------------------------------
-- Tests: edge cases
--------------------------------------------------------------------------------

describe("ResponseCache - edge cases", function()
	it("handles empty string key", function()
		resetTime()
		local cache = createCache()
		cache:set("", "empty", 0)
		expect(cache:get("")):toBe("empty")
	end)

	it("handles empty string value", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", "", 0)
		expect(cache:get("key1")):toBe("")
	end)

	it("handles false value (not confused with nil)", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", false, 0)
		-- false is a valid cached value, distinct from nil (cache miss)
		expect(cache:get("key1")):toBe(false)
	end)

	it("handles zero numeric value", function()
		resetTime()
		local cache = createCache()
		cache:set("key1", 0, 0)
		expect(cache:get("key1")):toBe(0)
	end)

	it("simultaneous expiration and eviction", function()
		resetTime()
		local cache = createCache({ maxEntries = 2 })
		cache:set("a", 1, 5)
		cache:set("b", 2, 5)
		advanceTime(5) -- both expired
		-- get should return nil for expired entries
		expect(cache:get("a")):toBe(nil)
		expect(cache:get("b")):toBe(nil)
	end)

	it("large number of entries with eviction", function()
		resetTime()
		local cache = createCache({ maxEntries = 10 })
		for i = 1, 50 do
			cache:set("key" .. tostring(i), i, 0)
		end
		expect(cache:size()):toBe(10)
		-- Last 10 entries should survive
		for i = 41, 50 do
			expect(cache:get("key" .. tostring(i))):toBe(i)
		end
		-- Earlier entries should be evicted
		expect(cache:get("key1")):toBe(nil)
	end)
end)
