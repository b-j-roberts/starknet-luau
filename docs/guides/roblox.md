# Roblox-Specific Considerations

This guide covers the practical realities of running starknet-luau inside Roblox: HttpService constraints, rate limits, security, server-side patterns, and performance.

## Server-Side Only

All Starknet operations **must run on the server** (in `Script` objects, not `LocalScript`). This is because:

1. **HttpService** is only available server-side
2. **Private keys** must never be exposed to the client
3. **RPC calls** should be authenticated/rate-limited by the server

### Architecture Pattern

```
┌──────────────┐     RemoteEvent/      ┌──────────────┐     HttpService     ┌─────────────┐
│   Client     │ ──> RemoteFunction ──>│   Server     │ ──────────────────> │ Starknet    │
│ (LocalScript)│                       │   (Script)   │                     │ RPC Node    │
│              │ <── results ────────  │ starknet-luau│ <────────────────── │             │
└──────────────┘                       └──────────────┘                     └─────────────┘
```

### Example: Client Requests, Server Executes

```luau
-- Server Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Starknet = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local checkBalance = Instance.new("RemoteFunction")
checkBalance.Name = "CheckBalance"
checkBalance.Parent = ReplicatedStorage

local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})
local token = Starknet.contract.ERC20.new(Starknet.constants.STRK_TOKEN_ADDRESS, provider)

checkBalance.OnServerInvoke = function(player: Player, address: string): string?
    -- Validate input (never trust client data)
    if type(address) ~= "string" or #address < 10 or #address > 66 then
        return nil
    end

    -- Sanitize: ensure it looks like a hex address
    if not string.match(address, "^0x[0-9a-fA-F]+$") then
        return nil
    end

    local ok, balance = pcall(function()
        return token:balance_of(address):expect()
    end)

    if ok then
        return balance.low
    end
    return nil
end
```

## HttpService Rate Limits

Roblox imposes a **500 requests per minute** limit on HttpService. starknet-luau has built-in rate limiting to stay within this.

### Default Rate Limiting

The provider defaults to 450 requests/minute (leaving headroom for other game HTTP calls):

```luau
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://...",
    maxRequestsPerMinute = 450,  -- default
})
```

### If Your Game Makes Other HTTP Calls

Lower the limit to share bandwidth with your other services:

```luau
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://...",
    maxRequestsPerMinute = 300,  -- leave 200 req/min for analytics, etc.
})
```

### Request Queuing

For heavy workloads, enable the request queue for automatic batching and prioritization:

```luau
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://...",
    enableQueue = true,
    maxQueueDepth = 100,  -- max pending requests before rejecting
})
```

The queue:
- **Prioritizes** transaction submissions and fee estimates (HIGH) over event queries (LOW)
- **Batches** read-only RPC calls into a single HTTP request (JSON-RPC batch)
- **Rejects** with `QUEUE_FULL` error when the queue exceeds `maxQueueDepth`

### Response Caching

Enable caching to reduce redundant RPC calls:

```luau
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://...",
    enableCache = true,
    maxCacheEntries = 256,  -- LRU cache size (default)
})
```

Caching behavior by method:

| Method | TTL | Notes |
|--------|-----|-------|
| `starknet_chainId` | Indefinite | Never changes |
| `starknet_specVersion` | Indefinite | Rarely changes |
| `starknet_getClassHashAt` | Indefinite | Immutable once deployed |
| `starknet_blockNumber` | 10 seconds | Changes per block |
| `starknet_getBlockWithTxHashes` | 10 seconds | |
| `starknet_getStorageAt` | 30 seconds | |
| `starknet_call` | 30 seconds | |
| `starknet_estimateFee` | Never cached | Must be fresh |
| `starknet_addInvokeTransaction` | Never cached | Side-effecting |
| `starknet_getNonce` | Never cached | Must be current |

The cache automatically invalidates storage/call/block entries when a new block is detected.

## Security Best Practices

### Never Expose Private Keys to the Client

```luau
-- BAD: Private key in a LocalScript or shared module
local PRIVATE_KEY = "0x..." -- Client can see this!

-- GOOD: Private key only in a server Script
-- Store in a secure location and load on the server
```

### Secure Key Storage Options

**Option 1: Environment-style configuration (simplest)**

Store the private key in a `StringValue` inside `ServerStorage` (clients cannot access ServerStorage):

```luau
-- ServerStorage/StarknetConfig/PrivateKey (StringValue)
local config = game:GetService("ServerStorage"):FindFirstChild("StarknetConfig")
local privateKey = config:FindFirstChild("PrivateKey").Value
```

**Option 2: DataStoreService**

```luau
local DataStoreService = game:GetService("DataStoreService")
local configStore = DataStoreService:GetDataStore("StarknetConfig")

-- Set once via Studio command bar or separate setup script:
-- configStore:SetAsync("privateKey", "0x...")

-- Read in your server script:
local privateKey = configStore:GetAsync("privateKey")
```

**Option 3: External secrets service**

For production games, fetch keys from an external service:

```luau
local HttpService = game:GetService("HttpService")
local response = HttpService:RequestAsync({
    Url = "https://your-secrets-api.com/key",
    Headers = { Authorization = "Bearer YOUR_API_TOKEN" },
})
local privateKey = HttpService:JSONDecode(response.Body).key
```

### Input Validation

Always validate client-submitted data:

