## 6. wallet/

### AccountType.luau
_95 lines. Callable account type configurations that carry class hashes and produce constructor calldata._

- `[ok]` Clean callable-table pattern via `__call` metatable — account types are both data carriers (`.type`, `.classHash`) and calldata builders in one.
- `[ok]` Argent calldata uses correct Cairo enum serialization: `Signer::Starknet(pubkey) = [0, pubkey]`, `Option::None = [0]`, `Option::Some(...) = [1, 0, guardian]`.
- `[ok]` `custom()` factory enables user-supplied class hashes for new contract versions.

- `[refactor]` **Class hash constants duplicated across 3 modules.** `AccountType.OZ_CLASS_HASH` (line 22) and `AccountType.ARGENT_CLASS_HASH` (line 25) are identical values to `Constants.OZ_ACCOUNT_CLASS_HASH` and `Constants.ARGENT_ACCOUNT_CLASS_HASH` (constants.luau:21,24), and `Account.OZ_CLASS_HASH` and `Account.ARGENT_CLASS_HASH` (Account.luau:44,47). Three independent sources of truth for the same values. `constants.luau` should be the single source of truth — both AccountType and Account should import from there.

- `[feat]` **Missing Braavos preset.** AccountType defines OZ and Argent but not Braavos. Account.luau supports Braavos (lines 50-53, 67-68, 100-101, 121-122) with both implementation and base class hashes. Users must use `AccountType.custom()` for Braavos, while `Account.fromPrivateKey()` handles it natively. This inconsistency means AccountFactory cannot create Braavos accounts with a preset type.

- `[api]` **`custom()` does not validate required fields.** If `config.buildCalldata` is nil, the error surfaces late at call-time via a confusing metatable error. Add upfront validation:
  ```luau
  if not config.type then error(...) end
  if not config.classHash then error(...) end
  if not config.buildCalldata then error(...) end
  ```

- `[test]` Tested indirectly via AccountFactory.spec.luau and BatchDeploy.spec.luau. No dedicated AccountType.spec.luau.
- `[test]` **No test for `AccountType.custom()` with missing buildCalldata.** Edge case that would produce a confusing runtime error.

---

### Account.luau
_1109 lines. High-level account management: address computation, transaction execution, deployment orchestration, SNIP-12 signing, and paymaster integration._

- `[ok]` `computeAddress()` correctly implements `computeHashOnElements` with Pedersen chain-hash, CONTRACT_ADDRESS_PREFIX, and 251-bit masking — verified against starknet.js test vectors.
- `[ok]` `CLASS_HASH_TO_TYPE` lookup table (lines 57-69) includes historical class hash versions for reliable account type detection.
- `[ok]` `deployAccount()` idempotency check (getNonce success → already deployed) prevents double-deploy safely.
- `[ok]` `signMessage()` correctly chains: hashMessage → BigInt.fromHex → signer.signRaw → hex conversion.
- `[ok]` `fromPrivateKey()` convenience constructor properly derives address via `computeAddress()` using public key and account-type-specific calldata.

- `[refactor]` **CRITICAL — God class (1109 lines, 21+ public methods, 9 dependencies).** Account.luau handles 8 distinct responsibilities:
  1. Address computation (static, ~60 lines)
  2. Account type detection + constructor calldata building (~50 lines)
  3. Account creation / factory constructors (~100 lines)
  4. Transaction execution with NonceManager integration (~55 lines)
  5. Deploy account orchestration with idempotency + waitForConfirmation (~110 lines)
  6. Fee estimation delegates (~30 lines)
  7. SNIP-12 message hashing/signing (~15 lines)
  8. Paymaster integration: deployWithPaymaster + estimatePaymasterFee + executePaymaster (~340 lines)

  The paymaster integration alone is ~340 lines (31% of the file) and could be extracted to a `PaymasterMixin` or `AccountPaymaster.luau` module. The static address computation and type detection could also live in a separate `AddressUtils.luau` or be consolidated with `AccountType.luau`.

