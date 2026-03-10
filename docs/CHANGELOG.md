# Changelog

All notable changes to starknet-luau will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

Major feature release adding paymaster (SNIP-29), deploy account V3, encrypted key management, player onboarding, and 60+ refactoring improvements. Test suite grew from 1,429 to 2,846 tests.

### Added

#### Paymaster — SNIP-29 (`paymaster`)
- **PaymasterRpc**: SNIP-29 JSON-RPC client with `buildTypedData()`, `executeTransaction()`, sponsored and self-paid fee modes (67 tests)
- **AvnuPaymaster**: AVNU-specific paymaster integration with gas token selection and method selector normalization (61 tests)
- **PaymasterPolicy**: Policy engine — contract/method allowlists, player whitelists, rate limits, daily caps (66 tests)
- **PaymasterBudget**: Per-player budget tracking with DataStore persistence, dirty write batching, GDPR compliance (105 tests)
- **SponsoredExecutor**: Orchestrator combining policy, budget, and paymaster for gasless execution with metrics tracking (78 tests)

#### Account Paymaster Integration (`wallet`)
- `Account:estimatePaymasterFee()` — estimate fees via paymaster
- `Account:executePaymaster()` — execute transactions with paymaster sponsorship
- `Account:deployWithPaymaster()` — deploy accounts with paymaster sponsorship
- `Account:getDeploymentData()` — get deployment data for paymaster

#### Deploy Account V3 (`tx`, `wallet`)
- `TransactionHash.calculateDeployAccountTransactionHash()` — Poseidon-based V3 DEPLOY_ACCOUNT hash computation (23 tests)
- `TransactionBuilder.deployAccount()` — full deploy flow: chainId → estimate fees → hash → sign → submit (39 tests)
- `TransactionBuilder.estimateDeployAccountFee()` — estimate-only deploy flow
- `Account:deployAccount()` — full orchestration with idempotency check (getNonce success → already deployed), configurable `maxFee` cap, `waitForConfirmation` option, NonceManager integration (58 tests)
- RPC method: `starknet_addDeployAccountTransaction` with `DeployAccountTransactionV3` type

#### Multi-Account-Type Support (`wallet`)
- **AccountType**: OZ, Argent, and `custom()` callable constructors with validation (52 tests)
- **AccountFactory**: `createAccount()`, `batchCreate()`, `batchDeploy()` for game onboarding (53 tests)
- Prefunding helpers: `getDeploymentFeeEstimate()`, `checkDeploymentBalance()`, `getDeploymentFundingInfo()` (44 tests)

#### SNIP-9 Outside Execution (`wallet`)
- **OutsideExecution**: V1, V2, V3 meta-transaction support — `getTypedData()`, `buildExecuteFromOutsideCall()`, `validateCalls()` (82 tests)

#### SNIP-12 TypedData (`wallet`)
- **TypedData**: LEGACY (Pedersen, `"StarkNetDomain"`) and ACTIVE (Poseidon, `"StarknetDomain"`) revisions, recursive type encoding, Merkle tree with sorted pair hashing, preset types (u256, TokenAmount, NftId) (43 tests)
- `Account:hashMessage(typedData)` and `Account:signMessage(typedData)` integration

#### Encrypted Key Store (`wallet`)
- **KeyStore**: XOR+HMAC-SHA256 encrypted DataStore persistence for player private keys, `getOrCreate()` primary onboarding API, secret rotation via `rotateSecret()`, GDPR deletion via `deleteKey()`, `userIds` tagging for Right to Erasure compliance (72 tests)

#### Onboarding Manager (`wallet`)
- **OnboardingManager**: Player lifecycle management — `onboard()`, `ensureDeployed()`, `getStatus()`, `removePlayer()` (37 tests)

#### EventPoller Persistence (`provider`)
- DataStore checkpointing for `_lastBlockNumber` across server restarts
- `onCheckpoint` callback for custom persistence backends
- `setLastBlockNumber()` for manual seeding, `getCheckpointKey()` for debugging (26 tests)

#### AbiCodec Public Export (`contract`)
- **AbiCodec**: Recursive encoder/decoder for all Cairo types — now publicly exported via `Starknet.contract.AbiCodec` (109 tests)

#### Error System (`errors`)
- **StarknetError**: Typed hierarchy — RpcError, SigningError, AbiError, ValidationError, TransactionError — with `pcall`-safe identity preservation, `:is()` type checking, `isStarknetError()` duck-type check (42 tests)
- **ErrorCodes**: 40+ categorized codes across 7 ranges (1000s=validation, 2000s=RPC, 3000s=signing, 4000s=ABI, 5000s=transaction, 6000s=outside execution, 7000s=paymaster)

#### Shared Utilities (`shared`)
- **interfaces.luau**: Interface-only types for ProviderInterface, AccountInterface, SignerInterface
- **HexUtils**: `normalizeHex()`, `asciiToHex()`, `hasHexPrefix()`, `parseHexToNumber()`
- **BufferUtils**: `bufferToHex()`, `concatBuffers()`, `singleByte()`
- **ByteArray**: Shared 31-byte chunk encode/decode
- **TestableDefaults**: Shared `_sleep`/`_clock` injection for testable modules

