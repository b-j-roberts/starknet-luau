--!strict
-- send-transaction.luau
-- Build, sign, and submit a token transfer on Starknet Sepolia.
--
-- This example shows the full lifecycle of a transaction:
--   1. Create a provider and account from a private key
--   2. Check the sender's balance before transfer
--   3. Build and submit a transfer transaction
--   4. Wait for the transaction to be confirmed
--   5. Check the balance after transfer
--
-- Usage: Place this Script under ServerScriptService (requires HttpService enabled).
--        Replace PRIVATE_KEY with your account's private key.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- WARNING: Never hardcode private keys in production code.
-- Use secure storage (DataStoreService, environment config, etc.)
local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"

-- Destination address for the transfer
local RECIPIENT = "0x_RECIPIENT_ADDRESS_HERE"

-- Amount to transfer: 0.001 ETH = 1e15 wei = 0x38D7EA4C68000
local TRANSFER_AMOUNT = "0x38D7EA4C68000"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

-- Step 1: Create a provider connected to Sepolia
local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- Step 2: Create an account from the private key.
-- This derives the onchain address using the OpenZeppelin class hash.
local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

print("[Send] Sender address:", account.address)
print("[Send] Public key:", account:getPublicKeyHex())

-- Step 3: Create an ERC-20 contract instance with the account for write access
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

--------------------------------------------------------------------------------
-- Check balance before transfer
--------------------------------------------------------------------------------

print("[Send] Checking balance before transfer...")

ethToken
	:balance_of(account.address)
	:andThen(function(balance)
		print("[Send] Current ETH balance (low):", balance.low)

		-- Verify we have enough balance
		local balanceNum = tonumber(balance.low, 16) or 0
		local transferNum = tonumber(TRANSFER_AMOUNT, 16) or 0
		if balanceNum < transferNum then
			error(`Insufficient balance: have {balanceNum}, need {transferNum}`)
		end

		print(`[Send] Sending {TRANSFER_AMOUNT} to {RECIPIENT}...`)

		--------------------------------------------------------------------------------
		-- Submit the transfer transaction
		--------------------------------------------------------------------------------

		-- Step 4: Call transfer via dynamic dispatch.
		-- Under the hood this:
		--   a. Fetches the current nonce
		--   b. Encodes calldata (recipient + amount as u256 low/high)
		--   c. Estimates fee with a dummy signature
		--   d. Computes the V3 INVOKE transaction hash (Poseidon)
		--   e. Signs with ECDSA (RFC 6979 deterministic k)
		--   f. Submits to the RPC node
		return ethToken:transfer(RECIPIENT, TRANSFER_AMOUNT)
	end)
	:andThen(function(result)
		print("[Send] Transaction submitted!")
		print("[Send] Transaction hash:", result.transactionHash)

		--------------------------------------------------------------------------------
		-- Wait for confirmation
		--------------------------------------------------------------------------------

		-- Step 5: Poll the node until the transaction is included in a block
		return account:waitForReceipt(result.transactionHash, {
			retryInterval = 5, -- poll every 5 seconds
		})
	end)
	:andThen(function(receipt)
		print("[Send] Transaction confirmed!")
		print("[Send] Status:", receipt.finality_status)
		print("[Send] Block:", receipt.block_number)

		--------------------------------------------------------------------------------
		-- Check balance after transfer
		--------------------------------------------------------------------------------

		return ethToken:balance_of(account.address)
	end)
	:andThen(function(balanceAfter)
		print("[Send] Balance after transfer (low):", balanceAfter.low)
		print("[Send] Transfer complete!")
	end)
	:catch(function(err)
		warn("[Send] Error:", tostring(err))
	end)
