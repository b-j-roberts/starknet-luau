# starknet-luau

[![CI](https://github.com/b-j-roberts/starknet-luau/actions/workflows/ci.yml/badge.svg)](https://github.com/b-j-roberts/starknet-luau/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.2.0-blue)](https://github.com/b-j-roberts/starknet-luau/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Pure Luau SDK for interacting with the Starknet blockchain from Roblox games.

Starknet is a Layer-2 Blockchain built on zero-knowledge proofs, designed for modern use cases like gaming! It lets your game write tamper-proof data (player-owned items, verifiable leaderboards, cross-game economies) to a public blockchain in a way that is completely abstracted from your users. They simply play your game, and unlock true ownership of their in-game assets.

This SDK provides account management, player onboarding, transaction building/signing, paymaster-sponsored transactions, and RPC connectivity -- all implemented in Luau with no external servers needed.

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

-- Create a provider connected to Starknet Sepolia testnet
local provider = Starknet.provider.RpcProvider.new({
    nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Read the latest block number
provider:getBlockNumber():andThen(function(blockNumber)
    print("Current block:", blockNumber)
end)

-- Read a token balance
local eth = Starknet.contract.ERC20.new(Starknet.constants.ETH_TOKEN_ADDRESS, provider)
eth:balanceOf(accountAddress):andThen(function(balance)
    print("Balance:", balance)
end)
```

**Sending a transaction:**

```luau
-- Create an account from a private key
local account = Starknet.wallet.Account.fromPrivateKey({
    privateKey = privateKey,
    provider = provider,
})

-- Transfer tokens (builds, signs, and submits in one call)
account:execute({
    {
        contractAddress = Starknet.constants.ETH_TOKEN_ADDRESS,
        entrypoint = "transfer",
        calldata = { recipientAddress, "0x38D7EA4C68000", "0x0" }, -- 0.001 ETH
    },
}):andThen(function(result)
    print("Transaction hash:", result.transaction_hash)
end)
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/guides/getting-started.md) | Installation, basic setup, reading chain data |
| [Reading Blockchain Data](docs/guides/reading-blockchain-data.md) | Token balances, NFT ownership, contract storage, block data |
| [Accounts & Transactions](docs/guides/accounts-and-transactions.md) | Create accounts, sign transactions, submit state changes |
| [Custom Contracts & ABI Encoding](docs/guides/custom-contracts-and-abi-encoding.md) | ABI-driven interaction, complex Cairo types, encode/decode |
| [Player Onboarding](docs/guides/player-onboarding.md) | Key generation, encrypted storage, wallet deployment lifecycle |
| [Sponsored Transactions](docs/guides/sponsored-transactions.md) | Gasless transactions via paymaster integration |
| [Events & Real-Time Data](docs/guides/events-and-real-time-data.md) | Event polling, live leaderboards, trade notifications |
| [Production Configuration](docs/guides/production-configuration.md) | Request batching, caching, nonce management, monitoring |
| [Cryptography & Primitives](docs/guides/cryptography-and-low-level-primitives.md) | Hash functions, field arithmetic, curve operations, signing |
| [API Reference](docs/guides/api-reference.md) | Complete method-by-method reference for all modules |

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

## Inspirations

- [starknet.js](https://github.com/starknet-io/starknet.js) -- The JavaScript SDK for Starknet, used as the primary reference for API design and test vectors
- [rbx-cryptography](https://github.com/daily3014/rbx-cryptography) -- Pure Luau cryptographic primitives for Roblox

## License

[MIT](LICENSE)
