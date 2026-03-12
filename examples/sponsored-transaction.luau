--!strict
-- sponsored-transaction.luau
-- Execute a gasless game action using SponsoredExecutor + AvnuPaymaster.
--
-- This example shows how to:
--   1. Configure an AVNU paymaster with an API key for sponsored transactions
--   2. Set up a PaymasterPolicy to restrict which contracts/methods are allowed
--   3. Set up a PaymasterBudget to limit per-player spending
--   4. Use SponsoredExecutor to submit a gasless ERC-20 transfer
--   5. Handle callbacks for transaction lifecycle events
--
-- The player pays zero gas — the paymaster sponsors the transaction.
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local AvnuPaymaster = StarknetLuau.paymaster.AvnuPaymaster
local PaymasterPolicy = StarknetLuau.paymaster.PaymasterPolicy
local PaymasterBudget = StarknetLuau.paymaster.PaymasterBudget
local SponsoredExecutor = StarknetLuau.paymaster.SponsoredExecutor
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- WARNING: Never hardcode private keys in production code.
-- Use KeyStore for player keys or secure server config for operator keys.
local PLAYER_PRIVATE_KEY = "0x_PLAYER_PRIVATE_KEY_HERE"

-- AVNU paymaster API key (get one from avnu.fi for sponsored transactions)
local AVNU_API_KEY = "YOUR_AVNU_API_KEY"

-- Recipient for the sponsored transfer
local RECIPIENT = "0x_RECIPIENT_ADDRESS_HERE"

-- Transfer amount: 0.001 ETH
local TRANSFER_AMOUNT = "0x38D7EA4C68000"

-- Player ID for policy/budget tracking (in production, use player.UserId)
local PLAYER_ID = "player_12345"

--------------------------------------------------------------------------------
-- Setup: Provider + Account
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

local account = Account.fromPrivateKey({
	privateKey = PLAYER_PRIVATE_KEY,
	provider = provider,
})

print("[Sponsored] Player address:", account.address)

--------------------------------------------------------------------------------
-- Setup: AVNU Paymaster (SNIP-29)
--------------------------------------------------------------------------------

-- AvnuPaymaster wraps the generic PaymasterRpc with AVNU-specific endpoints
-- and token registry. Providing an apiKey enables sponsored (gasless) mode.
local paymaster = AvnuPaymaster.new({
	network = "sepolia",
	apiKey = AVNU_API_KEY,
})

print("[Sponsored] Paymaster sponsored mode:", paymaster:isSponsored())

--------------------------------------------------------------------------------
-- Setup: Policy (restrict what the paymaster will sponsor)
--------------------------------------------------------------------------------

-- Policy validates calls BEFORE sending them to the paymaster.
-- This prevents players from using your sponsored quota for unrelated actions.
local policy = PaymasterPolicy.new({
	-- Only allow interactions with the ETH token contract
	allowedContracts = {
		{ address = Constants.ETH_TOKEN_ADDRESS },
	},
	-- Only allow the "transfer" method
	allowedMethods = {
		{ contract = Constants.ETH_TOKEN_ADDRESS, selector = "transfer" },
	},
	-- Rate limit: max 10 sponsored transactions per player per hour
	maxTxPerPlayer = 10,
	timeWindow = 3600,
	-- Cap fee per transaction (in wei)
	maxFeePerTx = "0xE8D4A51000", -- ~1e12 wei
})

--------------------------------------------------------------------------------
-- Setup: Budget (per-player virtual token spending limits)
--------------------------------------------------------------------------------

-- Budget tracks a virtual token balance per player. Players must have tokens
-- to submit sponsored transactions. Grant tokens via game rewards, purchases, etc.
local budget = PaymasterBudget.new({
	defaultTokenBalance = 0, -- new players start with 0 tokens
	costPerTransaction = 1, -- each sponsored tx costs 1 token
})

-- Grant the player some tokens (in production, tie this to game rewards)
budget:grantTokens(PLAYER_ID, 10)
print("[Sponsored] Player token balance:", budget:getBalance(PLAYER_ID))

--------------------------------------------------------------------------------
-- Setup: SponsoredExecutor (orchestrates everything)
--------------------------------------------------------------------------------

-- SponsoredExecutor chains: policy check → budget check → paymaster build/sign/execute
-- It handles retries on transient errors with exponential backoff.
local executor = SponsoredExecutor.new({
	account = account,
	paymaster = paymaster,
	feeMode = { mode = "sponsored" }, -- gasless mode (requires API key)

	-- Optional: attach policy and budget for validation
	policy = policy,
	budget = budget,

	-- Retry transient paymaster errors up to 3 times
	retryAttempts = 3,
	retryDelay = 1,

	-- Lifecycle callbacks
	callbacks = {
		onTransactionSubmitted = function(info)
			print("[Sponsored] Tx submitted:", info.transactionHash)
			if info.trackingId then
				print("[Sponsored] Tracking ID:", info.trackingId)
			end
		end,
		onTransactionConfirmed = function(info)
			print("[Sponsored] Tx confirmed! Hash:", info.transactionHash)
		end,
		onTransactionFailed = function(info)
			warn("[Sponsored] Tx failed:", tostring(info.error))
		end,
	},
})

--------------------------------------------------------------------------------
-- Execute a sponsored (gasless) transfer
--------------------------------------------------------------------------------

-- Build the ERC-20 transfer call
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)
local transferCall = ethToken:populate("transfer", { RECIPIENT, TRANSFER_AMOUNT })

print("[Sponsored] Executing sponsored transfer...")

executor
	:execute(PLAYER_ID, { transferCall }, {
		waitForConfirmation = true,
	})
	:andThen(function(result)
		print("[Sponsored] Transfer complete!")
		print("[Sponsored] Transaction hash:", result.transactionHash)
		print("[Sponsored] Tokens consumed:", result.tokensCost)
		print("[Sponsored] Retries needed:", result.retryCount)

		-- Check remaining budget
		print("[Sponsored] Remaining token balance:", budget:getBalance(PLAYER_ID))

		-- Check executor metrics
		local metrics = executor:getMetrics()
		print("[Sponsored] Total executions:", metrics.totalExecutions)
		print("[Sponsored] Total successful:", metrics.totalSuccessful)
	end)
	:catch(function(err)
		-- Handle different error types
		if StarknetError.isStarknetError(err) then
			if err:is("PaymasterError") then
				warn("[Sponsored] Paymaster error:", err.message)
			elseif err:is("ValidationError") then
				warn("[Sponsored] Policy rejected:", err.message)
			else
				warn("[Sponsored] Starknet error:", tostring(err))
			end
		else
			warn("[Sponsored] Unexpected error:", tostring(err))
		end
	end)

return {}
