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
- `[refactor]` **7 `StarknetError.new()` misuses** where specific subtypes should be used. See [errors/ section](./02-errors.md) for full table.
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
