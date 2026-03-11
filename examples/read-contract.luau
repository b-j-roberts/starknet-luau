--!strict
-- read-contract.luau
-- Read ERC-20 token balances from Starknet Sepolia.
--
-- This example shows how to:
--   1. Create an RPC provider pointed at Sepolia
--   2. Instantiate an ERC-20 contract (ETH and STRK)
--   3. Read name, symbol, decimals, and balance for an address
--   4. Format raw u256 balances into human-readable values
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Adjust the path to wherever the SDK is installed in your game
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Public Sepolia RPC endpoint (replace with your own for production)
local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Address to check (replace with any Starknet address)
local TARGET_ADDRESS = "0x_YOUR_STARKNET_ADDRESS_HERE"

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
-- Helper: format a u256 balance with decimals
--------------------------------------------------------------------------------

--- Convert a hex balance string to a human-readable decimal string.
--- WARNING: Lua numbers are f64 — precision loss occurs above 2^53 (~9e15).
--- For balances above ~9000 ETH (9e21 wei), use string-based arithmetic.
local function formatBalance(hexLow: string, decimals: number): string
	local raw = tonumber(hexLow) or 0
	local divisor = 10 ^ decimals
	return string.format("%.6f", raw / divisor)
end

--------------------------------------------------------------------------------
-- Read token metadata
--------------------------------------------------------------------------------

-- Fetch ETH token info
ethToken
	:name()
	:andThen(function(name)
		print("[ETH] Name:", name)
	end)
	:catch(function(err)
		warn("[ETH] Failed to read name:", tostring(err))
	end)

ethToken
	:symbol()
	:andThen(function(symbol)
		print("[ETH] Symbol:", symbol)
	end)
	:catch(function(err)
		warn("[ETH] Failed to read symbol:", tostring(err))
	end)

ethToken
	:decimals()
	:andThen(function(decimals)
		print("[ETH] Decimals:", decimals)
	end)
	:catch(function(err)
		warn("[ETH] Failed to read decimals:", tostring(err))
	end)

-- Fetch STRK token info
strkToken
	:name()
	:andThen(function(name)
		print("[STRK] Name:", name)
	end)
	:catch(function(err)
		warn("[STRK] Failed to read name:", tostring(err))
	end)

strkToken
	:symbol()
	:andThen(function(symbol)
		print("[STRK] Symbol:", symbol)
	end)
	:catch(function(err)
		warn("[STRK] Failed to read symbol:", tostring(err))
	end)

--------------------------------------------------------------------------------
-- Read balances
--------------------------------------------------------------------------------

-- balance_of returns { low: string, high: string } for u256 values
-- The "low" field holds the lower 128 bits (sufficient for most balances)
ethToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		print("[ETH] Balance (raw low):", balance.low)
		print("[ETH] Balance (raw high):", balance.high)
		-- Format as human-readable: divide by 10^18
		print("[ETH] Balance:", formatBalance(balance.low, 18), "ETH")
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) and err.code == ErrorCodes.RPC_ERROR.code then
			warn("[ETH] RPC error reading balance:", err.message)
		else
			warn("[ETH] Failed to read balance:", tostring(err))
		end
	end)

strkToken
	:balance_of(TARGET_ADDRESS)
	:andThen(function(balance)
		print("[STRK] Balance (raw low):", balance.low)
		print("[STRK] Balance (raw high):", balance.high)
		print("[STRK] Balance:", formatBalance(balance.low, 18), "STRK")
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) and err.code == ErrorCodes.RPC_ERROR.code then
			warn("[STRK] RPC error reading balance:", err.message)
		else
			warn("[STRK] Failed to read balance:", tostring(err))
		end
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

return {}
