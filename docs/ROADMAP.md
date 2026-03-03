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

# Phase 3: Paymaster Integration (SNIP-29)

Support sponsored transactions where the game developer pays gas on behalf of players. Generic SNIP-29 protocol client with AVNU-specific convenience layer.

**Rationale**: For mainstream Roblox games, players cannot be expected to hold STRK tokens. Paymaster support lets game developers sponsor gas costs, creating a seamless UX.

**Prerequisites**: TypedData (SNIP-12) ✅, ECDSA signing ✅, Account.signMessage() ✅

### 3.3.1 SNIP-9 Outside Execution Support

**Description**: Implement SNIP-9 Outside Execution typed data structures and signing for V1, V2, and V3-RC variants. This is the foundation for SNIP-29 paymaster integration, enabling `execute_from_outside` on user accounts.

**Requirements**:
- [ ] `OutsideExecution` typed data structures (V1 Pedersen, V2 Poseidon, V3-RC with FeeMode)
- [ ] `OutsideExecution` domain types: `StarkNetDomain` (V1), `StarknetDomain` (V2/V3-RC)
- [ ] V3-RC `FeeMode` union type: `NoFee` and `PayFee { tokenAddress, maxAmount, receiver }`
- [ ] Build `OutsideExecution` message from user calls + time bounds + nonce
- [ ] Sign `OutsideExecution` via existing `Account.signMessage()` (SNIP-12 typed data signing)
- [ ] Validate returned calls match user's submitted calls (+ optional appended fee transfer)

**Implementation Notes**:
- SNIP-9 is the foundation for SNIP-29: the paymaster submits `execute_from_outside` on the user's account
- V3-RC is preferred (separates fee info from calls), but V1/V2 needed for backward compat
- Builds on existing TypedData.luau (SNIP-12 revision LEGACY for V1, ACTIVE for V2/V3-RC)

---

### 3.3.2 PaymasterRpc Client (SNIP-29 Generic)

**Description**: Generic JSON-RPC client for any SNIP-29-compliant paymaster service. Provides the core protocol methods for building typed data, executing sponsored transactions, and querying supported tokens.

**Requirements**:
- [ ] `PaymasterRpc.new(config)` — config: `{ nodeUrl, headers?, timeout? }`
- [ ] `paymaster_getSupportedTokens()` → `{ tokenAddress, decimals, priceInStrk }[]`
- [ ] `paymaster_buildTypedData(userAddress, calls, gasTokenAddress, options?)` → SNIP-12 typed data
  - `options.accountClassHash` — for undeployed accounts
  - `options.deploymentData` — `{ classHash, calldata, salt, unique }` for deploy-via-paymaster
- [ ] `paymaster_execute(userAddress, typedData, signature)` → `{ transactionHash }`
- [ ] `isAvailable()` — health check (ping paymaster endpoint)
- [ ] Error handling: map paymaster JSON-RPC errors to `StarknetError.rpc()`
- [ ] Promise-based (all methods return Promises)

**Implementation Notes**:
- Pure JSON-RPC over HttpService, same pattern as `RpcProvider._fetchRpc()`
- Any SNIP-29-compliant paymaster works (AVNU, Cartridge, self-hosted)
- Inject `_httpRequest` for testability (same pattern as RpcProvider)

---

### 3.3.3 AVNU Paymaster Helpers

**Description**: Pre-configured convenience layer on top of PaymasterRpc for AVNU's paymaster service, with auto-selected endpoints and known token addresses per network.

**Requirements**:
- [ ] Pre-configured URLs: `AVNU_MAINNET = "https://starknet.paymaster.avnu.fi"`, `AVNU_SEPOLIA = "https://sepolia.paymaster.avnu.fi"`
- [ ] `AvnuPaymaster.new(config)` — extends PaymasterRpc with AVNU defaults
  - `config.network`: `"mainnet" | "sepolia"` → auto-selects URL
  - `config.apiKey` → sets `x-paymaster-api-key` header (enables gasfree/sponsored mode)
- [ ] Known AVNU token addresses (USDC, USDT, ETH, STRK, etc.) per network
- [ ] `getSupportedTokens()` with cached results (token list rarely changes)

**Implementation Notes**:
- Thin wrapper over PaymasterRpc, main value is ergonomics
- Without apiKey: gasless mode (user pays in alt token). With apiKey: gasfree/sponsored mode (game pays)

---

