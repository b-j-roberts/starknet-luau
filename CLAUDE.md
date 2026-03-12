# CLAUDE.md - starknet-luau

## Project Overview

Pure Luau SDK for Starknet blockchain interaction from Roblox games. No native FFI -- everything runs within Roblox's scripting environment.

## Architecture

- **crypto** -- Foundation layer: BigInt, FieldFactory, StarkField, StarkScalarField, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA
- **signer** -- Stark ECDSA signing with RFC 6979
- **provider** -- RpcProvider (22+ methods), JsonRpcClient, EventPoller, RequestQueue, ResponseCache, NonceManager
- **tx** -- TransactionBuilder, TransactionHash (V3 INVOKE + DEPLOY_ACCOUNT), CallData encoding
- **wallet** -- Account (OZ/Argent/Braavos), AccountType, AccountFactory, TypedData (SNIP-12), OutsideExecution (SNIP-9), KeyStore, OnboardingManager
- **contract** -- ABI-driven Contract interface, AbiCodec (recursive Cairo codec), ERC20/ERC721 presets, PresetFactory
- **paymaster** -- PaymasterRpc (SNIP-29), AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor
- **errors** -- StarknetError (typed hierarchy with factory constructors), ErrorCodes (numeric constants 1000-8010)
- **shared** -- Internal utilities: interfaces (breaks circular deps), HexUtils, BufferUtils, ByteArray, TestableDefaults

## Development Commands

```bash
make install    # wally install + sourcemap + wally-package-types
make test       # lune run tests/run
make serve      # rojo serve
make build      # rojo build -o starknet-luau.rbxm
make lint       # selene src/
make fmt        # stylua src/
make check      # lint + fmt check + test
```

## Code Conventions

- **Language**: Luau with `--!strict` mode on all files
- **Formatting**: StyLua (tabs, 120 col width, double quotes)
- **Linting**: Selene with Roblox standard library
- **Async**: All network operations use roblox-lua-promise (Promise-based)
- **Performance**: Use `--!native` and `--!optimize 2` pragmas on hot crypto paths
- **Testing**: Lune-based test runner, `.spec.luau` files in `tests/` mirroring `src/` structure
- **Test vectors**: Cross-reference against starknet.js expected values

## File Structure

- `src/` -- Library source (maps to ReplicatedStorage.StarknetLuau via Rojo)
- `tests/` -- Lune test specs (mirror src/ directory structure)
- `tests/fixtures/` -- Shared test vectors
- `tests/helpers/` -- MockPromise, TestUtils
- `examples/` -- Runnable example scripts (13 examples)
- `docs/` -- SPEC.md, ROADMAP.md, and guides

## Key Patterns

- Each module directory has an `init.luau` barrel export
- `shared/` module provides internal utilities (interfaces, hex/buffer helpers) -- not exported via top-level barrel
- Buffer-based arithmetic for field operations (f64 limbs)
- Stark prime P = 2^251 + 17 * 2^192 + 1
- Curve order N for scalar field operations
- V3 INVOKE and DEPLOY_ACCOUNT transactions with Poseidon-based hashing
- Dependency injection for HTTP, clock, defer enables pure-unit testing
- Typed error hierarchy (StarknetError) with numeric error codes across all modules

## Dependencies

- `evaera/promise@^3.1.0` -- Promise library

## Publishing

- **Wally**: scope `b-j-roberts` (wally.toml `name = "b-j-roberts/starknet-luau"`)
- **pesde**: scope `magic` (pesde.toml `name = "magic/starknet_luau"`) — pesde scopes are organization-level and `magic` is the registered pesde scope for this publisher

## Require Conventions

Barrel exports (`init.luau`) use Roblox-style `require(script.Module)` — these only execute inside Roblox runtime where `script` is the Instance reference. Source modules use relative path `require("./Module")` which works in both Lune tests and modern Roblox.
