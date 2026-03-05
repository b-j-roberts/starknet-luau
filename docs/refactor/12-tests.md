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
