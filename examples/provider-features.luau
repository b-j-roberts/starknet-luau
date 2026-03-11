--!strict
-- provider-features.luau
-- Configure RequestQueue, ResponseCache, and NonceManager for production use.
--
-- This example shows how to:
--   1. Enable RequestQueue for automatic request batching and prioritization
--   2. Enable ResponseCache for LRU caching with per-method TTLs
--   3. Enable NonceManager for safe concurrent transaction submission
--   4. Monitor metrics for queue depth, cache hits, and nonce tracking
--
-- These features are opt-in via RpcProvider config flags. When disabled (default),
-- the provider behaves identically to v0.1.0 — zero overhead, zero behavior change.
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- WARNING: Never hardcode private keys in production code.
local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"

--------------------------------------------------------------------------------
-- Full-featured provider setup
--------------------------------------------------------------------------------

-- Enable all three production features: queue, cache, and nonce manager.
local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,

	-- Rate limiting: max RPC requests per minute (default 450)
	maxRequestsPerMinute = 300,

	-- Retry: automatic retries on transient network errors
	retryAttempts = 3,
	retryDelay = 1, -- initial delay in seconds (doubles on each retry)

	------------------------------------------------------------------------
	-- RequestQueue: batches concurrent RPC calls into fewer HTTP requests
	------------------------------------------------------------------------
	enableQueue = true,
	queueConfig = {
		-- Maximum queued requests before rejecting with QUEUE_FULL error
		maxQueueDepth = 100,

		-- Maximum requests per JSON-RPC batch (single HTTP call)
		maxBatchSize = 20,

		-- Enable batching: groups compatible read-only calls into arrays.
		-- HIGH priority (addInvoke, estimateFee) are always sent individually.
		-- LOW priority (getEvents) and NORMAL (getNonce, call, etc.) are batched.
		enableBatching = true,
	},

	------------------------------------------------------------------------
	-- ResponseCache: LRU cache avoids redundant RPC calls
	------------------------------------------------------------------------
	enableCache = true,
	cacheConfig = {
		-- Maximum cached entries (LRU eviction when exceeded)
		maxEntries = 256,

		-- Per-method TTLs (seconds). 0 = cache indefinitely.
		-- These are the defaults — customize as needed:
		chainIdTTL = 0, -- chain ID never changes
		specVersionTTL = 0, -- spec version rarely changes
		classHashTTL = 0, -- class hashes are immutable
		classTTL = 0, -- contract classes are immutable
		blockNumberTTL = 10, -- block number changes every ~12s
		blockTTL = 10, -- block data is stable once confirmed
		storageTTL = 30, -- storage can change each block
		callTTL = 30, -- call results can change each block

		-- Never cached (by design): getNonce, estimateFee, addInvoke,
		-- getTransactionReceipt/Status, getEvents
	},

	------------------------------------------------------------------------
	-- NonceManager: safe nonce tracking for concurrent transactions
	------------------------------------------------------------------------
	enableNonceManager = true,
	nonceManagerConfig = {
		-- Maximum outstanding (unconfirmed) nonces per address.
		-- Prevents unbounded nonce growth if confirmations are slow.
		maxPendingNonces = 10,

		-- Auto-resync from chain when a nonce error is detected.
		autoResyncOnError = true,
	},
})

print("[Provider] Provider configured with queue + cache + nonce manager")

--------------------------------------------------------------------------------
-- Demonstrate cache behavior
--------------------------------------------------------------------------------

print("[Provider] --- Cache demonstration ---")

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)

-- First call: cache miss — hits the RPC node
ethToken
	:name()
	:andThen(function(name)
		print("[Provider] ETH name (1st call — cache miss):", name)

		-- Check cache metrics after first call
		local metrics = provider:getMetrics()
		print("[Provider] Cache hits:", metrics.cacheHits)
		print("[Provider] Cache misses:", metrics.cacheMisses)

		-- Second call: cache hit — returns instantly from LRU cache, no HTTP
		return ethToken:name()
	end)
	:andThen(function(name)
		print("[Provider] ETH name (2nd call — cache hit):", name)

		local metrics = provider:getMetrics()
		print("[Provider] Cache hits:", metrics.cacheHits)
		print("[Provider] Cache misses:", metrics.cacheMisses)
	end)
	:catch(function(err)
		warn("[Provider] Error:", tostring(err))
	end)

