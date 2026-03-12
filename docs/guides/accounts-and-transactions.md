# Accounts & Transactions

Create accounts, sign transactions, and submit on-chain state changes to Starknet from your Roblox game.

## Prerequisites

- Completed [Guide 2: Reading Blockchain Data](reading-blockchain-data.md)
- A funded Starknet Sepolia account — create one with a wallet like [Argent X](https://www.argent.xyz/) or [Braavos](https://braavos.app/), then get free testnet tokens from the [Starknet Faucet](https://starknet-faucet.vercel.app/)
- HttpService enabled in Game Settings

## Key Terms

- **ERC20** — a standard interface for fungible tokens (like in-game currency). ETH and STRK on Starknet are ERC20 tokens.
- **Gas** — the unit of computation cost on Starknet. You pay gas fees for every transaction.
- **Calldata** — the encoded function arguments sent with a transaction.
- **Nonce** — a counter tracking how many transactions an account has sent. Prevents replaying the same transaction twice.
- **Revert** — when a transaction fails on-chain and all its state changes are rolled back. You still pay gas for reverted transactions.
- **Token amounts** — ETH and STRK use 18 decimal places. 1 ETH = 1,000,000,000,000,000,000 (10^18) in its smallest unit. To get a hex amount: multiply the human-readable value by 10^18 and convert to hex. For example, 0.001 ETH = 10^15 = `"0x38D7EA4C68000"`.

## Creating an Account

### From a Private Key

The fastest way to get started. `Account.fromPrivateKey()` derives the on-chain address, creates a signer, and wires everything up internally:

```luau
--!strict
-- ServerScriptService/CreateAccount.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- WARNING: Never hardcode private keys in production code.
-- Use secure storage (DataStoreService, KeyStore, environment config, etc.)
local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

print("Address:", account.address)
print("Public key:", account:getPublicKeyHex())
```

By default this creates an OpenZeppelin account. You can also specify `"argent"` or `"braavos"`:

```luau
local argentAccount = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
	accountType = "argent",
	guardian = "0x0", -- No guardian. A guardian is a secondary key that can help recover the account.
})

local braavosAccount = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
	accountType = "braavos",
})
```

### Manual Construction

If you already have a signer and know the address, use `Account.new()` directly:

```luau
local StarkSigner = StarknetLuau.signer.StarkSigner

local signer = StarkSigner.new("0x_YOUR_PRIVATE_KEY")

local account = Account.new({
	address = "0x_YOUR_KNOWN_ADDRESS",
	signer = signer,
	provider = provider,
})
```

This skips address derivation and uses the address you provide as-is.

## Sending a Transaction

### ERC20 Transfer

The simplest write operation: transfer tokens using the `ERC20` preset with an account attached. Pass the account as the third argument to `ERC20.new()`:

```luau
--!strict
-- ServerScriptService/SendTransfer.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"
local RECIPIENT = "0x_RECIPIENT_ADDRESS_HERE"
local TRANSFER_AMOUNT = "0x38D7EA4C68000" -- 0.001 ETH (1e15 wei)

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

-- Pass the account as the third argument for write access
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

-- transfer() goes through the full transaction lifecycle:
-- nonce fetch -> calldata encoding -> fee estimation -> hash -> sign -> submit
ethToken
	:transfer(RECIPIENT, TRANSFER_AMOUNT)
	:andThen(function(result)
		print("Transaction submitted:", result.transactionHash)

		-- Wait for the transaction to be included in a block
		return account:waitForReceipt(result.transactionHash, {
			retryInterval = 5, -- seconds between polls (default 5)
		})
	end)
	:andThen(function(receipt)
		print("Confirmed in block:", receipt.block_number)
		print("Status:", receipt.finality_status)
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) then
			if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
				warn("Transaction reverted:", err.revertReason or err.message)
			elseif err.code == ErrorCodes.FEE_ESTIMATION_FAILED.code then
				warn("Fee estimation failed -- check your balance")
			else
				warn("Starknet error:", tostring(err))
			end
		else
			warn("Error:", tostring(err))
		end
	end)
```

### Using `account:execute()` Directly

For contracts without presets, or when you want explicit control, build Call objects and pass them to `account:execute()`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

-- Define a minimal ABI for the function you want to call
local CONTRACT_ABI = {
	{
		type = "function",
		name = "submit_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "score", type = "core::integer::u128" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

local gameContract = Contract.new({
	abi = CONTRACT_ABI,
	address = "0x_YOUR_CONTRACT_ADDRESS",
	provider = provider,
	account = account,
})

-- populate() builds a Call object without executing
local call = gameContract:populate("submit_score", { "0x_PLAYER_ADDRESS", "0x2A" })

-- Execute the call
account
	:execute({ call })
	:andThen(function(result)
		print("Submitted:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

A Call object is a table with three fields: `{ contractAddress: string, entrypoint: string, calldata: { string } }`.

## Multicall: Batching Multiple Calls

Multicall lets you bundle multiple contract calls into a single transaction. This is atomic -- either all calls succeed or all revert -- and more gas-efficient than sending them separately.

Use `populate()` on each contract to build Call objects, then pass the array to `account:execute()`:

```luau
--!strict
-- ServerScriptService/BatchTransfer.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

-- Build Call objects without executing
local calls = {}

local recipients = {
	{ address = "0x_RECIPIENT_1", amount = "0xDE0B6B3A7640000" }, -- 1 ETH
	{ address = "0x_RECIPIENT_2", amount = "0x6F05B59D3B20000" }, -- 0.5 ETH
	{ address = "0x_RECIPIENT_3", amount = "0x2386F26FC10000" }, -- 0.01 ETH
}

for _, recipient in recipients do
	local call = ethToken:populate("transfer", {
		recipient.address,
		recipient.amount,
	})
	table.insert(calls, call)
end

print("Batching", #calls, "transfers into one transaction...")

account
	:execute(calls, {
		feeMultiplier = 2.0, -- higher safety buffer for batch transactions
	})
	:andThen(function(result)
		print("Batch submitted:", result.transactionHash)
		return account:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("Batch confirmed in block:", receipt.block_number)
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) then
			if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
				warn("Batch reverted:", err.revertReason or err.message)
			else
				warn("Starknet error:", tostring(err))
			end
		else
			warn("Batch failed:", tostring(err))
		end
	end)
```

You can mix calls to different contracts in the same batch. For example, approve a token and then call a contract that spends it -- all in one transaction.

## Controlling Fees

Every `execute()` call estimates fees automatically with a 1.5x safety buffer. You can tune this per-transaction:

### Fee Multiplier

Adjusts how much buffer is applied to the estimated fee. Higher values reduce the risk of rejection during fee spikes but waste more gas:

```luau
account:execute(calls, {
	feeMultiplier = 1.0, -- exact estimate (risky if fees spike)
})

account:execute(calls, {
	feeMultiplier = 2.0, -- 2x buffer (safer for volatile periods)
})
```

### Max Fee Cap

Sets an absolute ceiling. If the estimated fee exceeds this, the transaction still submits but with a capped `maxAmount` in its resource bounds:

```luau
account:execute(calls, {
	maxFee = "0x2386F26FC10000", -- never pay more than 0.01 ETH
})
```

### Resource Bounds Override

For full control, provide explicit resource bounds. This bypasses fee estimation entirely:

```luau
account:execute(calls, {
	resourceBounds = {
		l1Gas = {
			maxAmount = "0x1000",
			maxPricePerUnit = "0x174876E800",
		},
		l2Gas = {
			maxAmount = "0x0",
			maxPricePerUnit = "0x0",
		},
	},
})
```

## Waiting for Confirmation

After submitting a transaction, poll the network for the receipt:

```luau
account
	:execute(calls)
	:andThen(function(result)
		return account:waitForReceipt(result.transactionHash, {
			retryInterval = 5, -- seconds between polls (default 5)
			maxAttempts = 20, -- give up after this many polls
		})
	end)
	:andThen(function(receipt)
		print("Block:", receipt.block_number)
		print("Status:", receipt.finality_status) -- "ACCEPTED_ON_L2" or "ACCEPTED_ON_L1"
	end)
	:catch(function(err)
		warn("Error:", tostring(err))
	end)
```

## Dry Run: Pre-Flight Check

The `dryRun` option builds and signs the transaction without submitting it. Use this to verify a transaction will succeed before committing:

```luau
account
	:execute(calls, { dryRun = true })
	:andThen(function(result)
		-- result contains the transaction details that would have been submitted
		print("Transaction hash:", result.transactionHash)
		print("Would have submitted successfully")
	end)
	:catch(function(err)
		-- Fee estimation or signing failed -- the transaction would have failed
		warn("Dry run failed:", tostring(err))
	end)
```

Dry run still fetches the nonce and estimates fees, so it exercises the full pipeline short of submission.

## Estimating Fees Without Executing

If you want the fee estimate without building the full transaction, use `account:estimateFee()`:

```luau
-- (continuing from the ERC20 Transfer example above)
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

local call = ethToken:populate("transfer", {
	"0x_RECIPIENT",
	"0x38D7EA4C68000",
})

account
	:estimateFee({ call })
	:andThen(function(estimate)
		-- estimate is the raw fee estimate table from the RPC node
		print("Estimated fee:", estimate)
	end)
	:catch(function(err)
		warn("Estimation failed:", tostring(err))
	end)
```

## Reading Account State

```luau
-- Get the current nonce (how many transactions this account has sent)
account
	:getNonce()
	:andThen(function(nonce)
		print("Current nonce:", nonce) -- "0x0" for new accounts
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

## Complete Example: Game Server Reward System

A complete pattern where the game server sends token rewards to players:

```luau
--!strict
-- ServerScriptService/RewardSystem.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Server-side operator account that pays for transactions
local SERVER_PRIVATE_KEY = "0x_YOUR_SERVER_PRIVATE_KEY"
local serverAccount = Account.fromPrivateKey({
	privateKey = SERVER_PRIVATE_KEY,
	provider = provider,
})

local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider, serverAccount)

-- Map Roblox player IDs to Starknet addresses (in production, use DataStore)
local playerWallets: { [number]: string } = {}

-- RemoteFunction for players to register their Starknet address
local registerWallet = Instance.new("RemoteFunction")
registerWallet.Name = "RegisterWallet"
registerWallet.Parent = ReplicatedStorage

registerWallet.OnServerInvoke = function(player: Player, address: string): boolean
	if type(address) ~= "string" or #address < 10 then
		return false
	end
	playerWallets[player.UserId] = address
	print(player.Name, "registered wallet:", address)
	return true
end

--- Send a STRK reward to a player's registered wallet.
local function sendReward(player: Player, amount: string)
	local walletAddress = playerWallets[player.UserId]
	if not walletAddress then
		warn(player.Name, "has no registered wallet")
		return
	end

	print("Sending", amount, "STRK to", player.Name)

	strkToken
		:transfer(walletAddress, amount)
		:andThen(function(result)
			print("Reward sent to", player.Name, "tx:", result.transactionHash)
			return serverAccount:waitForReceipt(result.transactionHash)
		end)
		:andThen(function(receipt)
			print("Reward confirmed for", player.Name, "block:", receipt.block_number)
		end)
		:catch(function(err)
			if StarknetError.isStarknetError(err) then
				if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
					warn("Reward reverted for", player.Name, err.revertReason or err.message)
				else
					warn("Reward error for", player.Name, tostring(err))
				end
			else
				warn("Reward failed for", player.Name, tostring(err))
			end
		end)
end

-- Clean up on player leave
Players.PlayerRemoving:Connect(function(player: Player)
	playerWallets[player.UserId] = nil
end)

return {
	sendReward = sendReward,
}
```

## Common Mistakes

**Private key must be in [1, N-1].** The curve order N is `0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f`. Keys of zero or >= N throw `KEY_OUT_OF_RANGE` (error code 3003). N-1 is valid.

**Hex normalization matters.** Addresses and class hashes must be `"0x"`-prefixed hex strings. The SDK normalizes them internally via `BigInt.fromHex` -> `toHex`, stripping leading zeros. If you compare addresses yourself, normalize both sides first or use case-insensitive comparison with `string.lower()`.

**Fee multiplier defaults to 1.5x.** This is a safety buffer so your transaction doesn't get rejected if fees spike between estimation and inclusion. Setting it to `1.0` uses the exact estimate, which risks rejection. Setting it too high wastes gas. The default works well for most cases; bump to `2.0` for batch transactions or volatile periods.

**Never hardcode private keys in production.** The examples use inline keys for clarity. In a real game, store keys in DataStore (encrypted via `KeyStore`) or a server-side secret store. See [Guide 5: Player Onboarding](player-onboarding.md) for secure key management.

**`waitForReceipt` polls the RPC node.** Roblox has no WebSocket support, so confirmation uses HTTP polling. The default interval is 5 seconds. Don't set it too low or you'll burn through your rate limit.

**Multicall is atomic.** If any call in the batch reverts, all calls revert. This is usually what you want (e.g., approve + spend), but be aware that one bad call fails the entire batch.

**Concurrent transactions need nonce coordination.** If your game server sends multiple transactions in rapid succession (e.g., several rewards at once), they can fail due to nonce conflicts. The SDK includes a `NonceManager` (used by default) that sequences transactions automatically, but be aware they won't execute in parallel on-chain.

## What's Next

Now that you can read and write on-chain state, [Guide 4: Custom Contracts & ABI Encoding](custom-contracts-and-abi-encoding.md) covers working with any Cairo contract using custom ABIs, complex types (structs, enums, arrays, Option, ByteArray), and event decoding.
