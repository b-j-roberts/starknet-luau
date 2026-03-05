## 13. Config / Build

### Makefile

**Current targets and status:**

| Target | Command | Works? | Notes |
|--------|---------|--------|-------|
| `install` | `wally install` + sourcemap + wally-package-types | Yes | Correct dependency chain |
| `pesde-install` | `pesde install` | Yes | Standalone, no other targets depend on it |
| `test` | `lune run tests/run` | Yes | Lune-based — doesn't need Wally packages |
| `serve` | `rojo serve` | Yes | Uses default.project.json (DataModel root) |
| `build` | `rojo build -o starknet-luau.rbxm` | Partial | See issues below |
| `lint` | `selene src/` | Yes | Uses starknet-luau.yml custom std |
| `fmt` | `stylua src/` | Yes | Formats in-place |
| `check` | `$(MAKE) lint` → `stylua --check src/` → `$(MAKE) test` | Yes | Sequential via recursive make |

**Issues:**

1. **`build` has no dependency on `install`** — `rojo build` needs `Packages/` to be populated (Wally Promise dependency). Running `make build` on a fresh clone without `make install` first will succeed but produce an rbxm without the Promise package. The CI release workflow handles this correctly (`wally install` → `rojo build`), but the Makefile doesn't enforce it.

2. **`build` uses DataModel-root project file** — `default.project.json` has `$className: "DataModel"` as root with `ReplicatedStorage.StarknetLuau` and `ReplicatedStorage.Packages` as children. When Rojo builds to `.rbxm`, it serializes the DataModel children, producing an rbxm containing a full `ReplicatedStorage` container. Inserting this rbxm into Studio would create a duplicate `ReplicatedStorage`. A distributable `.rbxm` should contain just the library module. Consider a dedicated build project file or adjusting the tree.

3. **No `clean` target** — No way to remove generated artifacts (`starknet-luau.rbxm`, `sourcemap.json`, `Packages/`, `roblox_packages/`). Minor but useful for CI debugging and fresh rebuilds.

4. **Missing targets for common workflows:**
   - No `build-and-test` or `all` convenience target
   - No `docs` target (if docs generation is ever needed)
   - No target to run a single test file (useful during development)

5. **`check` dependency ordering** — `check` runs lint → fmt check → test sequentially, which is correct. But if lint fails, it still runs fmt check and test due to `$(MAKE)` returning non-zero but the Makefile continuing. Consider using `&&` chaining or `.PHONY` dependencies.

**Recommendation:** Add `build: install` dependency. Consider adding a `clean` target. Evaluate whether `default.project.json` should be the Wally package descriptor (minimal) with `dev.project.json` used for `serve`/`build`.

---

### wally.toml / pesde.toml

**Consistency check:**

| Field | wally.toml | pesde.toml | Match? |
|-------|-----------|------------|--------|
| Name/scope | `b-j-roberts/starknet-luau` | `magic/starknet_luau` | **NO** — different scope and naming convention |
| Version | `0.1.0` | `0.1.0` | Yes |
| Description | "Pure Luau SDK for Starknet..." | "Pure Luau SDK for Starknet..." | Yes |
| License | MIT | MIT | Yes |
| Authors | `["Brandon Roberts"]` | `["Brandon Roberts"]` | Yes |
| Repository | `https://github.com/b-j-roberts/starknet-luau` | Same | Yes |
| Promise dep | `evaera/promise@^3.1.0` | `evaera/promise ^3.1.0` (wally index) | Yes |

**Issues:**

1. **Scope mismatch** — Wally uses `b-j-roberts` scope, pesde uses `magic`. The pesde scope should be whatever is registered with the pesde registry, but it should be documented why they differ. If `b-j-roberts` or `brandon-roberts` is available on pesde, it would be more consistent.

2. **Package name style** — Wally uses hyphens (`starknet-luau`), pesde uses underscores (`starknet_luau`). This is required by each registry's naming conventions, so it's correct but worth noting.

3. **`daily3014/cryptography@^3.1.0` ghost dependency** — CLAUDE.md mentions this as an "Optional peer dep for SHA/Keccak" but it is NOT declared in either wally.toml or pesde.toml. The only reference in source code is a comment in `BigInt.luau` line 6: "Following rbx-cryptography's proven performance patterns". This is inspiration attribution, not an actual dependency. The CLAUDE.md description should be updated to remove it.

