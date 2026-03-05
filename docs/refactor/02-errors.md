## 2. errors/

### ErrorCodes.luau
_73 lines. Flat table of `{code, name}` constants segmented by numeric range._

- `[ok]` Clean, well-organized by category with clear range boundaries (1000s=validation, 2000s=RPC, 3000s=signing, 4000s=ABI, 5000s=tx, 6000s=outside execution, 7000s=paymaster).
- `[ok]` Consistent structure: every entry is `{ code = N, name = "NAME" }`.
- `[refactor]` **`name` field duplicates the table key.** Every entry repeats itself: `ErrorCodes.INVALID_ARGUMENT = { code = 1000, name = "INVALID_ARGUMENT" }`. The `name` is useful at runtime when you only have the code object (e.g., logging), so this is a deliberate tradeoff — but it's a correctness risk if key and name ever diverge. Consider generating `name` from the key at definition time, or document that `name` must always match the key.
- `[refactor]` **Code 3002 is skipped** in the signing range (3001 → 3003). Minor numbering gap, not a bug, but should be documented or filled.
- `[refactor]` **`TRANSACTION_REVERTED` (2004) and `TRANSACTION_REJECTED` (2005) are in the 2000 RPC range** but are semantically transaction lifecycle errors. They're used with `StarknetError.transaction()` in `RpcProvider.luau`, creating a mismatch between numeric category and error subtype. Consider moving to 5000 range or document the crossover.
- `[api]` **Dead codes — defined but never used anywhere in `src/`:**
  - `OUT_OF_RANGE` (1002) — zero references. The similar `KEY_OUT_OF_RANGE` (3003) is used instead.
  - `INSUFFICIENT_BALANCE` (5002) — zero references.
  - `CACHE_ERROR` (2012) — zero references in source (only defined).
  - `OUTSIDE_EXECUTION_ERROR` (6000) — zero references; specific codes like `INVALID_VERSION` (6001) are used instead.
  - `PAYMASTER_ERROR` (7000) — zero references; specific codes like `PAYMASTER_UNAVAILABLE` (7001) are used instead.
- `[test]` **20+ error codes untested.** The test file only covers 1000-5001 ranges. Missing test assertions for:
  - 2010-2015 range (QUEUE_FULL, BATCH_ERROR, CACHE_ERROR, NONCE_FETCH_ERROR, NONCE_EXHAUSTED, NONCE_MANAGER_ERROR)
  - 5002-5003 (INSUFFICIENT_BALANCE, BATCH_DEPLOY_ERROR)
  - Entire 6000 range (5 Outside Execution codes)
  - Entire 7000 range (15 Paymaster codes)
- `[test]` **No uniqueness assertion.** No test verifies all codes are unique (no two entries share the same numeric code). A duplicate code number would silently cause error misidentification.

### StarknetError.luau
_181 lines. Factory constructors, shared ErrorProto metatable, type hierarchy, duck-type checker._

- `[ok]` Flat factory-function pattern (no subclass constructors or metatable chains) is an excellent fit for Luau.
- `[ok]` `error(table)` pattern preserving table identity through `pcall` is well-exploited and correctly tested.
- `[ok]` `__tostring` metamethod produces clean formatted output with conditional code display.
- `[ok]` Separation of concerns: `ErrorCodes` (static data) vs `StarknetError` (behavior) is clean.
- `[refactor]` **DRY violation in factory constructors.** Six factories (`new`, `rpc`, `signing`, `abi`, `validation`, `transaction`) repeat identical `setmetatable({...}, ErrorProto)` boilerplate. Four of six (`new`, `signing`, `abi` — and the core of `rpc` minus `rpcCode`) are byte-for-byte identical except for the `_type` string. Extract a shared internal helper:
  ```luau
  local function createError(errorType: string, fields: {[string]: any}): any
      fields._type = errorType
      return setmetatable(fields, ErrorProto)
  end
  ```
  Each factory becomes a thin wrapper that names its specific extra fields. Saves ~50 lines, eliminates risk of inconsistency when adding new error types.
