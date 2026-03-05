## 12. Tests

**Suite totals:** 41 spec files, 1926 tests, all passing.

---

### tests/run.luau

- `[ok]` **Automatic recursive discovery** via `discoverTests("tests")`. Walks filesystem with `fs.readDir()`, requires any file matching `%.spec%.luau$`. No hardcoded list — all 41 spec files on disk are picked up.
- `[ok]` Require path construction: `../{path minus .luau suffix}` resolves correctly for Lune's relative require semantics.
- `[fix]` **`toEqual` is identical to `toBe`** (lines 46-55). Both use `~=` (reference equality). No deep-equality comparison exists. Any future test using `expect(table1):toEqual(table2)` will silently pass/fail on reference identity. Currently no test relies on deep equality through `toEqual`, but this is a latent foot-gun.
- `[fix]` **3 paymaster spec files use a hand-rolled harness** (`PaymasterPolicy.spec`, `PaymasterBudget.spec`, `SponsoredExecutor.spec`). These define inline `test()`/`describe()`/`expect()` functions and track their own pass/fail counts. The runner's global `describe`/`it` are never called by these files, so the runner's aggregate accounting **does not capture their results** — they print independently but contribute 0 tests to the runner's totals. Either migrate to the runner's framework or have the runner detect and aggregate custom harness results.
- `[test]` **No `beforeEach`/`afterEach` hooks.** All setup is inline, leading to verbose repeated setup code (especially in provider/wallet/paymaster tests). Not blocking but contributes to boilerplate.
- `[test]` **No test timeouts.** A hanging test (e.g., infinite loop in crypto) blocks the entire run indefinitely.
- `[test]` **No parallel execution.** All 1926 tests run sequentially. Acceptable for now, will scale linearly.

---

### tests/helpers/MockPromise.luau

- `[ok]` Synchronous Promise shim that executes the executor immediately. Well-matched to the dependency-injection pattern used throughout the codebase (all 21 source files that use `andThen` chains resolve synchronously in test mode).
- `[ok]` `Promise.all()` implemented and used by `AccountFactory.batchDeploy`.
- `[fix]` **`expect()` destroys structured error identity.** Lines 98-102: if the rejected value is a table with `.message`, it calls `error(self._value.message)` — converting the structured `StarknetError` into a plain string. Tests that need to inspect rejection errors use `:catch()` or `:getStatus()` to work around this. Diverges from the real evaera/promise library.
- `[test]` **No deferred resolution support.** The `_defer` injection pattern (used in `RequestQueue` and `RpcProvider` tests) works around this with `_defer = function(fn) fn() end`. This is clean dependency injection, not fragile.
- `[test]` No `finally()`, `cancel()`, `race()`, `any()`, `allSettled()` — none used in production code currently.
- `[refactor]` **`SponsoredExecutor.spec.luau` has its own inline 58-line MockPromise** (lines 81-138) instead of importing the shared helper. Creates a divergence risk.

---

### tests/fixtures/test-vectors.luau

- `[ok]` Contains vectors for: BigInt, Poseidon, Pedersen, Keccak (13 selectors), ECDSA (3 pubkeys, 8 sign/verify), TransactionHash (6 V3 INVOKE), Account (3 address derivations), Constants.
- `[ok]` All vectors cite authoritative sources: starknet.js, @scure/starknet, Ethereum Keccak spec, SNIP-8.
- `[test]` **Only `cross-reference.spec.luau` imports from this file.** All other 40 spec files hardcode their own test values inline. The centralized vectors serve as a secondary validation layer, not the single source of truth. This means any change to an authoritative source requires updating in two places.
- `[test]` **Missing centralized vectors for**: SHA-256/HMAC (31 tests use inline NIST vectors), StarkScalarField (54 inline), StarkSigner (21 inline), TypedData/SNIP-12 (43 inline), AbiCodec (109 inline), Deploy Account hash.
- `[test]` **No commit hashes or version tags** on cited sources. Low staleness risk (Stark crypto is mathematically fixed) but no drift detection mechanism.

---

### tests/fixtures/cross-reference.spec.luau