4. **wally.toml include/exclude** — `include = ["default.project.json", "src/**", "LICENSE", "README.md"]` and `exclude = ["tests/**", "dev.project.json"]` are correct. The include list captures everything needed for the published package.

5. **No dev-dependencies declared** — `wally.toml` has empty `[dev-dependencies]` and `pesde.toml` has empty `[dev_dependencies]`. Since tests use Lune (not a Wally/pesde package), this is correct. Test framework is embedded in `tests/run.luau`.

6. **wally.lock and pesde.lock are git-tracked** — This is correct for reproducible builds. Promise resolves to `evaera/promise@3.2.1` in both.

**Dependency audit (declared vs. imported):**

| Dependency | Declared? | Actually imported? | Where? |
|------------|-----------|-------------------|--------|
| `evaera/promise` | Yes (both) | Yes | `src/provider/RpcProvider.luau:180`, `src/paymaster/PaymasterRpc.luau:235` — lazy-loaded via `require("@Packages/Promise")` |
| `daily3014/cryptography` | No | No (comment only) | BigInt.luau comment references pattern, not imported |

No undeclared runtime dependencies. No unused declared dependencies.

---

### default.project.json / dev.project.json

**default.project.json tree structure:**
```
DataModel
└── ReplicatedStorage
    ├── StarknetLuau → src/
    └── Packages → Packages/
```

**dev.project.json tree structure:**
```
DataModel
├── ReplicatedStorage
│   ├── StarknetLuau → src/
│   └── Packages → Packages/
├── ServerScriptService
│   └── Tests → tests/
├── Workspace (Baseplate part)
└── Lighting (ambient settings)
```

**Source coverage:** All 8 `src/` subdirectories (`contract/`, `crypto/`, `errors/`, `paymaster/`, `provider/`, `signer/`, `tx/`, `wallet/`) plus root files (`init.luau`, `constants.luau`) are captured by the single `$path: "src"` directive. No source files are missed.

**Issues:**

1. **CRITICAL: default.project.json should be the Wally package descriptor** — The Roblox ecosystem convention for Wally packages is that `default.project.json` describes the package's own tree (root = the library module), while a separate file handles development. Currently:
   - `default.project.json` = full DataModel (development layout)
   - `dev.project.json` = full DataModel + tests (extended development layout)

   For correct Wally packaging, `default.project.json` should be:
   ```json
   {
     "name": "starknet-luau",
     "tree": {
       "$path": "src"
     }
   }
   ```
   And the current `default.project.json` content should become `dev.project.json` (or a new `place.project.json`). The Makefile `serve` target would then reference `rojo serve dev.project.json` explicitly.

2. **dev.project.json correctly adds test infrastructure** — Tests under `ServerScriptService.Tests`, physical Workspace + Lighting for in-Studio testing. This is standard.

3. **Packages directory mapped in both** — The `Packages` → `Packages/` mapping is needed for the Promise dependency to resolve at runtime via `require(game.ReplicatedStorage.Packages.Promise)`. This is correct for development and in-Studio testing.

4. **`rojo build` output** — Building with DataModel root to `.rbxm` produces a model containing `ReplicatedStorage` as a child. When a consumer inserts this rbxm into Studio, they'd get a `ReplicatedStorage` folder inside wherever they drop it, which is awkward. The `.rbxm` release artifact should contain the library as a self-contained ModuleScript tree.

---

### selene.toml / .stylua.toml / .luaurc

**Code convention compliance:**

| Convention (per CLAUDE.md) | Config | Actual in code? |
|---------------------------|--------|----------------|
| Tabs | `.stylua.toml: indent_type = "Tabs"` | Yes |
| 120 col width | `.stylua.toml: column_width = 120` | Yes |
| Double quotes | `.stylua.toml: quote_style = "AutoPreferDouble"` | Yes |
| `--!strict` | `.luaurc: languageMode = "strict"` | Yes — all 45 source files |
| `--!native` + `--!optimize 2` on crypto | — | Yes — all 9 `src/crypto/*.luau` (non-init) |

**selene.toml:**
- `std = "starknet-luau"` references `starknet-luau.yml` (git-tracked, correct)
- The custom std extends `roblox` base and overrides `require` to accept `any` args (needed for relative string requires like `require("./Module")` that selene's default Roblox std wouldn't accept)
- No additional rule overrides — uses all defaults. Consider whether `allow(unused_variable)` or similar suppressions are needed for the codebase patterns.

