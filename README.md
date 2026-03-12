# starknet-luau

[![CI](https://github.com/b-j-roberts/starknet-luau/actions/workflows/ci.yml/badge.svg)](https://github.com/b-j-roberts/starknet-luau/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.2.0-blue)](https://github.com/b-j-roberts/starknet-luau/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Pure Luau SDK for interacting with the Starknet blockchain from Roblox games. Provides cryptographic primitives, account management, transaction building/signing, contract interaction, paymaster-sponsored transactions, and RPC connectivity -- all implemented in Luau with no external native dependencies.

## Features

- Player onboarding lifecycle management
- Encrypted key storage via DataStore
- SNIP-29 paymaster integration (AVNU, policy engine, per-player budgets)
- Deploy account orchestration with batch deploy for game onboarding
- Request queuing with priority batching and response caching
- Event polling with DataStore persistence
- V3 INVOKE and DEPLOY_ACCOUNT transaction building and signing
- ERC-20 and ERC-721 presets
- ABI-driven contract interaction with recursive Cairo type codec
- Full Stark-curve cryptography (BigInt, ECDSA, Poseidon, Pedersen, Keccak, SHA-256)
- SNIP-9 outside execution (meta-transactions)
- SNIP-12 typed data signing (LEGACY Pedersen + ACTIVE Poseidon)
- Typed error hierarchy with numeric error codes

## Installation

**Via [Pesde](https://pesde.dev/packages/magic/starknet_luau):**
```toml
[dependencies]
starknet_luau = { name = "magic/starknet_luau", version = "^0.2.0" }
```

> **Note:** Pesde installs packages to `roblox_packages/` by default. Your require path will be:
> ```luau
> local Starknet = require(game.ReplicatedStorage.roblox_packages.StarknetLuau)
> ```

**Via [Wally](https://wally.run/package/b-j-roberts/starknet-luau):**
```toml
[dependencies]
starknet-luau = "b-j-roberts/starknet-luau@0.2.0"
```

**Manual (.rbxm):**
Download the latest `.rbxm` from [Releases](../../releases) and drop it into your project.

## Quick Start

```luau
local Starknet = require(game.ReplicatedStorage.Packages.StarknetLuau)

-- Create a provider
local provider = Starknet.provider.RpcProvider.new("https://api.zan.top/public/starknet-sepolia")

-- Get the latest block number
provider:getBlockNumber():andThen(function(blockNumber)
    print("Current block:", blockNumber)
end)

-- Read from a contract
local contract = Starknet.contract.Contract.new(provider, contractAddress, abi)
contract:call("balanceOf", { accountAddress }):andThen(function(balance)
    print("Balance:", balance)
end)
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/guides/getting-started.md) | Installation, basic setup, first transaction |
| [Contract Interaction](docs/guides/contracts.md) | Reading state, writing transactions, multicall, presets |
| [Account Management](docs/guides/accounts.md) | Key generation, address derivation, account types, nonce handling |
| [Common Patterns](docs/guides/patterns.md) | NFT gating, token rewards, onchain leaderboards |
| [Roblox Considerations](docs/guides/roblox.md) | Rate limits, server-side patterns, security best practices |
| [Crypto Deep Dive](docs/guides/crypto.md) | Understanding BigInt, StarkField, curves, hashes, ECDSA |
| [API Reference](docs/guides/api-reference.md) | Complete API documentation for all modules |

## Examples

| Example | Description |
|---------|-------------|
| [read-contract.luau](examples/read-contract.luau) | Read ERC-20 token balances from Starknet |
| [send-transaction.luau](examples/send-transaction.luau) | Send an INVOKE transaction |
| [deploy-account.luau](examples/deploy-account.luau) | Deploy a new Starknet account |
| [player-onboarding.luau](examples/player-onboarding.luau) | Full player lifecycle with KeyStore + OnboardingManager |
| [sponsored-transaction.luau](examples/sponsored-transaction.luau) | Gasless transactions via paymaster |
| [multicall.luau](examples/multicall.luau) | Batch multiple calls in a single transaction |
| [nft-gate.luau](examples/nft-gate.luau) | Gate game content behind NFT ownership |
| [leaderboard.luau](examples/leaderboard.luau) | Onchain leaderboard integration |
| [typed-data.luau](examples/typed-data.luau) | SNIP-12 typed data signing |
| [outside-execution.luau](examples/outside-execution.luau) | SNIP-9 meta-transactions |
| [event-listener.luau](examples/event-listener.luau) | Poll and process onchain events |
| [provider-features.luau](examples/provider-features.luau) | Request queuing, caching, rate limiting |
| [error-handling.luau](examples/error-handling.luau) | Typed error handling patterns |

## API Overview

| Module | Description |
|--------|-------------|
| `wallet` | Account (OZ/Argent/Braavos), AccountType, AccountFactory, TypedData (SNIP-12), OutsideExecution (SNIP-9), KeyStore, OnboardingManager |
| `contract` | Contract (ABI-driven), AbiCodec (recursive Cairo codec), ERC20, ERC721, PresetFactory |
| `paymaster` | PaymasterRpc (SNIP-29), AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor |
| `provider` | RpcProvider (22+ RPC methods), JsonRpcClient, EventPoller, RequestQueue, ResponseCache, NonceManager |
| `tx` | TransactionBuilder, TransactionHash (V3 INVOKE + DEPLOY_ACCOUNT), CallData encoding |
| `crypto` | BigInt, StarkField, StarkScalarField, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA, FieldFactory |
| `signer` | StarkSigner with RFC 6979 deterministic signing |
| `errors` | StarknetError (typed hierarchy), ErrorCodes (numeric constants) |
| `shared` | interfaces, HexUtils, BufferUtils, ByteArray, TestableDefaults (internal) |

## Project Structure

```
starknet-luau/
├── src/
│   ├── init.luau               # Main entry point / barrel exports (9 namespaces)
│   ├── constants.luau          # Chain IDs, class hashes, token addresses, SDK version
│   ├── crypto/                 # Cryptographic primitives (BigInt, fields, curves, hashes, ECDSA)
│   ├── signer/                 # Stark ECDSA signing (RFC 6979)
│   ├── provider/               # RPC client, event polling, queue, cache, nonce manager
│   ├── tx/                     # Transaction building, hashing, calldata encoding
│   ├── wallet/                 # Account management, key store, onboarding, SNIP-9/12
│   ├── contract/               # ABI-driven contract interface, codec, ERC presets
│   ├── paymaster/              # SNIP-29 paymaster, AVNU, policy, budget, sponsored executor
│   ├── errors/                 # Typed error hierarchy and numeric error codes
│   └── shared/                 # Internal utilities (interfaces, hex, buffer, byte array)
├── tests/                      # Lune test specs (50 spec files, 2,846 tests)
├── examples/                   # Runnable example scripts (13 examples)
├── docs/                       # SPEC.md, ROADMAP.md, and guides
├── .github/workflows/          # CI + Release automation
├── default.project.json        # Rojo project (library)
├── dev.project.json            # Rojo project (development)
├── rokit.toml                  # Toolchain versions
├── wally.toml                  # Package manifest (Wally)
├── pesde.toml                  # Package manifest (Pesde)
└── Makefile                    # Build commands
```

## Development

### Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) v0.6+ (toolchain manager — installs Rojo, Wally, Lune, Selene, StyLua)
- [Pesde](https://pesde.dev) (optional, if using Pesde for dependencies)

### Setup

```bash
rokit install       # Install rojo, wally, lune, selene, stylua
make install        # Install Wally packages + generate types
rojo serve          # Start live sync to Roblox Studio
```

### Commands

```bash
make install        # Install deps via Wally, generate sourcemap + package types
make pesde-install  # Install deps via Pesde
make serve          # Start Rojo live sync
make build          # Build .rbxm model file
make test           # Run tests with Lune
make lint           # Lint with Selene
make fmt            # Format with StyLua
make check          # Run lint + fmt check + test
```

## Contributing

1. Fork the repo
2. Run `rokit install` to set up the toolchain
3. Run `make install` to install dependencies
4. Run `make check` before submitting a PR

## License

[MIT](LICENSE)