- `[refactor]` **Account.luau does not use AccountType.luau at all.** Account has its own parallel class hash constants (lines 44-53), its own `buildConstructorCalldata()` helper (lines 90-102), and its own `getDefaultClassHash()` (lines 118-125) — all duplicating what AccountType already provides. This creates a split:
  - `AccountFactory` delegates to `AccountType` for calldata building ✓
  - `Account.fromPrivateKey()` uses its own internal `buildConstructorCalldata()` ✗
  - If AccountType calldata format changes, Account.luau would not pick it up.

  Account should delegate to AccountType for calldata building and class hash lookup, eliminating the parallel implementation.

- `[refactor]` **`CONTRACT_ADDRESS_PREFIX` duplicated.** Line 26 defines it as a local constant, but `Constants.CONTRACT_ADDRESS_PREFIX` (constants.luau:37) has the same value. Should import from Constants.

- `[refactor]` **`computeHashOnElements()` duplicated in TypedData.luau.** Account.luau lines 77-84 and TypedData.luau `hashPedersen()` lines 83-90 implement the same Pedersen chain-hash algorithm. They differ only in interface (Account uses `Felt` buffers directly; TypedData converts hex strings). Extract to a shared utility, or have TypedData call Account's version with hex→Felt conversion wrappers.

- `[refactor]` **feeMode validation + gasTokenAddress resolution copy-pasted 3 times.** Nearly identical blocks in:
  1. `deployWithPaymaster()` lines 789-821 (18 lines)
  2. `estimatePaymasterFee()` lines 943-966 (24 lines)
  3. `executePaymaster()` lines 1017-1036 (20 lines)

  Total: ~62 lines of repeated validation. Extract to:
  ```luau
  local function validatePaymasterDetails(methodName, paymasterDetails, requireCalls)
      -- validates paymaster, feeMode, gasToken
      -- returns { paymaster, gasTokenAddress, feeMode }
  end
  ```

- `[refactor]` **Call normalization / validation duplicated verbatim.** Lines 854-870 (`deployWithPaymaster`) and lines 1065-1084 (`executePaymaster`) contain identical call-conversion and validateCalls blocks (~16 lines each):
  ```luau
  local rawReturnedCalls = typedData.message.Calls or typedData.message.calls or {}
  local returnedCalls = {}
  for _, rc in rawReturnedCalls do
      table.insert(returnedCalls, { to = rc.To or rc.to or rc.contractAddress, ... })
  end
  local valid = OutsideExecution.validateCalls(submittedOutsideCalls, returnedCalls)
  ```
  Extract to `_validatePaymasterCalls(submittedCalls, typedData)`.

- `[refactor]` **Deploy param building repeated 3 times.** Lines 600-610 (`deployAccount`), lines 686-696 (`estimateDeployAccountFee`), and lines 749-753 (`getDeploymentData`) all build the same table from `self._accountType`, `self._classHash`, `self._constructorCalldata`. Extract to `_buildDeployParams()`.

- `[refactor]` **NonceManager reserve/confirm/reject pattern duplicated.** Lines 528-567 (`execute`) and lines 617-647 (`deployAccount`) duplicate ~30 lines of identical NonceManager integration:
  ```luau
  if nm and not hasExplicitNonce then
      reserve → pcall(execute) → confirm/reject
  end
  ```
  Extract to `_withNonceManager(address, fn)` helper that wraps the reserve/confirm/reject lifecycle.

- `[refactor]` **Idempotency check duplicated.** Lines 586-597 (`deployAccount`) and lines 826-837 (`deployWithPaymaster`) contain identical getNonce-based "already deployed" early-return logic. Extract to a shared `_checkAlreadyDeployed()` helper.

- `[refactor]` **`u256ToBigInt()` (lines 106-114) is a utility trapped in Account.** This is a general-purpose u256 conversion that could be useful in AbiCodec, Contract, or ERC20 modules. It should live in a shared utility or `BigInt.fromU256()`.

- `[type]` **Pervasive `any` typing defeats type safety.** Every public method returns `any`. All constructor config params are `any`. `self._provider`, `self._signer`, `self._builder` are untyped. While partly a Luau limitation (metatable classes + generic Promise), it eliminates compile-time safety. At minimum, define an `Account` export type with the public method signatures.