**.luaurc:**
- `languageMode: "strict"` — matches convention ✓
- `lint: { "*": true }` — enables all lint warnings ✓
- `aliases.Packages = "Packages"` — enables `@Packages/Promise` resolution for Luau LSP ✓
- `aliases.ServerPackages = "ServerPackages"` — **`ServerPackages/` directory doesn't exist**. Harmless but unnecessary. Remove for clarity.

**LSP experience for relative requires:** Source modules use relative requires (`require("../crypto/BigInt")`) which Luau LSP may not resolve without explicit configuration. The `.luaurc` aliases only cover `@Packages/` and `@ServerPackages/`. Luau LSP should handle `./` and `../` relative requires natively in newer versions, but this could cause "unknown require" warnings in some setups.

---

### README.md

**Accuracy audit:**

| Item | Accurate? | Notes |
|------|-----------|-------|
| CI badge URL | Yes | `.github/workflows/ci.yml` exists with correct name |
| Version badge (0.1.0) | Yes | Matches wally.toml, pesde.toml |
| License badge/link | Yes | LICENSE file exists |
| Pesde install snippet | Partial | Uses `magic/starknet_luau` — matches pesde.toml but different scope than wally |
| Wally install snippet | Yes | Matches wally.toml name/version |
| Manual .rbxm install | Yes | Release workflow produces this artifact |
| Prerequisites (Rokit, Pesde) | Yes | `rokit.toml` exists; pesde is optional |
| Setup commands | Yes | `rokit install` → `make install` → `rojo serve` all work |
| Make commands table | Yes | All 7 targets documented, descriptions match behavior |
| Quick start code | Partial | See issues below |
| Docs table links | Yes | All 7 guide files exist at the referenced paths |
| API Overview table | **Incomplete** | Missing `errors` and `paymaster` modules |
| Project Structure diagram | **Incomplete** | Missing `src/errors/`, `src/paymaster/`, `src/constants.luau` |

**Issues:**

1. **Quick start require path** — `require(game.ReplicatedStorage.Packages.StarknetLuau)` assumes Wally consumer with standard Rojo config. This is correct for that audience but should note Pesde users may have a different path (`roblox_packages`). Also, the `Packages` in the path implies a nested `ReplicatedStorage > Packages > StarknetLuau` structure, which is standard for Wally consumers.

2. **API Overview table missing 2 modules** — Lists 6 modules (crypto, signer, provider, tx, wallet, contract) but `src/` has 8 subdirectories. Missing:
   - `errors` — StarknetError + ErrorCodes (structured error system)
   - `paymaster` — PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor

3. **Project Structure diagram missing modules** — Doesn't show `src/errors/`, `src/paymaster/`, or `src/constants.luau`. The `docs/` description says "Spec and roadmap" but docs also contains `guides/` (7 files) and `refactor/` (this doc series).

4. **No feature highlights for advanced capabilities** — No mention of:
   - SNIP-9 Outside Execution
   - SNIP-12 TypedData signing
   - SNIP-29 Paymaster support (sponsored transactions)
   - Deploy account orchestration
   - Account factory / batch deploy
   - Event querying and polling
   - Request queue / response cache / nonce manager

5. **Test count not mentioned** — 1,926 tests across 44 spec files is a strong credibility signal. Consider adding a badge or note.

6. **No "Supported Starknet Features" section** — Would help developers quickly assess whether the SDK covers their use case.

---

### Version Consistency

| Location | Version | Match? |
|----------|---------|--------|
| `wally.toml` | `0.1.0` | ✓ |
| `pesde.toml` | `0.1.0` | ✓ |
| `wally.lock` | `0.1.0` | ✓ |
| README badge | `0.1.0` | ✓ |
| README Wally snippet | `0.1.0` | ✓ |
| README Pesde snippet | `^0.1.0` | ✓ (semver range) |
| `src/constants.luau` | **Not present** | No version constant exported |

**Recommendation:** Consider adding `Constants.VERSION = "0.1.0"` to `src/constants.luau` for runtime version checking. Would need to be bumped alongside manifest files.

---

### .gitignore Coverage

