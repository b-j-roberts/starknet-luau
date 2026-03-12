# Documentation Guide Structure

Recommended guide set for the starknet-luau SDK, derived from the public API surface, example scripts, and integration patterns.

## Developer Personas

| Persona | Description | Entry Point |
|---------|-------------|-------------|
| **Game Builder** | Roblox dev adding blockchain features to their game. New to Starknet, knows Luau. | Wants to read data, send tokens, gate content |
| **Onboarding Engineer** | Building player wallet systems. Needs key management, deployment, paymasters. | Wants gasless onboarding, encrypted storage |
| **Integration Developer** | Experienced with Starknet, porting from starknet.js. Needs API parity knowledge. | Wants custom contracts, ABI codec, typed data |

## Reading Order

```
                    +---------------------+
                    |  1. Getting Started  |
                    +----------+----------+
                               |
                    +----------v----------+
                    | 2. Reading Blockchain|
                    |       Data          |
                    +----------+----------+
                               |
                    +----------v----------+
                    |  3. Accounts &      |
                    |    Transactions     |
                    +---+-----+------+----+
                        |     |      |
           +------------v+  +v------v--------+
           |4. Custom     |  |5. Player       |
           |  Contracts   |  |   Onboarding   |
           +--------------+  +-------+---------+
                                     |
                    +----------------v+    +------------------+
                    | 6. Sponsored    |    | 7. Events &      |
                    |   Transactions  |    |   Real-Time Data |
                    +-----------------+    +------------------+

                    +---------------------+
                    | 8. Production Config |  (read after 1-3)
                    +---------------------+
                    +---------------------+
                    | 9. Crypto Primitives |  (reference, any time)
                    +---------------------+
                    +---------------------+
                    | 10. API Reference    |  (reference, any time)
                    +---------------------+
```

---

## Guide 1: Getting Started

**Purpose:** Get a working RpcProvider connected and reading chain data in under 5 minutes.

**Audience:** Brand new -- first contact with the SDK.

**Prerequisites:** None.

**Key Topics:**
- Installing via Wally (`b-j-roberts/starknet-luau`) or pesde (`magic/starknet_luau`)
- Rojo project setup (sourcemap, `ReplicatedStorage.StarknetLuau`)
- Creating `RpcProvider.new({ nodeUrl = "..." })` -- the single entry point
- First call: `provider:getBlockNumber()` and `provider:getChainId()`
- Promise basics: `:andThen()`, `:catch()`, `:expect()` (blocking)
- **Roblox constraint: server-only** -- HttpService unavailable in LocalScripts
- Requiring the SDK: `local Starknet = require(ReplicatedStorage.StarknetLuau)`
- Namespace walkthrough: `Starknet.crypto`, `.provider`, `.wallet`, `.contract`, `.paymaster`, `.errors`

**Modules covered:** `RpcProvider.new()`, `provider:getBlockNumber()`, `provider:getChainId()`, `provider:getSpecVersion()`

---

## Guide 2: Reading Blockchain Data

**Purpose:** Query token balances, NFT ownership, contract storage, and block data -- no signing required.

**Audience:** Game builder adding read-only blockchain features.

**Prerequisites:** Guide 1.

**Key Topics:**
- ERC20 preset: `ERC20.new({ address, provider })` -- no account needed for reads
- Calling view functions: `token:name()`, `token:symbol()`, `token:decimals()`, `token:balance_of(address)`
- ERC721 preset: `ERC721.new({ address, provider })` -- `balance_of()`, `owner_of(tokenId)`
- **Gotcha: u256 return format** -- `{ low = "0x...", high = "0x..." }`, converting to number with precision warnings above 2^53
- Custom contract reads: `Contract.new({ abi, address, provider })` -- dynamic method dispatch
- Raw provider calls: `provider:call()`, `provider:getStorageAt()`, `provider:getClassHashAt()`
- Block queries: `provider:getBlockWithTxHashes()`, `provider:getBlockWithTxs()`
- **Constants module**: `Constants.ETH_ADDRESS`, `Constants.STRK_ADDRESS`, `Constants.OZ_CLASS_HASH`
- Practical pattern: NFT-gated game content (check balance -> grant access)

**Modules covered:** `ERC20`, `ERC721`, `Contract` (read path), `RpcProvider` (call/getStorageAt/block methods), `Constants`

