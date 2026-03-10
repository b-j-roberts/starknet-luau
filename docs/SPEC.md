# starknet-luau SDK Specification

## 1. Overview

### 1.1 Project Description

**starknet-luau** is a pure Luau SDK for interacting with the Starknet blockchain from Roblox games. It provides cryptographic primitives, account management, transaction building/signing, contract interaction, paymaster-sponsored transactions, and RPC connectivity -- all implemented in Luau with no external native dependencies.

### 1.2 Goals

- Enable Roblox game developers to integrate Starknet onchain mechanics (tokens, NFTs, leaderboards, game state)
- Provide a complete, self-contained Starknet SDK in pure Luau
- Build/sign/submit transactions entirely from the Roblox game server
- Support gasless player onboarding via SNIP-29 paymaster integration
- Offer a clean, well-documented API inspired by starknet.js
- Ship with comprehensive Lune-based tests cross-referenced against starknet.js expected values
- Distribute as a Wally and pesde package for easy installation

### 1.3 Target Audience

- Roblox game developers who want to add onchain features (NFT gating, token rewards, onchain leaderboards, verifiable game state)
- Starknet ecosystem developers building cross-platform tooling
- Developers building Autonomous World / Fully Onchain Game (FOCG) experiences on Roblox

### 1.4 Design Principles

1. **Pure Luau** -- No native FFI, no external processes. Everything runs within Roblox's scripting environment.
2. **Performance-first crypto** -- Use buffer-based field arithmetic with f64 limbs and `--!native` / `--!optimize 2` pragmas.
3. **Promise-based async** -- All network operations return Promises via roblox-lua-promise.
4. **Modular** -- Each submodule (crypto, signer, provider, tx, wallet, contract, paymaster, errors) is independently usable.
5. **Testable** -- Every module has Lune tests with expected values cross-referenced from starknet.js. Dependency injection for HTTP, clock, and defer enables pure-unit testing.
6. **Minimal dependencies** -- Only depends on roblox-lua-promise.

---

## 2. Architecture

### 2.1 High-Level Architecture

```
+-----------------------------------------------------------------------+
|                          starknet-luau SDK                            |
|                                                                       |
|  +-----------------+  +------------------+  +-----------------------+ |
|  |    contract     |  |     wallet       |  |      paymaster        | |
|  | (ABI codec,     |  | (Account,        |  | (SNIP-29 RPC,         | |
|  |  call, invoke,  |  |  key mgmt,       |  |  AVNU, policy,        | |
|  |  ERC20/721)     |  |  SNIP-9/12,      |  |  budget, sponsored    | |
|  |                 |  |  onboarding)     |  |  executor)            | |
|  +-------+---------+  +--------+---------+  +----------+------------+ |
|          |                     |                        |             |
|  +-------+----------+  +-------+----------+             |             |
|  |       tx         |  |     signer       |             |             |
|  | (build, hash,    |  | (StarkSigner,    |             |             |
|  |  calldata,       |  |  RFC 6979)       |             |             |
|  |  fee estimate,   |  +-------+----------+             |             |
|  |  deploy acct)    |          |                        |             |
|  +-------+----------+          |                        |             |
|          |                     |                        |             |
|  +-------+---------------------+----+       +-----------+----------+  |
|  |                 provider         |       |        errors        |  |
|  |  (JSON-RPC, queue, cache,        |       | (typed hierarchy,    |  |
|  |   nonce mgr, event polling)      |       |  error codes)        |  |
|  +-------+--------------------------+       +----------------------+  |
|          |                                                            |
|  +-------+----------------------------------------------------------+ |
|  |                    crypto                                        | |
|  | (BigInt, FieldFactory, StarkField, StarkScalarField, StarkCurve, | |
|  |  Poseidon, Pedersen, Keccak, SHA256, ECDSA)                      | |
|  +------------------------------------------------------------------+ |
|                                                                       |
|  +------------------------------------------------------------------+ |
|  |                shared (internal, not exported)                   | |
|  | (interfaces, HexUtils, BufferUtils, ByteArray, TestableDefaults) | |
|  +------------------------------------------------------------------+ |
+-----------------------------------------------------------------------+
                              |
                    Roblox HttpService
                              |
               Starknet RPC Node / Paymaster RPC
```

### 2.2 Module Dependency Graph

```
contract ──> tx ──> crypto
    |         |        ^
    |         v        |
    +──> wallet ──> signer ──> crypto
    |       |  |
    v       v  v
  provider  provider
    ^
    |
paymaster ──> wallet ──> provider

errors ──────── cross-cutting (used by all modules)
shared ──────── cross-cutting (interfaces, utilities)
```

- **crypto** is the foundation layer with zero SDK dependencies
- **signer** depends on crypto for ECDSA operations
- **provider** depends on crypto (for error types) and shared (for interfaces)
- **tx** depends on crypto (for hashing, calldata encoding) and provider (for nonce, fee estimation)
- **wallet** depends on signer, provider, and crypto (for address derivation)
- **contract** depends on tx (for building calls), wallet (for signing), and provider (for reading)
- **paymaster** depends on provider (JSON-RPC base), wallet (account integration), and tx (calldata)
- **errors** is cross-cutting, used by all modules for structured error propagation
- **shared** provides interface types (breaking circular dependencies) and utility functions

### 2.3 Repository Structure

