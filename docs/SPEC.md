# starknet-luau SDK Specification

## 1. Overview

### 1.1 Project Description

**starknet-luau** is a pure Luau SDK for interacting with the Starknet blockchain from Roblox games. It provides cryptographic primitives, account management, transaction building/signing, contract interaction, and RPC connectivity -- all implemented in Luau with no external native dependencies.

### 1.2 Goals

- Enable Roblox game developers to integrate Starknet onchain mechanics (tokens, NFTs, leaderboards, game state)
- Provide a complete, self-contained Starknet SDK in pure Luau
- Build/sign/submit transactions entirely from the Roblox game server
- Offer a clean, well-documented API inspired by starknet.js
- Ship with comprehensive Lune-based tests cross-referenced against starknet.js expected values
- Distribute as a Wally package for easy installation

### 1.3 Target Audience

- Roblox game developers who want to add onchain features (NFT gating, token rewards, onchain leaderboards, verifiable game state)
- Starknet ecosystem developers building cross-platform tooling
- Developers building Autonomous World / Fully Onchain Game (FOCG) experiences on Roblox

### 1.4 Design Principles

1. **Pure Luau** -- No native FFI, no external processes. Everything runs within Roblox's scripting environment.
2. **Performance-first crypto** -- Use buffer-based field arithmetic with f64 limbs and `--!native` / `--!optimize 2` pragmas, following rbx-cryptography's proven patterns.
3. **Promise-based async** -- All network operations return Promises via roblox-lua-promise.
4. **Modular** -- Each submodule (crypto, provider, account, tx, contract, signer) is independently usable.
5. **Testable** -- Every module has Lune tests with expected values cross-referenced from starknet.js.
6. **Minimal dependencies** -- Only depend on roblox-lua-promise and rbx-cryptography (peer dependency for SHA/Keccak where applicable).

---

## 2. Architecture

### 2.1 High-Level Architecture

```
+------------------------------------------------------------------+
|                        starknet-luau SDK                         |
|                                                                  |
|  +------------------+  +------------------+  +----------------+  |
|  |     contract     |  |     wallet       |  |   provider     |  |
|  |  (ABI, call,     |  |  (Account,       |  |  (RPC client,  |  |
|  |   invoke,        |  |   key mgmt,      |  |   rate limit,  |  |
|  |   ERC20/721)     |  |   nonce mgmt)    |  |   polling)     |  |
|  +--------+---------+  +--------+---------+  +-------+--------+  |
|           |                     |                     |          |
|  +--------+---------+  +-------+----------+           |          |
|  |       tx         |  |     signer       |           |          |
|  |  (build, hash,   |  |  (StarkSigner,   |           |          |
|  |   calldata,      |  |   interface)     |           |          |
|  |   fee estimate)  |  +-------+----------+           |          |
|  +--------+---------+          |                      |          |
|           |                    |                      |          |
|  +--------+--------------------+--------------------------+      |
|  |                    crypto                              |      |
|  |  (BigInt, StarkField, StarkCurve, Poseidon, Pedersen,  |      |
|  |   Keccak, SHA256, HMAC, ECDSA)                         |      |
|  +--------------------------------------------------------+      |
|                                                                  |
+------------------------------------------------------------------+
                              |
                    Roblox HttpService
                              |
                     Starknet RPC Node
```

### 2.2 Module Dependency Graph

```
contract ──> tx ──> crypto
    |         |        ^
    |         v        |
    +──> wallet ──> signer ──> crypto
    |         |
    v         v
  provider  provider
```

- **crypto** is the foundation layer with zero SDK dependencies
- **signer** depends on crypto for ECDSA operations
- **provider** is independent (only needs HttpService + Promise)
- **tx** depends on crypto (for hashing, calldata encoding) and provider (for nonce, fee estimation)
- **wallet** depends on signer, provider, and crypto (for address derivation)
- **contract** depends on tx (for building calls), wallet (for signing), and provider (for reading)

### 2.3 Repository Structure