---

## Guide 3: Accounts & Transactions

**Purpose:** Create accounts, sign transactions, and submit on-chain state changes.

**Audience:** Game builder ready to write to the chain.

**Prerequisites:** Guide 2.

**Key Topics:**
- `Account.fromPrivateKey({ privateKey, provider })` -- derive address, create signer internally
- `Account.new({ address, signer, provider })` -- manual construction
- Single transaction: `account:execute(calls)` -- orchestrates nonce -> fee estimate -> hash -> sign -> submit
- ERC20 transfer flow: `token:transfer(recipient, amount)` with account attached
- **Multicall**: `token:populate("transfer", args)` builds Call objects -> `account:execute(allCalls)` for atomic batch
- Fee control: `feeMultiplier` option (default 1.5x), `maxFee` cap, `resourceBounds` override
- Waiting for confirmation: `account:waitForReceipt(txHash, { retryInterval })` or `waitForConfirmation` option
- `dryRun` option: build + sign without submitting (pre-flight check)
- **Gotcha: private key range** -- must be in `[1, N-1]`, throws `KEY_OUT_OF_RANGE` (3003) otherwise
- **Gotcha: hex normalization** -- addresses and class hashes must be "0x"-prefixed, normalized via `BigInt.fromHex -> toHex`

**Modules covered:** `Account` (new, fromPrivateKey, execute, estimateFee, getNonce), `TransactionBuilder` (internal), `ERC20`/`ERC721` (write path), `CallData.encodeMulticall`

---

## Guide 4: Custom Contracts & ABI Encoding

**Purpose:** Interact with any Cairo contract using its ABI -- encode inputs, decode outputs, handle complex types.

**Audience:** Integration developer working with custom game contracts.

**Prerequisites:** Guide 3.

**Key Topics:**
- Defining ABI JSON: `type = "function"`, `type = "interface"` (nested items), `type = "struct"`, `type = "enum"`
- `Contract.new({ abi, address, provider, account })` -- dynamic method binding via `__index`
- View calls vs state-changing calls: `contract:call("method", args)` vs `contract:invoke("method", args)`
- `contract:populate("method", args)` for multicall batching
- `contract:getFunctions()`, `contract:hasFunction()`, `contract:getFunction()` for introspection
- **AbiCodec deep dive**: type system (felt252, bool, u8-u256, ByteArray, Array/Span, Option, Result, custom structs/enums)
- Encoding rules: felt = hex string, bool = true/false, u256 = "0x..." (auto-split to low/high), arrays = Luau tables
- **Gotcha: Option input flexibility** -- accepts `nil`, `{ Some = val }`, `{ None = true }`; always decodes to `{ variant = "Some"/"None", value = ... }`
- **Gotcha: enum variants are case-sensitive** -- must match ABI definition exactly
- ByteArray encoding for long strings (31-byte chunks, big-endian)
- Decoding multiple outputs: returns table keyed by output parameter name
- `PresetFactory.create(abi)` for building reusable contract wrappers
- Event decoding: `contract:parseEvents(receipt)`, `contract:queryEvents(filter)`

**Modules covered:** `Contract`, `AbiCodec` (buildTypeMap, resolveType, encode, decode, encodeInputs, decodeOutputs), `PresetFactory`, `CallData`

---

## Guide 5: Player Onboarding

**Purpose:** Generate, encrypt, store, and deploy player wallets for your game -- the full onboarding lifecycle.

**Audience:** Onboarding engineer building player-facing wallet systems.

**Prerequisites:** Guide 3.

**Key Topics:**
- **KeyStore**: encrypted private key persistence via Roblox DataStore
  - `KeyStore.new({ serverSecret, dataStoreName?, accountType? })` -- server secret for HMAC-SHA256 encryption
  - `:generateAndStore(playerId, provider)` -> `{ account, address }`
  - `:loadAccount(playerId, provider)` -> Account or nil
  - `:getOrCreate(playerId, provider)` -> `{ account, isNew }`
  - `:rotateSecret(newSecret, progressCallback?)` -- re-encrypt all keys
  - Security model: server secret must be kept secure, never exposed to clients
