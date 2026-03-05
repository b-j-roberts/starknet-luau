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
