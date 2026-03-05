## 9. Root

### constants.luau

#### Overview

`src/constants.luau` defines 13 public constants across 5 categories: chain IDs (2), class hashes (4), contract address prefix (1), token addresses (2), transaction versions (3), and SNIP-9 (1). The module is clean and well-organized — but it is massively under-utilized. Most source modules that need these values define their own copies inline, defeating the purpose of a constants file.

#### Per-Constant Audit

##### Chain IDs

| Constant | Value | Correct vs Spec | Source Duplicates | Test Duplicates |
|----------|-------|-----------------|-------------------|-----------------|
| `SN_MAIN` | `"0x534e5f4d41494e"` | Yes — ASCII "SN_MAIN" | `TransactionHash.luau:48` | 30+ inline occurrences across 14 test files |
| `SN_SEPOLIA` | `"0x534e5f5345504f4c4941"` | Yes — ASCII "SN_SEPOLIA" | `TransactionHash.luau:49` | 30+ inline occurrences across 14 test files |

- `[refactor]` **`TransactionHash.SN_MAIN` / `SN_SEPOLIA` duplicate `Constants.SN_MAIN` / `SN_SEPOLIA`.** TransactionHash does not import Constants at all — defines its own copies on lines 48–49 and re-exports them as public fields. These should be removed; consumers should use `Constants.SN_MAIN` / `SN_SEPOLIA` directly.
- `[refactor]` **14+ test files define `local SN_SEPOLIA = "0x534e5f5345504f4c4941"` inline** instead of importing from Constants or test-vectors. Files: `Account.spec:50`, `AccountFactory.spec:37`, `PrefundingHelper.spec:19`, `BatchDeploy.spec:22`, `OutsideExecution.spec:16`, `RpcProvider.spec:20`, `NonceManager.spec:15`, `DeployAccount.spec:18`, `TransactionBuilder.spec:19`, `Contract.spec:20`, `ERC20.spec:20`, `ERC721.spec:20`, `TransactionHash.spec:126-130`. Should import from `Constants` or `test-vectors.luau`.

##### Class Hashes

| Constant | Value | Correct vs Spec | Source Duplicates |
|----------|-------|-----------------|-------------------|
| `OZ_ACCOUNT_CLASS_HASH` | `0x061dac...2971b8f` | Yes — OZ Cairo 1 v0.8.1 | `Account.luau:44`, `AccountType.luau:22` |
| `ARGENT_ACCOUNT_CLASS_HASH` | `0x03607...45927f` | Yes — Argent v0.4.0 | `Account.luau:47`, `AccountType.luau:25` |
| `BRAAVOS_ACCOUNT_CLASS_HASH` | `0x03957...759bf8a` | Yes — Braavos impl v1.2.0 | `Account.luau:50` |
| `BRAAVOS_BASE_ACCOUNT_CLASS_HASH` | `0x03d16...8dc1f` | Yes — Braavos base v1.2.0 | `Account.luau:53` |

- `[refactor]` **Class hashes are the worst DRY violation in constants.** 4 class hashes × 3 definition sites = 12 independent copies of the same hex strings across `constants.luau`, `Account.luau` (lines 44–53), and `AccountType.luau` (lines 22–25). None of these modules import from each other. All values match, but maintenance burden is tripled. See [wallet/ section](./06-wallet.md) for the consolidation plan. Both `Account.luau` and `AccountType.luau` should import from `Constants`.
- `[refactor]` **`Account.luau` also has a `CLASS_HASH_TO_TYPE` lookup table (lines 57–69)** with normalized (leading-zero-stripped) versions of the same hashes plus historical versions (OZ v0.14, Argent v0.3.1). These historical hashes are NOT in `constants.luau`. If the SDK supports detecting accounts deployed with older contract versions, these historical class hashes should either be centralized in constants or documented as an internal lookup concern.

##### Contract Address Prefix

| Constant | Value | Correct vs Spec |
|----------|-------|-----------------|
| `CONTRACT_ADDRESS_PREFIX` | `0x535441524b4e45545f434f4e54524143545f41444452455353` | Yes — ASCII "STARKNET_CONTRACT_ADDRESS" |