- **Account deployment**: `account:deployAccount(options?)` -- idempotent (checks getNonce first)
  - Counterfactual address: exists before on-chain deployment
  - Prefunding: `Account.checkDeploymentBalance()`, `Account.getDeploymentFundingInfo()`
  - Fee estimation: `account:estimateDeployAccountFee()`
- **Account types**: `AccountType.OZ`, `AccountType.ARGENT`, `AccountType.BRAAVOS`
  - `Account.detectAccountType(classHash)` -- identify existing accounts
  - `AccountType.custom(config)` -- register game-specific account implementations
- **AccountFactory**: batch creation for game launches
  - `factory:batchCreate(count, options)` -> array of Accounts
  - `factory:batchDeploy(accounts, options)` -> deployment results
- **OnboardingManager**: unified player lifecycle
  - `manager:onboard(playerId)` -> `{ account, address, isNew, deployed, txHash }`
  - `:getStatus(playerId)` -- no RPC call, reads from KeyStore
  - `:ensureDeployed(playerId)` -- retry deployment if pending
  - `:removePlayer(playerId)` -- cleanup on leave
- **Roblox integration pattern**: PlayerAdded -> onboard, PlayerRemoving -> cleanup
- **Gotcha: DataStore requires published place** -- won't work in Studio without mock

**Modules covered:** `KeyStore`, `OnboardingManager`, `AccountFactory`, `AccountType`, `Account` (deployAccount, computeAddress, static helpers)

---

## Guide 6: Sponsored (Gasless) Transactions

**Purpose:** Let players transact without holding gas tokens -- paymasters pay fees on their behalf.

**Audience:** Onboarding engineer or game builder who wants frictionless UX.

**Prerequisites:** Guide 3 + Guide 5.

**Key Topics:**
- **PaymasterRpc** (SNIP-29): raw paymaster client
  - `PaymasterRpc.new({ nodeUrl, accountAddress, dappName })` -- generic SNIP-29 client
  - `:isAvailable()`, `:getSupportedTokens()`, `:buildTypedData()`, `:executeTransaction()`
- **AvnuPaymaster**: AVNU-specific wrapper (recommended for Sepolia/Mainnet)
  - `AvnuPaymaster.new({ network, apiKey? })` -- auto-resolves endpoint
  - Pre-loaded known tokens, `getTokenAddress("STRK")`, network endpoint resolution
- **Account integration**: `account:executePaymaster(calls, paymasterDetails)`
  - Also: `account:estimatePaymasterFee()`, `account:deployWithPaymaster()`
- **PaymasterPolicy**: rule engine for sponsorship decisions
  - Whitelist/blacklist players, allowed contracts/methods, max fees, rate limits
  - `policy:validate(playerId, calls)` -> `{ allowed, reason }`
- **PaymasterBudget**: per-player token budget tracking
  - `budget:grantTokens(playerId, amount)`, `:canAfford()`, `:consumeTransaction()`
  - DataStore persistence via `:flush()`
- **SponsoredExecutor**: complete orchestration (recommended entry point)
  - `executor:execute(playerId, calls, options?)` -- validates policy -> checks budget -> builds typedData -> signs -> submits
  - Lifecycle callbacks: `onSubmitted`, `onConfirmed`, `onFailed`
  - Metrics: `executor:getMetrics()` -- totalExecutions, successRate
  - **Gotcha: metrics cap at 1000 players** -- use external telemetry for production
- **SNIP-9 Outside Execution**: alternative pattern where player signs off-chain, relayer submits
  - `OutsideExecution.getTypedData(config)` -> `account:signMessage(typedData)` -> relayer `account:execute()`
  - Time-bounded execution window, nonce for replay protection

**Modules covered:** `PaymasterRpc`, `AvnuPaymaster`, `PaymasterPolicy`, `PaymasterBudget`, `SponsoredExecutor`, `OutsideExecution`, `Account` (paymaster methods)

---

## Guide 7: Events & Real-Time Data

**Purpose:** Monitor on-chain events continuously and react to blockchain state changes in your game.

**Audience:** Game builder adding live blockchain features (leaderboards, trading, rewards).

**Prerequisites:** Guide 2.

