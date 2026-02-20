# CLAUDE.md - starknet-luau

## Project Overview

Pure Luau SDK for Starknet blockchain interaction from Roblox games. No native FFI -- everything runs within Roblox's scripting environment.

## Architecture

- **crypto** -- Foundation layer: BigInt, StarkField, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA
- **signer** -- Stark ECDSA signing with RFC 6979
- **provider** -- JSON-RPC client over HttpService, Promise-based
- **tx** -- Transaction building, V3 INVOKE hash computation, calldata encoding
- **wallet** -- Account derivation (OZ, Argent), nonce management
- **contract** -- ABI-driven interface, ERC-20/ERC-721 presets

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
- `docs/` -- SPEC.md and ROADMAP.md

## Key Patterns

- Each module directory has an `init.luau` barrel export
- Buffer-based arithmetic for field operations (f64 limbs)
- Stark prime P = 2^251 + 17 * 2^192 + 1
- Curve order N for scalar field operations
- V3 INVOKE transactions with Poseidon-based hashing

## Dependencies

- `evaera/promise@^3.1.0` -- Promise library
- `daily3014/cryptography@^3.1.0` -- Optional peer dep for SHA/Keccak