- `[type]` **`CLASS_HASH_TO_TYPE` keys are manually normalized.** Lines 59-68 use lowercase hex without leading zeros (matching `BigInt.toHex` output), but this is an implicit contract. If `BigInt.toHex` output format ever changes, detection breaks silently. Add a comment or a normalization assertion.

- `[api]` **`Account:getPublicKeyHex()` (line 726) is a trivial pass-through.** It calls `self.signer:getPublicKeyHex()` — zero added value. Consumer could access `account.signer:getPublicKeyHex()` directly. However, it provides a cleaner public API that doesn't expose the signer. Keep but document as a convenience delegation.

- `[api]` **`Account:waitForReceipt()` (line 721) is a 3-layer delegation chain.** `Account → TransactionBuilder.waitForReceipt → Provider.waitForTransaction`. The TransactionBuilder middle layer adds nothing. Consider having Account delegate directly to provider.

- `[api]` **Inconsistent Promise module access.** Account.luau uses `self._provider:_getPromise()` (private method call). AccountFactory.luau uses `self._provider._PromiseModule` (private field access). Same intent, different access patterns. See [cross-cutting](./14-cross-cutting.md) for the broader issue.

- `[api]` **`error(StarknetError.new(..., "PaymasterError"))` used for paymaster errors.** Lines 874 and 1077 use `StarknetError.new()` with a string type hint instead of a dedicated `StarknetError.paymaster()` factory. Inconsistent with the error hierarchy pattern (see [errors/ section](./02-errors.md)).

- `[test]` 137 tests in Account.spec.luau — comprehensive coverage of static methods, instance methods, and paymaster integration.
- `[test]` **No dedicated tests for NonceManager integration in `Account:execute()` or `Account:deployAccount()`.** The reserve/confirm/reject path is not exercised from the Account level (NonceManager tests are in provider/NonceManager.spec.luau).
- `[test]` **No multicall tests for `Account:execute()`.** All execute tests pass a single Call. No test verifies 2+ calls encoding through the Account interface.
- `[test]` **Address computation verified redundantly across 4 test files.** The same 3 private-key-to-address mappings are verified in Account.spec, AccountFactory.spec, BatchDeploy.spec, and cross-reference.spec (~10+ duplicate assertions). Verify once in Account.spec, trust upstream in others.

---

### AccountFactory.luau
_429 lines. Factory for creating and batch-deploying Starknet accounts. Encapsulates provider + account type + signer._

- `[ok]` `new()` has thorough constructor validation: checks provider, accountType fields, signer presence.
- `[ok]` `batchCreate()` validates: count type, positivity, integer-ness, max batch size, mutually exclusive key sources, key count matching.
- `[ok]` `_createAccountFromSigner()` cleanly delegates to AccountType's callable interface for calldata building, then to `Account.computeAddress()` and `Account.new()`.
- `[ok]` `batchDeploy()` parallel path uses `.catch()` → resolve pattern (line 413-414) to prevent `Promise.all` from aborting on single failure — correct for batch error tolerance.

- `[refactor]` **Parallel deploy path duplicates sequential deploy result-building logic.** The sequential `deployOne()` (lines 315-358) builds result entries with status="skipped"/"deployed"/"failed", updates summary counts, and calls progressCallback. The parallel path (lines 376-415) duplicates all of this inside `andThen`/`catch` handlers — ~40 lines of identical branching logic. Extract the result-building into a shared `buildDeployResult(index, address, deployResult, err?)` helper.

- `[refactor]` **`_PromiseModule` accessed inconsistently.** Line 287 accesses `self._provider._PromiseModule` directly (private field), while Account.luau uses `self._provider:_getPromise()` (private method). Both bypass encapsulation but through different paths. Should use the same access pattern (ideally a public one).

- `[refactor]` **`_createAccountFromSigner` has Argent-specific branching.** Lines 81-85 check `self._accountType.type == "argent"` to pass `guardian` as second arg. But AccountType's `__call` metatable already handles this — passing `nil` as the second arg to a non-Argent type is harmless since it's ignored. Could simplify to always pass both args: `calldata = self._accountType(publicKey, opts.guardian)`.

