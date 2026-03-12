# Player Onboarding

Generate, encrypt, store, and deploy player wallets for your Roblox game -- the full onboarding lifecycle from first join to deployed account.

## Prerequisites

- Completed [Guide 3: Accounts & Transactions](accounts-and-transactions.md)
- HttpService enabled in Game Settings
- A published Roblox experience (DataStoreService requires a published place)

## How Account Deployment Works on Starknet

Starknet accounts are smart contracts. Creating one for a player is a three-phase process:

1. **Compute the address.** The address is derived deterministically from the class hash, constructor calldata, and salt. It exists before any on-chain transaction -- this is called the *counterfactual address*.
2. **Fund the address.** The counterfactual address must hold enough STRK/ETH to pay deployment gas. (Or use a paymaster to skip this -- see [Guide 6](sponsored-transactions.md).)
3. **Submit DEPLOY_ACCOUNT.** This creates the contract instance on-chain. The account is now live.

The SDK handles all three phases. Your job is choosing how to manage keys and when to deploy.

## KeyStore: Encrypted Key Persistence

`KeyStore` generates private keys, encrypts them with a server secret, and persists them in Roblox DataStoreService. Each player gets one encrypted record keyed by their UserId.

This is a **custodial model** -- your game server holds the keys. Players never see their private key.

### Setting Up KeyStore

```luau
--!strict
-- ServerScriptService/WalletSetup.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Server secret for encrypting player private keys.
-- MUST be at least 64 hex characters (32 bytes), not all zeros.
-- WARNING: If you lose this secret, all encrypted keys become unrecoverable.
local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"

local keyStore = KeyStore.new({
	serverSecret = SERVER_SECRET,
	dataStoreName = "StarknetPlayerKeys", -- DataStore name (customizable)
	accountType = "oz",                   -- OpenZeppelin accounts (default)
})
```

The `serverSecret` is used to derive HMAC-SHA256 keystreams for encryption. Keep it in a secure server-side config -- never expose it to clients.

### Creating and Loading Player Accounts

`getOrCreate()` is the primary onboarding API. It checks DataStore for an existing record; if none exists, it generates a new key, encrypts it, stores it, and returns the hydrated Account:

```luau
--!strict
-- ServerScriptService/PlayerWallet.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore
local StarknetError = StarknetLuau.errors.StarknetError

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"

local keyStore = KeyStore.new({
	serverSecret = SERVER_SECRET,
})

local activeAccounts: { [number]: any } = {}

Players.PlayerAdded:Connect(function(player: Player)
	local ok, err = pcall(function()
		local result = keyStore:getOrCreate(player.UserId, provider)
		activeAccounts[player.UserId] = result.account

		if result.isNew then
			print(`[Wallet] Created new wallet for {player.Name}: {result.account.address}`)
		else
			print(`[Wallet] Loaded existing wallet for {player.Name}: {result.account.address}`)
		end
	end)

	if not ok then
		if StarknetError.isStarknetError(err) then
			warn(`[Wallet] Starknet error for {player.Name}: {tostring(err)}`)
		else
			warn(`[Wallet] Failed for {player.Name}: {tostring(err)}`)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	activeAccounts[player.UserId] = nil
end)
```

### Other KeyStore Methods

```luau
-- Generate a new key, encrypt, store, and return a hydrated Account
-- (getOrCreate wraps this -- use generateAndStore when you know it's a new player)
local result = keyStore:generateAndStore(playerId, provider)
-- result = { account: Account, address: string }

-- Check if a player has a stored key (no decryption, no network)
local exists: boolean = keyStore:hasAccount(playerId)

-- Load an existing account (returns nil if no record)
local account = keyStore:loadAccount(playerId, provider)

-- Read metadata without decryption (address, createdAt, deployedAt)
local record = keyStore:getRecord(playerId)

-- Mark an account as deployed (idempotent)
keyStore:markDeployed(playerId)

-- Check deployment status (no network call)
local deployed: boolean = keyStore:isDeployed(playerId)

-- Delete a player's key (GDPR Right to Erasure)
keyStore:deleteKey(playerId)
```