- `[ok]` Covers 9 modules across 17 describe blocks: BigInt, Poseidon, Pedersen, Keccak, ECDSA, TransactionHash (6 V3 INVOKE vectors), Account (OZ v0.11, OZ v0.14, special cases), Constants.
- `[test]` **Gaps — modules NOT cross-referenced:**
  - SHA-256/HMAC — implicitly validated through ECDSA sign vectors, but no explicit cross-reference
  - StarkScalarField — implicitly validated through ECDSA, no explicit cross-reference
  - StarkSigner — wraps ECDSA, implicitly covered
  - **TypedData (SNIP-12) — significant gap.** Two revisions, complex recursive encoding, 43 inline tests but no centralized cross-reference
  - **AbiCodec — complex recursive codec, no cross-reference**
  - **Deploy Account transaction hash — only INVOKE hash is cross-referenced**
  - CallData encoding — no cross-reference vectors for multicall assembly

---

### tests/integration/sepolia.spec.luau

- `[ok]` Two-tier integration suite against the real Starknet Sepolia RPC endpoint.
  - **Tier 1** (no private key): `getChainId`, `getBlockNumber`, `getSpecVersion`, `call` (ETH balanceOf). 4 tests.
  - **Tier 2** (requires `STARKNET_SEPOLIA_PRIVKEY`): address derivation, nonce fetch, fee estimation, full `dryRun` execute. 4 tests. Gracefully handles undeployed/unfunded accounts.
- `[ok]` Hard-gated behind `STARKNET_SEPOLIA_URL` env var — emits a single passing no-op test when absent.
- `[test]` **Not exercised in CI.** `.github/workflows/ci.yml` runs `lune run tests/run` with no env vars injected. No GitHub Actions secrets configured. The entire integration suite runs as a 1-test skip in CI.
- `[test]` **Covers wire-level concerns untestable in unit tests:** HTTP adapter (Lune `net.request` → provider shape mapping), JSON-RPC framing, live chain state, end-to-end signature path with real chain ID.
- `[test]` **Does NOT cover:** transaction submission, deployment, event polling, paymaster calls.

---

### Test specs (per module)

_Review alongside their corresponding source modules above. Note test-specific issues here._

**crypto/ test summary (383 tests across 9 spec files):**

- `[ok]` BigInt.spec.luau (94 tests) — comprehensive, low redundancy, good limb boundary edge cases
- `[ok]` StarkCurve.spec.luau (53 tests) — excellent elliptic curve property coverage
- `[ok]` Keccak.spec.luau (24 tests) — good boundary testing at rate block boundary (135/136/137 bytes)
- `[ok]` SHA256.spec.luau (31 tests) — best-tested hash module, NIST + RFC 4231 vectors, padding edge cases
- `[ok]` ECDSA.spec.luau (37 tests) — 7+ @scure/starknet cross-reference vectors, tamper detection
- `[ok]` Poseidon.spec.luau (22 tests) — cross-referenced with starknet.js vectors
- `[test]` StarkField.spec.luau (51 tests) — medium redundancy. "add is commutative" and "Field Properties: additive identity" test overlapping concepts
- `[test]` **StarkScalarField.spec.luau (54 tests) — HIGH redundancy, 95% duplicate of StarkField tests.** Only 2 unique ECDSA-pattern tests add value. Should extract shared `fieldTestSuite(Field, modulus)` and run against both fields.
- `[test]` Pedersen.spec.luau (17 tests) — thin. Only 5 explicit hash vector tests; 5 tests just verify constant points are on the curve (static data validation, not algorithm coverage). Add more hash vectors.
- `[test]` No integration tests between crypto modules (e.g., "sign with ECDSA → verify → check public key derivation" as a single test). The `cross-reference.spec.luau` covers some of this but is in fixtures/.

---

**signer/ test summary (21 tests, 1 spec file):**

- `[ok]` StarkSigner.spec.luau (21 tests) — full coverage of all 5 public methods (`new`, `getPubKey`, `getPublicKeyHex`, `signRaw`, `signTransaction`). Clean, no mocks needed, no redundancy.
- `[test]` Error path uses `:toThrowType("SigningError")` but does NOT verify specific error codes (`INVALID_PRIVATE_KEY`, `KEY_OUT_OF_RANGE`).

---

**provider/ test summary (378 tests across 7 spec files):**