- `[type]` **All `any` types.** `provider: any`, `accountType: any`, `signer: any`, return type `any`. Same pervasive typing issue as Account.luau.

- `[api]` **`batchDeploy` parallel batch completion is synchronous.** Line 420: `Promise.all(batchPromises):expect()` blocks inside a `Promise.new()` callback. This works but is the same sync-in-async anti-pattern noted in TransactionBuilder — converting Promises to sync (`:expect()`) inside `Promise.new()`. In Roblox runtime with real async, this could cause issues.

- `[test]` 52 tests in AccountFactory.spec.luau + 53 tests in BatchDeploy.spec.luau = 105 tests total.
- `[test]` **Mock setup duplicated across 4 test files.** `createMockHttpRequest()` (~55 lines), `createTestProvider()`, `resetHandlers()`, and test constants (`PRIVKEY_1/2/3`, `PUBKEY_1/2/3`, `SN_SEPOLIA`) are copy-pasted identically in Account.spec, AccountFactory.spec, PrefundingHelper.spec, and BatchDeploy.spec. ~400-500 lines of duplication. Extract to `tests/helpers/MockRpc.luau`.
- `[test]` **No Braavos account type test in any factory test.** Only OZ and Argent are tested.

---

### TypedData.luau
_706 lines. SNIP-12 typed data encoding and hashing for structured message signing. Supports LEGACY (revision "0", Pedersen) and ACTIVE (revision "1", Poseidon)._

- `[ok]` Clean revision polymorphism: `getHashMethod()` and `getMerkleHashMethod()` abstract hash function selection by revision.
- `[ok]` Comprehensive type encoding: handles structs, enums, arrays, tuples, merkle trees, ByteArray, presets (u256, TokenAmount, NftId), i128 negatives, selectors.
- `[ok]` Merkle tree implementation correctly sorts pairs ascending before hashing, pads odd leaves with 0x0.
- `[ok]` Forward-declared functions (`encodeValue`, `encodeData`, `getStructHash`) handle mutual recursion correctly per Luau pattern.
- `[ok]` Preset types (ACTIVE only) correctly merged into type map for encoding.

- `[refactor]` **`computeHashOnElements` reimplemented.** `hashPedersen()` (lines 83-90) is functionally identical to `computeHashOnElements()` in Account.luau (lines 77-84). Both chain Pedersen hashes then hash with length. Differs only in hex string intermediary vs direct Felt buffers. Should be a single shared utility.

- `[refactor]` **`encodeShortString()` duplicated from CallData.** Lines 45-54 duplicate `tx/CallData.luau:57-74` minus the validation guards (no >31 length check, no non-ASCII check). This means TypedData **silently accepts invalid short strings**. TypedData should import CallData.encodeShortString and index `[1]` for the bare string variant (CallData returns `{ string }`). See [tx/ section](./05-tx.md).

- `[refactor]` **Stark prime P hard-coded.** Line 25: `local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")`. This is the same value as `StarkField.P` (StarkField.luau:16). Should import from StarkField to avoid divergence. See [cross-cutting](./14-cross-cutting.md).

- `[refactor]` **`encodeValue` is a 163-line monolithic function (lines 474-637).** Handles 15+ type dispatches in a single if/elseif chain. Could be refactored into a dispatch table pattern:
  ```luau
  local encoders = {
      felt = encodeFelt,
      bool = encodeBool,
      u256 = encodeU256,
      -- ...
  }
  ```
  This would improve readability and make adding new types trivial.

- `[perf]` **`tableContains()` is O(n) and used in dependency loops.** `getDependencies()` (lines 326, 341) calls `tableContains()` inside nested loops for cycle detection. For deeply nested type graphs this is O(n²). Replace with a hash-set for O(1) lookup:
  ```luau
  local seen = {} -- [typeName] = true
  ```

- `[perf]` **`merkleRoot()` creates new arrays on every recursive call.** Lines 212-230 allocate a new `next` table per recursion level. For large Merkle trees (e.g., allowlists), this creates O(n log n) temporary allocations. Consider in-place pairing.

