# API Reference

Complete API documentation for all starknet-luau modules. Organized by the 9-namespace barrel export structure.

## Table of Contents

**crypto**
- [crypto.BigInt](#bigint) | [crypto.StarkField](#starkfield) | [crypto.StarkScalarField](#starkscalarfield)
- [crypto.StarkCurve](#starkcurve) | [crypto.FieldFactory](#fieldfactory)
- [crypto.Poseidon](#poseidon) | [crypto.Pedersen](#pedersen)
- [crypto.Keccak](#keccak) | [crypto.SHA256](#sha256) | [crypto.ECDSA](#ecdsa)

**signer**
- [signer.StarkSigner](#starksigner)

**provider**
- [provider.RpcProvider](#rpcprovider) | [provider.JsonRpcClient](#jsonrpcclient)
- [provider.RequestQueue](#requestqueue) | [provider.ResponseCache](#responsecache)
- [provider.NonceManager](#noncemanager) | [provider.EventPoller](#eventpoller)

**tx**
- [tx.TransactionBuilder](#transactionbuilder) | [tx.TransactionHash](#transactionhash) | [tx.CallData](#calldata)

**wallet**
- [wallet.Account](#account) | [wallet.TypedData](#typeddata)
- [wallet.AccountType](#accounttype) | [wallet.AccountFactory](#accountfactory)
- [wallet.OutsideExecution](#outsideexecution)
- [wallet.KeyStore](#keystore) | [wallet.OnboardingManager](#onboardingmanager)

**contract**
- [contract.Contract](#contract) | [contract.AbiCodec](#abicodec)
- [contract.ERC20](#erc20) | [contract.ERC721](#erc721) | [contract.PresetFactory](#presetfactory)

**paymaster**
- [paymaster.PaymasterRpc](#paymasterrpc) | [paymaster.AvnuPaymaster](#avnupaymaster)
- [paymaster.PaymasterPolicy](#paymasterpolicy) | [paymaster.PaymasterBudget](#paymasterbudget)
- [paymaster.SponsoredExecutor](#sponsoredexecutor)

**errors**
- [errors.StarknetError](#starkneterror) | [errors.ErrorCodes](#errorcodes)

**other**
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

### Conversions

```luau
BigInt.toHex(a: BigInt) -> string
BigInt.toBytes(a: BigInt) -> buffer
BigInt.toNumber(a: BigInt) -> number
```

### Comparison

```luau
BigInt.isZero(a: BigInt) -> boolean
BigInt.eq(a: BigInt, b: BigInt) -> boolean
BigInt.cmp(a: BigInt, b: BigInt) -> number    -- -1, 0, or 1
BigInt.lt(a: BigInt, b: BigInt) -> boolean
BigInt.lte(a: BigInt, b: BigInt) -> boolean
```

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
BigInt.getBit(a: BigInt, index: number) -> number  -- 0 or 1, 0-indexed from LSB
BigInt.shl(a: BigInt, bits: number) -> BigInt
BigInt.shr(a: BigInt, bits: number) -> BigInt
BigInt.band(a: BigInt, b: BigInt) -> BigInt
BigInt.bor(a: BigInt, b: BigInt) -> BigInt
```

### Modular Arithmetic

```luau
BigInt.addmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.submod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.mulmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.powmod(a: BigInt, e: BigInt, m: BigInt) -> BigInt
BigInt.invmod(a: BigInt, m: BigInt) -> BigInt
```

### Barrett Reduction

```luau
BigInt.createBarrettCtx(m: BigInt) -> BarrettCtx
BigInt.mulmodB(a: BigInt, b: BigInt, ctx: BarrettCtx) -> BigInt
BigInt.powmodB(a: BigInt, e: BigInt, ctx: BarrettCtx) -> BigInt
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

### Arithmetic

```luau
StarkField.add(a: Felt, b: Felt) -> Felt
StarkField.sub(a: Felt, b: Felt) -> Felt
StarkField.mul(a: Felt, b: Felt) -> Felt
StarkField.square(a: Felt) -> Felt
StarkField.neg(a: Felt) -> Felt
StarkField.inv(a: Felt) -> Felt             -- a^(P-2) mod P (Fermat)
StarkField.sqrt(a: Felt) -> Felt?           -- Tonelli-Shanks, nil if no root
```

### Conversions & Comparison

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
StarkCurve.ALPHA: Felt          -- 1
StarkCurve.BETA: Felt           -- 0x6f21413efbe40de...
StarkCurve.G: AffinePoint       -- Generator point
StarkCurve.N: BigInt            -- Curve order
StarkCurve.INFINITY: AffinePoint -- Sentinel (x=0, y=0)
```

### Methods

```luau
StarkCurve.isInfinity(p: JacobianPoint) -> boolean
StarkCurve.isInfinityAffine(p: AffinePoint) -> boolean
StarkCurve.isOnCurve(p: AffinePoint) -> boolean
StarkCurve.affineEq(a: AffinePoint, b: AffinePoint) -> boolean
StarkCurve.affineNeg(p: AffinePoint) -> AffinePoint

StarkCurve.jacobianFromAffine(p: AffinePoint) -> JacobianPoint
StarkCurve.affineFromJacobian(p: JacobianPoint) -> AffinePoint

StarkCurve.jacobianDouble(p: JacobianPoint) -> JacobianPoint
StarkCurve.jacobianAdd(p1: JacobianPoint, p2: JacobianPoint) -> JacobianPoint
StarkCurve.scalarMul(p: AffinePoint, k: buffer) -> AffinePoint
StarkCurve.shamirMul(p1: AffinePoint, k1: buffer, p2: AffinePoint, k2: buffer) -> AffinePoint

StarkCurve.getPublicKey(privateKey: buffer) -> AffinePoint
```

| Method | Description |
|--------|-------------|
| `scalarMul(p, k)` | Compute `k * P` using windowed multiplication. Point first, scalar second |
| `shamirMul(p1, k1, p2, k2)` | Compute `k1*p1 + k2*p2` using Shamir's trick |
| `getPublicKey(privateKey)` | Compute `privateKey * G` (generator multiplication) |

---

## FieldFactory

Creates custom field arithmetic modules over any prime modulus.

```luau
FieldFactory.createField(
    modulus: buffer,
    modulusMinus2: buffer,
    barrettCtx: BarrettCtx,
    name: string
) -> Field
```

Returns a `Field` table with the same API as StarkField: `zero`, `one`, `fromNumber`, `fromHex`, `add`, `sub`, `mul`, `square`, `neg`, `inv`, `toHex`, `toBigInt`, `eq`, `isZero`, `powmod`.

---

## Poseidon

Poseidon hash over the Stark field (Hades permutation, width=3, rate=2).

```luau
Poseidon.hash(a: Felt, b: Felt) -> Felt
Poseidon.hashSingle(x: Felt) -> Felt
Poseidon.hashMany(values: { Felt }) -> Felt
```

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

Note: `r` and `s` are scalar values mod N (buffers), not field elements mod P.

### Methods

```luau
ECDSA.generateK(messageHash: buffer, privateKey: buffer) -> buffer
ECDSA.sign(messageHash: buffer, privateKey: buffer) -> Signature
ECDSA.verify(messageHash: buffer, publicKey: AffinePoint, signature: Signature) -> boolean
```

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
signer:signRaw(msgHash: buffer) -> Signature         -- { r: buffer, s: buffer }
signer:signTransaction(txHash: buffer) -> { string }  -- { r_hex, s_hex }
```

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
| `headers` | `{ [string]: string }?` | `{}` | Custom HTTP headers |
| `retryAttempts` | `number?` | `3` | Max retry attempts |
| `retryDelay` | `number?` | `1` | Seconds between retries (exponential backoff) |
| `maxRequestsPerMinute` | `number?` | `450` | Token bucket rate limit |
| `enableQueue` | `boolean?` | `false` | Enable request queuing and batching |
| `queueConfig` | `table?` | | Queue configuration (see RequestQueue) |
| `enableCache` | `boolean?` | `false` | Enable response caching |
| `cacheConfig` | `table?` | | Cache configuration (see ResponseCache) |
| `enableNonceManager` | `boolean?` | `false` | Enable local nonce tracking |
| `nonceManagerConfig` | `table?` | | Nonce manager config |

### Network Methods

```luau
provider:getChainId() -> Promise<string>
provider:getBlockNumber() -> Promise<number>
provider:getSpecVersion() -> Promise<string>
provider:getSyncingStats() -> Promise<any>
```

### Account Methods

```luau
provider:getNonce(contractAddress: string, blockId: any?) -> Promise<string>
```

### Transaction Methods

```luau
provider:call(request: CallRequest, blockId: any?) -> Promise<{ string }>
provider:estimateFee(transactions: { any }, simulationFlags: { string }?) -> Promise<{ FeeEstimate }>
provider:addInvokeTransaction(invokeTx: any) -> Promise<string>
provider:addDeployAccountTransaction(deployTx: any) -> Promise<DeployAccountResult>
provider:getTransactionReceipt(txHash: string) -> Promise<TransactionReceipt>
provider:getTransactionStatus(txHash: string) -> Promise<TransactionStatus>
provider:getTransactionByHash(txHash: string) -> Promise<Transaction>
provider:estimateMessageFee(message: any, blockId: any?) -> Promise<FeeEstimate>
```

### Block Methods

```luau
provider:getBlockWithTxHashes(blockId: any?) -> Promise<Block>
provider:getBlockWithTxs(blockId: any?) -> Promise<BlockWithTxs>
provider:getBlockWithReceipts(blockId: any?) -> Promise<BlockWithReceipts>
```

### Contract Methods

```luau
provider:getClassHashAt(contractAddress: string, blockId: any?) -> Promise<string>
provider:getStorageAt(contractAddress: string, key: string, blockId: any?) -> Promise<string>
provider:getClass(classHash: string, blockId: any?) -> Promise<ContractClass>
provider:getClassAt(contractAddress: string, blockId: any?) -> Promise<ContractClass>
```

### Event Methods

```luau
provider:getEvents(filter: EventFilter) -> Promise<EventsChunk>
provider:getAllEvents(filter: EventFilter) -> Promise<{ EmittedEvent }>
```

### Utility Methods

```luau
provider:waitForTransaction(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
provider:fetch(method: string, params: any) -> Promise<any>
provider:fetchSync(method: string, params: any) -> any
provider:getNodeUrl() -> string
provider:getPromise() -> any
provider:getNonceManager() -> NonceManager?
provider:getMetrics() -> ProviderMetrics
provider:flushCache() -> ()
```

---

## JsonRpcClient

Base JSON-RPC client shared by RpcProvider and PaymasterRpc.

### Constructor

```luau
JsonRpcClient.new(config: {
    nodeUrl: string,
    headers: { [string]: string }?,
    maxRequestsPerMinute: number?,
    retryAttempts: number?,
    retryDelay: number?,
    clientName: string?,
    errorMapper: ((decoded: any) -> never)?,
    shouldRetry: ((err: any) -> boolean)?,
}) -> JsonRpcClient
```

### Methods

```luau
client:getNodeUrl() -> string
client:getPromise() -> any
client:fetch(method: string, params: any) -> Promise<any>
client:getRateLimiter() -> RateLimiter
```

---

## RequestQueue

Priority queue with JSON-RPC batching for the provider. Enabled via `enableQueue: true`.

### Priority Levels

| Priority | Methods |
|----------|---------|
| HIGH | `addInvokeTransaction`, `estimateFee`, `addDeployAccountTransaction` |
| NORMAL | All other RPC methods |
| LOW | `getEvents` |

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

---

## ResponseCache

LRU cache with per-method TTL. Enabled via `enableCache: true`.

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
manager:getPendingCount(address: string) -> number
manager:isInitialized(address: string) -> boolean
manager:isDirty(address: string) -> boolean
manager:peekNextNonce(address: string) -> string?
manager:reset(address: string)
```

---

## EventPoller

Continuous event polling with configurable interval and DataStore persistence.

### Constructor

```luau
EventPoller.new(config: {
    provider: RpcProvider,
    filter: EventFilter,
    interval: number?,                    -- seconds (default: 10)
    onEvents: (events: { Event }) -> (),
    onError: ((err: any) -> ())?,
    -- DataStore persistence (optional)
    _dataStore: DataStoreLike?,           -- DataStore-compatible object
    checkpointKey: string?,               -- default: "EventPoller_checkpoint"
    onCheckpoint: ((blockNumber: number) -> ())?,
}) -> EventPoller
```

### Methods

```luau
poller:start()
poller:stop()
poller:isRunning() -> boolean
poller:getLastBlockNumber() -> number?
poller:setLastBlockNumber(blockNumber: number)
poller:getCheckpointKey() -> string?
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
builder:deployAccount(account: Account, params: DeployAccountParams, options: DeployAccountOptions?) -> Promise<DeployAccountResult>
builder:estimateDeployAccountFee(account: Account, params: DeployAccountParams) -> Promise<FeeEstimate>
builder:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
```

**Call:**
```luau
{
    contractAddress: string,
    entrypoint: string,
    calldata: { string },
}
```

---

## TransactionHash

Computes V3 transaction hashes using Poseidon.

```luau
TransactionHash.calculateInvokeTransactionHash(params: {
    senderAddress: string,
    compiledCalldata: { string },
    chainId: string,
    nonce: string,
    resourceBounds: ResourceBounds,
    version: string?,
    tip: string?,
    paymasterData: { string }?,
    accountDeploymentData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
}) -> string

TransactionHash.calculateDeployAccountTransactionHash(params: {
    classHash: string,
    constructorCalldata: { string },
    contractAddress: string,
    salt: string,
    chainId: string,
    nonce: string,
    resourceBounds: ResourceBounds,
    version: string?,
    tip: string?,
    paymasterData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
}) -> string

TransactionHash.hashFeeField(tip: string, resourceBounds: ResourceBounds) -> string
TransactionHash.hashDAMode(nonceDAMode: number, feeDAMode: number) -> string
```

**ResourceBounds:**
```luau
{
    l1Gas: { maxAmount: string, maxPricePerUnit: string },
    l2Gas: { maxAmount: string, maxPricePerUnit: string },
    l1DataGas: { maxAmount: string, maxPricePerUnit: string },
}
```

---

## CallData

Calldata encoding for Starknet transactions.

```luau
CallData.encodeFelt(value: string) -> { string }
CallData.encodeU256(value: string) -> { string }
CallData.encodeBool(value: boolean) -> { string }
CallData.encodeArray(values: { string }) -> { string }
CallData.encodeMulticall(calls: { Call }) -> { string }
CallData.validateCall(call: Call) -> ()
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
    accountType: string?,
    classHash: string?,
    constructorCalldata: { string }?,
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
    classHash: string,                    -- required
    publicKey: string,
    constructorCalldata: { string }?,
    salt: string?,                        -- defaults to public key
    deployer: string?,                    -- defaults to "0x0"
}) -> string

Account.detectAccountType(classHash: string) -> string?
Account.getConstructorCalldata(accountType: string, publicKey: string, guardian: string?) -> { string }

Account.getDeploymentFeeEstimate(config) -> Promise<{ estimatedFee, requiredBalance, gasConsumed, gasPrice, rawEstimate }>
Account.checkDeploymentBalance(config) -> Promise<{ hasSufficientBalance, balance, estimatedFee, requiredBalance, token, deficit? }>
Account.getDeploymentFundingInfo(config) -> Promise<{ address, estimatedFee, requiredBalance, token, tokenAddress, classHash, constructorCalldata, salt }>
```

### Instance Properties

```luau
account.address: string
account.signer: StarkSigner
```

### Instance Methods

```luau
account:getPublicKeyHex() -> string
account:getProvider() -> RpcProvider
account:getNonce() -> Promise<string>

-- Transaction execution
account:execute(calls: { Call }, options: ExecuteOptions?) -> Promise<ExecuteResult>
account:estimateFee(calls: { Call }) -> Promise<FeeEstimate>
account:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>

-- Account deployment
account:deployAccount(options: DeployAccountOptions?) -> Promise<{ transactionHash, contractAddress, alreadyDeployed? }>
account:estimateDeployAccountFee() -> Promise<FeeEstimate>
account:getDeploymentData() -> { classHash, calldata, salt, unique, version }

-- Typed data (SNIP-12)
account:hashMessage(typedData: TypedDataInput) -> string
account:signMessage(typedData: TypedDataInput) -> { string }  -- { r_hex, s_hex }

-- Paymaster integration
account:estimatePaymasterFee(calls: { any }, paymasterDetails: PaymasterDetails) -> Promise<{ feeEstimate, typedData }>
account:executePaymaster(calls: { any }, paymasterDetails: PaymasterDetails) -> Promise<{ transactionHash, trackingId }>
account:deployWithPaymaster(paymasterDetails: PaymasterDetails, options: table?) -> Promise<{ transactionHash, contractAddress, trackingId?, alreadyDeployed? }>
```

---

## TypedData

SNIP-12 typed data hashing and encoding (similar to EIP-712).

### Constants

```luau
TypedData.REVISION_LEGACY = "0"
TypedData.REVISION_ACTIVE = "1"
```

### Methods

```luau
TypedData.getMessageHash(typedData: TypedDataInput, accountAddress: string) -> string
TypedData.identifyRevision(typedData: TypedDataInput) -> string
TypedData.encodeType(types: table, typeName: string, revision: string?) -> string
TypedData.getTypeHash(types: table, typeName: string, revision: string?) -> string
TypedData.getDependencies(types: table, typeName: string, dependencies: { string }?, contains: string?, revision: string?) -> { string }
TypedData.encodeValue(types: table, typeName: string, data: any, ctx: table?, revision: string?) -> (string, string)
TypedData.encodeData(types: table, typeName: string, data: any, revision: string?) -> ({ string }, { string })
TypedData.getStructHash(types: table, typeName: string, data: any, revision: string?) -> string
TypedData.merkleRoot(leaves: { string }, hashPair: (string, string) -> string) -> string
```

---

## AccountType

Callable account type objects for configurable account creation.

### Pre-defined Types

```luau
AccountType.OZ       -- { type = "oz", classHash = ... }
AccountType.Argent   -- { type = "argent", classHash = ... }
AccountType.Braavos  -- { type = "braavos", classHash = ... }
```

Each is callable to generate constructor calldata:
```luau
AccountType.OZ(publicKey: string) -> { string }
AccountType.Argent(ownerKey: string, guardianKey: string?) -> { string }
AccountType.Braavos(publicKey: string) -> { string }
```

### Methods

```luau
AccountType.get(typeName: string) -> AccountTypeObj?
AccountType.custom(config: { type: string, classHash: string, buildCalldata: (...any) -> { string } }) -> AccountTypeObj
```

---

## AccountFactory

Batch account creation and deployment.

### Constructor

```luau
AccountFactory.new(provider: RpcProvider, accountType: AccountTypeObj, signer: StarkSigner) -> AccountFactory
```

### Methods

```luau
factory:createAccount(options: { classHash: string?, salt: string?, guardian: string? }?) -> { account, address, deployTx }
factory:batchCreate(count: number, options: { privateKeys: { string }?, keyGenerator: (() -> string)?, classHash: string?, guardian: string? }?) -> { { account, address, signer, deployTx } }
factory:batchDeploy(accounts: { { account, address } }, options: { maxConcurrency: number?, onDeployProgress: fn?, waitForConfirmation: boolean?, dryRun: boolean?, maxFee: string?, feeMultiplier: number? }?) -> Promise<{ deployed, failed, skipped, results }>
```

---

## OutsideExecution

SNIP-9 Outside Execution for meta-transactions.

### Constants

```luau
OutsideExecution.VERSION_V1 = "1"
OutsideExecution.VERSION_V2 = "2"
OutsideExecution.VERSION_V3_RC = "3"
OutsideExecution.ENTRYPOINT_V1 = "execute_from_outside"
OutsideExecution.ENTRYPOINT_V2 = "execute_from_outside_v2"
OutsideExecution.ENTRYPOINT_V3 = "execute_from_outside_v3"
OutsideExecution.ANY_CALLER: string
OutsideExecution.INTERFACE_ID_V1: string
OutsideExecution.INTERFACE_ID_V2: string
```

### Methods

```luau
OutsideExecution.getEntrypoint(version: string) -> string
OutsideExecution.getOutsideCall(call: table) -> { to, selector, calldata }
OutsideExecution.getTypedData(config: GetTypedDataConfig) -> TypedDataInput
OutsideExecution.validateCalls(submittedCalls: { table }, returnedCalls: { table }) -> boolean
OutsideExecution.buildExecuteFromOutsideCall(signerAddress: string, outsideExecution: table, signature: { string }, version: string) -> Call
```

**GetTypedDataConfig:**
```luau
{
    chainId: string,
    caller: string,
    execute_after: number | string,
    execute_before: number | string,
    nonce: number | string,
    calls: { Call },
    version: string,
    feeMode: table?,
}
```

---

## KeyStore

Encrypted private key persistence using DataStore.

### Constructor

```luau
KeyStore.new(config: {
    serverSecret: string,
    dataStoreName: string?,    -- default: "PlayerKeys"
    accountType: string?,      -- default: "oz"
}) -> KeyStore
```

### Methods

```luau
keyStore:generateAndStore(playerId: number, provider: RpcProvider) -> { account, address }
keyStore:loadAccount(playerId: number, provider: RpcProvider) -> Account?
keyStore:getOrCreate(playerId: number, provider: RpcProvider) -> { account, isNew }
keyStore:hasAccount(playerId: number) -> boolean
keyStore:deleteKey(playerId: number)
keyStore:rotateSecret(oldSecret: string, newSecret: string, playerIds: { number }) -> { rotated: number, failed: { { playerId, error } } }
keyStore:getRecord(playerId: number) -> KeyStoreRecord?
keyStore:markDeployed(playerId: number)
keyStore:isDeployed(playerId: number) -> boolean
```

---

## OnboardingManager

Orchestrates full player onboarding: key generation, account creation, deployment.

### Constructor

```luau
OnboardingManager.new(config: {
    keyStore: KeyStore,
    provider: RpcProvider,
    paymasterDetails: PaymasterDetails?,
    waitForConfirmation: boolean?,
    dryRun: boolean?,
}) -> OnboardingManager
```

### Methods

```luau
manager:onboard(playerId: number) -> OnboardingResult
manager:getStatus(playerId: number) -> { hasAccount, isDeployed, address? }
manager:ensureDeployed(playerId: number) -> OnboardingResult
manager:removePlayer(playerId: number)
```

**OnboardingResult:**
```luau
{
    account: Account,
    address: string,
    isNew: boolean,
    wasDeployed: boolean,
    alreadyDeployed: boolean,
    transactionHash: string?,
    trackingId: string?,
}
```

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
contract:call(method: string, args: { any }?, blockId: string?) -> Promise<any>
contract:invoke(method: string, args: { any }?, options: InvokeOptions?) -> Promise<ExecuteResult>
contract:populate(method: string, args: { any }?) -> Call
```

### Introspection

```luau
contract:getFunctions() -> { string }
contract:getFunction(name: string) -> ParsedFunction?
contract:hasFunction(name: string) -> boolean
contract:getEvents() -> { string }
contract:hasEvent(name: string) -> boolean
```

### Event Handling

```luau
contract:parseEvents(receipt: TransactionReceipt, options: { strict: boolean? }?) -> { events: { any }, errors: { { event, error } } }
contract:queryEvents(filter: EventFilter?) -> Promise<{ any }>
```

---

## AbiCodec

Low-level ABI encoding and decoding. Exported via `Starknet.contract.AbiCodec`.

### Methods

```luau
AbiCodec.buildTypeMap(abi: { any }) -> TypeMap
AbiCodec.resolveType(typeName: string, typeMap: TypeMap) -> TypeDef
AbiCodec.encode(value: any, typeName: string, typeMap: TypeMap) -> { string }
AbiCodec.decode(results: { string }, offset: number, typeName: string, typeMap: TypeMap) -> (any, number)
AbiCodec.encodeEnum(value: any, variants: { table }, typeMap: TypeMap) -> { string }
AbiCodec.decodeEnum(results: { string }, offset: number, variants: { table }, typeMap: TypeMap) -> (any, number)
AbiCodec.encodeInputs(args: { any }, inputs: { table }, typeMap: TypeMap) -> { string }
AbiCodec.decodeOutputs(results: { string }, outputs: { table }, typeMap: TypeMap) -> any
AbiCodec.decodeEvent(keys: { string }, data: { string }, eventDef: EventDef, typeMap: TypeMap) -> { [string]: any }
AbiCodec.encodeByteArray(str: string) -> { string }
AbiCodec.decodeByteArray(results: { string }, offset: number) -> (string, number)
```

---

## ERC20

Pre-built ERC-20 token contract with standard ABI.

### Constructor

```luau
ERC20.new(address: string, provider: RpcProvider, account: Account?) -> Contract
ERC20.getAbi() -> Abi
```

### View Methods

```luau
erc20:name() -> Promise<string>
erc20:symbol() -> Promise<string>
erc20:decimals() -> Promise<number>
erc20:total_supply() -> Promise<{ low: string, high: string }>
erc20:balance_of(account: string) -> Promise<{ low: string, high: string }>
erc20:allowance(owner: string, spender: string) -> Promise<{ low: string, high: string }>
```

### Write Methods

```luau
erc20:transfer(recipient: string, amount: string) -> Promise<ExecuteResult>
erc20:transfer_from(sender: string, recipient: string, amount: string) -> Promise<ExecuteResult>
erc20:approve(spender: string, amount: string) -> Promise<ExecuteResult>
erc20:increase_allowance(spender: string, amount: string) -> Promise<ExecuteResult>
erc20:decrease_allowance(spender: string, amount: string) -> Promise<ExecuteResult>
```

camelCase aliases: `totalSupply`, `balanceOf`, `transferFrom`, `increaseAllowance`, `decreaseAllowance`.

---

## ERC721

Pre-built ERC-721 NFT contract with standard ABI.

### Constructor

```luau
ERC721.new(address: string, provider: RpcProvider, account: Account?) -> Contract
ERC721.getAbi() -> Abi
```

### View Methods

```luau
erc721:name() -> Promise<string>
erc721:symbol() -> Promise<string>
erc721:balance_of(owner: string) -> Promise<{ low: string, high: string }>
erc721:owner_of(tokenId: string) -> Promise<string>
erc721:get_approved(tokenId: string) -> Promise<string>
erc721:is_approved_for_all(owner: string, operator: string) -> Promise<boolean>
erc721:token_uri(tokenId: string) -> Promise<string>
erc721:supports_interface(interfaceId: string) -> Promise<boolean>
```

### Write Methods

```luau
erc721:transfer_from(from: string, to: string, tokenId: string) -> Promise<ExecuteResult>
erc721:approve(to: string, tokenId: string) -> Promise<ExecuteResult>
erc721:set_approval_for_all(operator: string, approved: boolean) -> Promise<ExecuteResult>
erc721:safe_transfer_from(from: string, to: string, tokenId: string) -> Promise<ExecuteResult>
```

camelCase aliases: `balanceOf`, `ownerOf`, `getApproved`, `isApprovedForAll`, `transferFrom`, `setApprovalForAll`, `tokenURI`, `supportsInterface`, `safeTransferFrom`.

---

## PresetFactory

Create custom contract presets from any ABI.

```luau
PresetFactory.create(abi: Abi, shortStringMethods: { string }?) -> {
    new: (address: string, provider: RpcProvider, account: Account?) -> Contract,
    getAbi: () -> Abi,
}
```

The `shortStringMethods` parameter lists method names whose return values should be automatically decoded from felt short strings to Luau strings.

---

## PaymasterRpc

SNIP-29 JSON-RPC paymaster client.

### Constructor

```luau
PaymasterRpc.new(config: {
    nodeUrl: string,
    headers: { [string]: string }?,
    retryAttempts: number?,
    retryDelay: number?,
    maxRequestsPerMinute: number?,
}) -> PaymasterRpc
```

### Methods

```luau
paymaster:isAvailable() -> Promise<boolean>
paymaster:getSupportedTokens() -> Promise<{ TokenData }>
paymaster:buildTypedData(userAddress: string, calls: { Call }, gasTokenAddress: string, options: BuildTypedDataOptions?) -> Promise<BuildTypedDataResult>
paymaster:executeTransaction(userAddress: string, typedData: any, signature: { string }, gasTokenAddress: string?, options: BuildTypedDataOptions?) -> Promise<ExecuteResult>
paymaster:trackingIdToLatestHash(trackingId: string) -> Promise<TrackingResult>
paymaster:getNodeUrl() -> string
paymaster:fetch(method: string, params: any) -> Promise<any>
```

**BuildTypedDataOptions:**
```luau
{ accountClassHash: string?, deploymentData: DeploymentData? }
```

**BuildTypedDataResult:**
```luau
{ typedData: any, feeEstimate: FeeEstimate?, deploymentData: any? }
```

**ExecuteResult:**
```luau
{ trackingId: string?, transactionHash: string }
```

---

## AvnuPaymaster

AVNU-specific paymaster with token caching and network presets.

### Constructor

```luau
AvnuPaymaster.new(config: {
    network: string,           -- "sepolia" | "mainnet"
    apiKey: string?,
    nodeUrl: string?,          -- override endpoint
    tokenCacheTtl: number?,    -- seconds
}) -> AvnuPaymaster
```

### Instance Methods

Same interface as PaymasterRpc, plus:

```luau
avnu:getNetwork() -> string
avnu:isSponsored() -> boolean
avnu:getKnownTokens() -> { [string]: TokenInfo }
avnu:getTokenAddress(symbol: string) -> string?
avnu:clearTokenCache()
```

### Static Methods

```luau
AvnuPaymaster.getEndpoint(network: string) -> string?
AvnuPaymaster.getEndpoints() -> { [string]: string }
AvnuPaymaster.getTokensForNetwork(network: string) -> { [string]: TokenInfo }
```

---

## PaymasterPolicy

Policy engine for sponsorship restrictions.

### Constructor

```luau
PaymasterPolicy.new(config: {
    allowedContracts: { { address: string } }?,
    allowedMethods: { { contract: string, selector: string } }?,
    allowedPlayers: { { playerId: number } }?,
    maxFeePerTx: (string | buffer)?,
    maxTxPerPlayer: number?,
    timeWindow: number?,
}) -> PaymasterPolicy
```

### Methods

```luau
policy:validate(playerId: number, calls: { Call }) -> { allowed: boolean, reason: string? }
policy:validateFee(playerId: number, feeAmount: string | buffer) -> { allowed: boolean, reason: string? }
policy:recordUsage(playerId: number)
policy:resetUsage(playerId: number?)
policy:getUsageCount(playerId: number) -> number
```

---

## PaymasterBudget

Per-player budget tracking with DataStore persistence.

### Constructor

```luau
PaymasterBudget.new(config: {
    dataStoreName: string?,
    defaultTokenBalance: number?,
    costPerTransaction: number?,
    costPerGasUnit: number?,
    flushInterval: number?,
    maxDirtyEntries: number?,
}?) -> PaymasterBudget
```

### Methods

```luau
-- Balance
budget:getBalance(playerId: number) -> number
budget:grantTokens(playerId: number, amount: number)
budget:revokeTokens(playerId: number, amount: number)

-- Transactions
budget:calculateCost(gasUsed: number?) -> number
budget:canAfford(playerId: number, txCost: number?) -> boolean
budget:consumeTransaction(playerId: number, txCost: number?) -> number
budget:refundTransaction(playerId: number, txCost: number?)

-- Stats
budget:getUsageStats(playerId: number) -> { balance, totalTxCount, totalTokensSpent, lastTxTime }

-- Cache management
budget:flush()
budget:flushPlayer(playerId: number)
budget:loadPlayer(playerId: number)
budget:unloadPlayer(playerId: number)
budget:isCached(playerId: number) -> boolean
budget:getDirtyCount() -> number
budget:getFlushErrors() -> { string }
budget:clearFlushErrors()
```

---

## SponsoredExecutor

Orchestrates sponsored transaction execution with policy, budget, and retry logic.

### Constructor

```luau
SponsoredExecutor.new(config: {
    account: Account,
    paymaster: PaymasterRpc | AvnuPaymaster,
    feeMode: { mode: "sponsored" | "default", gasToken: string? },
    policy: PaymasterPolicy?,
    budget: PaymasterBudget?,
    callbacks: {
        onTransactionSubmitted: ((info) -> ())?,
        onTransactionConfirmed: ((info) -> ())?,
        onTransactionFailed: ((info) -> ())?,
    }?,
    retryAttempts: number?,
    retryDelay: number?,
    deploymentData: DeploymentData?,
}) -> SponsoredExecutor
```

### Methods

```luau
executor:execute(playerId: number, calls: { Call }, options: {
    txCost: number?,
    gasUsed: number?,
    deploymentData: DeploymentData?,
    waitForConfirmation: boolean?,
}?) -> Promise<{ transactionHash, trackingId?, tokensCost, retryCount }>

executor:getMetrics() -> ExecutorMetrics
executor:resetMetrics()
```

**ExecutorMetrics:**
```luau
{
    totalExecutions: number,
    totalSuccessful: number,
    totalFailed: number,
    totalRetries: number,
    totalTokensConsumed: number,
    totalTokensRefunded: number,
    byPlayer: { [number]: { executions, successful, failed, tokensSpent } },
    byContract: { [string]: number },
    byMethod: { [string]: number },
}
```

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

Flat table of error code constants. Each entry is `{ code: number, name: string }`.

### Validation (1000-1099)

| Name | Code |
|------|------|
| `INVALID_ARGUMENT` | 1000 |
| `REQUIRED_FIELD` | 1001 |
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
| `NONCE_FETCH_ERROR` | 2013 |
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
| `BATCH_DEPLOY_ERROR` | 5003 |
| `NONCE_EXHAUSTED` | 5004 |

### Outside Execution / SNIP-9 (6000-6099)

| Name | Code |
|------|------|
| `INVALID_VERSION` | 6001 |
| `CALL_VALIDATION_FAILED` | 6002 |
| `MISSING_FEE_MODE` | 6003 |
| `INVALID_TIME_BOUNDS` | 6004 |

### Paymaster / SNIP-29 (7000-7099)

| Name | Code |
|------|------|
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

### KeyStore / Onboarding (8000-8099)

| Name | Code |
|------|------|
| `KEY_STORE_ERROR` | 8000 |
| `KEY_STORE_DECRYPT_ERROR` | 8001 |
| `KEY_STORE_SECRET_INVALID` | 8002 |
| `ONBOARDING_ERROR` | 8010 |

### Utility Functions

```luau
ErrorCodes.isTransient(errorCode: number) -> boolean
-- Transient: NETWORK_ERROR (2001), RATE_LIMIT (2002), PAYMASTER_UNAVAILABLE (7001)

ErrorCodes.isNonRetryablePaymaster(errorCode: number) -> boolean
-- Non-retryable: 7000, 7002, 7003, 7004, 7005, 7006, 7007, 7008
```

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
| `BRAAVOS_ACCOUNT_CLASS_HASH` | Braavos implementation |
| `BRAAVOS_BASE_ACCOUNT_CLASS_HASH` | Braavos base (for address computation) |

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
| `ANY_CALLER` | Address constant for SNIP-9 any-caller permission |