- `[refactor]` **`:is()` grandparent traversal is over-engineered for current hierarchy, under-engineered for deeper ones.** The hierarchy is exactly one level deep (every subtype → `{"StarknetError"}`). The `:is()` method hardcodes a two-level walk (parents + grandparents) that would silently fail on three or more levels. If deeper hierarchies are intended, use a recursive/loop approach. If not, simplify to a single-level check:
  ```luau
  -- Current hierarchy is flat — simplify
  function ErrorProto:is(errorType: string): boolean
      if self._type == errorType then return true end
      local parents = TYPE_HIERARCHY[self._type]
      if parents then
          for _, p in parents do
              if p == errorType then return true end
          end
      end
      return false
  end
  ```
- `[api]` **`:is()` is never called in production code.** Every consumer uses `result._type == "RpcError"` (raw field check) instead of `result:is("RpcError")`. This makes `TYPE_HIERARCHY` and the entire `:is()` method effectively dead code in production. The hierarchy traversal logic has zero production callers. Either: (a) use `:is()` in production code to justify its existence, or (b) document it as a consumer-facing API and dogfood it internally.
- `[api]` **`isStarknetError()` is never used in production code.** Only appears in tests. The `SponsoredExecutor.isTransientError()` does its own `type(err) ~= "table"` guard instead of using `isStarknetError()`. Same concern: either dogfood it internally or accept it's consumer-only.
- `[api]` **Missing `PaymasterError` subtype.** The 7000-range has 15 error codes across 4+ source files (`PaymasterRpc`, `AvnuPaymaster`, `PaymasterBudget`, `SponsoredExecutor`), but no factory function or hierarchy entry. Paymaster errors are thrown as `StarknetError.new()` (untyped base), `StarknetError.rpc()`, or `StarknetError.validation()` — making programmatic discrimination harder. Recommend adding `StarknetError.paymaster()` factory and `PaymasterError` hierarchy entry.
- `[api]` **`StarknetError.new()` used as catch-all for 7 errors that should use specific subtypes:**

  | File | Line | ErrorCode | Current | Suggested |
  |------|------|-----------|---------|-----------|
  | `crypto/Pedersen.luau` | 125 | `MATH_ERROR` | `StarknetError.new()` | `validation()` (consistent with BigInt/StarkField) |
  | `wallet/Account.luau` | 872 | `PAYMASTER_CALL_VALIDATION_FAILED` | `StarknetError.new()` | `validation()` or `paymaster()` |
  | `wallet/Account.luau` | 1077 | `PAYMASTER_CALL_VALIDATION_FAILED` | `StarknetError.new()` | `validation()` or `paymaster()` |
  | `paymaster/PaymasterBudget.luau` | 341 | `INSUFFICIENT_BUDGET` | `StarknetError.new()` | `validation()` or `paymaster()` |
  | `paymaster/SponsoredExecutor.luau` | 298 | `PAYMASTER_POLICY_REJECTED` | `StarknetError.new()` | `validation()` or `paymaster()` |
  | `paymaster/SponsoredExecutor.luau` | 327 | `INSUFFICIENT_BUDGET` | `StarknetError.new()` | `validation()` or `paymaster()` |
  | `paymaster/SponsoredExecutor.luau` | 477 | `SPONSORED_EXECUTION_FAILED` | `StarknetError.new()` | `transaction()` |

- `[type]` **All factories return `any`.** Erases type information in `--!strict` mode. Callers get no autocomplete on `.message`, `.code`, `.data`, etc. Could define:
  ```luau
  export type StarknetErrorInstance = {
      _type: string,
      message: string,
      code: number?,
      data: any?,
      is: (self: StarknetErrorInstance, errorType: string) -> boolean,
  }
  ```
  Pragmatic limitation: Luau's type system has issues with `setmetatable` return types, so this may need to stay `any` for now.
- `[type]` **`data: any?` is too loose.** Usage patterns show it's always a table when present, but no runtime validation is performed.
- `[test]` **Test gaps:**
  - No test for `tostring` of `ValidationError`, `AbiError`, `TransactionError` subtypes (only `StarknetError`, `RpcError`, `SigningError` are tested).
  - No negative test for `isStarknetError` with a table that has `_type` and `message` but no `is` function.
  - No test for `:is()` with a manually-constructed object whose `_type` is not in `TYPE_HIERARCHY`.
  - No test for ErrorCodes mutual uniqueness (no duplicate code numbers).

### errors/init.luau (barrel)
_10 lines. Re-exports StarknetError and ErrorCodes._

- `[ok]` Clean barrel, no logic.
- `[ok]` Uses Roblox-style `require(script.X)` — correct for runtime barrel.