### 3.3.4 Account Paymaster Integration

**Description**: Extend the Account class with paymaster-routed execution methods, enabling sponsored transactions through any SNIP-29 paymaster.

**Requirements**:
- [ ] `Account:executePaymaster(calls, paymasterDetails)` — route execution through paymaster
  - `paymasterDetails.paymaster`: PaymasterRpc instance
  - `paymasterDetails.feeMode`: `{ mode: "default", gasToken: address }` or `{ mode: "sponsored" }`
  - `paymasterDetails.timeBounds?`: `{ executeAfter?, executeBefore? }`
- [ ] Flow: `buildTypedData` → validate calls → `signMessage(typedData)` → `execute(address, typedData, signature)`
- [ ] `Account:estimatePaymasterFee(calls, paymasterDetails)` — get fee estimate from paymaster
- [ ] Integration with NonceManager (paymaster uses outside execution nonce, not account nonce)

---

### 3.3.5 Paymaster Policy Config

**Description**: Pure validation module for defining allowed paymaster usage rules, preventing abuse by restricting which contracts, methods, and players can use sponsored gas.

**Requirements**:
- [ ] `PaymasterPolicy.new(config)` — define allowed usage rules
  - `config.allowedContracts`: `{ address }[]` — whitelist of contract addresses (empty = allow all)
  - `config.allowedMethods`: `{ contract, selector }[]` — whitelist of specific entrypoints
  - `config.allowedPlayers`: `{ playerId }[]` — whitelist of Roblox player IDs (empty = allow all)
  - `config.maxFeePerTx`: max fee amount per transaction (in gas token units)
  - `config.maxTxPerPlayer`: max transactions per player per time window
  - `config.timeWindow`: rolling window duration (seconds) for rate limits
- [ ] `policy:validate(playerId, calls)` — check if calls are allowed, returns `{ allowed, reason? }`
- [ ] `policy:validateFee(playerId, feeAmount)` — check fee against limits

**Implementation Notes**:
- Pure validation module, no persistence — composable with PaymasterBudget
- Game developer configures policy on server startup
- Designed to prevent abuse: only approved contracts/methods can use sponsored gas

---

### 3.3.6 Paymaster Budget & Token Management

**Description**: Per-player usage tracking via DataStoreService, managing virtual "paymaster tokens" that game developers grant as rewards or purchases to control sponsored transaction budgets.

**Requirements**:
- [ ] `PaymasterBudget.new(config)` — per-player usage tracking via DataStoreService
  - `config.dataStoreName`: DataStore name for persistence (default: `"StarknetPaymaster"`)
  - `config.defaultTokenBalance`: initial "paymaster tokens" per new player (default: 0)
  - `config.costPerTransaction`: tokens consumed per sponsored transaction (default: 1)
  - `config.costPerGasUnit?`: optional variable cost based on actual gas used
- [ ] `budget:getBalance(playerId)` → current paymaster token balance
- [ ] `budget:grantTokens(playerId, amount)` — add tokens (game rewards, purchases, etc.)
- [ ] `budget:revokeTokens(playerId, amount)` — remove tokens
- [ ] `budget:consumeTransaction(playerId, txCost?)` — deduct tokens for a sponsored tx
- [ ] `budget:canAfford(playerId, txCost?)` → boolean check before submitting
- [ ] `budget:getUsageStats(playerId)` → `{ totalTxCount, totalTokensSpent, balance, lastTxTime }`
- [ ] Atomic deduction: deduct tokens before submitting to paymaster, refund on failure
- [ ] In-memory cache with periodic DataStore flush (avoid DataStore rate limits)

**Implementation Notes**:
- "Paymaster tokens" are NOT on-chain — purely game-managed via Roblox DataStoreService
- Game devs grant tokens as rewards, purchases, or sign-up bonuses
- Integrates with PaymasterPolicy: `policy:validate()` → `budget:canAfford()` → `account:executePaymaster()`
- DataStoreService has rate limits (60 req/min per key); use in-memory cache with periodic writes
- Budget module is optional — game devs can use paymaster without it

---

### 3.3.7 Sponsored Transaction Flow (End-to-End)

**Description**: High-level orchestrator that chains the full sponsored transaction lifecycle: policy check, budget check, paymaster build, sign, execute, and budget deduction with error handling and retry logic.