--------------------------------------------------------------------------------
-- Demonstrate queue batching
--------------------------------------------------------------------------------

print("[Provider] --- Queue batching demonstration ---")

-- When multiple RPC calls are made in the same frame, the queue batches them
-- into a single HTTP request. This is transparent — each caller gets their
-- individual Promise resolved.

-- Fire off 3 calls in the same frame — they'll be batched into 1 HTTP call
local p1 = provider:getBlockNumber()
local p2 = provider:getChainId()
local p3 = provider:getSpecVersion()

-- All three resolve from the same batched response
p1:andThen(function(blockNumber)
	print("[Provider] Block number:", blockNumber)
end)

p2:andThen(function(chainId)
	print("[Provider] Chain ID:", chainId)
end)

p3:andThen(function(specVersion)
	print("[Provider] Spec version:", specVersion)
end)

-- Check queue metrics after batch
task.defer(function()
	local metrics = provider:getMetrics()
	print("[Provider] Queue metrics:")
	print("  Total requests:", metrics.totalRequests)
	print("  Batches sent:", metrics.batchesSent)
	print("  Total batched:", metrics.totalBatched)
end)

--------------------------------------------------------------------------------
-- Demonstrate nonce manager for concurrent transactions
--------------------------------------------------------------------------------

print("[Provider] --- Nonce manager demonstration ---")

-- Without NonceManager, two concurrent execute() calls would both fetch the
-- same nonce from the chain, causing one to fail with INVALID_NONCE.
-- With NonceManager, each call reserves the next nonce locally.

local ethTokenWithAccount = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)
local RECIPIENT_1 = "0x_RECIPIENT_1"
local RECIPIENT_2 = "0x_RECIPIENT_2"
local AMOUNT = "0x38D7EA4C68000" -- 0.001 ETH

-- Submit two transactions concurrently — NonceManager assigns sequential nonces
local tx1 = ethTokenWithAccount:transfer(RECIPIENT_1, AMOUNT)
local tx2 = ethTokenWithAccount:transfer(RECIPIENT_2, AMOUNT)

tx1:andThen(function(result)
	print("[Provider] Tx 1 submitted:", result.transactionHash)
end):catch(function(err)
	warn("[Provider] Tx 1 failed:", tostring(err))
end)

tx2:andThen(function(result)
	print("[Provider] Tx 2 submitted:", result.transactionHash)
end):catch(function(err)
	warn("[Provider] Tx 2 failed:", tostring(err))
end)

-- Monitor nonce manager state
task.defer(function()
	local nonceManager = provider:getNonceManager()
	if nonceManager then
		local nonceMeta = nonceManager:getMetrics()
		print("[Provider] Nonce metrics:")
		print("  Total reserved:", nonceMeta.totalReserved)
		print("  Total confirmed:", nonceMeta.totalConfirmed)
		print("  Total rejected:", nonceMeta.totalRejected)
	end
end)

--------------------------------------------------------------------------------
-- Manual cache management
--------------------------------------------------------------------------------

print("[Provider] --- Cache management ---")

-- Flush all cached entries (useful when you know state has changed)
-- provider:flushCache()

-- Bypass cache for a specific call
-- provider:fetch("starknet_getStorageAt", { address, key, "latest" }, { bypassCache = true })

-- Check total provider metrics
task.defer(function()
	local metrics = provider:getMetrics()
	print("[Provider] Total provider metrics:")
	print("  Requests:", metrics.totalRequests)
	print(
		"  Cache hit rate:",
		if metrics.cacheHits + metrics.cacheMisses > 0
			then string.format("%.0f%%", metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses) * 100)
			else "N/A"
	)
end)

return {}