```
starknet-luau/
├── src/
│   ├── init.luau                        # Main entry point / barrel export (9 namespaces)
│   ├── constants.luau                   # Chain IDs, class hashes, token addresses, SDK version
│   ├── crypto/
│   │   ├── init.luau                    # Crypto barrel export
│   │   ├── BigInt.luau                  # Buffer-based arbitrary precision integers (f64 limbs)
│   │   ├── FieldFactory.luau            # Parameterized field constructor (DRY StarkField/ScalarField)
│   │   ├── StarkField.luau              # GF(P) arithmetic for Stark prime
│   │   ├── StarkScalarField.luau        # Arithmetic modulo curve order N
│   │   ├── StarkCurve.luau              # Short Weierstrass EC operations (Jacobian coords)
│   │   ├── PoseidonConstants.luau       # Pre-computed round constants and MDS matrix
│   │   ├── Poseidon.luau                # Poseidon hash (Hades permutation, sponge)
│   │   ├── Pedersen.luau                # Pedersen hash (EC-based, for address derivation)
│   │   ├── Keccak.luau                  # Keccak-256 (sn_keccak for selectors)
│   │   ├── SHA256.luau                  # SHA-256 + HMAC-SHA256 (for RFC 6979)
│   │   └── ECDSA.luau                   # Stark ECDSA with RFC 6979, windowed scalarMul
│   ├── signer/
│   │   ├── init.luau                    # Signer barrel export
│   │   └── StarkSigner.luau             # Stark curve ECDSA signer
│   ├── provider/
│   │   ├── init.luau                    # Provider barrel export
│   │   ├── JsonRpcClient.luau           # Shared JSON-RPC base (rate limiting, retry)
│   │   ├── RpcProvider.luau             # Starknet JSON-RPC client (22+ methods)
│   │   ├── RpcTypes.luau                # Request/response type definitions
│   │   ├── NonceManager.luau            # Reserve/confirm/reject nonce pattern
│   │   ├── RequestQueue.luau            # 3-bucket priority queue with JSON-RPC batching
│   │   ├── ResponseCache.luau           # LRU cache with per-method TTL
│   │   └── EventPoller.luau             # Event polling with DataStore persistence
│   ├── tx/
│   │   ├── init.luau                    # Transaction barrel export
│   │   ├── CallData.luau                # Calldata encoding (felt, u256, multicall, selectors)
│   │   ├── TransactionHash.luau         # V3 INVOKE + DEPLOY_ACCOUNT hash (Poseidon)
│   │   └── TransactionBuilder.luau      # Full transaction orchestration pipeline
│   ├── wallet/
│   │   ├── init.luau                    # Wallet barrel export
│   │   ├── Account.luau                 # Account derivation, execution, deployment, SNIP-12
│   │   ├── AccountType.luau             # OZ/Argent/Braavos account type constructors
│   │   ├── AccountFactory.luau          # Multi-account creation, batch deploy
│   │   ├── TypedData.luau               # SNIP-12 typed data (LEGACY Pedersen + ACTIVE Poseidon)
│   │   ├── OutsideExecution.luau        # SNIP-9 meta-transactions (V1/V2/V3)
│   │   ├── KeyStore.luau                # Encrypted DataStore key persistence
│   │   └── OnboardingManager.luau       # Player account lifecycle management
│   ├── contract/
│   │   ├── init.luau                    # Contract barrel export
│   │   ├── AbiCodec.luau                # Recursive Cairo type encoder/decoder
│   │   ├── Contract.luau                # ABI-driven contract interface
│   │   ├── PresetFactory.luau           # DRY factory for ERC preset construction
│   │   ├── ERC20.luau                   # ERC-20 token preset
│   │   └── ERC721.luau                  # ERC-721 NFT preset
│   ├── errors/
│   │   ├── init.luau                    # Errors barrel export
│   │   ├── StarknetError.luau           # Typed error hierarchy with factory constructors
│   │   └── ErrorCodes.luau              # Numeric error code constants (1000-8010)
│   ├── paymaster/
│   │   ├── init.luau                    # Paymaster barrel export
│   │   ├── PaymasterRpc.luau            # SNIP-29 paymaster JSON-RPC client
│   │   ├── AvnuPaymaster.luau           # AVNU paymaster integration
│   │   ├── PaymasterPolicy.luau         # Sponsorship policy engine
│   │   ├── PaymasterBudget.luau         # Per-player budget tracking with DataStore
│   │   └── SponsoredExecutor.luau       # Sponsored execution orchestrator
│   └── shared/                          # Internal utilities (not exported via barrel)
│       ├── interfaces.luau              # Interface-only types (breaks circular deps)
│       ├── HexUtils.luau                # Hex encoding/decoding
│       ├── BufferUtils.luau             # Buffer manipulation (concat, slice, compare)
│       ├── ByteArray.luau               # Cairo ByteArray encoding (31-byte chunks)
│       └── TestableDefaults.luau        # Injectable defaults (HttpService, task.defer, clock)
├── tests/
│   ├── run.luau                         # Lune test runner (parallel, timing, hooks)
│   ├── init.spec.luau                   # Barrel export smoke tests (69 tests)
│   ├── constants.spec.luau              # Constants validation
│   ├── crypto/
│   │   ├── fieldTestSuite.luau          # Shared field test suite
│   │   ├── BigInt.spec.luau             # 94 tests
│   │   ├── StarkField.spec.luau         # 51 tests
│   │   ├── StarkScalarField.spec.luau   # 54 tests
│   │   ├── StarkCurve.spec.luau         # 53 tests
│   │   ├── Poseidon.spec.luau           # 22 tests
│   │   ├── Pedersen.spec.luau           # 17 tests
│   │   ├── Keccak.spec.luau             # 24 tests
│   │   ├── SHA256.spec.luau             # 31 tests
│   │   ├── ECDSA.spec.luau              # 37 tests
│   │   └── edge-cases.spec.luau         # 54 tests
│   ├── signer/
│   │   └── StarkSigner.spec.luau        # 21 tests
│   ├── provider/
│   │   ├── RpcProvider.spec.luau        # 59 tests
│   │   ├── JsonRpcClient.spec.luau      # 40 tests
│   │   ├── NonceManager.spec.luau       # 64 tests
│   │   ├── RequestQueue.spec.luau       # 82 tests
│   │   ├── RequestBatcher.spec.luau
│   │   ├── ResponseCache.spec.luau      # 89 tests
│   │   ├── EventPoller.spec.luau
│   │   └── getAllEvents.spec.luau
│   ├── tx/
│   │   ├── CallData.spec.luau
│   │   ├── TransactionHash.spec.luau    # 23+ tests
│   │   ├── TransactionBuilder.spec.luau # 36+ tests
│   │   └── DeployAccount.spec.luau      # 58+ tests
│   ├── wallet/
│   │   ├── Account.spec.luau            # 80+ tests
│   │   ├── AccountFactory.spec.luau     # 52 tests
│   │   ├── TypedData.spec.luau          # 43 tests
│   │   ├── OutsideExecution.spec.luau   # 82 tests
│   │   ├── KeyStore.spec.luau           # 72 tests
│   │   ├── OnboardingManager.spec.luau  # 37 tests
│   │   ├── PrefundingHelper.spec.luau   # 44 tests
│   │   └── BatchDeploy.spec.luau        # 53 tests
│   ├── contract/
│   │   ├── AbiCodec.spec.luau           # 109+ tests
│   │   ├── Contract.spec.luau           # 60+ tests
│   │   ├── ERC20.spec.luau              # 35 tests
│   │   ├── ERC721.spec.luau             # 41 tests
│   │   └── ContractEvents.spec.luau     # 47 tests
│   ├── paymaster/
│   │   ├── PaymasterRpc.spec.luau       # 67 tests
│   │   ├── AvnuPaymaster.spec.luau      # 61 tests
│   │   ├── PaymasterPolicy.spec.luau    # 66 tests
│   │   ├── PaymasterBudget.spec.luau    # 105 tests
│   │   └── SponsoredExecutor.spec.luau  # 78 tests
│   ├── shared/
│   │   ├── HexUtils.spec.luau
│   │   ├── BufferUtils.spec.luau
│   │   └── ByteArray.spec.luau
│   ├── errors/
│   │   └── StarknetError.spec.luau      # 42+ tests
│   ├── fixtures/
│   │   ├── test-vectors.luau            # Centralized test vectors (addresses, hashes, sigs)
│   │   └── cross-reference.spec.luau    # Cross-module starknet.js validation
│   ├── integration/
│   │   └── sepolia.spec.luau            # Live Sepolia integration tests
│   └── helpers/
│       ├── MockPromise.luau             # Synchronous Promise shim for Lune
│       ├── MockPromise.spec.luau        # MockPromise validation
│       └── TestUtils.luau               # Shared test infrastructure
├── examples/
│   ├── read-contract.luau               # Read ERC-20 balance
│   ├── send-transaction.luau            # Sign and submit a transfer
│   ├── nft-gate.luau                    # NFT ownership gating
│   ├── leaderboard.luau                 # Onchain leaderboard interaction
│   └── multicall.luau                   # Batch multiple contract calls
├── docs/
│   ├── SPEC.md                          # This file
│   ├── ROADMAP.md                       # Development roadmap
│   └── guides/                          # Usage guides
│       ├── quickstart.md
│       ├── accounts.md
│       ├── transactions.md
│       ├── contracts.md
│       ├── events.md
│       ├── paymaster.md
│       └── testing.md
├── default.project.json                 # Rojo project configuration
├── wally.toml                           # Wally package manifest
├── pesde.toml                           # pesde package manifest
├── rokit.toml                           # Rokit toolchain (rojo, wally, lune, selene, stylua)
├── Makefile                             # Build automation
├── .luaurc                              # Luau LSP configuration (strict mode)
├── selene.toml                          # Selene linter config
├── .stylua.toml                         # StyLua formatter config
├── .github/
│   └── workflows/
│       ├── ci.yml                       # CI: lint, fmt, test, build
│       └── release.yml                  # Release: build + publish to Wally
├── .gitignore
├── LICENSE                              # MIT
├── README.md
└── CLAUDE.md                            # Claude Code project instructions
```

---

## 3. Module Specifications

### 3.1 crypto -- Cryptographic Primitives

The crypto module is the foundation of the SDK. All implementations use buffer-based field arithmetic with f64 limbs for maximum Luau performance.

#### 3.1.1 BigInt

Arbitrary-precision integer arithmetic using buffer-backed f64 limb arrays.

**Design:**
- Representation: Array of f64 limbs stored in Luau `buffer` objects (little-endian)
- Limb size: 24 bits per limb (keeps products under 2^53 f64 precision limit)
- 11 limbs = 264 bits of coverage (sufficient for 252-bit Stark field elements)
- All operations use `--!native` and `--!optimize 2` pragmas
- Carry propagation via the IEEE 754 rounding trick: `x + 3*2^k - 3*2^k`
- Barrett reduction for optimized modular multiplication

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
BigInt.powmodB(a: BigInt, e: BigInt, ctx: BarrettCtx) -> BigInt
```

#### 3.1.2 FieldFactory

Parameterized field constructor that DRYs the implementation shared between StarkField and StarkScalarField.

**API:**
```lua
type Field = {
    modulus: buffer,
    barrettCtx: BarrettCtx,
    zero: () -> Felt,
    one: () -> Felt,
    fromNumber: (n: number) -> Felt,
    fromHex: (hex: string) -> Felt,
    add: (a: Felt, b: Felt) -> Felt,
    sub: (a: Felt, b: Felt) -> Felt,
    mul: (a: Felt, b: Felt) -> Felt,
    square: (a: Felt) -> Felt,
    neg: (a: Felt) -> Felt,
    inv: (a: Felt) -> Felt,
    toHex: (a: Felt) -> string,
    toBigInt: (a: Felt) -> BigInt,
    eq: (a: Felt, b: Felt) -> boolean,
    isZero: (a: Felt) -> boolean,
    powmod: (base: Felt, exp: buffer) -> Felt,
}

FieldFactory.createField(modulus: buffer, modulusMinus2: buffer, barrettCtx: BarrettCtx, name: string) -> Field
```

#### 3.1.3 StarkField

Modular arithmetic over the Stark prime field P = 2^251 + 17 * 2^192 + 1.

Created via `FieldFactory.createField(P, P-2, barrettCtxP, "StarkField")`.

**API:**
```lua
StarkField.P -> BigInt  -- the field prime (also: StarkField.modulus)

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
StarkField.inv(a: Felt) -> Felt
StarkField.powmod(base: Felt, exp: buffer) -> Felt