```luau
local function isValidAddress(addr: string): boolean
    if type(addr) ~= "string" then return false end
    if #addr < 3 or #addr > 66 then return false end
    if not string.match(addr, "^0x[0-9a-fA-F]+$") then return false end
    return true
end

remoteFunction.OnServerInvoke = function(player, address)
    if not isValidAddress(address) then
        return nil
    end
    -- Process...
end
```

### Rate Limit Client Requests

Prevent clients from flooding your server with RPC requests:

```luau
local requestTimes: { [number]: { number } } = {}
local MAX_REQUESTS_PER_PLAYER = 10
local WINDOW = 60  -- seconds

local function isRateLimited(player: Player): boolean
    local times = requestTimes[player.UserId] or {}
    local now = os.clock()

    -- Remove old entries
    local recent = {}
    for _, t in times do
        if now - t < WINDOW then
            table.insert(recent, t)
        end
    end
    requestTimes[player.UserId] = recent

    if #recent >= MAX_REQUESTS_PER_PLAYER then
        return true
    end

    table.insert(recent, now)
    return false
end
```

## Performance Considerations

### Crypto Operations

All cryptographic operations (hashing, signing, key derivation) are **synchronous** and CPU-bound. They use `--!native` and `--!optimize 2` for JIT compilation.

Typical performance on a Roblox server:

| Operation | Approximate Time |
|-----------|-----------------|
| Poseidon hash (2 felts) | < 1 ms |
| Pedersen hash (2 felts) | ~5-10 ms |
| ECDSA sign | ~20-50 ms |
| ECDSA verify | ~20-50 ms |
| Address derivation | ~15-30 ms |

> These numbers vary by server hardware. Pedersen and ECDSA are the most expensive operations because they involve multiple scalar multiplications on the elliptic curve.

### Avoid Blocking the Main Thread

For operations that might take a while (signing, multiple Pedersen hashes), consider running them in a coroutine:

```luau
task.spawn(function()
    local signature = signer:signRaw(messageHash)
    -- Continue with the signed result
end)
```

### Minimize RPC Calls

Each RPC call is an HTTP request. Minimize them by:

1. **Enabling caching** -- Repeated reads are served from cache
2. **Using multicall** -- Batch multiple writes into one transaction
3. **Caching locally** -- Store results in Luau tables for the session
4. **Using the request queue** -- Batches multiple reads into one HTTP request

### Memory

The crypto modules use `buffer` objects for field arithmetic. Each BigInt is ~88 bytes (11 limbs x 8 bytes). This is efficient, but be aware of memory if you're creating thousands of BigInt values in a tight loop. Let them be garbage-collected by not holding references.

## Promise Patterns for Roblox

### Fire-and-Forget

When you don't need to wait for the result:

```luau
provider:getBlockNumber():andThen(function(blockNumber)
    print("Block:", blockNumber)
end):catch(function(err)
    warn("Error:", tostring(err))
end)
-- Script continues immediately
```

### Blocking Wait

When you need the result before continuing (use sparingly -- blocks the thread):

```luau
local blockNumber = provider:getBlockNumber():expect()
print("Block:", blockNumber)
```

### Chaining Operations

```luau
account:execute(calls)
    :andThen(function(result)
        return account:waitForReceipt(result.transactionHash)
    end)
    :andThen(function(receipt)
        return token:balance_of(account.address)
    end)
    :andThen(function(balance)
        print("New balance:", balance.low)
    end)
    :catch(function(err)
        warn("Error in chain:", tostring(err))
    end)
```

### Parallel Operations

```luau
local Promise = require(path.to.Promise)

-- Run multiple reads in parallel
Promise.all({
    token:balance_of("0xAddress1"),
    token:balance_of("0xAddress2"),
    provider:getBlockNumber(),
}):andThen(function(results)
    print("Balance 1:", results[1].low)
    print("Balance 2:", results[2].low)
    print("Block:", results[3])
end)
```

### Timeout

```luau
-- Timeout after 30 seconds
provider:getBlockNumber():timeout(30):andThen(function(blockNumber)
    print("Block:", blockNumber)
end):catch(function(err)
    warn("Timed out or failed:", tostring(err))
end)
```

## Error Handling in Roblox

Use the structured error system for clear error messages:

```luau
local StarknetError = Starknet.errors.StarknetError

account:execute(calls)
    :catch(function(err)
        if StarknetError.isStarknetError(err) then
            if err:is("RpcError") then
                -- Network/RPC issue -- maybe retry later
                warn("RPC error:", err.message)
            elseif err:is("TransactionError") then
                -- Transaction was submitted but reverted
                warn("Reverted:", err.revertReason)
            elseif err:is("SigningError") then
                -- Key/signature issue
                warn("Signing failed:", err.message)
            elseif err:is("ValidationError") then
                -- Bad input
                warn("Invalid input:", err.message)
            end
        else
            -- Unknown error
            warn("Unexpected error:", tostring(err))
        end
    end)
```

## Deployment Checklist

Before publishing your game:

- [ ] HttpService is enabled in Game Settings > Security
- [ ] Private keys are stored securely (not in client-accessible locations)
- [ ] Client input is validated on the server
- [ ] Per-player rate limiting is implemented
- [ ] HttpService rate limit is configured (leaving headroom for other HTTP calls)
- [ ] Response caching is enabled for read-heavy workloads
- [ ] Error handling covers network failures gracefully
- [ ] RPC endpoint is reliable (consider a paid provider for production)

## Next Steps

- [Getting Started](getting-started.md) -- Basic installation and setup
- [Common Patterns](patterns.md) -- Game integration patterns
- [API Reference](api-reference.md) -- Complete API documentation
