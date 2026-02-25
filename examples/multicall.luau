--!strict
-- multicall.luau
-- Batch multiple contract calls into a single transaction.
--
-- This example shows how to:
--   1. Create an account from a private key
--   2. Use contract:populate() to build Call objects without executing
--   3. Batch multiple calls into one account:execute() transaction
--   4. Wait for the transaction receipt
--
-- Multicall saves gas and ensures atomicity: either all calls succeed or all revert.
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

-- Recipients for the batch transfer
local RECIPIENTS = {
	{ address = "0x_RECIPIENT_1_ADDRESS", amount = "0xDE0B6B3A7640000" }, -- 1e18
	{ address = "0x_RECIPIENT_2_ADDRESS", amount = "0x6F05B59D3B20000" }, -- 0.5e18
	{ address = "0x_RECIPIENT_3_ADDRESS", amount = "0x2386F26FC10000" }, -- 0.01e18
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- Create account from private key (derives address using OZ class hash)
local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

print("[Multicall] Account address:", account.address)

-- Create an ERC-20 contract instance with the account attached for writes
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

--------------------------------------------------------------------------------
-- Build multicall: batch multiple transfers into one transaction
--------------------------------------------------------------------------------

-- Use populate() to build Call objects without executing.
-- Each Call has { contractAddress, entrypoint, calldata }.
local calls = {}
for _, recipient in RECIPIENTS do
	-- populate() encodes the calldata based on the ABI but doesn't submit
	local call = ethToken:populate("transfer", {
		recipient.address, -- recipient ContractAddress
		recipient.amount, -- amount u256 (hex string)
	})
	table.insert(calls, call)
	print(`[Multicall] Queued transfer: {recipient.amount} to {recipient.address}`)
end

print(`[Multicall] Batching {#calls} transfers into one transaction...`)

-- Execute all calls in a single transaction.
-- The TransactionBuilder handles: nonce → fee estimation → hash → sign → submit
account
	:execute(calls, {
		-- Optional: adjust the fee safety margin (default 1.5x estimated fee)
		feeMultiplier = 1.5,
	})
	:andThen(function(result)
		print("[Multicall] Transaction submitted!")
		print("[Multicall] Hash:", result.transactionHash)

		-- Wait for the transaction to be included in a block
		return account:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("[Multicall] Transaction confirmed!")
		print("[Multicall] Status:", receipt.finality_status)
		print("[Multicall] Block:", receipt.block_number)
	end)
	:catch(function(err)
		warn("[Multicall] Transaction failed:", tostring(err))
	end)
