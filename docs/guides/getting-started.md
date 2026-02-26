# Getting Started

This guide walks you through installing starknet-luau and making your first Starknet calls from a Roblox game.

## Prerequisites

- [Roblox Studio](https://www.roblox.com/create) installed
- A Roblox game project (or a new baseplate)
- Basic familiarity with Luau scripting

## Installation

### Option 1: Pesde (Recommended)

Add to your `pesde.toml`:

```toml
[dependencies]
starknet_luau = { name = "magic/starknet_luau", version = "^0.1.0" }
```

Then run:

```bash
pesde install
```

### Option 2: Wally

Add to your `wally.toml`:

```toml
[dependencies]
starknet-luau = "b-j-roberts/starknet-luau@0.1.0"
```

Then run:

```bash
wally install
```

### Option 3: Manual (.rbxm)

1. Download the latest `.rbxm` from the [Releases](https://github.com/b-j-roberts/starknet-luau/releases) page
2. In Roblox Studio, right-click `ReplicatedStorage` > Insert from File
3. Select the downloaded `.rbxm` file

## Enable HttpService

starknet-luau communicates with Starknet RPC nodes over HTTP. You must enable HttpService in your game:

1. In Roblox Studio, open **Game Settings** (Home tab > Game Settings)
2. Go to the **Security** tab
3. Enable **Allow HTTP Requests**

Or via the command bar:

```luau
game:GetService("HttpService").HttpEnabled = true
```

> **Note:** HttpService is only available in server-side scripts (Script, not LocalScript). All Starknet operations must run on the server.

## Project Setup

After installing, require the SDK from a server Script:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Starknet = require(ReplicatedStorage:WaitForChild("StarknetLuau"))
```

The `Starknet` table exposes all modules:

```luau
Starknet.crypto     -- Cryptographic primitives
Starknet.signer     -- Transaction signing
Starknet.provider   -- RPC client
Starknet.tx         -- Transaction building
Starknet.wallet     -- Account management
Starknet.contract   -- Contract interaction + presets
Starknet.constants  -- Chain IDs, token addresses, class hashes
Starknet.errors     -- Structured error types
```

## Create a Provider

The provider is your connection to a Starknet node. All network operations go through it.

```luau
local RpcProvider = Starknet.provider.RpcProvider

local provider = RpcProvider.new({
    nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})
```

### Free RPC Endpoints

| Network | URL |
|---------|-----|
| Sepolia (testnet) | `https://api.zan.top/public/starknet-sepolia` |
| Sepolia (testnet) | `https://free-rpc.nethermind.io/sepolia-juno/` |
| Mainnet | `https://free-rpc.nethermind.io/mainnet-juno/` |

For production use, consider a dedicated RPC provider like [Alchemy](https://www.alchemy.com/starknet), [Infura](https://www.infura.io/), or [Blast](https://blastapi.io/).

## Your First Read: Get Block Number

The simplest call -- fetch the current block number:

```luau
provider:getBlockNumber():andThen(function(blockNumber)
    print("Current Starknet block:", blockNumber)
end):catch(function(err)
    warn("Failed to get block number:", tostring(err))
end)
```

All network operations return **Promises** (via [roblox-lua-promise](https://eryn.io/roblox-lua-promise/)). Use `:andThen()` to handle the result and `:catch()` to handle errors.

## Read a Token Balance

Use the built-in ERC-20 preset to read token balances without writing any ABI:

```luau
local ERC20 = Starknet.contract.ERC20
local Constants = Starknet.constants

-- Create an ERC-20 instance for the STRK token
local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider)

-- Read a balance (returns { low: string, high: string } for u256)
local walletAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

strkToken:balance_of(walletAddress):andThen(function(balance)
    print("STRK Balance:", balance.low)
end):catch(function(err)
    warn("Failed to read balance:", tostring(err))
end)
```

## Send Your First Transaction

To write onchain, you need an **Account** (which holds a private key for signing):

```luau
local Account = Starknet.wallet.Account
local ERC20 = Starknet.contract.ERC20
local Constants = Starknet.constants

-- Create an account from a private key
-- WARNING: Never hardcode private keys in production (see Roblox guide)
local account = Account.fromPrivateKey({
    privateKey = "0xYOUR_PRIVATE_KEY",
    provider = provider,
})

print("Account address:", account.address)

-- Create an ERC-20 instance with the account for write access
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

-- Transfer 0.001 ETH (1e15 wei)
ethToken:transfer("0xRECIPIENT_ADDRESS", "0x38D7EA4C68000")
    :andThen(function(result)
        print("Transaction submitted:", result.transactionHash)
        -- Wait for confirmation
        return account:waitForReceipt(result.transactionHash)
    end)
    :andThen(function(receipt)
        print("Confirmed in block:", receipt.block_number)
    end)
    :catch(function(err)
        warn("Transfer failed:", tostring(err))
    end)
```

Under the hood, this:

1. Fetches the current nonce from the network
2. Encodes the calldata based on the ERC-20 ABI
3. Estimates the transaction fee with a dummy signature
4. Computes the V3 INVOKE transaction hash (Poseidon)
5. Signs with ECDSA (RFC 6979 deterministic k)
6. Submits the signed transaction to the RPC node

## Understanding Promises

starknet-luau uses Promises for all async operations. Here's a quick reference:

```luau
-- Chain operations
provider:getChainId()
    :andThen(function(chainId)
        print("Chain:", chainId)
        return provider:getBlockNumber()
    end)
    :andThen(function(blockNumber)
        print("Block:", blockNumber)
    end)
    :catch(function(err)
        warn("Error:", tostring(err))
    end)

-- Wait synchronously (blocks the thread -- use sparingly)
local blockNumber = provider:getBlockNumber():expect()
```

For more on Promises, see the [roblox-lua-promise documentation](https://eryn.io/roblox-lua-promise/).

## Next Steps

- [Contract Interaction Guide](contracts.md) -- Reading state, writing transactions, multicall
- [Account Management Guide](accounts.md) -- Key generation, address derivation, account types
- [Common Patterns Guide](patterns.md) -- NFT gating, token rewards, leaderboards
- [Roblox Considerations Guide](roblox.md) -- Rate limits, security, server-side patterns
- [Crypto Deep Dive](crypto.md) -- Understanding the cryptographic primitives
- [API Reference](api-reference.md) -- Complete API documentation for all modules
