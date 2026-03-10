# starknet-luau Development Roadmap

---

# Phase 1: Core SDK ✅

Foundation layer — all crypto primitives, signing, provider, transaction building, account management, and contract interaction. Fully implemented.

### 1.1–1.9 Cryptographic Primitives ✅

- [x] **BigInt**: Buffer-based arbitrary precision integers with 24-bit f64 limbs, Barrett reduction (94 tests)
- [x] **StarkField**: Field arithmetic over Stark prime P = 2^251 + 17·2^192 + 1 (51 tests)
- [x] **StarkScalarField**: Scalar arithmetic over curve order N (54 tests)
- [x] **StarkCurve**: Elliptic curve point operations with Jacobian coordinates (53 tests)
- [x] **Poseidon**: Hades permutation hash (width=3, 91 rounds) for V3 transaction hashing (22 tests)
- [x] **Pedersen**: EC point-based hash for legacy address computation (17 tests)
- [x] **Keccak**: Keccak-256 (Ethereum variant) for function selector computation (24 tests)
- [x] **SHA256**: FIPS 180-4 SHA-256 + HMAC-SHA-256 for RFC 6979 nonce generation (31 tests)
- [x] **ECDSA**: Stark ECDSA signing with RFC 6979, cross-referenced against @scure/starknet (37 tests)

### 1.10 StarkSigner ✅

- [x] Key derivation, transaction signing, public key caching (21 tests)

### 1.11 RpcProvider ✅

- [x] JSON-RPC 2.0 client with Promise-based async, token bucket rate limiting, exponential backoff retry (59 tests)
- [x] EventPoller: configurable polling for contract events with start/stop lifecycle
- [x] RequestQueue: 3-bucket priority queue with JSON-RPC batching (82 tests)
- [x] ResponseCache: LRU cache with per-method TTL and block-based invalidation (89 tests)
- [x] NonceManager: per-address local nonce tracking with parallel reservation and auto-resync (64 tests)
- [x] Expanded RPC methods: `getBlockWithTxs`, `getBlockWithReceipts`, `getTransactionByHash`, `getStorageAt`, `getClassHashAt`, `getClassAt`, `getSpecVersion` (39 tests)

### 1.12 TransactionBuilder ✅

- [x] V3 INVOKE and DEPLOY_ACCOUNT transaction orchestration: nonce fetch, fee estimation, hash computation, signing, submission (36 tests)
- [x] TransactionHash: Poseidon-based V3 INVOKE and DEPLOY_ACCOUNT hash computation
- [x] CallData: multicall calldata encoding for `__execute__`

### 1.13 Account ✅

- [x] Address derivation, transaction execution, fee estimation for OpenZeppelin, Argent X, and Braavos account types (80 tests)

### 1.14 Contract ✅

- [x] ABI-driven dynamic dispatch — view functions via `call()`, external functions via `invoke()`, with `populate()` for multicall batching (60 tests)
- [x] AbiCodec: recursive encoder/decoder for all Cairo types — felt, bool, u256, structs, enums, Option, Result, Array, Span, ByteArray, tuples (109 tests)
- [x] ERC-20 preset: standard token interface with read/write methods (35 tests)
- [x] ERC-721 preset: NFT interface with ownership and approval methods (41 tests)

### 1.15 Error System ✅

- [x] Typed error hierarchy: RpcError, SigningError, AbiError, ValidationError, TransactionError (42 tests)
- [x] ErrorCodes: categorized constants across 7 ranges (1000s–7000s)

### 1.16 Infrastructure ✅

- [x] Constants: chain IDs, class hashes, token addresses, transaction versions, SDK version
- [x] Main entry point: single `require()` barrel export for the entire SDK
- [x] Dual package manager support: Wally + Pesde
- [x] 5 example scripts, 7 documentation guides

---

# Phase 2: Nice to Have

Features that enhance the MVP and make it fully production-ready and feature complete.

### 2.9 Performance Optimization

**Description**: Profile and optimize the crypto layer for maximum throughput.

**Requirements**:
- [ ] Benchmark suite for all crypto operations (BigInt, field ops, Poseidon, ECDSA)
- [x] Optimize scalar multiplication: 4-bit windowed method + Shamir's trick (done in refactor R.4.1)
- [ ] Optimize Poseidon: inline MDS multiplication, minimize allocations
- [ ] Pre-computed generator table for faster public key derivation
- [ ] Montgomery's trick for batch affine conversions
- [ ] Pedersen lookup table optimization
- [ ] Profile and reduce GC pressure (minimize table allocations in hot paths)

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

### 2.12 Encrypted Key Store (Player-Linked Accounts) ✅