---

### errors/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 264 (73 + 181 + 10) |
| **Total public functions** | 8 (6 factories + `isStarknetError` + `:is`) |
| **Total error codes defined** | 38 |
| **Dead error codes** | 5 (OUT_OF_RANGE, INSUFFICIENT_BALANCE, CACHE_ERROR, OUTSIDE_EXECUTION_ERROR, PAYMASTER_ERROR) |
| **Total tests** | 42 |
| **Untested error codes** | 26 (2010-2015, 5002-5003, 6000-6004, 7000-7020) |
| **DRY violations** | 1 significant (factory boilerplate) |
| **Production callers of `:is()`** | 0 |
| **Production callers of `isStarknetError()`** | 0 |
| **`StarknetError.new()` misuses** | 7 (should use specific subtypes) |
| **Raw `._type` checks** | 2 (RpcProvider.luau:322, PaymasterRpc.luau:388) |

### Priority Actions (errors/)

1. **HIGH — Fix 7 `StarknetError.new()` misuses.** Replace with appropriate subtypes (`validation()`, `transaction()`, or a new `paymaster()`). This ensures `:is()` hierarchy works correctly for error discrimination.
2. **HIGH — Add `PaymasterError` subtype.** 15 error codes, 4+ source files — this is a major feature area without its own error subtype. Add `StarknetError.paymaster()` factory and `PaymasterError = { "StarknetError" }` to hierarchy.
3. **HIGH — Dogfood `:is()` in production.** Replace the 2 raw `._type == "RpcError"` checks in `RpcProvider.luau:322` and `PaymasterRpc.luau:388` with `:is("RpcError")`. If the SDK's own code doesn't use the hierarchy API, consumers won't trust it either.
4. **MEDIUM — DRY the factory constructors.** Extract `createError()` internal helper. Saves ~50 lines, makes adding new subtypes trivial and consistent.
5. **MEDIUM — Add missing test coverage.** 26 error codes are completely untested in the error spec. Add assertions for 2010-2015, 5002-5003, 6000-6004, 7000-7020 ranges. Add code uniqueness assertion.
6. **MEDIUM — Simplify `:is()` traversal.** Either make it properly recursive (future-proof) or simplify to single-level check (matches current reality). The current two-level hardcoded walk is the worst of both worlds.
7. **LOW — Clean up dead codes.** Remove or document `OUT_OF_RANGE`, `INSUFFICIENT_BALANCE`, `CACHE_ERROR`, `OUTSIDE_EXECUTION_ERROR`, `PAYMASTER_ERROR`. If they exist for future use, add a comment.
8. **LOW — Type the factory return values.** Define `StarknetErrorInstance` type and use it as the return type for all factories. Improves autocomplete and type checking in strict mode.

---

### Error Usage Across SDK — Cross-Cutting Audit

_Full audit of every `error()`, `reject()`, `pcall`, and `:catch()` call across 45 source files._

**Overall: Migration to structured errors is complete.** Zero raw `error("string")` or `reject("string")` calls remain. All ~130 `error()` calls and ~55 `reject()` calls use `StarknetError` factories. No string-based error matching exists in any `pcall` or `:catch()` handler.

**Inconsistencies found:**

| Severity | Issue | Files Affected |
|----------|-------|----------------|
| Medium | 7 `StarknetError.new()` calls should use specific subtypes | Pedersen, Account (×2), PaymasterBudget, SponsoredExecutor (×3) |
| Medium | `MATH_ERROR` used with inconsistent subtypes: `validation()` in BigInt/StarkField, `new()` in Pedersen | BigInt, StarkField, StarkScalarField, Pedersen |
| Medium | 2 raw `._type == "RpcError"` checks bypass `:is()` | RpcProvider:322, PaymasterRpc:388 |
| Low | `isStarknetError()` never called in production | All modules do their own guards |
| Low | `SponsoredExecutor.isTransientError()` reinvents `isStarknetError` guard | SponsoredExecutor:108 |

**Clean modules (no issues):** BigInt, StarkField, StarkScalarField, StarkCurve, ECDSA, StarkSigner, RequestQueue, ResponseCache, NonceManager, EventPoller, TransactionBuilder, TransactionHash, CallData, Contract, AbiCodec, ERC20, ERC721, TypedData, OutsideExecution, AccountFactory, AvnuPaymaster, PaymasterPolicy.
