# Sponsored (Gasless) Transactions

Let players transact without holding gas tokens. A paymaster service pays fees on their behalf, so the player experience is completely frictionless.

## Prerequisites

- Completed [Guide 3: Accounts & Transactions](accounts-and-transactions.md)
- Completed [Guide 5: Player Onboarding](player-onboarding.md)
- HttpService enabled in Game Settings
- An AVNU paymaster API key (get one from [avnu.fi](https://avnu.fi)) for sponsored mode

## How Paymasters Work

On Starknet, every transaction requires gas fees paid in STRK or ETH. A **paymaster** is a third-party service that pays those fees for you, using the SNIP-29 standard (SNIP = Starknet Improvement Proposal -- protocol-level specs, like RFCs for the Starknet network). The flow looks like this:

1. Your server builds the calls the player wants to execute.
2. The paymaster wraps those calls in an OutsideExecution (SNIP-9) and returns typed data for signing.
3. The player's account signs the typed data.
4. The paymaster submits the signed transaction on-chain and pays the gas fee.

The SDK provides two approaches to sponsored transactions:

- **SponsoredExecutor** -- batteries-included orchestrator that handles policy, budget, paymaster interaction, retries, and callbacks in one call. Start here.
- **Account:executePaymaster()** -- lower-level method for direct paymaster interaction without policy or budget checks.

There's also a third pattern, **Outside Execution (SNIP-9)**, where your server acts as the relayer instead of a paymaster service.

## Quick Start: SponsoredExecutor

`SponsoredExecutor` is the recommended entry point. It chains: policy validation, budget check, paymaster build/sign/execute, retry on transient errors, and lifecycle callbacks.

```luau
--!strict
-- ServerScriptService/SponsoredTransfer.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster
local SponsoredExecutor = StarknetLuau.paymaster.SponsoredExecutor
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- In production, load the player's key from KeyStore (see Guide 5)
local account = Account.fromPrivateKey({
	privateKey = "0x_PLAYER_PRIVATE_KEY",
	provider = provider,
})

local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = "YOUR_AVNU_API_KEY",
})

local executor = SponsoredExecutor.new({
	account = account,
	paymaster = paymaster,
	feeMode = { mode = "sponsored" },
})

-- Build the call (account arg is optional for populate -- only needed for call/invoke)
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
local transferCall = ethToken:populate("transfer", { "0xRECIPIENT", "0x38D7EA4C68000" }) -- 0.001 ETH

-- Execute -- the player pays zero gas
executor
	:execute(12345, { transferCall })
	:andThen(function(result)
		print("Tx hash:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

The `playerId` (first argument to `execute`) is a number -- use `player.UserId` in production. It's used for policy rate-limiting and budget tracking.

## AvnuPaymaster Setup

`AvnuPaymaster` is a convenience wrapper around the generic `PaymasterRpc` client, pre-configured for AVNU's paymaster endpoints.

```luau
--!strict
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster

-- Sponsored mode: game developer pays gas (requires API key)
local paymaster = AvnuPaymaster.new({
	network = "sepolia",       -- "sepolia" or "mainnet"
	apiKey = "YOUR_AVNU_API_KEY",
})

-- Check if sponsored mode is active
print(paymaster:isSponsored()) -- true (API key provided)

-- Check if the paymaster service is reachable
paymaster:isAvailable():andThen(function(available: boolean)
	print("Paymaster available:", available)
end)
```

### Default Mode (Player Pays in Alt Token)

Without an API key, the paymaster runs in **default** mode -- the player still pays, but in an alternative token (e.g., USDC instead of STRK):

```luau
--!strict
local paymaster = AvnuPaymaster.new({
	network = "mainnet",
	-- No apiKey = default mode
})

print(paymaster:isSponsored()) -- false

-- Look up token addresses by symbol
local usdcAddress = paymaster:getTokenAddress("USDC")
-- "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8"
```

When using default mode, pass a `gasToken` in the `feeMode`:

```luau
--!strict
local executor = SponsoredExecutor.new({
	account = account,
	paymaster = paymaster,
	feeMode = { mode = "default", gasToken = usdcAddress },
})
```

### Querying Supported Tokens

```luau
--!strict
paymaster:getSupportedTokens():andThen(function(tokens)
	for _, token in tokens do
		print(token.tokenAddress, token.decimals, token.priceInStrk)
	end
end)
```

Results are cached for 5 minutes. Call `paymaster:clearTokenCache()` to force a refresh.

## PaymasterRpc: Generic SNIP-29 Client

For non-AVNU paymaster services (Cartridge, self-hosted, etc.), use `PaymasterRpc` directly:

```luau
--!strict
local PaymasterRpc = StarknetLuau.paymaster.PaymasterRpc

local paymaster = PaymasterRpc.new({
	nodeUrl = "https://your-paymaster-endpoint.com",
	headers = {
		["Authorization"] = "Bearer YOUR_TOKEN",
	},
})
```

`PaymasterRpc` exposes the same methods as `AvnuPaymaster`: `isAvailable()`, `getSupportedTokens()`, `buildTypedData()`, `executeTransaction()`, and `trackingIdToLatestHash()`. The difference is that you configure the endpoint manually and don't get AVNU-specific conveniences like known token addresses.

## PaymasterPolicy: Restricting What Gets Sponsored

Without guardrails, players could use your sponsored quota for any on-chain action. `PaymasterPolicy` validates calls before they reach the paymaster.

```luau
--!strict
local PaymasterPolicy = StarknetLuau.paymaster.PaymasterPolicy
local Constants = StarknetLuau.constants

local policy = PaymasterPolicy.new({
	-- Only allow interactions with these contracts
	allowedContracts = {
		{ address = Constants.ETH_TOKEN_ADDRESS },
		{ address = "0xYOUR_GAME_CONTRACT" },
	},

	-- Only allow these specific methods
	allowedMethods = {
		{ contract = Constants.ETH_TOKEN_ADDRESS, selector = "transfer" },
		{ contract = "0xYOUR_GAME_CONTRACT", selector = "claim_reward" },
		{ contract = "0xYOUR_GAME_CONTRACT", selector = "submit_score" },
	},

	-- Rate limit: max 10 sponsored transactions per player per hour
	maxTxPerPlayer = 10,
	timeWindow = 3600,

	-- Cap gas fee per transaction (hex string, in wei -- the smallest unit, like cents to dollars)
	maxFeePerTx = "0xE8D4A51000", -- ~1 trillion wei
})
```

### Validating Calls

`validate()` checks player whitelist, contract whitelist, method whitelist, and rate limits. It returns `{ allowed: boolean, reason: string? }`:

```luau
--!strict
local result = policy:validate(player.UserId, calls)
if not result.allowed then
	warn("Rejected:", result.reason)
	return
end
```

### Validating Fees

```luau
--!strict
-- Pass the estimated fee (hex string) from the paymaster to check against maxFeePerTx
local feeResult = policy:validateFee(player.UserId, "0x1234567890")
if not feeResult.allowed then
	warn("Fee too high:", feeResult.reason)
end
```

### Recording Usage

`validate()` does not record usage -- call `recordUsage()` after a successful transaction:

```luau
--!strict
policy:recordUsage(player.UserId)

-- Check usage count in current window
local count = policy:getUsageCount(player.UserId)
print("Transactions this window:", count)

-- Reset a specific player's usage (or all players with nil)
policy:resetUsage(player.UserId)
```

### Player Whitelisting

Restrict sponsored transactions to specific players:

```luau
--!strict
local policy = PaymasterPolicy.new({
	allowedPlayers = {
		{ playerId = 12345 },
		{ playerId = 67890 },
	},
	-- ... other rules
})
```

When `allowedPlayers` is set, only listed players can use sponsored transactions. Omit it to allow all players.

## PaymasterBudget: Per-Player Spending Limits

`PaymasterBudget` tracks virtual "paymaster tokens" -- a game-managed currency that controls how many sponsored transactions each player can submit. These tokens are not on-chain; they're managed entirely through Roblox DataStoreService.

```luau
--!strict
local PaymasterBudget = StarknetLuau.paymaster.PaymasterBudget

local budget = PaymasterBudget.new({
	defaultTokenBalance = 0,    -- new players start with 0
	costPerTransaction = 1,      -- each sponsored tx costs 1 token
	dataStoreName = "StarknetPaymaster", -- DataStore for persistence
})
```

### Granting and Checking Tokens

```luau
--!strict
-- Grant tokens as game rewards, purchases, daily bonuses, etc.
budget:grantTokens(player.UserId, 10)

-- Check balance
local balance = budget:getBalance(player.UserId)
print("Tokens:", balance) -- 10

-- Check if a player can afford a transaction
local canAfford = budget:canAfford(player.UserId) -- true if balance >= costPerTransaction
```

### Consuming and Refunding

`consumeTransaction()` deducts tokens before the paymaster call. If the paymaster fails, `refundTransaction()` gives them back:

```luau
--!strict
-- Deduct before submitting
local cost = budget:consumeTransaction(player.UserId)

-- If the paymaster call fails:
budget:refundTransaction(player.UserId, cost)
```

`SponsoredExecutor` handles this consume/refund pattern automatically.

### DataStore Persistence

Budget data lives in memory and flushes to DataStore periodically (every 30 seconds by default, or when 20 entries are dirty):

```luau
--!strict
-- Force flush all dirty entries now
budget:flush()

-- Flush a specific player (e.g., on PlayerRemoving)
budget:flushPlayer(player.UserId)

-- Pre-load a player's data from DataStore on join
budget:loadPlayer(player.UserId)

-- Unload from memory on leave (flushes first if dirty)
budget:unloadPlayer(player.UserId)
```

### Usage Statistics

```luau
--!strict
local stats = budget:getUsageStats(player.UserId)
print("Balance:", stats.balance)
print("Total transactions:", stats.totalTxCount)
print("Total tokens spent:", stats.totalTokensSpent)
print("Last transaction:", stats.lastTxTime)
```

## SponsoredExecutor: Full Orchestration

`SponsoredExecutor` ties everything together. Here's a complete setup with policy, budget, retries, and lifecycle callbacks:

```luau
--!strict
-- ServerScriptService/SponsoredGameActions.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore
local ERC20 = StarknetLuau.contract.ERC20
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster
local PaymasterPolicy = StarknetLuau.paymaster.PaymasterPolicy
local PaymasterBudget = StarknetLuau.paymaster.PaymasterBudget
local SponsoredExecutor = StarknetLuau.paymaster.SponsoredExecutor
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"
local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"
local AVNU_API_KEY = "YOUR_AVNU_API_KEY"

local provider = RpcProvider.new({ nodeUrl = SEPOLIA_RPC })

local keyStore = KeyStore.new({ serverSecret = SERVER_SECRET })

local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = AVNU_API_KEY,
})