- `[ok]` RpcProvider.spec.luau (139 tests) — thorough integration test covering 20+ RPC methods, cache integration, queue integration, retry logic, metrics.
- `[ok]` RequestQueue.spec.luau (60 tests) — full coverage of all public methods, clean isolation (each test creates its own instance).
- `[ok]` ResponseCache.spec.luau (60 tests) — excellent LRU cache unit tests with clockFn injection, edge cases (empty key, false value, zero value).
- `[ok]` NonceManager.spec.luau (64 tests) — comprehensive including auto-resync, parallel reservation, Account integration.
- `[ok]` EventPoller.spec.luau (16 tests) — polling lifecycle, event delivery, error resilience, `_sleep` injection for loop control.
- `[test]` RequestBatcher.spec.luau (10 tests) — **phantom module name**: no `src/provider/RequestBatcher.luau` exists. Tests RpcProvider's internal `_drainQueue`/`_dispatchBatch` batch dispatch logic. Well-focused but misleadingly named.
- `[test]` getAllEvents.spec.luau (8 tests) — **phantom module name**: no `src/provider/getAllEvents.luau` exists. Tests `RpcProvider:getAllEvents()` pagination logic. Focused on continuation_token handling.
- `[fix]` **`addDeployAccountTransaction` is untested at the provider level.** `RpcProvider:addDeployAccountTransaction()` has no unit test in any provider spec file. Only indirectly exercised through `Account.deployAccount()` integration tests.
- `[fix]` **Mock infrastructure duplicated across 5 provider spec files** (RpcProvider, NonceManager, EventPoller, getAllEvents, RequestBatcher): ~490 lines of near-identical `mockHandlers`, `createMockHttpRequest()`, `createTestProvider()`, `resetHandlers()`.
- `[test]` Error assertions weak: 11 bare `:toThrow()` calls in RpcProvider.spec, 2 in RequestBatcher.spec, 2 in getAllEvents.spec — none verify structured error type, code, or message. Only EventPoller uses `:toThrowType("ValidationError")`.
- `[test]` RequestQueue error code checked as magic number `2010` instead of `ErrorCodes.QUEUE_FULL.code`.
- `[test]` `estimateMessageFee` priority classification untested in RequestQueue.spec (source maps it as HIGH priority).

---

**tx/ test summary (190 tests across 4 spec files):**

- `[ok]` CallData.spec.luau (41 tests) — full coverage of all 9 public functions. Pure functions, no mocks. starknet.js cross-references in comments.
- `[ok]` TransactionHash.spec.luau (51 tests) — all 5 public functions + 2 constants tested. 6 INVOKE + 6 DEPLOY_ACCOUNT vectors, field sensitivity tests.
- `[ok]` TransactionBuilder.spec.luau (40 tests) — full flow verification for `estimateFee` and `execute`. Hash determinism, dryRun, multicall, fee multiplier.
- `[ok]` DeployAccount.spec.luau (58 tests) — `TransactionBuilder:deployAccount()` + `Account:deployAccount()` + `Account:estimateDeployAccountFee()`. Idempotency check, multi-account-type support.
- `[test]` DeployAccount.spec.luau — **phantom module name**: no `src/tx/DeployAccount.luau` exists. Tests methods on `TransactionBuilder` and `Account`.
- `[fix]` **`toRpcResourceBounds()` silently drops `l1DataGas`** (TransactionBuilder.luau line 132). Only `l1Gas` and `l2Gas` are mapped to snake_case. Custom `l1DataGas` resource bounds are lost. No test catches this because no test checks the submitted RPC payload for `l1_data_gas`.
- `[fix]` **Mock infrastructure duplicated** between TransactionBuilder.spec (~100 lines) and DeployAccount.spec (~130 lines): near-identical `mockHandlers`, `createMockHttpRequest()`, `createTestProvider()`.
- `[test]` **Untested options in `execute()`**: `skipValidate=false`, `tip`, `paymasterData`, `accountDeploymentData`, `nonceDataAvailabilityMode`, `feeDataAvailabilityMode`, `maxFee`.
- `[test]` **Untested options in `deployAccount()`**: `skipValidate=false`, `maxFee` with zero price.
- `[test]` Error assertions weak: all 12 rejection tests across both builder specs check `:getStatus() == "Rejected"` only, never inspect the error type, code, or message.
- `[test]` `SN_SEPOLIA` appears as inline hex 32 times in TransactionHash.spec — worst single-file offender.
- `[test]` No negative/malformed input tests for TransactionHash (nil fields, invalid hex).

---

**wallet/ test summary (411 tests across 6 spec files):**