-- Conversions
StarkField.toHex(a: Felt) -> string
StarkField.toBigInt(a: Felt) -> BigInt
StarkField.eq(a: Felt, b: Felt) -> boolean
StarkField.isZero(a: Felt) -> boolean
```

#### 3.1.4 StarkScalarField

Arithmetic modulo the curve order N (for ECDSA scalar operations).

Same API pattern as StarkField but with modulus N instead of P.

```lua
StarkScalarField.N -> BigInt  -- the curve order (also: StarkScalarField.modulus)
```

#### 3.1.5 StarkCurve

Elliptic curve operations on the Stark curve: y^2 = x^3 + x + beta (short Weierstrass, alpha=1).

**Design:**
- Internal representation: Jacobian coordinates (X, Y, Z) to avoid field inversions
- 4-bit windowed scalar multiplication for performance
- Shamir's trick for dual-base multiplication (used in ECDSA verify)
- Pre-computed generator point and lookup tables for Pedersen

**Types:**
```lua
type AffinePoint = { x: Felt, y: Felt }
type JacobianPoint = { x: Felt, y: Felt, z: Felt }
```

**Constants:**
```lua
StarkCurve.G -> AffinePoint        -- generator point
StarkCurve.N -> BigInt              -- curve order (from StarkScalarField)
StarkCurve.ALPHA -> Felt            -- 1
StarkCurve.BETA -> Felt             -- 0x06f21413...
StarkCurve.INFINITY -> AffinePoint  -- identity point sentinel
```

**API:**
```lua
-- Point operations (Jacobian)
StarkCurve.jacobianAdd(p1: JacobianPoint, p2: JacobianPoint) -> JacobianPoint
StarkCurve.jacobianDouble(p: JacobianPoint) -> JacobianPoint

-- Coordinate conversion
StarkCurve.jacobianFromAffine(p: AffinePoint) -> JacobianPoint
StarkCurve.affineFromJacobian(p: JacobianPoint) -> AffinePoint

-- Scalar multiplication (4-bit windowed)
StarkCurve.scalarMul(p: AffinePoint, k: buffer) -> AffinePoint
StarkCurve.shamirMul(p1: AffinePoint, k1: buffer, p2: AffinePoint, k2: buffer) -> AffinePoint

-- Point queries
StarkCurve.isOnCurve(p: AffinePoint) -> boolean
StarkCurve.isInfinity(p: JacobianPoint) -> boolean
StarkCurve.isInfinityAffine(p: AffinePoint) -> boolean
StarkCurve.affineEq(a: AffinePoint, b: AffinePoint) -> boolean
StarkCurve.affineNeg(p: AffinePoint) -> AffinePoint

-- Key derivation
StarkCurve.getPublicKey(privateKey: buffer) -> AffinePoint  -- k * G
```

#### 3.1.6 Poseidon

Poseidon hash function over the Stark field using Hades permutation.

**Design:**
- State width = 3, rate = 2, capacity = 1
- 91 rounds: 4 full + 83 partial + 4 full
- Pre-computed round constants and MDS matrix (in PoseidonConstants.luau)
- Sponge construction for variable-length input

**API:**
```lua
Poseidon.hash(a: Felt, b: Felt) -> Felt              -- h(a, b)
Poseidon.hashMany(values: {Felt}) -> Felt             -- sponge with rate=2
```

#### 3.1.7 Pedersen

Pedersen hash using elliptic curve point operations on the Stark curve.

**Design:**
- Uses 4 pre-computed constant base points (P0, P1, P2, P3)
- Processes 248-bit + 4-bit chunks of inputs
- Used for address computation (via `computeHashOnElements`) and SNIP-12 LEGACY revision

**API:**
```lua
Pedersen.hash(a: Felt, b: Felt) -> Felt
Pedersen.hashChain(values: {Felt}) -> Felt  -- chain: h(h(...h(0, v1), v2)..., vN), N)
```

#### 3.1.8 Keccak

Keccak-256 implementation (Ethereum/Starknet variant, NOT SHA-3).

**Design:**
- Full Keccak-f[1600] permutation (24 rounds)
- 64-bit lanes via {hi, lo} 32-bit pairs (Luau lacks native 64-bit)
- Starknet selector: keccak256 masked to 250 bits
- Domain separation byte: 0x01 (NOT SHA-3's 0x06)

**API:**
```lua
Keccak.hash(data: buffer) -> buffer                       -- raw keccak-256
Keccak.getSelectorFromName(name: string) -> Felt          -- function selector (250-bit)
Keccak.getSelector(name: string) -> string                -- selector as hex string
```

#### 3.1.9 SHA256

SHA-256 hash and HMAC-SHA-256 for RFC 6979 nonce generation.

**API:**
```lua
SHA256.sha256(data: buffer) -> buffer
SHA256.hmac(key: buffer, message: buffer) -> buffer
```

#### 3.1.10 ECDSA

Stark ECDSA signing with RFC 6979 deterministic nonce generation.

**Types:**
```lua
type Signature = { r: buffer, s: buffer }
```

**API:**
```lua
ECDSA.sign(messageHash: buffer, privateKey: buffer) -> Signature
ECDSA.verify(messageHash: buffer, publicKey: AffinePoint, signature: Signature) -> boolean
ECDSA.generateK(messageHash: buffer, privateKey: buffer) -> buffer
```

---

### 3.2 signer -- Signing Abstraction

#### 3.2.1 StarkSigner

Default signer implementation using Stark curve ECDSA with RFC 6979.

**Interface Types** (from `shared/interfaces.luau`):
```lua
type MinimalSigner = {
    signHash: (self: MinimalSigner, hash: buffer) -> { string },
}

type SignerInterface = {
    signHash: (self: SignerInterface, hash: buffer) -> { string },
    getPublicKeyHex: (self: SignerInterface) -> string,
    signRaw: (self: SignerInterface, msgHash: buffer) -> ECDSA.Signature,
    getPubKey: (self: SignerInterface) -> AffinePoint,
}
```

**API:**
```lua
-- Constructor
StarkSigner.new(privateKeyHex: string) -> StarkSigner

-- Methods
signer:getPubKey() -> AffinePoint
signer:getPublicKeyHex() -> string
signer:signRaw(msgHash: buffer) -> { r: buffer, s: buffer }
signer:signHash(hash: buffer) -> { string }  -- returns {r_hex, s_hex} for transaction signing
```

---

### 3.3 provider -- RPC Connectivity

#### 3.3.1 JsonRpcClient

Shared base class for JSON-RPC communication. Provides rate limiting, retry logic, and request lifecycle shared by both `RpcProvider` and `PaymasterRpc`.

**API:**
```lua
JsonRpcClient.new(config: {
    nodeUrl: string,
    headers: { [string]: string }?,
    maxRequestsPerMinute: number?,
    rateLimitTimeout: number?,
    retryAttempts: number?,
    retryDelay: number?,
    errorMapper: ((rawError: any) -> any)?,
    shouldRetry: ((error: any) -> boolean)?,
    clientName: string?,
    _httpRequest: ((request: HttpRequest) -> HttpResponse)?,
    _sleep: ((seconds: number) -> ())?,
    _clock: (() -> number)?,
}) -> JsonRpcClient