**Status**: Implemented — `src/wallet/KeyStore.luau` (72 tests)

- [x] `KeyStore.new(config)` — encrypted key persistence via DataStoreService with serverSecret, dataStoreName, accountType, injectable DataStore/clock
- [x] `keyStore:generateAndStore(playerId, provider)` → `{ account, address }`
- [x] `keyStore:loadAccount(playerId, provider)` → `Account?`
- [x] `keyStore:getOrCreate(playerId, provider)` → `{ account, isNew: boolean }`
- [x] `keyStore:hasAccount(playerId)` → `boolean`
- [x] `keyStore:deleteKey(playerId)` — GDPR Right to Erasure via `RemoveAsync`
- [x] Encryption: `XOR(privateKey, HMAC-SHA256(serverSecret, tostring(playerId)))`
- [x] Validation: reject serverSecret < 64 hex chars
- [x] `keyStore:rotateSecret(oldSecret, newSecret, playerIds)` — re-encryption with new secret
- [x] DataStore format with version, encrypted key, address, accountType, createdAt
- [x] `userIds` tagging for Roblox Right to Erasure webhook compliance
- [x] ErrorCodes: `KEY_STORE_ERROR`, `KEY_STORE_DECRYPT_ERROR`, `KEY_STORE_SECRET_INVALID`

---

### 2.13 EventPoller lastBlockNumber Persistence ✅

**Status**: Implemented — `EventPoller.luau` updated + `RpcTypes.luau` types (26 tests)

- [x] `onCheckpoint` callback in `EventPollerConfig`
- [x] `_dataStore` / `checkpointKey` config fields using `DataStoreLike` injection
- [x] DataStore restore on `start()`, checkpoint after each poll cycle
- [x] `setLastBlockNumber(blockNumber)` public method for manual seeding
- [x] `getCheckpointKey()` public method
- [x] DataStore write fires first, then callback; pcall-wrapped error handling
- [x] Zero behavior change when unconfigured

---

# Phase 3: Paymaster & Standards ✅

SNIP-9 outside execution, SNIP-12 typed data, SNIP-29 paymaster support, and account type extensibility. Fully implemented.

### 3.1 SNIP-12 TypedData ✅

**Status**: Implemented — `src/wallet/TypedData.luau` (43 tests)

- [x] LEGACY revision (Pedersen, `"StarkNetDomain"`) and ACTIVE revision (Poseidon, `"StarknetDomain"`)
- [x] Recursive type encoding with dependency resolution
- [x] Merkle tree support with sorted pair hashing
- [x] Preset types (u256, TokenAmount, NftId) for ACTIVE revision
- [x] `Account:hashMessage(typedData)` and `Account:signMessage(typedData)` integration

### 3.2 SNIP-9 Outside Execution ✅

**Status**: Implemented — `src/wallet/OutsideExecution.luau` (82 tests)

- [x] V1, V2, V3 meta-transaction support
- [x] `getTypedData()` — build SNIP-12 typed data for off-chain signing
- [x] `buildExecuteFromOutsideCall()` — construct the on-chain submission call
- [x] `validateCalls()` — validate calls against outside execution constraints
- [x] Interface ID constants for V1/V2

### 3.3 SNIP-29 Paymaster ✅

**Status**: Implemented across 5 modules (377+ tests)

- [x] **PaymasterRpc** (`src/paymaster/PaymasterRpc.luau`, 67 tests): SNIP-29 JSON-RPC client with `buildTypedData()`, `executeTransaction()`, sponsored and self-paid fee modes
- [x] **AvnuPaymaster** (`src/paymaster/AvnuPaymaster.luau`, 61 tests): AVNU-specific paymaster integration with gas token selection
- [x] **PaymasterPolicy** (`src/paymaster/PaymasterPolicy.luau`, 66 tests): policy engine — contract/method allowlists, player whitelists, rate limits, daily caps
- [x] **PaymasterBudget** (`src/paymaster/PaymasterBudget.luau`, 105 tests): per-player budget tracking with DataStore persistence, dirty write batching
- [x] **SponsoredExecutor** (`src/paymaster/SponsoredExecutor.luau`, 78 tests): orchestrator combining policy, budget, paymaster for gasless execution

### 3.4 Account Paymaster Integration ✅

- [x] `Account:estimatePaymasterFee()` — estimate fees via paymaster
- [x] `Account:executePaymaster()` — execute transactions with paymaster sponsorship
- [x] `Account:deployWithPaymaster()` — deploy accounts with paymaster sponsorship
- [x] `Account:getDeploymentData()` — get deployment data for paymaster

### 3.5 Multi-Account-Type Support ✅

