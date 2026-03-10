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

Overhaul all documentation to reflect the current codebase (57 source files, 9 modules, 2,846 tests). The SDK has grown significantly since v0.1.0 — adding paymaster (SNIP-29), deploy account, KeyStore, OnboardingManager, shared utilities, and completing 60+ refactor items — but documentation still describes the v0.1.0 state. Every doc file needs updating.

---

### R.6.1 Overhaul SPEC.md

**Description**: SPEC.md describes a v0.1.0 codebase that no longer exists. It has 13+ nonexistent file paths, 50+ function signature mismatches, 25+ modules with zero spec coverage, and a fundamentally wrong error handling description. The repository structure section (§2.3) lists 35 files; the actual codebase has 57. The architecture diagram omits 3 entire module trees (paymaster/, shared/, errors/).

**Requirements**:
- [ ] Rewrite §2.1 architecture diagram — add `paymaster`, `shared`, and `errors` module boxes; show paymaster→provider dependency; show shared as cross-cutting utility layer
- [ ] Rewrite §2.2 dependency graph — add paymaster→wallet→provider, errors as cross-cutting, shared as foundation alongside crypto
- [ ] Rewrite §2.3 repository structure to match actual 57-file layout:
  - Fix nonexistent paths: `SignerInterface.luau` (inline in StarkSigner), `RpcMethods.luau` (in RpcProvider directly), `CalldataEncoder.luau` (actual: `CallData.luau`), `TransactionTypes.luau` (inline), `AccountTypes.luau` (actual: `AccountType.luau`), `AbiParser.luau`/`AbiTypes.luau` (actual: `AbiCodec.luau`), `presets/` subdir (files are directly in `src/contract/`)
  - Add all missing source files: `FieldFactory.luau`, `PoseidonConstants.luau`, `JsonRpcClient.luau`, `RequestQueue.luau`, `ResponseCache.luau`, `NonceManager.luau`, `EventPoller.luau`, `AccountType.luau`, `AccountFactory.luau`, `OutsideExecution.luau`, `KeyStore.luau`, `OnboardingManager.luau`, `TypedData.luau`, `AbiCodec.luau`, `PresetFactory.luau`, entire `paymaster/` (5 modules), entire `shared/` (5 modules), entire `errors/` (3 modules), `constants.luau`
  - Add missing test files: 50 spec files across 13 directories (vs 11 listed in spec)
  - Fix example file name: `sign-transaction.luau` → `send-transaction.luau`
- [ ] Fix all function signature mismatches across §3.x modules (ref: 11-docs.md §SPEC.md):
  - StarkCurve: `scalarMul(p, k)` not `(k, p)`; no `pointAdd`/`pointDouble` (actual: `jacobianAdd`/`jacobianDouble`); type is `AffinePoint` not `Point`; `StarkCurve.P` not exported
  - ECDSA: return type is `{ r: buffer, s: buffer }` not `{ r: Felt, s: Felt }`
  - Signer: `signTransaction` takes `buffer` not `Felt`; `signRaw` returns `{ r: buffer, s: buffer }`
  - RpcProvider: config missing `enableQueue/Cache/NonceManager`, `queueConfig`, `cacheConfig`, injection fields; 12+ methods undocumented
  - CallData (not CalldataEncoder): `encodeFelt` is string-only; missing `encodeShortString`, `numberToHex`, `concat`
  - TransactionHash: function is `calculateInvokeTransactionHash` not `computeInvokeV3Hash`; missing `calculateDeployAccountTransactionHash`
  - TransactionBuilder: no public `buildInvoke`/`submitTransaction`; missing `deployAccount`/`estimateDeployAccountFee`; `execute` returns `Promise<ExecuteResult>` not `Promise<string>`
  - Account: `computeAddress` classHash is required; no public `.publicKey`/`.provider` properties; no `getBalance()` method; missing 10+ instance methods, 5+ static methods
  - NonceManager: wrong location (provider/ not wallet/); API is `reserve/confirm/reject/resync` not `getNonce/incrementNonce/invalidate`
  - Contract: no `attach()` method; missing 7 methods (`getFunctions`, `getFunction`, `hasFunction`, `parseEvents`, `queryEvents`, `getEvents`, `hasEvent`)
  - Presets: access path is `Starknet.contract.ERC20` not `Starknet.contract.presets.ERC20`