- `[test]` 43 tests in TypedData.spec.luau — thorough cross-reference with starknet.js SNIP-12 vectors.
- `[test]` **No test for merkle tree with ACTIVE revision.** Only LEGACY Merkle trees are tested.
- `[test]` **No test for deeply nested struct types** (beyond 2 levels).
- `[test]` **Account integration tests (lines 614-712) create a separate mock setup** instead of using a shared test infrastructure. This is isolated but inconsistent with the rest of the test suite.

---

### OutsideExecution.luau
_489 lines. SNIP-9 outside execution: builds typed data for V1/V2/V3, validates returned calls, and constructs on-chain Call objects._

- `[ok]` Version-specific type tables (`TYPES_V1`, `TYPES_V2`, `TYPES_V3`) cleanly separated and exposed for testing.
- `[ok]` `validateCalls()` is security-critical and handles edge cases: extra trailing call (paymaster fee transfer), empty calldata, hex normalization.
- `[ok]` `getOutsideCall()` correctly computes selector via `Keccak.getSelectorFromName()` when entrypoint is a name rather than a pre-computed hash.
- `[ok]` Constants (`ANY_CALLER`, `INTERFACE_ID_V1/V2`) properly imported from/aligned with `constants.luau`.

- `[refactor]` **Call conversion duplicated 3 times in `getTypedData()`.** Lines 222-231 (V1), 254-259 (V2), and 292-299 (V3) all iterate `outsideCalls` and build version-specific call tables. V2 and V3 blocks produce identical `{To, Selector, Calldata}` — could be shared. V1 uses `{to, selector, calldata_len, calldata}` (different format) but the iteration is still duplicable. Extract:
  ```luau
  local function formatCallsForVersion(outsideCalls, version)
  ```

- `[refactor]` **`normalizeHex()` duplicated.** Lines 134-136 implement `BigInt.toHex(BigInt.fromHex(hex))`, identical to `tx/CallData.luau:36-38`. See [tx/ section](./05-tx.md) and [cross-cutting](./14-cross-cutting.md) for the 3-way normalizeHex duplication.

- `[refactor]` **`buildExecuteFromOutsideCall()` is fragile with dual-key inspection.** Lines 415-478 manually check both camelCase and PascalCase keys (`caller`/`Caller`, `nonce`/`Nonce`, `execute_after`/`Execute After`/`executeAfter`). This is a symptom of un-normalized data flowing from `getTypedData()`. If `getTypedData()` always returned a canonical shape, this function wouldn't need the dual-key fallbacks.

- `[perf]` **`validateCalls()` normalizes every hex on every comparison.** `normalizeHex()` (which round-trips through BigInt) is called for every field of every call, including calldata arrays. For large calldata this is expensive. Consider normalizing once at input boundary rather than on every comparison.

- `[api]` **`getTypedData()` has 6 parameters.** Signature: `(chainId, options, nonce, calls, version, feeMode?)`. This is a wide parameter list. Consider using a single config table:
  ```luau
  getTypedData({ chainId, options, nonce, calls, version, feeMode? })
  ```

- `[test]` 82 tests in OutsideExecution.spec.luau — comprehensive coverage of V1/V2/V3 type building, call validation, and signing roundtrips.
- `[test]` **No V3 PayFee signing roundtrip test.** Only V3 NoFee has a signing roundtrip (line 824). V3 PayFee calldata encoding is tested (lines 626-659) but without the full sign-verify cycle.

---

### wallet/init.luau (barrel)
_17 lines. Re-exports Account, TypedData, AccountType, AccountFactory, OutsideExecution._

- `[ok]` Clean barrel, no logic.
- `[ok]` Uses Roblox-style `require(script.X)` — correct for runtime barrel per project convention.
- `[ok]` All 5 wallet sub-modules are exported.

---

