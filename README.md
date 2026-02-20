# starknet-luau

Pure Luau SDK for interacting with the Starknet blockchain from Roblox games. Provides cryptographic primitives, account management, transaction building/signing, contract interaction, and RPC connectivity -- all implemented in Luau with no external native dependencies.

## Installation

**Via Wally:**
```toml
[dependencies]
starknet-luau = "b-j-roberts/starknet-luau@0.1.0"
```

**Manual (.rbxm):**
Download the latest `.rbxm` from [Releases](../../releases) and drop it into your project.

## Development

### Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager)

### Setup

```bash
rokit install       # Install rojo, wally, lune, selene, stylua
make install        # Install Wally packages + generate types
rojo serve          # Start live sync to Roblox Studio
```

### Commands

```bash
make install        # Install deps, generate sourcemap + package types
make serve          # Start Rojo live sync
make build          # Build .rbxm model file
make test           # Run tests with Lune
make lint           # Lint with Selene
make fmt            # Format with StyLua
make check          # Run lint + fmt check + test
```

## Quick Start

```luau
local Starknet = require(game.ReplicatedStorage.Packages.StarknetLuau)

-- Create a provider
local provider = Starknet.provider.RpcProvider.new("https://starknet-sepolia.public.blastapi.io")

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

## API Overview

| Module | Description |
|--------|-------------|
| `crypto` | BigInt, StarkField, StarkCurve, Poseidon, Pedersen, Keccak, SHA256, ECDSA |
| `signer` | StarkSigner with RFC 6979 deterministic signing |
| `provider` | JSON-RPC client over HttpService with Promise-based async |
| `tx` | Transaction building, hashing, calldata encoding (V3 INVOKE) |
| `wallet` | Account derivation, nonce management (OZ, Argent) |
| `contract` | ABI-driven contract interface, ERC-20/ERC-721 presets |

## Project Structure

```
starknet-luau/
├── src/
│   ├── init.luau               # Main entry point / barrel exports
│   ├── crypto/                 # Cryptographic primitives
│   ├── signer/                 # Transaction signing
│   ├── provider/               # Starknet RPC client
│   ├── tx/                     # Transaction building
│   ├── wallet/                 # Account management
│   └── contract/               # Contract interaction + presets
├── tests/                      # Lune test specs
├── docs/                       # Spec and roadmap
├── .github/workflows/          # CI + Release automation
├── default.project.json        # Rojo project (library)
├── dev.project.json            # Rojo project (development)
├── rokit.toml                  # Toolchain versions
├── wally.toml                  # Package manifest
└── Makefile                    # Build commands
```

## Contributing

1. Fork the repo
2. Run `rokit install` to set up the toolchain
3. Run `make install` to install dependencies
4. Run `make check` before submitting a PR

## License

[MIT](LICENSE)