- [ ] Add spec sections for 25+ unspecced modules:
  - `src/constants.luau` — chain IDs, class hashes, token addresses, SDK version
  - `src/errors/` — StarknetError hierarchy, ErrorCodes 7-range system (1000s-7000s), `:is()` type checking
  - `src/contract/AbiCodec.luau` — recursive encoder/decoder for all Cairo types (now publicly exported)
  - `src/contract/PresetFactory.luau` — DRY factory for ERC-20/ERC-721 preset construction
  - `src/wallet/TypedData.luau` — SNIP-12 LEGACY (Pedersen) and ACTIVE (Poseidon) revisions
  - `src/wallet/OutsideExecution.luau` — SNIP-9 V1/V2/V3 meta-transactions
  - `src/wallet/AccountType.luau` — OZ, Argent callable account type constructors, `custom()`
  - `src/wallet/AccountFactory.luau` — `createAccount()`, `batchCreate()`, `batchDeploy()`
  - `src/wallet/KeyStore.luau` — encrypted DataStore key persistence with XOR+HMAC-SHA256
  - `src/wallet/OnboardingManager.luau` — player account lifecycle (onboard, deploy, status, cleanup)
  - `src/provider/EventPoller.luau` — event polling with DataStore persistence, `onCheckpoint` callback
  - `src/provider/RequestQueue.luau` — 3-bucket priority queue with JSON-RPC batching
  - `src/provider/ResponseCache.luau` — LRU cache with per-method TTL, block invalidation
  - `src/provider/NonceManager.luau` — reserve/confirm/reject pattern for parallel nonce management
  - `src/provider/JsonRpcClient.luau` — shared base for RpcProvider and PaymasterRpc
  - `src/paymaster/PaymasterRpc.luau` — SNIP-29 JSON-RPC client
  - `src/paymaster/AvnuPaymaster.luau` — AVNU paymaster integration
  - `src/paymaster/PaymasterPolicy.luau` — policy engine for sponsorship rules
  - `src/paymaster/PaymasterBudget.luau` — per-player budget tracking with DataStore
  - `src/paymaster/SponsoredExecutor.luau` — orchestrator for sponsored execution
  - `src/shared/` — HexUtils, BufferUtils, ByteArray, TestableDefaults, interfaces
  - `src/crypto/FieldFactory.luau` — parameterized field constructor (DRY StarkField/StarkScalarField)
- [ ] Fix §5 error handling: field is `_type` not `type`; update from 8 string categories to actual typed hierarchy with 7 numeric code ranges (1000s=validation, 2000s=RPC, 3000s=signing, 4000s=ABI, 5000s=transaction, 6000s=outside execution, 7000s=paymaster); document `:is()`, `isStarknetError()`, `pcall`-safe identity
- [ ] Fix §8 constants/networks: `Starknet.networks` does not exist; constants are `Constants.SN_MAIN`/`SN_SEPOLIA`; add `SDK_VERSION`, class hash constants, `CONTRACT_ADDRESS_PREFIX`, `ANY_CALLER`
- [ ] Fix §9 usage examples: correct `Starknet.contract.presets.ERC20` → `Starknet.contract.ERC20`

**Implementation Notes**:
- Cross-reference every §3.x API block against the actual source module's exported functions and types. The 11-docs.md audit has a complete list of mismatches but was written before AbiCodec export (now resolved), KeyStore, OnboardingManager, FieldFactory, and shared/ modules were added.
- Consider restructuring §3 to match the actual 9-namespace barrel export: crypto, signer, provider, tx, wallet, contract, constants, errors, paymaster.
- The spec is 1,155 lines — expect ~40% rewrite. Modules with correct specs (BigInt, StarkField, StarkScalarField, Poseidon, Pedersen, Keccak, SHA256) need only minor fixes; modules with wrong specs (Account, Contract, TransactionBuilder, RpcProvider) need full rewrites; 25+ modules need new sections.

