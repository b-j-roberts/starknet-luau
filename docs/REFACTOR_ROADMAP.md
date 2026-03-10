# starknet-luau Refactor Roadmap

Synthesized from the full code review audit in `docs/refactor/` (01-14). Every actionable tagged item (`[fix]`, `[refactor]`, `[feat]`, `[perf]`, `[type]`, `[test]`, `[doc]`, `[api]`) is represented below. Items tagged `[ok]` or `[skip]` are excluded.

---

## Summary Table

| Phase | # Items | Complexity | Key Files Affected |
|-------|---------|------------|--------------------|
| **R1: Code Deduplication & Shared Utilities** | 15 | L | RpcProvider, PaymasterRpc, Account, TypedData, CallData, StarkField, StarkScalarField, Keccak, SHA256, ECDSA, TransactionBuilder, AbiCodec, ERC20, ERC721 |
| **R2: Type Safety & API Consistency** | 6 | M | RpcTypes, StarkSigner, Account, Contract, TransactionBuilder, PaymasterRpc, ErrorCodes, SponsoredExecutor, OutsideExecution |
| **R3: Bug Fixes & Correctness** | 9 | S-M | TransactionBuilder, Contract, AbiCodec, PaymasterRpc, SponsoredExecutor, examples/ |
| **R4: Performance** | 7 | S | Poseidon, StarkCurve, TypedData, BigInt, PaymasterPolicy, Contract |
| **R5: Test Improvements** | 8 | M-L | 16+ test files, run.luau, MockPromise, test-vectors, paymaster specs |
| **R6: Documentation** | 6 | M-L | SPEC.md, ROADMAP.md, CHANGELOG.md, all 7 guides, README.md, source comments |
| **R7: Config, Build & Infrastructure** | 6 | S-M | Makefile, project JSONs, wally.toml, pesde.toml, .luaurc, CLAUDE.md |
| **Feature Items** | 4 | S-M | ERC20, ERC721, AccountType |

---

## Phase R1: Code Deduplication & Shared Utilities

Eliminate DRY violations across the codebase. Estimated ~2,500 lines eliminable (source + test). Items ordered by impact.

---

### R.1.1 Extract Shared JsonRpcClient Base Module

**Description**: `RpcProvider.luau` and `PaymasterRpc.luau` share ~400 lines of independently implemented JSON-RPC infrastructure: rate limiter, HTTP helpers, JSON encode/decode, raw request, retry logic, and Promise loading. This is the single largest DRY violation in the codebase. Extract a shared `src/provider/JsonRpcClient.luau` that both modules delegate to.

**Requirements**:
- [ ] Create `src/provider/JsonRpcClient.luau` with shared rate limiter (`createRateLimiter`, `tryAcquire`), HTTP helpers (`_doHttpRequest`, `_jsonEncode`, `_jsonDecode`), raw request (`_rawRequest` with error mapper callback), retry loop (`_requestWithRetry` with shouldRetry predicate), and Promise loading (ref: 04-provider.md §RpcProvider [refactor], 08-paymaster.md §PaymasterRpc [refactor], 14-cross-cutting.md §2A)
- [ ] Refactor `RpcProvider.luau` to delegate to `JsonRpcClient` for infrastructure, keeping queue/cache/nonce/block-invalidation/RPC methods (ref: 04-provider.md §RpcProvider [refactor])
- [ ] Refactor `PaymasterRpc.luau` to delegate to `JsonRpcClient`, keeping SNIP-29 error mapping and paymaster methods (ref: 08-paymaster.md §PaymasterRpc [refactor])
- [ ] Extract rate-limit spin wait (duplicated in `_rawRequest` and `_dispatchBatch`) to `_acquireRateLimitToken()` helper (ref: 04-provider.md §RpcProvider [refactor])
- [ ] Extract header construction (duplicated in `_rawRequest` and `_dispatchBatch`) to `_buildHeaders()` helper (ref: 04-provider.md §RpcProvider [refactor])
- [ ] Move `Promise<T>` type definition to `RpcTypes.luau` (ref: 14-cross-cutting.md §2C [refactor])
- [ ] Move `HttpRequest`/`HttpResponse` type definitions — PaymasterRpc should import from `RpcTypes` (ref: 04-provider.md §RpcTypes [refactor], 14-cross-cutting.md §2C [refactor])
- [ ] Move `StarknetError` shadow type in RpcTypes.luau to import from actual module or remove (ref: 04-provider.md §RpcTypes [refactor])

**Implementation Notes**:
- See provider/ cross-cutting audit in 04-provider.md for full 14-component duplication inventory
- `_rawRequest()` differs only in error mapping branch; accept optional `errorMapper` callback
- `_requestWithRetry()` differs in "don't retry" condition; accept `shouldRetry(err) -> boolean` predicate
- `_getPromise()` differs only in error message text
- Estimated before/after: RpcProvider ~1104→~900 lines, PaymasterRpc ~661→~460 lines, JsonRpcClient ~200 lines new

---

### R.1.2 Extract Shared Test Infrastructure

**Description**: 16 test files independently define identical mock HTTP handlers, mock providers, handler resets, and test constants, totaling ~1,717 lines of duplication. Additionally, 3 paymaster specs use an incompatible hand-rolled test harness invisible to the test runner.

**Requirements**:
- [x] Create `tests/helpers/TestUtils.luau` with shared `createMockRpcLayer()`, `createTestProvider()`, `applyDefaultHandlers()`, and common test constants (`SN_SEPOLIA`, `TEST_PRIVATE_KEY`, `ETH_TOKEN_ADDRESS`, `OZ_CLASS_HASH`) (ref: 14-cross-cutting.md §9, 12-tests.md §cross-cutting)
- [x] Migrate 16 spec files to use shared mock infrastructure: RpcProvider, NonceManager, EventPoller, getAllEvents, RequestBatcher, TransactionBuilder, DeployAccount, Account, AccountFactory, PrefundingHelper, BatchDeploy, Contract, ERC20, ERC721, ContractEvents, PaymasterRpc, AvnuPaymaster (ref: 06-wallet.md §test duplication, 07-contract.md §DRY, 04-provider.md §DRY, 12-tests.md §9A-9D)
- [x] Migrate 3 paymaster specs (PaymasterPolicy, PaymasterBudget, SponsoredExecutor) from hand-rolled test harness to `run.luau` framework (ref: 12-tests.md §run.luau [fix], 14-cross-cutting.md §9E)
- [x] Move SponsoredExecutor's inline 58-line MockPromise to use shared `tests/helpers/MockPromise.luau` (ref: 12-tests.md §MockPromise [refactor])
- [x] Replace 11+ files' inline `SN_SEPOLIA` definitions with import from Constants or TestUtils (ref: 09-root.md §chain IDs [refactor], 14-cross-cutting.md §9D)
- [x] Consolidate 15 files' duplicate private key constants under a single variable name (ref: 14-cross-cutting.md §9D)
- [x] Migrate TypedData Account integration tests (lines 614-712) from separate mock setup to shared test infrastructure (ref: 06-wallet.md §TypedData [test])

**Implementation Notes**:
- Factory-based design (not global state) so tests remain isolated
- Each test file drops from ~120 lines of boilerplate to ~10 lines
- Estimated savings: ~1,650 lines

---

### R.1.3 Centralize Constants (Single Source of Truth)

**Description**: Class hashes, chain IDs, token addresses, and other protocol constants are defined independently in 3+ modules each. Consolidate all to import from `src/constants.luau`.

**Requirements**:
- [ ] Remove class hash constants from `Account.luau` (lines 44-53) and `AccountType.luau` (lines 22-25); import from `constants.luau` (ref: 06-wallet.md §1, 09-root.md §class hashes [refactor], 14-cross-cutting.md §2B)
- [ ] Remove `CONTRACT_ADDRESS_PREFIX` local in `Account.luau:26`; use `Constants.CONTRACT_ADDRESS_PREFIX` (ref: 06-wallet.md §cross-module, 09-root.md §contract address prefix [refactor])
- [ ] Remove `SN_MAIN`/`SN_SEPOLIA` from `TransactionHash.luau:48-49`; import from `constants.luau`. Keep as re-exports for backward compat or remove (breaking change) (ref: 09-root.md §chain IDs [refactor], 14-cross-cutting.md §2B)
- [ ] Import `Constants.ETH_TOKEN_ADDRESS`/`STRK_TOKEN_ADDRESS` in `AvnuPaymaster.luau` for KNOWN_TOKENS ETH/STRK entries (ref: 09-root.md §token addresses [refactor], 14-cross-cutting.md §2B)
- [ ] Replace hardcoded Stark prime P in `TypedData.luau:25` with import from `StarkField.P` (ref: 06-wallet.md §cross-module, 14-cross-cutting.md §2B)
- [ ] Have `Account.luau` delegate to `AccountType` for calldata building; remove `buildConstructorCalldata()` (lines 90-102) and `getDefaultClassHash()` (lines 118-125) (ref: 06-wallet.md §2, 14-cross-cutting.md §2D)

**Implementation Notes**:
- `Account.CLASS_HASH_TO_TYPE` lookup table with historical versions should remain (serves a different purpose — reverse lookup)
- `TransactionHash.SN_MAIN/SN_SEPOLIA` removal is a breaking change; consider deprecated re-exports

---

### R.1.4 Extract Field Factory (StarkField / StarkScalarField)

**Description**: `StarkField.luau` and `StarkScalarField.luau` share 16 identical functions (~300 lines total) differing only in the modulus constant. This is the biggest DRY violation in the crypto layer.

