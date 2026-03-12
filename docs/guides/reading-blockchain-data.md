# Reading Blockchain Data

Query token balances, NFT ownership, contract storage, and block data from Starknet -- no signing or accounts required.

## Prerequisites

- Completed [Guide 1: Getting Started](getting-started.md) -- you have a working `RpcProvider`
- HttpService enabled in Game Settings

## Token Balances with ERC20

The `ERC20` preset wraps the standard OpenZeppelin Cairo ERC-20 ABI so you can read token data with zero boilerplate. No account is needed for read-only calls.

```luau
--!strict
-- ServerScriptService/ReadTokens.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Create ERC-20 instances for ETH and STRK using well-known addresses
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider)

local TARGET_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

-- Read token metadata
ethToken
	:name()
	:andThen(function(name)
		print("Token name:", name) -- "Ether"
	end)
	:catch(function(err)
		warn("Failed to read name:", tostring(err))
	end)

ethToken
	:symbol()
	:andThen(function(symbol)
		print("Symbol:", symbol) -- "ETH"
	end)
	:catch(function(err)
		warn("Failed to read symbol:", tostring(err))
	end)

ethToken
	:decimals()
	:andThen(function(decimals)
		print("Decimals:", decimals) -- "0x12" (18 in hex)
	end)
	:catch(function(err)
		warn("Failed to read decimals:", tostring(err))
	end)

-- Read a balance
ethToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		print("ETH balance (low):", balance.low)
		print("ETH balance (high):", balance.high)
	end)
	:catch(function(err)
		warn("Failed to read balance:", tostring(err))
	end)
```

### Available ERC20 View Methods

| Method | Arguments | Returns |
|--------|-----------|---------|
| `name()` | none | `string` (decoded from felt252) |
| `symbol()` | none | `string` (decoded from felt252) |
| `decimals()` | none | `string` (hex-encoded u8) |
| `total_supply()` | none | `{ low: string, high: string }` |
| `balance_of(account)` | address (hex string) | `{ low: string, high: string }` |
| `allowance(owner, spender)` | two addresses | `{ low: string, high: string }` |

Both snake_case (`balance_of`) and camelCase (`balanceOf`) method names work.

## Understanding u256 Return Values

Starknet represents `u256` as two 128-bit felts. Every method that returns a `u256` gives you a table with `low` and `high` fields, both hex strings:

```luau
ethToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		-- balance = { low = "0x2386f26fc10000", high = "0x0" }
		-- low  = lower 128 bits
		-- high = upper 128 bits (usually "0x0" for normal balances)

		-- Convert to a human-readable number (ETH has 18 decimals)
		local rawWei = tonumber(balance.low) or 0
		local ethAmount = rawWei / (10 ^ 18)
		print(string.format("Balance: %.6f ETH", ethAmount))
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

For most game use cases, `balance.high` will be `"0x0"` and you can work with `balance.low` alone. If you need to handle values above 2^128 (extremely rare), combine both fields.

## NFT Ownership with ERC721

The `ERC721` preset works the same way as `ERC20` -- create an instance with an address and provider, then call view methods:

```luau
--!strict
-- ServerScriptService/CheckNFT.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC721 = StarknetLuau.contract.ERC721

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local NFT_CONTRACT = "0x_YOUR_NFT_COLLECTION_ADDRESS"
local nftContract = ERC721.new(NFT_CONTRACT, provider)

-- Check how many NFTs an address owns
local PLAYER_ADDRESS = "0x_PLAYER_STARKNET_ADDRESS"

nftContract
	:balance_of(PLAYER_ADDRESS)
	:andThen(function(balance)
		local count = tonumber(balance.low) or 0
		print("NFTs owned:", count)
	end)
	:catch(function(err)
		warn("Failed to check NFT balance:", tostring(err))
	end)

-- Check who owns a specific token
local TOKEN_ID = "0x1" -- token ID as hex string

nftContract
	:owner_of(TOKEN_ID)
	:andThen(function(owner)
		print("Token owner:", owner) -- hex address
	end)
	:catch(function(err)
		warn("Failed to check owner:", tostring(err))
	end)

-- Read the token URI (metadata link)
nftContract
	:token_uri(TOKEN_ID)
	:andThen(function(uri)
		print("Token URI:", uri)
	end)
	:catch(function(err)
		warn("Failed to read URI:", tostring(err))
	end)