```
starknet-luau/
├── src/
│   ├── init.luau                    # Main entry point / barrel exports
│   ├── crypto/
│   │   ├── init.luau                # Crypto module exports
│   │   ├── BigInt.luau              # Buffer-based arbitrary precision integers
│   │   ├── StarkField.luau          # GF(P) arithmetic for Stark prime
│   │   ├── StarkScalarField.luau    # Arithmetic modulo curve order N
│   │   ├── StarkCurve.luau          # Short Weierstrass EC operations
│   │   ├── Poseidon.luau            # Poseidon hash (Hades permutation)
│   │   ├── Pedersen.luau            # Pedersen hash (EC-based)
│   │   ├── Keccak.luau              # Keccak-256 (sn_keccak for selectors)
│   │   ├── SHA256.luau              # SHA-256 + HMAC-SHA256
│   │   └── ECDSA.luau               # Stark ECDSA signing (RFC 6979)
│   ├── signer/
│   │   ├── init.luau                # Signer module exports
│   │   ├── SignerInterface.luau     # Abstract signer protocol/type
│   │   └── StarkSigner.luau         # Stark curve ECDSA signer
│   ├── provider/
│   │   ├── init.luau                # Provider module exports
│   │   ├── RpcProvider.luau         # JSON-RPC client over HttpService
│   │   ├── RpcMethods.luau          # RPC method definitions and types
│   │   └── RpcTypes.luau            # Request/response type definitions
│   ├── tx/
│   │   ├── init.luau                # Transaction module exports
│   │   ├── CalldataEncoder.luau     # Felt/u256/array/struct encoding
│   │   ├── TransactionHash.luau     # V3 INVOKE hash computation (Poseidon)
│   │   ├── TransactionBuilder.luau  # Build + sign transaction flow
│   │   └── TransactionTypes.luau    # Transaction type definitions
│   ├── wallet/
│   │   ├── init.luau                # Wallet module exports
│   │   ├── Account.luau             # Account derivation + management
│   │   ├── AccountTypes.luau        # Account type definitions (OZ, Argent, etc.)
│   │   └── NonceManager.luau        # Nonce tracking and management
│   └── contract/
│       ├── init.luau                # Contract module exports
│       ├── Contract.luau            # ABI-driven contract interface
│       ├── AbiParser.luau           # ABI parsing and type resolution
│       ├── AbiTypes.luau            # ABI type definitions
│       └── presets/
│           ├── ERC20.luau           # ERC-20 token interface
│           └── ERC721.luau          # ERC-721 NFT interface
├── tests/
│   ├── run.luau                     # Lune test runner
│   ├── crypto/
│   │   ├── BigInt.spec.luau
│   │   ├── StarkField.spec.luau
│   │   ├── StarkCurve.spec.luau
│   │   ├── Poseidon.spec.luau
│   │   ├── Pedersen.spec.luau
│   │   ├── Keccak.spec.luau
│   │   ├── SHA256.spec.luau
│   │   └── ECDSA.spec.luau
│   ├── signer/
│   │   └── StarkSigner.spec.luau
│   ├── provider/
│   │   └── RpcProvider.spec.luau
│   ├── tx/
│   │   ├── CalldataEncoder.spec.luau
│   │   ├── TransactionHash.spec.luau
│   │   └── TransactionBuilder.spec.luau
│   ├── wallet/
│   │   └── Account.spec.luau
│   ├── contract/
│   │   ├── Contract.spec.luau
│   │   └── AbiParser.spec.luau
│   └── fixtures/
│       ├── test-vectors.luau        # Known-good values from starknet.js
│       └── sample-abis.luau         # Sample contract ABIs for testing
├── examples/
│   ├── read-contract.luau           # Read ERC-20 balance
│   ├── sign-transaction.luau        # Sign and submit a transfer
│   ├── nft-gate.luau                # NFT ownership gating
│   ├── leaderboard.luau             # Onchain leaderboard interaction
│   └── multicall.luau               # Batch multiple contract calls
├── docs/
│   ├── SPEC.md                      # This file
│   └── ROADMAP.md                   # Development roadmap
├── default.project.json             # Rojo project configuration
├── wally.toml                       # Wally package manifest
├── rokit.toml                       # Rokit toolchain (rojo, wally, lune, selene, stylua)
├── Makefile                         # Build automation
├── .luaurc                          # Luau LSP configuration (strict mode)
├── selene.toml                      # Selene linter config
├── .stylua.toml                     # StyLua formatter config
├── .github/
│   └── workflows/
│       ├── ci.yml                   # CI: lint, fmt, test, build
│       └── release.yml              # Release: build + publish to Wally
├── .gitignore
├── LICENSE                          # MIT
├── README.md
└── CLAUDE.md                        # Claude Code project instructions
```

---

## 3. Module Specifications

### 3.1 crypto -- Cryptographic Primitives

The crypto module is the foundation of the SDK. All implementations use buffer-based field arithmetic with f64 limbs following rbx-cryptography's proven patterns for maximum Luau performance.

#### 3.1.1 BigInt

Arbitrary-precision integer arithmetic using buffer-backed f64 limb arrays.

**Design:**
- Representation: Array of f64 limbs stored in Luau `buffer` objects (little-endian)
- Limb size: 24 bits per limb (keeps products under 2^53 f64 precision limit)
- 11 limbs = 264 bits of coverage (sufficient for 252-bit Stark field elements)
- All operations use `--!native` and `--!optimize 2` pragmas
- Carry propagation via the IEEE 754 rounding trick: `x + 3*2^k - 3*2^k`

