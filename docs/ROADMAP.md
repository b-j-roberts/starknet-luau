# starknet-luau Development Roadmap

---

# Phase 1: MVP

The essential features needed for a working end-to-end Starknet integration from Roblox: create an account from a private key, build and sign transactions, submit them to the network, and read contract state.

### 1.1 BigInt -- Buffer-Based Arbitrary Precision Integers

**Description**: Implement arbitrary-precision integer arithmetic using buffer-backed f64 limb arrays, following rbx-cryptography's proven performance patterns. This is the foundation for all cryptographic operations.

**Requirements**:
- [ ] Buffer-based limb representation (11 limbs x 24 bits = 264 bits, little-endian, f64 values)
- [ ] Use `--!native` and `--!optimize 2` pragmas for all crypto modules
- [ ] Carry propagation via IEEE 754 rounding trick (`x + 3*2^k - 3*2^k`)
- [ ] Constructors: `fromNumber()`, `fromHex()`, `fromBytes()`, `zero()`, `one()`
- [ ] Conversions: `toHex()`, `toBytes()`, `toNumber()`
- [ ] Comparison: `eq()`, `lt()`, `lte()`, `cmp()`, `isZero()`
- [ ] Basic arithmetic: `add()`, `sub()`, `mul()`, `div()`, `mod()`, `divmod()`
- [ ] Bitwise: `shl()`, `shr()`, `band()`, `bor()`, `bitLength()`, `getBit()`
- [ ] Modular arithmetic: `addmod()`, `submod()`, `mulmod()`, `powmod()`, `invmod()`
- [ ] Barrett reduction: `createBarrettCtx()`, `mulmodB()` for ~30x speedup on repeated modular multiplication
- [ ] Unit tests for all operations against known values
- [ ] Edge case tests: zero, one, max field value, overflow, underflow

**Implementation Notes**:
- Reference rbx-cryptography's `MultiPrecision.luau` and `FieldPrime.luau` for buffer layout and carry patterns
- Keep intermediates under 2^53 (f64 precision limit) by using 24-bit limbs
- Barrett reduction is critical for Poseidon performance (91 rounds of field arithmetic)
- Test against values computed by JavaScript BigInt for correctness

---

### 1.2 StarkField -- Field Arithmetic over Stark Prime

**Description**: Implement modular arithmetic over P = 2^251 + 17 * 2^192 + 1, the Stark field prime. This is used by Poseidon, Pedersen, and all curve operations.

**Requirements**:
- [ ] Dedicated `Felt` type backed by buffer (not generic BigInt wrapper)
- [ ] Optimized reduction exploiting the sparse structure of P (overflow past bit 251 multiplied by -(17*2^192 + 1))
- [ ] Pre-computed Barrett context for P
- [ ] Constructors: `fromHex()`, `fromNumber()`, `zero()`, `one()`
- [ ] Arithmetic: `add()`, `sub()`, `mul()`, `square()`, `neg()`
- [ ] Inversion: `inv()` via Fermat's little theorem (a^(P-2) mod P)
- [ ] Square root: `sqrt()` for point decompression
- [ ] Conversions: `toHex()`, `toBigInt()`, `eq()`, `isZero()`
- [ ] Unit tests against starknet.js field arithmetic results

**Implementation Notes**:
- The Stark prime P = 2^251 + 17*2^192 + 1 has a sparse structure that enables efficient reduction
- Reference rbx-cryptography's `FieldPrime.luau` for the general approach (adapted from GF(2^255-19))
- Consider whether to use a specialized 12-limb representation or reuse BigInt with Barrett context

---

### 1.3 StarkScalarField -- Scalar Arithmetic over Curve Order

**Description**: Implement modular arithmetic over N (the curve order), needed for ECDSA scalar operations.

**Requirements**:
- [ ] Same API pattern as StarkField but with modulus N
- [ ] Pre-computed Barrett context for N
- [ ] Inversion: `inv()` via Fermat's little theorem (a^(N-2) mod N)
- [ ] Unit tests for scalar arithmetic

**Implementation Notes**:
- N = 0x0800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f
- Used for computing s = k^(-1) * (hash + r*privKey) mod N in ECDSA
- Could share implementation with StarkField using parameterized modulus

---

### 1.4 StarkCurve -- Elliptic Curve Point Operations

**Description**: Implement point arithmetic on the Stark curve (y^2 = x^3 + x + beta, short Weierstrass form with alpha=1).

**Requirements**:
- [ ] Point type: affine `{x: Felt, y: Felt}` and Jacobian `{x: Felt, y: Felt, z: Felt}`
- [ ] Curve constants: P, N, G (generator), alpha (1), beta
- [ ] Jacobian point addition (avoids field inversions)
- [ ] Jacobian point doubling
- [ ] Jacobian-to-affine conversion (single field inversion)
- [ ] Scalar multiplication via double-and-add
- [ ] Point validation: `isOnCurve()`, `isInfinity()`
- [ ] Public key derivation: `getPublicKey(privateKey)` = privateKey * G
- [ ] Unit tests: known public keys from starknet.js, point addition/doubling against expected values

