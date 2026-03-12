# API Reference

Complete method-by-method reference for every public function in the starknet-luau SDK, organized by namespace.

## Prerequisites

- Completed [Guide 1: Getting Started](getting-started.md)

## SDK Structure

```luau
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

StarknetLuau.crypto      -- BigInt, StarkField, StarkScalarField, FieldFactory, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA
StarknetLuau.signer      -- StarkSigner
StarknetLuau.provider    -- RpcProvider, RpcTypes, EventPoller, RequestQueue, ResponseCache, NonceManager
StarknetLuau.tx          -- CallData, TransactionHash, TransactionBuilder
StarknetLuau.wallet      -- Account, TypedData, AccountType, AccountFactory, OutsideExecution, KeyStore, OnboardingManager
StarknetLuau.contract    -- Contract, AbiCodec, ERC20, ERC721, PresetFactory
StarknetLuau.paymaster   -- PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor
StarknetLuau.errors      -- StarknetError, ErrorCodes
StarknetLuau.constants   -- Chain IDs, token addresses, class hashes
```

---

## crypto.BigInt

Buffer-based arbitrary precision arithmetic. All cryptographic values (keys, hashes, field elements) are `BigInt` buffers internally.

**Type:** `BigInt = buffer`

### Constructors

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.zero()` | `BigInt` | Additive identity (0) |
| `BigInt.one()` | `BigInt` | Multiplicative identity (1) |
| `BigInt.fromNumber(n: number)` | `BigInt` | From a Luau number (safe up to 2^53) |
| `BigInt.fromHex(hex: string)` | `BigInt` | From a `"0x"`-prefixed hex string |
| `BigInt.fromBytes(bytes: buffer)` | `BigInt` | From a big-endian byte buffer |
| `BigInt.fromU256(u256: { low: string, high: string })` | `BigInt` | From a u256 pair (high * 2^128 + low) |

### Conversions

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.toHex(a)` | `string` | `"0x"`-prefixed hex, no leading zeros |
| `BigInt.toBytes(a)` | `buffer` | Big-endian bytes, minimal length |
| `BigInt.toBytesFixed(a, n: number)` | `buffer` | Big-endian bytes, exactly `n` bytes, zero-padded left |
| `BigInt.toBytes32(a)` | `buffer` | Big-endian bytes, exactly 32 bytes |
| `BigInt.toNumber(a)` | `number` | Luau number (precision loss above 2^53) |
| `BigInt.clone(a)` | `BigInt` | Deep copy |

### Comparison

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.isZero(a)` | `boolean` | True if value is zero |
| `BigInt.eq(a, b)` | `boolean` | Equality |
| `BigInt.cmp(a, b)` | `number` | Returns -1, 0, or 1 |
| `BigInt.lt(a, b)` | `boolean` | Less than |
| `BigInt.lte(a, b)` | `boolean` | Less than or equal |

### Arithmetic

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.add(a, b)` | `BigInt` | a + b (unbounded) |
| `BigInt.sub(a, b)` | `BigInt` | a - b (caller must ensure a >= b) |
| `BigInt.mul(a, b)` | `BigInt` | a * b (truncated to 264 bits) |
| `BigInt.divmod(a, b)` | `BigInt, BigInt` | Quotient and remainder |
| `BigInt.div(a, b)` | `BigInt` | Integer division |
| `BigInt.mod(a, b)` | `BigInt` | Modulus |

### Bitwise Operations

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.bitLength(a)` | `number` | Number of significant bits |
| `BigInt.getBit(a, index: number)` | `number` | Bit at index (0-based LSB), returns 0 or 1 |
| `BigInt.shl(a, bits: number)` | `BigInt` | Shift left |
| `BigInt.shr(a, bits: number)` | `BigInt` | Shift right |
| `BigInt.band(a, b)` | `BigInt` | Bitwise AND |
| `BigInt.bor(a, b)` | `BigInt` | Bitwise OR |

### Modular Arithmetic

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.addmod(a, b, m)` | `BigInt` | (a + b) mod m |
| `BigInt.submod(a, b, m)` | `BigInt` | (a - b) mod m |
| `BigInt.mulmod(a, b, m)` | `BigInt` | (a * b) mod m |
| `BigInt.powmod(a, e, m)` | `BigInt` | a^e mod m (square-and-multiply) |
| `BigInt.invmod(a, m)` | `BigInt` | Modular inverse via extended GCD |

### Barrett Reduction

Pre-computed modular arithmetic for repeated operations with the same modulus. Used internally for all field operations.

| Function | Returns | Description |
|----------|---------|-------------|
| `BigInt.createBarrettCtx(m)` | `BarrettCtx` | Pre-compute context for modulus m |
| `BigInt.mulmodB(a, b, ctx)` | `BigInt` | Barrett modular multiply |
| `BigInt.powmodB(a, e, ctx)` | `BigInt` | Barrett modular exponentiation |

**Type:** `BarrettCtx = { m: buffer, mu: buffer, k: number }`

---

## crypto.StarkField

Modular arithmetic over the Stark prime P = 2^251 + 17*2^192 + 1. Used for hash outputs, addresses, curve coordinates, and storage values.

**Type:** `Felt = buffer`

**Constant:** `StarkField.P` -- The Stark prime

