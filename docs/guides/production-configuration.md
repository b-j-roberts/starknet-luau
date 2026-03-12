# Production Configuration

Tune the SDK for production: request batching, response caching, nonce management, error handling, and monitoring.

## Prerequisites

- Completed [Guide 3: Accounts & Transactions](accounts-and-transactions.md)
- A working RpcProvider connected to Starknet Sepolia or Mainnet

## The Three Opt-In Systems

The SDK ships with three production features that are **disabled by default**. When disabled, the provider behaves identically to a bare setup -- zero overhead, zero behavior change. Enable them via config flags when you're ready to move past prototyping:

| Feature | Config Flag | What It Does |
|---------|-------------|--------------|
| **RequestQueue** | `enableQueue = true` | Batches concurrent RPC calls into fewer HTTP requests |
| **ResponseCache** | `enableCache = true` | LRU cache eliminates redundant network calls |
| **NonceManager** | `enableNonceManager = true` | Tracks nonces locally for safe concurrent transactions |

Here's a full production provider setup with all three enabled:

```luau
--!strict
-- ServerScriptService/ProductionProvider.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",

	-- Rate limiting: max RPC requests per minute (default 450)
	maxRequestsPerMinute = 300,

	-- Retry: automatic retries on transient network errors
	retryAttempts = 3,
	retryDelay = 1, -- initial delay in seconds (doubles on each retry)

	-- Request batching
	enableQueue = true,
	queueConfig = {
		maxQueueDepth = 100,
		maxBatchSize = 20,
		enableBatching = true,
	},

	-- Response caching
	enableCache = true,
	cacheConfig = {
		maxEntries = 256,
	},

	-- Nonce management
	enableNonceManager = true,
	nonceManagerConfig = {
		maxPendingNonces = 10,
		autoResyncOnError = true,
	},
})
```

The rest of this guide walks through each system in detail.

## Request Queue

The RequestQueue batches concurrent RPC calls into fewer HTTP requests. When multiple calls happen in the same frame, they're grouped into a single JSON-RPC batch -- one HTTP round-trip instead of many.

### How It Works

The queue uses three priority buckets:

| Priority | Methods | Behavior |
|----------|---------|----------|
| **HIGH** | `addInvokeTransaction`, `addDeployAccountTransaction`, `estimateFee` | Dispatched individually, never batched |
| **NORMAL** | `getNonce`, `call`, `getBlockWithTxHashes`, `getStorageAt`, etc. | Grouped into JSON-RPC batch arrays |
| **LOW** | `getEvents` | Grouped into batches, processed after NORMAL |

HIGH-priority requests (writes and fee estimation) are always sent immediately as individual HTTP calls. NORMAL and LOW requests are collected and sent as a single batch.

### Batching in Action

When you fire multiple reads in the same frame, the queue collects them and sends one HTTP request:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableQueue = true,
	queueConfig = {
		maxQueueDepth = 100,
		maxBatchSize = 20,
		enableBatching = true,
	},
})

-- These three calls happen in the same frame.
-- Without the queue: 3 HTTP requests.
-- With the queue: 1 HTTP request containing a JSON-RPC batch array.
local p1 = provider:getBlockNumber()
local p2 = provider:getChainId()
local p3 = provider:getSpecVersion()

-- Each Promise resolves individually from the batched response
p1:andThen(function(blockNumber)
	print("Block:", blockNumber)
end)

p2:andThen(function(chainId)
	print("Chain:", chainId)
end)

p3:andThen(function(version)
	print("Version:", version)
end)
```

### Backpressure

When the queue depth hits `maxQueueDepth`, new requests are rejected immediately with a `QUEUE_FULL` error (code 2010). This prevents unbounded memory growth if your game fires more requests than the network can handle:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableQueue = true,
	queueConfig = {
		maxQueueDepth = 50, -- tighter limit for resource-constrained servers
	},
})

provider
	:getBlockNumber()
	:catch(function(err)
		if StarknetError.isStarknetError(err) and err.code == ErrorCodes.QUEUE_FULL.code then
			warn("Request queue full -- back off and retry later")
		else
			warn("Error:", tostring(err))
		end
	end)
```

### Queue Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxQueueDepth` | `number` | 100 | Maximum queued requests before rejecting with QUEUE_FULL |
| `maxBatchSize` | `number` | 20 | Maximum requests per JSON-RPC batch (single HTTP call) |
| `enableBatching` | `boolean` | true | Group compatible read-only calls into batch arrays |

## Response Cache

The ResponseCache is an LRU cache that stores RPC responses with per-method TTLs. Cache hits return instantly from memory with zero HTTP, zero queue, and zero rate-limit cost.