**API:**
```lua
-- Constructors
BigInt.fromNumber(n: number) -> BigInt
BigInt.fromHex(hex: string) -> BigInt
BigInt.fromBytes(buf: buffer) -> BigInt
BigInt.zero() -> BigInt
BigInt.one() -> BigInt

-- Conversions
BigInt.toHex(a: BigInt) -> string
BigInt.toBytes(a: BigInt) -> buffer
BigInt.toNumber(a: BigInt) -> number  -- only safe for small values

-- Comparison
BigInt.eq(a: BigInt, b: BigInt) -> boolean
BigInt.lt(a: BigInt, b: BigInt) -> boolean
BigInt.lte(a: BigInt, b: BigInt) -> boolean
BigInt.isZero(a: BigInt) -> boolean
BigInt.cmp(a: BigInt, b: BigInt) -> number  -- -1, 0, 1

-- Arithmetic
BigInt.add(a: BigInt, b: BigInt) -> BigInt
BigInt.sub(a: BigInt, b: BigInt) -> BigInt
BigInt.mul(a: BigInt, b: BigInt) -> BigInt
BigInt.div(a: BigInt, b: BigInt) -> BigInt
BigInt.mod(a: BigInt, b: BigInt) -> BigInt
BigInt.divmod(a: BigInt, b: BigInt) -> (BigInt, BigInt)

-- Bitwise
BigInt.shl(a: BigInt, bits: number) -> BigInt
BigInt.shr(a: BigInt, bits: number) -> BigInt
BigInt.band(a: BigInt, b: BigInt) -> BigInt
BigInt.bor(a: BigInt, b: BigInt) -> BigInt
BigInt.bitLength(a: BigInt) -> number
BigInt.getBit(a: BigInt, index: number) -> number

-- Modular arithmetic
BigInt.addmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.submod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.mulmod(a: BigInt, b: BigInt, m: BigInt) -> BigInt
BigInt.powmod(a: BigInt, e: BigInt, m: BigInt) -> BigInt
BigInt.invmod(a: BigInt, m: BigInt) -> BigInt

-- Barrett reduction (optimized modular multiplication)
BigInt.createBarrettCtx(m: BigInt) -> BarrettCtx
BigInt.mulmodB(a: BigInt, b: BigInt, ctx: BarrettCtx) -> BigInt
```

#### 3.1.2 StarkField

Modular arithmetic over the Stark prime field P = 2^251 + 17 * 2^192 + 1.

**Design:**
- Dedicated field element type backed by buffer (not generic BigInt)
- Optimized reduction exploiting the sparse structure of P
- Pre-computed Barrett context for P
- All operations return field elements (automatically reduced mod P)

**API:**
```lua
StarkField.P -> BigInt  -- the field prime

-- Constructors
StarkField.fromHex(hex: string) -> Felt
StarkField.fromNumber(n: number) -> Felt
StarkField.zero() -> Felt
StarkField.one() -> Felt

-- Arithmetic (all mod P)
StarkField.add(a: Felt, b: Felt) -> Felt
StarkField.sub(a: Felt, b: Felt) -> Felt
StarkField.mul(a: Felt, b: Felt) -> Felt
StarkField.square(a: Felt) -> Felt
StarkField.neg(a: Felt) -> Felt
StarkField.inv(a: Felt) -> Felt        -- Fermat's little theorem: a^(P-2)
StarkField.sqrt(a: Felt) -> Felt?      -- Tonelli-Shanks or direct

-- Conversions
StarkField.toHex(a: Felt) -> string
StarkField.toBigInt(a: Felt) -> BigInt
StarkField.eq(a: Felt, b: Felt) -> boolean
StarkField.isZero(a: Felt) -> boolean
```

#### 3.1.3 StarkScalarField

Arithmetic modulo the curve order N (for ECDSA scalar operations).

Same API pattern as StarkField but with modulus N instead of P.

```lua
StarkScalarField.N -> BigInt  -- the curve order
```

#### 3.1.4 StarkCurve

Elliptic curve operations on the Stark curve: y^2 = x^3 + x + beta (short Weierstrass, alpha=1).

**Design:**
- Internal representation: Jacobian coordinates (X, Y, Z) to avoid field inversions
- Batch conversion to affine using Montgomery's trick
- Double-and-add scalar multiplication
- Pre-computed generator point and lookup tables for Pedersen

**Constants:**
```
P  = 2^251 + 17 * 2^192 + 1                    (field prime)
N  = 0x0800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f  (curve order)
G  = (generator x, generator y)                  (base point)
alpha = 1
beta  = 0x06f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89
```

**API:**
```lua
-- Point type
type Point = { x: Felt, y: Felt }
type JacobianPoint = { x: Felt, y: Felt, z: Felt }

-- Constants
StarkCurve.P -> BigInt
StarkCurve.N -> BigInt
StarkCurve.G -> Point     -- generator
StarkCurve.ALPHA -> Felt
StarkCurve.BETA -> Felt

-- Point operations
StarkCurve.pointAdd(p1: Point, p2: Point) -> Point
StarkCurve.pointDouble(p: Point) -> Point
StarkCurve.scalarMul(k: BigInt, p: Point) -> Point
StarkCurve.isOnCurve(p: Point) -> boolean
StarkCurve.isInfinity(p: Point) -> boolean

-- Key derivation
StarkCurve.getPublicKey(privateKey: BigInt) -> Point  -- k * G
```