### Rotating the Server Secret

If your server secret is compromised, re-encrypt all player keys with a new secret:

```luau
--!strict
local playerIds = { 12345, 67890, 11111 } -- all player IDs with stored keys

local OLD_SECRET = "0x_OLD_SECRET_HEX"
local NEW_SECRET = "0x_NEW_SECRET_HEX"

local result = keyStore:rotateSecret(OLD_SECRET, NEW_SECRET, playerIds)
print("Rotated:", result.rotated)
for _, failure in result.failed do
	warn("Failed player:", failure.playerId, failure.error)
end
```

After rotation, `keyStore` internally updates to use the new secret for all subsequent operations.

## Deploying Player Accounts

An account address exists before deployment, but it can't send transactions until the DEPLOY_ACCOUNT transaction creates it on-chain.

### Manual Deployment

If you manage keys yourself (without OnboardingManager), deploy with `account:deployAccount()`:

```luau
--!strict
-- ServerScriptService/DeployPlayer.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local PRIVATE_KEY = "0x_PLAYER_PRIVATE_KEY"

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
	accountType = "oz",
})

print("Counterfactual address:", account.address)

-- Estimate deployment fees without deploying
account
	:estimateDeployAccountFee()
	:andThen(function(estimate)
		print("Estimated deploy fee:", estimate)
	end)
	:catch(function(err)
		warn("Fee estimate failed:", tostring(err))
	end)

-- deployAccount() is idempotent: if the account is already deployed,
-- it returns { alreadyDeployed = true } without submitting a transaction.
account
	:deployAccount({
		waitForConfirmation = true, -- block until included in a block (default)
	})
	:andThen(function(result)
		if result.alreadyDeployed then
			print("Account was already deployed")
		else
			print("Deployed! Tx:", result.transactionHash)
		end
		print("Address:", result.contractAddress)
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) then
			if err.code == ErrorCodes.FEE_ESTIMATION_FAILED.code then
				warn("Fee estimation failed -- is the account funded?")
			else
				warn("Deploy error:", tostring(err))
			end
		else
			warn("Error:", tostring(err))
		end
	end)
```

### Checking Funding Requirements

Before deploying (without a paymaster), the counterfactual address must hold enough tokens to pay gas. Use the static helpers to check:

```luau
--!strict
local Account = StarknetLuau.wallet.Account
local Constants = StarknetLuau.constants

-- Check if the account has enough balance for deployment
Account.checkDeploymentBalance({
	provider = provider,
	address = account.address,
	classHash = Constants.OZ_ACCOUNT_CLASS_HASH,
	constructorCalldata = { account:getPublicKeyHex() },
	salt = account:getPublicKeyHex(),
})
	:andThen(function(info)
		print("Balance:", info.balance)
		print("Estimated fee:", info.estimatedFee)
		print("Has sufficient balance:", info.hasSufficientBalance)
		if not info.hasSufficientBalance then
			print("Deficit:", info.deficit)
		end
	end)
	:catch(function(err)
		warn("Check failed:", tostring(err))
	end)
```

For a simpler API that computes the address for you:

```luau
-- getDeploymentFundingInfo derives the address from the public key
Account.getDeploymentFundingInfo({
	publicKey = account:getPublicKeyHex(),
	provider = provider,
	accountType = "oz", -- defaults to "oz"
})
	:andThen(function(info)
		print("Address:", info.address)
		print("Estimated fee:", info.estimatedFee)
		print("Token:", info.token)              -- "STRK"
		print("Token address:", info.tokenAddress)
	end)
	:catch(function(err)
		warn("Error:", tostring(err))
	end)
```

## Account Types

The SDK supports three account implementations out of the box:

| Type | `AccountType` | Class Hash | Constructor |
|------|--------------|------------|-------------|
| OpenZeppelin | `AccountType.OZ` | `0x061dac...` | `{ publicKey }` |
| Argent X | `AccountType.Argent` | `0x03607...` | `{ 0x0, ownerKey, 0x0 }` (no guardian) |
| Braavos | `AccountType.Braavos` | `0x03d16...` | `{ publicKey }` |