### wallet/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 2,845 (95 + 1,109 + 429 + 706 + 489 + 17) |
| **Total public functions** | 38 (AccountType: 3, Account: 21, AccountFactory: 4, TypedData: 10, OutsideExecution: 5) |
| **Total tests** | 421 (Account: 137, AccountFactory: 52, BatchDeploy: 53, PrefundingHelper: 44, TypedData: 43, OutsideExecution: 82, integration: 10) |
| **DRY violations** | 12 significant (see below) |
| **God class** | 1 (Account.luau — 1,109 lines, 9 deps, 8 responsibilities) |
| **Type issues** | 2 (pervasive `any`, no Account export type) |
| **Missing features** | 1 (Braavos preset in AccountType) |

### Intra-Module DRY Violations

| # | Violation | Lines Wasted | Location |
|---|-----------|-------------|----------|
| 1 | Class hash constants defined in Account + AccountType (both duplicate constants.luau) | ~16 | Account.luau:44-53 + AccountType.luau:22-25 |
| 2 | `buildConstructorCalldata()` duplicated in Account vs AccountType.__call | ~14 | Account.luau:90-102 vs AccountType.luau:37-62 |
| 3 | `getDefaultClassHash()` reimplements AccountType config | ~8 | Account.luau:118-125 |
| 4 | feeMode validation + gasTokenAddress resolution ×3 | ~62 | Account.luau:789-821, 943-966, 1017-1036 |
| 5 | Call normalization + validateCalls ×2 | ~32 | Account.luau:854-870, 1065-1084 |
| 6 | Deploy param building ×3 | ~24 | Account.luau:600-610, 686-696, 749-753 |
| 7 | NonceManager reserve/confirm/reject ×2 | ~30 | Account.luau:528-567, 617-647 |
| 8 | Idempotency check (getNonce → alreadyDeployed) ×2 | ~12 | Account.luau:586-597, 826-837 |
| 9 | Call conversion in getTypedData ×3 (V2=V3) | ~12 | OutsideExecution.luau:222-231, 254-259, 292-299 |
| 10 | batchDeploy sequential/parallel result-building | ~40 | AccountFactory.luau:315-358 vs 376-415 |

### Cross-Module DRY Violations (wallet/ ↔ other modules)

| # | Violation | Files Affected |
|---|-----------|----------------|
| 1 | `computeHashOnElements` / `hashPedersen` — same Pedersen chain-hash | `Account.luau:77-84` ↔ `TypedData.luau:83-90` |
| 2 | `encodeShortString()` duplicated (TypedData lacks validation) | `TypedData.luau:45-54` ↔ `tx/CallData.luau:57-74` |
| 3 | `normalizeHex()` duplicated 3× | `OutsideExecution.luau:134-136` ↔ `tx/CallData.luau:36-38` ↔ `paymaster/PaymasterPolicy.luau:36-45` |
| 4 | Stark prime P hard-coded | `TypedData.luau:25` ↔ `StarkField.luau:16` |
| 5 | `CONTRACT_ADDRESS_PREFIX` duplicated | `Account.luau:26` ↔ `constants.luau:37` |

### Test Infrastructure Duplication

| # | Duplication | Files Affected | Lines Wasted |
|---|------------|----------------|-------------|
| 1 | `createMockHttpRequest()` identical across 4 files | Account.spec, AccountFactory.spec, PrefundingHelper.spec, BatchDeploy.spec | ~220 |
| 2 | `createTestProvider()` identical across 4 files | Same as above | ~40 |
| 3 | `resetHandlers()` near-identical across 4 files | Same as above | ~80 |
| 4 | Test constants (PRIVKEY_1/2/3, PUBKEY_1/2/3, SN_SEPOLIA) across 4 files | Same as above | ~60 |
| 5 | Address computation assertions repeated across 4 test files | Account.spec, AccountFactory.spec, BatchDeploy.spec, cross-reference.spec | ~50 |
| **Total** | | | **~450** |

---

### Priority Actions (wallet/)

1. **HIGH — Consolidate class hash constants to single source of truth.** Remove `Account.OZ_CLASS_HASH` / `ARGENT_CLASS_HASH` / `BRAAVOS_CLASS_HASH` / `BRAAVOS_BASE_CLASS_HASH` (Account.luau:44-53) and `AccountType.OZ_CLASS_HASH` / `ARGENT_CLASS_HASH` (AccountType.luau:22-25). Both modules should import from `constants.luau`. Eliminates 3-way duplication — if a class hash changes, only `constants.luau` needs updating.