#### Infrastructure
- `Constants.SDK_VERSION` for runtime version checking
- ERC-20 event definitions (Transfer, Approval) in preset ABI
- ERC-721 event definitions (Transfer, Approval, ApprovalForAll) in preset ABI
- ERC-20: `increase_allowance`/`decrease_allowance` standard functions
- ERC-721: `safe_transfer_from`, `token_uri`, `supports_interface` standard functions
- Wally package JSON restructured for proper `wally publish` compatibility
- `dev.project.json` for development DataModel layout

### Changed

#### Refactoring (~2,500 lines eliminated)
- **JsonRpcClient**: Shared JSON-RPC base module — RpcProvider and PaymasterRpc delegate to common infrastructure (rate limiter, HTTP helpers, retry logic, Promise loading)
- **FieldFactory**: Parameterized field constructor — StarkField and StarkScalarField generated from shared factory with different moduli
- **PresetFactory**: Shared factory for ERC-20/ERC-721 preset construction
- **DRY Account.luau**: 5 extracted helpers (`_validatePaymasterDetails`, `_validatePaymasterCalls`, `_buildDeployParams`, `_withNonceManager`, `_checkAlreadyDeployed`) — 1,063→950 lines
- **DRY TransactionBuilder**: `_executePipeline`, `_estimateInternal`, `extractFirstEstimate`, `ZERO_RESOURCE_BOUNDS`, `BaseTransactionOptions` — 595→582 lines
- **DRY Contract/Presets**: `resolveAndEncode` helper, `appendAll` helper, PresetFactory consolidation
- **Shared test infrastructure**: `tests/helpers/TestUtils.luau` — 20 spec files migrated, ~1,650 lines of boilerplate eliminated
- **Private method coupling fixed**: `_getPromise()` → `getPromise()`, `fetchSync()` on RpcProvider, `getNonceManager()` in Account, `Account:getProvider()`, `PaymasterRpc:resolveImmediate()`
- **Type annotation improvements**: `StarknetErrorInstance` export type, narrowed `data`/`priority`/`items`/`CacheConfig`/`Call` types, PaymasterPolicy+SponsoredExecutor export types
- **AbiCodec correctness**: Bounds checking in decode, unreachable assertions in encode/decode, `warn()` for unknown types, `decodeEvent` error on truncated data, `parseEvents` returns `{events, errors}` with strict mode

#### Performance
- **4-bit windowed scalar multiplication** + **Shamir's trick** for ECDSA verify (~40% speedup for 252-bit scalar operations)
- **Barrett `powmodB`** exposed on BigInt for callers outside field modules
- **Cache & queue micro-optimizations**: serde caching, NonceManager O(1) `pendingCount`, OutsideExecution pre-normalize, lazy ABI selectors, SponsoredExecutor metrics cap, fast cache keys

### Fixed

- Error code cleanup: removed 5 dead error codes, documented skipped ranges and domain crossovers
- Return value consistency: `addInvokeTransaction`/`addDeployAccountTransaction` normalized, `executePaymaster()` return shape aligned with `execute()`
- PaymasterRpc `executeTransaction()` fee mode now correctly determined from `gasTokenAddress` instead of hardcoded `"sponsored"`
- `PaymasterPolicy.allowedMethods` selector vs entrypoint naming confusion resolved
- `StarkCurve.scalarMul()` returns INFINITY sentinel for k=0 instead of nil
- `RpcProvider:addInvokeTransaction()` no longer manually copies all 11 fields
- `OutsideExecution.getTypedData()` accepts config table instead of 6 positional parameters
- PaymasterRpc rate-limit timeout now configurable

### Test Improvements

- **Test framework**: `beforeEach`/`afterEach` hooks, per-test timing with slow test warnings (>1s), `--parallel` flag for concurrent subprocess execution
- **MockPromise**: Added `finally()`, `cancel()`, `race()`, `allSettled()`
- **Coverage gaps filled**: 64 new tests across RpcProvider, RequestQueue, Account, AbiCodec, Contract, TransactionBuilder, PaymasterBudget, PaymasterRpc
- **Error assertions strengthened**: 18 `:toThrow("msg")` → `:toThrowCode`, 51 bare `:toThrow()` → `:toThrowCode`/`:toThrowType`, 9 hardcoded error codes → `ErrorCodes.XXX.code`
- **Error system tests expanded**: 24 untested error codes covered, code uniqueness assertion, `tostring` for all subtypes, `isStarknetError` negative tests
- **Barrel export smoke test**: `tests/init.spec.luau` validating 9 namespaces + sub-module keys (69 tests)
- **Crypto edge cases**: StarkSigner key boundaries, Pedersen `hashChain` vectors, Poseidon `hashMany` with 5/7/8/16/100 elements, TransactionHash determinism, cross-module integration pipelines (54 tests)
- **Test redundancy reduced**: MockPromise tests centralized, phantom describe blocks fixed, address vectors centralized, version tags on vector sources
- **Total: 2,846 tests** (was 1,429 in v0.1.0)

---