**Requirements**:
- [ ] High-level `SponsoredExecutor` that chains: Policy check → Budget check → Paymaster build → Sign → Execute → Budget deduct
- [ ] Error handling: refund tokens on paymaster rejection, revert, or network failure
- [ ] Event callbacks: `onTransactionSubmitted`, `onTransactionConfirmed`, `onTransactionFailed`
- [ ] Retry with backoff on transient paymaster errors (502/503/504)
- [ ] Logging/metrics: track paymaster usage per player, per contract, per method

**Implementation Notes**:
- This is the "batteries included" module that ties 3.3.2-3.3.6 together
- Each sub-module is independently usable for advanced users

---

# Phase 4: Account Deployment

Full account deployment flow for creating new Starknet accounts from within Roblox. Supports OZ and Argent account types with prefunded deployment.

**Rationale**: Enables games to automatically create Starknet accounts for players as part of the onboarding flow.

**Prerequisites**: Poseidon ✅, Pedersen ✅, Account.computeAddress() ✅, ECDSA ✅, Constants.DEPLOY_ACCOUNT_TX_V3 ✅

### 3.4.1 DEPLOY_ACCOUNT V3 Transaction Hash

**Description**: Poseidon-based hash computation for DEPLOY_ACCOUNT V3 transactions, following the same pattern as INVOKE V3 but with deployment-specific fields.

**Requirements**:
- [ ] Poseidon-based hash computation for DEPLOY_ACCOUNT V3:
  ```
  poseidon("deploy_account", version, contract_address,
           poseidon(tip, l1_gas_bounds, l2_gas_bounds, l1_data_gas_bounds),
           poseidon(paymaster_data), chain_id, nonce,
           data_availability_modes, poseidon(constructor_calldata),
           class_hash, contract_address_salt)
  ```
- [ ] Encode resource bounds in same format as INVOKE V3 (`ResourceBounds` → felt encoding)
- [ ] `"deploy_account"` prefix constant (felt encoding of ASCII string)
- [ ] Nonce is always 0 for deployment transactions
- [ ] Test vectors cross-referenced against starknet.js `calculateDeployAccountTransactionHash`

**Implementation Notes**:
- Similar to `TransactionBuilder._computeTransactionHash()` but different prefix and fields
- Includes `class_hash` and `contract_address_salt` instead of sender calldata
- Add to `TransactionBuilder.luau` as `_computeDeployAccountHash()`

---

### 3.4.2 Deploy Account Transaction Builder

**Description**: Build, estimate fees for, sign, and format DEPLOY_ACCOUNT V3 transactions for RPC submission.

**Requirements**:
- [ ] `TransactionBuilder:buildDeployAccountTransaction(params)` — builds the DEPLOY_ACCOUNT V3 tx
  - `params.classHash`: account implementation class hash
  - `params.constructorCalldata`: compiled constructor args
  - `params.addressSalt`: salt for address computation (typically public key)
  - `params.contractAddress`: pre-computed counterfactual address
  - `params.resourceBounds?`: explicit resource bounds (or estimated)
- [ ] Fee estimation for deploy: use `estimateFee` with `DEPLOY_ACCOUNT` transaction type
- [ ] Sign the deploy account transaction hash with the signer
- [ ] Format for RPC submission: `starknet_addDeployAccountTransaction`

---

### 3.4.3 RPC: addDeployAccountTransaction

**Description**: Add the `addDeployAccountTransaction` RPC method to the provider for submitting deployment transactions and estimating their fees.

**Requirements**:
- [ ] Add `addDeployAccountTransaction(tx)` method to `RpcProvider.luau`
- [ ] Request format: `{ type: "DEPLOY_ACCOUNT", version: "0x3", ... }` per JSON-RPC spec
- [ ] Response: `{ transaction_hash, contract_address }`
- [ ] Add `estimateFee` support for `DEPLOY_ACCOUNT` transaction type (dummy sig + SKIP_VALIDATE)

---

### 3.4.4 Account.deployAccount() Method

**Description**: Full orchestration method on the Account class that handles the complete deployment lifecycle: address computation, existence check, fee estimation, transaction building, signing, submission, and confirmation.

**Requirements**:
- [ ] `Account:deployAccount(options?)` — full orchestration:
  1. Compute counterfactual address (use existing `Account.computeAddress()`)
  2. Check if already deployed (call `getNonce` — if it returns, account exists)
  3. Estimate deployment fee
  4. Build DEPLOY_ACCOUNT V3 transaction
  5. Sign transaction hash
  6. Submit via `addDeployAccountTransaction`
  7. Wait for confirmation (optional, via `waitForReceipt`)
