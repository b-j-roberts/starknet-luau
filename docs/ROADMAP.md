# starknet-luau Development Roadmap

---

# Phase 2: Nice to Have

Features that enhance the MVP and make it fully production-ready and feature complete.

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

### 2.12 Encrypted Key Store (Player-Linked Accounts)

**Description**: Secure DataStoreService-backed persistence for player private keys, enabling automatic account recovery across sessions. Keys are encrypted at rest using a server-managed secret so that raw private keys are never stored in plaintext in Roblox's DataStore. This is a custodial model — the game developer is the custodian. SDK docs should point developers toward relay server mode (5.1) or wallet linking (5.6) for non-custodial alternatives.

**Requirements**:
- [ ] `KeyStore.new(config)` — encrypted key persistence via DataStoreService
  - `config.serverSecret`: hex string from a private ServerStorage config module (minimum 32 bytes / 64 hex chars, validated on construction)
  - `config.dataStoreName`: DataStore name (default: `"StarknetKeyStore"`)
  - `config.accountType`: account type for generated accounts (default: `"oz"`)
  - `config._dataStore`: injectable `DataStoreLike` for testing (same pattern as PaymasterBudget)
  - `config._clock`: injectable clock for testing (same pattern as PaymasterBudget)
- [ ] `keyStore:generateAndStore(playerId, provider)` → `{ account, address }` — generate new keypair via ECDSA, encrypt private key, persist to DataStore, return hydrated Account
- [ ] `keyStore:loadAccount(playerId, provider)` → `Account?` — load encrypted key from DataStore, decrypt, return hydrated Account via `Account.fromPrivateKey()` (or nil if no key exists)
- [ ] `keyStore:getOrCreate(playerId, provider)` → `{ account, isNew: boolean }` — load existing or generate + store new key (primary onboarding API for PlayerAdded)
- [ ] `keyStore:hasAccount(playerId)` → `boolean` — check existence without decrypting (reads address field only)
- [ ] `keyStore:deleteKey(playerId)` — remove key from DataStore via `RemoveAsync` (account deletion / GDPR Right to Erasure compliance)
- [ ] Encryption: `ciphertext = XOR(privateKey, HMAC-SHA256(serverSecret, tostring(playerId)))` — deterministic per-player keystream, no IV/nonce storage needed since each playerId is unique; uses existing `SHA256.hmac()` from crypto layer
- [ ] Validation: reject serverSecret shorter than 64 hex chars (32 bytes); reject empty strings and obvious weak values (e.g., all zeros)
- [ ] Security: never log, print, or expose decrypted private keys in error messages, DataStore error context, or stack traces
- [ ] `keyStore:rotateSecret(oldSecret, newSecret, playerIds)` — re-encrypt specified player keys with a new server secret; returns `{ rotated: number, failed: { playerId, error }[] }`
- [ ] DataStore format: `{ version = 1, encrypted = "0x...", address = "0x...", accountType = "oz", createdAt = <os.time()> }`
- [ ] Tag DataStore writes with `userIds = { playerId }` via `DataStoreSetOptions` for Roblox Right to Erasure webhook compliance
- [ ] ErrorCodes: `KEY_STORE_ERROR`, `KEY_STORE_DECRYPT_ERROR`, `KEY_STORE_SECRET_INVALID`
- [ ] Comprehensive test suite with MockDataStore (functional + failure modes), matching PaymasterBudget test patterns