local policy = PaymasterPolicy.new({
	allowedContracts = {
		{ address = Constants.ETH_TOKEN_ADDRESS },
	},
	allowedMethods = {
		{ contract = Constants.ETH_TOKEN_ADDRESS, selector = "transfer" },
	},
	maxTxPerPlayer = 10,
	timeWindow = 3600,
	maxFeePerTx = "0xE8D4A51000",
})

local budget = PaymasterBudget.new({
	defaultTokenBalance = 0,
	costPerTransaction = 1,
})

-- Per-player executors (each player has their own account)
local playerExecutors: { [number]: any } = {}

Players.PlayerAdded:Connect(function(player: Player)
	local ok, err = pcall(function()
		local result = keyStore:getOrCreate(player.UserId, provider)
		local account = result.account

		-- Grant 5 sponsored transactions on join
		budget:grantTokens(player.UserId, 5)

		playerExecutors[player.UserId] = SponsoredExecutor.new({
			account = account,
			paymaster = paymaster,
			feeMode = { mode = "sponsored" },
			policy = policy,
			budget = budget,
			retryAttempts = 3,
			retryDelay = 1,
			callbacks = {
				onTransactionSubmitted = function(info)
					print(`[{player.Name}] Tx submitted: {info.transactionHash}`)
				end,
				onTransactionConfirmed = function(info)
					print(`[{player.Name}] Tx confirmed: {info.transactionHash}`)
				end,
				onTransactionFailed = function(info)
					warn(`[{player.Name}] Tx failed: {tostring(info.error)}`)
					warn(`  Retries: {info.retryCount}, Tokens refunded: {info.tokensRefunded}`)
				end,
			},
		})

		print(`[Sponsored] {player.Name} ready with {budget:getBalance(player.UserId)} tokens`)
	end)

	if not ok then
		warn(`[Sponsored] Setup failed for {player.Name}: {tostring(err)}`)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	playerExecutors[player.UserId] = nil
	budget:unloadPlayer(player.UserId)
end)
```

### Executing Sponsored Calls

```luau
--!strict
-- Called from a RemoteFunction or game event handler
local function sponsoredTransfer(player: Player, recipient: string, amount: string)
	local executor = playerExecutors[player.UserId]
	if not executor then
		warn("No executor for player", player.Name)
		return
	end

	-- account not needed for populate() -- the executor handles signing/submission
	local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
	local transferCall = ethToken:populate("transfer", { recipient, amount })

	executor
		:execute(player.UserId, { transferCall }, {
			waitForConfirmation = true,
		})
		:andThen(function(result)
			print(`Transfer complete! Hash: {result.transactionHash}`)
			print(`Tokens used: {result.tokensCost}, Retries: {result.retryCount}`)
			print(`Remaining balance: {budget:getBalance(player.UserId)}`)
		end)
		:catch(function(err)
			if StarknetError.isStarknetError(err) then
				-- Error types: "RpcError", "SigningError", "AbiError",
				-- "ValidationError", "TransactionError", "PaymasterError"
				if err:is("PaymasterError") then
					warn("Paymaster error:", err.message)
				elseif err:is("ValidationError") then
					warn("Policy rejected:", err.message)
				else
					warn("Error:", tostring(err))
				end
			else
				warn("Unexpected error:", tostring(err))
			end
		end)