- `[refactor]` **Duplicated in `Account.luau:26`** as `local CONTRACT_ADDRESS_PREFIX = "0x535441524b4e45545f434f4e54524143545f41444452455353"`. Account already imports Constants (line 15) but doesn't use `Constants.CONTRACT_ADDRESS_PREFIX`. Should replace the local definition with the import.

##### Token Addresses

| Constant | Value | Correct vs Spec | Source Duplicates |
|----------|-------|-----------------|-------------------|
| `ETH_TOKEN_ADDRESS` | `0x049d3...04dc7` | Yes — Starknet ETH ERC-20 | `AvnuPaymaster.luau:36, 58` |
| `STRK_TOKEN_ADDRESS` | `0x04718...7c938d` | Yes — Starknet STRK ERC-20 | `AvnuPaymaster.luau:41, 63` |

- `[refactor]` **`AvnuPaymaster.luau` hardcodes ETH and STRK addresses** in its `KNOWN_TOKENS` table (lines 32–66) for both mainnet and sepolia networks, duplicating the values from `constants.luau`. Should import from Constants. Note: AvnuPaymaster also defines USDC and USDT addresses (lines 44–53) that are NOT in constants.luau — these are AVNU-specific and appropriately live in the paymaster module.
- `[doc]` **`constants.luau` comment says "same on Mainnet and Sepolia"** (line 40) for token addresses. This is correct for ETH and STRK, but worth noting that this is a Starknet-specific property (L1 ETH doesn't behave this way). The comment is accurate and helpful.

##### Transaction Versions

| Constant | Value | Correct vs Spec | Source Duplicates |
|----------|-------|-----------------|-------------------|
| `INVOKE_TX_V3` | `"0x3"` | Yes | None |
| `DEPLOY_ACCOUNT_TX_V3` | `"0x3"` | Yes | None |
| `DECLARE_TX_V3` | `"0x3"` | Yes | None |

- `[ok]` No source duplicates — these are cleanly used via `Constants.INVOKE_TX_V3` etc.
- `[refactor]` **All three V3 constants have the same value `"0x3"`.** Semantically meaningful to have separate names for each transaction type (future versions may diverge), but `TransactionHash.luau:40` defines a separate `local V3_VERSION = StarkField.fromHex("0x3")` as a `Felt` (buffer), not a hex string. This isn't exactly a duplicate since it's a different type (`Felt` vs `string`), but it represents the same concept. Consider whether `TransactionHash` should derive `V3_VERSION` from `Constants.INVOKE_TX_V3`.

##### SNIP-9 Constants

| Constant | Value | Correct vs Spec |
|----------|-------|-----------------|
| `ANY_CALLER` | `"0x414e595f43414c4c4552"` | Yes — ASCII "ANY_CALLER" |

- `[ok]` `OutsideExecution.luau:33` re-exports as `OutsideExecution.ANY_CALLER = Constants.ANY_CALLER`. This is a convenience re-export, not a duplication — the value originates from Constants. Clean pattern.

#### Constants That Are Missing

These are magic values scattered across the codebase that arguably belong in `constants.luau`:

- `[refactor]` **Transaction type prefixes.** `TransactionHash.luau:34-37` defines `INVOKE_PREFIX = "0x696e766f6b65"` (ASCII "invoke") and `DEPLOY_ACCOUNT_PREFIX = "0x6465706c6f795f6163636f756e74"` (ASCII "deploy_account") as local Felt values. These are protocol-level constants used in transaction hash computation. Centralizing them in `constants.luau` as hex strings would make the protocol constants discoverable. However, they're only used in `TransactionHash.luau`, so the argument for centralization is weaker — this is a judgment call.
- `[refactor]` **Resource names.** `TransactionHash.luau:43-45` defines `L1_GAS_NAME`, `L2_GAS_NAME`, `L1_DATA_NAME` as BigInt buffers. Same argument as above — protocol constants with a single use site.
- `[refactor]` **SNIP-9 Interface IDs.** `OutsideExecution.luau:36-37` defines `INTERFACE_ID_V1` and `INTERFACE_ID_V2` as hex strings. These are well-known SNIP constants that could live in `constants.luau` under a SNIP-9 section — but they're also fine as module-level constants since they're only relevant to outside execution.
- `[refactor]` **AVNU endpoint URLs.** `AvnuPaymaster.luau:17-19` hardcodes mainnet/sepolia endpoint URLs. These are service-specific configuration, not protocol constants — appropriately live in the paymaster module, not constants.

**Recommendation:** Only centralize constants that are (a) protocol-level and (b) used across multiple modules. Transaction prefixes and resource names are protocol-level but single-use — keep them local. Class hashes, chain IDs, token addresses, and CONTRACT_ADDRESS_PREFIX are both protocol-level and multi-use — must be centralized.

#### Constant Tests

- `[ok]` `tests/constants.spec.luau` (100 lines, 10 tests) validates all 13 constants with exact value assertions plus a completeness check. Good coverage.
- `[test]` **No test for `ANY_CALLER`** — the completeness test on line 82–98 checks 9 fields but omits `ANY_CALLER`, `ARGENT_ACCOUNT_CLASS_HASH`, `BRAAVOS_ACCOUNT_CLASS_HASH`, and `BRAAVOS_BASE_ACCOUNT_CLASS_HASH`. These should be added to the completeness check.
- `[test]` **Cross-reference test `tests/fixtures/cross-reference.spec.luau:349-354`** validates `TransactionHash.SN_MAIN/SN_SEPOLIA` against test vectors, but does NOT validate `Constants.SN_MAIN/SN_SEPOLIA`. Should cross-reference Constants too.

---

### init.luau (main entry)

#### Overview

`src/init.luau` is the top-level barrel export — the single entry point for Roblox consumers who `require` the SDK. It imports all 8 sub-modules + constants and re-exports them as a flat table.

```luau
return {
    crypto = crypto,
    signer = signer,
    provider = provider,
    tx = tx,
    wallet = wallet,
    contract = contract,
    constants = constants,
    errors = errors,
    paymaster = paymaster,
}
```

#### API Surface Audit

| Namespace | Modules Exposed | Modules in Directory | Gap |
|-----------|----------------|---------------------|-----|
| `crypto` | 9/9 | BigInt, StarkField, StarkScalarField, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA | None |
| `signer` | 1/1 | StarkSigner | None |
| `provider` | 6/6 | RpcProvider, RpcTypes, EventPoller, RequestQueue, ResponseCache, NonceManager | None |
| `tx` | 3/3 | CallData, TransactionHash, TransactionBuilder | None |
| `wallet` | 5/5 | Account, TypedData, AccountType, AccountFactory, OutsideExecution | None |
| `contract` | 3/4 | Contract, ERC20, ERC721 — **missing AbiCodec** | 1 |
| `errors` | 2/2 | StarknetError, ErrorCodes | None |
| `paymaster` | 5/5 | PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor | None |
| `constants` | 1/1 | (flat module, not a directory) | None |
| **Total** | **35/36** | | **1 gap** |

- `[api]` **AbiCodec not exported.** `src/contract/AbiCodec.luau` is intentionally marked as internal (comment on line 4: "Internal module consumed by Contract.luau — not exported through barrel init.luau"). However, `docs/guides/api-reference.md` documents it as public API with 4 methods (`buildTypeMap`, `resolveType`, `encode`, `decode`). Consumers who want to do custom calldata encoding outside of `Contract` (e.g., building raw multicall data) have no access to the recursive type-aware codec. See [contract/ section](./07-contract.md) for the decision.

#### Barrel Export Style Inconsistency

- `[refactor]` **`contract/init.luau` uses inline `require()` calls** instead of the local-variable-then-return pattern used by all other barrel exports.

Current (`contract/init.luau`):
```luau
return {
    Contract = require(script.Contract),
    ERC20 = require(script.ERC20),
    ERC721 = require(script.ERC721),
}
```

Every other barrel (`crypto`, `signer`, `provider`, `tx`, `wallet`, `errors`, `paymaster`):
```luau
local Module = require(script.Module)
-- ...
return {
    Module = Module,
    -- ...
}
```

Should normalize `contract/init.luau` to match the standard pattern.

#### Namespace Design for Roblox Game Developers

- `[ok]` The top-level API surface is clean: 9 namespaces, each mapping to a logical concern. Roblox developers access modules via `Starknet.crypto.BigInt`, `Starknet.wallet.Account`, etc.
- `[api]` **The `tx` namespace name is terse.** While common in blockchain SDKs, a Roblox game developer may find `transaction` more discoverable. However, this is a minor naming preference — `tx` is well-established in the Starknet ecosystem and matches starknet.js naming.
- `[api]` **No "convenience" top-level re-exports.** starknet.js re-exports commonly used classes at the top level (e.g., `import { Account, Provider, Contract } from "starknet"`). This SDK requires `Starknet.wallet.Account`, `Starknet.provider.RpcProvider`, `Starknet.contract.Contract`. Adding optional top-level aliases (e.g., `Starknet.Account = Starknet.wallet.Account`) would improve DX for common use cases — but also creates two ways to access the same thing. This is a taste call.
- `[ok]` The barrel correctly uses `require(script.X)` (Roblox-style) since it's only loaded at Roblox runtime. Source modules correctly use `require("./path")` for Lune compatibility.

#### What's NOT Exported (and Shouldn't Be)

These are internal implementation details correctly excluded from the public API:

- `tests/helpers/MockPromise.luau` — test infrastructure
- `tests/helpers/MockRpc.luau` (proposed) — test infrastructure
- Buffer utility functions (`bufferToHex`, `concatBuffers`, `singleByte`) — currently trapped in crypto modules, should be extracted to shared utility (see [cross-cutting](./14-cross-cutting.md)) but still not public API
- `normalizeHex()` — duplicated across 3 modules, should be shared internally but not exported

#### What Might Be Missing

- `[api]` **No version constant.** The SDK has no `Starknet.VERSION` or `Starknet.SDK_VERSION` string. Useful for debugging, logging, and ensuring compatibility. Low priority but standard practice for SDKs.
- `[api]` **No type re-exports.** Luau consumers can't easily access types like `RpcProvider.RpcProviderConfig`, `CallData.Call`, or `TransactionHash.ResourceBounds` without importing the sub-module directly. The barrel export makes the module table available but doesn't surface the type namespace. This is a Luau limitation (types aren't first-class values) but worth noting for documentation.

#### init.luau Tests

- `[test]` **No dedicated test file for init.luau barrel export.** There is no `tests/init.spec.luau` that validates the main barrel exports all expected namespaces. The `tests/constants.spec.luau` covers constants, and `tests/fixtures/cross-reference.spec.luau` covers some cross-module validation, but no test verifies the barrel itself.
- `[test]` **Tests never import through the barrel.** All 1926 tests import modules directly (e.g., `require("../../src/crypto/BigInt")`), bypassing the barrel entirely. This means if a barrel export is accidentally removed or renamed, no test would catch it. At minimum, add a smoke test that imports via the barrel and verifies each namespace key exists.

---

### Summary of Issues

#### Critical (DRY violations in source code)

| Issue | Tag | Files Affected | Impact |
|-------|-----|----------------|--------|
| Class hashes defined in 3 places | `[refactor]` | `constants.luau`, `Account.luau`, `AccountType.luau` | 12 independent copies of 4 hex strings |
| Chain IDs defined in 2 places | `[refactor]` | `constants.luau`, `TransactionHash.luau` | Values diverge risk; 2 public APIs for same data |
| `CONTRACT_ADDRESS_PREFIX` duplicated | `[refactor]` | `constants.luau`, `Account.luau` | Account already imports Constants but doesn't use it |
| ETH/STRK addresses hardcoded in AvnuPaymaster | `[refactor]` | `constants.luau`, `AvnuPaymaster.luau` | 4 hardcoded copies of 2 addresses |
| Stark prime P duplicated | `[refactor]` | `StarkField.luau`, `TypedData.luau` | Different variable names, same hex value |

#### Moderate (API / style / test gaps)

| Issue | Tag | Details |
|-------|-----|---------|
| AbiCodec not exported but documented as public | `[api]` | Contradicts API reference docs |
| `contract/init.luau` style mismatch | `[refactor]` | Inline require vs local+return pattern |
| No init.luau barrel test | `[test]` | Barrel export correctness is untested |
| Constants completeness test incomplete | `[test]` | Missing `ANY_CALLER` and 3 class hashes |
| 14+ test files hardcode `SN_SEPOLIA` inline | `[refactor]` | Should import from Constants or test-vectors |

#### Low Priority (Nice-to-have)

| Issue | Tag | Details |
|-------|-----|---------|
| No `SDK_VERSION` constant | `[api]` | Standard SDK practice |
| `tx` namespace could be `transaction` | `[api]` | Naming taste — `tx` matches starknet.js |
| No top-level convenience aliases | `[api]` | `Starknet.Account` vs `Starknet.wallet.Account` |
| Transaction prefixes not centralized | `[refactor]` | Single-use in TransactionHash — borderline |

---

### Recommended Refactor Plan

#### Phase 1: Consolidate Constants (eliminates all critical DRY violations)

1. **In `Account.luau`**: Remove lines 26, 44–53 (local `CONTRACT_ADDRESS_PREFIX` + 4 class hash fields). Replace with imports from `Constants`:
   ```luau
   -- Replace Account.OZ_CLASS_HASH with Constants.OZ_ACCOUNT_CLASS_HASH
   -- Replace local CONTRACT_ADDRESS_PREFIX with Constants.CONTRACT_ADDRESS_PREFIX
   ```
   Keep `CLASS_HASH_TO_TYPE` lookup table (lines 57–69) since it serves a different purpose (reverse lookup with historical versions).

2. **In `AccountType.luau`**: Remove lines 22, 25 (`OZ_CLASS_HASH`, `ARGENT_CLASS_HASH`). Import from `Constants`. Update `AccountType.OZ.classHash` and `AccountType.Argent.classHash` to reference the imported constants.

3. **In `TransactionHash.luau`**: Remove lines 48–49 (`SN_MAIN`, `SN_SEPOLIA`). These are public exports — removing them is a **breaking change**. Either:
   - (a) Remove and update all consumers to use `Constants.SN_MAIN/SN_SEPOLIA`, or
   - (b) Keep as re-exports: `TransactionHash.SN_MAIN = Constants.SN_MAIN` (deprecated alias)

4. **In `AvnuPaymaster.luau`**: Import `Constants` and use `Constants.ETH_TOKEN_ADDRESS` / `Constants.STRK_TOKEN_ADDRESS` for the ETH/STRK entries in `KNOWN_TOKENS` table. Keep USDC/USDT inline (AVNU-specific).

5. **In `TypedData.luau`**: Remove line 25 (`local STARK_PRIME = BigInt.fromHex(...)`). Import from `StarkField`: `local STARK_PRIME = StarkField.P`.

#### Phase 2: Barrel & Test Hygiene

6. **Normalize `contract/init.luau`** to use local-variable-then-return pattern.

7. **Add `tests/init.spec.luau`** that imports the barrel and asserts all 9 namespace keys exist with expected sub-module keys.

8. **Update `tests/constants.spec.luau`** completeness test to include `ANY_CALLER`, `ARGENT_ACCOUNT_CLASS_HASH`, `BRAAVOS_ACCOUNT_CLASS_HASH`, `BRAAVOS_BASE_ACCOUNT_CLASS_HASH`.

9. **Consolidate test `SN_SEPOLIA` definitions**: Replace 14+ inline definitions with `local Constants = require("../../src/constants")` and `Constants.SN_SEPOLIA`.

#### Phase 3: Optional Enhancements

10. **Add `Constants.SDK_VERSION = "0.2.0"`** for runtime version checking.

11. **Decide on AbiCodec export** — either export it in `contract/init.luau` and update the source comment, or remove it from `api-reference.md`. See [contract/ section](./07-contract.md).