**Implementation Notes**:
- Follow the `DataStoreLike` injection pattern from `PaymasterBudget.luau` — `{ GetAsync, SetAsync, RemoveAsync }` structural type, nil-check guards, fully testable in Lune without Roblox runtime.
- Address stored in plaintext alongside encrypted key — enables `hasAccount()` and address lookups without decryption overhead.
- `getOrCreate()` is the primary onboarding API — game servers call it on `PlayerAdded` to transparently create or restore player accounts.
- Integration with `Account.fromPrivateKey()` — decrypt → construct Account → return. Account type string stored in DataStore record for correct reconstruction.
- Server secret lives in a private ModuleScript in `ServerStorage` (not checked into source control). `HttpService:GetSecret()` returns an opaque `Secret` object that cannot be used as raw bytes for HMAC — a private config module is the pragmatic approach. SDK docs must emphasize: never commit the config module, never pass the secret to clients.
- Security model: Roblox infrastructure sees only encrypted blobs (cannot decrypt without serverSecret); game developer holds serverSecret (trust boundary); players cannot access ServerStorage, DataStore, or server memory.
- DataStore rate limits: `SetAsync` has a 6-second cooldown per key and a budget of `(60 + numPlayers × 10)` writes per minute per server. For mass onboarding (many players joining simultaneously), consider sequential processing or queuing rather than parallel `SetAsync` calls.
- GDPR: `deleteKey()` uses `RemoveAsync` (not `SetAsync(nil)`) for full removal. `userIds` tagging on writes enables Roblox's automated Right to Erasure webhook notifications.
- Dependencies: SHA256 + HMAC (crypto layer), Account.fromPrivateKey() (wallet layer), PaymasterBudget DataStoreLike pattern (paymaster layer) — all already implemented.

---

### 2.13 EventPoller lastBlockNumber Persistence

**Description**: Persist the EventPoller's `_lastBlockNumber` across server restarts so no events are missed during downtime. A 30-second Roblox server restart skips ~2 blocks — games relying on Transfer events for rewards or NFT minting would silently lose data. The persistence payload is a single number, making this high value for minimal complexity.

**Requirements**:
- [ ] Add `onCheckpoint: ((blockNumber: number) -> ())?` callback to `EventPollerConfig` — fires after each poll cycle that advances `_lastBlockNumber`, letting users persist to any backend
- [ ] Add `_dataStore: DataStoreLike?` and `checkpointKey: string?` to `EventPollerConfig` — reuse PaymasterBudget's `DataStoreLike` structural type (`{ GetAsync, SetAsync }`)
- [ ] On `start()`, if `_dataStore` is provided, call `GetAsync(checkpointKey)` to seed `_lastBlockNumber` and the initial `from_block` filter (skip seeding if result is nil or non-number)
- [ ] After each poll cycle that updates `_lastBlockNumber`, call `_dataStore:SetAsync(checkpointKey, maxBlock)` wrapped in `pcall` — log errors via `onError` but do not halt polling
- [ ] Fire `onCheckpoint(blockNumber)` after the DataStore write (or in place of it when `_dataStore` is nil) so callback-only users get the same hook
- [ ] Add `setLastBlockNumber(blockNumber: number)` public method — enables manual seeding before `start()` for users who restore state from their own backend via `onCheckpoint`
- [ ] Add `getCheckpointKey()` public method — returns the configured key (or nil), useful for debugging
- [ ] When both `_dataStore` and `onCheckpoint` are provided, DataStore write fires first, then callback (callback receives the block number regardless of DataStore success/failure)
- [ ] Zero behavior change when neither `_dataStore` nor `onCheckpoint` is configured — existing users unaffected
- [ ] Update `EventPollerConfig` type in `RpcTypes.luau` with the new optional fields
- [ ] Comprehensive tests: DataStore restore on start, checkpoint after events, pcall error handling, callback-only mode, setLastBlockNumber seeding, no-op when unconfigured

**Implementation Notes**:
- Follow PaymasterBudget's `DataStoreLike` injection pattern exactly — nil-check guards, `pcall` wrapping, mockable in Lune tests with a simple table `{ GetAsync = fn, SetAsync = fn }`.
- DataStore writes are infrequent (once per poll interval, default 10s) and tiny (single number), well within Roblox's `SetAsync` rate limits (6s cooldown per key, ~70+ writes/min budget).
- The `onCheckpoint` callback gives non-DataStore users (relay servers, custom backends) the same persistence capability without coupling to Roblox APIs.
- `setLastBlockNumber()` must also update the internal filter's `from_block` so a subsequent `start()` resumes from that point rather than re-fetching the chain tip.
- Consider storing `{ blockNumber = n, timestamp = os.time() }` in DataStore instead of a bare number — enables staleness detection on restore (e.g., warn if checkpoint is >1 hour old). Keep the `onCheckpoint` callback signature as just `(number)` for simplicity.

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
- Paymaster token top-up: product ID → `PaymasterBudget:grantTokens()` (see 3.3.6)
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