- [ ] Return `{ transactionHash, contractAddress }`
- [ ] Idempotent: if account already deployed, return early without error
- [ ] `options.maxFee?`: override estimated fee
- [ ] `options.feeMultiplier?`: multiplier on estimated fee (default 1.5x, same as execute)
- [ ] `options.waitForConfirmation?`: boolean, default true

---

### 3.4.5 Multi-Account-Type Support (OZ + Argent)

**Description**: Account factory with support for multiple account contract types, providing constructor calldata builders and configurable class hashes for OZ and Argent accounts.

**Requirements**:
- [x] Account class hash constants:
  - OZ (v0.8.1): `0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f`
  - Argent (v0.4.0): `0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f`
- [x] Constructor calldata builders:
  - `AccountType.OZ(publicKey)` → `[publicKey]`
  - `AccountType.Argent(ownerKey, guardianKey?)` → `[owx0, ownerKey, 0x0]` / `[0x0, ownerKey, 0x1, 0x0, guardianKey]`
- [x] `AccountFactory.new(provider, accountType, signer)` — factory for creating deployable accounts
- [x] `factory:createAccount(options?)` → `{ account, address, deployTx }` (pre-deployment Account instance)
- [x] Document class hash versioning: these hashes correspond to specific contract versions

**Implementation Notes**:
- Class hashes change with new contract versions — make them configurable, not just constants
- Argent guardian defaults to `0x0` (no guardian) for simplicity
- Braavos support deferred to future task (proxy pattern + custom deploy signatures)

---

### 3.4.6 Prefunding Helper

**Description**: Utilities for checking whether a counterfactual address has sufficient balance for deployment and estimating the required funding amount.

**Requirements**:
- [x] `Account.checkDeploymentBalance(address, provider)` → `{ hasSufficientBalance, balance, estimatedFee }`
  - Calls `starknet_call` on ETH/STRK contract `balanceOf(address)` and compares to estimated deploy fee
- [x] `Account.getDeploymentFeeEstimate(classHash, constructorCalldata, salt, provider)` → estimated fee
- [x] Guide/helper for funding: return the counterfactual address so the game backend can send funds
- [x] Support checking both STRK and ETH balances (V3 txs use STRK for gas)

---

### 3.4.7 Batch Deploy for Game Onboarding

**Description**: Batch account creation and deployment for game onboarding flows, with rate limit integration, progress callbacks, and error tolerance.

**Requirements**:
- [ ] `AccountFactory:batchCreate(count, options?)` → `{ account, address }[]` (generate multiple accounts)
- [ ] `AccountFactory:batchDeploy(accounts, options?)` — deploy multiple accounts sequentially
  - Respects rate limits (integrates with RequestQueue)
  - Progress callback: `onDeployProgress(index, total, result)`
  - Continues on individual failure (collect errors, don't abort batch)
- [ ] Configurable concurrency: sequential (default) or parallel with max concurrency
- [ ] Summary report: `{ deployed, failed, skipped (already deployed) }`

**Implementation Notes**:
- Batch deploy is primarily a game-server operation during player onboarding
- Each deploy is an independent transaction (no multicall for DEPLOY_ACCOUNT)
- Consider integrating with NonceManager for the funding account (if game server funds from one account)

---

### 3.4.8 Bridge: Paymaster-Sponsored Deployment

**Description**: Deploy accounts via paymaster with zero prefunding, combining account deployment and first execution in a single paymaster call. *(Depends on Phase 3 Paymaster Integration — implement after both phases are complete.)*

**Requirements**:
- [ ] `Account:deployWithPaymaster(paymasterDetails)` — deploy via paymaster (zero prefunding needed)
- [ ] Pass `deploymentData` to `paymaster_buildTypedData` (SNIP-29 supports this)
- [ ] Combined deploy + first execute in single paymaster call (like PoW pattern)
- [ ] Flow: compute address → build deploymentData → paymaster buildTypedData → sign → paymaster execute

**Implementation Notes**:
- This is the ideal UX: player gets an account + executes first action with zero tokens
- Bridges Phase 3 (PaymasterRpc) and Phase 4 (Account deployment)
- The paymaster's relayer handles the DEPLOY_ACCOUNT tx and pays the fee

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
