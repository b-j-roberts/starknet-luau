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

## Sections

1. [crypto/](./01-crypto.md)
2. [errors/](./02-errors.md)
3. [signer/](./03-signer.md)
4. [provider/](./04-provider.md)
5. [tx/](./05-tx.md)
6. [wallet/](./06-wallet.md)
7. [contract/](./07-contract.md)
8. [paymaster/](./08-paymaster.md)
9. [Root](./09-root.md)
10. [Examples](./10-examples.md)
11. [Docs](./11-docs.md)
12. [Tests](./12-tests.md)
13. [Config / Build](./13-config-build.md)
14. [Cross-Cutting Concerns](./14-cross-cutting.md)