## [0.1.0] - 2025-02-26

Initial release of starknet-luau -- a pure Luau SDK for Starknet blockchain interaction from Roblox games.

### Added

#### Cryptographic Primitives (`crypto`)
- **BigInt**: Buffer-based arbitrary precision integers with 24-bit f64 limbs, Barrett reduction, full modular arithmetic (94 tests)
- **StarkField**: Field arithmetic over the Stark prime P = 2^251 + 17 * 2^192 + 1 (51 tests)
- **StarkScalarField**: Scalar arithmetic over the curve order N (54 tests)
- **StarkCurve**: Elliptic curve point operations on the Stark curve (y^2 = x^3 + x + beta) with Jacobian coordinates (53 tests)
- **Poseidon**: Poseidon hash with Hades permutation (width=3, 91 rounds) for V3 transaction hashing (22 tests)
- **Pedersen**: Pedersen hash using EC point operations for legacy address computation (17 tests)
- **Keccak**: Keccak-256 (Ethereum variant) for function selector computation (24 tests)
- **SHA256**: FIPS 180-4 SHA-256 + HMAC-SHA-256 for RFC 6979 nonce generation (31 tests)
- **ECDSA**: Stark ECDSA signing with RFC 6979 deterministic nonces, cross-referenced against @scure/starknet (37 tests)

#### Signing (`signer`)
- **StarkSigner**: Key derivation, transaction signing, public key caching (21 tests)

#### RPC Provider (`provider`)
- **RpcProvider**: JSON-RPC 2.0 client with Promise-based async, token bucket rate limiting, exponential backoff retry (59 tests)
- **RpcTypes**: Complete type definitions for all Starknet JSON-RPC request/response types
- **EventPoller**: Configurable polling for contract events with start/stop lifecycle
- **RequestQueue**: 3-bucket priority queue with JSON-RPC batching for read-only methods (82 tests)
- **ResponseCache**: LRU cache with per-method TTL and block-based invalidation (89 tests)
- **NonceManager**: Per-address local nonce tracking with parallel reservation and auto-resync (64 tests)
- Expanded RPC methods: `getBlockWithTxs`, `getBlockWithReceipts`, `getTransactionByHash`, `getStorageAt`, `getClassHashAt`, `getClassAt`, `getSpecVersion` (39 tests)

#### Transaction Building (`tx`)
- **TransactionBuilder**: Orchestrates nonce fetch, fee estimation, V3 INVOKE hash computation, signing, and submission (36 tests)
- **TransactionHash**: V3 INVOKE transaction hash computation using Poseidon
- **CallData**: Multicall calldata encoding for `__execute__`

#### Account Management (`wallet`)
- **Account**: Address derivation, transaction execution, fee estimation for OpenZeppelin, Argent X, and Braavos account types (80 tests)
- **TypedData**: SNIP-12 typed data signing with both LEGACY (Pedersen) and ACTIVE (Poseidon) revisions, Merkle tree support, preset types (43 tests)

#### Contract Interaction (`contract`)
- **Contract**: ABI-driven dynamic dispatch -- view functions via `call()`, external functions via `invoke()`, with `populate()` for multicall batching (60 tests)
- **AbiCodec**: Recursive encoder/decoder for all Cairo types -- felt, bool, u256, structs, enums, Option, Result, Array, Span, ByteArray, tuples (109 tests)
- **ERC20**: Pre-built ERC-20 token interface with standard read/write methods (35 tests)
- **ERC721**: Pre-built ERC-721 NFT interface with ownership and approval methods (41 tests)

#### Error Handling (`errors`)
- **StarknetError**: Typed error hierarchy (RpcError, SigningError, AbiError, ValidationError, TransactionError) with structured codes, `pcall`-safe identity preservation, and `:is()` type checking (42 tests)
- **ErrorCodes**: Categorized error code constants (validation=1000s, RPC=2000s, signing=3000s, ABI=4000s, transaction=5000s)

#### Infrastructure
- **Constants**: Chain IDs, class hashes (OZ, Argent, Braavos), well-known token addresses, transaction versions
- **Main entry point**: Single `require()` barrel export for the entire SDK
- Dual package manager support: Wally (`b-j-roberts/starknet-luau`) and Pesde (`magic/starknet_luau`)
- CI pipeline: build, test (1,429 tests), lint (Selene), format check (StyLua)
- Automated release workflow: GitHub Release + Wally publish + Pesde publish on version tags
- 5 example scripts: read-contract, send-transaction, nft-gate, multicall, leaderboard
- 7 documentation guides: getting-started, contracts, accounts, patterns, roblox, crypto, api-reference

### Known Limitations
- V3 INVOKE transactions only (no DECLARE — DEPLOY_ACCOUNT and paymaster added in v0.2.0)
- Polling-based event monitoring (no WebSocket/SSE support in Roblox)
- No session key support yet
- Tested against Sepolia testnet; mainnet usage should be validated independently

[0.2.0]: https://github.com/b-j-roberts/starknet-luau/releases/tag/v0.2.0
[0.1.0]: https://github.com/b-j-roberts/starknet-luau/releases/tag/v0.1.0