**Implementation Notes**:
- Short Weierstrass addition formulas differ from Edwards (which rbx-cryptography uses)
- Jacobian coordinates: (X, Y, Z) represents affine (X/Z^2, Y/Z^3)
- Addition: X3 = R^2 - J - 2*V, Y3 = R*(V-X3) - 2*S1*J, Z3 = ((Z1+Z2)^2-Z1Z1-Z2Z2)*H
- Doubling: uses alpha=1 simplification
- Consider precomputed table for generator point to speed up pubkey derivation

---

### 1.5 Poseidon Hash

**Description**: Implement the Poseidon hash function over the Stark field using the Hades permutation strategy. This is the primary hash function for V3 transactions.

**Requirements**:
- [ ] Hades permutation: state width=3, rate=2, capacity=1
- [ ] Round structure: 4 full + 83 partial + 4 full = 91 total rounds
- [ ] Pre-computed round constants (91 * 3 = 273 field elements)
- [ ] Pre-computed MDS matrix (3x3)
- [ ] S-box: x^3 (cube) for Stark field
- [ ] Core API: `hash(a, b)`, `hashSingle(x)`, `hashMany(values)`
- [ ] Sponge construction for variable-length input (absorb rate=2 elements at a time)
- [ ] Unit tests matching starknet.js `hash.computePoseidonHash` and `hash.computePoseidonHashOnElements`

**Implementation Notes**:
- Performance critical: used for every transaction hash and some address computations
- Barrett reduction (from BigInt) is essential here -- 91 rounds * multiple field multiplications per round
- Round constants must be exact -- use values from the Starknet specification
- Consider inlining the MDS multiplication for the 3x3 case

---

### 1.6 Pedersen Hash

**Description**: Implement Pedersen hash using elliptic curve point operations. Used for legacy operations and some address computations.

**Requirements**:
- [ ] 4 pre-computed constant base points (P0, P1, P2, P3) from Starknet specification
- [ ] Process inputs in 248-bit + 4-bit chunks
- [ ] Point addition and scalar multiplication during hashing
- [ ] API: `hash(a, b)` returning a Felt
- [ ] Unit tests matching starknet.js `hash.computePedersenHash`

**Implementation Notes**:
- Slower than Poseidon due to EC operations, but required for compatibility
- Pre-computed lookup tables for the constant points can significantly speed this up
- The sn-testing-game implementation can be referenced for the algorithm flow (but rewritten with buffer-based crypto)

---

### 1.7 Keccak-256

**Description**: Implement Keccak-256 (Ethereum variant, NOT SHA-3) for function selector computation.