**Status**: Implemented — `src/wallet/AccountType.luau` + `AccountFactory.luau` (52 tests)

- [x] AccountType: OZ, Argent, and `custom()` callable constructors with validation
- [x] AccountFactory: `createAccount()`, `batchCreate()`, `batchDeploy()` for game onboarding
- [x] Prefunding helpers: `getDeploymentFeeEstimate()`, `checkDeploymentBalance()`, `getDeploymentFundingInfo()` (44 tests)
- [x] Batch deploy for game onboarding (53 tests)

### 3.6 Encrypted Key Store & Player Onboarding ✅

- [x] **KeyStore** (`src/wallet/KeyStore.luau`, 72 tests) — see 2.12
- [x] **OnboardingManager** (`src/wallet/OnboardingManager.luau`, 37 tests): player lifecycle management — `onboard()`, `ensureDeployed()`, `getStatus()`, `removePlayer()`

---

# Phase 4: Deploy Account ✅

V3 DEPLOY_ACCOUNT transaction support — hash computation, transaction building, RPC integration, and full Account orchestration. Fully implemented.

### 4.1 DEPLOY_ACCOUNT V3 Hash ✅

**Status**: Implemented — `TransactionHash.calculateDeployAccountTransactionHash()` (23 tests)

### 4.2 Deploy Account Transaction Builder ✅

**Status**: Implemented — `TransactionBuilder.deployAccount()` + `estimateDeployAccountFee()` (39 tests)

### 4.3 Account Deploy Orchestration ✅

**Status**: Implemented — `Account:deployAccount()` (58 tests)

- [x] Idempotency check: getNonce success → `{ alreadyDeployed = true }`
- [x] Fee estimation with configurable `maxFee` cap
- [x] `waitForConfirmation` option (default true)
- [x] NonceManager integration (reserve/confirm/reject pattern)
- [x] RPC `starknet_addDeployAccountTransaction` submission

### 4.4 Paymaster-Sponsored Deployment ✅

**Status**: Implemented — `Account:deployWithPaymaster()` (25 tests)

---

# Phase 5: Future

Features, improvements, and explorations to take the project to the next level. These are not needed for feature completion but would expand the SDK's capabilities significantly.

### 5.1 Relay Server Mode

**Description**: Support delegating transaction signing and submission to an external relay server.

**Features**:
- Relay provider that sends unsigned intents to a relay endpoint
- Relay server reference implementation (TypeScript/Node.js)
- Support for server-side session keys held by the relay
- API key / game secret authentication for relay requests
- Automatic failover between pure Luau and relay modes

**Rationale**: Many production games will want to keep private keys off the Roblox game server entirely. A relay server pattern (like the sn-testing-game uses) provides better key isolation and can handle paymaster integration server-side.

---

### 5.2 Session Keys

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

### 5.3 Contract Declaration

**Description**: Declare new contract classes on Starknet from within the SDK.

**Features**:
- Sierra contract compilation support
- CASM generation or pre-compiled CASM import
- Declare transaction (V3) building and signing
- Idempotent declare (skip if already declared)
- Combined declare-and-deploy flow

**Rationale**: Useful for games that deploy per-player contracts or evolve their contract logic over time.

---

### 5.4 Streaming / SSE Support

**Description**: Real-time event streaming using Roblox's `CreateWebStreamClient` for Server-Sent Events.

**Features**:
- SSE client for streaming new block headers
- Event subscription via streaming endpoints
- Automatic reconnection on disconnect
- Event buffering during connection gaps
- Integration with RPC nodes that support SSE

**Rationale**: Polling is limited to 500 req/min. SSE allows near-real-time event notifications without consuming HTTP request budget.

---

### 5.5 Multi-Signer Support

**Description**: Support additional signer types beyond Stark ECDSA.

**Features**:
- Ethereum secp256k1 signer (for ETH-key Starknet accounts)
- Custom signer protocol for game-specific signing schemes
- Privy integration for social login-derived keys
- Hardware wallet signer (for admin operations)

**Rationale**: The Starknet ecosystem supports multiple signature schemes. Games may want to support players who use Ethereum wallets or social login.

---

### 5.6 Wallet Linking Patterns

**Description**: Pre-built patterns for linking external Starknet wallets to Roblox player accounts.

**Features**:
- Signature-based wallet verification (player signs a message with their wallet, game verifies)
- QR code generation for mobile wallet connection
- DataStoreService integration for persistent wallet links
- On-chain wallet registry contract
- Wallet linking UI components (Roact/Fusion)

**Rationale**: For games that want players to connect their existing wallets rather than using game-managed accounts.