---

### R.6.2 Update ROADMAP.md, REFACTOR_ROADMAP.md & CHANGELOG.md

**Description**: ROADMAP.md has 10+ completed sections still marked `[ ]`. REFACTOR_ROADMAP.md has 60+ completed items still marked `[ ]`. CHANGELOG.md only covers v0.1.0 with 1,429 tests (actual: 2,846) and false "Known Limitations". A full v0.2.0 CHANGELOG section is needed covering all post-v0.1.0 work.

**Requirements**:
- [ ] **ROADMAP.md**: Mark all completed sections `[x]`:
  - 2.12 Encrypted Key Store (KeyStore.luau, 72 tests)
  - 2.13 EventPoller lastBlockNumber Persistence (26 tests)
  - All Phase 3 paymaster items: 3.3.1 SNIP-9 (82 tests), 3.3.3 AVNU Paymaster (61 tests), 3.3.4 Account Paymaster Integration, 3.3.5 Paymaster Policy (66 tests)
  - All Phase 4 deploy items: 3.4.1-3.4.4 Deploy Account (hash, builder, RPC, orchestration), 3.4.7 Batch Deploy (53 tests), 3.4.8 Paymaster-Sponsored Deployment
  - Remove stale dependency notes ("Depends on Phase 3... implement after both phases are complete" — both are done)
- [ ] **ROADMAP.md**: Fix structural issues:
  - Fix Phase 4 prefix numbering (`3.4.x` → `4.x` or leave with note)
  - Add missing Phase 1 section (all crypto, signer, provider, tx, wallet, contract are implemented but have no roadmap record)
  - Fix API naming mismatches: `paymaster_execute` → `executeTransaction`, `_computeDeployAccountHash` → `TransactionHash.calculateDeployAccountTransactionHash`, `buildDeployAccountTransaction` → `deployAccount`/`estimateDeployAccountFee`
- [ ] **REFACTOR_ROADMAP.md**: Mark all completed refactor items `[x]` across phases:
  - R1 (14+ items): R.1.1 JsonRpcClient, R.1.2 TestUtils, R.1.4 FieldFactory, R.1.8 DRY Account, R.1.9 DRY TransactionBuilder, R.1.12 DRY Contract/Presets, plus 8+ sub-items
  - R2 (16+ items): R.2.1 shared/interfaces.luau, R.2.2 private method coupling, R.2.6 type annotations, plus 13+ sub-items
  - R3 (9 items): R.3.3 AbiCodec decode bounds, plus all sub-items — phase 100% complete
  - R4 (3 items): R.4.1 windowed scalar mul, R.4.5 cache/queue micro-opts, R.4.6 Barrett powmodB
  - R5 (8 items): R.5.1-R.5.8 all complete — phase 100% complete
  - R7 (4+ items): R.7.1 project JSON, R.7.2 Makefile (partial), R.7.3 config cleanup (partial), R.7.4 SDK version constant
  - Feature items: R.F.1 ERC event definitions, R.F.2 missing ERC functions, R.F.4 AccountType.custom() validation