### Using Account Types

```luau
--!strict
local AccountType = StarknetLuau.wallet.AccountType

-- Each type is callable -- it builds constructor calldata from a public key
local ozCalldata = AccountType.OZ("0xPUBKEY")
-- → { "0xPUBKEY" }

local argentCalldata = AccountType.Argent("0xOWNER_KEY")
-- → { "0x0", "0xOWNER_KEY", "0x0" }

-- Argent with a guardian key
local argentGuardedCalldata = AccountType.Argent("0xOWNER_KEY", "0xGUARDIAN_KEY")
-- → { "0x0", "0xOWNER_KEY", "0x1", "0x0", "0xGUARDIAN_KEY" }

local braavosCalldata = AccountType.Braavos("0xPUBKEY")
-- → { "0xPUBKEY" }
```

### Custom Account Types

When new contract versions are deployed with different class hashes, register them with `AccountType.custom()`:

```luau
--!strict
local AccountType = StarknetLuau.wallet.AccountType

local myAccountType = AccountType.custom({
	type = "oz_v2",
	classHash = "0x_NEW_OZ_CLASS_HASH",
	buildCalldata = function(publicKey: string): { string }
		return { publicKey }
	end,
})

-- Use it like any built-in type
local calldata = myAccountType("0xPUBKEY") -- { "0xPUBKEY" }
```

### Detecting Account Types

If you encounter an existing on-chain account and need to identify its type, use `Account.detectAccountType()`:

```luau
local Constants = StarknetLuau.constants

-- Detect from a known class hash
local accountType = Account.detectAccountType(Constants.OZ_ACCOUNT_CLASS_HASH)
print(accountType) -- "oz"

local argentType = Account.detectAccountType(Constants.ARGENT_ACCOUNT_CLASS_HASH)
print(argentType) -- "argent"

-- Returns nil for unknown class hashes
local unknown = Account.detectAccountType("0x_SOME_UNKNOWN_HASH")
print(unknown) -- nil
```

This is useful when loading accounts from chain state where you know the address and class hash but not which implementation was used.

### Lookup by Name

```luau
local ozType = AccountType.get("oz")       -- returns AccountType.OZ
local argentType = AccountType.get("argent") -- returns AccountType.Argent
```

## AccountFactory: Batch Account Creation

`AccountFactory` creates multiple pre-deployment accounts with unique key pairs. Useful for pre-generating wallets during game setup or batch-deploying accounts for a game launch.

### Creating Accounts in Batch

```luau
--!strict
-- ServerScriptService/BatchSetup.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local AccountFactory = StarknetLuau.wallet.AccountFactory
local AccountType = StarknetLuau.wallet.AccountType
local StarkSigner = StarknetLuau.signer.StarkSigner

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local signer = StarkSigner.new("0x_YOUR_PRIVATE_KEY")

local factory = AccountFactory.new(provider, AccountType.OZ, signer)

-- batchCreate requires either privateKeys or a keyGenerator
local accounts = factory:batchCreate(5, {
	keyGenerator = function(): string
		-- In production, use a cryptographically secure random key generator.
		-- KeyStore.generateAndStore does this internally if you use OnboardingManager.
		return "0x" .. string.format("%064x", math.random(1, 2^53))
	end,
})

for i, entry in accounts do
	print(`Account {i}: {entry.address}`)
end
```

Each entry in the array has:
- `account` -- pre-deployment Account instance
- `address` -- counterfactual address (hex string)
- `signer` -- the StarkSigner for this account
- `deployTx(options?)` -- convenience function that calls `account:deployAccount(options)`

### Batch Deployment

After accounts are funded (or using a paymaster), deploy them all:

```luau
--!strict
factory
	:batchDeploy(accounts, {
		maxConcurrency = 1,  -- sequential (default), increase for parallel deploys
		waitForConfirmation = true,
		onDeployProgress = function(index: number, total: number, result: any)
			print(`[{index}/{total}] {result.address}: {result.status}`)
		end,
	})
	:andThen(function(summary)
		print("Deployed:", summary.deployed)
		print("Skipped (already deployed):", summary.skipped)
		print("Failed:", summary.failed)
	end)
	:catch(function(err)
		warn("Batch deploy error:", tostring(err))
	end)
```