2. **HIGH — Make Account.luau delegate to AccountType for calldata building.** Remove `buildConstructorCalldata()` and `getDefaultClassHash()` from Account.luau. `Account.fromPrivateKey()` and the deploy helpers should use AccountType presets (importing AccountType.luau). This removes ~25 lines and eliminates the disconnected parallel implementation.

3. **HIGH — Extract shared paymaster validation helpers in Account.luau.** Create `_validatePaymasterDetails(methodName, details)` returning `{ paymaster, gasTokenAddress }`, and `_validatePaymasterCalls(submittedCalls, typedData)` returning validated call list. Eliminates ~94 lines of copy-pasted validation across 3 methods.

4. **HIGH — Extract `_buildDeployParams()` helper in Account.luau.** Replace the 3 identical deploy param table constructions (deployAccount, estimateDeployAccountFee, getDeploymentData) with a single internal method. Saves ~18 lines and ensures param format consistency.

5. **HIGH — Extract `_withNonceManager(address, fn)` wrapper in Account.luau.** Replace the duplicated reserve/confirm/reject pattern in execute() and deployAccount() with a single higher-order function. Saves ~30 lines and prevents the NonceManager lifecycle from diverging between the two paths.

6. **HIGH — Extract test mock infrastructure to `tests/helpers/MockRpc.luau`.** Move `createMockHttpRequest()`, `createTestProvider()`, `resetHandlers()`, and shared test constants to a single helper module. Import in Account.spec, AccountFactory.spec, PrefundingHelper.spec, BatchDeploy.spec. Eliminates ~400-450 lines of identical test setup code.

7. **MEDIUM — Add Braavos preset to AccountType.luau.** Add `AccountType.BRAAVOS_CLASS_HASH` and `AccountType.Braavos` callable type (using Braavos base class hash, same calldata format as OZ: `[publicKey]`). This makes AccountFactory parity with Account.fromPrivateKey for all three major account types.

8. **MEDIUM — Extract paymaster integration from Account.luau.** Move `deployWithPaymaster()`, `estimatePaymasterFee()`, and `executePaymaster()` (~340 lines) to a separate `AccountPaymaster.luau` module or mixin pattern. Account.luau methods become thin delegates:
   ```luau
   function Account:executePaymaster(calls, details)
       return AccountPaymaster.execute(self, calls, details)
   end
   ```
   This brings Account.luau from 1109 lines to ~770 lines and isolates the paymaster concern.

9. **MEDIUM — Extract `computeHashOnElements` to a shared utility.** Used by Account.luau and TypedData.luau. Move to `crypto/Pedersen.luau` as `Pedersen.hashMany()` or to a new `src/utils/hash.luau`. Both consumers then import from one place.

10. **MEDIUM — Consolidate `normalizeHex()` across modules.** Add `BigInt.normalizeHex(hex)` (one-liner: `toHex(fromHex(hex))`) and have OutsideExecution, CallData, and PaymasterPolicy import it. See [tx/ section](./05-tx.md) and [cross-cutting](./14-cross-cutting.md).

11. **MEDIUM — Have TypedData import `encodeShortString` from CallData.** Eliminates duplicate and gains the >31 length / non-ASCII validation guards that TypedData currently lacks. TypedData currently silently accepts invalid short strings — this is a latent correctness issue.

12. **MEDIUM — Have TypedData import Stark prime P from StarkField.** Replace hardcoded `BigInt.fromHex("0x800000000000011...")` with `StarkField.P` or equivalent. See [cross-cutting](./14-cross-cutting.md).

13. **MEDIUM — Fix `normalizeHex()` in OutsideExecution's `buildExecuteFromOutsideCall()`.** The dual-key inspection (camelCase/PascalCase) is a symptom of un-normalized data. Normalize the outside execution data shape at `getTypedData()` output boundary, so `buildExecuteFromOutsideCall()` can trust a single canonical key format.