end
```

### Executor Metrics

```luau
--!strict
local metrics = executor:getMetrics()
print("Total executions:", metrics.totalExecutions)
print("Successful:", metrics.totalSuccessful)
print("Failed:", metrics.totalFailed)
print("Total retries:", metrics.totalRetries)
print("Tokens consumed:", metrics.totalTokensConsumed)
print("Tokens refunded:", metrics.totalTokensRefunded)

-- Per-contract and per-method breakdown
for contract, count in metrics.byContract do
	print(`Contract {contract}: {count} calls`)
end

-- Reset metrics
executor:resetMetrics()
```

## Account:executePaymaster() -- Direct Paymaster Access

For cases where you don't need policy or budget validation, use `Account:executePaymaster()` directly:

```luau
--!strict
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = "YOUR_AVNU_API_KEY",
})

local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)
local transferCall = ethToken:populate("transfer", { "0xRECIPIENT", "0x38D7EA4C68000" }) -- 0.001 ETH

account
	:executePaymaster({ transferCall }, {
		paymaster = paymaster,
		feeMode = { mode = "sponsored" },
	})
	:andThen(function(result)
		print("Tx hash:", result.transactionHash)
		if result.trackingId then
			print("Tracking ID:", result.trackingId)
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

The `trackingId` is assigned by the paymaster service. You can look up the final on-chain transaction hash from a tracking ID with `paymaster:trackingIdToLatestHash(trackingId)`.

### Estimating Paymaster Fees

```luau
--!strict
account
	:estimatePaymasterFee({ transferCall }, {
		paymaster = paymaster,
		feeMode = { mode = "default", gasToken = paymaster:getTokenAddress("STRK") },
	})
	:andThen(function(result)
		local fee = result.feeEstimate
		if fee then
			print("Estimated fee (STRK):", fee.estimatedFeeInStrk)
			print("Suggested max fee:", fee.suggestedMaxFeeInStrk)
		end
	end)
```

### Deploying Accounts via Paymaster

Deploy new accounts without prefunding using `Account:deployWithPaymaster()`:

```luau
--!strict
local account = Account.fromPrivateKey({
	privateKey = "0x_NEW_PLAYER_KEY",
	provider = provider,
	accountType = "oz",
})

account
	:deployWithPaymaster({
		paymaster = paymaster,
		feeMode = { mode = "sponsored" },
	}, {
		waitForConfirmation = true,
	})
	:andThen(function(result)
		if result.alreadyDeployed then
			print("Already deployed at:", result.contractAddress)
		else
			print("Deployed! Tx:", result.transactionHash)
		end
	end)
	:catch(function(err)
		warn("Deploy failed:", tostring(err))
	end)
```

`deployWithPaymaster()` is idempotent -- it checks `getNonce()` first and returns `{ alreadyDeployed = true }` if the account already exists.

### Getting Deployment Data

If you're building paymaster requests manually (e.g., for `SponsoredExecutor` with deployment), get the SNIP-29 deployment data from an account:

```luau
--!strict
local deploymentData = account:getDeploymentData()
-- { classHash, calldata, salt, unique (bool: whether the deployer address factors into the computed address) }

-- Pass to SponsoredExecutor for deploy-and-invoke
local executor = SponsoredExecutor.new({
	account = account,
	paymaster = paymaster,
	feeMode = { mode = "sponsored" },
	deploymentData = deploymentData, -- enables deploy-and-invoke
})
```

## Outside Execution (SNIP-9): Server-as-Relayer

Outside Execution is an alternative to paymasters. Instead of a paymaster service paying gas, your **game server** acts as the relayer. The player signs their intent off-chain, and the server submits it using the server's own funded account.

This is useful when:
- You want full control over gas payments without a third-party paymaster
- You want to batch player actions into fewer transactions
- You need session-key-like behavior without deploying session contracts

### The Flow

1. Player builds a call (e.g., "transfer 100 tokens")
2. Server builds a SNIP-9 TypedData structure with time bounds and a nonce
3. Player's account signs the TypedData (server-side since keys are custodial)
4. Server builds an `execute_from_outside_v2` call targeting the player's account
5. Server submits this call using the relayer account (server pays gas)

```luau
--!strict
-- ServerScriptService/OutsideExecution.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local OutsideExecution = StarknetLuau.wallet.OutsideExecution
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Player account (custodial -- loaded from KeyStore in production)
local playerAccount = Account.fromPrivateKey({
	privateKey = "0x_PLAYER_KEY",
	provider = provider,
})

-- Relayer account (server-owned, funded with STRK for gas)
local relayerAccount = Account.fromPrivateKey({
	privateKey = "0x_RELAYER_KEY",
	provider = provider,
})

-- Step 1: Build the player's intended call
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
local transferCall = ethToken:populate("transfer", { "0xRECIPIENT", "0x38D7EA4C68000" }) -- 0.001 ETH

-- Step 2: Get chain ID and build SNIP-9 TypedData
local chainId = provider:getChainId():expect() -- :expect() blocks until the Promise resolves
local now = os.time()

local typedData = OutsideExecution.getTypedData({
	chainId = chainId,
	caller = OutsideExecution.ANY_CALLER, -- any relayer can submit
	execute_after = tostring(now - 60),    -- 1 min grace for clock skew
	execute_before = tostring(now + 3600), -- expires in 1 hour
	nonce = tostring(now),                 -- unique nonce (timestamp works)
	calls = { transferCall },
	version = OutsideExecution.VERSION_V2, -- V2 recommended
})

-- Step 3: Player signs the TypedData
local signature = playerAccount:signMessage(typedData)

-- Step 4: Build the on-chain call for the relayer
-- Convert Call (entrypoint name) → OutsideCall (computed selector hash) for SNIP-9
local outsideCall = OutsideExecution.getOutsideCall(transferCall)

local executeCall = OutsideExecution.buildExecuteFromOutsideCall(
	playerAccount.address,
	{
		caller = OutsideExecution.ANY_CALLER,
		execute_after = tostring(now - 60),
		execute_before = tostring(now + 3600),
		nonce = tostring(now),
		calls = { outsideCall },
	},
	signature,
	OutsideExecution.VERSION_V2
)

-- Step 5: Relayer submits the transaction (relayer pays gas)
relayerAccount
	:execute({ executeCall })
	:andThen(function(result)
		print("Submitted! Tx:", result.transactionHash)
		return relayerAccount:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("Confirmed in block:", receipt.block_number)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

### Key Concepts

**`caller`** -- who can submit this on-chain. `OutsideExecution.ANY_CALLER` allows any address. Set it to the relayer's address to restrict submission to a specific relayer.

**Time bounds** -- `execute_after` and `execute_before` define the validity window. The transaction is rejected if submitted outside this window. Always include a small grace period for clock skew.

**Nonce** -- prevents replay attacks. Each outside execution must use a unique nonce. Using `os.time()` works when each player submits at most one outside execution per second. For higher throughput, combine it with a counter (e.g., `os.time() * 1000 + counter`).

**`getOutsideCall()`** -- converts a Call object (with named `entrypoint`) to the OutsideCall format (with computed `selector` hash). Required because SNIP-9 uses selectors, not entrypoint names.

### SNIP-9 Versions

| Version | Constant | Entrypoint | Typed Data |
|---------|----------|------------|------------|
| V1 | `VERSION_V1` | `execute_from_outside` | Pedersen / StarkNetDomain |
| V2 | `VERSION_V2` | `execute_from_outside_v2` | Poseidon / StarknetDomain |
| V3-RC | `VERSION_V3_RC` | `execute_from_outside_v3` | Poseidon + Fee Mode enum |

Use V2 unless you need V3's fee mode support. V1 is legacy (Pedersen-based) and supported for older accounts.

## Choosing Between Paymasters and Outside Execution

| Concern | Paymaster (SponsoredExecutor) | Outside Execution |
|---------|-------------------------------|-------------------|
| Gas payer | Third-party paymaster service | Your server's relayer account |
| Setup cost | API key from paymaster provider | Fund a relayer account |
| Gas token flexibility | STRK, ETH, USDC, etc. | Whatever the relayer holds |
| Batching player actions | One tx per player call | Can batch multiple players |
| External dependency | Paymaster service must be online | Only your RPC node |
| SDK integration | `SponsoredExecutor` (batteries included) | Manual assembly |

For most games, **SponsoredExecutor + AvnuPaymaster** is the simplest path to gasless UX. Use Outside Execution when you need full control or want to eliminate the third-party dependency.

## Common Mistakes

**SponsoredExecutor metrics cap at 1000 distinct player entries.** The `byPlayer` map in `executor:getMetrics()` stops tracking new players after 1000 entries. For production games with more players, use external telemetry (e.g., Roblox AnalyticsService) for per-player metrics.

**Policy `validate()` does not record usage.** Call `policy:recordUsage(playerId)` after a successful transaction. `SponsoredExecutor` handles this automatically, but if you use `PaymasterPolicy` standalone, you must call it yourself or rate limits won't work.

**Budget tokens are consumed before the paymaster call.** If the paymaster fails, `SponsoredExecutor` automatically refunds tokens via `budget:refundTransaction()`. If you use `PaymasterBudget` standalone, handle the refund yourself.

**Outside Execution time bounds are checked on-chain.** If `execute_before` has passed by the time the transaction is included in a block, it will revert. Use generous windows (1+ hours) and include a grace period in `execute_after` for clock skew between your server and the Starknet sequencer.

**`maxTxPerPlayer` requires `timeWindow`.** Setting a rate limit without a time window throws a validation error. Both must be set together.

**Budget `flush()` requires a published place.** Like all DataStore operations, `PaymasterBudget` persistence only works in published Roblox experiences. In Studio, inject a mock via `_dataStore` in the config.

## What's Next

With gasless transactions working, [Guide 7: Events & Real-Time Data](events-and-real-time-data.md) covers monitoring on-chain events to react to blockchain state changes in your game.
