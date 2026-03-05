# Refactor Research — starknet-luau v0.2.0

Full code review & refactor audit. Reviewing every module bottom-up (foundations first, high-level last).

Leave notes per file using the tags defined in the legend below.

---

## Legend

| Tag | Meaning |
|--------|----------------------------------------------|
| `[ok]` | Reviewed, no issues found |
| `[fix]` | Bug, incorrect implementation, or code that needs correction |
| `[refactor]` | Code smell, duplication, or structural improvement needed |
| `[feat]` | Missing feature or incomplete functionality |
| `[perf]` | Performance concern or optimization opportunity |
| `[type]` | Type annotation issue (missing, wrong, or `--!strict` gap) |
| `[test]` | Missing test coverage or test quality issue |
| `[doc]` | Missing or misleading documentation / comments |
| `[api]` | Public API design issue (naming, signatures, consistency) |
| `[skip]` | Intentionally skipped for now |

---

## 1. crypto/

### BigInt.luau
_806 lines. Foundation layer: buffer-based arbitrary precision integers using 11 f64 limbs × 24 bits._

- `[ok]` Clean foundation design. 24-bit limbs keep intermediates < 2^53 (f64 safe). Good carry propagation.
- `[ok]` Comprehensive public API: constructors, comparisons, arithmetic, bitwise, modular ops, Barrett reduction.
- `[ok]` Performance pragmas (`--!native`, `--!optimize 2`) correctly applied.
- `[ok]` Structured error handling via `StarknetError.validation()` for division by zero, inversion of zero.
- `[refactor]` `toHex()` (line 225) builds hex from f64 limbs manually. This is a different code path from `bufferToHex()` in Keccak/SHA256 (which converts raw byte buffers). Not a duplication per se, but these are two distinct hex-encoding functions that serve different data shapes — document this distinction or consider unifying via `toBytes() → bufferToHex()`.
- `[perf]` `powmod()` (line 476) uses `BigInt.mulmod()` (division-based) instead of Barrett reduction. This is the slow path — only StarkField/StarkScalarField use the fast Barrett `powmodBarrett()`. Consider adding a `powmodB(a, e, ctx)` to BigInt directly so callers don't have to reimplement the loop.
- `[type]` `export type BigInt = buffer` — type alias provides no structural distinction from raw buffers. A consumer could accidentally pass a raw `buffer.create(88)` as a `BigInt`. This is a Luau limitation, but worth noting.
- `[test]` 94 tests, low redundancy, good edge cases at limb boundaries (2^24, 2^48, 2^72). No gaps.

### StarkField.luau
_189 lines. Modular arithmetic over Stark prime P = 2^251 + 17·2^192 + 1._

- `[ok]` Clean thin wrapper over BigInt with pre-computed Barrett context. All arithmetic reduces mod P.
- `[ok]` Tonelli-Shanks `sqrt()` correctly parameterized (S=192, Q=0x800000000000011, z=3).
- `[refactor]` **MAJOR — near-identical to StarkScalarField.luau.** The following functions are copy-pasted with only the modulus variable name changed: `reduce()`, `powmodBarrett()`, `zero()`, `one()`, `fromNumber()`, `fromHex()`, `add()`, `sub()`, `mul()`, `square()`, `neg()`, `inv()`, `toHex()`, `toBigInt()`, `eq()`, `isZero()`. That's 16 functions duplicated across ~300 total lines. See [Cross-Cutting: Field Duplication](#field-duplication) below.
- `[refactor]` `P` constant (line 16) is also duplicated in `wallet/TypedData.luau:25` as `STARK_PRIME`. Should import from a single source.
- `[test]` 51 tests, medium redundancy. Tests like "add is commutative" and "Field Properties: additive identity" overlap. Could consolidate ~30% via table-driven parameterization.

### StarkScalarField.luau
_136 lines. Modular arithmetic over curve order N._

