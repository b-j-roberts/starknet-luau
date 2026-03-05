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
-

### StarkField.luau
-

### StarkScalarField.luau
-

### StarkCurve.luau
-

### Poseidon.luau
-

### Pedersen.luau
-

### Keccak.luau
-

### SHA256.luau
-

### ECDSA.luau
-

### crypto/init.luau (barrel)
-

---

## 2. errors/

### ErrorCodes.luau
-

### StarknetError.luau
-

### errors/init.luau (barrel)
-

---

## 3. signer/

### StarkSigner.luau
-

### signer/init.luau (barrel)
-

---

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

-

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
-

### Require patterns (Roblox vs Lune)
-

### Error handling consistency
-

### API naming consistency
-

### Type exports
-
