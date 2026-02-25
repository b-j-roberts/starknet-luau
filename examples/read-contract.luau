--!strict
-- read-contract.luau
-- Read ERC-20 token balances from Starknet Sepolia.
--
-- This example shows how to:
--   1. Create an RPC provider pointed at Sepolia
--   2. Instantiate an ERC-20 contract (ETH and STRK)
--   3. Read name, symbol, decimals, and balance for an address
--
-- Usage: Place this Script under ServerScriptService (requires HttpService enabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Adjust the path to wherever the SDK is installed in your game
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Public Sepolia RPC endpoint (replace with your own for production)
local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Address to check (replace with any Starknet address)
local TARGET_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

-- Create a provider connected to Sepolia testnet
local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- Create ERC-20 instances for ETH and STRK tokens
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)
local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider)

--------------------------------------------------------------------------------
-- Read token metadata
--------------------------------------------------------------------------------

-- Fetch ETH token info
ethToken:name():andThen(function(name)
	print("[ETH] Name:", name)
end)

ethToken:symbol():andThen(function(symbol)
	print("[ETH] Symbol:", symbol)
end)

ethToken:decimals():andThen(function(decimals)
	print("[ETH] Decimals:", decimals)
end)

-- Fetch STRK token info
strkToken:name():andThen(function(name)
	print("[STRK] Name:", name)
end)

strkToken:symbol():andThen(function(symbol)
	print("[STRK] Symbol:", symbol)
end)

--------------------------------------------------------------------------------
-- Read balances
--------------------------------------------------------------------------------

-- balance_of returns { low: string, high: string } for u256 values
-- The "low" field holds the lower 128 bits (sufficient for most balances)
ethToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		print("[ETH] Balance (low):", balance.low)
		print("[ETH] Balance (high):", balance.high)
	end)
	:catch(function(err)
		warn("[ETH] Failed to read balance:", tostring(err))
	end)

strkToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		print("[STRK] Balance (low):", balance.low)
		print("[STRK] Balance (high):", balance.high)
	end)
	:catch(function(err)
		warn("[STRK] Failed to read balance:", tostring(err))
	end)

-- You can also read total supply
ethToken
	:total_supply()
	:andThen(function(supply)
		print("[ETH] Total supply (low):", supply.low)
	end)
	:catch(function(err)
		warn("[ETH] Failed to read total supply:", tostring(err))
	end)