**Key Topics:**
- **One-shot event queries**: `provider:getEvents(filter)` with pagination, `provider:getAllEvents(filter)` auto-paginated
- **Contract event helpers**: `contract:parseEvents(receipt)` for transaction receipts, `contract:queryEvents(filter)` for historical
- **EventPoller**: continuous background polling
  - `EventPoller.new({ provider, filter, onEvents, onCheckpoint, interval, _dataStore })` -- configurable
  - `:start()` -- blocking poll loop, use `task.spawn`
  - `:stop()` -- graceful shutdown via `game:BindToClose`
- **DataStore checkpoint persistence**: survive server restarts
  - `onCheckpoint` callback saves block number to DataStore
  - On restart, poller resumes from last checkpoint
  - `:setLastBlockNumber(n)` for manual recovery
- Event filter construction: contract address, event keys (selectors via `Keccak.getSelectorFromName()`)
- Event data unpacking: `block_number`, `transaction_hash`, `keys[]`, `data[]`
- **Gotcha: no WebSockets** -- Roblox only supports HTTP polling, latency = pollInterval
- Pattern: event-driven game state updates (NFT minted -> spawn item, transfer -> update ownership)

**Modules covered:** `EventPoller`, `RpcProvider` (getEvents, getAllEvents), `Contract` (parseEvents, queryEvents), `Keccak.getSelectorFromName`

---

## Guide 8: Production Configuration

**Purpose:** Tune the SDK for production: rate limiting, caching, nonce management, error handling, and monitoring.

**Audience:** Any developer moving from prototype to production.

**Prerequisites:** Guides 1-3.

**Key Topics:**
- **RequestQueue** (opt-in: `enableQueue: true`):
  - Priority buckets: HIGH (writes, immediate), NORMAL (reads, batched), LOW (events, batched)
  - `maxQueueDepth` (default 100), `maxBatchSize` (default 20)
  - Backpressure: `QUEUE_FULL` (2010) when depth exceeded
  - **Gotcha: task.defer batching** -- all fetch() calls in same frame are batched
- **ResponseCache** (opt-in: `enableCache: true`):
  - LRU eviction, per-method TTL: `chainId=0` (indefinite), `blockNumber=10s`, `storage/call=30s`
  - Block-aware invalidation: storage/call caches flush on new block
  - Never cached: write operations, nonce, transaction status
  - `provider:flushCache()` for manual invalidation
- **NonceManager** (opt-in: `enableNonceManager: true`):
  - Reserve -> confirm/reject pattern for concurrent transactions
  - `maxPendingNonces` (default 10), `autoResyncOnError` (default true)
  - **Gotcha: confirm must happen** or nonces leak (stuck pending)
- **Error handling strategy**:
  - `StarknetError` type hierarchy: `:is("RpcError")`, `:is("ValidationError")`, etc.
  - `ErrorCodes.isTransient(code)` for retry decisions
  - Exponential backoff for transient errors, fail-fast for validation
  - Error code ranges: 1000s validation, 2000s RPC, 3000s signing, 4000s ABI, 5000s tx, 7000s paymaster
- **Rate limiting**: default 450 req/min, configurable via `maxRequestsPerMinute`
- **Metrics**: `provider:getMetrics()` -- totalRequests, cacheHits, batchesSent, rateLimitHits
- Deployment checklist: HttpService enabled, DataStore published, server secrets secured

**Modules covered:** `RequestQueue`, `ResponseCache`, `NonceManager`, `StarknetError`, `ErrorCodes`, `RpcProvider` (configuration)

---

## Guide 9: Cryptography & Low-Level Primitives

**Purpose:** Reference for developers who need direct access to hash functions, field arithmetic, curve operations, or custom signing flows.

**Audience:** Integration developer building custom protocols or debugging.

**Prerequisites:** Guide 3 + familiarity with elliptic curve cryptography.

**Key Topics:**
- **BigInt**: buffer-based arbitrary precision (`fromHex`, `toHex`, `fromNumber`, `toBytes32`, arithmetic, modular ops)
  - **Gotcha: BigInt is a buffer alias** -- no opaque type wrapper in Luau
  - Barrett reduction: `createBarrettCtx(m)` -> `mulmodB(a, b, ctx)` for hot-path field ops
- **StarkField** (mod P) vs **StarkScalarField** (mod N): when to use which
  - StarkField: hash outputs, address computation, curve coordinates
  - StarkScalarField: private keys, nonces, signature components
