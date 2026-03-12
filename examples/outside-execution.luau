--!strict
-- outside-execution.luau
-- SNIP-9 Outside Execution for meta-transactions.
--
-- This example shows how to:
--   1. Build an OutsideExecution typed data structure for off-chain signing
--   2. Sign the typed data with the player's account
--   3. Build the execute_from_outside call for a relayer to submit
--   4. Submit via a relayer account (server pays gas, player signs intent)
--
-- Outside Execution enables meta-transactions: the player signs their intent
-- off-chain, and a relayer (server) submits the transaction on their behalf.
-- This is useful when:
--   - Players don't have gas tokens (combined with paymaster for full gasless UX)
--   - The server batches player actions for efficiency
--   - You want session-key-like behavior without deploying session contracts
--
-- SNIP-9 versions:
--   - V1: execute_from_outside (original)
--   - V2: execute_from_outside_v2 (adds fee call validation)
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local OutsideExecution = StarknetLuau.wallet.OutsideExecution
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Player's private key (in production, loaded from KeyStore)
-- WARNING: Never hardcode private keys in production code.
local PLAYER_PRIVATE_KEY = "0x_PLAYER_PRIVATE_KEY_HERE"

-- Server/relayer private key (pays gas on behalf of the player)
local RELAYER_PRIVATE_KEY = "0x_RELAYER_PRIVATE_KEY_HERE"

-- Transfer recipient
local RECIPIENT = "0x_RECIPIENT_ADDRESS_HERE"

-- Transfer amount: 0.001 ETH
local TRANSFER_AMOUNT = "0x38D7EA4C68000"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- Player account (signs the intent off-chain)
local playerAccount = Account.fromPrivateKey({
	privateKey = PLAYER_PRIVATE_KEY,
	provider = provider,
})

-- Relayer account (submits the transaction and pays gas)
local relayerAccount = Account.fromPrivateKey({
	privateKey = RELAYER_PRIVATE_KEY,
	provider = provider,
})

print("[OutsideExec] Player address:", playerAccount.address)
print("[OutsideExec] Relayer address:", relayerAccount.address)

--------------------------------------------------------------------------------
-- Step 1: Build the call the player wants to execute
--------------------------------------------------------------------------------

-- The player wants to transfer ETH but doesn't have gas tokens.
-- Build the Call object using ERC-20's populate().
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
local transferCall = ethToken:populate("transfer", { RECIPIENT, TRANSFER_AMOUNT })

-- Convert the call for OutsideExecution format (entrypoint name → selector hash)
local outsideCall = OutsideExecution.getOutsideCall(transferCall)

print("[OutsideExec] Transfer call built:")
print(`  To: {outsideCall.to}`)
print(`  Selector: {outsideCall.selector}`)

--------------------------------------------------------------------------------
-- Step 2: Build the SNIP-9 typed data for signing
--------------------------------------------------------------------------------

-- Get the chain ID for the typed data domain
local chainId = provider:getChainId():expect()

-- Build the TypedData structure that the player will sign.
-- This includes time bounds and a nonce to prevent replay attacks.
local now = os.time()
local typedData = OutsideExecution.getTypedData({
	chainId = chainId,

	-- Who can submit this on-chain. ANY_CALLER allows any relayer.
	-- For restricted access, set this to the relayer's address.
	caller = OutsideExecution.ANY_CALLER,

	-- Time window: valid from now until 1 hour from now
	execute_after = tostring(now - 60), -- 1 minute grace for clock skew
	execute_before = tostring(now + 3600), -- expires in 1 hour

	-- Unique nonce to prevent replay (use a counter or random value)
	nonce = tostring(now), -- using timestamp as a simple unique nonce

	-- The calls to execute (pass raw Call objects; getTypedData converts internally)
	calls = { transferCall },

	-- SNIP-9 version (V2 is recommended for newer accounts)
	version = OutsideExecution.VERSION_V2,
})

print("[OutsideExec] Typed data built for signing")

--------------------------------------------------------------------------------
-- Step 3: Player signs the typed data off-chain
--------------------------------------------------------------------------------

-- The player signs the structured data. This does NOT submit anything on-chain.
-- In a real game, the player's key would be loaded from KeyStore and the
-- signing would happen server-side (custodial) or via a client signature flow.
local signature = playerAccount:signMessage(typedData)
print("[OutsideExec] Player signed the outside execution")
print("[OutsideExec] Signature r:", signature[1])
print("[OutsideExec] Signature s:", signature[2])

--------------------------------------------------------------------------------
-- Step 4: Relayer submits the execute_from_outside transaction
--------------------------------------------------------------------------------

-- Build the on-chain call that the relayer will submit.
-- This calls execute_from_outside_v2 on the PLAYER'S account contract,
-- passing the player's signed intent. The relayer pays gas.
local outsideExecution = {
	caller = OutsideExecution.ANY_CALLER,
	execute_after = tostring(now - 60),
	execute_before = tostring(now + 3600),
	nonce = tostring(now),
	calls = { outsideCall },
}

local executeCall = OutsideExecution.buildExecuteFromOutsideCall(
	playerAccount.address,
	outsideExecution,
	signature, -- player's signature { r_hex, s_hex }
	OutsideExecution.VERSION_V2
)

print("[OutsideExec] Relayer submitting transaction...")

-- The relayer executes the call using their own account (pays gas)
relayerAccount
	:execute({ executeCall })
	:andThen(function(result)
		print("[OutsideExec] Transaction submitted!")
		print("[OutsideExec] Tx hash:", result.transactionHash)
		return relayerAccount:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("[OutsideExec] Transaction confirmed!")
		print("[OutsideExec] Block:", receipt.block_number)
		print("[OutsideExec] The player's transfer was executed by the relayer")
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) then
			if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
				warn("[OutsideExec] Reverted:", err.revertReason or err.message)
			else
				warn("[OutsideExec] Error:", tostring(err))
			end
		else
			warn("[OutsideExec] Error:", tostring(err))
		end
	end)

return {}