**Requirements**:
- [ ] Full Keccak-f[1600] permutation (24 rounds)
- [ ] 64-bit lanes via {hi, lo} 32-bit pairs using `bit32` library
- [ ] Theta, rho+pi, chi, iota steps
- [ ] Padding: 0x01 domain byte + MSB 0x80 (NOT SHA-3's 0x06)
- [ ] `keccak256(data: buffer) -> buffer` -- raw hash
- [ ] `snKeccak(data: buffer) -> Felt` -- Starknet keccak (250-bit mask)
- [ ] `getSelectorFromName(name: string) -> Felt` -- function selector from name
- [ ] Unit tests matching starknet.js `hash.getSelectorFromName`

**Implementation Notes**:
- 64-bit lane operations are the main complexity -- Luau only has 32-bit `bit32`
- Must split each 64-bit lane into hi/lo 32-bit words
- The sn-testing-game has a working implementation that can inform the approach
- Consider whether rbx-cryptography's SHA3 module can be adapted (it implements Keccak but with SHA-3 padding)

---

### 1.8 SHA-256 + HMAC

**Description**: Implement SHA-256 and HMAC-SHA-256 for RFC 6979 deterministic nonce generation used in ECDSA signing.

**Requirements**:
- [ ] FIPS 180-4 compliant SHA-256
- [ ] HMAC-SHA-256 (RFC 2104)
- [ ] API: `SHA256.hash(data: buffer) -> buffer`, `SHA256.hmac(key: buffer, message: buffer) -> buffer`
- [ ] Unit tests against known SHA-256 test vectors (NIST)

**Implementation Notes**:
- Could potentially delegate to rbx-cryptography if available as peer dependency
- Implement our own to avoid hard dependency
- 64 rounds with precomputed K constants

---

### 1.9 ECDSA Signing (RFC 6979)

**Description**: Implement Stark ECDSA signing with deterministic nonce generation for transaction signing.

**Requirements**:
- [ ] RFC 6979 deterministic K generation using HMAC-SHA-256
- [ ] Sign: `sign(messageHash, privateKey) -> {r, s}`
  - r = (k * G).x mod N
  - s = k^(-1) * (messageHash + r * privateKey) mod N
- [ ] Verify: `verify(messageHash, publicKey, signature) -> boolean`
  - w = s^(-1) mod N
  - R' = (messageHash * w) * G + (r * w) * publicKey
  - Check R'.x mod N == r
- [ ] Unit tests: sign known messages, verify signatures, cross-check with starknet.js

**Implementation Notes**:
- RFC 6979 prevents nonce reuse (which would leak the private key)
- The deterministic K allows reproducible signatures for testing
- Must handle edge cases: k = 0, r = 0 (retry with incremented counter)

---

### 1.10 StarkSigner

**Description**: Implement the Stark curve signer that wraps ECDSA operations behind the SignerInterface.

**Requirements**:
- [ ] Constructor: `StarkSigner.new(privateKey: string)` (hex string)
- [ ] `signer:getPubKey() -> Point` -- derive and cache public key
- [ ] `signer:signRaw(msgHash: Felt) -> {r, s}` -- ECDSA sign
- [ ] `signer:signTransaction(txHash: Felt) -> {string}` -- returns signature as felt array `[r_hex, s_hex]`
- [ ] `signer:getPublicKeyHex() -> string` -- public key x-coordinate as hex
- [ ] Unit tests for key derivation and signing

**Implementation Notes**:
- Cache the public key after first derivation (expensive EC scalar mul)
- Transaction signature format for Starknet: `[r, s]` as hex strings in the signature array

---

### 1.11 RPC Provider

**Description**: Implement a JSON-RPC client for Starknet using Roblox HttpService with Promise-based API.

**Requirements**:
- [ ] Constructor with configurable RPC URL, headers, rate limit, retry settings
- [ ] JSON-RPC 2.0 request/response handling
- [ ] Core methods (all returning Promises):
  - `getChainId()`
  - `getBlockNumber()`
  - `getNonce(contractAddress, blockId?)`
  - `call(request, blockId?)`
  - `estimateFee(transactions, simulationFlags?)`
  - `addInvokeTransaction(invokeTx)`
  - `getTransactionReceipt(txHash)`
  - `getTransactionStatus(txHash)`
  - `getEvents(filter)`
- [ ] `waitForTransaction(txHash, options?)` -- poll until confirmed
- [ ] `fetch(method, params)` -- raw RPC call for custom methods
- [ ] Built-in rate limiting (default: 450 req/min, leaving headroom below Roblox's 500)
- [ ] Retry with exponential backoff on transient failures
- [ ] Proper error handling: parse JSON-RPC errors, handle HTTP failures, timeout
- [ ] Type definitions for all request/response types (RpcTypes.luau)
- [ ] Unit tests with mocked HTTP responses (Lune's `net.serve` for mock server)

**Implementation Notes**:
- Use HttpService:RequestAsync for full control over method/headers/body
- Must handle both Roblox Studio (HttpEnabled flag) and published game environments
- Rate limiter should use a token bucket or sliding window algorithm
- For Lune tests, mock the HTTP layer using `net.serve` to create a local mock RPC server
- JSON-RPC request format: `{"jsonrpc": "2.0", "method": "starknet_<method>", "params": {...}, "id": <counter>}`

---

### 1.12 Calldata Encoder

**Description**: Encode Luau values into Starknet calldata (flat felt arrays) for transaction building.

**Requirements**:
- [ ] `encodeFelt(value)` -- single felt encoding
- [ ] `encodeU256(value)` -- split into low/high 128-bit felts
- [ ] `encodeBool(value)` -- 0 or 1
- [ ] `encodeArray(values)` -- length-prefixed array
- [ ] `encodeStruct(fields, abi?)` -- ordered field concatenation
- [ ] `encodeMulticall(calls)` -- multicall format for `__execute__`
  - Format: `[num_calls, to_0, selector_0, calldata_len_0, ...calldata_0, ...]`
- [ ] Helper: felt-from-string (short string encoding, max 31 ASCII chars)
- [ ] Unit tests against starknet.js `CallData.compile` results

**Implementation Notes**:
- Multicall encoding is the primary format since all account transactions go through `__execute__`
- Selectors are computed via `snKeccak(functionName)` from the Keccak module
- U256 splitting: low = value & ((1 << 128) - 1), high = value >> 128

---

### 1.13 Transaction Hash Computation

**Description**: Compute V3 INVOKE transaction hashes using Poseidon, following the Starknet specification.

**Requirements**:
- [ ] Resource bounds encoding: `(resource_name << 192) | (max_amount << 128) | max_price_per_unit`
  - Resource names: L1_GAS, L2_GAS, L1_DATA_GAS as ASCII-encoded felts
- [ ] Fee field hash: `poseidonHashMany([tip, l1_bound, l2_bound, l1_data_bound])`
- [ ] DA mode encoding: `(nonce_da_mode << 32) | fee_da_mode`
- [ ] Full V3 INVOKE hash: `poseidonHashMany([prefix, version, sender, fee_hash, paymaster_hash, chain_id, nonce, da_mode, deploy_data_hash, calldata_hash])`
- [ ] Unit tests matching starknet.js `hash.calculateInvokeTransactionHash`

**Implementation Notes**:
- The "invoke" prefix is `0x696e766f6b65` (ASCII encoding of "invoke")
- Default values: tip=0, paymaster_data=[], nonce_da_mode=0, fee_da_mode=0, account_deployment_data=[]
- Resource bounds default: l1_data_gas can be {0, 0} if not specified

---

### 1.14 Transaction Builder

**Description**: High-level transaction building that orchestrates nonce fetching, fee estimation, hash computation, signing, and submission.

**Requirements**:
- [ ] Constructor: `TransactionBuilder.new(provider)`
- [ ] `builder:execute(account, calls, options?)` -- full flow:
  1. Fetch nonce from provider (or use override)
  2. Fetch chain ID
  3. Encode calldata (multicall format)
  4. Estimate fees (or use override)
  5. Compute transaction hash (Poseidon)
  6. Sign hash with account's signer
  7. Submit via `addInvokeTransaction`
  8. Return transaction hash
- [ ] `builder:estimateFee(account, calls)` -- estimate without submitting
- [ ] `builder:waitForReceipt(txHash, options?)` -- poll for receipt
- [ ] Unit tests for the build flow (mocked provider)

**Implementation Notes**:
- Fee estimation adds a buffer (e.g., 50%) to the estimated gas to avoid transaction failure
- The execute method returns a Promise that resolves with the transaction hash
- Consider adding a `dryRun` option that builds and signs but doesn't submit

---

### 1.15 Account

**Description**: High-level account management combining signer, provider, and address.

**Requirements**:
- [ ] `Account.new(config)` -- from address + signer + provider
- [ ] `Account.fromPrivateKey(config)` -- derives address from private key using OZ class hash
- [ ] `Account.computeAddress(config)` -- static address derivation
  - Formula: `poseidonHash(["STARKNET_CONTRACT_ADDRESS", deployer, salt, classHash, poseidonHash(constructorCalldata)]) mod 2^251`
- [ ] Account types: OZ class hash constants
- [ ] `account:execute(calls, options?)` -- convenience wrapper
- [ ] `account:getNonce()` -- fetch current nonce
- [ ] `account:estimateFee(calls)` -- estimate fee for calls
- [ ] Unit tests for address derivation against starknet.js

**Implementation Notes**:
- For OZ accounts: constructorCalldata = [publicKey], salt = publicKey
- Address derivation is pure computation (no network calls)
- The Account wraps TransactionBuilder internally for execute/estimateFee

---

### 1.16 Contract Interface (Basic)

**Description**: ABI-driven contract interaction for reading state and building transaction calls.

**Requirements**:
- [ ] `Contract.new(config)` -- from ABI + address + provider + optional account
- [ ] ABI parsing: extract function names, input types, output types, state mutability
- [ ] `contract:call(method, args?)` -- read-only contract call (view functions)
- [ ] `contract:invoke(method, args?, options?)` -- write transaction (external functions)
- [ ] `contract:populate(method, args?)` -- build a Call object for multicall batching
- [ ] Dynamic method generation via `__index` metamethod:
  - View functions -> `:call()` automatically
  - External functions -> `:invoke()` automatically
- [ ] Basic response parsing: felt arrays -> Luau values based on ABI output types
- [ ] Unit tests with sample ABI and mocked RPC

**Implementation Notes**:
- ABI format follows the Cairo ABI JSON specification
- Dynamic dispatch: `contract.transfer(...)` resolves to invoke or call based on `state_mutability`
- For MVP, support basic types (felt252, u256, bool, address) -- complex types (structs, enums) in Phase 2

---

### 1.17 ERC-20 Preset

**Description**: Pre-built contract interface for ERC-20 token interaction.

**Requirements**:
- [ ] Built-in ERC-20 ABI (standard OpenZeppelin Cairo implementation)
- [ ] `ERC20.new(address, provider, account?)` -- constructor
- [ ] Read methods: `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(owner)`, `allowance(owner, spender)`
- [ ] Write methods: `transfer(recipient, amount)`, `approve(spender, amount)`, `transferFrom(sender, recipient, amount)`
- [ ] Unit tests with mocked responses

---

### 1.18 ERC-721 Preset

**Description**: Pre-built contract interface for ERC-721 NFT interaction.

**Requirements**:
- [ ] Built-in ERC-721 ABI
- [ ] `ERC721.new(address, provider, account?)` -- constructor
- [ ] Read methods: `name()`, `symbol()`, `ownerOf(tokenId)`, `balanceOf(owner)`, `getApproved(tokenId)`, `isApprovedForAll(owner, operator)`
- [ ] Write methods: `transferFrom(from, to, tokenId)`, `approve(to, tokenId)`, `setApprovalForAll(operator, approved)`
- [ ] Unit tests with mocked responses

---

### 1.19 Main Entry Point + Barrel Exports

**Description**: Create the top-level `init.luau` that exports the full SDK as a single require.

**Requirements**:
- [ ] `src/init.luau` exports:
  - `Starknet.crypto` -- all crypto primitives
  - `Starknet.signer` -- signer types
  - `Starknet.provider` -- RPC provider
  - `Starknet.tx` -- transaction building
  - `Starknet.wallet` -- account management
  - `Starknet.contract` -- contract interaction
  - `Starknet.constants` -- network constants, class hashes, token addresses
- [ ] Each submodule `init.luau` properly exports its contents

---

### 1.20 Test Fixtures and Integration Tests ✅

**Description**: Create comprehensive test fixtures from starknet.js and basic integration tests.

**Requirements**:
- [x] Generate `tests/fixtures/test-vectors.luau` containing:
  - Known BigInt arithmetic results
  - Poseidon hash outputs for specific inputs
  - Pedersen hash outputs for specific inputs
  - Keccak/selector outputs for known function names
  - ECDSA signatures for known (message, privKey) pairs
  - Transaction hashes for known transaction parameters
  - Account addresses for known (privKey, classHash) pairs
- [x] Create integration test that performs end-to-end flow against Sepolia (gated by env var)
- [x] All crypto tests pass with values matching starknet.js output

---

### 1.21 Examples

**Description**: Create practical example scripts demonstrating common use cases.

**Requirements**:
- [ ] `examples/read-contract.luau` -- read ERC-20 balance from Sepolia
- [ ] `examples/sign-transaction.luau` -- build, sign, and submit a token transfer
- [ ] `examples/nft-gate.luau` -- check NFT ownership for player gating
- [ ] `examples/multicall.luau` -- batch multiple contract calls in one transaction
- [ ] `examples/leaderboard.luau` -- read/write an onchain leaderboard contract
- [ ] Each example includes comments explaining the flow

---

# Phase 2: Nice to Have

Features that enhance the MVP and make it fully production-ready and feature complete.

### 2.1 Advanced ABI Parsing and Encoding

**Description**: Full Cairo ABI support including complex types, structs, enums, options, and results.

**Requirements**:
- [ ] Struct encoding/decoding -- ordered field serialization with recursive type resolution
- [ ] Enum encoding/decoding -- variant index + variant data
- [ ] `Option<T>` support -- `CairoOption` with `Some`/`None` variants
- [ ] `Result<T, E>` support -- `CairoResult` with `Ok`/`Err` variants
- [ ] `Array<T>` and `Span<T>` with typed element encoding
- [ ] `ByteArray` support -- long string encoding (chunks of 31 bytes + pending word)
- [ ] Tuple support
- [ ] Nested type resolution (struct containing struct, array of structs, etc.)
- [ ] ABI-aware response decoding -- parse felt arrays back into Luau tables based on output types
- [ ] Unit tests for each type against starknet.js `CallData.compile` and `CallData.decodeParameters`

**Implementation Notes**:
- Cairo ABIs use a flat representation where struct/enum definitions are listed separately
- Type resolution requires building a type map from the ABI's `type_definitions` section
- ByteArray encoding: split into chunks of 31 bytes, with a final pending_word and pending_word_len

---

### 2.2 Multiple Account Type Support

**Description**: Support Argent X and Braavos account derivation in addition to OpenZeppelin.

**Requirements**:
- [ ] Argent X account derivation:
  - Class hash constant
  - Constructor calldata: `[publicKey, guardian]` (guardian=0 for no guardian)
  - Guardian key support (optional)
- [ ] Braavos account derivation:
  - Class hash constant
  - Braavos-specific constructor format
- [ ] Account type detection from class hash
- [ ] `Account.fromPrivateKey` accepts `accountType` parameter
- [ ] Unit tests for address derivation for each account type

**Implementation Notes**:
- Different account types use different constructor calldata formats
- Argent uses a guardian key for extra security (can be 0 to disable)
- Braavos has its own deployment proxy pattern

---

### 2.3 Event Querying and Polling

**Description**: Robust event querying with pagination and polling capabilities.

**Requirements**:
- [ ] `provider:getEvents(filter)` with proper continuation token handling
- [ ] `provider:getAllEvents(filter)` -- auto-paginate through all matching events
- [ ] Event polling helper: periodically check for new events matching a filter
- [ ] Event parsing: decode event data using contract ABI
- [ ] `contract:parseEvents(receipt)` -- extract and decode typed events from a transaction receipt
- [ ] `contract:queryEvents(filter?)` -- query events filtered to this contract's address

**Implementation Notes**:
- Roblox lacks WebSockets, so polling is the only option for "real-time" events
- Consider a configurable polling interval (default: 10 seconds)
- Rate limiting is critical here to avoid exhausting the 500 req/min budget

---

### 2.4 SNIP-12 Typed Data Signing

**Description**: Implement SNIP-12 (Starknet's equivalent of EIP-712) for off-chain message signing.

**Requirements**:
- [ ] Type hash computation from type definitions
- [ ] Struct hash computation (recursive encoding of typed data)
- [ ] Domain separator computation
- [ ] Message hash: `poseidonHash("StarkNet Message", domainHash, accountAddress, messageHash)`
- [ ] `account:signMessage(typedData)` -- sign typed data with account's signer
- [ ] `account:hashMessage(typedData)` -- compute message hash without signing
- [ ] Unit tests matching starknet.js `typedData.getMessageHash`

**Implementation Notes**:
- SNIP-12 is important for off-chain signatures used in protocols like gasless approvals
- The type system is recursive (types can reference other types)

---

### 2.5 Improved Error Handling

**Description**: Rich, typed error system with actionable error messages.

**Requirements**:
- [ ] Error class hierarchy: `StarknetError`, `RpcError`, `SigningError`, `AbiError`, etc.
- [ ] RPC errors include the original JSON-RPC error code and detailed message
- [ ] Transaction revert errors include the revert reason and execution trace (if available)
- [ ] Validation errors with clear messages about what's wrong and how to fix it
- [ ] `error:is(errorType)` for type checking in catch handlers
- [ ] Custom error codes for SDK-specific errors (rate limit, timeout, invalid argument)

---

### 2.6 Request Rate Limiting and Queuing

**Description**: Sophisticated rate limiting to maximize throughput within Roblox's 500 req/min constraint.

**Requirements**:
- [ ] Token bucket rate limiter with configurable capacity and refill rate
- [ ] Request queue with priority levels (transaction submission > reads > events)
- [ ] Automatic request batching for compatible RPC methods
- [ ] Backpressure: return meaningful errors when queue is full
- [ ] Metrics: expose request count, queue depth, and rate limit headroom
- [ ] Per-provider rate limit tracking (support multiple providers)

**Implementation Notes**:
- Default budget: 450 req/min per provider (leaving 50 for other game HTTP needs)
- Priority queue ensures transaction submissions aren't delayed by polling
- Consider JSON-RPC batch requests to reduce HTTP call count

---

### 2.7 Response Caching

**Description**: Cache commonly requested data to reduce RPC calls.

**Requirements**:
- [ ] Configurable cache for:
  - Chain ID (cache indefinitely)
  - Block number (cache for N seconds)
  - Contract class hashes (cache indefinitely for deployed contracts)
  - ABI definitions (cache indefinitely)
  - Storage values (cache with configurable TTL)
- [ ] Cache invalidation on new block or manual flush
- [ ] LRU eviction for bounded memory usage
- [ ] Bypass cache option for fresh data

---

### 2.8 Nonce Manager

**Description**: Intelligent nonce management for sequential transaction submission.

**Requirements**:
- [ ] Local nonce tracking per account address
- [ ] Automatic increment after successful submission
- [ ] Invalidation on transaction failure or revert
- [ ] Parallel transaction support with nonce reservation
- [ ] Automatic re-sync with on-chain nonce on error

**Implementation Notes**:
- Critical for games that submit multiple transactions in quick succession
- Without local nonce tracking, each transaction needs a getNonce RPC call

---

### 2.9 Performance Optimization

**Description**: Profile and optimize the crypto layer for maximum throughput.

**Requirements**:
- [ ] Benchmark suite for all crypto operations (BigInt, field ops, Poseidon, ECDSA)
- [ ] Optimize Poseidon: inline MDS multiplication, minimize allocations
- [ ] Optimize scalar multiplication: windowed method or NAF encoding
- [ ] Pre-computed generator table for faster public key derivation
- [ ] Montgomery's trick for batch affine conversions
- [ ] Pedersen lookup table optimization
- [ ] Profile and reduce GC pressure (minimize table allocations in hot paths)

---

### 2.10 Expanded RPC Method Coverage

**Description**: Implement remaining Starknet JSON-RPC methods beyond the MVP set.

**Requirements**:
- [ ] `getBlockWithTxs(blockId)` -- full block with transactions
- [ ] `getBlockWithReceipts(blockId)` -- block with transaction receipts
- [ ] `getTransactionByHash(txHash)` -- full transaction details
- [ ] `getStorageAt(address, key, blockId)` -- raw storage reads
- [ ] `getClass(blockId, classHash)` -- contract class definition
- [ ] `getClassHashAt(blockId, address)` -- class hash of deployed contract
- [ ] `getClassAt(blockId, address)` -- class at address
- [ ] `estimateMessageFee(msg)` -- L1→L2 message fee estimation
- [ ] `getSpecVersion()` -- RPC spec version
- [ ] `getSyncingStats()` -- node sync status

---

### 2.11 Multi-Version RPC Spec Support (v0.7, v0.8+)

**Description**: Support multiple Starknet JSON-RPC spec versions so the SDK works across providers running different API versions.

**Requirements**:
- [ ] Detect spec version via `starknet_specVersion` on provider initialization
- [ ] Research v0.7 → v0.8 breaking changes:
  - New methods added in v0.8: `starknet_getBlockHeader`, `starknet_getMessagesStatus`, `starknet_getCompiledCasm`
  - Response schema changes (e.g., transaction receipt format, fee estimation fields)
  - Parameter format changes (block ID encoding, resource bounds)
  - Deprecated or renamed fields
- [ ] Adapter layer that normalizes responses to a common internal format
- [ ] Version-specific request formatters where parameter shapes differ
- [ ] Configuration option: `specVersion` override (skip auto-detect)
- [ ] Unit tests with mocked v0.7 and v0.8 responses to verify both paths
- [ ] Document which public RPC providers run which spec version

**Implementation Notes**:
- Current SDK was built against v0.7 method names (which are unchanged in v0.8)
- Main risk is response schema changes, not method renames
- ZAN public endpoints already run v0.8.1; dRPC Sepolia also runs v0.8.1
- Consider a `compat` module that maps between versions rather than forking the provider

---

### 2.12 Pesde Package Support

**Description**: Add support for the Pesde package manager alongside Wally.

**Requirements**:
- [ ] Create `pesde.toml` / `pesde.yaml` manifest
- [ ] Ensure package structure is compatible with both Wally and Pesde
- [ ] Document installation via both package managers
- [ ] CI: publish to both registries on release

---

### 2.13 Documentation and Guides

**Description**: Comprehensive documentation beyond the code-level API.

**Requirements**:
- [ ] Getting Started guide (installation, basic setup, first transaction)
- [ ] Crypto module deep dive (understanding the primitives)
- [ ] Contract interaction guide (reading state, writing transactions, multicall)
- [ ] Account management guide (key generation, address derivation, nonce handling)
- [ ] Common patterns guide (NFT gating, token rewards, leaderboards)
- [ ] Roblox-specific considerations (rate limits, server-side only, security)
- [ ] Migration guide from sn-testing-game patterns to starknet-luau
- [ ] API reference generated from type annotations

---

# Phase 3: Future

Features, improvements, and explorations to take the project to the next level. These are not needed for feature completion but would expand the SDK's capabilities significantly.

### 3.1 Relay Server Mode

**Description**: Support delegating transaction signing and submission to an external relay server.

**Features**:
- Relay provider that sends unsigned intents to a relay endpoint
- Relay server reference implementation (TypeScript/Node.js)
- Support for server-side session keys held by the relay
- API key / game secret authentication for relay requests
- Automatic failover between pure Luau and relay modes

**Rationale**: Many production games will want to keep private keys off the Roblox game server entirely. A relay server pattern (like the sn-testing-game uses) provides better key isolation and can handle paymaster integration server-side.

---

### 3.2 Session Keys

**Description**: Implement session key support for gasless, popup-free game transactions.

**Features**:
- Session key generation (ephemeral key pair per game session)
- Policy definition (which contracts/methods are auto-approved)
- Session key registration on the account contract
- Auto-signing within policy constraints
- Session expiration and renewal
- Integration with Cartridge Controller's session key standard

**Rationale**: Session keys are essential for gaming UX. Players shouldn't need to approve every game action. Cartridge Controller has proven this model works well for Starknet games.

---

### 3.3 Paymaster Integration (SNIP-29)

**Description**: Support sponsored transactions where the game developer pays gas on behalf of players.

**Features**:
- SNIP-29 paymaster protocol support
- Integration with AVNU paymaster (Sepolia + Mainnet)
- Integration with Cartridge paymaster
- Alternative token gas payment (pay in ETH, USDC, etc. instead of STRK)
- Budget tracking and management
- Sponsored transaction building flow

**Rationale**: For mainstream Roblox games, players cannot be expected to hold STRK tokens. Paymaster support lets game developers sponsor gas costs, creating a seamless UX.

---

### 3.4 Account Deployment

**Description**: Full account deployment flow for creating new Starknet accounts from within Roblox.

**Features**:
- Deploy account transactions (V3)
- Counterfactual address computation
- Pre-funding flow (fund address before deployment)
- Multi-account-type deployment (OZ, Argent, Braavos)
- Batch deploy for game player onboarding

**Rationale**: Enables games to automatically create Starknet accounts for players as part of the onboarding flow.

---

### 3.5 Contract Declaration

**Description**: Declare new contract classes on Starknet from within the SDK.

**Features**:
- Sierra contract compilation support
- CASM generation or pre-compiled CASM import
- Declare transaction (V3) building and signing
- Idempotent declare (skip if already declared)
- Combined declare-and-deploy flow

**Rationale**: Useful for games that deploy per-player contracts or evolve their contract logic over time.

---

### 3.6 Streaming / SSE Support

**Description**: Real-time event streaming using Roblox's `CreateWebStreamClient` for Server-Sent Events.

**Features**:
- SSE client for streaming new block headers
- Event subscription via streaming endpoints
- Automatic reconnection on disconnect
- Event buffering during connection gaps
- Integration with RPC nodes that support SSE

**Rationale**: Polling is limited to 500 req/min. SSE allows near-real-time event notifications without consuming HTTP request budget.

---

### 3.7 Multi-Signer Support

**Description**: Support additional signer types beyond Stark ECDSA.

**Features**:
- Ethereum secp256k1 signer (for ETH-key Starknet accounts)
- Custom signer protocol for game-specific signing schemes
- Privy integration for social login-derived keys
- Hardware wallet signer (for admin operations)

**Rationale**: The Starknet ecosystem supports multiple signature schemes. Games may want to support players who use Ethereum wallets or social login.

---

### 3.8 Wallet Linking Patterns

**Description**: Pre-built patterns for linking external Starknet wallets to Roblox player accounts.

**Features**:
- Signature-based wallet verification (player signs a message with their wallet, game verifies)
- QR code generation for mobile wallet connection
- DataStoreService integration for persistent wallet links
- On-chain wallet registry contract
- Wallet linking UI components (Roact/Fusion)

**Rationale**: For games that want players to connect their existing wallets rather than using game-managed accounts.

---

### 3.9 Onchain Game Primitives

**Description**: Higher-order utilities for common onchain game patterns.

**Features**:
- Onchain leaderboard read/write helpers
- Token reward distribution patterns
- NFT ownership verification and gating
- Onchain game state polling and caching
- Turn-based game state management
- Verifiable randomness integration (VRF)

**Rationale**: These are the most common patterns Roblox developers will need. Pre-built utilities dramatically reduce integration time.

---

### 3.10 Starknet ID Integration

**Description**: Resolve `.stark` domain names to addresses and vice versa.

**Features**:
- `getStarkName(address)` -- resolve address to .stark name
- `getAddressFromStarkName(name)` -- resolve .stark name to address
- Display formatting helpers (show .stark name in game UI)

**Rationale**: Better UX for displaying player identities in-game.

---

### 3.11 Testing Framework Enhancements

**Description**: Advanced testing utilities for SDK consumers.

**Features**:
- Mock provider for unit testing game code without RPC calls
- Mock signer for testing without real private keys
- Devnet integration (starknet-devnet-rs) for local testing
- Snapshot-based testing for contract state
- Gas usage reporting in tests

**Rationale**: Game developers need to test their Starknet integrations without hitting real networks.

---

### 3.12 Roblox Plugin

**Description**: A Roblox Studio plugin for configuring and managing starknet-luau.

**Features**:
- Network configuration UI (select mainnet/sepolia, set RPC URL)
- Contract ABI import wizard
- Account management (generate keys, view balance)
- Transaction explorer (view recent transactions)
- Event monitor (real-time event display)

**Rationale**: A Studio plugin would dramatically improve the developer experience for setting up and debugging Starknet integrations.

---

### 3.13 TypeScript SDK Bridge

**Description**: A TypeScript companion package that mirrors the Luau SDK's API for relay server development.

**Features**:
- Shared type definitions between Luau and TypeScript
- Relay server template using the TypeScript bridge
- Consistent API surface across Luau (game) and TypeScript (server)
- Shared test vectors

**Rationale**: Many production setups will have a Luau game client + TypeScript relay server. Shared APIs reduce context switching.

---

### 3.14 Performance Benchmarking Suite

**Description**: Comprehensive benchmarks for crypto operations and network throughput.

**Features**:
- Micro-benchmarks for each crypto primitive (BigInt ops, field mul, Poseidon, ECDSA)
- Transaction throughput benchmarks (txs/second under rate limits)
- Memory profiling (GC pressure, allocation patterns)
- Comparison against sn-testing-game implementation
- CI-integrated performance regression detection

**Rationale**: Performance is critical for game servers. Regression detection prevents unintentional slowdowns.
