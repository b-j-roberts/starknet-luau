# Getting Started

Get a working RpcProvider connected to Starknet and reading chain data in under 5 minutes.

Starknet is a layer-2 blockchain network built on Ethereum. This SDK lets your Roblox game read and write data on Starknet directly from Luau — no external servers required.

## Prerequisites

- A Roblox game project using [Rojo](https://rojo.space/) for file sync
- [Wally](https://wally.run/) or [pesde](https://pesde.dev/) for package management
- HttpService enabled in Game Settings (Security tab)

## Install the SDK

### Option A: Wally

Add to your `wally.toml`:

```toml
[dependencies]
StarknetLuau = "b-j-roberts/starknet-luau@0.2.0"
```

Then install:

```bash
wally install
```

### Option B: pesde

```bash
pesde add magic/starknet_luau@0.2.0
```

### After installing (Wally only)

If you installed via Wally, generate the Rojo sourcemap and apply type exports:

```bash
rojo sourcemap default.project.json -o sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/
```

If you installed via pesde, type exports are handled automatically — skip this step.

## Server-Only Constraint

All network operations go through Roblox's `HttpService`, which is **only available in server Scripts** (inside `ServerScriptService` or `ServerStorage`). LocalScripts and ModuleScripts running on the client cannot make HTTP requests.

The typical architecture is:

1. **Server**: SDK lives here. Reads blockchain data, submits transactions, manages wallets.
2. **Client**: Sends requests to the server via `RemoteEvents` or `RemoteFunctions`. Never touches the SDK directly.

## Project Setup

Your Rojo project file needs to map the SDK into `ReplicatedStorage` so both server and client code can reference the modules. Add a `StarknetLuau` entry pointing to the installed package:

```json
{
  "name": "my-game",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "StarknetLuau": {
        "$path": "Packages/StarknetLuau"
      },
      "Packages": {
        "$path": "Packages"
      }
    },
    "ServerScriptService": {
      "Scripts": {
        "$path": "src/server"
      }
    }
  }
}
```

## Requiring the SDK

All SDK usage starts with a single `require`. The SDK exports nine namespaces:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

-- Available namespaces:
local crypto    = StarknetLuau.crypto     -- BigInt, hash functions, curve ops
local signer    = StarknetLuau.signer     -- Stark ECDSA signing
local provider  = StarknetLuau.provider   -- RpcProvider, EventPoller
local tx        = StarknetLuau.tx         -- TransactionBuilder, TransactionHash
local wallet    = StarknetLuau.wallet     -- Account, KeyStore, OnboardingManager
local contract  = StarknetLuau.contract   -- Contract, ERC20, ERC721, AbiCodec
local paymaster = StarknetLuau.paymaster  -- PaymasterRpc, SponsoredExecutor
local errors    = StarknetLuau.errors     -- StarknetError, ErrorCodes
local constants = StarknetLuau.constants  -- Chain IDs, token addresses, class hashes
```

You only need to import the namespaces you actually use. Most scripts start with `provider` and `constants`.

## Creating a Provider

`RpcProvider` is the single entry point for all blockchain communication. Create one by passing a `nodeUrl` pointing to a Starknet JSON-RPC endpoint:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

-- Public Sepolia testnet endpoint
-- For production, use a dedicated endpoint from Alchemy, Infura, or Blast
local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})
```

That's it. The provider handles request framing, rate limiting (default 450 requests/minute), and automatic retry on failure internally.

## Your First Calls

Every RpcProvider method returns a **Promise** (from [evaera/promise](https://eryn.io/roblox-lua-promise/)). Use `:andThen()` for the success path and `:catch()` for errors:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Read the current block number
provider
	:getBlockNumber()
	:andThen(function(blockNumber)
		print("Current block:", blockNumber) -- e.g. 123456
	end)
	:catch(function(err)
		warn("Failed to get block number:", tostring(err))
	end)

-- Read the chain ID (returns a hex string)
provider
	:getChainId()
	:andThen(function(chainId)
		print("Chain ID:", chainId) -- "0x534e5f5345504f4c4941" for Sepolia
	end)
	:catch(function(err)
		warn("Failed to get chain ID:", tostring(err))
	end)

-- Read the RPC spec version
provider
	:getSpecVersion()
	:andThen(function(version)
		print("RPC spec version:", version) -- e.g. "0.7.1"
	end)
	:catch(function(err)
		warn("Failed to get spec version:", tostring(err))
	end)
```

## Working with Promises

The SDK uses Promises everywhere because Roblox's HttpService is asynchronous. Here are the three patterns you'll use most:

### Chain dependent calls with `:andThen()`

When one call depends on the result of another, chain them:

```luau
provider
	:getBlockNumber()
	:andThen(function(blockNumber)
		-- Use the block number to fetch that block's details
		-- getBlockWithTxHashes accepts a block number or "latest"
		return provider:getBlockWithTxHashes(tostring(blockNumber))
	end)
	:andThen(function(block)
		print("Block timestamp:", block.timestamp)
		print("Transaction count:", #block.transactions)
	end)
	:catch(function(err)
		warn("Error:", tostring(err))
	end)
```

### Handle errors with `:catch()`

Always attach a `:catch()` handler. Unhandled Promise rejections produce warnings in the Roblox output but won't tell you what went wrong:

```luau
provider
	:getBlockNumber()
	:andThen(function(blockNumber)
		print("Block:", blockNumber)
	end)
	:catch(function(err)
		warn("Something went wrong:", tostring(err))
	end)
```

### Block with `:expect()` (testing only)

`:expect()` blocks the current thread until the Promise resolves and returns the value directly. This is useful in test scripts but **should not be used in production game code** because it freezes the server thread:

```luau
-- Blocks until resolved. Throws on rejection.
local blockNumber = provider:getBlockNumber():expect()
print("Block:", blockNumber)
```

## Verifying Your Connection

Here is a complete script you can drop into `ServerScriptService` to verify everything is wired up correctly:

```luau
--!strict
-- ServerScriptService/VerifyStarknet.server.luau
-- Drop this into ServerScriptService to test your SDK installation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

print("=== starknet-luau connection test ===")
print("SDK version:", Constants.SDK_VERSION)

provider
	:getChainId()
	:andThen(function(chainId)
		if chainId == Constants.SN_SEPOLIA then
			print("Connected to Sepolia testnet")
		elseif chainId == Constants.SN_MAIN then
			print("Connected to Mainnet")
		else
			print("Connected to chain:", chainId)
		end
		return provider:getBlockNumber()
	end)
	:andThen(function(blockNumber)
		print("Latest block:", blockNumber)
		return provider:getSpecVersion()
	end)
	:andThen(function(specVersion)
		print("RPC spec version:", specVersion)
		print("=== connection test passed ===")
	end)
	:catch(function(err)
		warn("=== connection test FAILED ===")
		warn(tostring(err))
	end)
```

If you see `=== connection test passed ===` in the Output window, the SDK is installed and your provider can reach the network.

## Common Mistakes

**HttpService not enabled**: You'll get a permissions error if HttpService isn't turned on. Go to Game Settings > Security > Allow HTTP Requests and enable it.

**Requiring from a LocalScript**: `HttpService:RequestAsync` is server-only. If you try to use the provider from a LocalScript, the request will fail at runtime. Keep all SDK usage on the server.

**Missing `:catch()` handlers**: If a Promise rejects without a `:catch()`, Roblox prints a generic warning that's hard to debug. Always attach error handlers so you can see the actual error message.

**Using `:expect()` in production**: `:expect()` blocks the entire server thread while waiting for the network response. Use `:andThen()` chains in any code that runs during gameplay.

## What's Next

Now that you have a working provider, [Guide 2: Reading Blockchain Data](reading-blockchain-data.md) shows how to query token balances, NFT ownership, and contract state without any signing or accounts.
