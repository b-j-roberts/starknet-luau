--!strict
-- deploy-account.luau
-- Create and deploy a new player account on Starknet.
--
-- This example shows how to:
--   1. Generate a keypair and derive the counterfactual address
--   2. Check if the account is already deployed
--   3. Estimate deployment fees and verify funding
--   4. Deploy the account via Account:deployAccount()
--   5. Verify deployment by reading the nonce
--
-- Account deployment on Starknet is a two-step process:
--   a. The address is computed deterministically from the class hash + constructor args + salt
--   b. The account must be funded at that address BEFORE deployment (to pay gas)
--   c. The DEPLOY_ACCOUNT transaction creates the contract instance on-chain
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- The private key for the NEW account to deploy.
-- In production, generate this securely via KeyStore or a CSPRNG.
-- WARNING: Never hardcode private keys in production code.
local NEW_ACCOUNT_PRIVATE_KEY = "0x_NEW_ACCOUNT_PRIVATE_KEY_HERE"

-- An already-deployed funder account to send gas to the new address.
-- This is only needed if the new account isn't pre-funded.
local FUNDER_PRIVATE_KEY = "0x_FUNDER_PRIVATE_KEY_HERE"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

--------------------------------------------------------------------------------
-- Step 1: Derive the new account's address (before it exists on-chain)
--------------------------------------------------------------------------------

-- Account.fromPrivateKey computes the address deterministically:
--   address = hash(prefix, deployer=0, salt=publicKey, classHash, constructorCalldata)
-- The account doesn't need to exist on-chain yet — the address is counterfactual.
local newAccount = Account.fromPrivateKey({
	privateKey = NEW_ACCOUNT_PRIVATE_KEY,
	provider = provider,
	accountType = "oz", -- OpenZeppelin account (default)
})

print("[Deploy] New account address:", newAccount.address)
print("[Deploy] Public key:", newAccount:getPublicKeyHex())

--------------------------------------------------------------------------------
-- Helper: fund the new account from a funder wallet
--------------------------------------------------------------------------------

local function fundAccount(targetAddress: string, amount: string)
	print(`[Deploy] Funding {targetAddress} with {amount} STRK...`)

	local funder = Account.fromPrivateKey({
		privateKey = FUNDER_PRIVATE_KEY,
		provider = provider,
	})

	local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider, funder)

	return strkToken
		:transfer(targetAddress, amount)
		:andThen(function(result)
			print("[Deploy] Funding tx:", result.transactionHash)
			return funder:waitForReceipt(result.transactionHash)
		end)
		:andThen(function(receipt)
			print("[Deploy] Funding confirmed in block:", receipt.block_number)
		end)
end

--------------------------------------------------------------------------------
-- Step 2: Check deployment funding requirements
--------------------------------------------------------------------------------

-- checkDeploymentBalance queries the account's ETH/STRK balance and compares
-- it against the estimated deployment fee.
print("[Deploy] Checking deployment balance...")

Account.checkDeploymentBalance({
	provider = provider,
	classHash = Constants.OZ_ACCOUNT_CLASS_HASH,
	publicKey = newAccount:getPublicKeyHex(),
})
	:andThen(function(balanceInfo)
		print("[Deploy] Account balance:", balanceInfo.balance)
		print("[Deploy] Estimated deploy fee:", balanceInfo.estimatedFee)
		print("[Deploy] Token:", balanceInfo.token)
		print("[Deploy] Has sufficient balance:", balanceInfo.hasSufficientBalance)

		if not balanceInfo.hasSufficientBalance then
			print("[Deploy] Account needs funding! Deficit:", balanceInfo.deficit)

			-- Fund the account from the funder wallet
			return fundAccount(newAccount.address, balanceInfo.estimatedFee)
		end

		return nil
	end)
	:andThen(function(_)
		------------------------------------------------------------------------
		-- Step 3: Deploy the account
		------------------------------------------------------------------------

		-- Account:deployAccount() orchestrates the full deployment:
		--   a. Calls getNonce() — if it succeeds, account is already deployed (idempotent)
		--   b. Estimates DEPLOY_ACCOUNT fees with a dummy signature
		--   c. Computes the V3 DEPLOY_ACCOUNT transaction hash (Poseidon)
		--   d. Signs the hash with ECDSA
		--   e. Submits starknet_addDeployAccountTransaction
		--   f. Waits for confirmation (default: true)
		print("[Deploy] Deploying account...")

		return newAccount:deployAccount({
			-- waitForConfirmation defaults to true — blocks until included in a block
			waitForConfirmation = true,
			-- Optional: cap the maximum fee (in wei)
			-- maxFee = "0x2386F26FC10000", -- ~0.01 ETH
		})
	end)
	:andThen(function(result)
		if result.alreadyDeployed then
			print("[Deploy] Account was already deployed!")
		else
			print("[Deploy] Account deployed successfully!")
			print("[Deploy] Transaction hash:", result.transactionHash)
		end
		print("[Deploy] Contract address:", result.contractAddress)

		------------------------------------------------------------------------
		-- Step 4: Verify deployment
		------------------------------------------------------------------------

		-- After deployment, the account should respond to getNonce
		return newAccount:getNonce()
	end)
	:andThen(function(nonce)
		print("[Deploy] Verified — account nonce:", nonce)
		print("[Deploy] Account is ready to use!")
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) then
			if err.code == ErrorCodes.FEE_ESTIMATION_FAILED.code then
				warn("[Deploy] Fee estimation failed — is the account funded?")
			elseif err.code == ErrorCodes.TRANSACTION_REJECTED.code then
				warn("[Deploy] Deployment rejected by node:", err.message)
			else
				warn("[Deploy] Starknet error:", tostring(err))
			end
		else
			warn("[Deploy] Error:", tostring(err))
		end
	end)

return {}