#### 3.1.5 Poseidon

Poseidon hash function over the Stark field using Hades permutation.

**Design:**
- State width = 3, rate = 2, capacity = 1
- 91 rounds: 4 full + 83 partial + 4 full
- Pre-computed round constants and MDS matrix
- Sponge construction for variable-length input

**API:**
```lua
-- Core hash
Poseidon.hash(a: Felt, b: Felt) -> Felt              -- h(a, b)
Poseidon.hashSingle(x: Felt) -> Felt                  -- h(x, 0, 1)
Poseidon.hashMany(values: {Felt}) -> Felt             -- sponge with rate=2
```

#### 3.1.6 Pedersen

Pedersen hash using elliptic curve point operations on the Stark curve.

**Design:**
- Uses 4 pre-computed constant base points (P0, P1, P2, P3)
- Processes 248-bit + 4-bit chunks of inputs
- Used for legacy operations and some address computations

**API:**
```lua
Pedersen.hash(a: Felt, b: Felt) -> Felt
```

#### 3.1.7 Keccak

Keccak-256 implementation (Ethereum/Starknet variant, NOT SHA-3).

**Design:**
- Full Keccak-f[1600] permutation (24 rounds)
- 64-bit lanes via {hi, lo} 32-bit pairs (Luau lacks native 64-bit)
- Starknet selector: keccak256 masked to 250 bits
- Domain separation byte: 0x01 (NOT SHA-3's 0x06)

**API:**
```lua
Keccak.keccak256(data: buffer) -> buffer              -- raw keccak-256
Keccak.snKeccak(data: buffer) -> Felt                 -- starknet keccak (250-bit mask)
Keccak.getSelectorFromName(name: string) -> Felt      -- function selector
```

#### 3.1.8 SHA256

SHA-256 hash and HMAC-SHA-256 for RFC 6979 nonce generation.

**API:**
```lua
SHA256.hash(data: buffer) -> buffer
SHA256.hmac(key: buffer, message: buffer) -> buffer
```

#### 3.1.9 ECDSA

Stark ECDSA signing with RFC 6979 deterministic nonce generation.

**API:**
```lua
-- Signing
ECDSA.sign(messageHash: Felt, privateKey: BigInt) -> { r: Felt, s: Felt }
ECDSA.verify(messageHash: Felt, publicKey: Point, signature: { r: Felt, s: Felt }) -> boolean

-- Nonce generation (internal, exposed for testing)
ECDSA.generateK(messageHash: Felt, privateKey: BigInt) -> BigInt
```

---

### 3.2 signer -- Signing Abstraction

#### 3.2.1 SignerInterface

Abstract protocol that all signer implementations must follow.

```lua
type SignerInterface = {
    getPubKey: (self: SignerInterface) -> Point,
    signRaw: (self: SignerInterface, msgHash: Felt) -> { r: Felt, s: Felt },
    signTransaction: (self: SignerInterface, txHash: Felt) -> { string },  -- signature as felt array
}
```

#### 3.2.2 StarkSigner

Default signer implementation using Stark curve ECDSA.

```lua
-- Constructor
StarkSigner.new(privateKey: string) -> StarkSigner  -- hex string

-- Methods (implements SignerInterface)
signer:getPubKey() -> Point
signer:signRaw(msgHash: Felt) -> { r: Felt, s: Felt }
signer:signTransaction(txHash: Felt) -> { string }
signer:getPublicKeyHex() -> string
```

---

### 3.3 provider -- RPC Connectivity

#### 3.3.1 RpcProvider

JSON-RPC client for communicating with Starknet nodes via Roblox HttpService.

**Design:**
- Uses HttpService:RequestAsync for all HTTP calls
- All methods return Promises (via roblox-lua-promise)
- Built-in rate limiting to respect Roblox's 500 req/min limit
- Configurable RPC endpoint URL
- JSON-RPC 2.0 compliant request/response handling

**Constructor:**
```lua
RpcProvider.new(config: {
    nodeUrl: string,                    -- RPC endpoint URL
    headers: { [string]: string }?,     -- optional custom headers (e.g. API key)
    maxRequestsPerMinute: number?,      -- rate limit (default: 450, leaving headroom)
    retryAttempts: number?,             -- retry on failure (default: 3)
    retryDelay: number?,                -- seconds between retries (default: 1)
}) -> RpcProvider
```

**Core RPC Methods (MVP):**
```lua
-- Network
provider:getChainId() -> Promise<string>
provider:getBlockNumber() -> Promise<number>
provider:getSpecVersion() -> Promise<string>

-- Account
provider:getNonce(contractAddress: string, blockId: string?) -> Promise<string>

-- Transactions
provider:call(request: CallRequest, blockId: string?) -> Promise<{string}>
provider:estimateFee(transactions: {Transaction}, simulationFlags: {string}?) -> Promise<{FeeEstimate}>
provider:addInvokeTransaction(invokeTx: InvokeTransaction) -> Promise<string>  -- tx hash
provider:getTransactionReceipt(txHash: string) -> Promise<TransactionReceipt>
provider:getTransactionStatus(txHash: string) -> Promise<TransactionStatus>

-- Blocks
provider:getBlockWithTxHashes(blockId: string?) -> Promise<Block>

-- Contract
provider:getClassHashAt(contractAddress: string, blockId: string?) -> Promise<string>
provider:getStorageAt(contractAddress: string, key: string, blockId: string?) -> Promise<string>

-- Events
provider:getEvents(filter: EventFilter) -> Promise<EventsChunk>

-- Utility
provider:waitForTransaction(txHash: string, options: {
    retryInterval: number?,    -- seconds (default: 5)
    maxAttempts: number?,      -- max polls (default: 30)
}?) -> Promise<TransactionReceipt>
```

**Internal:**
```lua
-- Raw RPC call (for custom/unsupported methods)
provider:fetch(method: string, params: any) -> Promise<any>
```

#### 3.3.2 RpcTypes

Type definitions for all RPC request/response objects.

```lua
type CallRequest = {
    contract_address: string,
    entry_point_selector: string,
    calldata: { string },
}

type FeeEstimate = {
    gas_consumed: string,
    gas_price: string,
    overall_fee: string,
    data_gas_consumed: string,
    data_gas_price: string,
    unit: string,
}

type TransactionReceipt = {
    transaction_hash: string,
    actual_fee: { amount: string, unit: string },
    execution_status: string,  -- "SUCCEEDED" | "REVERTED"
    finality_status: string,   -- "ACCEPTED_ON_L2" | "ACCEPTED_ON_L1"
    block_hash: string?,
    block_number: number?,
    events: { Event },
    revert_reason: string?,
}

type TransactionStatus = {
    finality_status: string,
    execution_status: string?,
}

type Event = {
    from_address: string,
    keys: { string },
    data: { string },
}

type EventFilter = {
    from_block: string?,
    to_block: string?,
    address: string?,
    keys: { { string } }?,
    chunk_size: number?,
    continuation_token: string?,
}

type EventsChunk = {
    events: { Event },
    continuation_token: string?,
}
```

---

### 3.4 tx -- Transaction Building

#### 3.4.1 CalldataEncoder

Serializes Luau values into Starknet calldata (flat felt arrays).

**Encoding Rules:**
| Cairo Type     | Encoding                              | Felt Count |
|---------------|---------------------------------------|------------|
| `felt252`     | `[value]`                             | 1          |
| `u256`        | `[low_128, high_128]`                 | 2          |
| `address`     | `[value]`                             | 1          |
| `bool`        | `[0]` or `[1]`                        | 1          |
| `Array<T>`    | `[len, elem0..., elem1..., ...]`      | 1 + n*T    |
| `Struct`      | `[field0_felts..., field1_felts...]`  | sum(fields)|

**Multicall Encoding (for `__execute__`):**
```
[num_calls, to_0, selector_0, calldata_len_0, ...calldata_0, to_1, ...]
```

**API:**
```lua
CalldataEncoder.encodeFelt(value: string | number) -> { string }
CalldataEncoder.encodeU256(value: string) -> { string }
CalldataEncoder.encodeBool(value: boolean) -> { string }
CalldataEncoder.encodeArray(values: { string }) -> { string }
CalldataEncoder.encodeMulticall(calls: { Call }) -> { string }

type Call = {
    contractAddress: string,
    entrypoint: string,
    calldata: { string },
}
```

#### 3.4.2 TransactionHash

Computes V3 INVOKE transaction hashes using Poseidon.

**V3 Hash Structure:**
```
poseidonHashMany([
    "invoke",                           -- tx type prefix (ASCII-encoded felt)
    3,                                  -- version
    sender_address,
    fee_field_hash,                     -- poseidonHashMany([tip, l1_gas_bound, l2_gas_bound, l1_data_gas_bound])
    poseidonHashMany(paymaster_data),
    chain_id,
    nonce,
    da_mode_hash,                       -- (nonce_da_mode << 32) | fee_da_mode
    poseidonHashMany(account_deployment_data),
    poseidonHashMany(calldata)
])
```

**Resource Bounds Encoding:**
```
(resource_name_felt << 192) | (max_amount << 128) | max_price_per_unit
```

**API:**
```lua
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

type ResourceBounds = {
    l1Gas: { maxAmount: string, maxPricePerUnit: string },
    l2Gas: { maxAmount: string, maxPricePerUnit: string },
    l1DataGas: { maxAmount: string, maxPricePerUnit: string }?,
}
```

#### 3.4.3 TransactionBuilder

High-level transaction building and submission.

**API:**
```lua
TransactionBuilder.new(provider: RpcProvider) -> TransactionBuilder

-- Build, sign, and submit in one call
builder:execute(account: Account, calls: { Call }, options: ExecuteOptions?) -> Promise<string>

-- Step-by-step
builder:buildInvoke(account: Account, calls: { Call }, options: ExecuteOptions?) -> Promise<SignedTransaction>
builder:submitTransaction(signedTx: SignedTransaction) -> Promise<string>

-- Fee estimation
builder:estimateFee(account: Account, calls: { Call }) -> Promise<FeeEstimate>

-- Wait for receipt
builder:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>

type ExecuteOptions = {
    resourceBounds: ResourceBounds?,   -- override fee bounds
    nonce: string?,                    -- override nonce
    tip: string?,
    skipFeeEstimation: boolean?,       -- use provided resourceBounds directly
}

type WaitOptions = {
    retryInterval: number?,            -- seconds (default: 5)
    maxAttempts: number?,              -- (default: 30)
}
```

#### 3.4.4 TransactionTypes

```lua
type InvokeTransactionV3 = {
    type: "INVOKE",
    version: "0x3",
    sender_address: string,
    calldata: { string },
    signature: { string },
    nonce: string,
    resource_bounds: {
        l1_gas: { max_amount: string, max_price_per_unit: string },
        l2_gas: { max_amount: string, max_price_per_unit: string },
    },
    tip: string,
    paymaster_data: { string },
    nonce_data_availability_mode: string,
    fee_data_availability_mode: string,
    account_deployment_data: { string },
}
```

---

### 3.5 wallet -- Account Management

#### 3.5.1 Account

Represents a Starknet account with signing capabilities.

**Design:**
- Wraps a signer, provider, and account address
- Provides high-level methods for common operations
- Handles nonce management automatically

**API:**
```lua
Account.new(config: {
    provider: RpcProvider,
    address: string,
    signer: StarkSigner | SignerInterface,
}) -> Account

-- From private key (derives address using OZ class hash)
Account.fromPrivateKey(config: {
    provider: RpcProvider,
    privateKey: string,          -- hex
    classHash: string?,          -- defaults to OZ
}) -> Account

-- Address derivation (static, no provider needed)
Account.computeAddress(config: {
    publicKey: string,
    classHash: string?,          -- defaults to OZ
    constructorCalldata: { string }?,
    salt: string?,               -- defaults to public key
}) -> string

-- Properties
account.address -> string
account.publicKey -> string
account.signer -> SignerInterface
account.provider -> RpcProvider

-- Methods
account:getNonce() -> Promise<string>
account:getBalance(tokenAddress: string?) -> Promise<string>  -- defaults to STRK

-- Transaction execution (convenience wrapper over TransactionBuilder)
account:execute(calls: { Call }, options: ExecuteOptions?) -> Promise<string>
account:estimateFee(calls: { Call }) -> Promise<FeeEstimate>
```

#### 3.5.2 AccountTypes

Pre-defined class hashes for common account implementations.

```lua
AccountTypes.OZ_LATEST = "0x061dac032f228abef9c6626f..."       -- OpenZeppelin latest
AccountTypes.ARGENT = "0x01a736d6ed154502257f02b1ccdf..."       -- Argent X
AccountTypes.BRAAVOS = "0x..."                                   -- Braavos
```

#### 3.5.3 NonceManager

Tracks nonces locally to avoid fetching from RPC on every transaction.

```lua
NonceManager.new(provider: RpcProvider) -> NonceManager

manager:getNonce(address: string) -> Promise<string>
manager:incrementNonce(address: string) -> ()
manager:invalidate(address: string) -> ()  -- force re-fetch
```

---

### 3.6 contract -- Contract Interaction

#### 3.6.1 Contract

ABI-driven smart contract interface.

**Design:**
- Reads ABI at construction time
- Generates callable methods via `__index` metamethod
- Supports both read (call) and write (invoke) operations
- Methods are determined by ABI: view functions are calls, external functions are invokes

**API:**
```lua
Contract.new(config: {
    abi: ABI,
    address: string,
    provider: RpcProvider,
    account: Account?,          -- required for write operations
}) -> Contract

-- Dynamic methods (generated from ABI)
contract:functionName(arg1, arg2, ...) -> Promise<result>

-- Explicit call/invoke
contract:call(method: string, args: { any }?) -> Promise<{ string }>
contract:invoke(method: string, args: { any }?, options: ExecuteOptions?) -> Promise<string>

-- Build a Call object for multicall batching
contract:populate(method: string, args: { any }?) -> Call

-- Utility
contract:attach(newAddress: string) -> Contract  -- same ABI, different address
```

#### 3.6.2 AbiParser

Parses Starknet ABI JSON into usable type information.

```lua
AbiParser.parse(abiJson: { any }) -> ParsedABI

type ParsedABI = {
    functions: { [string]: FunctionABI },
    events: { [string]: EventABI },
    structs: { [string]: StructABI },
    enums: { [string]: EnumABI },
}

type FunctionABI = {
    name: string,
    type: "function" | "l1_handler",
    inputs: { { name: string, type: string } },
    outputs: { { type: string } },
    state_mutability: "view" | "external",
}
```

#### 3.6.3 Presets

**ERC20:**
```lua
ERC20.new(address: string, provider: RpcProvider, account: Account?) -> ERC20

erc20:name() -> Promise<string>
erc20:symbol() -> Promise<string>
erc20:decimals() -> Promise<number>
erc20:totalSupply() -> Promise<string>
erc20:balanceOf(owner: string) -> Promise<string>
erc20:allowance(owner: string, spender: string) -> Promise<string>
erc20:transfer(recipient: string, amount: string) -> Promise<string>
erc20:approve(spender: string, amount: string) -> Promise<string>
erc20:transferFrom(sender: string, recipient: string, amount: string) -> Promise<string>
```

**ERC721:**
```lua
ERC721.new(address: string, provider: RpcProvider, account: Account?) -> ERC721

erc721:name() -> Promise<string>
erc721:symbol() -> Promise<string>
erc721:ownerOf(tokenId: string) -> Promise<string>
erc721:balanceOf(owner: string) -> Promise<string>
erc721:getApproved(tokenId: string) -> Promise<string>
erc721:isApprovedForAll(owner: string, operator: string) -> Promise<boolean>
erc721:transferFrom(from: string, to: string, tokenId: string) -> Promise<string>
erc721:approve(to: string, tokenId: string) -> Promise<string>
```

---

## 4. Async Pattern

All network-bound operations use roblox-lua-promise. The SDK follows these conventions:

### 4.1 Promise Usage

```lua
local Starknet = require(path.to.starknet-luau)

-- Creating a provider
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://free-rpc.nethermind.io/sepolia-juno/",
})

-- Reading a contract (promise-based)
provider:getBlockNumber():andThen(function(blockNumber)
    print("Current block:", blockNumber)
end):catch(function(err)
    warn("Failed:", err)
end)

-- Chaining operations
local account = Starknet.wallet.Account.fromPrivateKey({
    provider = provider,
    privateKey = "0x...",
})

account:execute({
    {
        contractAddress = "0x...",
        entrypoint = "transfer",
        calldata = { recipientAddress, amountLow, amountHigh },
    }
}):andThen(function(txHash)
    return provider:waitForTransaction(txHash)
end):andThen(function(receipt)
    print("Transaction confirmed:", receipt.transaction_hash)
end):catch(function(err)
    warn("Transaction failed:", err)
end)
```

### 4.2 Synchronous Crypto

Crypto operations (hashing, signing, key derivation) are **synchronous** since they are CPU-bound and don't involve network I/O. They return values directly, not Promises.

```lua
local hash = Starknet.crypto.Poseidon.hash(a, b)        -- synchronous
local sig = signer:signRaw(msgHash)                       -- synchronous
local address = Starknet.wallet.Account.computeAddress({  -- synchronous
    publicKey = "0x...",
})
```

---

## 5. Error Handling

### 5.1 Error Types

```lua
type StarknetError = {
    type: string,       -- error category
    message: string,    -- human-readable description
    code: number?,      -- RPC error code (if applicable)
    data: any?,         -- additional error data
}

-- Error categories
"RPC_ERROR"            -- JSON-RPC error response
"NETWORK_ERROR"        -- HTTP/connection failure
"RATE_LIMIT"           -- Roblox 500 req/min exceeded
"TIMEOUT"              -- Request or transaction timed out
"INVALID_ARGUMENT"     -- Bad input to SDK function
"SIGNING_ERROR"        -- Signature computation failed
"TRANSACTION_REVERTED" -- Transaction executed but reverted
"ABI_ERROR"            -- ABI parsing or encoding error
```

### 5.2 Error Propagation

- Network operations propagate errors through Promise rejection
- Synchronous operations throw on invalid input (checked via assertions)
- All RPC errors include the original JSON-RPC error code and message

---

## 6. Dependencies

### 6.1 Required Dependencies

| Package | Wally ID | Purpose |
|---------|----------|---------|
| roblox-lua-promise | `evaera/promise@^3.1.0` | Async/promise handling |

### 6.2 Peer Dependencies

| Package | Wally ID | Purpose |
|---------|----------|---------|
| rbx-cryptography | `daily3014/cryptography@^3.1.0` | SHA-256, Keccak base (optional -- SDK includes its own implementations but can delegate if peer is present) |

### 6.3 Dev Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| rojo | 7.6.x | File-to-Roblox sync |
| wally | 0.3.x | Package management |
| lune | 0.10.x | Test runner |
| selene | 0.30.x | Linting |
| stylua | 2.3.x | Formatting |
| wally-package-types | 1.6.x | IDE type generation |

---

## 7. Testing Strategy

### 7.1 Approach

All tests run via Lune outside of Roblox, enabling fast iteration without Studio. Each module has a corresponding `.spec.luau` file.

### 7.2 Test Vectors

Crypto tests use known-good values generated by running equivalent operations through starknet.js. Test vectors are stored in `tests/fixtures/test-vectors.luau` and cover:

- BigInt arithmetic edge cases
- Field element operations (add, mul, inv) against known results
- Poseidon hash for specific inputs matching starknet.js `hash.computePoseidonHash`
- Pedersen hash matching starknet.js `hash.computePedersenHash`
- Keccak/selector matching starknet.js `hash.getSelectorFromName`
- ECDSA signatures matching starknet.js `ec.starkCurve.sign`
- Transaction hashes matching starknet.js `hash.calculateInvokeTransactionHash`
- Address derivation matching starknet.js `hash.calculateContractAddressFromHash`

### 7.3 Test Runner

Custom Lune-based test runner (from roblox-adv-testing pattern) with `describe()`, `it()`, `expect()` API:

```lua
describe("Poseidon", function()
    it("should hash two felts correctly", function()
        local result = Poseidon.hash(
            StarkField.fromHex("0x03"),
            StarkField.fromHex("0x05")
        )
        expect(StarkField.toHex(result)).toBe("0x...")  -- value from starknet.js
    end)
end)
```

### 7.4 Integration Tests

Integration tests (in a separate `tests/integration/` directory) that make actual RPC calls to Sepolia:

- Read block number
- Call a deployed contract
- Full transaction flow (build, sign, submit, wait)

These are gated behind an environment variable (`STARKNET_RPC_URL`) and skipped in CI by default.

---

## 8. Configuration

### 8.1 Network Presets

```lua
Starknet.networks = {
    mainnet = {
        chainId = "0x534e5f4d41494e",  -- "SN_MAIN"
        rpcUrl = "https://free-rpc.nethermind.io/mainnet-juno/",
    },
    sepolia = {
        chainId = "0x534e5f5345504f4c4941",  -- "SN_SEPOLIA"
        rpcUrl = "https://free-rpc.nethermind.io/sepolia-juno/",
    },
}
```

### 8.2 Constants

```lua
Starknet.constants = {
    INVOKE_TX_PREFIX = 0x696e766f6b65,              -- "invoke"
    DECLARE_TX_PREFIX = 0x6465636c617265,            -- "declare"
    DEPLOY_ACCOUNT_TX_PREFIX = 0x6465706c6f795f6163636f756e74,
    TRANSACTION_VERSION_3 = 0x3,
    STRK_TOKEN_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    ETH_TOKEN_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
}
```

---

## 9. Usage Examples

### 9.1 Read ERC-20 Balance

```lua
local Starknet = require(path.to.starknet-luau)

local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://free-rpc.nethermind.io/sepolia-juno/",
})

local strk = Starknet.contract.presets.ERC20.new(
    Starknet.constants.STRK_TOKEN_ADDRESS,
    provider
)

strk:balanceOf("0x123..."):andThen(function(balance)
    print("STRK Balance:", balance)
end)
```

### 9.2 Send a Transaction

```lua
local account = Starknet.wallet.Account.fromPrivateKey({
    provider = provider,
    privateKey = "0xYOUR_PRIVATE_KEY",
})

local strk = Starknet.contract.presets.ERC20.new(
    Starknet.constants.STRK_TOKEN_ADDRESS,
    provider,
    account
)

strk:transfer("0xRECIPIENT", "1000000000000000000"):andThen(function(txHash)
    print("Transfer submitted:", txHash)
    return provider:waitForTransaction(txHash)
end):andThen(function(receipt)
    if receipt.execution_status == "SUCCEEDED" then
        print("Transfer confirmed!")
    else
        warn("Transfer reverted:", receipt.revert_reason)
    end
end):catch(function(err)
    warn("Transfer failed:", err)
end)
```

### 9.3 Multicall (Batch Operations)

```lua
local gameContract = Starknet.contract.Contract.new({
    abi = gameAbi,
    address = "0xGAME_CONTRACT",
    provider = provider,
    account = account,
})

-- Build multiple calls
local call1 = gameContract:populate("move_player", { "0x5", "0xA" })
local call2 = gameContract:populate("attack", { "0x3" })

-- Execute atomically in one transaction
account:execute({ call1, call2 }):andThen(function(txHash)
    print("Game actions submitted:", txHash)
end)
```

### 9.4 NFT Ownership Check

```lua
local nft = Starknet.contract.presets.ERC721.new("0xNFT_CONTRACT", provider)

nft:balanceOf(playerWalletAddress):andThen(function(balance)
    if tonumber(balance) > 0 then
        -- Grant access to exclusive area
        grantAccess(player)
    else
        -- Show "NFT required" message
        denyAccess(player)
    end
end)
```