| Path | Ignored? | Should be? | Notes |
|------|----------|-----------|-------|
| `*.rbxm` / `*.rbxl` / `*.rbxlx` / `*.rbxmx` | Yes | Yes | Build artifacts |
| `starknet-luau.rbxm` | Yes (via `*.rbxm`) | Yes | Specific build output |
| `sourcemap.json` | Yes | Yes | Generated by rojo |
| `Packages/` | Yes | Yes | Wally install output |
| `ServerPackages/` | Yes | Yes | Wally dev output |
| `DevPackages/` | Yes | Yes | Wally dev output |
| `roblox_packages/` | Yes | Yes | Pesde install output |
| `.pesde/` | Yes | Yes | Pesde internal |
| `roblox.yml` | Yes | Yes | Generated selene std |
| `wally.lock` | No (tracked) | No (tracked) | Correct — reproducible builds |
| `pesde.lock` | No (tracked) | No (tracked) | Correct — reproducible builds |
| `starknet-luau.yml` | No (tracked) | No (tracked) | Correct — custom selene std |
| `.DS_Store` / `Thumbs.db` | Yes | Yes | OS files |
| `.env` / secrets | Not present | N/A | No secrets files exist |

Coverage is correct and complete for current project structure.

---

### CI Configuration

**ci.yml** — 4 parallel jobs (build, test, lint, fmt). All use `roblox-ts/setup-rokit@v0.1.2` which installs tools from `rokit.toml`.

| Job | Steps | Notes |
|-----|-------|-------|
| `build` | checkout → rokit → `wally install` → `rojo build -o starknet-luau.rbxm` | Correctly installs deps before build |
| `test` | checkout → rokit → `lune run tests/run` | No `wally install` needed — correct |
| `lint` | checkout → rokit → `selene src/` | No `wally install` needed — correct |
| `fmt` | checkout → rokit → `stylua --check src/` | No `wally install` needed — correct |

**release.yml** — Triggers on `v*` tags. Builds rbxm, creates GitHub Release, publishes to Wally and Pesde.

**Issues:**

1. **No matrix testing** — Only runs on `ubuntu-latest`. Tests are Lune-based (cross-platform), so this is fine, but could optionally test macOS/Windows.
2. **No caching** — Each CI job installs Rokit tools from scratch. Consider caching `~/.rokit/` for faster CI.
3. **CI doesn't run `make check`** — Runs individual jobs in parallel instead. This is actually better (faster, more granular failure reporting). Not an issue.
4. **Release workflow DataModel root issue** — Same `rojo build` concern as local build. The rbxm artifact attached to releases may have unexpected tree structure.

---

### Fresh Clone Experience

Steps for a new contributor:

```bash
git clone https://github.com/b-j-roberts/starknet-luau.git
cd starknet-luau
rokit install       # Installs rojo, wally, lune, selene, stylua, wally-package-types
make install        # wally install + sourcemap + package types
make test           # 1926 tests pass ✓
make check          # lint + fmt check + test ✓
make build          # Produces starknet-luau.rbxm ✓
```

**Works correctly.** The only potential friction:
1. `rokit` must be installed first (documented in README prerequisites)
2. `make test` works without `make install` (Lune tests don't need Packages)
3. `make build` without `make install` succeeds but produces rbxm without Promise bundled
4. No indication of required Rokit version

---

### Summary of Recommended Changes

**Critical (affects publishing/distribution):**
1. Restructure `default.project.json` to be the Wally package descriptor (`$path: "src"` root), move current DataModel layout to `dev.project.json`, update Makefile `serve`/`build` targets accordingly

**Important (correctness/completeness):**
2. Update README API Overview table to include `errors` and `paymaster` modules
3. Update README Project Structure to include `src/errors/`, `src/paymaster/`, `src/constants.luau`
4. Remove `daily3014/cryptography` mention from CLAUDE.md (it's not a dependency)
5. Remove `ServerPackages` alias from `.luaurc` (directory doesn't exist)

**Nice-to-have (developer experience):**
6. Add `clean` target to Makefile
7. Add `build: install` dependency in Makefile (or document the ordering)
8. Add `Constants.VERSION` to `src/constants.luau`
9. Add Starknet feature highlights to README (SNIP-9/12/29, paymaster, deploy, events)
10. Consider adding Rokit CI caching
11. Document pesde scope difference (`magic` vs `b-j-roberts`)