| Function | Returns | Description |
|----------|---------|-------------|
| `StarkField.zero()` | `Felt` | Additive identity |
| `StarkField.one()` | `Felt` | Multiplicative identity |
| `StarkField.fromNumber(n)` | `Felt` | From number, reduced mod P |
| `StarkField.fromHex(hex)` | `Felt` | From hex string, reduced mod P |
| `StarkField.add(a, b)` | `Felt` | (a + b) mod P |
| `StarkField.sub(a, b)` | `Felt` | (a - b) mod P |
| `StarkField.mul(a, b)` | `Felt` | (a * b) mod P |
| `StarkField.square(a)` | `Felt` | a^2 mod P |
| `StarkField.neg(a)` | `Felt` | -a mod P |
| `StarkField.inv(a)` | `Felt` | a^(-1) mod P (Fermat's little theorem) |
| `StarkField.powmod(base, exp)` | `Felt` | base^exp mod P |
| `StarkField.toHex(a)` | `string` | Convert to hex |
| `StarkField.toBigInt(a)` | `BigInt` | Clone to raw BigInt |
| `StarkField.eq(a, b)` | `boolean` | Equality |
| `StarkField.isZero(a)` | `boolean` | Zero check |
| `StarkField.sqrt(a)` | `Felt?` | Square root (Tonelli-Shanks). Returns nil if not a quadratic residue. |

---

## crypto.StarkScalarField

Modular arithmetic over the curve order N. Used for private keys, ECDSA nonces, and signature components.

**Type:** `Scalar = buffer`

**Constant:** `StarkScalarField.N` -- The curve order

Same API as StarkField (except no `sqrt`), operating mod N instead of mod P:

`zero`, `one`, `fromNumber`, `fromHex`, `add`, `sub`, `mul`, `square`, `neg`, `inv`, `powmod`, `toHex`, `toBigInt`, `eq`, `isZero`

---

## crypto.FieldFactory

Factory for creating custom modular arithmetic fields.

| Function | Returns | Description |
|----------|---------|-------------|
| `FieldFactory.createField(modulus, modulusMinus2, barrettCtx, name)` | `Field` | Create a field with all arithmetic operations |

The returned `Field` has the same API as StarkField (without `sqrt`).

---

## crypto.StarkCurve

Elliptic curve operations on the Stark curve (y^2 = x^3 + x + beta).

**Types:**
- `AffinePoint = { x: Felt, y: Felt }`
- `JacobianPoint = { x: Felt, y: Felt, z: Felt }`

**Constants:** `ALPHA`, `BETA`, `G` (generator), `N` (curve order), `INFINITY`

### Point Operations

| Function | Returns | Description |
|----------|---------|-------------|
| `StarkCurve.isOnCurve(p: AffinePoint)` | `boolean` | Verify point satisfies curve equation |
| `StarkCurve.isInfinityAffine(p: AffinePoint)` | `boolean` | Check for point at infinity |
| `StarkCurve.isInfinity(p: JacobianPoint)` | `boolean` | Check Jacobian identity (z == 0) |
| `StarkCurve.affineEq(a, b: AffinePoint)` | `boolean` | Point equality |
| `StarkCurve.affineNeg(p: AffinePoint)` | `AffinePoint` | Negate (reflect across x-axis) |
| `StarkCurve.jacobianFromAffine(p: AffinePoint)` | `JacobianPoint` | Convert to Jacobian (z = 1) |
| `StarkCurve.affineFromJacobian(p: JacobianPoint)` | `AffinePoint` | Convert to affine (X/Z^2, Y/Z^3) |
| `StarkCurve.jacobianDouble(p: JacobianPoint)` | `JacobianPoint` | Point doubling |
| `StarkCurve.jacobianAdd(p1, p2: JacobianPoint)` | `JacobianPoint` | Point addition |
| `StarkCurve.scalarMul(p: AffinePoint, k: buffer)` | `AffinePoint` | k * P (4-bit windowed) |
| `StarkCurve.shamirMul(p1, k1, p2, k2)` | `AffinePoint` | k1*P1 + k2*P2 (Shamir's trick) |
| `StarkCurve.getPublicKey(privateKey: buffer)` | `AffinePoint` | privateKey * G. Validates key in [1, N-1]. |

---

## crypto.Poseidon

Poseidon hash (width-3 Hades permutation). Used for V3 transaction hashes and SNIP-12 active revision.

| Function | Returns | Description |
|----------|---------|-------------|
| `Poseidon.hash(a: Felt, b: Felt)` | `Felt` | Hash two field elements |
| `Poseidon.hashSingle(x: Felt)` | `Felt` | Hash a single element |
| `Poseidon.hashMany(values: { Felt })` | `Felt` | Sponge hash of variable-length input |

---

## crypto.Pedersen

Pedersen hash (elliptic curve point operations). Used for contract addresses and SNIP-12 legacy revision.

| Function | Returns | Description |
|----------|---------|-------------|
| `Pedersen.hash(a: Felt, b: Felt)` | `Felt` | Hash two field elements |
| `Pedersen.hashChain(elements: { Felt })` | `Felt` | Chain hash: `pedersen(pedersen(...pedersen(0, e1), e2..., en), n)` |

---

## crypto.Keccak

Ethereum-variant Keccak-256 (not SHA-3). Used for function selectors.

| Function | Returns | Description |
|----------|---------|-------------|
| `Keccak.keccak256(input: buffer)` | `buffer` | Raw 32-byte Keccak-256 hash |
| `Keccak.snKeccak(input: buffer)` | `Felt` | Starknet keccak: masked to 250 bits |
| `Keccak.getSelectorFromName(name: string)` | `Felt` | Function selector. Returns zero for `"__default__"` and `"__l1_default__"`. |

---

## crypto.SHA256

FIPS 180-4 SHA-256. Used internally by ECDSA for RFC 6979.

| Function | Returns | Description |
|----------|---------|-------------|
| `SHA256.hash(data: buffer)` | `buffer` | 32-byte SHA-256 hash |
| `SHA256.hmac(key: buffer, message: buffer)` | `buffer` | HMAC-SHA-256 |

---

## crypto.ECDSA

Stark ECDSA with RFC 6979 deterministic nonce generation.

**Type:** `Signature = { r: buffer, s: buffer }`

| Function | Returns | Description |
|----------|---------|-------------|
| `ECDSA.sign(messageHash: buffer, privateKey: buffer)` | `Signature` | Sign a hash. Validates key in [1, N-1]. |
| `ECDSA.verify(messageHash: buffer, publicKey: AffinePoint, signature: Signature)` | `boolean` | Verify a signature |
| `ECDSA.generateK(messageHash: buffer, privateKey: buffer)` | `buffer` | RFC 6979 deterministic nonce (exposed for testing) |

---

## signer.StarkSigner

High-level signing interface wrapping ECDSA. Used internally by `Account`.

### Constructor

```
StarkSigner.new(privateKeyHex: string) -> StarkSigner
```

Validates key is in [1, N-1]. Throws `KEY_OUT_OF_RANGE` (3003) otherwise.

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getPubKey()` | `AffinePoint` | Derived public key (cached after first call) |
| `:getPublicKeyHex()` | `string` | Public key x-coordinate as `"0x..."` |
| `:signRaw(msgHash: buffer)` | `Signature` | Sign, returns `{ r: buffer, s: buffer }` |
| `:signHash(hash: buffer)` | `{ string }` | Sign, returns `{ "0x<r>", "0x<s>" }` |

---

## provider.RpcProvider

JSON-RPC client for all Starknet blockchain communication. Single entry point for network access.

### Constructor

```luau
RpcProvider.new(config: RpcProviderConfig) -> RpcProvider
```

**RpcProviderConfig fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nodeUrl` | `string` | required | JSON-RPC endpoint URL |
| `headers` | `{ [string]: string }?` | `nil` | Custom HTTP headers |
| `maxRequestsPerMinute` | `number?` | `450` | Rate limiter cap |
| `rateLimitTimeout` | `number?` | `30` | Seconds to wait for rate limit token |
| `retryAttempts` | `number?` | `3` | Max retry count on transient errors |
| `retryDelay` | `number?` | `1` | Initial backoff delay in seconds |
| `enableQueue` | `boolean?` | `false` | Enable request batching queue |
| `queueConfig` | `RequestQueueConfig?` | `nil` | Queue options: `maxQueueDepth`, `maxBatchSize` |
| `enableCache` | `boolean?` | `false` | Enable response caching |
| `cacheConfig` | `CacheConfig?` | `nil` | Per-method TTL overrides |
| `enableNonceManager` | `boolean?` | `false` | Enable nonce tracking |
| `nonceManagerConfig` | `NonceManagerConfig?` | `nil` | Nonce options: `maxPendingNonces`, `autoResyncOnError` |

### Chain Query Methods

All methods return `Promise<T>`.

| Method | Returns | Description |
|--------|---------|-------------|
| `:getChainId()` | `string` | Hex-encoded chain ID |
| `:getBlockNumber()` | `number` | Latest block number |
| `:getSpecVersion()` | `string` | JSON-RPC spec version |
| `:getNonce(address, blockId?)` | `string` | Contract nonce (hex) |

### Contract Read Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:call(request: CallRequest, blockId?)` | `{ string }` | Read-only contract call |
| `:getStorageAt(address, key, blockId?)` | `string` | Storage value at key |
| `:getClassHashAt(address, blockId?)` | `string` | Class hash at address |
| `:getClass(classHash, blockId?)` | `ContractClass` | Contract class definition |
| `:getClassAt(address, blockId?)` | `ContractClass` | Contract class at address |

### Block Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getBlockWithTxHashes(blockId?)` | `Block` | Block with transaction hashes |
| `:getBlockWithTxs(blockId?)` | `BlockWithTxs` | Block with full transactions |
| `:getBlockWithReceipts(blockId?)` | `BlockWithReceipts` | Block with receipts |

### Transaction Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getTransactionByHash(txHash)` | `Transaction` | Full transaction details |
| `:getTransactionReceipt(txHash)` | `TransactionReceipt` | Transaction receipt |
| `:getTransactionStatus(txHash)` | `TransactionStatus` | Finality and execution status |
| `:estimateFee(transactions, simulationFlags?)` | `{ FeeEstimate }` | Fee estimation |
| `:estimateMessageFee(message: MessageFromL1, blockId?)` | `FeeEstimate` | L1-to-L2 message fee |
| `:addInvokeTransaction(invokeTx)` | `InvokeResult` | Submit signed invoke tx |
| `:addDeployAccountTransaction(deployTx)` | `DeployAccountResult` | Submit signed deploy account tx |
| `:waitForTransaction(txHash, options?)` | `TransactionReceipt` | Poll until confirmed/rejected |

**WaitOptions:** `{ retryInterval: number?, maxAttempts: number? }`

### Event Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getEvents(filter: EventFilter)` | `EventsChunk` | Single page of events |
| `:getAllEvents(filter: EventFilter)` | `{ EmittedEvent }` | All matching events (auto-paginated) |

### Node Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getSyncingStats()` | `any` | Sync status (`false` or `SyncingStatus` object) |

### Infrastructure Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getNodeUrl()` | `string` | Configured endpoint URL |
| `:fetch(method, params, options?)` | `Promise<any>` | Raw RPC call (for unsupported methods) |
| `:fetchSync(method, params)` | `any` | Synchronous RPC call (for use inside Promise executors) |
| `:flushCache()` | `()` | Clear all cached responses |
| `:getMetrics()` | `ProviderMetrics` | Queue + cache + rate limiter + nonce metrics |
| `:getNonceManager()` | `NonceManager?` | Nonce manager instance (nil if disabled) |
| `:getPromise()` | `any` | Promise constructor |

---

## provider.EventPoller

Continuous background polling for on-chain events with optional DataStore checkpoint persistence.

### Constructor

```luau
EventPoller.new(config: EventPollerConfig) -> EventPoller
```

**EventPollerConfig fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | `RpcProvider` | required | Provider for RPC calls |
| `filter` | `EventFilter` | required | Event filter (address, keys, block range) |
| `interval` | `number?` | `5` | Poll interval in seconds |
| `onEvents` | `(events: { EmittedEvent }) -> ()?` | `nil` | Callback for new events |
| `onError` | `(err: any) -> ()?` | `nil` | Callback for errors |
| `onCheckpoint` | `(blockNumber: number) -> ()?` | `nil` | Callback after each poll cycle |
| `_dataStore` | `DataStoreLike?` | `nil` | DataStore for checkpoint persistence |
| `checkpointKey` | `string?` | `nil` | DataStore key for checkpoint |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:start()` | `()` | Start polling (blocking loop -- use `task.spawn`) |
| `:stop()` | `()` | Stop the polling loop |
| `:isRunning()` | `boolean` | Check if currently polling |
| `:getLastBlockNumber()` | `number?` | Last polled block number |
| `:setLastBlockNumber(n: number)` | `()` | Set block number manually (for recovery) |
| `:getCheckpointKey()` | `string?` | Configured checkpoint key |

---

## provider.RequestQueue

3-bucket priority queue with backpressure for request batching. Used internally by RpcProvider when `enableQueue = true`.

### Constructor

```luau
RequestQueue.new(maxQueueDepth: number?) -> RequestQueue  -- default 100
```

### Static Methods

| Function | Returns | Description |
|----------|---------|-------------|
| `RequestQueue.getPriority(method)` | `string` | Priority level: `"high"` / `"normal"` / `"low"` |
| `RequestQueue.isBatchable(method)` | `boolean` | Whether method is safe for JSON-RPC batching |

### Instance Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:enqueue(method, params, resolve, reject)` | `()` | Add to queue. Rejects with `QUEUE_FULL` (2010) at capacity. |
| `:dequeue()` | `QueueItem?` | Pop highest-priority item |
| `:depth()` | `number` | Current queue depth |
| `:isEmpty()` | `boolean` | Empty check |
| `:peekPriority()` | `string?` | Priority of next item |
| `:getMetrics()` | `QueueMetrics` | Metrics snapshot |
| `:recordCompleted()` | `()` | Record successful completion |
| `:recordFailed()` | `()` | Record failure |
| `:recordBatched(count)` | `()` | Record items batched |
| `:recordBatchSent()` | `()` | Record batch sent |

---

## provider.ResponseCache

LRU cache with per-method TTL for JSON-RPC responses. Used internally by RpcProvider when `enableCache = true`.

### Constructor

```luau
ResponseCache.new(config: CacheConfig?, clockFn?) -> ResponseCache
```

**CacheConfig fields** (all optional):

| Field | Default | Description |
|-------|---------|-------------|
| `maxEntries` | `256` | Maximum cache entries |
| `chainIdTTL` | `0` | TTL for chainId (0 = indefinite) |
| `specVersionTTL` | `0` | TTL for specVersion |
| `blockNumberTTL` | `10` | TTL in seconds |
| `blockTTL` | `10` | TTL for block data |
| `classHashTTL` | `0` | TTL for classHash (indefinite) |
| `classTTL` | `0` | TTL for class (indefinite) |
| `storageTTL` | `30` | TTL for storage |
| `callTTL` | `30` | TTL for call |

Never cached: `addInvokeTransaction`, `estimateFee`, `getNonce`, `getTransactionReceipt`, `getTransactionStatus`, `getEvents`.

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:get(key)` | `any?` | Get cached value (nil on miss/expired) |
| `:set(key, value, ttl)` | `()` | Store with TTL in seconds (0 = indefinite) |
| `:invalidate(key)` | `()` | Remove by exact key |
| `:invalidateByPrefix(prefix)` | `()` | Remove all keys starting with prefix |
| `:flush()` | `()` | Clear all entries |
| `:getTTLForMethod(method)` | `number?` | TTL for RPC method (nil = not cacheable) |
| `:size()` | `number` | Current entry count |
| `:getMetrics()` | `CacheMetrics` | Hits, misses, evictions, size |

---

## provider.NonceManager

Reserve/confirm/reject nonce tracking for concurrent transactions. Used internally by RpcProvider when `enableNonceManager = true`.

### Constructor

```luau
NonceManager.new(provider, config?) -> NonceManager
```

**Config:** `{ maxPendingNonces: number? (default 10), autoResyncOnError: boolean? (default true) }`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:reserve(address)` | `Promise<string>` | Reserve next nonce (fetches on-chain on first call) |
| `:confirm(address, nonceHex)` | `()` | Confirm nonce was used successfully |
| `:reject(address, nonceHex)` | `()` | Reject nonce (marks dirty for re-sync) |
| `:resync(address)` | `Promise<string>` | Force re-sync from chain |
| `:reset(address?)` | `()` | Reset tracking (specific address or all) |
| `:getPendingCount(address)` | `number` | Number of reserved but unconfirmed nonces |
| `:isInitialized(address)` | `boolean` | Whether address has local tracking |
| `:isDirty(address)` | `boolean` | Whether address needs re-sync |
| `:peekNextNonce(address)` | `string?` | Next nonce without reserving (nil if uninitialized) |
| `:getMetrics()` | `NonceManagerMetrics` | reserved, confirmed, rejected, resyncs |

---

## tx.TransactionBuilder

Transaction orchestration: nonce fetch, fee estimation, hash computation, signing, and submission.

### Constructor

```luau
TransactionBuilder.new(provider) -> TransactionBuilder
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:execute(account, calls, options?)` | `Promise<{ transactionHash }>` | Full invoke flow: nonce -> estimate -> hash -> sign -> submit |
| `:estimateFee(account, calls)` | `Promise<FeeEstimate>` | Estimate fee without submitting |
| `:deployAccount(account, params, options?)` | `Promise<{ transactionHash, contractAddress }>` | Full deploy account flow |
| `:estimateDeployAccountFee(account, params)` | `Promise<FeeEstimate>` | Estimate deploy fee |
| `:waitForReceipt(txHash, options?)` | `Promise<TransactionReceipt>` | Poll until confirmed |

**ExecuteOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nonce` | `string?` | auto-fetch | Override nonce |
| `maxFee` | `string?` | `nil` | Cap l1Gas maxAmount |
| `resourceBounds` | `ResourceBounds?` | `nil` | Override fee estimation entirely |
| `feeMultiplier` | `number?` | `1.5` | Safety buffer on estimated fees |
| `dryRun` | `boolean?` | `false` | Build + sign without submitting |
| `waitForConfirmation` | `boolean?` | `false` | Poll for receipt after submission |

**DeployAccountParams:** `{ classHash, constructorCalldata, addressSalt, contractAddress }`

---

## tx.TransactionHash

Pure Poseidon-based hash computation for V3 transactions.

| Function | Returns | Description |
|----------|---------|-------------|
| `TransactionHash.calculateInvokeTransactionHash(params)` | `string` | V3 INVOKE hash |
| `TransactionHash.calculateDeployAccountTransactionHash(params)` | `string` | V3 DEPLOY_ACCOUNT hash |
| `TransactionHash.hashFeeField(tip, resourceBounds)` | `string` | Fee field Poseidon digest |
| `TransactionHash.hashDAMode(nonceDAMode, feeDAMode)` | `string` | DA mode encoding |

**ResourceBounds type:**
```luau
{ l1Gas: { maxAmount: string, maxPricePerUnit: string },
  l2Gas: { maxAmount: string, maxPricePerUnit: string },
  l1DataGas: { maxAmount: string, maxPricePerUnit: string } }
```

---

## tx.CallData

Low-level calldata encoding utilities.

**Type:** `Call = { contractAddress: string, entrypoint: string, calldata: { string } }`

| Function | Returns | Description |
|----------|---------|-------------|
| `CallData.encodeFelt(hex)` | `{ string }` | Normalize a felt value |
| `CallData.encodeBool(value)` | `{ string }` | `true` -> `"0x1"`, `false` -> `"0x0"` |
| `CallData.encodeShortString(str)` | `{ string }` | ASCII string to felt (max 31 chars) |
| `CallData.encodeU256(hex)` | `{ string }` | Split to `{ low, high }` (two 128-bit felts) |
| `CallData.encodeArray(elements)` | `{ string }` | Length-prefixed array |
| `CallData.encodeMulticall(calls: { Call })` | `{ string }` | `__execute__` multicall format |
| `CallData.validateCall(call: Call)` | `()` | Validate address and entrypoint fields |
| `CallData.numberToHex(n)` | `string` | Number to hex felt |
| `CallData.compile(rawArgs)` | `{ string }` | General-purpose encoder (hex, numbers, bools, arrays, structs) |
| `CallData.concat(...)` | `{ string }` | Concatenate encoded results |

---

## wallet.Account

Main account interface for signing and submitting transactions.

### Constructors

```luau
Account.new(config: {
    address: string,
    signer: SignerInterface,
    provider: RpcProvider,
    accountType: string?,      -- "oz" | "argent" | "braavos"
    classHash: string?,
    constructorCalldata: { string }?,
}) -> Account

Account.fromPrivateKey(config: {
    privateKey: string,
    provider: RpcProvider,
    accountType: string?,      -- default "oz"
    classHash: string?,
    guardian: string?,          -- for Argent accounts
}) -> Account
```

### Instance Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:execute(calls, options?)` | `Promise<{ transactionHash }>` | Execute calls (multicall supported) |
| `:estimateFee(calls)` | `Promise<FeeEstimate>` | Estimate fee for calls |
| `:getNonce()` | `Promise<string>` | Current on-chain nonce |
| `:waitForReceipt(txHash, options?)` | `Promise<TransactionReceipt>` | Poll for receipt |
| `:getProvider()` | `RpcProvider` | Get the provider |
| `:getPublicKeyHex()` | `string` | Public key as `"0x..."` |
| `:hashMessage(typedData)` | `string` | SNIP-12 message hash |
| `:signMessage(typedData)` | `{ string }` | Sign SNIP-12 message, returns `{ r_hex, s_hex }` |

### Deploy Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:deployAccount(options?)` | `Promise<{ transactionHash, contractAddress, alreadyDeployed? }>` | Full deploy orchestration (idempotent) |
| `:estimateDeployAccountFee()` | `Promise<FeeEstimate>` | Estimate deploy fee |
| `:getDeploymentData()` | `DeploymentData` | SNIP-29 deployment data |

### Paymaster Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:executePaymaster(calls, paymasterDetails)` | `Promise<{ transactionHash, trackingId? }>` | Gasless execution via paymaster |
| `:estimatePaymasterFee(calls, paymasterDetails)` | `Promise<{ feeEstimate, typedData }>` | Estimate paymaster fee |
| `:deployWithPaymaster(paymasterDetails, options?)` | `Promise<{ transactionHash, contractAddress, trackingId?, alreadyDeployed? }>` | Deploy via paymaster |

### Static Methods

| Function | Returns | Description |
|----------|---------|-------------|
| `Account.computeAddress(config)` | `string` | Compute counterfactual address |
| `Account.detectAccountType(classHash)` | `string?` | Detect type from class hash |
| `Account.getConstructorCalldata(accountType, publicKey, guardian?)` | `{ string }` | Build constructor calldata |
| `Account.getDeploymentFeeEstimate(config)` | `Promise<...>` | Estimate deploy fee (no signer needed) |
| `Account.checkDeploymentBalance(config)` | `Promise<...>` | Check if address has sufficient balance |
| `Account.getDeploymentFundingInfo(config)` | `Promise<...>` | All deployment info (address, fees, class hash) |

---

## wallet.AccountType

Account implementation registry.

### Pre-defined Types

| Field | Type | Class Hash | Constructor Calldata |
|-------|------|------------|---------------------|
| `AccountType.OZ` | `"oz"` | OpenZeppelin | `(publicKey) -> { publicKey }` |
| `AccountType.Argent` | `"argent"` | Argent X | `(ownerKey, guardianKey?) -> { ... }` |
| `AccountType.Braavos` | `"braavos"` | Braavos | `(publicKey) -> { publicKey }` |

### Methods

| Function | Returns | Description |
|----------|---------|-------------|
| `AccountType.get(typeName)` | `AccountTypeConfig?` | Look up by name (`"oz"`, `"argent"`, `"braavos"`) |
| `AccountType.custom(config)` | `AccountTypeConfig` | Register a custom account type |

**custom config:** `{ type: string, classHash: string, buildCalldata: (...any) -> { string } }`

---

## wallet.AccountFactory

Batch account creation and deployment for game launches.

### Constructor

```luau
AccountFactory.new(provider, accountType, signer) -> AccountFactory
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:createAccount(options?)` | `{ account, address, deployTx }` | Create pre-deployment account |
| `:batchCreate(count, options?)` | `{ { account, address, signer, deployTx } }` | Create multiple accounts |
| `:batchDeploy(accounts, options?)` | `Promise<{ deployed, failed, skipped, results }>` | Deploy accounts with progress tracking |

**batchDeploy options:** `maxConcurrency`, `onDeployProgress`, `waitForConfirmation`, `dryRun`, `maxFee`, `feeMultiplier`

---

## wallet.KeyStore

Encrypted private key persistence via Roblox DataStore.

### Constructor

```luau
KeyStore.new(config: KeyStoreConfig) -> KeyStore
```

**KeyStoreConfig:** `{ serverSecret: string, dataStoreName: string?, accountType: string?, _dataStore: DataStoreLike? }`

`serverSecret` must be a hex string of at least 32 bytes, not all zeros.

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:generateAndStore(playerId, provider)` | `{ account, address }` | Generate keypair, encrypt, store, return Account |
| `:loadAccount(playerId, provider)` | `Account?` | Load from DataStore (nil if not found) |
| `:getOrCreate(playerId, provider)` | `{ account, isNew }` | Load or generate + store |
| `:hasAccount(playerId)` | `boolean` | Check existence (no decryption) |
| `:deleteKey(playerId)` | `()` | Delete key (GDPR erasure) |
| `:rotateSecret(oldSecret, newSecret, playerIds)` | `{ rotated, failed }` | Re-encrypt keys with new secret |
| `:getRecord(playerId)` | `KeyStoreRecord?` | Read metadata without decryption |
| `:markDeployed(playerId)` | `()` | Set deployedAt timestamp |
| `:isDeployed(playerId)` | `boolean` | Check deployment status (no network) |

---

## wallet.OnboardingManager

Unified player lifecycle management: create/load keys, deploy accounts, track status.

### Constructor

```luau
OnboardingManager.new(config: OnboardingConfig) -> OnboardingManager
```

**OnboardingConfig:** `{ keyStore, provider, paymasterDetails?, waitForConfirmation?, dryRun? }`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:onboard(playerId)` | `OnboardingResult` | Full onboarding: create/load key, deploy if needed |
| `:getStatus(playerId)` | `OnboardingStatus` | Status check (no RPC, no decryption) |
| `:ensureDeployed(playerId)` | `OnboardingResult` | Deploy existing account (errors if none) |
| `:removePlayer(playerId)` | `()` | Delete player key |

**OnboardingResult:** `{ account, address, isNew, wasDeployed, alreadyDeployed, transactionHash?, trackingId? }`

**OnboardingStatus:** `{ hasAccount, isDeployed, address? }`

---

## wallet.TypedData

SNIP-12 structured message hashing for off-chain signatures.

**Constants:** `REVISION_LEGACY = "0"`, `REVISION_ACTIVE = "1"`

| Function | Returns | Description |
|----------|---------|-------------|
| `TypedData.identifyRevision(typedData)` | `string` | `"0"` (legacy/Pedersen) or `"1"` (active/Poseidon) |
| `TypedData.getMessageHash(typedData, accountAddress)` | `string` | Final hash for ECDSA signing |
| `TypedData.getStructHash(types, typeName, data, revision?)` | `string` | Hash of a single struct |
| `TypedData.getTypeHash(types, typeName, revision?)` | `string` | Hash of canonical type encoding |
| `TypedData.encodeType(types, typeName, revision?)` | `string` | Canonical type string |
| `TypedData.encodeValue(types, typeName, data, ctx?, revision?)` | `string, string` | Single value encoding |
| `TypedData.encodeData(types, typeName, data, revision?)` | `{ string }, { string }` | All fields: (typeNames, values) |
| `TypedData.getDependencies(types, typeName, deps?, contains?, revision?)` | `{ string }` | Recursive type dependencies |
| `TypedData.merkleRoot(leaves, hashPair)` | `string` | Merkle root (pairs sorted ascending) |

---

## wallet.OutsideExecution

SNIP-9 meta-transactions: player signs off-chain, relayer submits on-chain.

**Constants:**
- Versions: `VERSION_V1 = "1"`, `VERSION_V2 = "2"`, `VERSION_V3_RC = "3"`
- Entrypoints: `ENTRYPOINT_V1`, `ENTRYPOINT_V2`, `ENTRYPOINT_V3`
- `ANY_CALLER` -- allows any relayer address
- Interface IDs: `INTERFACE_ID_V1`, `INTERFACE_ID_V2`
- Type definitions: `TYPES_V1`, `TYPES_V2`, `TYPES_V3`

| Function | Returns | Description |
|----------|---------|-------------|
| `OutsideExecution.getTypedData(config)` | `TypedData` | Build SNIP-12 data for signing |
| `OutsideExecution.getEntrypoint(version)` | `string` | Entrypoint name for version |
| `OutsideExecution.getOutsideCall(call)` | `OutsideCall` | Convert named call to selector-based call |
| `OutsideExecution.validateCalls(submitted, returned)` | `boolean` | Verify call integrity |
| `OutsideExecution.buildExecuteFromOutsideCall(signerAddress, outsideExecution, signature, version)` | `Call` | Build the on-chain submission call |

**GetTypedDataConfig:** `{ chainId, caller, execute_after, execute_before, nonce, calls, version, feeMode? }`

---

## contract.Contract

ABI-driven dynamic contract interface with automatic method dispatch.

### Constructor

```luau
Contract.new(config: {
    abi: Abi,
    address: string,
    provider: RpcProvider,
    account: Account?,
}) -> Contract
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:call(method, args?, blockId?)` | `Promise<any>` | Read-only view call. Returns decoded output. |
| `:invoke(method, args?, options?)` | `Promise<{ transactionHash }>` | State-changing call (requires account) |
| `:populate(method, args?)` | `Call` | Build a Call for multicall batching |
| `:getFunctions()` | `{ string }` | Sorted list of ABI function names |
| `:getFunction(name)` | `ParsedFunction?` | Function metadata |
| `:hasFunction(name)` | `boolean` | Check if function exists |
| `:parseEvents(receipt, options?)` | `ParseEventsResult` | Decode events from a receipt |
| `:queryEvents(filter?)` | `Promise<EventsChunk>` | Query events filtered to this contract |
| `:getEvents()` | `{ string }` | Sorted list of event names |
| `:hasEvent(name)` | `boolean` | Check if event exists |

**Dynamic dispatch:** View functions are callable directly as `contract:methodName(args)` (calls `:call()`). External functions are callable directly and invoke `:invoke()`.

**ParseEventsResult:** `{ events: { ParsedEvent }, errors: { ParseEventError } }`

---

## contract.AbiCodec

Recursive Cairo ABI encoding and decoding.

| Function | Returns | Description |
|----------|---------|-------------|
| `AbiCodec.buildTypeMap(abi)` | `TypeMap` | Parse struct/enum/interface definitions from ABI JSON |
| `AbiCodec.resolveType(typeName, typeMap)` | `TypeDef` | Resolve type name (handles generics, tuples, integers) |
| `AbiCodec.encode(value, typeName, typeMap)` | `{ string }` | Encode a value to calldata felts |
| `AbiCodec.decode(results, offset, typeName, typeMap)` | `any, number` | Decode from result felts. Returns (value, feltsConsumed). |
| `AbiCodec.encodeInputs(args, inputs, typeMap)` | `{ string }` | Encode all function inputs |
| `AbiCodec.decodeOutputs(results, outputs, typeMap)` | `any` | Decode function outputs. Single output -> direct value. Multiple -> keyed table. |
| `AbiCodec.encodeEnum(value, variants, typeMap)` | `{ string }` | Encode enum (Option/Result/custom) |
| `AbiCodec.decodeEnum(results, offset, variants, typeMap)` | `any, number` | Decode enum |
| `AbiCodec.decodeEvent(keys, data, eventDef, typeMap)` | `{ [string]: any }` | Decode event fields |
| `AbiCodec.encodeByteArray(str)` | `{ string }` | String to ByteArray felts |
| `AbiCodec.decodeByteArray(results, offset)` | `string, number` | ByteArray felts to string |

### Supported Types

| Type | Luau Input | Luau Output |
|------|-----------|-------------|
| `felt252`, `ContractAddress`, `ClassHash` | `"0x..."` hex string | `"0x..."` hex string |
| `bool` | `true` / `false` | `true` / `false` |
| `u8` - `u128` | `"0x..."` or number | `"0x..."` |
| `u256` | `"0x..."` (auto-split low/high) | `{ low = "0x...", high = "0x..." }` |
| `Array<T>`, `Span<T>` | `{ val1, val2, ... }` | `{ val1, val2, ... }` |
| `Option<T>` | `nil` / `{ Some = val }` / `{ None = true }` | `{ variant = "Some"/"None", value = ... }` |
| `Result<T, E>` | `{ Ok = val }` / `{ Err = val }` | `{ variant = "Ok"/"Err", value = ... }` |
| `ByteArray` | Luau string | Luau string |
| `(T1, T2, ...)` tuples | `{ val1, val2, ... }` | `{ val1, val2, ... }` |
| Custom structs | `{ field1 = val, field2 = val }` | `{ field1 = val, field2 = val }` |
| Custom enums | `{ variant = "Name", value = data }` | `{ variant = "Name", value = data }` |

---

## contract.ERC20

Pre-built ERC-20 contract wrapper with standard ABI.

```luau
ERC20.new(address, provider, account?) -> Contract
ERC20.getAbi() -> Abi
```

**View methods:** `name`, `symbol`, `decimals`, `total_supply`, `balance_of(address)`, `allowance(owner, spender)`

**Write methods:** `transfer(recipient, amount)`, `transfer_from(sender, recipient, amount)`, `approve(spender, amount)`, `increase_allowance(spender, amount)`, `decrease_allowance(spender, amount)`

CamelCase aliases available: `totalSupply`, `balanceOf`, `transferFrom`, `increaseAllowance`, `decreaseAllowance`.

`name()` and `symbol()` auto-decode felt252 to UTF-8 strings.

---

## contract.ERC721

Pre-built ERC-721 contract wrapper with standard ABI.

```luau
ERC721.new(address, provider, account?) -> Contract
ERC721.getAbi() -> Abi
```

**View methods:** `name`, `symbol`, `balance_of(address)`, `owner_of(tokenId)`, `get_approved(tokenId)`, `is_approved_for_all(owner, operator)`, `token_uri(tokenId)`, `supports_interface(interfaceId)`

**Write methods:** `transfer_from(from, to, tokenId)`, `approve(to, tokenId)`, `set_approval_for_all(operator, approved)`, `safe_transfer_from(from, to, tokenId)`

CamelCase aliases available: `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `transferFrom`, `setApprovalForAll`, `safeTransferFrom`, `tokenURI`, `supportsInterface`.

---

## contract.PresetFactory

Factory for building reusable contract wrappers from an ABI.

```luau
PresetFactory.create(abi: Abi, shortStringMethods: { string }?) -> { new: (address, provider, account?) -> Contract, getAbi: () -> Abi }
```

`shortStringMethods` lists view methods whose felt252 results auto-decode to UTF-8 strings (e.g., `{ "name", "symbol" }`).

---

## paymaster.PaymasterRpc

SNIP-29 generic paymaster JSON-RPC client.

### Constructor

```luau
PaymasterRpc.new(config: PaymasterConfig) -> PaymasterRpc
```

**PaymasterConfig:** `{ nodeUrl, accountAddress?, dappName?, headers?, _httpRequest?, _sleep?, _clock? }`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:isAvailable()` | `Promise<boolean>` | Check service availability |
| `:getSupportedTokens()` | `Promise<{ TokenData }>` | Tokens with STRK pricing |
| `:buildTypedData(userAddress, calls, gasTokenAddress, options?)` | `Promise<BuildTypedDataResult>` | Build SNIP-12 data for sponsored tx |
| `:executeTransaction(userAddress, typedData, signature, gasTokenAddress?, options?)` | `Promise<ExecuteResult>` | Execute signed tx through paymaster |
| `:trackingIdToLatestHash(trackingId)` | `Promise<TrackingResult>` | Map tracking ID to tx hash |
| `:fetch(method, params)` | `Promise<any>` | Raw RPC call |
| `:getNodeUrl()` | `string` | Endpoint URL |
| `:resolveImmediate(value)` | `Promise<any>` | Wrap value in resolved Promise |

**BuildTypedDataOptions:** `{ accountClassHash?, accountAddress?, version?, timeBounds?, deploymentData?, feeMode? }`

---

## paymaster.AvnuPaymaster

AVNU-specific paymaster wrapper with auto-resolved endpoints and token caching.

### Constructor

```luau
AvnuPaymaster.new(config: AvnuPaymasterConfig) -> AvnuPaymaster
```

**AvnuPaymasterConfig:** `{ network, accountAddress?, dappName?, apiKey?, tokenCacheTTL?, _httpRequest?, _sleep?, _clock? }`

### Methods

Same as PaymasterRpc, plus:

| Method | Returns | Description |
|--------|---------|-------------|
| `:getNetwork()` | `string` | Configured network name |
| `:isSponsored()` | `boolean` | True if API key is set (gasfree mode) |
| `:getKnownTokens()` | `{ [string]: TokenInfo }` | Known tokens for network |
| `:getTokenAddress(symbol)` | `string?` | Token address by symbol (e.g., `"STRK"`) |
| `:clearTokenCache()` | `()` | Clear cached token list |

### Static Methods

| Function | Returns | Description |
|----------|---------|-------------|
| `AvnuPaymaster.getEndpoint(network)` | `string?` | Endpoint URL for network |
| `AvnuPaymaster.getEndpoints()` | `{ [string]: string }` | All known endpoints |
| `AvnuPaymaster.getTokensForNetwork(network)` | `{ [string]: TokenInfo }` | Known tokens for network |

---

## paymaster.PaymasterPolicy

Rule engine for sponsorship decisions: whitelists, rate limits, fee caps.

### Constructor

```luau
PaymasterPolicy.new(config: PolicyConfig) -> PaymasterPolicy
```

**PolicyConfig:**

| Field | Type | Description |
|-------|------|-------------|
| `allowedPlayers` | `{ number }?` | Player whitelist (nil = allow all) |
| `blockedPlayers` | `{ number }?` | Player blacklist |
| `allowedContracts` | `{ string }?` | Contract address whitelist |
| `allowedMethods` | `{ string }?` | Method name whitelist |
| `maxFeePerTransaction` | `string?` | Max fee (hex felt) per transaction |
| `maxTransactionsPerPlayer` | `number?` | Rate limit count |
| `rateLimitWindowSeconds` | `number?` | Rate limit window |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:validate(playerId, calls)` | `ValidationResult` | Check if calls are allowed. Does NOT record usage. |
| `:validateFee(playerId, feeAmount)` | `ValidationResult` | Check fee is within limit |
| `:recordUsage(playerId)` | `()` | Record a transaction for rate limiting |
| `:resetUsage(playerId?)` | `()` | Reset rate limit counters (nil = all players) |
| `:getUsageCount(playerId)` | `number` | Current usage in active window |

**ValidationResult:** `{ allowed: boolean, reason: string? }`

---

## paymaster.PaymasterBudget

Per-player token budget tracking with DataStore persistence.

### Constructor

```luau
PaymasterBudget.new(config: BudgetConfig?) -> PaymasterBudget
```

**BudgetConfig:** `{ defaultBalance?, costPerTransaction?, dataStore?: DataStoreLike, autoFlush?, _clock? }`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:getBalance(playerId)` | `number` | Current token balance |
| `:grantTokens(playerId, amount)` | `()` | Add tokens |
| `:revokeTokens(playerId, amount)` | `()` | Remove tokens (floor at zero) |
| `:calculateCost(gasUsed?)` | `number` | Token cost for a transaction |
| `:canAfford(playerId, txCost?)` | `boolean` | Affordability check |
| `:consumeTransaction(playerId, txCost?)` | `number` | Deduct tokens, returns actual cost |
| `:refundTransaction(playerId, txCost?)` | `()` | Refund after failure |
| `:getUsageStats(playerId)` | `PlayerData` | Balance, total tx count, total spent, last tx time |
| `:flush()` | `()` | Flush all dirty data to DataStore |
| `:flushPlayer(playerId)` | `()` | Flush single player |
| `:loadPlayer(playerId)` | `()` | Load from DataStore into cache |
| `:unloadPlayer(playerId)` | `()` | Flush + remove from cache |
| `:isCached(playerId)` | `boolean` | In-memory check |
| `:getDirtyCount()` | `number` | Entries awaiting flush |
| `:getFlushErrors()` | `{ string }` | DataStore errors from flush |
| `:clearFlushErrors()` | `()` | Clear error log |

---

## paymaster.SponsoredExecutor

Complete orchestration: policy check, budget check, paymaster build/sign/execute, budget deduct/refund.

### Constructor

```luau
SponsoredExecutor.new(config: SponsoredExecutorConfig) -> SponsoredExecutor
```

**SponsoredExecutorConfig:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `paymaster` | `PaymasterRpc` or `AvnuPaymaster` | yes | Paymaster client |
| `policy` | `PaymasterPolicy` | no | Sponsorship rules |
| `budget` | `PaymasterBudget` | no | Token budget tracking |
| `gasToken` | `string` | no | Gas token address (default STRK) |
| `callbacks` | `ExecutorCallbacks` | no | Lifecycle hooks |
| `maxRetries` | `number` | no | Retry count on transient errors |

**ExecutorCallbacks:** `{ onSubmitted?, onConfirmed?, onFailed? }`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `:execute(playerId, calls, options?)` | `Promise<SponsoredExecuteResult>` | Full sponsored execution flow |
| `:getMetrics()` | `ExecutorMetrics` | Execution metrics |
| `:resetMetrics()` | `()` | Reset all metrics |

**SponsoredExecuteResult:** `{ transactionHash, trackingId?, gasUsed? }`

**ExecutorMetrics:** `{ totalExecutions, totalSuccesses, totalFailures, totalRetries, perPlayerMetrics }`

---

## errors.StarknetError

Typed error hierarchy with factory constructors.

### Factory Constructors

| Function | Error Type | Description |
|----------|-----------|-------------|
| `StarknetError.new(message, code?, data?)` | `StarknetError` | Base error |
| `StarknetError.rpc(message, sdkCode?, rpcCode?, data?)` | `RpcError` | Network / JSON-RPC errors |
| `StarknetError.signing(message, code?, data?)` | `SigningError` | Key / ECDSA errors |
| `StarknetError.abi(message, code?, data?)` | `AbiError` | Encoding / decoding errors |
| `StarknetError.validation(message, code?, hint?, data?)` | `ValidationError` | Input validation errors |
| `StarknetError.transaction(message, code?, revertReason?, executionTrace?, data?)` | `TransactionError` | Tx execution errors |
| `StarknetError.paymaster(message, code?, data?)` | `PaymasterError` | Paymaster errors |

### Instance Method

```luau
error:is(errorType: string) -> boolean  -- Check type hierarchy: "RpcError", "StarknetError", etc.
```

### Utility

```luau
StarknetError.isStarknetError(value: any) -> boolean  -- Duck-type check
StarknetError.ErrorCodes  -- Re-exported ErrorCodes module
```

### Error Type Hierarchy

```
StarknetError
├── RpcError
├── SigningError
├── AbiError
├── ValidationError
├── TransactionError
└── PaymasterError
```

All child types satisfy `:is("StarknetError")` as well as their own type.

---

## errors.ErrorCodes

Numeric error code constants and classification helpers.

### Helpers

| Function | Returns | Description |
|----------|---------|-------------|
| `ErrorCodes.isTransient(code)` | `boolean` | True for retryable errors (network, rate limit, timeout) |
| `ErrorCodes.isNonRetryablePaymaster(code)` | `boolean` | True for deterministic paymaster failures |

### Constants

Each constant is `{ code: number, name: string }`.

**Validation (1000s):**

| Constant | Code |
|----------|------|
| `INVALID_ARGUMENT` | 1000 |
| `REQUIRED_FIELD` | 1001 |
| `INVALID_FORMAT` | 1003 |

**RPC / Network (2000s):**

| Constant | Code |
|----------|------|
| `RPC_ERROR` | 2000 |
| `NETWORK_ERROR` | 2001 |
| `RATE_LIMIT` | 2002 |
| `TIMEOUT` | 2003 |
| `TRANSACTION_REVERTED` | 2004 |
| `TRANSACTION_REJECTED` | 2005 |
| `QUEUE_FULL` | 2010 |
| `BATCH_ERROR` | 2011 |
| `NONCE_FETCH_ERROR` | 2013 |
| `NONCE_MANAGER_ERROR` | 2015 |

**Signing / Crypto (3000s):**

| Constant | Code |
|----------|------|
| `SIGNING_ERROR` | 3000 |
| `INVALID_PRIVATE_KEY` | 3001 |
| `KEY_OUT_OF_RANGE` | 3003 |
| `MATH_ERROR` | 3010 |

**ABI / Encoding (4000s):**

| Constant | Code |
|----------|------|
| `ABI_ERROR` | 4000 |
| `UNKNOWN_TYPE` | 4001 |
| `ENCODE_ERROR` | 4002 |
| `DECODE_ERROR` | 4003 |
| `UNKNOWN_ENUM_VARIANT` | 4004 |
| `FUNCTION_NOT_FOUND` | 4005 |
| `ARGUMENT_COUNT` | 4006 |

**Transaction (5000s):**

| Constant | Code |
|----------|------|
| `TRANSACTION_ERROR` | 5000 |
| `FEE_ESTIMATION_FAILED` | 5001 |
| `BATCH_DEPLOY_ERROR` | 5003 |
| `NONCE_EXHAUSTED` | 5004 |

**Outside Execution (6000s):**

| Constant | Code |
|----------|------|
| `INVALID_VERSION` | 6001 |
| `CALL_VALIDATION_FAILED` | 6002 |
| `MISSING_FEE_MODE` | 6003 |
| `INVALID_TIME_BOUNDS` | 6004 |

**Paymaster (7000s):**

| Constant | Code |
|----------|------|
| `PAYMASTER_ERROR` | 7000 |
| `PAYMASTER_UNAVAILABLE` | 7001 |
| `PAYMASTER_TOKEN_NOT_SUPPORTED` | 7002 |
| `PAYMASTER_INVALID_SIGNATURE` | 7003 |
| `PAYMASTER_MAX_AMOUNT_TOO_LOW` | 7004 |
| `PAYMASTER_INVALID_DEPLOYMENT_DATA` | 7005 |
| `PAYMASTER_EXECUTION_ERROR` | 7006 |
| `PAYMASTER_INVALID_ADDRESS` | 7007 |
| `PAYMASTER_CLASS_HASH_NOT_SUPPORTED` | 7008 |
| `PAYMASTER_CALL_VALIDATION_FAILED` | 7009 |
| `PAYMASTER_POLICY_REJECTED` | 7010 |
| `BUDGET_ERROR` | 7011 |
| `INSUFFICIENT_BUDGET` | 7012 |
| `DATASTORE_ERROR` | 7013 |
| `INVALID_AMOUNT` | 7014 |
| `SPONSORED_EXECUTION_FAILED` | 7020 |

**KeyStore / Onboarding (8000s):**

| Constant | Code |
|----------|------|
| `KEY_STORE_ERROR` | 8000 |
| `KEY_STORE_DECRYPT_ERROR` | 8001 |
| `KEY_STORE_SECRET_INVALID` | 8002 |
| `ONBOARDING_ERROR` | 8010 |

---

## constants

Flat table of string constants. No functions.

### Chain IDs

| Constant | Value | Description |
|----------|-------|-------------|
| `SN_MAIN` | `"0x534e5f4d41494e"` | Starknet Mainnet |
| `SN_SEPOLIA` | `"0x534e5f5345504f4c4941"` | Starknet Sepolia Testnet |

### Token Addresses

| Constant | Description |
|----------|-------------|
| `ETH_TOKEN_ADDRESS` | ETH ERC-20 on Starknet |
| `STRK_TOKEN_ADDRESS` | STRK ERC-20 on Starknet |

### Account Class Hashes

| Constant | Description |
|----------|-------------|
| `OZ_ACCOUNT_CLASS_HASH` | OpenZeppelin account |
| `ARGENT_ACCOUNT_CLASS_HASH` | Argent X account |
| `BRAAVOS_ACCOUNT_CLASS_HASH` | Braavos account |
| `BRAAVOS_BASE_ACCOUNT_CLASS_HASH` | Braavos base account |

### Transaction Versions

| Constant | Value |
|----------|-------|
| `INVOKE_TX_V3` | `"0x3"` |
| `DEPLOY_ACCOUNT_TX_V3` | `"0x3"` |
| `DECLARE_TX_V3` | `"0x3"` |

### Other

| Constant | Description |
|----------|-------------|
| `CONTRACT_ADDRESS_PREFIX` | ASCII `"STARKNET_CONTRACT_ADDRESS"` as hex |
| `ANY_CALLER` | SNIP-9 any-caller sentinel |
| `SDK_VERSION` | `"0.2.0"` |

---

## Common Gotchas

These pitfalls apply across multiple modules:

1. **Hex normalization**: Always normalize addresses/hashes via `BigInt.fromHex()` -> `BigInt.toHex()`. Unnormalized strings break comparisons.

2. **u256 return format**: Returns `{ low, high }` -- two 128-bit felts, not a single value.

3. **Private key range**: Must be in `[1, N-1]`. Throws `KEY_OUT_OF_RANGE` (3003) otherwise.

4. **Buffer vs hex string**: `StarkSigner:signHash()` expects a buffer (BigInt), not a hex string. Convert with `BigInt.fromHex()`.

5. **Resource bounds formats**: camelCase internally (TransactionHash), snake_case on the wire (RPC). TransactionBuilder handles conversion.

6. **Pedersen for addresses, Poseidon for transactions**: Contract address uses Pedersen. V3 transaction hashes use Poseidon.

7. **Server-only**: All network operations require HttpService, available only in server Scripts.

8. **No WebSockets**: EventPoller uses HTTP polling with configurable interval.

9. **DataStore requires published place**: KeyStore and EventPoller persistence only work in published experiences.

10. **Nonce manager confirmation**: Reserved nonces must be confirmed or rejected. Unconfirmed nonces leak.

11. **Option decoding asymmetry**: Input accepts `nil`/`{Some=v}`/`{None=true}`. Output is always `{variant="Some"/"None", value=...}`.

12. **Enum case sensitivity**: Variant names must match ABI exactly. Throws `UNKNOWN_ENUM_VARIANT` (4004).

13. **Fee multiplier**: Default 1.5x. Configurable per-transaction via `feeMultiplier`.

14. **SponsoredExecutor metrics cap**: Per-player metrics map caps at 1000 entries.

15. **SNIP-12 domain name**: `"StarkNetDomain"` (capital N) = legacy revision 0. `"StarknetDomain"` (lowercase n) = active revision 1.