**Requirements**:
- [ ] Create `src/crypto/FieldFactory.luau` with `createField(modulus, modulusMinus2, barrettCtx, name)` that generates all shared methods: `reduce`, `powmodBarrett`, `zero`, `one`, `fromNumber`, `fromHex`, `add`, `sub`, `mul`, `square`, `neg`, `inv`, `toHex`, `toBigInt`, `eq`, `isZero` (ref: 01-crypto.md §StarkField [refactor], §StarkScalarField [refactor])
- [ ] Refactor `StarkField.luau` to use the factory, adding `sqrt()` as an extension (ref: 01-crypto.md §StarkField [refactor])
- [ ] Refactor `StarkScalarField.luau` to use the factory (ref: 01-crypto.md §StarkScalarField [refactor])
- [x] Move `powmodBarrett()` to `BigInt.powmodB(a, e, ctx)` so callers don't reimplement the loop (ref: 01-crypto.md §priority actions #5; see also R.4.6 for performance motivation)
- [ ] Extract parameterized field test suite `fieldTestSuite(Field, modulus, name)` and run against both fields (ref: 01-crypto.md §StarkScalarField [test])

**Implementation Notes**:
- StarkScalarField has no `sqrt()` (intentional — document why in API comment)
- Saves ~130 source lines + ~50 test lines of duplication
- Curve order `N` in `StarkCurve.luau:41` should import from `StarkScalarField.N` instead of recomputing (ref: 01-crypto.md §StarkCurve [refactor])

---

### R.1.5 Extract Shared Hex & Buffer Utilities

**Description**: `bufferToHex()`, `normalizeHex()`, `asciiToHex()`, `concatBuffers()`, `toBytes32()`, and other utility functions are duplicated across 8+ modules. Extract to shared utility modules.