---

### 5.7 Onchain Game Primitives

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

### 5.8 Starknet ID Integration

**Description**: Resolve `.stark` domain names to addresses and vice versa.

**Features**:
- `getStarkName(address)` -- resolve address to .stark name
- `getAddressFromStarkName(name)` -- resolve .stark name to address
- Display formatting helpers (show .stark name in game UI)

**Rationale**: Better UX for displaying player identities in-game.

---

### 5.9 Testing Framework Enhancements

**Description**: Advanced testing utilities for SDK consumers.

**Features**:
- Mock provider for unit testing game code without RPC calls
- Mock signer for testing without real private keys
- Devnet integration (starknet-devnet-rs) for local testing
- Snapshot-based testing for contract state
- Gas usage reporting in tests

**Rationale**: Game developers need to test their Starknet integrations without hitting real networks.

---

### 5.10 Roblox Plugin

**Description**: A Roblox Studio plugin for configuring and managing starknet-luau.

**Features**:
- Network configuration UI (select mainnet/sepolia, set RPC URL)
- Contract ABI import wizard
- Account management (generate keys, view balance)
- Transaction explorer (view recent transactions)
- Event monitor (real-time event display)

**Rationale**: A Studio plugin would dramatically improve the developer experience for setting up and debugging Starknet integrations.

---

### 5.11 TypeScript SDK Bridge

**Description**: A TypeScript companion package that mirrors the Luau SDK's API for relay server development.

**Features**:
- Shared type definitions between Luau and TypeScript
- Relay server template using the TypeScript bridge
- Consistent API surface across Luau (game) and TypeScript (server)
- Shared test vectors

**Rationale**: Many production setups will have a Luau game client + TypeScript relay server. Shared APIs reduce context switching.

---

### 5.12 Performance Benchmarking Suite

**Description**: Comprehensive benchmarks for crypto operations and network throughput.

**Features**:
- Micro-benchmarks for each crypto primitive (BigInt ops, field mul, Poseidon, ECDSA)
- Transaction throughput benchmarks (txs/second under rate limits)
- Memory profiling (GC pressure, allocation patterns)
- Comparison against sn-testing-game implementation
- CI-integrated performance regression detection

**Rationale**: Performance is critical for game servers. Regression detection prevents unintentional slowdowns.

---

### 5.13 Marketplace Bridge (Robux ↔ On-Chain)

**Description**: Bridge between Roblox's `MarketplaceService` (Robux purchases) and Starknet on-chain actions. Allows game developers to trigger arbitrary contract calls, mint tokens/NFTs, or top up paymaster budgets in response to Robux transactions — while remaining testable in pure Luau/Lune via dependency injection.

**Features**:
- `MarketplaceBridge.new(config)` — core bridge with injected `_marketplaceService` (real in Roblox, mock in Lune)
- Arbitrary contract call mapping: product ID → `{ contractAddress, entrypoint, calldataBuilder }`
- ERC-20 preset: product ID → `erc20:transfer` or `erc20:mint` with configurable amount
- ERC-721 preset: product ID → `erc721:mint` with metadata/tokenId generation
- Paymaster token top-up: product ID → `PaymasterBudget:grantTokens()`
- Idempotent receipt processing: track `receiptId → transactionHash` to prevent double-grants
- `ProcessReceipt` handler that orchestrates: validate receipt → resolve action → execute on-chain tx → confirm → grant
- Receipt persistence via DataStoreService (injected, mockable) for crash recovery
- Event callbacks: `onPurchaseStarted`, `onChainTxSubmitted`, `onChainTxConfirmed`, `onPurchaseFailed`
- Refund / compensation logic when on-chain tx fails after Robux is spent

**Presets**:
- `MarketplaceBridge.erc20Purchase(productId, tokenAddress, amount)` — one-liner for token grants
- `MarketplaceBridge.erc721Purchase(productId, contractAddress, tokenIdFn)` — one-liner for NFT mints
- `MarketplaceBridge.paymasterTopUp(productId, tokenAmount)` — one-liner for paymaster budget credit

**Neutrality (Lune/Test Compatibility)**:
- All Roblox services injected: `_marketplaceService`, `_dataStoreService`, `_players`
- Core logic (receipt → action resolution → tx building) is pure Luau with zero Roblox API calls
- Full test suite runnable via `lune run` with mock services

**Rationale**: The most natural monetization path for Roblox games using Starknet. Players buy with Robux (familiar), game triggers on-chain actions (transparent ownership). Presets for ERC-20/ERC-721/paymaster top-up cover 90% of use cases out of the box. Dependency injection preserves the SDK's test-anywhere philosophy.