### Default TTL Policy

The cache applies different TTLs based on how frequently each type of data changes:

| Category | Methods | Default TTL | Rationale |
|----------|---------|-------------|-----------|
| **Immutable** | `chainId`, `specVersion`, `classHash`, `class` | 0 (indefinite) | These values never change |
| **Block data** | `blockNumber`, `blockWithTxHashes`, `blockWithTxs`, `blockWithReceipts` | 10s | Updates roughly every 12s on Starknet |
| **State** | `getStorageAt`, `call` | 30s | Can change each block, but reads are often repetitive |
| **Never cached** | `getNonce`, `estimateFee`, `addInvokeTransaction`, `getTransactionReceipt`, `getTransactionStatus`, `getEvents` | N/A | Write operations, nonces, and transaction status must always be fresh |

### Customizing TTLs

Override any TTL via `cacheConfig`. Set a TTL to `0` for indefinite caching, or increase it to reduce network calls at the cost of staleness:

```luau
local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableCache = true,
	cacheConfig = {
		maxEntries = 512, -- double the default LRU capacity
		storageTTL = 60, -- cache storage reads for 60s instead of 30s
		callTTL = 60, -- cache contract call results for 60s
		blockNumberTTL = 5, -- poll block number more aggressively
	},
})
```

### Block-Aware Invalidation

The cache automatically invalidates state-sensitive entries when it detects a new block. When `getBlockNumber()` returns a higher block than previously seen, the cache flushes all `getStorageAt`, `call`, and block data entries. Immutable data (chain ID, class hashes) is never invalidated.

This means you don't need to manually flush the cache in most cases -- stale data clears itself on each new block.

### Manual Cache Control

For cases where you know state has changed (e.g., right after submitting a transaction), flush the cache explicitly:

```luau
-- Flush all cached entries
provider:flushCache()
```

### Cache Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxEntries` | `number` | 256 | Maximum cached entries before LRU eviction |
| `chainIdTTL` | `number` | 0 | Chain ID TTL in seconds (0 = indefinite) |
| `specVersionTTL` | `number` | 0 | Spec version TTL |
| `classHashTTL` | `number` | 0 | Class hash TTL |
| `classTTL` | `number` | 0 | Contract class TTL |
| `blockNumberTTL` | `number` | 10 | Block number TTL |
| `blockTTL` | `number` | 10 | Block data TTL |
| `storageTTL` | `number` | 30 | Storage read TTL |
| `callTTL` | `number` | 30 | Contract call result TTL |

## Nonce Manager

Without a nonce manager, two concurrent `account:execute()` calls both fetch the same nonce from the chain. One succeeds; the other fails with `INVALID_NONCE`. The NonceManager solves this by tracking nonces locally using a reserve-confirm-reject pattern.

### How It Works

1. **Reserve**: Before sending a transaction, the manager reserves the next nonce locally. The first call per address fetches the on-chain nonce; subsequent calls increment from the local counter.
2. **Confirm**: After the sequencer accepts the transaction, the reserved nonce is confirmed and released from the pending set.
3. **Reject**: If the transaction fails, the nonce is rejected. If `autoResyncOnError` is enabled, the manager re-fetches the on-chain nonce before the next reservation.

This is transparent when using `account:execute()` -- the Account class handles reserve/confirm/reject internally.

### Concurrent Transactions

With the nonce manager enabled, you can safely submit multiple transactions at the same time:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableNonceManager = true,
	nonceManagerConfig = {
		maxPendingNonces = 10,
		autoResyncOnError = true,
	},
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

-- Submit two transfers concurrently.
-- NonceManager assigns nonce 0 to tx1 and nonce 1 to tx2 (or whatever the next values are).
local tx1 = ethToken:transfer("0x_RECIPIENT_1", "0x38D7EA4C68000")
local tx2 = ethToken:transfer("0x_RECIPIENT_2", "0x38D7EA4C68000")

tx1:andThen(function(result)
	print("Tx 1 submitted:", result.transactionHash)
end):catch(function(err)
	warn("Tx 1 failed:", tostring(err))
end)

tx2:andThen(function(result)
	print("Tx 2 submitted:", result.transactionHash)
end):catch(function(err)
	warn("Tx 2 failed:", tostring(err))
end)
```

### Backpressure

The nonce manager limits how many nonces can be outstanding (reserved but not yet confirmed or rejected). When `maxPendingNonces` is reached, new reservations are rejected with `NONCE_EXHAUSTED` (code 5004). This prevents runaway nonce growth if transactions are submitting faster than they're confirming:

```luau
local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableNonceManager = true,
	nonceManagerConfig = {
		maxPendingNonces = 5, -- tighter limit: only 5 in-flight transactions at once
	},
})
```

### Nonce Manager Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxPendingNonces` | `number` | 10 | Maximum outstanding nonces per address |
| `autoResyncOnError` | `boolean` | true | Re-fetch on-chain nonce after a rejection |