**Requirements**:
- [ ] Create `src/shared/HexUtils.luau` with `normalizeHex(hex)`, `asciiToHex(str)`, `hasHexPrefix(s)`, `parseHexToNumber(hex)` (ref: 14-cross-cutting.md §2A, §2D)
- [ ] Consolidate 3 divergent `normalizeHex()` implementations: `CallData.luau:36-38`, `OutsideExecution.luau:134-136` (BigInt roundtrip), `PaymasterPolicy.luau:36-45` (manual string) (ref: 05-tx.md §cross-module, 06-wallet.md §10, 14-cross-cutting.md §2A)
- [ ] Extract `bufferToHex()` from `Keccak.luau:359-369` and `SHA256.luau:292-302` (identical 10-line functions + HEX_CHARS) to `src/shared/BufferUtils.luau` (ref: 01-crypto.md §Keccak [refactor], §SHA256 [refactor], 14-cross-cutting.md §2E)
- [ ] Extract `concatBuffers()` and `singleByte()` from `ECDSA.luau:121-142` to BufferUtils (ref: 01-crypto.md §ECDSA [refactor])
- [ ] Extract `toBytes32()` from `ECDSA.luau:41-55` as `BigInt.toBytes32()` or `BigInt.toBytesFixed(n)` (ref: 01-crypto.md §ECDSA [refactor], 14-cross-cutting.md §2E)
- [ ] Consolidate `asciiToHex()` pattern duplicated 5x across TypedData, CallData, AbiCodec (ref: 14-cross-cutting.md §2A)
- [ ] Remove public `bufferToHex()` from Keccak and SHA256 APIs (crypto modules shouldn't expose hex utilities) (ref: 01-crypto.md §Keccak [refactor], §SHA256 [api], 14-cross-cutting.md §6B)
- [ ] Extract `readBE32()`/`writeBE32()` from SHA256 to BufferUtils if creating shared module (ref: 01-crypto.md §SHA256 [refactor])

**Implementation Notes**:
- `normalizeHex` via BigInt roundtrip is the canonical implementation; manual string version may diverge on edge cases
- `parseHexToNumber` fixes the `tonumber("0x1a", 16)` dead-branch pattern in AbiCodec (4 instances)

---

### R.1.6 Extract Shared ByteArray & Short String Encoding

**Description**: ByteArray encoding (31-byte chunks) and `encodeShortString()` are duplicated between TypedData and AbiCodec/CallData with divergent implementations.

**Requirements**:
- [ ] Create `src/shared/ByteArray.luau` with shared ByteArray encode/decode logic (ref: 14-cross-cutting.md §2A)
- [ ] Consolidate `encodeByteArray()` from `TypedData.luau:139-191` and `AbiCodec.luau:256-293` (different chunking strategies) (ref: 14-cross-cutting.md §2A)
- [ ] Have `TypedData.luau` import `encodeShortString` from `CallData.luau` instead of duplicating (TypedData version lacks validation) (ref: 05-tx.md §cross-module, 06-wallet.md §11, 14-cross-cutting.md §2A)
- [ ] Extract AbiCodec ByteArray `bytesToHex()`/`hexToBytes()` helpers (4 near-identical loops) (ref: 07-contract.md §AbiCodec [refactor])

**Implementation Notes**:
- TypedData's `encodeShortString` silently accepts >31 chars and non-ASCII — importing from CallData fixes this latent correctness issue

---

### R.1.7 Extract Shared Pedersen Chain-Hash Utility

**Description**: `computeHashOnElements()` (Pedersen chain-hash then hash with length) is implemented identically in `Account.luau` and `TypedData.luau`.

**Requirements**:
- [ ] Extract to `Pedersen.hashMany()` or `src/shared/hash.luau` (ref: 06-wallet.md §9, 14-cross-cutting.md §2A)
- [ ] Update `Account.luau:77-84` and `TypedData.luau:83-90` to use the shared utility (ref: 06-wallet.md §cross-module)
- [ ] Extract `u256ToBigInt()` from `Account.luau:106-114` to `BigInt.fromU256()` (general-purpose utility trapped in Account) (ref: 06-wallet.md §Account [refactor], 14-cross-cutting.md §2E)

---

### R.1.8 DRY Account.luau Internal Helpers

**Description**: `Account.luau` is a 1,109-line god class with extensive internal duplication across paymaster methods, deploy methods, and nonce management.

**Requirements**:
- [ ] Extract `_validatePaymasterDetails(methodName, details)` returning `{ paymaster, gasTokenAddress, feeMode }` — eliminates ~62 lines across 3 methods (ref: 06-wallet.md §3, 08-paymaster.md §Account [refactor])
- [ ] Extract `_validatePaymasterCalls(submittedCalls, typedData)` — eliminates ~32 lines across 2 methods (ref: 06-wallet.md §5, 08-paymaster.md §Account [refactor])
- [ ] Extract `_buildDeployParams()` — eliminates ~24 lines across 3 methods (ref: 06-wallet.md §4)
- [ ] Extract `_withNonceManager(address, fn)` wrapper — eliminates ~30 lines across 2 methods (ref: 06-wallet.md §5)
- [ ] Extract `_checkAlreadyDeployed()` — eliminates ~12 lines across 2 methods (ref: 06-wallet.md §Account [refactor])

**Implementation Notes**:
- These are internal helpers within Account.luau — no API changes
- Consider Phase R1.12 (paymaster extraction) as a follow-up to further reduce Account.luau size

---

### R.1.9 DRY TransactionBuilder Pipelines

**Description**: `execute()` and `deployAccount()` share ~80% identical flow. Fee estimation methods similarly overlap. Several inline patterns repeat 4+ times.

**Requirements**:
- [ ] Extract shared `_executePipeline()` parameterized by hash function, builder, submitter, nonce strategy — eliminates ~100 lines (ref: 05-tx.md §TransactionBuilder [refactor], 14-cross-cutting.md §10)
- [ ] Extract shared `_estimateInternal()` parameterized by builder and nonce source — eliminates ~25 lines (ref: 05-tx.md §TransactionBuilder [refactor])
- [ ] Define module-level `ZERO_RESOURCE_BOUNDS` constant — replaces 4 inline constructions (ref: 05-tx.md §TransactionBuilder [refactor])
- [ ] Extract `extractFirstEstimate(feeResult)` helper — replaces 4 identical conditionals (ref: 05-tx.md §TransactionBuilder [refactor])
- [ ] Extract `BaseTransactionOptions` type shared between `ExecuteOptions` and `DeployAccountOptions` (8 identical fields) (ref: 05-tx.md §TransactionBuilder [type], 14-cross-cutting.md §10)

---

### R.1.10 DRY TransactionHash Fee Field

**Description**: Both `calculateInvokeTransactionHash` and `calculateDeployAccountTransactionHash` inline the fee field hash computation instead of calling the existing `hashFeeField()` function.

**Requirements**:
- [ ] Call `hashFeeField()` internally in both `calculate*TransactionHash` functions — eliminates ~30 lines of duplicated inline code (ref: 05-tx.md §TransactionHash [refactor])
- [ ] Extract shared `prepareCommonFields(params)` returning `{ feeFieldHash, paymasterHash, daMode }` for DA mode encoding + default parameter extraction (~12 lines each) (ref: 05-tx.md §TransactionHash [refactor])

---

### R.1.11 DRY Error System Factory Constructors

**Description**: Six error factory constructors repeat identical `setmetatable` boilerplate. Four of six are byte-for-byte identical except for the `_type` string.

**Requirements**:
- [ ] Extract shared `createError(errorType, fields)` internal helper in `StarknetError.luau` — eliminates ~50 lines (ref: 02-errors.md §StarknetError [refactor])
- [ ] Simplify `:is()` traversal — current two-level hardcoded walk is neither simple (for flat hierarchy) nor future-proof (for deep hierarchy). Either make recursive or simplify to single-level check (ref: 02-errors.md §StarknetError [refactor])

---

### R.1.12 DRY Contract & Preset Modules

**Description**: `call()` and `populate()` in Contract share 22 identical lines. ERC20 and ERC721 are structurally identical modules differing only in ABI content.

**Requirements**:
- [ ] Extract `resolveAndEncode(self_, method, args)` helper in Contract.luau — eliminates ~18 lines (ref: 07-contract.md §Contract [refactor])
- [ ] Extract `appendAll(target, source)` helper in AbiCodec.luau using `table.move` — replaces 10+ instances of 3-line encode-and-append pattern (~33 lines) (ref: 07-contract.md §AbiCodec [refactor])
- [ ] Create `contract/PresetFactory.luau` for ERC20/ERC721 — eliminates ~30 lines per preset of identical factory/validation boilerplate (ref: 07-contract.md §cross-cutting)
- [ ] Remove redundant validation in ERC20/ERC721 `new()` that duplicates Contract.new() checks (ref: 07-contract.md §ERC20 [refactor], §ERC721 [refactor])

---

### R.1.13 DRY PaymasterRpc & PaymasterBudget Internals

**Description**: Several internal patterns within paymaster modules are duplicated.

**Requirements**:
- [x] Extract `formatDeploymentData(dd)` helper in PaymasterRpc — eliminates ~17 lines between `buildTypedData` and `executeTransaction` (ref: 08-paymaster.md §PaymasterRpc [refactor])
- [x] Extract `normalizeKeys()` helper in PaymasterRpc for repetitive response normalization (ref: 08-paymaster.md §PaymasterRpc [refactor])
- [x] Extract shared transaction structure construction between PaymasterRpc `buildTypedData` and `executeTransaction` (envelope construction beyond just deploymentData) (ref: 08-paymaster.md §PaymasterRpc [refactor])
- [x] Consolidate `PlayerData`/`UsageStats` identical types in PaymasterBudget (ref: 08-paymaster.md §PaymasterBudget [refactor])
- [x] Replace `clonePlayerData()` manual 4-field copy with `table.clone()` (ref: 08-paymaster.md §PaymasterBudget [refactor])
- [x] Deduplicate DataStore loading between `_getPlayerData()` and `loadPlayer()` in PaymasterBudget (~15 lines) (ref: 08-paymaster.md §PaymasterBudget [refactor])
- [x] Extract config validation helper `validateNonNeg(name, value)` in PaymasterBudget — replaces 6 nearly identical blocks (ref: 08-paymaster.md §PaymasterBudget [refactor])
- [x] Fix `flushPlayer()` dirty count recomputation — should decrement, not re-iterate (inconsistent with `unloadPlayer` which already does it correctly) (ref: 08-paymaster.md §PaymasterBudget [refactor])
- [x] Deduplicate player whitelist check between `validate()` and `validateFee()` in PaymasterPolicy (ref: 08-paymaster.md §PaymasterPolicy [refactor])

---

### R.1.14 DRY Signer & Signing Flows

**Description**: Two code paths produce identical hex signature output. `signTransaction()` bypasses `signRaw()`, and `Account:signMessage()` reimplements hex conversion.

**Requirements**:
- [ ] Fix `signTransaction()` to delegate to `signRaw()` instead of calling ECDSA.sign() directly (ref: 03-signer.md §StarkSigner [refactor])
- [ ] Fix `Account:signMessage()` to call `signer:signTransaction(hashBuf)` instead of `signer:signRaw()` + manual hex conversion (ref: 03-signer.md §StarkSigner [refactor], 14-cross-cutting.md §6)
- [ ] Extract DRY nonce hex parsing in NonceManager (same pattern at lines 98, 152, 171) to `parseNonceHex()` local helper (ref: 04-provider.md §NonceManager [refactor])

---

### R.1.15 Miscellaneous DRY Items

**Requirements**:
- [x] Move Poseidon round constants (250+ lines of hex strings) to `PoseidonConstants.luau` for readability (ref: 01-crypto.md §Poseidon [refactor])
- [x] Consolidate `getMetrics()` two nearly-identical return paths (queue-enabled vs disabled) in RpcProvider (ref: 04-provider.md §RpcProvider [refactor])
- [x] Extract call conversion in `OutsideExecution.getTypedData()` — V2 and V3 blocks produce identical `{To, Selector, Calldata}` (ref: 06-wallet.md §OutsideExecution [refactor])
- [x] Extract shared deploy result-building logic in AccountFactory — sequential and parallel paths duplicate ~40 lines (ref: 06-wallet.md §AccountFactory [refactor])
- [x] Normalize `OutsideExecution.buildExecuteFromOutsideCall()` dual-key inspection — normalize data at `getTypedData()` output boundary (ref: 06-wallet.md §OutsideExecution [refactor])
- [x] Centralize transient error classification — `SponsoredExecutor.isTransientError()` and `PaymasterRpc._requestWithRetry()` classify from opposite perspectives. Add `ErrorCodes.isTransient(code)` (ref: 08-paymaster.md §SponsoredExecutor [refactor], 14-cross-cutting.md §2E)
- [x] Align 3 paymaster modules' import pattern for ErrorCodes (use `StarknetError.ErrorCodes` like other 23 modules) (ref: 14-cross-cutting.md §1)
- [x] Extract shared `_sleep`/`_clock` injection boilerplate into `src/shared/TestableDefaults.luau` — 6 modules updated to use `Defaults.sleep`/`Defaults.clock` (ref: 14-cross-cutting.md §2D)
- [x] Extract EventPoller filter reconstruction — duplicated on every poll cycle instead of built once (ref: 04-provider.md §EventPoller [refactor])
- [x] Remove `CallData.encodeStruct()` no-op wrapper that does an unnecessary copy (ref: 05-tx.md §CallData [refactor])
- [x] Extract Promise+pcall boilerplate repeated in every TransactionBuilder method into shared wrapper — already done via `_executePipeline` + `_estimateInternal` in R.1.9 (ref: 05-tx.md §TransactionBuilder [refactor])
- [x] Simplify `AccountFactory._createAccountFromSigner` Argent-specific branching (ref: 06-wallet.md §AccountFactory [refactor])
- [x] Break TypedData `encodeValue` monolithic function into `TYPE_ENCODERS` dispatch table (ref: 06-wallet.md §TypedData [refactor])

---

## Phase R2: Type Safety & API Consistency

Improve type annotations, define shared interfaces, fix API inconsistencies, and resolve naming issues.

---

### R.2.1 Define Shared Interface Types

**Description**: 8+ constructors accept `provider: any`, `account: any`, and `signer: any` with no type safety. Multiple implicit interfaces exist for the same concepts.

**Requirements**:
- [ ] Create `src/shared/types.luau` with `Call`, `ProviderInterface`, `AccountInterface`, `SignerInterface` (minimal + full), `PaymasterDetails`, `WaitOptions` (ref: 14-cross-cutting.md §3, §7)
- [ ] Define `ProviderInterface` type from union of all public methods called by consumers (ref: 14-cross-cutting.md §3A [api])
- [ ] Export `Signer` (full) and `MinimalSigner` (signTransaction-only) types from `signer/StarkSigner.luau`; use in Account.new(), AccountFactory, TransactionBuilder (ref: 03-signer.md §StarkSigner [api])
- [ ] Consolidate `Call` type (defined independently in PaymasterRpc, TransactionBuilder, Contract) (ref: 08-paymaster.md §PaymasterRpc [api], 14-cross-cutting.md §2C)
- [ ] Consolidate `WaitOptions` type (defined in TransactionBuilder and RpcTypes) (ref: 14-cross-cutting.md §2C)
- [ ] Define and export `PaymasterDetails` type for Account paymaster methods (ref: 08-paymaster.md §Account [api])
- [ ] Type `EventPollerConfig.provider` properly instead of `any` (ref: 04-provider.md §RpcTypes [type])
- [ ] Type `ContractConfig.provider` and `ContractConfig.account` with minimal interfaces instead of `any` (ref: 07-contract.md §Contract [type])

---

### R.2.2 Fix Private Method Coupling

**Description**: `_getPromise()` is called 21 times across 6 files despite being private. Other private methods and fields are accessed externally.

**Requirements**:
- [x] Make `_getPromise()` public (`getPromise()`) or inject Promise module at construction time for all consumers (ref: 04-provider.md §RpcProvider [refactor], 14-cross-cutting.md §4)
- [x] Add public `fetchSync(method, params)` to RpcProvider; update EventPoller to use it instead of `_requestWithRetry()` (ref: 04-provider.md §EventPoller [refactor], §priority actions #3)
- [x] Use `provider:getNonceManager()` (already exists at RpcProvider:636) instead of `provider._nonceManager` in Account; add to exported type (ref: 04-provider.md §external audit, 14-cross-cutting.md §4)
- [x] Align Promise module access pattern — Account uses `provider:_getPromise()`, AccountFactory uses `provider._PromiseModule`. Unify (ref: 06-wallet.md §18, 14-cross-cutting.md §4)
- [x] Fix SponsoredExecutor double encapsulation breach (`account._provider:_getPromise()` at line 289) — accept Promise module in config or expose Account.getProvider() (ref: 08-paymaster.md §SponsoredExecutor [fix], 14-cross-cutting.md §4)
- [x] Fix AvnuPaymaster private field access (`inner._PromiseModule` at line 254) — add `resolveImmediate(value)` method to PaymasterRpc (ref: 08-paymaster.md §AvnuPaymaster [refactor])

---

### R.2.3 Add PaymasterError Subtype

**Description**: 15 error codes in the 7000 range across 4+ files have no dedicated factory or hierarchy entry. Paymaster errors are thrown as untyped `StarknetError.new()`.

**Requirements**:
- [ ] Add `StarknetError.paymaster(message, code, context?)` factory to `StarknetError.luau` (ref: 02-errors.md §StarknetError [api], 08-paymaster.md §priority actions #4)
- [ ] Add `PaymasterError = { "StarknetError" }` to `TYPE_HIERARCHY` (ref: 02-errors.md §StarknetError [api])
- [ ] Fix 7 `StarknetError.new()` misuses to use specific subtypes: Pedersen→`validation()`, Account paymaster→`paymaster()`, PaymasterBudget→`paymaster()`, SponsoredExecutor→`paymaster()`/`transaction()` (ref: 02-errors.md §error usage audit, 14-cross-cutting.md §5)
- [ ] Dogfood `:is()` in production — replace 2 raw `._type == "RpcError"` checks in RpcProvider:322 and PaymasterRpc:388 with `:is("RpcError")` (ref: 02-errors.md §StarknetError [api])
- [ ] Fix `MATH_ERROR` inconsistent subtype usage (validation() in BigInt/StarkField vs new() in Pedersen) (ref: 14-cross-cutting.md §5)

---

### R.2.4 Error Code & Hierarchy Cleanup

**Description**: Dead error codes, numbering gaps, domain mismatches between numeric ranges and error subtypes.

**Requirements**:
- [x] Remove or document 5 dead error codes: `OUT_OF_RANGE` (1002), `INSUFFICIENT_BALANCE` (5002), `CACHE_ERROR` (2012), `OUTSIDE_EXECUTION_ERROR` (6000), `PAYMASTER_ERROR` (7000) (ref: 02-errors.md §ErrorCodes [api])
- [x] Document skipped code 3002 in signing range (ref: 02-errors.md §ErrorCodes [refactor])
- [x] Document `TRANSACTION_REVERTED` (2004) / `TRANSACTION_REJECTED` (2005) crossover: in 2000 RPC range but used with `StarknetError.transaction()` (ref: 02-errors.md §ErrorCodes [refactor])
- [x] Fix `NONCE_EXHAUSTED` (2014) domain mismatch — 2xxx code used with `StarknetError.transaction()` in NonceManager (ref: 14-cross-cutting.md §5)
- [x] Remove `RpcTypes.ErrorTypes` dead code (lines 376-382, 5 error type constants never referenced) (ref: 04-provider.md §RpcTypes [api])
- [x] Consider generating ErrorCodes `name` from table key to prevent key/name divergence (ref: 02-errors.md §ErrorCodes [refactor])
- [x] Audit `isStarknetError()` — never called in production code; either dogfood it or document as test-only utility (ref: 02-errors.md §StarknetError [api])

---

### R.2.5 Return Value & API Surface Consistency

**Description**: Several API boundaries have inconsistent return shapes, missing methods from exported types, or misleading parameter names.

**Requirements**:
- [x] Add `getNonceManager()` to exported `RpcProvider` type (method exists at line 636 but not in type) (ref: 04-provider.md §RpcProvider [api])
- [x] Add `addDeployAccountTransaction` to HIGH priority in RequestQueue `METHOD_PRIORITY` (ref: 04-provider.md §RequestQueue [refactor])
- [x] Document `ResourceBounds` type incompatibility: `TransactionHash` (camelCase, 3 fields) vs `RpcTypes` (snake_case, 2 fields) and `toRpcResourceBounds()` silently dropping `l1DataGas` (ref: 05-tx.md §TransactionHash [type], §TransactionBuilder [refactor], 14-cross-cutting.md §2C)
- [x] Document `BlockId` type vs `formatBlockId()` string shorthand inconsistency (ref: 04-provider.md §RpcTypes [type])
- [x] Consider renaming `signTransaction` → `signHex` on StarkSigner (no transaction-specific logic; current name discourages reuse for message signing) — breaking API change, weigh carefully (ref: 03-signer.md §priority actions #5)
- [x] Add `getLastBlockNumber(): number?` to EventPoller public API (ref: 04-provider.md §EventPoller [api])
- [x] Normalize `contract/init.luau` barrel export style to match other barrels (use local-variable-then-return pattern) (ref: 09-root.md §init.luau [refactor])
- [x] Document `self_: any = self` pattern at class level in Contract.luau (appears 11 times) (ref: 07-contract.md §Contract [refactor])
- [x] Fix `addInvokeTransaction` returning bare string vs `addDeployAccountTransaction` returning table — normalize to consistent return shape (ref: 14-cross-cutting.md §3D)
- [x] Fix `Account:executePaymaster()` passing through raw unnormalized return value — should match `execute()` return shape (ref: 14-cross-cutting.md §3D)
- [x] Fix `PaymasterPolicy.allowedMethods` semantic mismatch — `selector` vs `entrypoint` naming confusion causes silent comparison failure when mixing hex selectors with function names (ref: 14-cross-cutting.md §6)
- [x] Consider `StarkCurve.scalarMul()` INFINITY sentinel instead of returning `nil` for k=0 — current `AffinePoint?` return forces nil-checks everywhere (ref: 01-crypto.md §StarkCurve [api])
- [x] Fix `RpcProvider:addInvokeTransaction()` manually copying all 11 fields — fragile pattern that breaks when fields change (ref: 04-provider.md §RpcProvider [api])
- [x] Consider making `TransactionHash.encodeResourceBound()` internal — too low-level for public API surface (ref: 05-tx.md §TransactionHash [api])
- [x] Consider `OutsideExecution.getTypedData()` config table instead of 6 positional parameters (ref: 06-wallet.md §OutsideExecution [api])
- [x] Make PaymasterRpc rate-limit timeout configurable instead of hardcoded 10 seconds (ref: 08-paymaster.md §PaymasterRpc [api])
- [x] Fix AvnuPaymaster method selector normalization gap with PaymasterPolicy (ref: 08-paymaster.md §AvnuPaymaster [refactor])

---

### R.2.6 Type Annotation Improvements

**Description**: Pervasive `any` return types defeat strict mode type checking across the codebase.

**Requirements**:
- [ ] Define `StarknetErrorInstance` export type for factory return values in StarknetError.luau (ref: 02-errors.md §StarknetError [type])
- [ ] Type `RequestQueue.QueueItem.priority` as `"high" | "normal" | "low"` instead of `string` (ref: 04-provider.md §RequestQueue [type])
- [ ] Type `AbiEntry.items` as `{ AbiFunction }?` instead of `{ any }?` (ref: 07-contract.md §AbiCodec [type])
- [ ] Type `ResponseCache` constructor config as `CacheConfig` from RpcTypes instead of `{ [string]: any }?` (ref: 04-provider.md §ResponseCache [api])
- [ ] Type `SponsoredExecutorConfig` fields (`account`, `paymaster`, `policy`, `budget`) with proper types instead of `any` (ref: 08-paymaster.md §SponsoredExecutor [type])
- [ ] Export `PaymasterPolicy` constructor return type (ref: 08-paymaster.md §PaymasterPolicy [type])
- [ ] Document `export type BigInt = buffer` provides no structural distinction from raw buffers — known Luau limitation (ref: 01-crypto.md §BigInt [type])
- [ ] Narrow `StarknetError.data: any?` to `{ [string]: any }?` — usage shows it's always a table when present (ref: 02-errors.md §StarknetError [type])
- [ ] Fix StarkSigner constructor return type `:: any` cast — document as known Luau strict mode limitation (ref: 03-signer.md §StarkSigner [type])
- [ ] Add validation for `contractAddress` format in `Call` type (ref: 05-tx.md §CallData [type])
- [ ] Type `PaymasterPolicy.validate()` `calls` parameter as `{ Call }` instead of `{ any }` (ref: 08-paymaster.md §PaymasterPolicy [type])

---

## Phase R3: Bug Fixes & Correctness

Fix incorrect implementations and correctness issues.

---

### R.3.1 Fix DA Mode Passthrough in TransactionBuilder

**Description**: `buildInvokeTransaction` (lines 168-169) and `buildDeployAccountTransaction` (lines 199-200) hardcode DA modes to `"0x0"` despite accepting the parameters. The hash computation correctly uses the DA mode values, so the hash and submitted transaction would mismatch for non-L1 DA modes.

**Requirements**:
- [ ] Use `params.nonceDataAvailabilityMode` / `params.feeDataAvailabilityMode` instead of hardcoded `"0x0"` in both builder functions (ref: 05-tx.md §TransactionBuilder [fix], 14-cross-cutting.md §2E)
- [ ] Add test exercising non-zero DA modes end-to-end (ref: 05-tx.md §priority actions #1)

**Implementation Notes**:
- 4-line fix. This is a correctness bug that would cause transaction rejection on any chain supporting non-L1 DA modes.

---

### R.3.2 Fix Address Comparison in Contract Event Filtering

**Description**: `Contract.parseEvents()` uses `string.lower()` for address comparison, which doesn't handle leading-zero normalization. RPC responses can return `"0x49d..."` while the contract address is `"0x049d..."`.

**Requirements**:
- [ ] Pre-compute a normalized address via BigInt roundtrip in `Contract.new()` and store as `_normalizedAddress` (ref: 07-contract.md §Contract [fix], 14-cross-cutting.md §6B)
- [ ] Normalize event `from_address` via BigInt roundtrip before comparison (ref: 07-contract.md §Contract [fix])
- [ ] Consider normalizing addresses on construction in `Account.new()` and `Contract.new()` (ref: 14-cross-cutting.md §6A)
- [ ] Add test for hex normalization mismatch (leading-zero stripping) (ref: 07-contract.md §Contract [test])

---

### R.3.3 Fix AbiCodec Decode Bounds & Dead Branches

**Description**: `decode()` reads array indices without bounds checking, producing silent `nil` for malformed responses. `parseHexNumber` has a dead first branch. Unreachable fallbacks exist in encode/decode.

**Requirements**:
- [x] Add bounds checking in `AbiCodec.decode()` — validate `offset <= #results` before reading (ref: 07-contract.md §AbiCodec [fix])
- [x] Extract `parseHexToNumber(hex)` helper replacing 4 instances of broken two-branch pattern where first `tonumber(hex, 16)` always fails for `0x`-prefixed strings (ref: 07-contract.md §AbiCodec [fix]; implementation shared with R.1.5 HexUtils extraction)
- [x] Remove or replace unreachable fallbacks in `encode()` (line 411-412) and `decode()` (line 573-574) with `error("unreachable")` assertions (ref: 07-contract.md §AbiCodec [refactor])
- [x] Add `warn()` or strict mode option for `resolveType()` unknown type fallback to felt (ref: 07-contract.md §AbiCodec [refactor])
- [x] Fix `AbiCodec.decodeEvent()` silently skipping members when keys/data arrays are shorter than expected — should warn or error (ref: 07-contract.md §AbiCodec [refactor])
- [x] Fix `Contract.parseEvents()` silently swallowing decode errors — no logging, callback, or strict-mode option (ref: 07-contract.md §Contract [refactor])

---

### R.3.4 Implement or Remove maxFee in execute()

**Description**: `ExecuteOptions.maxFee` exists in the type definition (line 27) but `execute()` never reads it, unlike `deployAccount()` which implements the cap logic.

**Requirements**:
- [ ] Either implement `maxFee` cap logic in `execute()` (copy from `deployAccount`) or remove the field from `ExecuteOptions` type (ref: 05-tx.md §TransactionBuilder [refactor], 14-cross-cutting.md §3D)
- [ ] Add test for `maxFee` behavior in `execute()` (ref: 05-tx.md §priority actions #3)

---

### R.3.5 Fix PaymasterRpc executeTransaction Fee Mode

**Description**: `executeTransaction()` hardcodes `fee_mode.mode = "sponsored"` regardless of input, unlike `buildTypedData()` which correctly determines mode based on `gasTokenAddress`.

**Requirements**:
- [x] Either accept `gasTokenAddress` parameter in `executeTransaction()` or pass through `feeMode` from the preceding `buildTypedData` result (ref: 08-paymaster.md §PaymasterRpc [fix])

---

### R.3.6 Fix Example tonumber Bug

**Description**: `tonumber("0xFF", 16)` returns `nil` in Luau when the string has a `0x` prefix. This bug affects 3/5 examples and AbiCodec.

**Requirements**:
- [ ] Fix `tonumber(hexString, 16)` → `tonumber(hexString)` in `leaderboard.luau`, `nft-gate.luau`, `send-transaction.luau` (ref: 10-examples.md §cross-cutting)
- [ ] Fix `read-contract.luau` misleading TARGET_ADDRESS (uses ETH token contract address to check its own balance) (ref: 10-examples.md §read-contract)
- [ ] Remove identity transform no-op in `nft-gate.luau:103-105` (ref: 10-examples.md §nft-gate)

---

### R.3.7 Fix Test Runner toEqual and MockPromise

**Description**: `toEqual` is identical to `toBe` (reference equality) — no deep-equality comparison exists. MockPromise `expect()` destroys structured error identity.

**Requirements**:
- [ ] Implement deep-equality in `toEqual` in `tests/run.luau` (ref: 12-tests.md §run.luau [fix])
- [ ] Fix MockPromise `expect()` to preserve structured `StarknetError` table identity instead of converting to string (ref: 12-tests.md §MockPromise [fix])

---

### R.3.8 Fix wallet → contract Layer Violation

**Description**: `Account.luau` imports `contract/ERC20.luau` — the only `require()` pointing from a lower layer to a higher one. Used in `checkDeploymentBalance()` and `getDeploymentFundingInfo()`.

**Requirements**:
- [ ] Break the dependency by accepting a balance-checking callback, or move balance-query logic to a provider-layer utility (ref: 14-cross-cutting.md §1)

---

### R.3.9 Fix SponsoredExecutor safeCall() Swallowing Errors

**Description**: `safeCall()` catches callback errors and only calls `warn()`, silently discarding the error. Callers have no way to detect or handle the failure.

**Requirements**:
- [ ] Fix `safeCall()` to propagate or configurable handler instead of silently swallowing callback errors with `warn()` (ref: 08-paymaster.md §SponsoredExecutor [refactor])

---

## Phase R4: Performance

Optimization opportunities identified during the audit. All are low priority since the codebase already uses `--!native` and `--!optimize 2` on crypto paths.

---

### R.4.1 Windowed Scalar Multiplication

**Description**: `StarkCurve.scalarMul()` uses basic double-and-add. A 4-bit window would reduce additions from ~126 to ~63 for 252-bit scalars (~40% speedup for ECDSA verify).

**Requirements**:
- [ ] Implement windowed method or wNAF for `scalarMul()` (ref: 01-crypto.md §StarkCurve [perf])
- [ ] Consider Shamir's trick for ECDSA verify (2 independent scalar muls → interleaved) (ref: 01-crypto.md §ECDSA [perf])

---

### R.4.2 Poseidon & Pedersen Initialization

**Requirements**:
- [ ] Consider pre-computing Poseidon round constants as raw buffer literals or lazy initialization (273 `StarkField.fromHex()` calls at require time) (ref: 01-crypto.md §Poseidon [perf])
- [ ] Document Pedersen precomputation memory cost (~388 KB for 504 Jacobian points) (ref: 01-crypto.md §Pedersen [perf])

---

### R.4.3 TypedData Performance

**Requirements**:
- [ ] Replace `tableContains()` O(n) linear scan with hash-set (`seen[name] = true`) for O(1) cycle detection in `getDependencies()` (ref: 06-wallet.md §TypedData [perf])
- [ ] Consider in-place pairing in `merkleRoot()` to avoid O(n log n) temporary allocations for large Merkle trees (ref: 06-wallet.md §TypedData [perf])

---

### R.4.4 PaymasterPolicy Timestamp Pruning

**Description**: Rate-limit timestamps grow unboundedly. A player with high activity accumulates thousands of timestamps iterated on every `validate()`.

**Requirements**:
- [ ] Prune expired timestamps in `recordUsage()` after insertion (ref: 08-paymaster.md §PaymasterPolicy [refactor])

---

### R.4.5 Cache & Queue Micro-Optimizations

**Requirements**:
- [ ] Cache `require("@lune/serde")` at module level in PaymasterRpc instead of re-requiring on every `_jsonEncode`/`_jsonDecode` (ref: 08-paymaster.md §PaymasterRpc [perf])
- [ ] Consider tracking NonceManager `pendingCount` incrementally instead of O(n) table iteration on every `reserve()` (ref: 04-provider.md §NonceManager [refactor])
- [ ] Fix `OutsideExecution.validateCalls()` normalizing every hex on every comparison — pre-normalize once (ref: 06-wallet.md §OutsideExecution [perf])
- [ ] Consider lazy selector computation in `AbiCodec.parseAbi()` for large ABIs instead of eager computation (ref: 07-contract.md §AbiCodec [perf])
- [ ] Cap `SponsoredExecutor` metrics `byContract` and `byMethod` maps — grow unboundedly with no eviction (ref: 08-paymaster.md §SponsoredExecutor [refactor])
- [ ] Consider caching serialized cache keys or using a cheaper key strategy than `_jsonEncode(params)` on every `fetch()` call (ref: 04-provider.md §RpcProvider [perf])

---

### R.4.6 BigInt powmod via Barrett

**Description**: `BigInt.powmod()` uses division-based `mulmod()` instead of Barrett reduction.

**Requirements**:
- [x] Add `BigInt.powmodB(a, e, ctx)` so callers outside field modules can use the fast path (ref: 01-crypto.md §BigInt [perf]; see also R.1.4 for DRY motivation — same work item)

---

### R.4.7 Build _eventsByName Lookup in Contract ✅

**Description**: `hasEvent()` is O(n) linear scan vs O(1) `hasFunction()` because events are keyed by selector hex.

**Requirements**:
- [x] Maintain parallel `_eventsByName` lookup table built in `parseAbiEvents()` (ref: 07-contract.md §Contract [refactor])

---

## Phase R5: Test Improvements

Fill coverage gaps, strengthen assertions, and add missing test vectors.

---

### R.5.1 Fill Critical Test Coverage Gaps ✅

**Requirements**:
- [x] Test `addDeployAccountTransaction` at provider level (only indirectly exercised) (ref: 12-tests.md §provider [fix])
- [x] Test `Account:deployAccount()` directly in Account.spec (only tested via BatchDeploy/AccountFactory) (ref: 12-tests.md §wallet [test])
- [x] Test `Account:waitForReceipt()` (not tested anywhere) (ref: 12-tests.md §wallet [test])
- [x] Test `Account:execute()` with NonceManager integration (ref: 12-tests.md §wallet [test], 06-wallet.md §16)
- [x] Test multicall (2+ calls) through `Account:execute()` (ref: 06-wallet.md §16)
- [x] Add AbiCodec error path tests (4 error branches untested: invalid Result, unknown enum variant, non-table enum, invalid variant index) (ref: 12-tests.md §contract [fix], 07-contract.md §AbiCodec [test])
- [x] Test `Contract:call()` blockId parameter (never exercised) (ref: 12-tests.md §contract [test])
- [x] Test `toRpcResourceBounds()` dropping `l1DataGas` (ref: 12-tests.md §tx [fix])
- [x] Test `skipValidate=false` in execute/deploy (ref: 12-tests.md §tx [test])
- [x] Test `CallData.encodeMulticall()` with malformed Call objects (missing fields, wrong types) (ref: 05-tx.md §CallData [test])
- [x] Test `queryEvents` continuation_token passthrough (ref: 12-tests.md §contract [test])
- [x] Test interface ABI parsing (nested `items` extraction) (ref: 12-tests.md §contract [test])
- [x] Test `AbiCodec.decodeEvent()` directly (currently only tested indirectly through Contract) (ref: 12-tests.md §contract [test])
- [x] Test `AbiCodec.resolveType()` fallback with unknown type names (ref: 07-contract.md §AbiCodec [test])
- [x] Test `PaymasterBudget` with NaN input values (ref: 12-tests.md §paymaster [test])
- [x] Test `PaymasterRpc` rate limiter timeout branch (never triggered in current tests) (ref: 12-tests.md §paymaster [test])
- [x] Test `estimateMessageFee` priority classification in RequestQueue (ref: 12-tests.md §provider [test])

---

### R.5.2 Strengthen Error Assertions

**Requirements**:
- [ ] Standardize on `:toThrowCode()` or `:toThrowType()` for all structured error assertions — audit all bare `:toThrow()` calls (7+ files) (ref: 12-tests.md §cross-cutting #7)
- [ ] Add error code assertions to StarkSigner constructor error tests (currently checks type only, not code) (ref: 03-signer.md §StarkSigner [test])
- [ ] Replace hardcoded error code numbers in PaymasterRpc.spec with `ErrorCodes.XXX.code` symbolic references (ref: 12-tests.md §paymaster [fix])
- [ ] Replace magic number `2010` in RequestQueue error test with `ErrorCodes.QUEUE_FULL.code` (ref: 12-tests.md §provider [test])
- [ ] Add error path tests for AbiCodec, TransactionHash, and ResponseCache (currently none) (ref: 12-tests.md §cross-cutting #7)

---

### R.5.3 Expand Error System Tests

**Requirements**:
- [x] Test 26 untested error codes: 2010-2015, 5002-5003, 6000-6004, 7000-7020 ranges (ref: 02-errors.md §ErrorCodes [test])
- [x] Add code uniqueness assertion (no duplicate numeric codes) (ref: 02-errors.md §ErrorCodes [test])
- [x] Add `tostring` tests for `ValidationError`, `AbiError`, `TransactionError` subtypes (ref: 02-errors.md §StarknetError [test])
- [x] Add negative test for `isStarknetError` with table that has `_type`+`message` but no `is` function (ref: 02-errors.md §StarknetError [test])
- [x] Add test for `:is()` with manually-constructed object whose `_type` is not in `TYPE_HIERARCHY` (ref: 02-errors.md §StarknetError [test])
- [x] Update constants.spec.luau completeness test to include `ANY_CALLER`, `ARGENT_ACCOUNT_CLASS_HASH`, `BRAAVOS_ACCOUNT_CLASS_HASH`, `BRAAVOS_BASE_ACCOUNT_CLASS_HASH` (ref: 09-root.md §constant tests [test])

---

### R.5.4 Add Barrel Export Smoke Test

**Requirements**:
- [x] Create `tests/init.spec.luau` that validates main barrel exports all 9 expected namespace keys with expected sub-module keys (ref: 09-root.md §init.luau tests [test])

---

### R.5.5 Signer & Crypto Edge Case Tests ✅

**Requirements**:
- [x] Test `key == N-1` (valid) and `key == N+1` (invalid) boundary in StarkSigner constructor (ref: 03-signer.md §StarkSigner [test])
- [x] Test `signRaw(BigInt.zero())` and `signRaw(BigInt.fromHex(N_hex))` for extreme hash values (ref: 03-signer.md §StarkSigner [test])
- [x] Add more Pedersen hash vectors (only 5 explicit tests currently) (ref: 01-crypto.md §Pedersen [test])
- [x] Test `hashMany` with larger inputs (8+, 16+, 100+ elements) for Poseidon sponge padding (ref: 01-crypto.md §Poseidon [test])
- [x] Add TransactionHash fuzz/property test for hash determinism (same inputs → same output) (ref: 05-tx.md §TransactionHash [test])
- [x] Add integration tests between crypto modules (e.g., Poseidon→StarkField→BigInt pipeline, ECDSA→StarkCurve→StarkScalarField pipeline) (ref: 12-tests.md §crypto [test])

---

### R.5.6 Wallet & Contract Test Gaps

**Requirements**:
- [ ] Add V3 PayFee signing roundtrip test in OutsideExecution (only NoFee tested) (ref: 06-wallet.md §OutsideExecution [test])
- [ ] Add Merkle tree ACTIVE revision test in TypedData (only LEGACY tested) (ref: 06-wallet.md §TypedData [test])
- [ ] Add `AccountType.custom()` with missing fields test (ref: 06-wallet.md §AccountType [test])
- [ ] Add Braavos account type test in factory tests (ref: 06-wallet.md §AccountFactory [test])
- [ ] Test `parseEvents()` hex normalization mismatch and silent decode failure path (ref: 07-contract.md §Contract [test])
- [ ] Test deeply nested recursive types in AbiCodec (`Array<Array<struct>>`, `Option<Option<felt252>>`) (ref: 07-contract.md §AbiCodec [test])
- [ ] Test OutsideExecution `INTERFACE_ID_V1`/`INTERFACE_ID_V2` exposed constants (ref: 12-tests.md §wallet [test])
- [ ] Test Contract dynamic dispatch with trailing options table that conflicts with struct input (ref: 07-contract.md §Contract [test])
- [ ] Test TypedData `getDependencies` indirect cycle detection, ByteArray 31-byte boundary, negative i128 assertion (ref: 12-tests.md §wallet [test])

---

### R.5.7 Reduce Test Redundancy

**Requirements**:
- [ ] Reduce redundant address computation tests (same 3 vectors verified in 4+ test files) (ref: 06-wallet.md §17)
- [ ] Move 4 `MockPromise.all` tests from BatchDeploy.spec to `tests/helpers/MockPromise.spec.luau` (ref: 12-tests.md §wallet [test])
- [ ] Fix 5 phantom module name spec files (describe blocks reference wrong module names) (ref: 12-tests.md §cross-cutting)
- [ ] Centralize test vectors — currently only consumed by `cross-reference.spec` while all other 40 specs hardcode vectors inline (ref: 12-tests.md §test-vectors [test])
- [ ] Add centralized vectors for SHA-256, StarkScalarField, StarkSigner, TypedData, AbiCodec, DeployAccountHash (ref: 12-tests.md §test-vectors [test])
- [ ] Add commit hashes or version tags to cited test vector sources (ref: 12-tests.md §test-vectors [test])

---

### R.5.8 Test Framework Improvements ✅

**Description**: The test runner (`run.luau`) lacks standard test infrastructure features that would improve test reliability and developer experience.

**Requirements**:
- [x] Consider adding `beforeEach`/`afterEach` hooks for test isolation (ref: 12-tests.md §run.luau [test])
- [x] Consider adding per-test timeouts to catch infinite loops (ref: 12-tests.md §run.luau [test])
- [x] Consider parallel test execution for faster CI (ref: 12-tests.md §run.luau [test])
- [x] Consider adding `finally()`, `cancel()`, `race()`, `allSettled()` to MockPromise for completeness (low priority — none currently used in production) (ref: 12-tests.md §MockPromise [test])

---

## Phase R6: Documentation

Fix inaccurate documentation, fill coverage gaps, and update stale content.

---

### R.6.1 Overhaul SPEC.md

**Description**: SPEC.md has 13+ nonexistent file paths, 50+ function signature mismatches, 15+ modules with zero spec coverage, and fundamentally wrong error handling description.

**Requirements**:
- [ ] Fix all nonexistent file paths (SignerInterface.luau, RpcMethods.luau, CalldataEncoder.luau, TransactionTypes.luau, AccountTypes.luau, AbiParser.luau, AbiTypes.luau, presets/ subdirectory, etc.) (ref: 11-docs.md §SPEC.md)
- [ ] Fix all function signature mismatches (StarkCurve param order, ECDSA return types, RpcProvider config, Account methods, etc.) (ref: 11-docs.md §SPEC.md)
- [ ] Add spec coverage for 15+ unspecced modules: constants, errors, AbiCodec, TypedData, OutsideExecution, AccountType, AccountFactory, EventPoller, RequestQueue, ResponseCache, NonceManager, entire paymaster/ (ref: 11-docs.md §SPEC.md)
- [ ] Fix error handling section: field is `_type` not `type`, update category descriptions to match actual 7-range numeric system (ref: 11-docs.md §SPEC.md)
- [ ] Fix constants/networks section to match actual `Constants.SN_MAIN/SN_SEPOLIA` etc. (ref: 11-docs.md §SPEC.md)

---

### R.6.2 Update ROADMAP.md & CHANGELOG.md

**Description**: ROADMAP.md has 10 sections with all checkboxes incorrectly marked `[ ]` when work is 100% complete. CHANGELOG.md claims "1,429 tests" (actual ~2,075+) and has factually wrong "Known Limitations".

**Requirements**:
- [ ] Mark all completed ROADMAP sections as done: 3.3.1, 3.3.3, 3.3.4, 3.3.5, 3.4.1-3.4.4, 3.4.7, 3.4.8 (ref: 11-docs.md §ROADMAP.md)
- [ ] Fix ROADMAP phase numbering (Phase 4 uses `3.4.x` prefix) and add missing Phase 1 entries (ref: 11-docs.md §ROADMAP.md)
- [ ] Update CHANGELOG test counts to match actual suite (ref: 11-docs.md §CHANGELOG.md)
- [ ] Fix CHANGELOG "Known Limitations" — remove false claims about missing DEPLOY_ACCOUNT and paymaster support (ref: 11-docs.md §CHANGELOG.md)
- [ ] Add CHANGELOG entries for all missing implemented modules: paymaster/, deploy account, AccountType, AccountFactory, BatchDeploy, prefunding, OutsideExecution, ContractEvents, etc. (ref: 11-docs.md §CHANGELOG.md)
- [ ] Fix API naming mismatches between roadmap and code (ref: 11-docs.md §ROADMAP.md)
- [ ] Resolve test count contradiction between 12-tests.md (1926) and 11-docs.md (~2,075+) — re-count with `make test` and update both docs (ref: 14-cross-cutting.md §11)

---

### R.6.3 Fix All Guides

**Description**: Every guide has inaccuracies ranging from nonexistent methods to broken code examples.

**Requirements**:
- [ ] **getting-started.md**: Add `paymaster` module to module listing (ref: 11-docs.md §getting-started)
- [ ] **crypto.md**: Fix StarkCurve `pointAdd`/`pointDouble` (actual: `jacobianAdd`/`jacobianDouble`), fix `scalarMul` param order, fix ECDSA return type description, document missing functions (ref: 11-docs.md §crypto.md)
- [ ] **accounts.md**: Fix `classHash` vs `accountType` usage, Braavos example, `computeAddress` required params, `signMessage` return type, add AccountType/AccountFactory/OutsideExecution docs, add 9+ missing Account methods (ref: 11-docs.md §accounts.md)
- [ ] **contracts.md**: Remove nonexistent `Contract:attach()`, add 7 missing Contract methods, add event ABI examples, document camelCase aliases, add preset `getAbi()` methods (ref: 11-docs.md §contracts.md)
- [ ] **patterns.md**: Fix `tonumber(balance.low, 16)` bug, fix `Keccak.getSelectorFromName()` buffer→hex, fix `getEvents` filter BlockId format, fix wallet linking point decompression, fix address comparison normalization, add missing Keccak import, add paymaster/deploy/error-handling patterns (ref: 11-docs.md §patterns.md)
- [ ] **roblox.md**: Fix config nesting (`maxQueueDepth`→`queueConfig`, `maxCacheEntries`→`cacheConfig.maxEntries`), complete cache TTL table, fix `tonumber` bugs, fix `signRaw` parameter type, fix `--!native` terminology (native codegen, not JIT), add NonceManager/paymaster/deploy guidance (ref: 11-docs.md §roblox.md)
- [ ] **api-reference.md**: Add 8 missing modules (AccountType, AccountFactory, OutsideExecution, PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor), fix TypedData section (wrong function names), fix TransactionHash identifiers, remove nonexistent `Contract:attach()`, add 9+ missing Account methods, add 7 missing Contract methods, add 18 missing ErrorCodes, resolve AbiCodec public/private contradiction (ref: 11-docs.md §api-reference.md)

---

### R.6.4 Update README.md

**Requirements**:
- [ ] Add `errors` and `paymaster` modules to API Overview table (ref: 13-config-build.md §README [refactor])
- [ ] Add `src/errors/`, `src/paymaster/`, `src/constants.luau` to project structure diagram (ref: 13-config-build.md §README [refactor])
- [ ] Add feature highlights for SNIP-9/12/29, paymaster, deploy, events, queue/cache/nonce (ref: 13-config-build.md §README)
- [ ] Consider adding test count badge (ref: 13-config-build.md §README)
- [ ] Add quick-start require path note for pesde users (`roblox_packages` vs `Packages` path difference) (ref: 13-config-build.md §README)
- [ ] Add required Rokit version or tool prerequisites to README (ref: 13-config-build.md §fresh clone experience)

---

### R.6.5 Add Missing Examples

**Description**: 5 current examples cover basic usage. Production-critical features (paymaster, deploy, events, error handling) have no example coverage.

**Requirements**:
- [ ] Create `sponsored-transaction.luau` — gasless game action using SponsoredExecutor + AvnuPaymaster (ref: 10-examples.md §feature coverage gaps)
- [ ] Create `deploy-account.luau` — create and deploy a new player account on-chain (ref: 10-examples.md §feature coverage gaps)
- [ ] Create `event-listener.luau` — poll for on-chain events and react in-game (ref: 10-examples.md §feature coverage gaps)
- [ ] Create `error-handling.luau` — demonstrate StarknetError types, `:is()` checks, recovery patterns (ref: 10-examples.md §feature coverage gaps)
- [ ] Create `batch-onboarding.luau` — batch account creation using AccountFactory (ref: 10-examples.md §feature coverage gaps [doc])
- [ ] Create `typed-data.luau` — SNIP-12 TypedData signing example (ref: 10-examples.md §feature coverage gaps [doc])
- [ ] Create `outside-execution.luau` — SNIP-9 Outside Execution example (ref: 10-examples.md §feature coverage gaps [doc])
- [ ] Create `provider-features.luau` — RequestQueue, ResponseCache, NonceManager configuration example (ref: 10-examples.md §feature coverage gaps [doc])
- [ ] Fix `read-contract.luau` missing `:catch()` on metadata calls and missing module return (ref: 10-examples.md §read-contract [doc])
- [ ] Polish existing examples — add missing annotations and pedagogical improvements:
  - [ ] `leaderboard.luau`: note single contract instance suffices for read+write; add u128 score overflow warning (>2^53) (ref: 10-examples.md §leaderboard [doc])
  - [ ] `multicall.luau`: annotate `feeMultiplier = 1.5` as default or use non-default value (ref: 10-examples.md §multicall [doc])
  - [ ] `nft-gate.luau`: add `:expect()` thread-blocking comment; use placeholder address instead of hardcoded (ref: 10-examples.md §nft-gate [doc])
  - [ ] `read-contract.luau`: add human-readable balance formatting (divide by 10^18) (ref: 10-examples.md §read-contract [doc])
  - [ ] `send-transaction.luau`: annotate `retryInterval = 5` as default; add f64 precision warning for large balances (ref: 10-examples.md §send-transaction [doc])
  - [ ] Cross-cutting: standardize module return pattern across all examples (ref: 10-examples.md §cross-cutting [doc])
  - [ ] Cross-cutting: retrofit structured error handling (`:is()`, error codes) in existing examples (ref: 10-examples.md §cross-cutting [doc])
  - [ ] Cross-cutting: explicitly state Roblox-only runtime in examples documentation (ref: 10-examples.md §cross-cutting [doc])

---

### R.6.6 Add Missing Code-Level Documentation

**Description**: Several design decisions, intentional omissions, and known Luau limitations are undocumented in source code, making the codebase harder to reason about for contributors.

**Requirements**:
- [ ] Document intentional `sqrt()` omission in `StarkScalarField` — scalar field does not need square roots (ref: 01-crypto.md §StarkScalarField [api])
- [ ] Document `StarkCurve` Jacobian identity convention `{ x = one(), y = one(), z = zero() }` (ref: 01-crypto.md §StarkCurve [type])
- [ ] Document intentional redundant private key validation between `StarkSigner` and `ECDSA` (defense-in-depth) (ref: 03-signer.md §StarkSigner [refactor])
- [ ] Document `StarkSigner.getPubKey()` returning full `AffinePoint` — note that `getPublicKeyHex()` is preferred for most uses (ref: 03-signer.md §StarkSigner [api])
- [ ] Document intentional omission of `getPrivateKeyHex()` accessor on StarkSigner (ref: 03-signer.md §StarkSigner [api])
- [ ] Document `ResponseCache.getTTLForMethod()` returning nil for unknown methods as intentional (ref: 04-provider.md §ResponseCache [refactor])
- [ ] Document `TransactionBuilder.skipValidate` default of `true` explicitly in constructor/type (ref: 05-tx.md §TransactionBuilder [api])
- [ ] Document `waitForReceipt` 3-layer delegation chain: Account → TransactionBuilder → RpcProvider (ref: 05-tx.md §TransactionBuilder [api], 06-wallet.md §Account [api])
- [ ] Document `Account.CLASS_HASH_TO_TYPE` keys are manually normalized — implicit contract with `BigInt.toHex()` (ref: 06-wallet.md §Account [type])
- [ ] Fix `tx/init.luau` module comment — says "V3 INVOKE" but module also handles DEPLOY_ACCOUNT (ref: 05-tx.md §tx/init.luau [doc])
- [ ] Add class-level doc comment to `Contract.luau` (ref: 07-contract.md §Contract [doc])

---

## Phase R7: Config, Build & Infrastructure

Build system, project files, and configuration improvements.

---

### R.7.1 Fix Project JSON Structure for Wally Publishing

**Description**: `default.project.json` uses DataModel root (development layout), but the Roblox ecosystem convention for Wally packages is that `default.project.json` describes the package's own tree (root = library module).

**Requirements**:
- [x] Restructure `default.project.json` to be Wally package descriptor with `$path: "src"` root (ref: 13-config-build.md §default.project.json)
- [x] Move current DataModel layout to `dev.project.json` (or new `place.project.json`) (ref: 13-config-build.md §default.project.json)
- [x] Update Makefile `serve` target to reference `rojo serve dev.project.json` (ref: 13-config-build.md §Makefile)
- [x] Update Makefile `build` target for correct distributable rbxm (ref: 13-config-build.md §Makefile)

---

### R.7.2 Makefile Improvements

**Requirements**:
- [ ] Add `build: install` dependency to prevent building without Packages (ref: 13-config-build.md §Makefile)
- [ ] Add `clean` target to remove generated artifacts (ref: 13-config-build.md §Makefile)
- [ ] Fix `check` target dependency ordering — use `&&` chaining so failures short-circuit (ref: 13-config-build.md §Makefile)
- [ ] Add convenience targets for common workflows: `test-one` (single spec file), `build-and-test` (ref: 13-config-build.md §Makefile [refactor])

---

### R.7.3 Configuration Cleanup

**Requirements**:
- [ ] Remove `ServerPackages` alias from `.luaurc` (directory doesn't exist) (ref: 13-config-build.md §selene/stylua/luaurc)
- [ ] Remove `daily3014/cryptography` mention from CLAUDE.md (it's not a dependency — only a comment attribution in BigInt.luau) (ref: 13-config-build.md §wally.toml)
- [ ] Document pesde scope difference (`magic` vs `b-j-roberts`) (ref: 13-config-build.md §wally.toml)
- [ ] Document dual require pattern (`require(script.X)` in init.luau barrels vs `require("./X")` in source modules) with a comment in each init.luau explaining the convention (ref: 14-cross-cutting.md §8)

---

### R.7.4 Add SDK Version Constant

**Requirements**:
- [ ] Add `Constants.SDK_VERSION = "0.1.0"` to `src/constants.luau` for runtime version checking (ref: 09-root.md §missing constants [api], 13-config-build.md §version consistency)

---

### R.7.5 CI Improvements

**Requirements**:
- [ ] Consider adding Rokit tool caching in CI for faster builds (ref: 13-config-build.md §CI)
- [ ] Fix release workflow rbxm artifact tree structure (same DataModel root issue) (ref: 13-config-build.md §CI)
- [ ] Consider CI matrix testing across OS (macOS + Ubuntu) (ref: 13-config-build.md §CI [refactor])
- [ ] Add Sepolia integration test step to CI (currently not exercised, no env vars configured) (ref: 12-tests.md §sepolia [test])
- [ ] Expand integration test coverage to include transaction submission, account deployment, event polling, and paymaster flows (ref: 12-tests.md §sepolia [test])

---

### R.7.6 Decide on AbiCodec Export Status

**Description**: `AbiCodec` is intentionally not exported through the barrel but `api-reference.md` documents it as public. Consumers wanting custom calldata encoding have no access to the recursive type-aware codec.

**Requirements**:
- [ ] Either export AbiCodec in `contract/init.luau` and update source comment, or remove it from `api-reference.md` (ref: 09-root.md §API surface, 07-contract.md §barrel [api])
- [ ] If not exporting, consider adding `Contract.encodeCalldata(abi, functionName, args)` static method as a public thin wrapper (ref: 07-contract.md §barrel [api])

---

## Feature Items (from [feat] tags)

These are feature gaps identified during review, not refactor work. Included for completeness.

---

### R.F.1 Add Event Definitions to ERC20/ERC721 Preset ABIs

**Description**: Neither preset's hardcoded ABI includes Transfer, Approval, or ApprovalForAll event definitions, making `parseEvents()`, `hasEvent()`, and `getEvents()` non-functional on preset instances.

**Requirements**:
- [ ] Add Transfer and Approval event definitions to ERC20_ABI (ref: 07-contract.md §ERC20 [feat], 14-cross-cutting.md §10)
- [ ] Add Transfer, Approval, and ApprovalForAll event definitions to ERC721_ABI (ref: 07-contract.md §ERC721 [feat])
- [ ] Add ERC-20 event parsing tests for new Transfer/Approval event definitions (ref: 07-contract.md §ERC20 [test])
- [ ] Add ERC-721 event parsing tests for new Transfer/Approval/ApprovalForAll event definitions (ref: 07-contract.md §ERC721 [test])

**Implementation Notes**:
- Data-only change (adding ABI entries) with zero logic changes needed

---

### R.F.2 Add Missing ERC Standard Functions

**Requirements**:
- [ ] Add `increase_allowance`/`decrease_allowance` (+ camelCase) to ERC20 ABI (ref: 07-contract.md §ERC20 [feat])
- [ ] Add `safe_transfer_from`, `token_uri`, `supports_interface` (+ camelCase) to ERC721 ABI (ref: 07-contract.md §ERC721 [feat])
- [ ] Add tests for new ERC-721 functions (`safe_transfer_from`, `token_uri`, `supports_interface`) (ref: 07-contract.md §ERC721 [test])

---

### R.F.3 Add Braavos Preset to AccountType

**Description**: AccountType defines OZ and Argent but not Braavos. `Account.fromPrivateKey()` handles Braavos natively, but AccountFactory cannot create Braavos accounts with a preset type.

**Requirements**:
- [ ] Add `AccountType.Braavos` callable type with Braavos base class hash and calldata format (ref: 06-wallet.md §AccountType [feat])

---

### R.F.4 Add AccountType.custom() Validation

**Requirements**:
- [ ] Validate `config.type`, `config.classHash`, and `config.buildCalldata` are present in `AccountType.custom()` (ref: 06-wallet.md §AccountType [api])

---

## Appendix: Deferred Low-Priority Items

Items identified during review that are intentionally deferred — v2 API design ideas, minor convenience improvements, and observations that are not actionable refactors. Included for completeness and future reference.

- [ ] Consider INFINITY sentinel return for `StarkCurve.scalarMul()` edge cases instead of `nil` (ref: 01-crypto.md §StarkCurve — tracked in R.2.5 as consideration)
- [ ] `tx` namespace name is terse — consider renaming to `transaction` in a future major version (ref: 09-root.md §init.luau [api])
- [ ] No convenience top-level re-exports from main `init.luau` (e.g., `StarknetLuau.Account` shorthand) (ref: 09-root.md §init.luau [api])
- [ ] No type re-exports from main `init.luau` (ref: 09-root.md §init.luau [api])
- [ ] All three V3 version constants have the same value — `TransactionHash.V3_VERSION` should derive from `Constants` (ref: 09-root.md §constants.luau [refactor])
- [ ] Transaction type prefixes, resource names, and SNIP-9 Interface IDs could be centralized in constants — judgment call on scope (ref: 09-root.md §constants.luau [refactor])
- [ ] `constants.spec.luau` cross-reference test validates `TransactionHash.SN_MAIN/SN_SEPOLIA` but not `Constants.SN_MAIN/SN_SEPOLIA` (ref: 09-root.md §constant tests [test])
- [ ] `AvnuPaymaster` has no way to update API key after construction (ref: 08-paymaster.md §AvnuPaymaster [api])
- [ ] `PaymasterBudget` has no `destroy()` or lifecycle cleanup method (ref: 08-paymaster.md §PaymasterBudget [api])
- [ ] `SponsoredExecutor` has no getter for inner components (account, paymaster, policy, budget) (ref: 08-paymaster.md §SponsoredExecutor [api])
- [ ] `SponsoredExecutor` has no way to update `feeMode` after construction (ref: 08-paymaster.md §SponsoredExecutor [api])
- [ ] `AccountFactory.batchDeploy` uses `Promise.all():expect()` inside `Promise.new()` — synchronous blocking pattern (ref: 06-wallet.md §AccountFactory [api])
- [ ] `Contract` dynamic dispatch heuristic for detecting options table vs struct input is fragile — marked LOW in source (ref: 07-contract.md §Contract [api])
- [ ] `ResponseCache.invalidateByPrefix()` is O(n) — noted as acceptable for current cache sizes (ref: 04-provider.md §ResponseCache [refactor])
- [ ] `Account.getPublicKeyHex()` is a trivial pass-through to signer — document as convenience delegation (ref: 06-wallet.md §Account [api])
- [ ] `CallData.numberToHex()` uses `StarkField` for a non-field operation — consider standalone impl (ref: 05-tx.md §CallData [api])
- [ ] Test runner: `run.luau` test-vectors.luau only consumed by cross-reference.spec — 40 other specs hardcode vectors inline (broader than R.5.7 centralization) (ref: 12-tests.md §test-vectors [test])
- [ ] `getAllEvents()` pagination in RpcProvider duplicates EventPoller pagination logic (ref: 04-provider.md §RpcProvider [refactor])
- [ ] `RequestQueue.dequeue()` uses `table.remove(_, 1)` which is O(n) — acceptable for current max queue depth of 100 (ref: 04-provider.md §RequestQueue [perf])