```

### Available ERC721 View Methods

| Method | Arguments | Returns |
|--------|-----------|---------|
| `name()` | none | `string` |
| `symbol()` | none | `string` |
| `balance_of(owner)` | address | `{ low: string, high: string }` |
| `owner_of(tokenId)` | hex string | `string` (address) |
| `get_approved(tokenId)` | hex string | `string` (address) |
| `is_approved_for_all(owner, operator)` | two addresses | hex `"0x1"` (true) or `"0x0"` (false) |
| `token_uri(tokenId)` | hex string | `string` (decoded ByteArray) |
| `supports_interface(interfaceId)` | felt252 hex | hex `"0x1"` or `"0x0"` |

## Custom Contract Reads

For contracts that aren't ERC-20 or ERC-721, use `Contract.new()` with a custom ABI. Define only the functions you need:

```luau
--!strict
-- ServerScriptService/ReadLeaderboard.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Contract = StarknetLuau.contract.Contract

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Define the ABI for the functions you want to call
local LEADERBOARD_ABI = {
	{
		type = "function",
		name = "get_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "get_top_player",
		inputs = {},
		outputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "get_high_score",
		inputs = {},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
}

local LEADERBOARD_ADDRESS = "0x_YOUR_LEADERBOARD_CONTRACT"

-- No account needed -- only reading
local leaderboard = Contract.new({
	abi = LEADERBOARD_ABI,
	address = LEADERBOARD_ADDRESS,
	provider = provider,
})

-- Dynamic dispatch: view functions are callable directly on the contract
leaderboard
	:get_score("0x_SOME_PLAYER_ADDRESS")
	:andThen(function(score)
		local numericScore = tonumber(score) or 0
		print("Player score:", numericScore)
	end)
	:catch(function(err)
		warn("Failed to read score:", tostring(err))
	end)

leaderboard
	:get_high_score()
	:andThen(function(score)
		local numericScore = tonumber(score) or 0
		print("High score:", numericScore)
	end)
	:catch(function(err)
		warn("Failed to read high score:", tostring(err))
	end)
```

The `Contract` class parses the ABI and creates callable methods automatically. Functions with `state_mutability = "view"` become read-only calls routed through `provider:call()`. You can also call them explicitly with `contract:call("method_name", { args })`.

### Introspection

```luau
-- List all functions the contract exposes
local functions = leaderboard:getFunctions()
print("Available functions:", table.concat(functions, ", "))

-- Check if a specific function exists
if leaderboard:hasFunction("get_score") then
	print("get_score is available")
end
```

## Raw Provider Calls

When you need lower-level access, use the provider methods directly.

### Read Contract Storage

`getStorageAt` reads a single storage slot by its key:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local CONTRACT_ADDRESS = "0x_YOUR_CONTRACT"
local STORAGE_KEY = "0x0" -- storage slot key (felt252)

provider
	:getStorageAt(CONTRACT_ADDRESS, STORAGE_KEY)
	:andThen(function(value)
		print("Storage value:", value) -- hex string
	end)
	:catch(function(err)
		warn("Failed to read storage:", tostring(err))
	end)
```

### Raw `provider:call()`

For direct low-level contract calls without ABI decoding:

```luau
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField

-- Compute the function selector from its name
local selector = StarkField.toHex(Keccak.getSelectorFromName("get_score"))

provider
	:call({
		contract_address = "0x_YOUR_CONTRACT",
		entry_point_selector = selector,
		calldata = { "0x_PLAYER_ADDRESS" },
	})
	:andThen(function(result)
		-- result is an array of hex strings (raw felts)
		print("Raw result:", result[1])
	end)
	:catch(function(err)
		warn("Call failed:", tostring(err))
	end)
```

### Identify a Contract

`getClassHashAt` returns the class hash deployed at an address, useful for identifying what type of contract lives at an address:

```luau
provider
	:getClassHashAt("0x_SOME_CONTRACT_ADDRESS")
	:andThen(function(classHash)
		print("Class hash:", classHash)

		-- Compare against known class hashes
		local Constants = StarknetLuau.constants
		if classHash == Constants.OZ_ACCOUNT_CLASS_HASH then
			print("This is an OpenZeppelin account")
		end
	end)
	:catch(function(err)
		warn("Failed to get class hash:", tostring(err))
	end)
```

## Block Queries

Read block data to inspect transactions and chain state:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Get the latest block with just transaction hashes (lighter response)
provider
	:getBlockWithTxHashes()
	:andThen(function(block)
		print("Block number:", block.block_number)
		print("Block hash:", block.block_hash)
		print("Timestamp:", block.timestamp)
		print("Transaction count:", #block.transactions)
	end)
	:catch(function(err)
		warn("Failed to get block:", tostring(err))
	end)

-- Get a specific block by number (pass as string)
provider
	:getBlockWithTxHashes("100000")
	:andThen(function(block)
		print("Block 100000 hash:", block.block_hash)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)

-- Get a block with full transaction details (heavier response)
provider
	:getBlockWithTxs()
	:andThen(function(block)
		print("Block:", block.block_number)
		for i, tx in block.transactions do
			print(string.format("  Tx %d: %s (type: %s)", i, tx.transaction_hash, tx.type))
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

### Block Method Summary

| Method | Returns |
|--------|---------|
| `getBlockNumber()` | Latest block number (number) |
| `getBlockWithTxHashes(blockId?)` | Block with transaction hash strings |
| `getBlockWithTxs(blockId?)` | Block with full transaction objects |
| `getBlockWithReceipts(blockId?)` | Block with transactions and their receipts |

All block methods accept an optional `blockId` string. Omit it for `"latest"`, or pass a block number as a string.

## Constants

The `constants` module provides well-known addresses and chain IDs so you don't have to hardcode them:

```luau
local Constants = StarknetLuau.constants

-- Chain IDs
Constants.SN_MAIN     -- "0x534e5f4d41494e" (Mainnet)
Constants.SN_SEPOLIA  -- "0x534e5f5345504f4c4941" (Sepolia)

-- Token addresses (same on Mainnet and Sepolia)
Constants.ETH_TOKEN_ADDRESS   -- ETH ERC-20 contract
Constants.STRK_TOKEN_ADDRESS  -- STRK ERC-20 contract

-- Account class hashes
Constants.OZ_ACCOUNT_CLASS_HASH      -- OpenZeppelin Account
Constants.ARGENT_ACCOUNT_CLASS_HASH  -- Argent X Account
Constants.BRAAVOS_ACCOUNT_CLASS_HASH -- Braavos Account

-- SDK version
Constants.SDK_VERSION  -- "0.2.0"
```

## Practical Pattern: NFT-Gated Game Content

A common use case is checking NFT ownership before granting access to exclusive content. Here's a complete pattern using a `RemoteFunction` so players can submit their Starknet address from a client UI:

```luau
--!strict
-- ServerScriptService/NFTGate.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC721 = StarknetLuau.contract.ERC721

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local NFT_CONTRACT = "0x_YOUR_NFT_COLLECTION_ADDRESS"
local nftContract = ERC721.new(NFT_CONTRACT, provider)

-- Track verified players
local verifiedPlayers: { [number]: boolean } = {}

-- Create the RemoteFunction for client -> server verification
local verifyRemote = Instance.new("RemoteFunction")
verifyRemote.Name = "VerifyStarknetNFT"
verifyRemote.Parent = ReplicatedStorage

verifyRemote.OnServerInvoke = function(player: Player, address: string): boolean
	-- Validate input
	if type(address) ~= "string" or #address < 10 then
		return false
	end

	-- Check NFT balance -- :expect() is safe here because
	-- OnServerInvoke runs in its own coroutine
	local hasNFT = nftContract
		:balance_of(address)
		:andThen(function(balance)
			local count = tonumber(balance.low) or 0
			return count >= 1
		end)
		:catch(function(err)
			warn("NFT check failed for", player.Name, tostring(err))
			return false
		end)
		:expect()

	if hasNFT then
		verifiedPlayers[player.UserId] = true
		print(player.Name, "verified -- granting NFT holder access")
	end

	return hasNFT
end

-- Clean up on player leave
Players.PlayerRemoving:Connect(function(player: Player)
	verifiedPlayers[player.UserId] = nil
end)

-- Expose for other server scripts
return {
	isPlayerVerified = function(player: Player): boolean
		return verifiedPlayers[player.UserId] == true
	end,
}
```

Other server scripts can then check `isPlayerVerified(player)` before granting access to exclusive areas, items, or abilities.

## Common Mistakes

**u256 is not a single number.** Methods like `balance_of` and `total_supply` return `{ low = "0x...", high = "0x..." }`, not a single hex string. Always read `balance.low` for the value. Accessing the result directly as a string will give you a table reference.

**Precision loss with `tonumber()`.** Lua numbers are 64-bit floats (f64), which lose precision above 2^53 (~9 quadrillion). For ETH balances this means accuracy degrades above ~9000 ETH. For display purposes this is usually fine, but for exact comparisons on large values use hex string comparison or the SDK's `BigInt` module.

**Addresses must be hex strings.** All address parameters expect `"0x"`-prefixed hex strings. Passing a plain number or forgetting the prefix will cause the RPC call to fail.

**`getBlockWithTxs` is heavy.** If you only need transaction hashes, use `getBlockWithTxHashes` instead. The full transaction version returns much more data and is slower.

## What's Next

Now that you can read on-chain state, [Guide 3: Accounts & Transactions](accounts-and-transactions.md) shows how to create accounts, sign transactions, and write state changes to Starknet.
