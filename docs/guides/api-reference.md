# API Reference

Complete API documentation for all starknet-luau modules.

## Table of Contents

- [crypto.BigInt](#bigint)
- [crypto.StarkField](#starkfield)
- [crypto.StarkScalarField](#starkscalarfield)
- [crypto.StarkCurve](#starkcurve)
- [crypto.Poseidon](#poseidon)
- [crypto.Pedersen](#pedersen)
- [crypto.Keccak](#keccak)
- [crypto.SHA256](#sha256)
- [crypto.ECDSA](#ecdsa)
- [signer.StarkSigner](#starksigner)
- [provider.RpcProvider](#rpcprovider)
- [provider.RequestQueue](#requestqueue)
- [provider.ResponseCache](#responsecache)
- [provider.NonceManager](#noncemanager)
- [provider.EventPoller](#eventpoller)
- [tx.TransactionBuilder](#transactionbuilder)
- [tx.TransactionHash](#transactionhash)
- [tx.CallData](#calldata)
- [wallet.Account](#account)
- [wallet.TypedData](#typeddata)
- [contract.Contract](#contract)
- [contract.AbiCodec](#abicodec)
- [contract.ERC20](#erc20)
- [contract.ERC721](#erc721)
- [errors.StarknetError](#starkneterror)
- [errors.ErrorCodes](#errorcodes)
- [constants](#constants)

---

## BigInt

Arbitrary-precision integer arithmetic using buffer-backed f64 limb arrays.

**Type:** `BigInt = buffer` (11 limbs x 24 bits = 264 bits)

### Constructors

```luau
BigInt.zero() -> BigInt
BigInt.one() -> BigInt
BigInt.fromNumber(n: number) -> BigInt
BigInt.fromHex(hex: string) -> BigInt
BigInt.fromBytes(bytes: buffer) -> BigInt
BigInt.clone(a: BigInt) -> BigInt
```

| Method | Description |
|--------|-------------|
| `zero()` | Returns the additive identity (0) |
| `one()` | Returns the multiplicative identity (1) |
| `fromNumber(n)` | Creates BigInt from a Lua number. Only safe for values < 2^53 |
| `fromHex(hex)` | Creates BigInt from a hex string (with or without "0x" prefix) |
| `fromBytes(bytes)` | Creates BigInt from a 32-byte big-endian buffer |
| `clone(a)` | Returns a copy of the BigInt |

### Conversions

```luau
BigInt.toHex(a: BigInt) -> string
BigInt.toBytes(a: BigInt) -> buffer
BigInt.toNumber(a: BigInt) -> number
```

| Method | Description |
|--------|-------------|
| `toHex(a)` | Returns hex string with "0x" prefix, minimal length |
| `toBytes(a)` | Returns 32-byte big-endian buffer |
| `toNumber(a)` | Returns Lua number. Only safe for values < 2^53 |

### Comparison

```luau
BigInt.isZero(a: BigInt) -> boolean
BigInt.eq(a: BigInt, b: BigInt) -> boolean
BigInt.cmp(a: BigInt, b: BigInt) -> number
BigInt.lt(a: BigInt, b: BigInt) -> boolean
BigInt.lte(a: BigInt, b: BigInt) -> boolean
```

| Method | Description |
|--------|-------------|
| `isZero(a)` | Returns true if `a == 0` |
| `eq(a, b)` | Returns true if `a == b` |
| `cmp(a, b)` | Returns -1 if `a < b`, 0 if `a == b`, 1 if `a > b` |
| `lt(a, b)` | Returns true if `a < b` |
| `lte(a, b)` | Returns true if `a <= b` |

### Arithmetic

```luau
BigInt.add(a: BigInt, b: BigInt) -> BigInt
BigInt.sub(a: BigInt, b: BigInt) -> BigInt
BigInt.mul(a: BigInt, b: BigInt) -> BigInt
BigInt.div(a: BigInt, b: BigInt) -> BigInt
BigInt.mod(a: BigInt, b: BigInt) -> BigInt
BigInt.divmod(a: BigInt, b: BigInt) -> (BigInt, BigInt)
```

### Bitwise

```luau
BigInt.bitLength(a: BigInt) -> number
BigInt.getBit(a: BigInt, index: number) -> number
BigInt.shl(a: BigInt, bits: number) -> BigInt
BigInt.shr(a: BigInt, bits: number) -> BigInt
BigInt.band(a: BigInt, b: BigInt) -> BigInt
BigInt.bor(a: BigInt, b: BigInt) -> BigInt
```

| Method | Description |
|--------|-------------|
| `bitLength(a)` | Number of significant bits |
| `getBit(a, index)` | Returns bit at position `index` (0-indexed from LSB). Returns 0 or 1 |
| `shl(a, bits)` | Left shift by `bits` positions |
| `shr(a, bits)` | Right shift by `bits` positions |
| `band(a, b)` | Bitwise AND |
| `bor(a, b)` | Bitwise OR |

### Modular Arithmetic

```luau
BigInt.addmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.submod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.mulmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.powmod(a: BigInt, e: BigInt, m: BigInt) -> BigInt
BigInt.invmod(a: BigInt, m: BigInt) -> BigInt
```

| Method | Description |
|--------|-------------|
| `addmod(a, b, m)` | `(a + b) mod m` |
| `submod(a, b, m)` | `(a - b) mod m` |
| `mulmod(a, b, m)` | `(a * b) mod m` |
| `powmod(a, e, m)` | `a^e mod m` (square-and-multiply) |
| `invmod(a, m)` | `a^(-1) mod m` (modular inverse via extended Euclidean algorithm) |

### Barrett Reduction

```luau
BigInt.createBarrettCtx(m: BigInt) -> BarrettCtx
BigInt.mulmodB(a: BigInt, b: BigInt, ctx: BarrettCtx) -> BigInt
```

Pre-computed Barrett context for faster modular multiplication when using the same modulus repeatedly.

---

## StarkField

Modular arithmetic over the Stark prime `P = 2^251 + 17 * 2^192 + 1`.

**Type:** `Felt = buffer`

### Constants

```luau
StarkField.P: BigInt   -- The Stark prime
```

### Constructors

```luau
StarkField.zero() -> Felt
StarkField.one() -> Felt
StarkField.fromNumber(n: number) -> Felt
StarkField.fromHex(hex: string) -> Felt
```

All values are automatically reduced mod P.

### Arithmetic

```luau
StarkField.add(a: Felt, b: Felt) -> Felt      -- (a + b) mod P
StarkField.sub(a: Felt, b: Felt) -> Felt      -- (a - b) mod P
StarkField.mul(a: Felt, b: Felt) -> Felt      -- (a * b) mod P
StarkField.square(a: Felt) -> Felt            -- a^2 mod P
StarkField.neg(a: Felt) -> Felt               -- P - a
StarkField.inv(a: Felt) -> Felt               -- a^(P-2) mod P (Fermat)
StarkField.sqrt(a: Felt) -> Felt?             -- Square root (Tonelli-Shanks), nil if none
```

### Conversions

```luau
StarkField.toHex(a: Felt) -> string
StarkField.toBigInt(a: Felt) -> BigInt
StarkField.eq(a: Felt, b: Felt) -> boolean
StarkField.isZero(a: Felt) -> boolean
```

---

## StarkScalarField

Arithmetic modulo the curve order `N`. Same API as StarkField but with modulus N.

```luau
StarkScalarField.N: BigInt   -- The curve order
```

Provides: `fromHex`, `fromNumber`, `zero`, `one`, `add`, `sub`, `mul`, `square`, `neg`, `inv`, `toHex`, `toBigInt`, `eq`, `isZero`.

---

## StarkCurve

Elliptic curve operations on `y^2 = x^3 + x + beta`.

### Types

```luau
type AffinePoint = { x: Felt, y: Felt }
type JacobianPoint = { x: Felt, y: Felt, z: Felt }
```

### Constants

```luau
StarkCurve.ALPHA: Felt        -- 1
StarkCurve.BETA: Felt         -- 0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89
StarkCurve.G: AffinePoint     -- Generator point
StarkCurve.N: BigInt          -- Curve order
```

### Methods

```luau
StarkCurve.isInfinity(p: JacobianPoint) -> boolean
StarkCurve.isOnCurve(p: AffinePoint) -> boolean
StarkCurve.affineEq(a: AffinePoint, b: AffinePoint) -> boolean
StarkCurve.affineNeg(p: AffinePoint) -> AffinePoint

StarkCurve.jacobianFromAffine(p: AffinePoint) -> JacobianPoint
StarkCurve.affineFromJacobian(p: JacobianPoint) -> AffinePoint?

StarkCurve.jacobianDouble(p: JacobianPoint) -> JacobianPoint
StarkCurve.jacobianAdd(p1: JacobianPoint, p2: JacobianPoint) -> JacobianPoint
StarkCurve.scalarMul(p: AffinePoint, k: buffer) -> AffinePoint?

StarkCurve.getPublicKey(privateKey: buffer) -> AffinePoint
```

| Method | Description |
|--------|-------------|
| `scalarMul(p, k)` | Compute `k * P` using double-and-add. Returns nil for point at infinity |
| `getPublicKey(privateKey)` | Compute `privateKey * G` (generator multiplication) |

---

## Poseidon

Poseidon hash over the Stark field (Hades permutation, width=3, rate=2).

```luau
Poseidon.hash(a: Felt, b: Felt) -> Felt
Poseidon.hashSingle(x: Felt) -> Felt
Poseidon.hashMany(values: { Felt }) -> Felt
```

| Method | Description |
|--------|-------------|
| `hash(a, b)` | Hash two field elements |
| `hashSingle(x)` | Hash a single element: `hash(x, 0, 1)` |
| `hashMany(values)` | Sponge construction for variable-length input |

---

## Pedersen

Pedersen hash using EC point operations (4 pre-computed base points).

```luau
Pedersen.hash(a: Felt, b: Felt) -> Felt
```

---

## Keccak

Keccak-256 implementation (Ethereum variant, domain byte `0x01`).

```luau
Keccak.keccak256(input: buffer) -> buffer
Keccak.snKeccak(input: buffer) -> Felt
Keccak.getSelectorFromName(name: string) -> Felt
Keccak.bufferToHex(buf: buffer) -> string
```

| Method | Description |
|--------|-------------|
| `keccak256(input)` | Raw Keccak-256 hash, returns 32-byte buffer |
| `snKeccak(input)` | Starknet keccak: result masked to 250 bits, returns Felt |
| `getSelectorFromName(name)` | Compute function selector: `snKeccak(UTF-8 bytes of name)` |
| `bufferToHex(buf)` | Debug utility: buffer to hex string |

---

## SHA256

SHA-256 hash and HMAC-SHA-256.

```luau
SHA256.hash(data: buffer) -> buffer
SHA256.hmac(key: buffer, message: buffer) -> buffer
SHA256.bufferToHex(buf: buffer) -> string
```

---

## ECDSA

Stark ECDSA signing with RFC 6979 deterministic nonce generation.

### Types

```luau
type Signature = { r: buffer, s: buffer }
```

### Methods

```luau
ECDSA.generateK(messageHash: buffer, privateKey: buffer) -> buffer
ECDSA.sign(messageHash: buffer, privateKey: buffer) -> Signature
ECDSA.verify(messageHash: buffer, publicKey: AffinePoint, signature: Signature) -> boolean
```

| Method | Description |
|--------|-------------|
| `generateK(messageHash, privateKey)` | RFC 6979 deterministic nonce. Uses Starknet-specific `bits2int` |
| `sign(messageHash, privateKey)` | Sign a message hash. Returns `{ r, s }` as buffers |
| `verify(messageHash, publicKey, signature)` | Verify a signature against a public key |

---

## StarkSigner

Default Stark curve ECDSA signer implementation.

### Constructor

```luau
StarkSigner.new(privateKeyHex: string) -> StarkSigner
```

Validates that the private key is in range `(0, N)`.

### Methods

```luau
signer:getPubKey() -> AffinePoint
signer:getPublicKeyHex() -> string
signer:signRaw(msgHash: buffer) -> Signature
signer:signTransaction(txHash: buffer) -> { string }
```

| Method | Description |
|--------|-------------|
| `:getPubKey()` | Returns the public key as an affine point `{ x, y }`. Lazy-cached |
| `:getPublicKeyHex()` | Returns the public key X coordinate as a hex string |
| `:signRaw(msgHash)` | Sign a raw message hash buffer. Returns `{ r: buffer, s: buffer }` |
| `:signTransaction(txHash)` | Sign a transaction hash. Returns `{ r_hex, s_hex }` as hex strings |

---

## RpcProvider

JSON-RPC client for Starknet nodes.

### Constructor

```luau
RpcProvider.new(config: RpcProviderConfig) -> RpcProvider
```

**RpcProviderConfig:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nodeUrl` | `string` | required | RPC endpoint URL |
| `headers` | `{ [string]: string }?` | `{}` | Custom HTTP headers (e.g., API key) |
| `retryAttempts` | `number?` | `3` | Max retry attempts on failure |
| `retryDelay` | `number?` | `1` | Seconds between retries (exponential backoff) |
| `maxRequestsPerMinute` | `number?` | `450` | Token bucket rate limit |
| `enableQueue` | `boolean?` | `false` | Enable request queuing and batching |
| `queueConfig` | `table?` | | Queue configuration (see RequestQueue) |
| `enableCache` | `boolean?` | `false` | Enable response caching |
| `cacheConfig` | `table?` | | Cache configuration (see ResponseCache) |
| `enableNonceManager` | `boolean?` | `false` | Enable local nonce tracking |
| `nonceManagerConfig` | `table?` | | Nonce manager config (see NonceManager) |

### Network Methods

```luau
provider:getChainId() -> Promise<string>
provider:getBlockNumber() -> Promise<number>
provider:getSpecVersion() -> Promise<string>
provider:getSyncingStats() -> Promise<any>
```

### Account Methods

```luau
provider:getNonce(contractAddress: string, blockId: string?) -> Promise<string>
```

### Transaction Methods

```luau
provider:call(request: CallRequest, blockId: string?) -> Promise<{ string }>
provider:estimateFee(transactions: { InvokeTransactionV3 }, simulationFlags: { string }?) -> Promise<{ FeeEstimate }>
provider:addInvokeTransaction(invokeTx: InvokeTransactionV3) -> Promise<string>
provider:getTransactionReceipt(txHash: string) -> Promise<TransactionReceipt>
provider:getTransactionStatus(txHash: string) -> Promise<TransactionStatus>
provider:getTransactionByHash(txHash: string) -> Promise<Transaction>
provider:estimateMessageFee(message: MessageFromL1, blockId: string?) -> Promise<FeeEstimate>
```

### Block Methods

```luau
provider:getBlockWithTxHashes(blockId: string?) -> Promise<Block>
provider:getBlockWithTxs(blockId: string?) -> Promise<BlockWithTxs>
provider:getBlockWithReceipts(blockId: string?) -> Promise<BlockWithReceipts>
```

### Contract Methods

```luau
provider:getClassHashAt(contractAddress: string, blockId: string?) -> Promise<string>
provider:getStorageAt(contractAddress: string, key: string, blockId: string?) -> Promise<string>
provider:getClass(classHash: string, blockId: string?) -> Promise<ContractClass>
provider:getClassAt(contractAddress: string, blockId: string?) -> Promise<ContractClass>
```

### Event Methods

```luau
provider:getEvents(filter: EventFilter) -> Promise<EventsChunk>
provider:getAllEvents(filter: EventFilter) -> Promise<{ EmittedEvent }>
```

### Utility Methods

```luau
provider:waitForTransaction(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
provider:fetch(method: string, params: any, options: FetchOptions?) -> Promise<any>
provider:getNodeUrl() -> string
provider:getMetrics() -> ProviderMetrics
provider:flushCache() -> ()
```

### RPC Types

**CallRequest:**
```luau
{
    contract_address: string,
    entry_point_selector: string,
    calldata: { string },
}
```

**FeeEstimate:**
```luau
{
    gas_consumed: string,
    gas_price: string,
    overall_fee: string,
    data_gas_consumed: string,
    data_gas_price: string,
    unit: string,
}
```

**TransactionReceipt:**
```luau
{
    transaction_hash: string,
    actual_fee: { amount: string, unit: string },
    execution_status: string,   -- "SUCCEEDED" | "REVERTED"
    finality_status: string,    -- "ACCEPTED_ON_L2" | "ACCEPTED_ON_L1"
    block_hash: string?,
    block_number: number?,
    events: { Event },
    revert_reason: string?,
}
```

**EventFilter:**
```luau
{
    from_block: string?,
    to_block: string?,
    address: string?,
    keys: { { string } }?,
    chunk_size: number?,
    continuation_token: string?,
}
```

**WaitOptions:**
```luau
{
    retryInterval: number?,   -- seconds (default: 5)
    maxAttempts: number?,     -- (default: 30)
}
```

**FetchOptions:**
```luau
{
    bypassCache: boolean?,    -- skip cache lookup and storage
    priority: string?,        -- "high" | "normal" | "low"
}
```

---

## RequestQueue

Priority queue with JSON-RPC batching for the provider. Enabled via `enableQueue: true`.

### Priority Levels

| Priority | Methods |
|----------|---------|
| HIGH | `addInvokeTransaction`, `estimateFee` |
| NORMAL | All other RPC methods |
| LOW | `getEvents` |

### Batching

Read-only methods (chainId, blockNumber, getNonce, call, getStorageAt, etc.) are automatically batched into a single HTTP request when queued in the same frame.

### Static Methods

```luau
RequestQueue.getPriority(method: string) -> string
RequestQueue.isBatchable(method: string) -> boolean
```

### Instance Methods

```luau
queue:enqueue(method: string, params: any, resolve: fn, reject: fn)
queue:depth() -> number
queue:isEmpty() -> boolean
queue:getMetrics() -> QueueMetrics
```

**QueueMetrics:**
```luau
{
    totalRequests: number,
    totalCompleted: number,
    totalFailed: number,
    totalBatched: number,
    totalDropped: number,
    currentQueueDepth: number,
    batchesSent: number,
}
```

---

## ResponseCache

LRU cache with per-method TTL. Enabled via `enableCache: true`.

### Default TTLs

| Method | TTL | Notes |
|--------|-----|-------|
| `starknet_chainId` | 0 (indefinite) | Never changes |
| `starknet_specVersion` | 0 (indefinite) | Rarely changes |
| `starknet_getClassHashAt` | 0 (indefinite) | Immutable |
| `starknet_getClass` | 0 (indefinite) | Immutable |
| `starknet_blockNumber` | 10s | Changes per block |
| `starknet_getBlockWithTxHashes` | 10s | |
| `starknet_getStorageAt` | 30s | |
| `starknet_call` | 30s | |

Never cached: `addInvokeTransaction`, `estimateFee`, `getNonce`, `getTransactionReceipt`, `getTransactionStatus`, `getEvents`.

### Instance Methods

```luau
cache:get(key: string) -> any?
cache:set(key: string, value: any, ttl: number)
cache:invalidate(key: string)
cache:invalidateByPrefix(prefix: string)
cache:flush()
cache:getTTLForMethod(method: string) -> number?
cache:getMetrics() -> CacheMetrics
cache:size() -> number
```

**CacheMetrics:**
```luau
{
    cacheHits: number,
    cacheMisses: number,
    cacheEvictions: number,
    cacheSize: number,
}
```

---

## NonceManager

Per-address local nonce tracking with parallel reservation. Enabled via `enableNonceManager: true`.

### Constructor

```luau
NonceManager.new(provider: RpcProvider, config: {
    maxPendingNonces: number?,     -- default 10
    autoResyncOnError: boolean?,   -- default true
}?) -> NonceManager
```

### Methods

```luau
manager:reserve(address: string) -> Promise<string>
manager:confirm(address: string, nonceHex: string)
manager:reject(address: string, nonceHex: string)
manager:resync(address: string) -> Promise<string>
manager:getMetrics() -> NonceManagerMetrics
```

| Method | Description |
|--------|-------------|
| `:reserve(address)` | Reserve the next nonce. First call fetches from chain. Returns hex string |
| `:confirm(address, nonce)` | Mark a nonce as successfully used |
| `:reject(address, nonce)` | Mark a nonce as failed. Triggers dirty flag if `autoResyncOnError` |
| `:resync(address)` | Force re-fetch from chain, clear all pending |
| `:getMetrics()` | Returns `{ totalReserved, totalConfirmed, totalRejected, totalResyncs }` |

---

## EventPoller

Continuous event polling with configurable interval.

### Constructor

```luau
EventPoller.new(config: {
    provider: RpcProvider,
    filter: EventFilter,
    interval: number?,                    -- seconds (default: 10)
    onEvents: (events: { Event }) -> (),
    onError: ((err: any) -> ())?,
}) -> EventPoller
```

### Methods

```luau
poller:start()
poller:stop()
poller:isRunning() -> boolean
```

---

## TransactionBuilder

High-level transaction building, signing, and submission.

### Constructor

```luau
TransactionBuilder.new(provider: RpcProvider) -> TransactionBuilder
```

### Methods

```luau
builder:estimateFee(account: Account, calls: { Call }) -> Promise<FeeEstimate>
builder:execute(account: Account, calls: { Call }, options: ExecuteOptions?) -> Promise<ExecuteResult>
builder:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
```

**Call:**
```luau
{
    to: string,              -- contract address
    functionName: string,    -- entry point name
    inputs: { string },      -- encoded calldata
}
```

**ExecuteOptions:**
```luau
{
    nonce: string?,                        -- override nonce
    resourceBounds: ResourceBounds?,       -- override fee bounds
    feeMultiplier: number?,                -- fee safety margin (default: 1.5)
    tip: string?,
    paymasterData: { string }?,
    accountDeploymentData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
    dryRun: boolean?,                      -- build + sign without submitting
    skipValidate: boolean?,
}
```

**ExecuteResult:**
```luau
{
    transactionHash: string,
}
```

---

## TransactionHash

Computes V3 INVOKE transaction hashes using Poseidon.

```luau
TransactionHash.computeInvokeV3Hash(params: {
    senderAddress: string,
    calldata: { string },
    chainId: string,
    nonce: string,
    resourceBounds: ResourceBounds,
    tip: string?,
    paymasterData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
    accountDeploymentData: { string }?,
}) -> Felt
```

**ResourceBounds:**
```luau
{
    l1Gas: { maxAmount: string, maxPricePerUnit: string },
    l2Gas: { maxAmount: string, maxPricePerUnit: string },
    l1DataGas: { maxAmount: string, maxPricePerUnit: string }?,
}
```

---

## CallData

Calldata encoding for Starknet transactions.

```luau
CallData.encodeFelt(value: string | number) -> { string }
CallData.encodeU256(value: string) -> { string }
CallData.encodeBool(value: boolean) -> { string }
CallData.encodeArray(values: { string }) -> { string }
CallData.encodeMulticall(calls: { Call }) -> { string }
```

---

## Account

Starknet account with signing capabilities.

### Constants

```luau
Account.ACCOUNT_TYPE_OZ = "oz"
Account.ACCOUNT_TYPE_ARGENT = "argent"
Account.ACCOUNT_TYPE_BRAAVOS = "braavos"
Account.OZ_CLASS_HASH: string
Account.ARGENT_CLASS_HASH: string
Account.BRAAVOS_CLASS_HASH: string
Account.BRAAVOS_BASE_CLASS_HASH: string
```

### Constructors

```luau
Account.new(config: {
    address: string,
    signer: StarkSigner,
    provider: RpcProvider,
}) -> Account

Account.fromPrivateKey(config: {
    privateKey: string,
    provider: RpcProvider,
    accountType: string?,     -- "oz" (default), "argent", "braavos"
    classHash: string?,       -- custom class hash (overrides accountType)
    guardian: string?,         -- guardian key for Argent/Braavos
}) -> Account
```

### Static Methods

```luau
Account.computeAddress(config: {
    publicKey: string,
    classHash: string?,               -- defaults to OZ
    constructorCalldata: { string }?,
    salt: string?,                    -- defaults to public key
    deployer: string?,                -- defaults to "0x0"
}) -> string

Account.detectAccountType(classHash: string) -> string?
Account.getConstructorCalldata(accountType: string, publicKey: string, guardian: string?) -> { string }
```

### Instance Properties

```luau
account.address: string
account.signer: StarkSigner
account.provider: RpcProvider
```

### Instance Methods

```luau
account:getPublicKeyHex() -> string
account:getNonce() -> Promise<string>
account:execute(calls: { Call }, options: ExecuteOptions?) -> Promise<ExecuteResult>
account:estimateFee(calls: { Call }) -> Promise<FeeEstimate>
account:waitForTransaction(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
account:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
account:hashMessage(typedData: TypedDataInput) -> string
account:signMessage(typedData: TypedDataInput) -> { r_hex: string, s_hex: string }
```

---

## TypedData

SNIP-12 typed data hashing and encoding (similar to EIP-712).

### Types

```luau
type TypedDataInput = {
    types: { [string]: { { name: string, type: string } } },
    primaryType: string,
    domain: {
        name: string?,
        version: string?,
        chainId: string?,
        revision: string?,   -- "0" (LEGACY/Pedersen) or "1" (ACTIVE/Poseidon)
    },
    message: { [string]: any },
}
```

### Methods

```luau
TypedData.hash(typedData: TypedDataInput) -> string
TypedData.hashLegacy(typedData: TypedDataInput) -> string
TypedData.hashActive(typedData: TypedDataInput) -> string
TypedData.encodeType(primaryType: string, types: table) -> string
TypedData.encodeValue(value: any, type: string, types: table) -> string
```

| Method | Description |
|--------|-------------|
| `hash(typedData)` | Auto-detects revision from `domain.revision` and delegates |
| `hashLegacy(typedData)` | Revision 0: uses `StarkNetDomain` and Pedersen hashing |
| `hashActive(typedData)` | Revision 1: uses `StarknetDomain` and Poseidon hashing |
| `encodeType(primaryType, types)` | Encode the type definition string |
| `encodeValue(value, type, types)` | Encode a single value according to its type |

---

## Contract

ABI-driven smart contract interface with dynamic dispatch.

### Constructor

```luau
Contract.new(config: {
    abi: { any },           -- Cairo ABI JSON table
    address: string,        -- contract address
    provider: RpcProvider,
    account: Account?,      -- required for write operations
}) -> Contract
```

### Dynamic Methods

Functions from the ABI are available as methods via `__index`:

- **View functions** (`state_mutability = "view"`) → `:functionName(args...) -> Promise<result>`
- **External functions** (`state_mutability = "external"`) → `:functionName(args...) -> Promise<ExecuteResult>`

### Explicit Methods

```luau
contract:call(method: string, args: { any }?) -> Promise<any>
contract:invoke(method: string, args: { any }?, options: ExecuteOptions?) -> Promise<ExecuteResult>
contract:populate(method: string, args: { any }?) -> Call
contract:attach(newAddress: string) -> Contract
```

| Method | Description |
|--------|-------------|
| `:call(method, args)` | Execute a view function (no gas cost) |
| `:invoke(method, args, options)` | Execute an external function (submits transaction) |
| `:populate(method, args)` | Build a Call object for multicall batching |
| `:attach(newAddress)` | Create a new Contract with the same ABI at a different address |

### Return Values

- **Single output** → returned directly
- **Multiple outputs** → returned as `{ [paramName]: value }`

---

## AbiCodec

Low-level ABI encoding and decoding.

### Methods

```luau
AbiCodec.buildTypeMap(abi: { any }) -> TypeMap
AbiCodec.resolveType(typeName: string, typeMap: TypeMap) -> TypeDef
AbiCodec.encode(value: any, typeName: string, typeMap: TypeMap) -> { string }
AbiCodec.decode(results: { string }, offset: number, typeName: string, typeMap: TypeMap) -> (any, number)
```

| Method | Description |
|--------|-------------|
| `buildTypeMap(abi)` | Parse ABI into a type map. Registers structs, enums, and built-in aliases |
| `resolveType(typeName, typeMap)` | Resolve a type name to its definition. Handles generics, tuples, integers |
| `encode(value, typeName, typeMap)` | Encode a Luau value into calldata felts |
| `decode(results, offset, typeName, typeMap)` | Decode calldata felts into a Luau value. Returns `(value, feltsConsumed)` |

### TypeDef

```luau
{
    kind: string,                    -- "felt" | "bool" | "u256" | "unit" | "struct" | "enum" | "array" | "tuple" | "bytearray"
    members: { { name, type } }?,   -- for structs
    variants: { { name, type } }?,  -- for enums
    elementType: string?,            -- for arrays/spans
    tupleTypes: { string }?,         -- for tuples
}
```

---

## ERC20

Pre-built ERC-20 token contract with standard ABI.

### Constructor

```luau
ERC20.new(address: string, provider: RpcProvider, account: Account?) -> Contract
```

### View Methods (No Account Required)

```luau
erc20:name() -> Promise<string>
erc20:symbol() -> Promise<string>
erc20:decimals() -> Promise<number>
erc20:total_supply() -> Promise<{ low: string, high: string }>
erc20:balance_of(account: string) -> Promise<{ low: string, high: string }>
erc20:allowance(owner: string, spender: string) -> Promise<{ low: string, high: string }>
```

### Write Methods (Account Required)

```luau
erc20:transfer(recipient: string, amount: string) -> Promise<ExecuteResult>
erc20:transfer_from(sender: string, recipient: string, amount: string) -> Promise<ExecuteResult>
erc20:approve(spender: string, amount: string) -> Promise<ExecuteResult>
```

camelCase aliases are also available: `totalSupply`, `balanceOf`, `transferFrom`.

---

## ERC721

Pre-built ERC-721 NFT contract with standard ABI.

### Constructor

```luau
ERC721.new(address: string, provider: RpcProvider, account: Account?) -> Contract
```

### View Methods

```luau
erc721:name() -> Promise<string>
erc721:symbol() -> Promise<string>
erc721:balance_of(owner: string) -> Promise<{ low: string, high: string }>
erc721:owner_of(tokenId: string) -> Promise<string>
erc721:get_approved(tokenId: string) -> Promise<string>
erc721:is_approved_for_all(owner: string, operator: string) -> Promise<boolean>
```

### Write Methods

```luau
erc721:transfer_from(from: string, to: string, tokenId: string) -> Promise<ExecuteResult>
erc721:approve(to: string, tokenId: string) -> Promise<ExecuteResult>
erc721:set_approval_for_all(operator: string, approved: boolean) -> Promise<ExecuteResult>
```

camelCase aliases: `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `transferFrom`, `setApprovalForAll`.

---

## StarknetError

Structured error system with type hierarchy.

### Error Type Hierarchy

```
StarknetError (base)
  ├── RpcError
  ├── SigningError
  ├── AbiError
  ├── ValidationError
  └── TransactionError
```

### Factory Methods

```luau
StarknetError.new(message: string, code: number?, data: any?) -> StarknetError
StarknetError.rpc(message: string, sdkCode: number?, rpcCode: number?, data: any?) -> RpcError
StarknetError.signing(message: string, code: number?, data: any?) -> SigningError
StarknetError.abi(message: string, code: number?, data: any?) -> AbiError
StarknetError.validation(message: string, code: number?, hint: string?, data: any?) -> ValidationError
StarknetError.transaction(message: string, code: number?, revertReason: string?, executionTrace: any?, data: any?) -> TransactionError
```

### Instance Methods

```luau
err:is(errorType: string) -> boolean
err:__tostring() -> string
```

### Utility

```luau
StarknetError.isStarknetError(val: any) -> boolean
```

### Error Fields

All errors have: `_type`, `message`, `code`, `data`.

- **RpcError** adds: `rpcCode`
- **ValidationError** adds: `hint`
- **TransactionError** adds: `revertReason`, `executionTrace`

---

## ErrorCodes

Flat table of error code constants.

### Validation (1000-1099)

| Name | Code |
|------|------|
| `INVALID_ARGUMENT` | 1000 |
| `REQUIRED_FIELD` | 1001 |
| `OUT_OF_RANGE` | 1002 |
| `INVALID_FORMAT` | 1003 |

### RPC / Network (2000-2099)

| Name | Code |
|------|------|
| `RPC_ERROR` | 2000 |
| `NETWORK_ERROR` | 2001 |
| `RATE_LIMIT` | 2002 |
| `TIMEOUT` | 2003 |
| `TRANSACTION_REVERTED` | 2004 |
| `TRANSACTION_REJECTED` | 2005 |
| `QUEUE_FULL` | 2010 |
| `BATCH_ERROR` | 2011 |
| `CACHE_ERROR` | 2012 |
| `NONCE_FETCH_ERROR` | 2013 |
| `NONCE_EXHAUSTED` | 2014 |
| `NONCE_MANAGER_ERROR` | 2015 |

### Signing / Crypto (3000-3099)

| Name | Code |
|------|------|
| `SIGNING_ERROR` | 3000 |
| `INVALID_PRIVATE_KEY` | 3001 |
| `KEY_OUT_OF_RANGE` | 3003 |
| `MATH_ERROR` | 3010 |

### ABI / Encoding (4000-4099)

| Name | Code |
|------|------|
| `ABI_ERROR` | 4000 |
| `UNKNOWN_TYPE` | 4001 |
| `ENCODE_ERROR` | 4002 |
| `DECODE_ERROR` | 4003 |
| `UNKNOWN_ENUM_VARIANT` | 4004 |
| `FUNCTION_NOT_FOUND` | 4005 |
| `ARGUMENT_COUNT` | 4006 |

### Transaction (5000-5099)

| Name | Code |
|------|------|
| `TRANSACTION_ERROR` | 5000 |
| `FEE_ESTIMATION_FAILED` | 5001 |

---

## Constants

```luau
local Constants = Starknet.constants
```

### Chain IDs

| Constant | Value |
|----------|-------|
| `SN_MAIN` | `"0x534e5f4d41494e"` |
| `SN_SEPOLIA` | `"0x534e5f5345504f4c4941"` |

### Class Hashes

| Constant | Description |
|----------|-------------|
| `OZ_ACCOUNT_CLASS_HASH` | OpenZeppelin account |
| `ARGENT_ACCOUNT_CLASS_HASH` | Argent X account |
| `BRAAVOS_ACCOUNT_CLASS_HASH` | Braavos account |
| `BRAAVOS_BASE_ACCOUNT_CLASS_HASH` | Braavos base account |

### Token Addresses

| Constant | Description |
|----------|-------------|
| `ETH_TOKEN_ADDRESS` | `0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7` |
| `STRK_TOKEN_ADDRESS` | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |

### Transaction Versions

| Constant | Value |
|----------|-------|
| `INVOKE_TX_V3` | `"0x3"` |
| `DEPLOY_ACCOUNT_TX_V3` | `"0x3"` |
| `DECLARE_TX_V3` | `"0x3"` |

### Other

| Constant | Description |
|----------|-------------|
| `CONTRACT_ADDRESS_PREFIX` | `0x535441524b4e45545f434f4e54524143545f41444452455353` (ASCII "STARKNET_CONTRACT_ADDRESS") |