The summary contains:
- `deployed` -- number of newly deployed accounts
- `skipped` -- number already deployed (idempotent)
- `failed` -- number of failures
- `results` -- array of `{ index, address, transactionHash?, status, error? }` per account

## OnboardingManager: One-Call Player Setup

`OnboardingManager` composes KeyStore + deployment into a single `onboard()` call. It handles the complete lifecycle: generate key, encrypt, store, deploy, mark deployed.

### Basic Setup (Self-Funded Deployment)

```luau
--!strict
-- ServerScriptService/Onboarding.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore
local OnboardingManager = StarknetLuau.wallet.OnboardingManager
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"

local keyStore = KeyStore.new({
	serverSecret = SERVER_SECRET,
})

local onboarding = OnboardingManager.new({
	keyStore = keyStore,
	provider = provider,
	waitForConfirmation = true, -- wait for deploy to confirm (default)
})

local activeAccounts: { [number]: any } = {}

Players.PlayerAdded:Connect(function(player: Player)
	local ok, result = pcall(function()
		return onboarding:onboard(player.UserId)
	end)

	if not ok then
		if StarknetError.isStarknetError(result) then
			warn(`[Onboard] Error for {player.Name}: {tostring(result)}`)
		else
			warn(`[Onboard] Failed for {player.Name}: {tostring(result)}`)
		end
		return
	end

	activeAccounts[player.UserId] = result.account
	print(`[Onboard] {player.Name} ready at {result.address}`)
	print(`  New: {result.isNew}, Deployed: {result.wasDeployed}, Already: {result.alreadyDeployed}`)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	activeAccounts[player.UserId] = nil
	-- Only call removePlayer() for GDPR key deletion.
	-- Normal departures just clear the in-memory reference.
end)

-- Handle players already in the server (late-loading scripts)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		-- same logic as PlayerAdded handler
	end)
end
```

### Paymaster-Sponsored Setup (Gasless)

To deploy accounts without prefunding, pass `paymasterDetails`:

```luau
--!strict
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster

local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = "YOUR_AVNU_API_KEY",
})

local onboarding = OnboardingManager.new({
	keyStore = keyStore,
	provider = provider,
	paymasterDetails = {
		paymaster = paymaster,
		feeMode = { mode = "sponsored" },
	},
	waitForConfirmation = false, -- faster join times
})
```

With a paymaster, players pay zero gas. No prefunding step is needed. This is the recommended pattern for production games. See [Guide 6: Sponsored Transactions](sponsored-transactions.md) for full paymaster configuration.

### OnboardingResult

`onboard()` returns an `OnboardingResult` table:

| Field | Type | Description |
|-------|------|-------------|
| `account` | Account | Hydrated Account instance, ready to use |
| `address` | string | On-chain address (hex) |
| `isNew` | boolean | `true` if a new key was generated this call |
| `wasDeployed` | boolean | `true` if deployment happened this call |
| `alreadyDeployed` | boolean | `true` if account was already deployed |
| `transactionHash` | string? | Deploy tx hash (nil if already deployed) |
| `trackingId` | string? | Paymaster tracking ID (if applicable) |

### Querying Status

Check a player's onboarding state without decryption or RPC calls:

```luau
local status = onboarding:getStatus(player.UserId)
-- status.hasAccount: boolean  -- key exists in DataStore
-- status.isDeployed: boolean  -- marked as deployed
-- status.address: string?     -- counterfactual address (nil if no account)
```

This reads metadata only -- no decryption, no network. Use it for UI display ("Wallet Ready" vs "Setting Up...").

### Retrying Failed Deployments

If a deployment failed (network error, insufficient gas), retry with `ensureDeployed()`:

```luau
local ok, result = pcall(function()
	return onboarding:ensureDeployed(player.UserId)
end)

if ok then
	if result.alreadyDeployed then
		print("Account was already deployed")
	else
		print("Deployed now! Tx:", result.transactionHash)
	end
end
```