14. **MEDIUM — Add validation to `AccountType.custom()`.** Check that `config.type`, `config.classHash`, and `config.buildCalldata` are present and the right types before constructing the metatable.

15. **LOW — Replace `tableContains()` with hash-set in TypedData.getDependencies().** Replace the O(n) linear scan with `seen[name] = true` for O(1) cycle detection in type dependency resolution.

16. **LOW — Add missing test coverage:**
    - NonceManager integration in Account:execute() and deployAccount()
    - Multicall (2+ calls) through Account:execute()
    - Braavos account type in factory/prefunding tests
    - V3 PayFee signing roundtrip in OutsideExecution
    - Merkle tree with ACTIVE revision in TypedData
    - `AccountType.custom()` with missing fields

17. **LOW — Reduce redundant address computation tests.** The same 3 private-key-to-address vectors are verified in 4+ test files. Verify once in Account.spec.luau, trust the upstream computation in higher-level tests. Higher-level tests should focus on their own responsibilities (factory creation, batch deploy, etc.), not re-proving Pedersen correctness.

18. **LOW — Standardize Promise module access pattern.** Account uses `provider:_getPromise()`, AccountFactory uses `provider._PromiseModule`. Align on a single public method (`provider:getPromise()` or similar). See [cross-cutting](./14-cross-cutting.md).

---

### Architectural Flow: Account Module Interactions

```
┌────────────────────┐
│   AccountFactory    │──uses──▶ AccountType (callable table)
│   (batch ops)       │──creates──▶ Account.new()
└────────┬───────────┘           Account.computeAddress()
         │
         │ delegates deploy to
         ▼
┌────────────────────┐
│     Account         │──uses──▶ TransactionBuilder (execute, deploy)
│  (god class)        │──uses──▶ StarkSigner (signing)
│                     │──uses──▶ TypedData (SNIP-12 hash/sign)
│                     │──uses──▶ OutsideExecution (paymaster calls)
│                     │──uses──▶ ERC20 (balance checks)
│                     │──uses──▶ Pedersen (address computation)
│                     │──uses──▶ Constants (duplicated locally)
│                     │──accesses──▶ provider._nonceManager (private)
│                     │──accesses──▶ provider:_getPromise() (private)
└────────────────────┘

┌────────────────────┐
│   TypedData         │──uses──▶ Pedersen (LEGACY hash)
│   (SNIP-12)         │──uses──▶ Poseidon (ACTIVE hash)
│                     │──uses──▶ Keccak (type hash)
│                     │──duplicates──▶ encodeShortString (from CallData)
│                     │──duplicates──▶ Stark prime P (from StarkField)
└────────────────────┘

┌────────────────────┐
│ OutsideExecution    │──uses──▶ Keccak (selector computation)
│   (SNIP-9)          │──uses──▶ BigInt (hex normalization)
│                     │──duplicates──▶ normalizeHex (from CallData)
└────────────────────┘

┌────────────────────┐
│   AccountType       │──duplicates──▶ class hashes (from constants.luau)
│   (config)          │  (standalone — no imports)
└────────────────────┘
```

### Recommended Extraction Plan

Phase 1 — DRY elimination (no API changes):
1. Class hashes → import from `constants.luau` in both Account + AccountType
2. Account delegates to AccountType for calldata building
3. Extract `_validatePaymasterDetails()`, `_validatePaymasterCalls()`, `_buildDeployParams()`, `_withNonceManager()`, `_checkAlreadyDeployed()` as internal helpers in Account.luau
4. Extract test mock infrastructure to `tests/helpers/MockRpc.luau`

Phase 2 — Cross-module consolidation:
5. `normalizeHex()` → `BigInt.normalizeHex()` or `src/utils/hex.luau`
6. `encodeShortString()` → TypedData imports from CallData
7. `computeHashOnElements()` → `Pedersen.hashMany()` or shared utility
8. Stark prime P → TypedData imports from StarkField

Phase 3 — Structural extraction (API-preserving):
9. Paymaster methods → `AccountPaymaster.luau` (Account.luau delegates)
10. Add Braavos preset to AccountType
11. Type annotations for Account, AccountFactory export types