- **StarkCurve**: point operations, `scalarMul`, `shamirMul` (Shamir's trick), `getPublicKey`
- **Hash functions**: `Poseidon.hash/hashMany`, `Pedersen.hash/hashChain`, `Keccak.keccak256/snKeccak`, `SHA256.hash/hmac`
  - When each is used: Poseidon (V3 tx hashes, SNIP-12 active), Pedersen (address, SNIP-12 legacy), Keccak (selectors), SHA256 (HMAC in RFC 6979)
- **ECDSA**: `sign(hash, privateKey)`, `verify(hash, pubKey, sig)`, RFC 6979 deterministic nonce
  - **Gotcha: Starknet-specific bits2int** -- differs from standard RFC 6979
- **StarkSigner**: `signHash(buffer)` returns `[r_hex, s_hex]` -- **expects buffer, not hex string**
- **TypedData** (SNIP-12): `getMessageHash()`, revision detection, Pedersen vs Poseidon
  - **Gotcha: "StarkNetDomain" (legacy) vs "StarknetDomain" (active)** -- capital N matters
- **TransactionHash**: `calculateInvokeTransactionHash()`, `calculateDeployAccountTransactionHash()` -- pure functions

**Modules covered:** `BigInt`, `StarkField`, `StarkScalarField`, `FieldFactory`, `StarkCurve`, `Poseidon`, `Pedersen`, `Keccak`, `SHA256`, `ECDSA`, `StarkSigner`, `TypedData`, `TransactionHash`

---

## Guide 10: API Reference

**Purpose:** Complete method-by-method reference for every public function in the SDK.

**Audience:** All developers -- lookup reference, not a reading guide.

**Prerequisites:** At least Guide 1.

**Key Topics:**
- Every public function signature, parameters, return types
- Organized by namespace: `crypto`, `signer`, `provider`, `tx`, `wallet`, `contract`, `paymaster`, `errors`, `constants`
- Type definitions: `RpcProviderConfig`, `AccountConfig`, `Call`, `FeeEstimate`, `ResourceBounds`, `ExecuteResult`, etc.
- Error code table: all codes with triggers and categories
- Constants: addresses, class hashes, chain IDs

---

## Why Each Guide Exists

| Guide | Reasoning |
|-------|-----------|
| **Getting Started** | Every SDK needs a 5-minute quickstart. RpcProvider is always the first thing created. |
| **Reading Blockchain Data** | 4 of 13 examples (`read-contract`, `nft-gate`, `leaderboard` reads, `event-listener`) need zero signing. Lowest-friction value. |
| **Accounts & Transactions** | The pivot from reading to writing. 8 of 13 examples need an Account. Where most developers spend time. |
| **Custom Contracts** | `leaderboard.luau` demonstrates custom ABI usage. AbiCodec's type system (Option, Result, ByteArray, enums) is non-trivial. |
| **Player Onboarding** | `player-onboarding.luau` and `deploy-account.luau` show this is a core use case. KeyStore, AccountFactory, and OnboardingManager form a cohesive story. |
| **Sponsored Transactions** | `sponsored-transaction.luau` and `outside-execution.luau` show the gasless UX path. Differentiator for Roblox games -- players shouldn't need gas tokens. |
| **Events & Real-Time Data** | `event-listener.luau` shows DataStore-backed polling. Essential for live game features (trade notifications, leaderboard updates). |
| **Production Configuration** | `provider-features.luau` demonstrates all three opt-in systems. Every production game needs these. Separated to avoid overwhelming new developers. |
| **Crypto Primitives** | The 9 crypto modules are powerful but niche. Most developers won't need direct access, but custom protocol builders need a reference. |
| **API Reference** | Standard reference doc. Generated from the 120+ public functions across 40+ modules. |

---

## Public API Surface Summary

The SDK exposes **9 top-level namespaces**, **40+ source modules**, and **120+ public functions/methods**.

### High-Level (Developer-Facing)
- `Account` -- Main account interface
- `Contract` -- Dynamic ABI-driven contract binding
- `ERC20`, `ERC721` -- Token standard presets
- `TransactionBuilder` -- Transaction orchestration
- `RpcProvider` -- Blockchain connectivity
- `KeyStore` -- Encrypted key storage
- `OnboardingManager` -- Player onboarding flow
- `AccountFactory` -- Batch account creation
- `SponsoredExecutor`, `PaymasterRpc`, `AvnuPaymaster` -- Sponsored transactions
- `PaymasterPolicy`, `PaymasterBudget` -- Sponsorship governance

### Low-Level (Building Blocks)
- `BigInt` -- Arbitrary precision arithmetic
- `StarkField`, `StarkScalarField`, `FieldFactory` -- Modular arithmetic
- `StarkCurve` -- Elliptic curve point operations
- `Poseidon`, `Pedersen`, `Keccak`, `SHA256` -- Hash functions
- `ECDSA` -- Signing primitives
- `StarkSigner` -- Key management

### Infrastructure (Internal/Optional)
- `RequestQueue` -- Request batching (opt-in)
- `ResponseCache` -- Response caching (opt-in)
- `NonceManager` -- Nonce tracking (opt-in)
- `EventPoller` -- Continuous event polling
- `JsonRpcClient` -- Low-level JSON-RPC transport
- `AbiCodec` -- Cairo ABI encoding/decoding
- `TypedData` -- SNIP-12 message hashing
- `OutsideExecution` -- SNIP-9 meta-transactions
- `CallData` -- Calldata encoding
- `TransactionHash` -- Hash computation
- `AccountType` -- Account implementation registry
- `PresetFactory` -- Custom preset creation

---

## Common Gotchas (Cross-Guide Reference)

These pitfalls appear across multiple guides and are worth calling out prominently:

1. **Hex normalization**: Always normalize addresses/hashes via `BigInt.fromHex -> toHex`. Unnormalized strings break lookup tables and comparisons.
2. **u256 format**: Returns `{ low, high }` -- two 128-bit felts, not a single value. Use `tonumber()` on low field only if value < 2^53.
3. **Private key range**: Must be in `[1, N-1]`. Zero and curve order N are invalid. N-1 is valid (generates -G).
4. **Buffer vs hex string**: `StarkSigner:signHash()` expects a buffer (BigInt), not a hex string. Convert with `BigInt.fromHex()` first.
5. **Resource bounds formats**: camelCase internally (TransactionHash), snake_case on the wire (RPC). TransactionBuilder handles conversion.
6. **Pedersen for addresses**: Address computation uses Pedersen hash, not Poseidon, despite V3 transactions using Poseidon.
7. **Server-only**: All network operations require HttpService, available only in server Scripts, not LocalScripts.
8. **No WebSockets**: Roblox lacks WebSocket support. EventPoller uses HTTP polling with configurable interval.
9. **DataStore requires published place**: KeyStore and EventPoller DataStore persistence only work in published experiences.
10. **Nonce manager confirmation**: Reserved nonces must be confirmed or rejected. Unconfirmed nonces leak and become unavailable.
11. **Option decoding**: Input accepts `nil`/`{Some=v}`/`{None=true}` flexibly, but output is always `{variant="Some"/"None", value=...}`.
12. **Enum case sensitivity**: Custom enum variant names must match ABI definitions exactly. Mismatches throw `UNKNOWN_ENUM_VARIANT` (4004).
13. **Fee multiplier**: Default 1.5x safety buffer. Too low risks rejection; too high wastes gas. Configurable per-transaction.
14. **SponsoredExecutor metrics cap**: Per-player metrics map caps at 1000 entries. Use external telemetry for production.
15. **SNIP-12 domain name**: `"StarkNetDomain"` (capital N) for legacy revision 0, `"StarknetDomain"` (lowercase n) for active revision 1.

---

## Error Code Reference

| Code Range | Category | Common Triggers |
|------------|----------|-----------------|
| 1000-1099 | Validation | Missing fields, invalid hex, string too long, non-ASCII |
| 2000-2099 | RPC/Network | HTTP failures, rate limiting, transaction reverted/rejected |
| 3000-3099 | Signing/Crypto | Invalid private key, key out of range, division by zero |
| 4000-4099 | ABI/Encoding | Unknown type, encode/decode mismatch, unknown enum variant |
| 5000-5099 | Transaction | Fee estimation failed, batch deploy error, nonce exhausted |
| 6000-6099 | Outside Execution | Invalid version, call validation failed, invalid time bounds |
| 7000-7099 | Paymaster | Token not supported, invalid signature, max amount too low |
| 8000-8099 | KeyStore/Onboarding | Key store error, decrypt error, secret invalid |