client:request(method: string, params: any) -> Promise<any>
client:batch(requests: { { method: string, params: any } }) -> Promise<{ any }>
client:getNodeUrl() -> string
client:getPromise() -> any
```

#### 3.3.2 RpcProvider

Full Starknet JSON-RPC client with optional queue, cache, and nonce management.

**Constructor:**
```lua
RpcProvider.new(config: {
    nodeUrl: string,
    headers: { [string]: string }?,
    maxRequestsPerMinute: number?,       -- default: 450
    rateLimitTimeout: number?,           -- default: 10 seconds
    retryAttempts: number?,              -- default: 3
    retryDelay: number?,                 -- default: 1 second
    -- Opt-in subsystems
    enableQueue: boolean?,               -- enable request queue + batching
    queueConfig: RequestQueueConfig?,
    enableCache: boolean?,               -- enable response caching
    cacheConfig: CacheConfig?,
    enableNonceManager: boolean?,        -- enable nonce management
    nonceManagerConfig: NonceManagerConfig?,
    -- Testing injection
    _httpRequest: ((request: HttpRequest) -> HttpResponse)?,
    _sleep: ((seconds: number) -> ())?,
    _clock: (() -> number)?,
    _defer: ((fn: () -> ()) -> ())?,
}) -> RpcProvider
```

**Network Methods:**
```lua
provider:getChainId() -> Promise<string>
provider:getBlockNumber() -> Promise<number>
provider:getSpecVersion() -> Promise<string>
provider:getSyncingStats() -> Promise<any>
```

**Account Methods:**
```lua
provider:getNonce(contractAddress: string, blockId: string?) -> Promise<string>
```

**Transaction Methods:**
```lua
provider:call(request: CallRequest, blockId: string?) -> Promise<{string}>
provider:estimateFee(transactions: {InvokeTransactionV3}, simulationFlags: {string}?) -> Promise<{FeeEstimate}>
provider:estimateMessageFee(message: MessageFromL1, blockId: string?) -> Promise<FeeEstimate>
provider:addInvokeTransaction(invokeTx: InvokeTransactionV3) -> Promise<InvokeResult>
provider:addDeployAccountTransaction(deployTx: DeployAccountTransactionV3) -> Promise<DeployAccountResult>
provider:getTransactionReceipt(txHash: string) -> Promise<TransactionReceipt>
provider:getTransactionStatus(txHash: string) -> Promise<TransactionStatus>
provider:getTransactionByHash(txHash: string) -> Promise<Transaction>
```

**Block Methods:**
```lua
provider:getBlockWithTxHashes(blockId: string?) -> Promise<Block>
provider:getBlockWithTxs(blockId: string?) -> Promise<BlockWithTxs>
provider:getBlockWithReceipts(blockId: string?) -> Promise<BlockWithReceipts>
```

**Contract Methods:**
```lua
provider:getClassHashAt(contractAddress: string, blockId: string?) -> Promise<string>
provider:getStorageAt(contractAddress: string, key: string, blockId: string?) -> Promise<string>
provider:getClass(classHash: string, blockId: string?) -> Promise<ContractClass>
provider:getClassAt(contractAddress: string, blockId: string?) -> Promise<ContractClass>
```

**Event Methods:**
```lua
provider:getEvents(filter: EventFilter) -> Promise<EventsChunk>
provider:getAllEvents(filter: EventFilter) -> Promise<{EmittedEvent}>  -- auto-paginates
```

**Utility Methods:**
```lua
provider:waitForTransaction(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>
provider:fetch(method: string, params: any, options: FetchOptions?) -> Promise<any>
provider:fetchSync(method: string, params: any) -> any
provider:getNodeUrl() -> string
provider:getMetrics() -> ProviderMetrics
provider:flushCache() -> ()
provider:getNonceManager() -> NonceManager?
provider:getPromise() -> any
```

#### 3.3.3 RpcTypes

Type definitions for all RPC request/response objects. Key types:

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

type InvokeResult = { transaction_hash: string }
type DeployAccountResult = { transaction_hash: string, contract_address: string }

type TransactionReceipt = {
    transaction_hash: string,
    actual_fee: { amount: string, unit: string },
    execution_status: string,
    finality_status: string,
    block_hash: string?,
    block_number: number?,
    events: { Event },
    revert_reason: string?,
}

type TransactionStatus = {
    finality_status: string,
    execution_status: string?,
}

type WaitOptions = {
    retryInterval: number?,    -- seconds (default: 5)
    maxAttempts: number?,      -- max polls (default: 30)
}

type EventFilter = {
    from_block: { block_number: number }?,
    to_block: { block_number: number }?,
    address: string?,
    keys: { { string } }?,
    chunk_size: number?,
    continuation_token: string?,
}

type EventsChunk = {
    events: { EmittedEvent },
    continuation_token: string?,
}

type EmittedEvent = {
    from_address: string,
    keys: { string },
    data: { string },
    block_hash: string?,
    block_number: number?,
    transaction_hash: string?,
}

type EventPollerConfig = {
    provider: any,
    contractAddress: string,
    keys: { { string } }?,
    pollInterval: number?,
    onEvents: ((events: { EmittedEvent }) -> ())?,
    onCheckpoint: ((blockNumber: number) -> ())?,
    dataStore: DataStoreLike?,
    checkpointKey: string?,
}
```

#### 3.3.4 NonceManager

Manages nonces for parallel transaction submission using a reserve/confirm/reject pattern.

**Design:**
- Reserve: atomically claims the next nonce for an address
- Confirm: acknowledges successful submission
- Reject: rolls back on failure
- Auto-resync from provider on error

**API:**
```lua
NonceManager.new(provider: any, config: {
    maxPendingNonces: number?,
    autoResyncOnError: boolean?,
}?) -> NonceManager

manager:reserve(address: string) -> Promise<string>
manager:confirm(address: string, nonce: string) -> ()
manager:reject(address: string) -> ()
manager:getMetrics() -> {
    totalReserved: number,
    totalConfirmed: number,
    totalRejected: number,
    totalResyncs: number,
}
```

#### 3.3.5 RequestQueue

3-bucket priority queue with automatic JSON-RPC batching for read-only methods.

**Design:**
- HIGH priority: `addInvokeTransaction`, `estimateFee` (dispatched individually)
- NORMAL priority: most read methods (batchable into single HTTP call)
- LOW priority: `getEvents` (batchable)
- Backpressure via `maxQueueDepth` (default 100, rejects with QUEUE_FULL)
- Drain-on-defer: batches all `fetch()` calls queued in the same frame

**API:**
```lua
RequestQueue.new(maxQueueDepth: number?) -> RequestQueue

queue:enqueue(method: string, params: any, resolve: any, reject: any) -> ()
queue:dequeue() -> QueueItem?
queue:depth() -> number
queue:isEmpty() -> boolean
queue:peekPriority() -> string?
queue:getMetrics() -> QueueMetrics

-- Static helpers
RequestQueue.getPriority(method: string) -> string
RequestQueue.isBatchable(method: string) -> boolean
```

#### 3.3.6 ResponseCache

LRU cache with per-method TTL for JSON-RPC responses.

**Design:**
- Doubly-linked list + hash map for O(1) get/set/evict
- Per-method TTL: `chainId`/`specVersion`/`classHash`=indefinite, `blockNumber`/`block`=10s, `storage`/`call`=30s
- Never cached: `addInvokeTransaction`, `estimateFee`, `getNonce`, `getTransactionReceipt`/`Status`, `getEvents`
- Block invalidation: new block numbers invalidate storage/call/block caches

**API:**
```lua
ResponseCache.new(config: CacheConfig?, clockFn: (() -> number)?) -> ResponseCache

cache:get(key: string) -> any?
cache:set(key: string, value: any, ttl: number) -> ()
cache:invalidate(key: string) -> ()
cache:invalidateByPrefix(prefix: string) -> ()
cache:flush() -> ()
cache:getTTLForMethod(method: string) -> number?
cache:getMetrics() -> CacheMetrics
cache:size() -> number

type CacheConfig = {
    maxEntries: number?,         -- default: 256
    chainIdTTL: number?,         -- default: 0 (indefinite)
    blockNumberTTL: number?,     -- default: 10
    blockTTL: number?,           -- default: 10
    storageTTL: number?,         -- default: 30
    callTTL: number?,            -- default: 30
    classHashTTL: number?,       -- default: 0
    classTTL: number?,           -- default: 0
    specVersionTTL: number?,     -- default: 0
}
```

#### 3.3.7 EventPoller

Polls for contract events at a configurable interval with optional DataStore persistence for checkpoint recovery.

**API:**
```lua
EventPoller.new(config: EventPollerConfig) -> EventPoller

poller:start() -> ()
poller:stop() -> ()
poller:isRunning() -> boolean
poller:getLastBlockNumber() -> number?
poller:setLastBlockNumber(blockNumber: number) -> ()
poller:getCheckpointKey() -> string?
```

---

### 3.4 tx -- Transaction Building

#### 3.4.1 CallData

Serializes Luau values into Starknet calldata (flat felt arrays). Computes function selectors.

**Types:**
```lua
type Call = {
    contractAddress: string,
    entrypoint: string,
    calldata: { string },
}
```

**Encoding Rules:**
| Cairo Type     | Encoding                              | Felt Count |
|---------------|---------------------------------------|------------|
| `felt252`     | `[value]`                             | 1          |
| `u256`        | `[low_128, high_128]`                 | 2          |
| `address`     | `[value]`                             | 1          |
| `bool`        | `[0]` or `[1]`                        | 1          |
| `Array<T>`    | `[len, elem0..., elem1..., ...]`      | 1 + n*T    |
| `Struct`      | `[field0_felts..., field1_felts...]`  | sum(fields)|

**API:**
```lua
CallData.encodeFelt(hex: string) -> { string }
CallData.encodeU256(hex: string) -> { string }
CallData.encodeBool(value: boolean) -> { string }
CallData.encodeArray(elements: { string }) -> { string }
CallData.encodeShortString(str: string) -> { string }
CallData.encodeMulticall(calls: { Call }) -> { string }
CallData.validateCall(call: Call) -> ()
CallData.numberToHex(n: number) -> string
CallData.compile(rawArgs: { any }) -> { string }
CallData.concat(...: { string }) -> { string }
```

#### 3.4.2 TransactionHash

Computes V3 transaction hashes using Poseidon.

**Types:**
```lua
type ResourceBound = { maxAmount: string, maxPricePerUnit: string }
type ResourceBounds = {
    l1Gas: ResourceBound,
    l2Gas: ResourceBound,
    l1DataGas: ResourceBound,
}
```

**API:**
```lua
-- V3 INVOKE hash
TransactionHash.calculateInvokeTransactionHash(params: {
    senderAddress: string,
    compiledCalldata: { string },
    chainId: string,
    nonce: string,
    resourceBounds: ResourceBounds,
    version: string?,
    tip: string?,
    paymasterData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
}) -> string

-- V3 DEPLOY_ACCOUNT hash
TransactionHash.calculateDeployAccountTransactionHash(params: {
    contractAddress: string,
    classHash: string,
    constructorCalldata: { string },
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

-- Helpers
TransactionHash.hashFeeField(tip: string, resourceBounds: ResourceBounds) -> string
TransactionHash.hashDAMode(nonceDAMode: number, feeDAMode: number) -> string
```

#### 3.4.3 TransactionBuilder

Full transaction orchestration: nonce → chainId → calldata → fee estimation → hash → sign → submit.

**Types:**
```lua
type BaseTransactionOptions = {
    nonce: string?,
    maxFee: string?,
    resourceBounds: ResourceBounds?,
    feeMultiplier: number?,          -- default: 1.5
    tip: string?,
    paymasterData: { string }?,
    nonceDataAvailabilityMode: number?,
    feeDataAvailabilityMode: number?,
    dryRun: boolean?,
    skipValidate: boolean?,
}

type ExecuteOptions = BaseTransactionOptions & {
    accountDeploymentData: { string }?,
}

type DeployAccountParams = {
    classHash: string,
    constructorCalldata: { string },
    addressSalt: string,
    contractAddress: string,
}

type DeployAccountOptions = BaseTransactionOptions & {
    waitForConfirmation: boolean?,   -- default: true
}

type ExecuteResult = { transactionHash: string }
type DryRunResult = { transactionHash: string, transaction: any, signature: { string } }
```

**API:**
```lua
TransactionBuilder.new(provider: any, chainId: string?) -> TransactionBuilder

-- INVOKE
builder:execute(account: Account, calls: { Call }, options: ExecuteOptions?) -> Promise<ExecuteResult>
builder:estimateExecuteFee(account: Account, calls: { Call }, options: BaseTransactionOptions?) -> Promise<FeeEstimate>

-- DEPLOY_ACCOUNT
builder:deployAccount(account: any, params: DeployAccountParams, options: DeployAccountOptions?) -> Promise<ExecuteResult>
builder:estimateDeployAccountFee(account: any, params: DeployAccountParams, options: BaseTransactionOptions?) -> Promise<FeeEstimate>
```

---

### 3.5 wallet -- Account Management

#### 3.5.1 Account

Represents a Starknet account with signing capabilities. Wraps TransactionBuilder internally.

**Static Methods:**
```lua
-- Address derivation (pure, no provider needed)
Account.computeAddress(config: {
    classHash: string,           -- required
    publicKey: string,
    deployer: string?,           -- default: 0
    salt: string?,               -- default: publicKey
    constructorCalldata: { string }?,  -- default: { publicKey }
}) -> string

-- Detect account type from class hash
Account.detectAccountType(classHash: string) -> string?  -- "oz"|"argent"|"braavos"|nil

-- Build constructor calldata for an account type
Account.getConstructorCalldata(accountType: string, publicKey: string, guardian: string?) -> { string }

-- Estimate deployment fee (no signer needed, uses dummy signer)
Account.getDeploymentFeeEstimate(config: {
    classHash: string,
    constructorCalldata: { string },
    salt: string,
    contractAddress: string,
    provider: ProviderInterface,
    feeMultiplier: number?,
}) -> Promise<{ estimatedFee, gasConsumed, gasPrice, rawEstimate }>

-- Check if account has sufficient balance for deployment
Account.checkDeploymentBalance(config: { ... }) -> Promise<boolean>

-- Get human-readable funding info
Account.getDeploymentFundingInfo(config: { ... }) -> Promise<{ ... }>
```

**Constructors:**
```lua
Account.new(config: {
    address: string,
    signer: SignerInterface,
    provider: ProviderInterface,
    accountType: string?,              -- "oz"|"argent"|"braavos"
    classHash: string?,
    constructorCalldata: { string }?,
}) -> Account

Account.fromPrivateKey(config: {
    privateKey: string,                -- hex
    provider: ProviderInterface,
    accountType: string?,              -- default: "oz"
    classHash: string?,
    guardian: string?,                  -- Argent only
}) -> Account
```

**Properties:**
```lua
account.address -> string
account.signer -> SignerInterface
```

**Instance Methods:**
```lua
-- Transaction execution
account:execute(calls: { Call }, options: ExecuteOptions?) -> Promise<ExecuteResult>
account:estimateFee(calls: { Call }) -> Promise<FeeEstimate>
account:getNonce() -> Promise<string>
account:waitForReceipt(txHash: string, options: WaitOptions?) -> Promise<TransactionReceipt>

-- Account deployment
account:deployAccount(options: DeployAccountOptions?) -> Promise<{
    alreadyDeployed: boolean?,
    transactionHash: string,
    contractAddress: string,
}>
account:estimateDeployAccountFee() -> Promise<FeeEstimate>
account:getDeploymentData() -> { classHash, constructorCalldata, addressSalt, contractAddress }

-- SNIP-12 typed data
account:hashMessage(typedData: { [string]: any }) -> string
account:signMessage(typedData: { [string]: any }) -> { string }  -- {r_hex, s_hex}

-- Paymaster-sponsored execution
account:executePaymaster(calls: { Call }, paymasterDetails: PaymasterDetails) -> Promise<ExecuteResult>
account:estimatePaymasterFee(calls: { Call }, paymasterDetails: PaymasterDetails) -> Promise<FeeEstimate>
account:deployWithPaymaster(paymasterDetails: PaymasterDetails, options: DeployAccountOptions?) -> Promise<{
    alreadyDeployed: boolean?,
    transactionHash: string,
    contractAddress: string,
    trackingId: string?,
}>

-- Accessors
account:getProvider() -> RpcProvider
account:getPublicKeyHex() -> string
account:getNonceManager() -> NonceManager?
```

#### 3.5.2 AccountType

Pre-defined account type constructors with callable semantics for building constructor calldata.

```lua
-- Each type is callable: AccountType.OZ(publicKey) -> constructorCalldata
AccountType.OZ -> { type: "oz", classHash: string, (publicKey: string) -> { string } }
AccountType.Argent -> { type: "argent", classHash: string, (ownerKey: string, guardianKey?: string) -> { string } }
AccountType.Braavos -> { type: "braavos", classHash: string, (publicKey: string) -> { string } }

-- Lookup by name
AccountType.get(typeName: string) -> AccountType?

-- Create custom account type
AccountType.custom(config: {
    type: string,
    classHash: string,
    buildCalldata: (...any) -> { string },
}) -> AccountType
```

#### 3.5.3 AccountFactory

Factory for creating and batch-deploying accounts.

```lua
AccountFactory.new(provider: any, accountType: any, signer: any) -> AccountFactory

factory:createAccount(options: {
    classHash: string?,
    addressSalt: string?,
    guardian: string?,
}?) -> { account: Account, address: string, deployTx: any }

factory:batchCreate(count: number, options: {
    keyGenerator: (() -> string)?,
    classHash: string?,
    guardian: string?,
}?) -> { { account: Account, address: string } }

factory:batchDeploy(accounts: { any }, options: {
    maxParallel: number?,
    onDeployProgress: ((progress: any) -> ())?,
}?) -> Promise<{
    deployed: number,
    failed: number,
    skipped: number,
    results: { any },
}>
```

#### 3.5.4 TypedData (SNIP-12)

Typed data hashing supporting both LEGACY (revision "0", Pedersen) and ACTIVE (revision "1", Poseidon) revisions.

**Constants:**
```lua
TypedData.REVISION_LEGACY = "0"
TypedData.REVISION_ACTIVE = "1"
```

**API:**
```lua
TypedData.getMessageHash(typedData: { [string]: any }) -> string
TypedData.hashTypedData(typedData: { [string]: any }) -> string  -- alias
```

**Revision Differences:**
| Feature | LEGACY ("0") | ACTIVE ("1") |
|---------|-------------|-------------|
| Domain type | `StarkNetDomain` | `StarknetDomain` |
| Hash function | Pedersen (`computeHashOnElements`) | Poseidon (`hashMany`) |
| Preset types | None | `u256`, `TokenAmount`, `NftId` |

#### 3.5.5 OutsideExecution (SNIP-9)

Build typed data for meta-transactions that can be submitted by any address.

**Constants:**
```lua
OutsideExecution.VERSION_V1 = "1"
OutsideExecution.VERSION_V2 = "2"
OutsideExecution.VERSION_V3_RC = "3"
OutsideExecution.ENTRYPOINT_V1 = "execute_from_outside"
OutsideExecution.ENTRYPOINT_V2 = "execute_from_outside_v2"
OutsideExecution.ENTRYPOINT_V3 = "execute_from_outside_v3"
OutsideExecution.ANY_CALLER -> string  -- from Constants
OutsideExecution.INTERFACE_ID_V1 -> string
OutsideExecution.INTERFACE_ID_V2 -> string
```

**API:**
```lua
OutsideExecution.buildTypedData(version: string, chainId: string, account: string, calls: { Call }, options: {
    nonce: string?,
    executeAfter: string?,
    executeBefore: string?,
    accountClassHash: string?,
}?) -> TypedData

OutsideExecution.getOutsideCall(call: Call) -> any
OutsideExecution.getOutsideExecution(typedData: any) -> any
```

#### 3.5.6 KeyStore

Encrypted private key persistence using Roblox DataStore with XOR+HMAC-SHA256.

**Types:**
```lua
type KeyStoreConfig = {
    serverSecret: string,              -- encryption key
    dataStoreName: string?,            -- default: "StarknetKeyStore"
    accountType: string?,              -- default: "oz"
    _dataStore: DataStoreLike?,        -- inject for testing
    _clock: (() -> number)?,
    _randomBytes: ((n: number) -> buffer)?,
}

type KeyStoreRecord = {
    version: number,
    encrypted: string,
    address: string,
    accountType: string,
    createdAt: number,
    deployedAt: number?,
}
```

**API:**
```lua
KeyStore.new(config: KeyStoreConfig) -> KeyStore

store:generateAndStore(playerId: number) -> { privateKey: string, address: string, publicKey: string }
store:loadAccount(provider: any, playerId: number, options: { dryRun: boolean? }?) -> Account?
store:getOrCreate(provider: any, playerId: number, options: { dryRun: boolean? }?) -> { account: Account, isNew: boolean }
store:hasAccount(playerId: number) -> boolean
store:deleteKey(playerId: number) -> ()
store:rotateSecret(newSecret: string, affectedPlayerIds: { number }?) -> ()
```

#### 3.5.7 OnboardingManager

High-level player account lifecycle: create key → derive address → deploy account (optionally with paymaster).

**Types:**
```lua
type OnboardingConfig = {
    keyStore: KeyStore,
    provider: ProviderInterface,
    paymasterDetails: PaymasterDetails?,
    waitForConfirmation: boolean?,
    dryRun: boolean?,
}

type OnboardingResult = {
    account: Account,
    address: string,
    isNew: boolean,
    wasDeployed: boolean,
    alreadyDeployed: boolean,
    transactionHash: string?,
    trackingId: string?,
}

type OnboardingStatus = {
    hasAccount: boolean,
    isDeployed: boolean,
    address: string?,
}
```

**API:**
```lua
OnboardingManager.new(config: OnboardingConfig) -> OnboardingManager

manager:onboard(playerId: number, options: {
    maxFee: string?,
    feeMultiplier: number?,
    dryRun: boolean?,
}?) -> Promise<OnboardingResult>

manager:getStatus(playerId: number) -> Promise<OnboardingStatus>
manager:ensureDeployed(playerId: number) -> Promise<any>
manager:removePlayer(playerId: number) -> ()
```

---

### 3.6 contract -- Contract Interaction

#### 3.6.1 AbiCodec

Recursive encoder/decoder for all Cairo types. Publicly exported for advanced use.

**Types:**
```lua
type TypeDef = {
    kind: string,              -- "felt"|"bool"|"u256"|"unit"|"struct"|"enum"|"array"|"tuple"|"bytearray"
    members: { { name: string, type: string } }?,  -- for struct
    variants: { { name: string, type: string } }?,  -- for enum
    elementType: string?,      -- for array
    tupleTypes: { string }?,   -- for tuple
}

type TypeMap = { [string]: TypeDef }
```

**API:**
```lua
AbiCodec.buildTypeMap(abi: any) -> TypeMap
AbiCodec.resolveType(typeName: string, typeMap: TypeMap) -> TypeDef
AbiCodec.encode(value: any, typeName: string, typeMap: TypeMap) -> { string }
AbiCodec.decode(results: { string }, offset: number, typeName: string, typeMap: TypeMap) -> (any, number)
```

**Type Encoding Reference:**
| Cairo Type | Luau Input | Encoded Felts |
|-----------|-----------|---------------|
| `felt252` | `"0x..."` | 1 |
| `bool` | `true`/`false` | 1 |
| `u256` | `"0x..."` | 2 (low, high) |
| `()` (unit) | `nil` | 0 |
| `ByteArray` | `"hello"` | 1+N+1+1 (chunks) |
| `Option<T>` | `{Some=val}`/`{None=true}`/`nil` | varies |
| `Result<T,E>` | `{Ok=val}`/`{Err=val}` | varies |
| `Array<T>` / `Span<T>` | `{elem1, elem2}` | 1 + N*size(T) |
| `(T1, T2)` (tuple) | `{val1, val2}` | size(T1) + size(T2) |
| Struct | `{field1=val, ...}` | sum(fields) |
| Enum | `{variant="Name", value=data}` | 1 + size(variant) |

#### 3.6.2 Contract

ABI-driven smart contract interface with dynamic method dispatch.

**Design:**
- Reads ABI at construction time, extracts functions from `type == "function"` and `type == "interface"` entries
- `__index` metamethod auto-dispatches: `view` → `call()`, `external` → `invoke()`
- Multiple outputs → table keyed by output parameter name; single output → direct value

**Types:**
```lua
type ContractConfig = {
    abi: Abi,
    address: string,
    provider: ProviderInterface,
    account: AccountInterface?,  -- required for invoke()
}

type InvokeOptions = {
    nonce: string?,
    maxFee: string?,
    feeMultiplier: number?,
    dryRun: boolean?,
}

type ParseEventsResult = {
    events: { any },
    errors: { ParseEventError },
}
```

**API:**
```lua
Contract.new(config: ContractConfig) -> Contract

-- Dynamic methods (auto-generated from ABI via __index)
contract:functionName(arg1, arg2, ...) -> Promise<result>

-- Explicit call/invoke
contract:call(method: string, args: { any }?, blockId: string?) -> Promise<any>
contract:invoke(method: string, args: { any }?, options: InvokeOptions?) -> Promise<ExecuteResult>

-- Build a Call object for multicall batching
contract:populate(method: string, args: { any }?) -> Call

-- ABI introspection
contract:getAbi() -> Abi
contract:getFunctions() -> { string }           -- list of function names
contract:getFunction(name: string) -> ParsedFunction?
contract:hasFunction(name: string) -> boolean

-- Event handling
contract:parseEvents(receipt: any, options: { strict: boolean? }?) -> ParseEventsResult
contract:queryEvents(filter: EventFilter?) -> Promise<{ any }>
contract:getEvents() -> { string }              -- list of event names
contract:hasEvent(name: string) -> boolean
```

#### 3.6.3 PresetFactory

DRY factory for building typed contract presets from an ABI definition.

```lua
PresetFactory.create(abi: Abi) -> {
    new: (address: string, provider: any, account: any?) -> Contract,
    getAbi: () -> Abi,
}
```

#### 3.6.4 ERC-20 Preset

Access: `Starknet.contract.ERC20`

```lua
local erc20 = Starknet.contract.ERC20.new(address, provider, account?)

-- View methods (call)
erc20:name() -> Promise<string>
erc20:symbol() -> Promise<string>
erc20:decimals() -> Promise<number>
erc20:total_supply() -> Promise<string>
erc20:balanceOf(owner: string) -> Promise<string>
erc20:allowance(owner: string, spender: string) -> Promise<string>

-- External methods (invoke, requires account)
erc20:transfer(recipient: string, amount: string) -> Promise<ExecuteResult>
erc20:approve(spender: string, amount: string) -> Promise<ExecuteResult>
erc20:transfer_from(sender: string, recipient: string, amount: string) -> Promise<ExecuteResult>
```

#### 3.6.5 ERC-721 Preset

Access: `Starknet.contract.ERC721`

```lua
local erc721 = Starknet.contract.ERC721.new(address, provider, account?)

-- View methods
erc721:name() -> Promise<string>
erc721:symbol() -> Promise<string>
erc721:owner_of(tokenId: string) -> Promise<string>
erc721:balance_of(owner: string) -> Promise<string>
erc721:get_approved(tokenId: string) -> Promise<string>
erc721:is_approved_for_all(owner: string, operator: string) -> Promise<boolean>

-- External methods
erc721:transfer_from(from: string, to: string, tokenId: string) -> Promise<ExecuteResult>
erc721:approve(to: string, tokenId: string) -> Promise<ExecuteResult>
```

---

### 3.7 errors -- Structured Error System

#### 3.7.1 StarknetError

Typed error hierarchy with factory constructors. Errors created via factory functions are `pcall`-safe — caught errors retain their metatable and `:is()` method.

**Types:**
```lua
type StarknetErrorInstance = {
    _type: string,            -- "StarknetError"|"RpcError"|"SigningError"|"AbiError"|"ValidationError"|"TransactionError"|"PaymasterError"
    message: string,
    code: number?,
    data: any?,
    rpcCode: number?,         -- RpcError only
    hint: string?,            -- ValidationError only
    revertReason: string?,    -- TransactionError only
    executionTrace: string?,  -- TransactionError only
    is: (self: any, errorType: string) -> boolean,
}
```

**Factory Constructors:**
```lua
StarknetError.new(message: string, code: number?, data: any?) -> StarknetErrorInstance
StarknetError.rpc(message: string, sdkCode: number?, rpcCode: number?, data: any?) -> StarknetErrorInstance
StarknetError.signing(message: string, code: number?, data: any?) -> StarknetErrorInstance
StarknetError.abi(message: string, code: number?, data: any?) -> StarknetErrorInstance
StarknetError.validation(message: string, code: number?, hint: string?, data: any?) -> StarknetErrorInstance
StarknetError.transaction(message: string, code: number?, revertReason: string?, executionTrace: string?, data: any?) -> StarknetErrorInstance
StarknetError.paymaster(message: string, code: number?, data: any?) -> StarknetErrorInstance
```

**Utility:**
```lua
StarknetError.isStarknetError(value: any) -> boolean  -- duck-type check (_type + message + is)
StarknetError.ErrorCodes -> ErrorCodes                 -- re-export
```

**Type Hierarchy:**
```
StarknetError (base)
├── RpcError
├── SigningError
├── AbiError
├── ValidationError
├── TransactionError
└── PaymasterError
```

`:is(errorType)` checks own `_type` then walks parent hierarchy. For example, `RpcError:is("RpcError")` → true, `RpcError:is("StarknetError")` → true.

#### 3.7.2 ErrorCodes

Numeric error code constants organized by category range.

| Range | Category | Key Codes |
|-------|----------|-----------|
| 1000-1099 | Validation | `INVALID_ARGUMENT` (1000), `REQUIRED_FIELD` (1001), `INVALID_FORMAT` (1003) |
| 2000-2099 | RPC/Network | `RPC_ERROR` (2000), `NETWORK_ERROR` (2001), `RATE_LIMIT` (2002), `TIMEOUT` (2003), `TRANSACTION_REVERTED` (2004), `TRANSACTION_REJECTED` (2005), `QUEUE_FULL` (2010), `BATCH_ERROR` (2011), `NONCE_FETCH_ERROR` (2013), `NONCE_MANAGER_ERROR` (2015) |
| 3000-3099 | Signing/Crypto | `SIGNING_ERROR` (3000), `INVALID_PRIVATE_KEY` (3001), `KEY_OUT_OF_RANGE` (3003), `MATH_ERROR` (3010) |
| 4000-4099 | ABI/Encoding | `ABI_ERROR` (4000), `UNKNOWN_TYPE` (4001), `ENCODE_ERROR` (4002), `DECODE_ERROR` (4003), `UNKNOWN_ENUM_VARIANT` (4004), `FUNCTION_NOT_FOUND` (4005), `ARGUMENT_COUNT` (4006) |
| 5000-5099 | Transaction | `TRANSACTION_ERROR` (5000), `FEE_ESTIMATION_FAILED` (5001), `BATCH_DEPLOY_ERROR` (5003), `NONCE_EXHAUSTED` (5004) |
| 6000-6099 | Outside Execution | `INVALID_VERSION` (6001), `CALL_VALIDATION_FAILED` (6002), `MISSING_FEE_MODE` (6003), `INVALID_TIME_BOUNDS` (6004) |
| 7000-7099 | Paymaster | `PAYMASTER_ERROR` (7000), `PAYMASTER_UNAVAILABLE` (7001), `PAYMASTER_TOKEN_NOT_SUPPORTED` (7002), `PAYMASTER_POLICY_REJECTED` (7010), `BUDGET_ERROR` (7011), `INSUFFICIENT_BUDGET` (7012), `SPONSORED_EXECUTION_FAILED` (7020) |
| 8000-8099 | KeyStore/Onboard | `KEY_STORE_ERROR` (8000), `KEY_STORE_DECRYPT_ERROR` (8001), `KEY_STORE_SECRET_INVALID` (8002), `ONBOARDING_ERROR` (8010) |

**Utility Functions:**
```lua
ErrorCodes.isTransient(errorCode: number) -> boolean           -- NETWORK_ERROR, RATE_LIMIT, TIMEOUT
ErrorCodes.isNonRetryablePaymaster(errorCode: number) -> boolean  -- PAYMASTER_INVALID_SIGNATURE, etc.
```

---

### 3.8 paymaster -- Sponsored Transactions

#### 3.8.1 PaymasterRpc (SNIP-29)

JSON-RPC client for SNIP-29 paymaster services. Built on `JsonRpcClient`.

**Types:**
```lua
type FeeMode = { mode: "sponsored" | "default", gasToken: string? }
type DeploymentData = { classHash: string, calldata: { string }, salt: string, unique: boolean?, sigdata: { string }?, version: string? }
type PaymasterDetails = { paymaster: PaymasterInterface, feeMode: FeeMode, deploymentData: DeploymentData?, gasTokenAddress: string? }
```

**API:**
```lua
PaymasterRpc.new(config: {
    nodeUrl: string,
    headers: { [string]: string }?,
    retryAttempts: number?,
    retryDelay: number?,
    maxRequestsPerMinute: number?,
    rateLimitTimeout: number?,
    _httpRequest: any?, _sleep: any?, _clock: any?,
}) -> PaymasterRpc

rpc:isAvailable() -> Promise<boolean>
rpc:getSupportedTokens() -> Promise<{ TokenData }>
rpc:buildTypedData(userAddress: string, calls: { Call }, gasTokenAddress: string, options: {
    accountClassHash: string?,
    deploymentData: DeploymentData?,
}?) -> Promise<{ typedData: any, feeEstimate: FeeEstimate?, deploymentData: DeploymentData? }>
rpc:executeTransaction(userAddress: string, typedData: any, signature: { string }, gasTokenAddress: string?, options: any?) -> Promise<{ trackingId: string?, transactionHash: string }>
rpc:trackingIdToLatestHash(trackingId: string) -> Promise<{ transactionHash: string, status: string }>
rpc:getNodeUrl() -> string
```

#### 3.8.2 AvnuPaymaster

AVNU-specific paymaster integration. Wraps `PaymasterRpc` with AVNU endpoint resolution and known token lookups.

```lua
AvnuPaymaster.new(config: {
    network: string,           -- "mainnet" | "sepolia"
    apiKey: string?,
    nodeUrl: string?,
    tokenCacheTtl: number?,
    -- ...JsonRpcClient config
}) -> AvnuPaymaster

-- Delegates all PaymasterRpc methods, plus:
avnu:getKnownToken(network: string, symbol: string) -> TokenInfo?
avnu:getKnownTokens(network: string) -> { [string]: TokenInfo }
```

#### 3.8.3 PaymasterPolicy

Policy engine for deciding whether to sponsor a transaction.

```lua
PaymasterPolicy.new(config: {
    allowedContracts: { string }?,
    allowedMethods: { string }?,
    allowedPlayers: { number }?,
    maxFeePerTx: string?,
    maxTxPerPlayer: number?,
    timeWindow: number?,          -- seconds
    _clock: (() -> number)?,
}) -> PaymasterPolicy

policy:validate(playerId: number, calls: { Call }) -> { allowed: boolean, reason: string? }
policy:validateFee(playerId: number, feeAmount: string | buffer) -> { allowed: boolean, reason: string? }
policy:recordUsage(playerId: number) -> ()
policy:resetUsage(playerId: number?) -> ()
policy:getUsageCount(playerId: number) -> number
```

#### 3.8.4 PaymasterBudget

Per-player token budget tracking with dirty-write DataStore persistence.

```lua
PaymasterBudget.new(config: {
    dataStoreName: string?,
    defaultTokenBalance: number?,
    costPerTransaction: number?,
    costPerGasUnit: number?,
    flushInterval: number?,
    maxDirtyEntries: number?,
    _dataStore: DataStoreLike?,
    _clock: (() -> number)?,
}?) -> PaymasterBudget

budget:canAfford(playerId: number, cost: number) -> boolean
budget:consumeTransaction(playerId: number, cost: number) -> ()
budget:refundTransaction(playerId: number, amount: number) -> ()
budget:calculateCost(gasUsed: number?) -> number
budget:getBalance(playerId: number) -> number
budget:grantTokens(playerId: number, amount: number) -> ()
budget:consumeTokens(playerId: number, amount: number) -> ()
budget:flush() -> Promise<{ synced: number, errors: { any } }>
```

#### 3.8.5 SponsoredExecutor

Orchestrator that ties together Account, PaymasterRpc, Policy, and Budget for gasless execution.

**Types:**
```lua
type SponsoredExecutorConfig = {
    account: AccountInterface,
    paymaster: PaymasterInterface,
    feeMode: FeeMode,
    policy: PolicyInterface?,
    budget: BudgetInterface?,
    callbacks: {
        onTransactionSubmitted: ((info: SubmittedInfo) -> ())?,
        onTransactionConfirmed: ((info: ConfirmedInfo) -> ())?,
        onTransactionFailed: ((info: FailedInfo) -> ())?,
    }?,
    retryAttempts: number?,
    retryDelay: number?,
    deploymentData: DeploymentData?,
    _sleep: any?,
    _clock: any?,
}
```

**API:**
```lua
SponsoredExecutor.new(config: SponsoredExecutorConfig) -> SponsoredExecutor

executor:execute(playerId: number, calls: { Call }, options: {
    txCost: number?,
    gasUsed: number?,
    deploymentData: DeploymentData?,
    waitForConfirmation: boolean?,
}?) -> Promise<{
    transactionHash: string,
    trackingId: string?,
    tokensCost: number,
    retryCount: number,
}>

executor:getMetrics() -> {
    totalExecutions: number,
    totalSuccessful: number,
    totalFailed: number,
    totalRetries: number,
    totalTokensConsumed: number,
    totalTokensRefunded: number,
    byPlayer: { [number]: PlayerMetrics },
    byContract: { [string]: number },
    byMethod: { [string]: number },
}
```

---

### 3.9 shared -- Internal Utilities

> **Note:** The `shared/` module is not exported via the main barrel export. It provides internal infrastructure used by other modules.

#### 3.9.1 interfaces.luau

Interface-only type definitions that break circular dependencies between modules.

```lua
type MinimalSigner = { signHash: (self: any, hash: buffer) -> { string } }
type SignerInterface = MinimalSigner & { getPublicKeyHex, signRaw, getPubKey }
type ProviderInterface = { getChainId, getNonce, call, estimateFee, addInvokeTransaction, addDeployAccountTransaction, waitForTransaction, getEvents, getAllEvents, getPromise, getNonceManager, fetchSync }
type AccountInterface = { address, signer, execute, getNonce, estimateFee, getPublicKeyHex, hashMessage, signMessage, executePaymaster, getProvider }
type PaymasterInterface = { isAvailable, getSupportedTokens, buildTypedData, executeTransaction, trackingIdToLatestHash, getNodeUrl }
type PaymasterDetails = { paymaster, feeMode, deploymentData?, gasTokenAddress? }
type PolicyInterface = { validate, recordUsage }
type BudgetInterface = { canAfford, consumeTransaction, refundTransaction, calculateCost, getBalance }
type Call = { contractAddress: string, entrypoint: string, calldata: { string } }
```

#### 3.9.2 HexUtils, BufferUtils, ByteArray

Utility modules for hex encoding/decoding, buffer manipulation, and Cairo ByteArray encoding (31-byte big-endian chunks).

#### 3.9.3 TestableDefaults

Injectable defaults for `HttpService`, `task.defer`, and `os.clock` that allow dependency injection in tests.

---

### 3.10 constants

SDK-wide constants exported as `Starknet.constants`.

```lua
-- Chain IDs (ASCII-encoded felt)
Constants.SN_MAIN = "0x534e5f4d41494e"
Constants.SN_SEPOLIA = "0x534e5f5345504f4c4941"

-- Class Hashes
Constants.OZ_ACCOUNT_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
Constants.ARGENT_ACCOUNT_CLASS_HASH = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"
Constants.BRAAVOS_ACCOUNT_CLASS_HASH = "0x03957f9f5a1cbfe918cedc2015c85200ca51a5f7506ecb6de98a5207b759bf8a"
Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH = "0x03d16c7a9a60b0593bd202f660a28c5d76e0403601d9ccc7e4fa253b6a70c201"

-- Contract Address Computation
Constants.CONTRACT_ADDRESS_PREFIX = "0x535441524b4e45545f434f4e54524143545f41444452455353"

-- Well-Known Token Addresses
Constants.ETH_TOKEN_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
Constants.STRK_TOKEN_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"

-- Transaction Versions
Constants.INVOKE_TX_V3 = "0x3"
Constants.DEPLOY_ACCOUNT_TX_V3 = "0x3"
Constants.DECLARE_TX_V3 = "0x3"

-- SNIP-9
Constants.ANY_CALLER = "0x414e595f43414c4c4552"

-- SDK
Constants.SDK_VERSION = "0.1.0"
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
}):andThen(function(result)
    return provider:waitForTransaction(result.transactionHash)
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
    classHash = Starknet.constants.OZ_ACCOUNT_CLASS_HASH,
    publicKey = "0x...",
})
```

---

## 5. Error Handling

### 5.1 Structured Error Hierarchy

All SDK errors use the structured `StarknetError` system with typed constructors and numeric error codes.

```lua
type StarknetErrorInstance = {
    _type: string,       -- error type (e.g. "RpcError", "ValidationError")
    message: string,     -- human-readable description
    code: number?,       -- SDK error code from ErrorCodes
    data: any?,          -- additional error data
}
```

### 5.2 Type Checking

```lua
local ok, err = pcall(function()
    -- some SDK operation that throws
end)

if not ok then
    local StarknetError = Starknet.errors.StarknetError

    if StarknetError.isStarknetError(err) then
        -- Structured error — use :is() for type checks
        if err:is("RpcError") then
            warn("RPC error:", err.message, "code:", err.code)
        elseif err:is("ValidationError") then
            warn("Invalid input:", err.message, "hint:", err.hint)
        end
    else
        -- Raw string error from Luau runtime
        warn("Unexpected:", tostring(err))
    end
end
```

### 5.3 Error Propagation

- Network operations propagate errors through Promise rejection
- Synchronous operations throw structured `StarknetError` instances via `error(StarknetError.xxx(...))`
- Caught errors in `pcall` preserve their metatable — `:is()` works after catch
- All RPC errors include the original JSON-RPC error code via `rpcCode` field

---

## 6. Dependencies

### 6.1 Required Dependencies

| Package | ID | Purpose |
|---------|----------|---------|
| roblox-lua-promise | `evaera/promise@^3.1.0` | Async/promise handling |

### 6.2 Dev Dependencies

| Tool | Purpose |
|------|---------|
| rojo | File-to-Roblox sync |
| wally | Package management |
| lune | Test runner |
| selene | Linting |
| stylua | Formatting |
| wally-package-types | IDE type generation |

---

## 7. Testing Strategy

### 7.1 Approach

All tests run via Lune outside of Roblox, enabling fast iteration without Studio. Each module has a corresponding `.spec.luau` file. The test runner supports `--parallel` flag for concurrent subprocess execution, per-test timing with slow-test warnings, and `beforeEach`/`afterEach` hooks.

### 7.2 Test Coverage

| Module | Spec Files | Approx Tests |
|--------|-----------|-------------|
| crypto | 11 | 437 |
| signer | 1 | 21 |
| provider | 8 | 400+ |
| tx | 4 | 120+ |
| wallet | 8 | 460+ |
| contract | 5 | 290+ |
| errors | 1 | 42+ |
| paymaster | 5 | 377 |
| shared | 3 | 30+ |
| fixtures/integration | 3 | 80+ |
| barrel/constants | 2 | 79+ |
| helpers | 1 | 26 |
| **Total** | **52** | **~2,778** |

### 7.3 Test Vectors

Crypto tests use known-good values generated by running equivalent operations through starknet.js. Test vectors are centralized in `tests/fixtures/test-vectors.luau` and cover:

- BigInt arithmetic edge cases
- Field element operations against known results
- Poseidon hash matching starknet.js `hash.computePoseidonHash`
- Pedersen hash matching starknet.js `hash.computePedersenHash`
- Keccak/selector matching starknet.js `hash.getSelectorFromName`
- ECDSA signatures matching `@scure/starknet` test suite
- Transaction hashes matching starknet.js `hash.calculateInvokeTransactionHash`
- Deploy account hashes matching starknet.js
- Address derivation for OZ, Argent, and Braavos account types

### 7.4 Integration Tests

Integration tests (in `tests/integration/`) make actual RPC calls to Sepolia:

- Read block number
- Call a deployed contract
- Full transaction flow (build, sign, submit, wait)

Gated behind `STARKNET_RPC_URL` environment variable and skipped in CI by default.

---

## 8. Configuration

### 8.1 Constants

The SDK exports constants (not network preset objects) via `Starknet.constants`:

```lua
local Constants = Starknet.constants

-- Use chain IDs directly
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://free-rpc.nethermind.io/sepolia-juno/",
})

-- Use class hashes
local address = Starknet.wallet.Account.computeAddress({
    classHash = Constants.OZ_ACCOUNT_CLASS_HASH,
    publicKey = "0x...",
})

-- Use token addresses
local strk = Starknet.contract.ERC20.new(
    Constants.STRK_TOKEN_ADDRESS,
    provider
)
```

---

## 9. Usage Examples

### 9.1 Read ERC-20 Balance

```lua
local Starknet = require(path.to.starknet-luau)

local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://free-rpc.nethermind.io/sepolia-juno/",
})

local strk = Starknet.contract.ERC20.new(
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

local strk = Starknet.contract.ERC20.new(
    Starknet.constants.STRK_TOKEN_ADDRESS,
    provider,
    account
)

strk:transfer("0xRECIPIENT", "1000000000000000000"):andThen(function(result)
    print("Transfer submitted:", result.transactionHash)
    return provider:waitForTransaction(result.transactionHash)
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
account:execute({ call1, call2 }):andThen(function(result)
    print("Game actions submitted:", result.transactionHash)
end)
```

### 9.4 NFT Ownership Check

```lua
local nft = Starknet.contract.ERC721.new("0xNFT_CONTRACT", provider)

nft:balance_of(playerWalletAddress):andThen(function(balance)
    if tonumber(balance) > 0 then
        grantAccess(player)
    else
        denyAccess(player)
    end
end)
```

### 9.5 Gasless Player Onboarding

```lua
local KeyStore = Starknet.wallet.KeyStore
local OnboardingManager = Starknet.wallet.OnboardingManager
local AvnuPaymaster = Starknet.paymaster.AvnuPaymaster

local keyStore = KeyStore.new({
    serverSecret = "your-server-secret",
})

local paymaster = AvnuPaymaster.new({ network = "sepolia" })

local onboarding = OnboardingManager.new({
    keyStore = keyStore,
    provider = provider,
    paymasterDetails = {
        paymaster = paymaster,
        feeMode = { mode = "sponsored" },
    },
})

-- Onboard a player (creates key, derives address, deploys account)
onboarding:onboard(player.UserId):andThen(function(result)
    print("Player onboarded at:", result.address)
    print("Already deployed:", result.alreadyDeployed)
end)
```

### 9.6 Sponsored Execution

```lua
local SponsoredExecutor = Starknet.paymaster.SponsoredExecutor
local PaymasterPolicy = Starknet.paymaster.PaymasterPolicy
local PaymasterBudget = Starknet.paymaster.PaymasterBudget

local executor = SponsoredExecutor.new({
    account = gameServerAccount,
    paymaster = paymaster,
    feeMode = { mode = "sponsored" },
    policy = PaymasterPolicy.new({
        allowedContracts = { "0xGAME_CONTRACT" },
        maxTxPerPlayer = 100,
        timeWindow = 3600,
    }),
    budget = PaymasterBudget.new({
        defaultTokenBalance = 1000,
        costPerTransaction = 1,
    }),
})

executor:execute(player.UserId, {
    gameContract:populate("claim_reward", { "0x1" }),
}):andThen(function(result)
    print("Sponsored tx:", result.transactionHash)
end)
```