- `[refactor]` **MAJOR — 95% identical to StarkField.luau.** Only differences: (1) modulus is N instead of P, (2) no `sqrt()` function, (3) error message says "StarkScalarField" instead of "StarkField". Every other line is a character-for-character copy. **This is the single biggest DRY violation in the codebase.** See recommendation below.
- `[refactor]` `N` constant (line 17) is duplicated in `StarkCurve.luau:41`. StarkCurve should import from StarkScalarField instead of re-computing `BigInt.fromHex(...)`.
- `[api]` Missing `sqrt()` — intentional (not all scalars are quadratic residues mod N, and it's not needed for ECDSA). But should document why it's absent for API consistency.
- `[test]` 54 tests, **HIGH redundancy** — 95% duplicate of StarkField tests. Only 2 unique ECDSA-pattern tests. Could share a parameterized test suite.

#### Recommended Fix: Field Factory {#field-duplication}

Extract a `createField(modulus, modulusMinus2, name)` factory function that generates all 16 shared methods. StarkField adds `sqrt()` as an extension. This eliminates ~130 lines of duplication and makes it trivial to add new fields in the future.

```luau
-- Option A: Factory function in a shared module
local FieldFactory = require("./FieldFactory")
local StarkField = FieldFactory.create(P, P_MINUS_2, "StarkField")
StarkField.sqrt = function(a) ... end -- extension

-- Option B: Parameterized base with metatables
-- Less explicit but more Luau-idiomatic
```

### StarkCurve.luau
_238 lines. Elliptic curve operations on y² = x³ + x + β (Jacobian coordinates)._

- `[ok]` Correct Jacobian doubling formula (dbl-2001-b from hyperelliptic.org for a=1). Well-optimized field op count.
- `[ok]` Addition handles edge cases correctly: P1=infinity, P2=infinity, P1=P2 (delegates to doubling), P1=-P2 (returns identity).
- `[ok]` Left-to-right double-and-add scalar multiplication — standard and correct.
- `[ok]` `getPublicKey()` validates private key range [1, N-1] with proper error types.
- `[refactor]` `StarkCurve.N` (line 41) duplicates `StarkScalarField.N`. Should `require("./StarkScalarField")` and re-export `StarkScalarField.N` instead of calling `BigInt.fromHex()` again (wastes ~microseconds at load and is a correctness risk if one is updated without the other).
- `[perf]` `scalarMul()` uses basic double-and-add (no windowed method, no wNAF). For the typical 252-bit scalars, this means ~252 doublings + ~126 additions. A 4-bit window would reduce to ~252 doublings + ~63 additions. Low priority since this is already behind `--!native`, but worth noting for hot paths (ECDSA verify does 2 scalar muls).
- `[api]` `scalarMul()` returns `AffinePoint?` (nil for k=0). This forces nil-checks at every call site. Consider returning a dedicated `INFINITY` sentinel point instead, or documenting this as a design choice.
- `[type]` Jacobian identity uses `{ x = one(), y = one(), z = zero() }` — the x/y values are arbitrary when z=0, but `one()` is a valid convention. Document this.
- `[test]` 53 tests, low redundancy, excellent coverage of curve properties.

### Poseidon.luau
_623 lines. Hades-based sponge hash over StarkField._

- `[ok]` Correct round structure: 4 full + 83 partial + 4 full = 91 rounds. S-box = x³.
- `[ok]` MDS matrix [[3,1,1],[1,-1,1],[1,1,-2]] implemented as optimized inline operations (no matrix multiplication loop).
- `[ok]` Round constants from official `poseidon3.txt` — 273 values (91 rounds × 3).
- `[perf]` Round constants are parsed from hex strings at module load time (lines 26-270). That's 273 `StarkField.fromHex()` calls during `require()`. Consider pre-computing as raw buffer literals or lazy initialization if startup time matters.
- `[refactor]` File is 623 lines, but 250+ lines are round constant hex strings. Could move constants to a separate `PoseidonConstants.luau` file to improve readability of the algorithm implementation. The core algorithm (permute + hash functions) is only ~100 lines.
- `[test]` 22 tests, cross-referenced with starknet.js vectors. Could test `hashMany` with larger inputs (8+, 16+, 100+ elements) to stress the sponge padding logic.
- `[doc]` Good header comment with reference link.

### Pedersen.luau
_130 lines. Elliptic curve hash using precomputed point tables._

- `[ok]` Lazy table initialization via `ensureTables()` — avoids 504 point doublings at require time.
- `[ok]` Correct decomposition: 248-bit low + 4-bit high for each input, mapped to P0/P1 and P2/P3 bases.
- `[ok]` Uses Jacobian arithmetic throughout (no affine inversions until final result).
- `[perf]` Precomputation: 2 tables × 252 entries = 504 Jacobian points stored. Each is `{x, y, z}` = 3 BigInt buffers = 264 bytes × 3 × 504 = ~388 KB. Acceptable for a game runtime, but worth documenting.
- `[perf]` `processSingleElement()` (line 98) does 252 `getBit()` + conditional `jacobianAdd()` per element. Since most bits are 1 for random field elements, this averages ~126 additions. No optimization (e.g., skip runs of zeros). Acceptable given lazy init and `--!native`.
- `[test]` 17 tests — adequate but thin. Only 5 explicit hash vector tests (vs 6+ for Poseidon/Keccak/SHA256). 5 tests just validate constant points are on the curve (static data, not algorithm coverage). Could benefit from more hash vectors.

### Keccak.luau
_403 lines. Keccak-256 (Ethereum-style, NOT NIST SHA-3)._

- `[ok]` Correct Keccak-f[1600] permutation: theta, rho+pi, chi, iota over 24 rounds.
- `[ok]` Rate = 1088 bits (136 bytes) for Keccak-256. Padding uses 0x01 (Keccak), not 0x06 (SHA-3).
- `[ok]` `snKeccak()` correctly masks to 250 bits for Starknet function selectors.
- `[refactor]` **`bufferToHex()` (lines 359-369) is an exact duplicate of SHA256's `bufferToHex()` (lines 292-302).** Both are identical 10-line functions with the same `HEX_CHARS` constant. Should extract to a shared utility.
- `[refactor]` Keccak has both `local function bufferToHex()` (private, line 360) and `function Keccak.bufferToHex()` (public, line 399) that wraps it. The public version exists only for "testing/debugging" per the comment. Consider whether a crypto module should expose hex utilities — this leaks implementation details.
- `[perf]` 64-bit lane operations use hi/lo 32-bit pair emulation (lines 85-120) since Luau has no native 64-bit integer type. This is inherently ~2x slower than native 64-bit but unavoidable in Luau. The `bit32` usage is correct.
- `[test]` 24 tests, good boundary testing at 135/136/137 bytes (rate block boundary). Selector tests with real Cairo names. Minimal redundancy.

### SHA256.luau
_305 lines. FIPS 180-4 SHA-256 + RFC 2104 HMAC-SHA-256._

- `[ok]` Correct message schedule expansion, 64-round compression, standard constants.
- `[ok]` HMAC implementation follows RFC 2104 (key padding, ipad/opad XOR, double hash).
- `[ok]` Padding handles multi-block messages correctly (64-byte blocks with length in final 8 bytes).
- `[refactor]` **`bufferToHex()` (lines 292-302) is an exact duplicate of Keccak's.** See Keccak entry above.
- `[refactor]` `readBE32()` / `writeBE32()` (lines 16-28) are general-purpose big-endian I/O helpers. Could be shared if a `BufferUtils.luau` is created.
- `[api]` `SHA256.bufferToHex()` is exposed publicly "for testing/debugging". Same concern as Keccak — crypto modules shouldn't be the canonical source of hex utilities.
- `[test]` 31 tests — excellent. NIST vectors, RFC 4231 HMAC vectors, padding edge cases at block boundaries (55, 56, 63, 64, 128 bytes). Best-tested hash module.

### ECDSA.luau
_325 lines. RFC 6979 deterministic ECDSA signing for the Stark curve._

- `[ok]` Correct RFC 6979 implementation with Starknet-specific `bits2int` / `bits2intModN` modifications.
- `[ok]` `bits2intModN()` correctly handles the 63-hex-char edge case (multiply by 16 before bits2int to cancel 4-bit shift). This matches @scure/starknet behavior.
- `[ok]` Sign: validates private key range, generates deterministic k, computes r = (k·G).x mod N, s = k⁻¹·(m + r·d) mod N.
- `[ok]` Verify: validates r, s ∈ [1, N-1], checks public key on curve, computes R' = u1·G + u2·Q.
- `[refactor]` `concatBuffers()` (lines 121-135) and `singleByte()` (lines 138-142) are general-purpose buffer utilities used only here. Should extract to shared utility module.
- `[refactor]` `toBytes32()` (lines 41-55) is a fixed-length BigInt-to-bytes serialization. This pattern (zero-pad to 32 bytes) is needed elsewhere too (e.g., transaction hash serialization). Consider adding `BigInt.toBytes32()` or `BigInt.toBytesN(n)`.
- `[perf]` `generateK()` (line 151) has a 1000-iteration safety limit. In practice, the first candidate almost always works for Stark curve parameters. The limit is appropriate.
- `[perf]` `verify()` does 2 independent scalar multiplications (u1·G, u2·Q) that could be done with Shamir's trick (interleaved double-and-add). ~40% speedup for verification. Low priority.
- `[test]` 37 tests — excellent. 7+ cross-reference vectors from @scure/starknet, tamper detection, error cases.

### crypto/init.luau (barrel)
_24 lines. Re-exports all crypto modules._

- `[ok]` Clean barrel export, no logic.
- `[refactor]` Uses Roblox-style `require(script.Module)` — correct for Roblox runtime but incompatible with Lune. This is the documented pattern (see MEMORY.md) so it's intentional. No action needed.
- `[doc]` Has a comment listing all exported modules. Good.

---

### crypto/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 3,179 |
| **Total public functions** | 72 |
| **Total tests** | 383 |
| **Performance pragmas** | All 9 modules use `--!strict --!native --!optimize 2` |
| **Error handling** | Consistent `StarknetError` structured errors throughout |
| **DRY violations** | 3 significant (field duplication, bufferToHex, buffer utilities) |

### Priority Actions

1. **HIGH — Extract Field Factory.** StarkField and StarkScalarField share 16 identical functions (~300 lines). Create `FieldFactory.luau` or parameterize via a `createField()` function. Saves ~130 lines, eliminates the biggest DRY violation.
2. **HIGH — Extract `BufferUtils.luau`.** Consolidate `bufferToHex()` (duplicated in Keccak + SHA256), `concatBuffers()` (ECDSA-only), `singleByte()` (ECDSA-only), and optionally `readBE32()`/`writeBE32()` (SHA256-only). ~50 lines saved, cleaner module boundaries.
3. **MEDIUM — Centralize constants.** Curve order `N` is computed via `BigInt.fromHex()` in both `StarkScalarField.luau:17` and `StarkCurve.luau:41`. Stark prime `P` is in both `StarkField.luau:16` and `wallet/TypedData.luau:25`. Either import from a single source or use `src/constants.luau`.
4. **MEDIUM — Consolidate field tests.** StarkField (51 tests) and StarkScalarField (54 tests) are 95% identical. Extract a parameterized `fieldTestSuite(Field, modulus, name)` and run it against both. Saves ~50 tests of duplication.
5. **LOW — Add `BigInt.powmodB(a, e, ctx)`.** Both field modules reimplement `powmodBarrett()` identically. Moving it into BigInt eliminates duplication and benefits any future field types.
6. **LOW — Move Poseidon round constants.** 250+ lines of hex strings make `Poseidon.luau` hard to read. Extract to `PoseidonConstants.luau`.
7. **LOW — Windowed scalar multiplication.** 4-bit window or wNAF for `StarkCurve.scalarMul()` would speed up ECDSA verify (~40% fewer point additions). Only matters if verification is a hot path.

---

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

- `[type]` **All factories return `any`.** Erases type information in `--!strict` mode. Callers get no autocomplete on `.message`, `.code`, `.revertReason`, etc. Could define:
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

---

## 3. signer/

### StarkSigner.luau
_78 lines. Stark curve signer wrapping ECDSA operations behind a clean interface._

- `[ok]` Clean, minimal wrapper — 78 lines total. Single responsibility: key management + signing delegation.
- `[ok]` Constructor validates private key range `[1, N-1]` with structured `SigningError` errors. Consistent with ECDSA.sign() internal validation.
- `[ok]` Lazy public key derivation: `getPubKey()` caches the expensive EC scalar multiplication on first call. Subsequent calls return the cached `AffinePoint` (same table reference, verified in tests).
- `[ok]` Deterministic signing via ECDSA.sign() — no redundant validation or re-implementation. The signer is a pure facade.
- `[ok]` Proper error codes: `INVALID_PRIVATE_KEY` for zero key, `KEY_OUT_OF_RANGE` for key >= N.

- `[refactor]` **Dual signing on `signTransaction()`.** `signTransaction()` (line 73) calls `ECDSA.sign()` directly instead of delegating to `self:signRaw()`. This means `signTransaction` and `signRaw` are two independent entry points into ECDSA, making it harder to add instrumentation, logging, or rate limiting at a single chokepoint. Should be:
  ```luau
  function StarkSignerClass:signTransaction(txHash: buffer): { string }
      local sig = self:signRaw(txHash)  -- delegate instead of ECDSA.sign()
      return { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }
  end
  ```
  Functionally identical, but channels all signing through one method.

- `[refactor]` **`signRaw` + hex conversion duplicated in Account:signMessage().** `Account:signMessage()` (Account.luau:741-742) does `self.signer:signRaw(hashBuf)` then `{ BigInt.toHex(sig.r), BigInt.toHex(sig.s) }` — this is exactly what `signTransaction()` already does. The Account method reimplements the buffer→hex conversion instead of calling `signTransaction()`. This creates two code paths that produce identical `{ string }` output from a hash buffer:
  1. `StarkSigner:signTransaction(buf)` → used by TransactionBuilder
  2. `Account:signMessage()` → `signer:signRaw(buf)` + manual `BigInt.toHex()` → used by SNIP-12, paymaster, outside execution

  **Fix:** `Account:signMessage()` should call `self.signer:signTransaction(hashBuf)` directly:
  ```luau
  function Account:signMessage(typedData: { [string]: any }): { string }
      local msgHash = self:hashMessage(typedData)
      local hashBuf = BigInt.fromHex(msgHash)
      return self.signer:signTransaction(hashBuf)  -- reuse signTransaction
  end
  ```
  Eliminates the duplicate `BigInt.toHex(sig.r), BigInt.toHex(sig.s)` pattern.

- `[refactor]` **Naming asymmetry: `signTransaction` vs `signRaw`.** The method `signTransaction()` doesn't do anything transaction-specific — it just signs a hash and returns hex strings. A message hash and a transaction hash go through the exact same code path. The name implies it has transaction-specific logic (nonce, calldata, etc.) when it's really just `signToHex()`. Consider renaming to `signToHexArray()` or `signHex()` to clarify it works on any hash, not just transaction hashes. This would also make it more natural for `Account:signMessage()` to call it.

- `[refactor]` **Redundant private key validation between StarkSigner and ECDSA.** `StarkSigner.new()` (lines 27-37) validates `privateKey ∈ [1, N-1]`. `ECDSA.sign()` (lines 218-228) performs the **exact same validation** again on every call. Since the signer stores the validated key and passes it through, the ECDSA-level check is redundant for signer-mediated calls. Two options:
  - **Keep both (current approach):** Defense-in-depth. ECDSA stays safe for direct callers who bypass StarkSigner. Minor perf cost (two BigInt comparisons per sign).
  - **Remove ECDSA validation:** ECDSA becomes a "trusted internal" layer, signer enforces the contract. Saves 2 BigInt comparisons per sign. Risk: direct ECDSA callers lose validation.
  - **Recommendation:** Keep both for now — the perf cost is negligible and the safety is worth it. But document the intentional redundancy so future maintainers don't "optimize" one away without understanding the tradeoff.

- `[api]` **No `Signer` interface type exported.** The signer is consumed duck-typed everywhere:
  - `TransactionBuilder.Account.signer` (TransactionBuilder.luau:18-20) defines its own inline type: `{ signTransaction: (self: any, txHash: buffer) -> { string } }`
  - `Account.new()` (Account.luau:429) accepts `signer: any` — no type constraint at all
  - `AccountFactory._createAccountFromSigner()` (AccountFactory.luau:63) accepts `signer: any`
  - `Account:signMessage()` (Account.luau:741) calls `signer:signRaw()` — a method not in TransactionBuilder's type
  - The dummy signer in `getDeploymentFeeEstimate` (Account.luau:227-233) implements only `signTransaction`

  This means there are **two implicit signer interfaces** in the SDK:
  1. **Minimal (TransactionBuilder):** `{ signTransaction(self, buffer) -> {string} }` — used for tx signing + fee estimation
  2. **Full (Account):** `{ signTransaction, signRaw, getPubKey, getPublicKeyHex }` — used for SNIP-12, address derivation, deploy

  **Recommendation:** Export a formal `Signer` type from `src/signer/StarkSigner.luau` (already there as `StarkSigner` type, line 11-16) and use it in Account.new() and AccountFactory instead of `any`. Define a `MinimalSigner` type for TransactionBuilder's narrower requirement. This makes the contract explicit and helps catch errors at type-check time.

- `[api]` **`getPubKey()` returns full `AffinePoint` (x, y) but only `x` is ever used.** Every consumer calls `getPublicKeyHex()` which extracts only `pubKey.x`. The raw `AffinePoint` (including `y`) is never used outside tests. `getPubKey()` exposes internal crypto details that most consumers don't need. Not a bug, but worth documenting that `getPublicKeyHex()` is the intended public API for most use cases.

- `[api]` **Private key is stored as a BigInt buffer (`self._privateKey`) with no accessor.** There's no `getPrivateKeyHex()` method, which is correct from a security perspective — private keys should not be casually extractable. However, there's also no way to serialize/restore a signer for persistence. If account recovery or export is ever needed, this would require a new method. Document the intentional omission.

- `[type]` **Constructor return type is `any` (line 44: `return self :: any`).** The exported `StarkSigner` type (lines 11-16) is well-defined, but the `:: any` cast erases it at the constructor boundary. Callers of `StarkSigner.new()` get `any` instead of `StarkSigner`. This is a Luau limitation with `setmetatable` patterns — the cast is necessary to avoid type errors with the metatable approach. Document this as a known limitation.

- `[test]` 21 tests — **well-structured, low redundancy, excellent coverage given the module's simplicity.**
  - 5 constructor tests (valid keys, zero rejection, N rejection, prefix handling)
  - 4 getPubKey tests (correctness, caching, @scure/starknet vector)
  - 2 getPublicKeyHex tests (format, prefix)
  - 7 signRaw tests (output shape, determinism, ECDSA equivalence, cross-reference vector, verifiability)
  - 8 signTransaction tests (array format, hex prefix, signRaw equivalence, cross-reference vector, verifiability)
  - 2 multi-signer tests (key isolation, signature isolation)
- `[test]` **Missing: error message content assertions.** Tests use `:toThrowType("SigningError")` but don't verify the error code is `INVALID_PRIVATE_KEY` vs `KEY_OUT_OF_RANGE`. If error codes were swapped, tests would still pass.
- `[test]` **Missing: private key near boundary N-1.** Tests validate `key == 0` (rejected) and `key >= N` (rejected) but don't test `key == N-1` (should succeed) or `key == N+1` (should fail). Boundary testing is important for the `[1, N-1]` range.
- `[test]` **Missing: signing with edge-case hashes.** No test for `signRaw(BigInt.zero())` or `signRaw(BigInt.fromHex(N_hex))` — extreme hash values that stress the `bits2intModN` path.

### signer/init.luau (barrel)
_9 lines. Re-exports StarkSigner._

- `[ok]` Clean barrel export, no logic.
- `[ok]` Uses Roblox-style `require(script.StarkSigner)` — correct for runtime barrel.
- `[api]` Returns `{ StarkSigner = StarkSigner }` table. Consistent with other barrel exports.

---

### signer/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 87 (78 + 9) |
| **Total public functions** | 5 (new, getPubKey, getPublicKeyHex, signRaw, signTransaction) |
| **Total tests** | 21 |
| **Test vectors** | 2 (@scure/starknet cross-reference) |
| **Production callers** | 7 (TransactionBuilder ×2, Account ×5) |
| **Code duplication** | 1 significant (signRaw→hex in Account:signMessage) |
| **Implicit interfaces** | 2 (full StarkSigner, minimal signTransaction-only) |
| **DRY violations** | 2 (signTransaction bypasses signRaw, Account reimplements hex conversion) |

### Priority Actions (signer/)

1. **HIGH — Fix Account:signMessage() to use signTransaction().** Replace `signer:signRaw(buf)` + manual hex conversion with `signer:signTransaction(buf)`. Eliminates the duplicated `BigInt.toHex(sig.r), BigInt.toHex(sig.s)` pattern across two files. One-line fix.
2. **HIGH — Fix signTransaction() to delegate to signRaw().** Change `ECDSA.sign(txHash, self._privateKey)` to `self:signRaw(txHash)`. Channels all signing through one method, making instrumentation easier.
3. **MEDIUM — Export formal Signer interface types.** Define and export `Signer` (full) and `MinimalSigner` (signTransaction-only) types. Use them in Account.new(), AccountFactory, and TransactionBuilder instead of `any`. Makes the implicit contract explicit.
4. **MEDIUM — Add boundary tests.** Test `key == N-1` (valid), `key == N+1` (invalid), `signRaw(zero_hash)`, `signRaw(N_hash)`. Add error code assertions to constructor error tests.
5. **LOW — Consider renaming signTransaction → signHex.** The method has no transaction-specific logic — it signs any hash and returns hex. Current name is misleading and discourages reuse for non-transaction signing (which Account:signMessage() needs). This is a breaking API change, so weigh against stability.
6. **LOW — Document intentional redundant validation.** StarkSigner.new() and ECDSA.sign() both validate the private key range. Add a comment in ECDSA.sign() noting this is defense-in-depth for direct callers.

---

### Signer Cross-Cutting Audit — All Signing Flows

_Complete audit of every signing operation across the SDK, tracing from user-facing API to ECDSA._

**Flow 1: Transaction Execution (INVOKE V3)**
```
Account:execute(calls, options)
  → TransactionBuilder:execute(account, calls, options)
    → TransactionHash.calculateInvokeTransactionHash(...) → hex string
    → BigInt.fromHex(txHash) → buffer
    → account.signer:signTransaction(buffer) → { "0x...", "0x..." }
      → ECDSA.sign(txHash, privateKey) → { r: buffer, s: buffer }
    → RPC: addInvokeTransaction({ signature = [...] })
```

**Flow 2: Account Deployment (DEPLOY_ACCOUNT V3)**
```
Account:deployAccount(options)
  → TransactionBuilder:deployAccount(account, params, options)
    → TransactionHash.calculateDeployAccountTransactionHash(...) → hex string
    → BigInt.fromHex(txHash) → buffer
    → account.signer:signTransaction(buffer) → { "0x...", "0x..." }
      → ECDSA.sign(txHash, privateKey) → { r: buffer, s: buffer }
    → RPC: addDeployAccountTransaction({ signature = [...] })
```

**Flow 3: SNIP-12 Message Signing**
```
Account:signMessage(typedData)
  → TypedData.getMessageHash(typedData, address) → hex string
  → BigInt.fromHex(msgHash) → buffer
  → self.signer:signRaw(buffer) → { r: buffer, s: buffer }     ← DIFFERENT PATH
  → { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }               ← MANUAL HEX CONVERSION
```
**Issue:** This flow bypasses `signTransaction()` and reimplements the hex conversion. Should use `signTransaction()` for consistency.

**Flow 4: Paymaster-Sponsored Execution**
```
Account:executeWithPaymaster(paymaster, calls, options)
  → AvnuPaymaster:buildTypedData(...) → TypedData
  → Account:signMessage(typedData) → { "0x...", "0x..." }     (uses Flow 3)
  → AvnuPaymaster:executeTransaction(address, typedData, signature)
```

**Flow 5: Paymaster-Sponsored Deployment**
```
Account:deployWithPaymaster(paymaster, options)
  → AvnuPaymaster:buildTypedData(...) → TypedData
  → Account:signMessage(typedData) → { "0x...", "0x..." }     (uses Flow 3)
  → AvnuPaymaster:executeTransaction(address, typedData, signature, { deploymentData })
```

**Flow 6: Fee Estimation (Dummy Signer)**
```
Account.getDeploymentFeeEstimate(config)
  → dummyAccount.signer.signTransaction(_self, _hash) → { "0x0", "0x0" }
  → TransactionBuilder:estimateDeployAccountFee(dummyAccount, params)
  → RPC: estimateFee({ ..., signature = ["0x0", "0x0"], SKIP_VALIDATE })
```

**Flow 7: OutsideExecution Tests (Direct ECDSA)**
```
tests/wallet/OutsideExecution.spec.luau:
  → TypedData.getMessageHash(td, address) → hex string
  → BigInt.fromHex(msgHash) → buffer
  → signer:signRaw(buffer) → { r: buffer, s: buffer }
  → ECDSA.verify(hashBuf, pubKeyPoint, sig)
```
**Note:** Tests use `signRaw()` directly for verification roundtrip. This is appropriate for unit tests.

**Summary of signing entry points:**

| Entry Point | Method Used | Output Format | Callers |
|-------------|-------------|---------------|---------|
| Transaction signing | `signTransaction(buffer)` | `{ string }` (hex array) | TransactionBuilder.execute, TransactionBuilder.deployAccount |
| Message signing | `signRaw(buffer)` + manual hex | `{ string }` (hex array) | Account.signMessage |
| Verification prep | `signRaw(buffer)` | `{ r: buffer, s: buffer }` | OutsideExecution tests |
| Fee estimation | dummy `signTransaction` | `{ "0x0", "0x0" }` | Account.getDeploymentFeeEstimate |

**Key Finding:** All four entry points ultimately produce the same final format (`{ string }`) but through two different code paths. Unifying Flow 3 to use `signTransaction()` would reduce this to one production path.

## 4. provider/

### RpcTypes.luau
-

### RpcProvider.luau
-

### RequestQueue.luau
-

### ResponseCache.luau
-

### NonceManager.luau
-

### EventPoller.luau
-

### provider/init.luau (barrel)
-

---

## 5. tx/

### CallData.luau
-

### TransactionHash.luau
-

### TransactionBuilder.luau
-

### tx/init.luau (barrel)
-

---

## 6. wallet/

### AccountType.luau
-

### Account.luau
-

### AccountFactory.luau
-

### TypedData.luau
-

### OutsideExecution.luau
-

### wallet/init.luau (barrel)
-

---

## 7. contract/

### AbiCodec.luau
-

### Contract.luau
-

### ERC20.luau
-

### ERC721.luau
-

### contract/init.luau (barrel)
-

---

## 8. paymaster/

### PaymasterRpc.luau
-

### AvnuPaymaster.luau
-

### PaymasterPolicy.luau
-

### PaymasterBudget.luau
-

### SponsoredExecutor.luau
-

### paymaster/init.luau (barrel)
-

---

## 9. Root

### constants.luau
-

### init.luau (main entry)
-

---

## 10. Examples

### leaderboard.luau
-

### multicall.luau
-

### nft-gate.luau
-

### read-contract.luau
-

### send-transaction.luau
-

---

## 11. Docs

### SPEC.md
-

### ROADMAP.md
-

### CHANGELOG.md
-

### docs/guides/getting-started.md
-

### docs/guides/crypto.md
-

### docs/guides/accounts.md
-

### docs/guides/contracts.md
-

### docs/guides/patterns.md
-

### docs/guides/roblox.md
-

### docs/guides/api-reference.md
-

---

## 12. Tests

### tests/helpers/MockPromise.luau
-

### tests/fixtures/test-vectors.luau
-

### tests/fixtures/cross-reference.spec.luau
-

### tests/integration/sepolia.spec.luau
-

### tests/run.luau
-

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

## 13. Config / Build

### Makefile
-

### wally.toml / pesde.toml
-

### default.project.json / dev.project.json
-

### selene.toml / .stylua.toml / .luaurc
-

### README.md
-

---

## Cross-Cutting Concerns

_Issues that span multiple modules. Reference specific files where relevant._

### Shared utilities / code duplication

- `[refactor]` **`bufferToHex()` duplicated verbatim** in `crypto/Keccak.luau:359-369` and `crypto/SHA256.luau:292-302`. Identical 10-line function + `HEX_CHARS` constant. Extract to a shared `BufferUtils.luau`.
- `[refactor]` **`concatBuffers()` and `singleByte()`** in `crypto/ECDSA.luau:121-142` are general-purpose buffer utilities trapped in a crypto module. Move to shared utility.
- `[refactor]` **`readBE32()` / `writeBE32()`** in `crypto/SHA256.luau:16-28` are general big-endian I/O. Could move to shared utility if needed elsewhere.
- `[refactor]` **`toBytes32()`** in `crypto/ECDSA.luau:41-55` (fixed-length BigInt serialization) is a pattern needed in transaction hash computation too. Consider `BigInt.toBytes32()` or `BigInt.toBytesFixed(n)`.
- `[refactor]` **StarkField + StarkScalarField: 16 identical functions** (~300 lines total). Biggest DRY violation. See crypto/ section for recommended field factory approach.
- `[refactor]` **Curve order N computed twice**: `StarkScalarField.luau:17` and `StarkCurve.luau:41` both call `BigInt.fromHex()` with the same hex string. StarkCurve should import from StarkScalarField.
- `[refactor]` **Stark prime P computed twice**: `StarkField.luau:16` and `wallet/TypedData.luau:25`. TypedData should import from StarkField.

### Require patterns (Roblox vs Lune)

- `[ok]` Source modules (`src/`) use `require("./Module")` for sibling imports — works in both Lune and modern Roblox.
- `[ok]` Barrel exports (`init.luau`) use `require(script.Module)` — Roblox-only, which is correct since barrels are only used at runtime.
- `[ok]` Test files use relative paths from test location: `require("../../src/crypto/BigInt")` — Lune-compatible.
- `[doc]` This dual-pattern is documented in MEMORY.md but not in the codebase itself. Consider a comment in `init.luau` files explaining the pattern for new contributors.

### Error handling consistency

- `[ok]` All crypto modules use `StarknetError` structured errors with `ErrorCodes` constants.
- `[ok]` Error messages include module prefix (e.g., "ECDSA.sign:", "StarkField:", "StarkCurve:").
- `[ok]` Validation errors use `StarknetError.validation()`, crypto errors use `StarknetError.signing()`.
- `[ok]` No raw `error("string")` calls remain in any source module — all 130+ migrated to structured errors.
- `[ok]` No raw `reject("string")` calls remain — all 55+ use `StarknetError` objects.
- `[ok]` No string-based error matching (`string.find`, `string.match`) in any `pcall` or `:catch()` handler.
- `[refactor]` **7 `StarknetError.new()` misuses** where specific subtypes should be used. See [errors/ section](#2-errors) for full table.
- `[refactor]` **`MATH_ERROR` code used with inconsistent subtypes** — `validation()` in BigInt/StarkField vs `new()` (base) in Pedersen. Consumer catching math errors cannot rely on `:is("ValidationError")` consistently.
- `[refactor]` **`:is()` method and `isStarknetError()` are never used in production** — only in tests. The 2 production error-type checks use raw `._type == "RpcError"`. Either dogfood the hierarchy API internally or acknowledge it's consumer-facing only.
- `[api]` **Missing `PaymasterError` subtype.** 15 error codes across 4+ files have no dedicated factory or hierarchy entry. Paymaster errors are thrown as untyped `StarknetError.new()`, `rpc()`, or `validation()` — inconsistent and hard to discriminate programmatically.
- `[refactor]` **Error code numeric ranges don't always match error subtypes.** `TRANSACTION_REVERTED` (2004) and `TRANSACTION_REJECTED` (2005) are in the 2000 RPC range but used with `StarknetError.transaction()`. `MATH_ERROR` (3010) is in the 3000 signing range but used with both `validation()` and `new()`. No enforcement that code ranges and `_type` subtypes are aligned.

### API naming consistency

- `[ok]` Constructors: `zero()`, `one()`, `fromNumber(n)`, `fromHex(hex)` — consistent across BigInt, StarkField, StarkScalarField.
- `[ok]` Arithmetic: `add(a,b)`, `sub(a,b)`, `mul(a,b)`, `square(a)`, `neg(a)`, `inv(a)` — consistent across fields.
- `[ok]` Conversions: `toHex(a)`, `toBigInt(a)`, `eq(a,b)`, `isZero(a)` — consistent.
- `[ok]` Hash functions: `hash(a,b)` for Poseidon/Pedersen, `keccak256(input)` / `hash(data)` for Keccak/SHA256 — different names are appropriate since they serve different roles.
- `[api]` `bufferToHex()` is exposed on both `Keccak` and `SHA256` as a public method "for testing/debugging". Crypto modules shouldn't be the canonical source of hex conversion utilities. Move to BufferUtils and remove from crypto public APIs.

### Type exports

- `[ok]` `BigInt.BigInt = buffer` — exported, used by StarkField/StarkScalarField.
- `[ok]` `StarkField.Felt = buffer` — exported, used by StarkCurve, Poseidon, Pedersen.
- `[ok]` `StarkScalarField.Scalar = buffer` — exported, used by ECDSA.
- `[ok]` `StarkCurve.AffinePoint`, `StarkCurve.JacobianPoint` — exported, used by Pedersen, ECDSA.
- `[ok]` `ECDSA.Signature = { r: buffer, s: buffer }` — exported.
- `[ok]` `BigInt.BarrettCtx` — exported, used by field modules.
- `[type]` All buffer-based types (`BigInt`, `Felt`, `Scalar`) are aliases for `buffer`. Luau's type system cannot distinguish them structurally, so a `Felt` can be passed where a `Scalar` is expected without type errors. This is a known Luau limitation, not actionable.