- [ ] **REFACTOR_ROADMAP.md**: Update summary table completion percentages to reflect actual state
- [ ] **CHANGELOG.md**: Write v0.2.0 section covering all post-v0.1.0 work:
  - **Paymaster (SNIP-29)**: PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor (377+ tests across 5 modules)
  - **Account Paymaster Integration**: `estimatePaymasterFee()`, `executePaymaster()`, `deployWithPaymaster()`, `getDeploymentData()`
  - **Deploy Account V3**: TransactionHash deploy hash, TransactionBuilder deploy flow, Account orchestration with idempotency check, RPC `addDeployAccountTransaction`
  - **Multi-Account-Type Support**: AccountType (OZ, Argent, custom), AccountFactory (`batchCreate`, `batchDeploy`), prefunding helpers
  - **SNIP-9 Outside Execution**: V1/V2/V3 meta-transactions (82 tests)
  - **SNIP-12 TypedData**: LEGACY (Pedersen) and ACTIVE (Poseidon) revisions, Merkle tree, preset types (43 tests)
  - **Encrypted Key Store**: XOR+HMAC-SHA256 encrypted DataStore persistence, secret rotation, GDPR deletion (72 tests)
  - **Onboarding Manager**: Player lifecycle management — onboard, deploy, status tracking, cleanup (37 tests)
  - **EventPoller Persistence**: DataStore checkpointing, `onCheckpoint` callback, `setLastBlockNumber` (26 tests)
  - **AbiCodec**: Recursive encoder/decoder for all Cairo types — now publicly exported (109 tests)
  - **Error System**: Typed hierarchy (5 subtypes), 40+ error codes across 7 categories, `pcall`-safe identity (42 tests)
  - **Refactoring**: JsonRpcClient base, FieldFactory, PresetFactory, shared utilities (HexUtils, BufferUtils, ByteArray, interfaces), DRY reductions (~2,500 lines eliminated)
  - **Performance**: 4-bit windowed scalar mul + Shamir's trick, Barrett powmodB, cache/queue micro-optimizations
  - **Test Improvements**: Test framework with beforeEach/afterEach hooks, per-test timing, --parallel flag, MockPromise enhancements; total 2,846 tests (was 1,429)
  - **Infrastructure**: Wally package JSON restructure, Makefile improvements, SDK version constant, ERC event definitions, missing ERC standard functions
- [ ] **CHANGELOG.md**: Fix v0.1.0 section:
  - Update test count from 1,429 to actual v0.1.0 count (or note v0.2.0 total of 2,846)
  - Fix "Known Limitations": remove false claims about missing DEPLOY_ACCOUNT and missing paymaster support; remove "windowed scalar multiplication not yet applied" (done in R.4.1); keep genuinely pending items (no DECLARE, no WebSocket, no session keys)
  - Update per-module test counts to match current suite