## Error Handling

The SDK throws structured `StarknetError` instances instead of plain strings. Every error has a `message`, a numeric `code`, and a `_type` that places it in a hierarchy.

### Error Type Hierarchy

```
StarknetError
├── RpcError          -- Network, rate limit, RPC failures
├── ValidationError   -- Invalid inputs, missing fields
├── SigningError      -- Invalid keys, crypto failures
├── AbiError          -- Encoding/decoding, unknown types
├── TransactionError  -- Reverts, fee estimation, nonce exhaustion
└── PaymasterError    -- Paymaster-specific failures
```

Use `:is()` to check where an error falls in the hierarchy. It walks up the parent chain, so an `RpcError` also `:is("StarknetError")`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local StarknetError = StarknetLuau.errors.StarknetError

-- Inside a :catch() handler:
local function handleError(err: any)
	if not StarknetError.isStarknetError(err) then
		warn("Non-SDK error:", tostring(err))
		return
	end

	if err:is("RpcError") then
		warn("Network/RPC problem:", err.message)
	elseif err:is("ValidationError") then
		warn("Bad input:", err.message)
		if err.hint then
			warn("Hint:", err.hint)
		end
	elseif err:is("TransactionError") then
		warn("Transaction failed:", err.message)
		if err.revertReason then
			warn("Revert reason:", err.revertReason)
		end
	else
		warn("Error:", tostring(err))
	end
end
```

### Matching Specific Error Codes

For precise handling, match against `ErrorCodes` constants instead of checking the type:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local ErrorCodes = StarknetLuau.errors.ErrorCodes
local StarknetError = StarknetLuau.errors.StarknetError

local function handleTransactionError(err: any)
	if not StarknetError.isStarknetError(err) then
		warn("Unknown error:", tostring(err))
		return
	end

	if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
		warn("Reverted:", err.revertReason or err.message)
	elseif err.code == ErrorCodes.TRANSACTION_REJECTED.code then
		warn("Rejected by node:", err.message)
	elseif err.code == ErrorCodes.FEE_ESTIMATION_FAILED.code then
		warn("Fee estimation failed -- call would likely revert")
	elseif err.code == ErrorCodes.RATE_LIMIT.code then
		warn("Rate limited -- slow down")
	elseif err.code == ErrorCodes.QUEUE_FULL.code then
		warn("Request queue full -- back off")
	elseif err.code == ErrorCodes.NONCE_EXHAUSTED.code then
		warn("Too many pending transactions")
	elseif err.code == ErrorCodes.NETWORK_ERROR.code then
		warn("Network connectivity issue")
	else
		warn("Error", err.code, ":", err.message)
	end
end
```

### Transient vs Permanent Errors

Use `ErrorCodes.isTransient()` to decide whether to retry. Transient errors (network failures, rate limits) may succeed on retry. Permanent errors (reverts, validation failures) will not:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local MAX_RETRIES = 3

local function executeWithRetry(calls: { any }, attempt: number?): any
	attempt = attempt or 1

	return account:execute(calls):catch(function(err)
		if not StarknetError.isStarknetError(err) then
			error(err)
		end

		-- Transient: NETWORK_ERROR, RATE_LIMIT, PAYMASTER_UNAVAILABLE
		if ErrorCodes.isTransient(err.code) and (attempt :: number) < MAX_RETRIES then
			local delay = 2 ^ (attempt :: number) -- 2s, 4s, 8s
			print("Transient error, retrying in", delay, "seconds...")
			task.wait(delay)
			return executeWithRetry(calls, (attempt :: number) + 1)
		end

		-- Permanent error or retries exhausted
		error(err)
	end)