`ensureDeployed()` errors if no KeyStore record exists for the player -- call `onboard()` first.

### Removing a Player

```luau
-- Deletes the encrypted key from DataStore (GDPR Right to Erasure)
onboarding:removePlayer(player.UserId)
```

For normal player departures (leaving the server), just clear the in-memory reference. Only call `removePlayer()` for permanent key deletion (e.g., GDPR requests).

## Complete Example: Production Onboarding System

This ties together KeyStore, OnboardingManager, paymaster-sponsored deployment, status checks, and the Roblox player lifecycle:

```luau
--!strict
-- ServerScriptService/PlayerOnboarding.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore
local OnboardingManager = StarknetLuau.wallet.OnboardingManager
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"
local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"
local AVNU_API_KEY = "YOUR_AVNU_API_KEY"

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

local keyStore = KeyStore.new({
	serverSecret = SERVER_SECRET,
	dataStoreName = "StarknetPlayerKeys",
	accountType = "oz",
})

local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = AVNU_API_KEY,
})

local onboarding = OnboardingManager.new({
	keyStore = keyStore,
	provider = provider,
	paymasterDetails = {
		paymaster = paymaster,
		feeMode = { mode = "sponsored" },
	},
	waitForConfirmation = false,
})

local activeAccounts: { [number]: any } = {}

local function onPlayerAdded(player: Player)
	local playerId = player.UserId
	print(`[Onboard] {player.Name} (ID: {playerId}) joined`)

	local ok, result = pcall(function()
		return onboarding:onboard(playerId)
	end)

	if not ok then
		if StarknetError.isStarknetError(result) then
			if result.code == ErrorCodes.KEY_STORE_ERROR.code then
				warn(`[Onboard] KeyStore error for {player.Name}: {result.message}`)
			elseif result.code == ErrorCodes.ONBOARDING_ERROR.code then
				warn(`[Onboard] Onboarding error for {player.Name}: {result.message}`)
			else
				warn(`[Onboard] Starknet error for {player.Name}: {tostring(result)}`)
			end
		else
			warn(`[Onboard] Failed for {player.Name}: {tostring(result)}`)
		end
		return
	end

	activeAccounts[playerId] = result.account
	print(`[Onboard] {player.Name} onboarded at {result.address}`)
	print(`  New: {result.isNew}, Deployed: {result.wasDeployed}, Already: {result.alreadyDeployed}`)
end

local function onPlayerRemoving(player: Player)
	activeAccounts[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[Onboard] Player onboarding system initialized")
```

## Common Mistakes

**DataStore requires a published place.** `KeyStore` uses `DataStoreService`, which only works in published Roblox experiences. In Studio, inject a mock DataStore via the `_dataStore` config field for testing.

**Server secret loss is catastrophic.** If you lose the `serverSecret`, all encrypted keys become unrecoverable. There is no recovery path. Store it securely and back it up.

**Server secret must be at least 64 hex characters.** Shorter secrets or all-zeros are rejected with `KEY_STORE_SECRET_INVALID` (error code 8002). Use a 32-byte (64 hex char) or longer value.

**`onboard()` is idempotent but `removePlayer()` is destructive.** Calling `onboard()` multiple times for the same player is safe -- it loads the existing key. But `removePlayer()` permanently deletes the encrypted key from DataStore. Only call it for GDPR erasure requests, not normal player departures.

**Deployment requires funding (without a paymaster).** A counterfactual address can't deploy itself for free. Either prefund the address with STRK, or use a paymaster for gasless deployment. The `FEE_ESTIMATION_FAILED` error usually means the account is unfunded.

**`deployAccount()` is idempotent.** It checks `getNonce()` first. If the call succeeds (account responds), it returns `{ alreadyDeployed = true }` without submitting a transaction. Safe to retry.

## What's Next

With player wallets created and deployed, [Guide 6: Sponsored Transactions](sponsored-transactions.md) covers how to let players transact without holding gas tokens using paymasters, policies, and budgets.