**Implementation Notes**:
- Run `make test` to get authoritative test count (currently 2,846). Individual module counts from MEMORY.md are stale — the refactor phases added/removed/moved tests.
- For REFACTOR_ROADMAP, grep each R.x.x item ID against MEMORY.md's "Implementation Status" to confirm completion. Cross-reference with git log for commit evidence.
- The v0.2.0 CHANGELOG section should follow the same Keep a Changelog format as v0.1.0 (### Added, ### Changed, ### Fixed sections).
- Consider moving completed ROADMAP sections to a "Completed" archive section rather than just checking boxes, to reduce visual noise.

---

### R.6.3 Fix All Guides

**Description**: Every guide has inaccuracies ranging from nonexistent methods to broken code examples. Since the original audit (11-docs.md), additional modules have been added (KeyStore, OnboardingManager, PresetFactory, EventPoller persistence, shared/) that need guide coverage, and the AbiCodec public/private contradiction has been resolved (now exported).

**Requirements**:
- [ ] **getting-started.md**: Add `paymaster` and `shared` modules to module listing; add `wallet.KeyStore`, `wallet.OnboardingManager` to wallet module description (ref: 11-docs.md §getting-started)
- [ ] **crypto.md**: Fix StarkCurve `pointAdd`/`pointDouble` (actual: `jacobianAdd`/`jacobianDouble`), fix `scalarMul` param order `(p, k)`, fix ECDSA return type `{ r: buffer, s: buffer }`, document FieldFactory, document missing BigInt/StarkField/StarkScalarField/StarkCurve functions (ref: 11-docs.md §crypto.md)
- [ ] **accounts.md**:
  - Fix `classHash` vs `accountType` usage and Braavos example
  - Fix `computeAddress` required params (classHash is required)
  - Fix `signMessage` return type
  - Add AccountType/AccountFactory documentation (OZ, Argent, custom(), batchCreate, batchDeploy)
  - Add OutsideExecution (SNIP-9) documentation
  - Add KeyStore documentation (encrypted key persistence, getOrCreate, rotateSecret, deleteKey)
  - Add OnboardingManager documentation (onboard, ensureDeployed, getStatus, removePlayer)
  - Add 10+ missing Account methods (deployAccount, estimateDeployAccountFee, getDeploymentData, deployWithPaymaster, estimatePaymasterFee, executePaymaster, hashMessage, signMessage, waitForReceipt, getPublicKeyHex, static: detectAccountType, getConstructorCalldata, getDeploymentFeeEstimate, checkDeploymentBalance, getDeploymentFundingInfo)
  - (ref: 11-docs.md §accounts.md)
- [ ] **contracts.md**:
  - Remove nonexistent `Contract:attach()`
  - Add 7 missing Contract methods (getFunctions, getFunction, hasFunction, parseEvents, queryEvents, getEvents, hasEvent)
  - Add event ABI examples and document camelCase aliases
  - Add EventPoller documentation including DataStore persistence and `onCheckpoint` callback
  - Add AbiCodec public API documentation (now exported via `Starknet.contract.AbiCodec`)
  - Add PresetFactory documentation
  - Add preset `getAbi()` static methods
  - (ref: 11-docs.md §contracts.md)
- [ ] **patterns.md**:
  - Verify `tonumber(balance.low, 16)` bug (may be fixed by commit faecee7 "Fix Example tonumber Bug")
  - Fix `Keccak.getSelectorFromName()` buffer→hex conversion (needs `StarkField.toHex()`)
  - Fix `getEvents` filter BlockId format (`{ block_tag = "latest" }` not `"latest"`)
  - Fix wallet linking point decompression (needs full y-coordinate)
  - Fix address comparison normalization (use `BigInt.toHex(BigInt.fromHex(...))`)
  - Add missing Keccak import
  - Add paymaster/sponsored transaction pattern (SponsoredExecutor + AvnuPaymaster)
  - Add account deployment/onboarding pattern (KeyStore + OnboardingManager flow)
  - Add structured error handling pattern (StarknetError `:is()`, error codes, recovery)
  - Add NonceManager pattern for parallel transactions
  - (ref: 11-docs.md §patterns.md)
- [ ] **roblox.md**:
  - Fix config nesting (`maxQueueDepth`→`queueConfig.maxQueueDepth`, `maxCacheEntries`→`cacheConfig.maxEntries`)
  - Complete cache TTL table (add `getClass`/`getClassAt` indefinite, `getBlockWithTxs`/`getBlockWithReceipts` 10s, list never-cached methods)
  - Fix `signRaw` parameter type (buffer, not hex string)
  - Fix `--!native` terminology (native codegen, not JIT)
  - Add NonceManager guidance for concurrent server requests
  - Add paymaster integration patterns for gasless player transactions
  - Add KeyStore/OnboardingManager patterns for player wallet setup
  - Add EventPoller persistence guidance (DataStore checkpointing)
  - Verify `tonumber` bugs are fixed (commit faecee7)
  - (ref: 11-docs.md §roblox.md)
- [ ] **api-reference.md**:
  - Add 13+ missing modules: AccountType, AccountFactory, OutsideExecution, KeyStore, OnboardingManager, PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor, PresetFactory, JsonRpcClient, shared/* (HexUtils, BufferUtils, ByteArray, interfaces)
  - Fix TypedData section (wrong function names: actual is `getMessageHash`, `encodeType`, not `hash`/`hashLegacy`/`hashActive`/`encodeValue`)
  - Fix TransactionHash identifiers (`calculateInvokeTransactionHash` not `computeInvokeV3Hash`; add `calculateDeployAccountTransactionHash`)
  - Remove nonexistent `Contract:attach()` and `account:waitForTransaction()` (actual: `waitForReceipt`)
  - Add 10+ missing Account methods and 7 missing Contract methods
  - Add 20+ missing ErrorCodes (outside execution 6000s, paymaster 7000s categories)
  - Update AbiCodec section — now publicly exported (contradiction resolved by commit 4f3047f), document full public API
  - Add EventPoller persistence API (onCheckpoint, setLastBlockNumber, getCheckpointKey, DataStore config)
  - Add RpcTypes section (~25 export types)
  - (ref: 11-docs.md §api-reference.md)

**Implementation Notes**:
- The 11-docs.md audit is the authoritative reference for specific line-by-line issues, but it was written before KeyStore, OnboardingManager, PresetFactory, FieldFactory, shared/*, and EventPoller persistence were added. Each guide needs additional sections for these.
- The `tonumber(balance.low, 16)` bug in patterns.md and roblox.md may already be fixed by commit faecee7 — verify before editing.
- AbiCodec public/private contradiction is resolved: `contract/init.luau` now exports AbiCodec and PresetFactory alongside Contract, ERC20, ERC721.
- Consider restructuring api-reference.md to mirror the 9-namespace barrel export structure rather than the current ad-hoc ordering.

---

### R.6.4 Update README.md & CLAUDE.md

**Description**: README.md is missing 3+ module trees from the API overview and project structure. CLAUDE.md accurately describes core conventions but is missing the paymaster, shared, and wallet expansion modules from its architecture description.

**Requirements**:
- [ ] **README.md**:
  - Add `errors`, `paymaster`, and `shared` modules to API Overview table
  - Add `src/errors/`, `src/paymaster/`, `src/shared/`, `src/constants.luau` to project structure diagram
  - Expand `wallet` module description to include KeyStore, OnboardingManager, AccountType, AccountFactory, OutsideExecution
  - Expand `provider` module description to include EventPoller, RequestQueue, ResponseCache, NonceManager, JsonRpcClient
  - Expand `contract` module description to include AbiCodec, PresetFactory
  - Add feature highlights: SNIP-9 outside execution, SNIP-12 typed data, SNIP-29 paymaster, deploy account, encrypted key store, player onboarding, event polling with persistence, request queuing/caching
  - Update test count (2,846 tests, 50 spec files)
  - Add quick-start require path note for pesde users (`roblox_packages` vs `Packages` path)
  - Add required Rokit version or tool prerequisites
  - Update version references to 0.2.0 where applicable
- [ ] **CLAUDE.md**:
  - Update Architecture section — add `paymaster`, `shared`, `errors` to the module list
  - Add wallet sub-modules: KeyStore, OnboardingManager, AccountType, AccountFactory, OutsideExecution, TypedData
  - Add provider sub-modules: EventPoller, RequestQueue, ResponseCache, NonceManager, JsonRpcClient
  - Add contract sub-modules: AbiCodec, PresetFactory
  - Remove `rbx-cryptography` from Dependencies section (it's a comment attribution in BigInt.luau, not a dependency)
  - Add `shared` module to Key Patterns section
  - Update test count reference if present

**Implementation Notes**:
- README badge version should match `wally.toml` / `pesde.toml` version.
- CLAUDE.md is loaded into Claude Code context on every session — keep it concise and focused on conventions and key patterns, not exhaustive API docs.
- The project structure diagram in README should match SPEC.md §2.3 after the R.6.1 overhaul.

---

### R.6.5 Add Missing Examples

**Description**: 5 current examples cover basic usage (read-contract, send-transaction, multicall, nft-gate, leaderboard). Production-critical features — paymaster, deploy account, events, error handling, player onboarding, key management — have no example coverage. The SDK now has 9 modules and 57 source files; examples should demonstrate the full breadth of the API.

**Requirements**:
- [ ] Create `sponsored-transaction.luau` — gasless game action using SponsoredExecutor + AvnuPaymaster: configure paymaster, set up policy, execute a sponsored transfer with zero gas cost to the player
- [ ] Create `deploy-account.luau` — create and deploy a new player account on-chain: generate keypair, compute address, fund account, deploy via `Account:deployAccount()`, verify deployment
- [ ] Create `player-onboarding.luau` — full player lifecycle using KeyStore + OnboardingManager: `getOrCreate` on PlayerAdded, `ensureDeployed`, `getStatus` for UI, `removePlayer` on leave
- [ ] Create `event-listener.luau` — poll for on-chain events using EventPoller with DataStore persistence: configure `onCheckpoint`, handle events in callback, demonstrate resume after restart
- [ ] Create `error-handling.luau` — demonstrate StarknetError types, `:is()` checks, ErrorCodes constants, recovery patterns for RPC errors, transaction reverts, and validation failures
- [ ] Create `typed-data.luau` — SNIP-12 TypedData signing: build a typed data structure, `account:hashMessage()`, `account:signMessage()`, verify signature
- [ ] Create `outside-execution.luau` — SNIP-9 Outside Execution: build typed data for meta-transaction, sign off-chain, submit via relayer
- [ ] Create `provider-features.luau` — RequestQueue, ResponseCache, NonceManager configuration: show `enableQueue`/`enableCache`/`enableNonceManager`, demonstrate batching, cache hits, nonce reservation
- [ ] Fix `read-contract.luau`: add missing `:catch()` on metadata calls, add module return, add human-readable balance formatting (divide by 10^18)
- [ ] Polish existing examples:
  - [ ] `leaderboard.luau`: note single contract instance suffices for read+write; add u128 score overflow warning (>2^53)
  - [ ] `multicall.luau`: annotate `feeMultiplier = 1.5` as default or use non-default value
  - [ ] `nft-gate.luau`: add `:expect()` thread-blocking comment; use placeholder address instead of hardcoded
  - [ ] `send-transaction.luau`: annotate `retryInterval = 5` as default; add f64 precision warning for large balances
  - [ ] Cross-cutting: standardize module return pattern across all examples
  - [ ] Cross-cutting: retrofit structured error handling (`:is()`, ErrorCodes) in existing examples
  - [ ] Cross-cutting: add header comment to each example stating Roblox-only runtime requirement

**Implementation Notes**:
- The `tonumber(balance.low, 16)` bug was fixed in commit faecee7 — verify the fix is present in current examples before adding it as a task.
- Each new example should follow the pattern of existing examples: header comment explaining what it demonstrates, `RpcProvider.new()` setup, actual API usage, error handling.
- `player-onboarding.luau` is the highest-value new example — it demonstrates the most common production use case (PlayerAdded → KeyStore → OnboardingManager → Account).
- Examples must use Roblox-compatible patterns (HttpService, DataStoreService injection) but should be clear about which parts need a real Roblox server vs. what can be understood conceptually.

---

### R.6.6 Add Missing Code-Level Documentation

**Description**: Several design decisions, intentional omissions, architectural patterns, and known Luau limitations are undocumented in source code, making the codebase harder to reason about for contributors. The refactoring phases (R1-R5) introduced new patterns (FieldFactory, PresetFactory, `_executePipeline`, shared/interfaces) that also need inline documentation.

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
- [ ] Add class-level doc comment to `Contract.luau` explaining ABI-driven dynamic dispatch, `__index` metamethod, view→call vs external→invoke routing (ref: 07-contract.md §Contract [doc])
- [ ] Document `FieldFactory` pattern — explain why StarkField and StarkScalarField are generated from a shared factory with different moduli (ref: new since R.1.4)
- [ ] Document `PresetFactory` pattern — explain how ERC20/ERC721 use a shared factory to reduce duplication (ref: new since R.1.12)
- [ ] Document `_executePipeline` pattern in TransactionBuilder — explain the shared pipeline abstraction for invoke/deploy flows (ref: new since R.1.9)
- [ ] Document `shared/interfaces.luau` design decision — interface-only types live here, data types stay in owning modules (ref: new since R.2.1)

**Implementation Notes**:
- These are brief inline comments (1-3 lines each), not doc pages. The goal is to make the "why" obvious to someone reading the source for the first time.
- For factory patterns (FieldFactory, PresetFactory), a single comment at the top of the factory module explaining the pattern is sufficient — the consuming modules don't need additional comments.
- The `tx/init.luau` comment fix is trivial: change "V3 INVOKE" to "V3 INVOKE and DEPLOY_ACCOUNT" or similar.

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