end
```

### Error Code Ranges

| Range | Category | Examples |
|-------|----------|---------|
| 1000-1099 | Validation | Missing fields, invalid hex, bad format |
| 2000-2099 | RPC/Network | HTTP failures, rate limiting, timeouts, queue full |
| 3000-3099 | Signing/Crypto | Invalid private key, key out of range |
| 4000-4099 | ABI/Encoding | Unknown type, encode/decode mismatch, unknown enum |
| 5000-5099 | Transaction | Fee estimation failed, nonce exhausted, batch deploy |
| 6000-6099 | Outside Execution | Invalid version, invalid time bounds |
| 7000-7099 | Paymaster | Token not supported, invalid signature, policy rejected |
| 8000-8099 | KeyStore | Decrypt error, invalid secret |

## Rate Limiting

The provider includes a built-in token bucket rate limiter. The default is 450 requests per minute. Lower it if your RPC endpoint has a tighter limit:

```luau
local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	maxRequestsPerMinute = 200, -- match your endpoint's rate limit
})
```

When the token bucket is empty, requests block until a token becomes available (up to `rateLimitTimeout` seconds, default 10). If the timeout expires, the request fails with `RATE_LIMIT` (code 2002).

When the queue is enabled, batch requests consume only one rate-limit token per batch, not one per individual RPC call. This is the main benefit of combining the queue with rate limiting.

## Monitoring with Metrics

Call `provider:getMetrics()` to get a snapshot of all subsystem stats. This returns a table you can log periodically or expose through your game's admin UI:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	enableQueue = true,
	enableCache = true,
	enableNonceManager = true,
})

-- Log metrics every 60 seconds
task.spawn(function()
	while true do
		task.wait(60)
		local m = provider:getMetrics()

		-- Queue health
		print("Queue depth:", m.currentQueueDepth, "/", "requests:", m.totalRequests)
		print("Batches sent:", m.batchesSent, "items batched:", m.totalBatched)
		print("Dropped (QUEUE_FULL):", m.totalDropped)

		-- Cache effectiveness
		local totalCacheLookups = m.cacheHits + m.cacheMisses
		if totalCacheLookups > 0 then
			local hitRate = math.floor(m.cacheHits / totalCacheLookups * 100)
			print("Cache hit rate:", hitRate .. "%", "(" .. m.cacheHits .. "/" .. totalCacheLookups .. ")")
		end
		print("Cache size:", m.cacheSize, "evictions:", m.cacheEvictions)

		-- Rate limiter
		print("Rate limit tokens:", m.rateLimitTokens, "/", m.rateLimitMax)

		-- Nonce manager
		print("Nonces -- reserved:", m.nonceReserved, "confirmed:", m.nonceConfirmed, "rejected:", m.nonceRejected, "resyncs:", m.nonceResyncs)
	end
end)
```

### Metrics Reference

| Field | Source | Description |
|-------|--------|-------------|
| `totalRequests` | Queue | Total requests enqueued |
| `totalCompleted` | Queue | Requests completed successfully |
| `totalFailed` | Queue | Requests that failed |
| `totalBatched` | Queue | Requests sent as part of a batch |
| `totalDropped` | Queue | Requests rejected by backpressure |
| `currentQueueDepth` | Queue | Current number of queued requests |
| `batchesSent` | Queue | Number of batch HTTP requests sent |
| `cacheHits` | Cache | Requests served from cache |
| `cacheMisses` | Cache | Requests that went to network |
| `cacheEvictions` | Cache | Entries evicted by LRU |
| `cacheSize` | Cache | Current number of cached entries |
| `rateLimitTokens` | Rate Limiter | Available rate-limit tokens |
| `rateLimitMax` | Rate Limiter | Maximum rate-limit tokens |
| `nonceReserved` | Nonce Manager | Total nonces reserved |
| `nonceConfirmed` | Nonce Manager | Total nonces confirmed |
| `nonceRejected` | Nonce Manager | Total nonces rejected |
| `nonceResyncs` | Nonce Manager | Times nonce state was re-fetched from chain |

## Complete Production Setup

Here's a full production server script combining all the systems:

```luau
--!strict
-- ServerScriptService/GameServer.server.luau
-- Production-ready Starknet provider with all opt-in features enabled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

-- Production provider with all features enabled
local provider = RpcProvider.new({
	nodeUrl = "https://your-rpc-endpoint.example.com",
	maxRequestsPerMinute = 300,
	retryAttempts = 3,
	retryDelay = 1,

	enableQueue = true,
	queueConfig = {
		maxQueueDepth = 100,
		maxBatchSize = 20,
		enableBatching = true,
	},

	enableCache = true,
	cacheConfig = {
		maxEntries = 256,
		storageTTL = 30,
		callTTL = 30,
	},

	enableNonceManager = true,
	nonceManagerConfig = {
		maxPendingNonces = 10,
		autoResyncOnError = true,
	},
})

local serverAccount = Account.fromPrivateKey({
	privateKey = "0x_YOUR_SERVER_PRIVATE_KEY",
	provider = provider,
})

local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider, serverAccount)

local MAX_RETRIES = 3

local function sendRewardWithRetry(recipientAddress: string, amount: string, attempt: number?): any
	attempt = attempt or 1

	return strkToken
		:transfer(recipientAddress, amount)
		:catch(function(err)
			if not StarknetError.isStarknetError(err) then
				error(err)
			end

			if ErrorCodes.isTransient(err.code) and (attempt :: number) < MAX_RETRIES then
				local delay = 2 ^ (attempt :: number)
				warn("Transient error, retry", attempt, "in", delay, "s:", err.message)
				task.wait(delay)
				return sendRewardWithRetry(recipientAddress, amount, (attempt :: number) + 1)
			end

			error(err)
		end)
end

-- Example usage: reward a player
local function rewardPlayer(recipientAddress: string, amount: string)
	sendRewardWithRetry(recipientAddress, amount)
		:andThen(function(result)
			print("Reward sent:", result.transactionHash)

			-- Flush cache after our own writes so subsequent reads are fresh
			provider:flushCache()
		end)
		:catch(function(err)
			warn("Reward failed after retries:", tostring(err))
		end)
end

-- Periodic metrics logging
task.spawn(function()
	while true do
		task.wait(300) -- every 5 minutes
		local m = provider:getMetrics()
		local totalLookups = m.cacheHits + m.cacheMisses
		local hitRate = if totalLookups > 0
			then string.format("%.0f%%", m.cacheHits / totalLookups * 100)
			else "N/A"
		print(
			"[Starknet Metrics]",
			"requests:", m.totalRequests,
			"batched:", m.totalBatched,
			"cache:", hitRate,
			"dropped:", m.totalDropped,
			"nonce_resyncs:", m.nonceResyncs
		)
	end
end)

return {
	rewardPlayer = rewardPlayer,
}
```

## Deployment Checklist

Before publishing your game with blockchain features:

1. **HttpService enabled** -- Game Settings > Security > Allow HTTP Requests. Without this, all RPC calls fail silently.
2. **Published place for DataStore** -- If you use `KeyStore`, `OnboardingManager`, or `EventPoller` with DataStore persistence, the experience must be published. DataStore doesn't work in unpublished Studio sessions.
3. **Server secrets secured** -- Never hardcode private keys in scripts. Use DataStore, a server-side secrets manager, or `KeyStore` with encrypted storage (see [Guide 5: Player Onboarding](player-onboarding.md)).
4. **Rate limits matched** -- Set `maxRequestsPerMinute` to match your RPC endpoint's rate limit. The default of 450 works for many public endpoints, but paid endpoints may allow more and free endpoints may allow less.
5. **Retry config tuned** -- `retryAttempts = 3` and `retryDelay = 1` (exponential: 1s, 2s, 4s) is a good starting point. Increase for unreliable networks; decrease for latency-sensitive operations.
6. **Cache TTLs reviewed** -- The defaults work for most games. Lower TTLs if your game needs near-real-time state reads. Higher TTLs if you're hitting rate limits.
7. **`game:BindToClose` cleanup** -- If you use `EventPoller`, stop polling in `BindToClose` to ensure graceful shutdown and DataStore checkpoint saves.

## Common Mistakes

**Nonces must be confirmed or rejected.** The NonceManager's reserve-confirm-reject pattern is handled automatically by `account:execute()`. But if you're building custom transaction flows that call the nonce manager directly, you must call `confirm()` on success and `reject()` on failure. Unconfirmed nonces stay in the pending set and count toward `maxPendingNonces`, eventually triggering `NONCE_EXHAUSTED` (code 5004).

**`task.defer` batching is frame-scoped.** The queue batches all `fetch()` calls made in the same frame (Roblox heartbeat cycle). Calls separated by `task.wait()` or spread across different frames will be sent as separate batches. This is usually what you want -- just be aware that batching requires concurrent calls.

**Cache doesn't prevent write-after-write staleness.** If you submit a transaction and immediately read the affected storage, the cache may return the pre-transaction value (TTL hasn't expired yet). Call `provider:flushCache()` after submitting transactions when you need fresh reads.

**SponsoredExecutor metrics cap at 1000 players.** If you're using `SponsoredExecutor` from [Guide 6](sponsored-transactions.md), its internal per-player metrics map caps at 1000 entries. For production games with more players, use external telemetry instead of relying on `executor:getMetrics()`.

## What's Next

This guide covered the infrastructure layer. For reference-level documentation on every public function in the SDK, see Guide 10: API Reference.

If you haven't already, [Guide 9: Cryptography & Low-Level Primitives](cryptography-and-low-level-primitives.md) covers the low-level hash functions, field arithmetic, and curve operations used under the hood.