- `[ok]` Account.spec.luau (137 tests) — largest spec file. Covers `computeAddress` (OZ/Argent/Braavos), `new`, `fromPrivateKey`, `detectAccountType`, `getConstructorCalldata`, constants, paymaster integration (`estimatePaymasterFee`, `executePaymaster`, `deployWithPaymaster`).
- `[ok]` AccountFactory.spec.luau (52 tests) — `AccountType` constants/calldata, `AccountFactory.new` validation, `createAccount` (OZ/Argent/custom).
- `[ok]` BatchDeploy.spec.luau (53 tests) — `batchCreate` validation + key sources, `batchDeploy` (sequential, parallel, error tolerance, progress callbacks, already-deployed detection).
- `[ok]` OutsideExecution.spec.luau (82 tests) — best error testing in the suite, uses `:toThrowCode(6001)` for specific error code checking. Covers V1/V2/V3-RC, validateCalls, buildExecuteFromOutsideCall, typed data integration, signing roundtrip.
- `[ok]` PrefundingHelper.spec.luau (44 tests) — covers `getDeploymentFeeEstimate`, `checkDeploymentBalance`, `getDeploymentFundingInfo`. Properly references `Constants.STRK_TOKEN_ADDRESS`/`ETH_TOKEN_ADDRESS`.
- `[ok]` TypedData.spec.luau (43 tests) — LEGACY + ACTIVE revisions, cross-referenced against starknet.js vectors. encodeType, getTypeHash, getMessageHash, merkle tree, Account integration.
- `[test]` BatchDeploy.spec.luau — **phantom module name**: no `src/wallet/BatchDeploy.luau` exists. Tests `AccountFactory:batchCreate()` and `:batchDeploy()`.
- `[test]` PrefundingHelper.spec.luau — **phantom module name**: no `src/wallet/PrefundingHelper.luau` exists. Tests static methods on `Account`.
- `[fix]` **Mock infrastructure duplicated across 4 wallet spec files** (Account, AccountFactory, BatchDeploy, PrefundingHelper): ~478 lines of near-identical `mockHandlers`, `createMockHttpRequest()`, `createTestProvider()`, test constants.
- `[fix]` **Test constants duplicated across 4 files**: `PRIVKEY_1/2/3`, `PUBKEY_1/2/3`, expected addresses, `SN_SEPOLIA`, `OZ_CLASS_HASH`, `ARGENT_CLASS_HASH`, mock fee responses.
- `[test]` **Gaps in Account.spec**: `Account:deployAccount()` not tested directly (only via BatchDeploy/AccountFactory), `Account:waitForReceipt()` not tested anywhere, `Account:execute()` with NonceManager not tested.
- `[test]` TypedData.spec gaps: `getDependencies()` only indirect, `encodeData()` only indirect, ByteArray boundary cases (exactly 31 chars, 62 chars) untested individually, negative i128 test asserts truthiness only (not the actual two's-complement value), merkle tree only tested with odd leaf count.
- `[test]` BatchDeploy.spec includes 4 `MockPromise.all` tests that test the test infrastructure itself — should be in `tests/helpers/MockPromise.spec.luau`.
- `[test]` OutsideExecution: `INTERFACE_ID_V1`/`V2` exposed constants are untested.
- `[test]` Error assertion inconsistency across files: Account.spec uses `:toThrowType("ValidationError")`, OutsideExecution uses `:toThrowCode(6001)`, PrefundingHelper uses bare `:toThrow()`.

---

**contract/ test summary (292 tests across 5 spec files):**

- `[ok]` AbiCodec.spec.luau (109 tests) — most thorough codec test. Covers all encode/decode paths: primitives, structs, enums, Option, Result, Array, Span, tuple, ByteArray, round-trip, nested types.
- `[ok]` Contract.spec.luau (60 tests) — `new`, `call`, `populate`, `invoke`, `getFunctions`, `getFunction`, `hasFunction`, `__index` dynamic dispatch.
- `[ok]` ERC20.spec.luau (35 tests) — all 12 ERC-20 functions (snake_case + camelCase aliases), populate for multicall.
- `[ok]` ERC721.spec.luau (41 tests) — all 15 ERC-721 functions (snake_case + camelCase), populate for multicall.
- `[ok]` ContractEvents.spec.luau (23 tests) — `parseEvents`, `queryEvents`, `getEvents`, `hasEvent`, address filtering, unknown selectors, legacy event format.
- `[test]` ContractEvents.spec.luau — **phantom module name**: no `src/contract/ContractEvents.luau` exists. Tests event-related methods on `Contract`.
- `[fix]` **Mock infrastructure duplicated across 4 contract spec files** (Contract, ERC20, ERC721, ContractEvents): ~320 lines of near-identical mock code.
- `[fix]` **AbiCodec has ZERO error path tests.** Source has error throws for: invalid Result value, unknown enum variant, non-table enum value, invalid variant index during decode. None are tested.
- `[test]` `Contract:call()` — the optional `blockId` parameter is never tested.
- `[test]` `Contract:parseEvents()` silent failure path untested — when `AbiCodec.decodeEvent` throws inside the `pcall`, the event is silently skipped.
- `[test]` `queryEvents` continuation_token passthrough untested.
- `[test]` Interface ABI parsing (nested `items` for `type="interface"`) not tested in Contract.spec.
- `[test]` `AbiCodec.decodeEvent()` not tested directly — only indirectly through `Contract:parseEvents()`.

---

**paymaster/ test summary (377 tests across 5 spec files):**

- `[ok]` PaymasterRpc.spec.luau (67 tests) — full coverage of all 8 public methods. Strong error path testing covering all SNIP-29 error codes, retry logic.
- `[ok]` AvnuPaymaster.spec.luau (61 tests) — full coverage. Good caching logic tests unique to AVNU layer.
- `[ok]` PaymasterPolicy.spec.luau (66 tests) — excellent validation and rule enforcement testing.
- `[ok]` PaymasterBudget.spec.luau (105 tests) — most tests of any paymaster spec. Good DataStore error handling.
- `[ok]` SponsoredExecutor.spec.luau (78 tests) — excellent error classification (transient vs deterministic), retry exhaustion, budget refund on revert.
- `[fix]` **3 paymaster specs use hand-rolled test harness** (PaymasterPolicy, PaymasterBudget, SponsoredExecutor): ~70 lines of inline `describe`/`test`/`expect` each (~210 lines total). These bypass the runner's `describe`/`it` globals — runner does not capture their pass/fail counts.
- `[fix]` **SponsoredExecutor.spec has its own inline MockPromise** (58 lines) instead of importing `tests/helpers/MockPromise.luau`.
- `[fix]` **PaymasterRpc.spec uses hardcoded error code numbers** (`7002`, `7003`, `7004`, `7005`, `7006`, `7008`, `7000`, `2001`) instead of `ErrorCodes.XXX.code`. SponsoredExecutor.spec correctly uses symbolic references.
- `[fix]` **Mock HTTP infrastructure duplicated** between PaymasterRpc.spec (~150 lines) and AvnuPaymaster.spec (~190 lines).
- `[test]` PaymasterBudget: NaN input for `grantTokens`/`revokeTokens` has source validation but no test.
- `[test]` PaymasterRpc: rate limiter timeout branch never triggered in tests.

---

**errors/ test summary (42 tests, 1 spec file):**

- `[ok]` StarknetError.spec.luau (42 tests) — all factory constructors (`new`, `rpc`, `signing`, `abi`, `validation`, `transaction`), `isStarknetError` (7 tests including edge cases), `:is()` hierarchy (11 tests), `__tostring` (4 tests).
- `[fix]` **Only 19 of 46 ErrorCodes explicitly tested.** Missing:
  - 2000-range: QUEUE_FULL, BATCH_ERROR, CACHE_ERROR, NONCE_FETCH_ERROR, NONCE_EXHAUSTED, NONCE_MANAGER_ERROR
  - 5000-range: INSUFFICIENT_BALANCE, BATCH_DEPLOY_ERROR
  - 6000-range: all 5 outside execution codes (OUTSIDE_EXECUTION_ERROR, INVALID_VERSION, CALL_VALIDATION_FAILED, MISSING_FEE_MODE, INVALID_TIME_BOUNDS)
  - 7000-range: all 13 paymaster codes
- `[test]` ErrorCodes value-verification tests use raw numbers (appropriate since verifying the values themselves).

---

**constants.spec.luau (10 tests):**

- `[ok]` Tests SN_MAIN, SN_SEPOLIA, OZ_ACCOUNT_CLASS_HASH, CONTRACT_ADDRESS_PREFIX, ETH/STRK_TOKEN_ADDRESS, INVOKE/DEPLOY_ACCOUNT/DECLARE_TX_V3.
- `[fix]` **4 constants untested**: `ARGENT_ACCOUNT_CLASS_HASH`, `BRAAVOS_ACCOUNT_CLASS_HASH`, `BRAAVOS_BASE_ACCOUNT_CLASS_HASH`, `ANY_CALLER`. The "Module Completeness" test checks 9 of 13 constants for non-nil.

---

### Cross-cutting test issues

**1. Mock infrastructure duplication (CRITICAL — ~1600+ lines)**

16 spec files independently define `createMockHttpRequest()` + `mockHandlers`:

| Module group | Files | Lines duplicated |
|---|---|---|
| provider/ | RpcProvider, NonceManager, EventPoller, getAllEvents, RequestBatcher | ~490 lines |
| wallet/ | Account, AccountFactory, BatchDeploy, PrefundingHelper | ~478 lines |
| contract/ | Contract, ERC20, ERC721, ContractEvents | ~320 lines |
| paymaster/ | PaymasterRpc, AvnuPaymaster | ~340 lines |
| **Total** | **16 files** | **~1,630 lines** |

**Recommendation:** Extract to `tests/helpers/MockRpc.luau` with a configurable handler registry. Estimated savings: ~1,200 lines (keep ~430 for per-file handler configuration).

**2. Hardcoded SN_SEPOLIA chain ID — 17 spec files, 64 occurrences**

11 files define `local SN_SEPOLIA = "0x534e5f5345504f4c4941"`. 6 files use the raw hex inline (TransactionHash.spec alone has 32 inline occurrences). Zero spec files import `Constants.SN_SEPOLIA` from the source module.

**3. Hardcoded private key — 14 spec files, 22 occurrences**

The key `"0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"` appears under 4 different names (`PRIVKEY_1`, `PRIVKEY`, `TEST_PRIVATE_KEY`, `TEST_PRIVKEY`) across 14 files. All originate from the same @scure/starknet test vector.

**4. Phantom module names — 5 spec files test non-existent source modules**

| Spec file | Actually tests |
|---|---|
| `RequestBatcher.spec.luau` | `RpcProvider` internal batch dispatch |
| `getAllEvents.spec.luau` | `RpcProvider:getAllEvents()` method |
| `ContractEvents.spec.luau` | `Contract` event methods |
| `BatchDeploy.spec.luau` | `AccountFactory:batchCreate/batchDeploy` |
| `PrefundingHelper.spec.luau` | `Account` static prefunding methods |

Not necessarily wrong (organized by feature phase), but creates confusion about what source each test exercises.

**5. No barrel export smoke test**

`src/init.luau` uses Roblox-style `require(script.X)` — cannot run under Lune. No test verifies the barrel export works. The 09-root.md refactor doc already flagged this.

**6. Two incompatible test frameworks in use**

38 spec files use the runner's `describe`/`it`/`expect():toBe()`. 3 paymaster specs use inline hand-rolled `describe`/`test`/`expect().toBe` (dot-call, no colon). The runner does not aggregate results from the hand-rolled harness.

**7. Error assertion quality spectrum**

| Quality level | Pattern | Files using it |
|---|---|---|
| Best | `:toThrowCode(6001)` | OutsideExecution.spec (1 file) |
| Good | `:toThrowType("ValidationError")` | Account, AccountFactory, EventPoller, StarkSigner, Contract (5 files) |
| Weak | `:toThrow()` (bare, no specifics) | RpcProvider, RequestBatcher, getAllEvents, TransactionBuilder, DeployAccount, PrefundingHelper, CallData (7+ files) |
| Absent | No error path tests at all | AbiCodec, TransactionHash, ResponseCache |

**Recommendation:** Standardize on `:toThrowCode()` or `:toThrowType()` for all structured error assertions. Add error path tests to AbiCodec (4 error branches untested) and audit all bare `:toThrow()` calls.

**8. Missing coverage gaps (high priority)**

| Gap | Description |
|---|---|
| `addDeployAccountTransaction` | Not unit-tested at provider level |
| `Account:deployAccount()` | Not directly tested in Account.spec |
| `Account:waitForReceipt()` | Not tested anywhere |
| `Account:execute()` with NonceManager | Not tested |
| `AbiCodec` error paths | 4 `error()` branches, 0 tests |
| `Contract:call()` blockId param | Never exercised |
| `toRpcResourceBounds` drops l1DataGas | No test catches the data loss |
| `skipValidate=false` in execute/deploy | Source handles it, never tested |

**9. Test vector centralization**

`tests/fixtures/test-vectors.luau` exists but is only consumed by `cross-reference.spec.luau`. All 40 other spec files hardcode their own vectors. The project has effectively two test vector strategies: per-file inline vectors for detailed edge cases, and centralized vectors for cross-module validation. This duplication means any authoritative source update requires changes in multiple places.
