--!strict
-- leaderboard.luau
-- Read and write an onchain leaderboard contract.
--
-- This example shows how to:
--   1. Define a custom ABI for a game leaderboard contract
--   2. Use Contract.new() with a custom ABI (not just ERC-20/721 presets)
--   3. Read leaderboard state (view functions)
--   4. Submit scores onchain (external functions)
--
-- The example assumes a hypothetical Cairo leaderboard contract with these functions:
--   - get_score(player: ContractAddress) -> u128
--   - get_top_player() -> ContractAddress
--   - get_high_score() -> u128
--   - submit_score(player: ContractAddress, score: u128)
--
-- Usage: Place this Script under ServerScriptService (requires HttpService enabled).
--        Deploy a compatible leaderboard contract and set its address below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Replace with your deployed leaderboard contract address
local LEADERBOARD_ADDRESS = "0x_YOUR_LEADERBOARD_CONTRACT_ADDRESS"

-- Server-side private key for submitting scores (game operator account)
-- WARNING: Never hardcode private keys in production code
local SERVER_PRIVATE_KEY = "0x_YOUR_SERVER_PRIVATE_KEY"

--------------------------------------------------------------------------------
-- Custom ABI for the leaderboard contract
--------------------------------------------------------------------------------

-- Define the ABI matching your Cairo contract's interface.
-- Each entry specifies the function type, name, inputs, outputs, and mutability.
local LEADERBOARD_ABI = {
	-- get_score(player) -> u128 (view)
	{
		type = "function",
		name = "get_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
	-- get_top_player() -> ContractAddress (view)
	{
		type = "function",
		name = "get_top_player",
		inputs = {},
		outputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		state_mutability = "view",
	},
	-- get_high_score() -> u128 (view)
	{
		type = "function",
		name = "get_high_score",
		inputs = {},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
	-- submit_score(player, score) (external)
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

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- Server account for submitting scores
local serverAccount = Account.fromPrivateKey({
	privateKey = SERVER_PRIVATE_KEY,
	provider = provider,
})

-- Read-only contract instance (no account needed for view calls)
local leaderboardReader = Contract.new({
	abi = LEADERBOARD_ABI,
	address = LEADERBOARD_ADDRESS,
	provider = provider,
})

-- Writable contract instance (account attached for external calls)
local leaderboardWriter = Contract.new({
	abi = LEADERBOARD_ABI,
	address = LEADERBOARD_ADDRESS,
	provider = provider,
	account = serverAccount,
})

--------------------------------------------------------------------------------
-- Reading the leaderboard (view functions)
--------------------------------------------------------------------------------

--- Fetch a player's score from the onchain leaderboard.
local function getPlayerScore(playerAddress: string)
	-- Dynamic dispatch: calls get_score as a view function
	leaderboardReader
		:get_score(playerAddress)
		:andThen(function(score: string)
			-- Score is returned as a hex string (single felt)
			local numericScore = tonumber(score, 16) or 0
			print(`[Leaderboard] Score for {playerAddress}: {numericScore}`)
		end)
		:catch(function(err)
			warn("[Leaderboard] Failed to read score:", tostring(err))
		end)
end

--- Fetch the current high score and top player.
local function getHighScore()
	-- Read top player and high score in parallel
	leaderboardReader
		:get_top_player()
		:andThen(function(topPlayer: string)
			print("[Leaderboard] Top player:", topPlayer)
		end)
		:catch(function(err)
			warn("[Leaderboard] Failed to read top player:", tostring(err))
		end)

	leaderboardReader
		:get_high_score()
		:andThen(function(score: string)
			local numericScore = tonumber(score, 16) or 0
			print(`[Leaderboard] High score: {numericScore}`)
		end)
		:catch(function(err)
			warn("[Leaderboard] Failed to read high score:", tostring(err))
		end)
end

--------------------------------------------------------------------------------
-- Writing to the leaderboard (external function via multicall)
--------------------------------------------------------------------------------

--- Submit a player's score onchain.
--- The server account signs and pays for the transaction.
local function submitScore(playerAddress: string, score: number)
	-- Convert numeric score to hex string for calldata encoding
	local scoreHex = string.format("0x%x", score)

	print(`[Leaderboard] Submitting score {score} for {playerAddress}...`)

	-- Dynamic dispatch: calls submit_score as an external function
	-- This goes through account:execute() internally
	leaderboardWriter
		:submit_score(playerAddress, scoreHex)
		:andThen(function(result)
			print("[Leaderboard] Score submitted! Tx:", result.transactionHash)

			-- Wait for confirmation
			return serverAccount:waitForReceipt(result.transactionHash)
		end)
		:andThen(function(receipt)
			print("[Leaderboard] Confirmed in block:", receipt.block_number)
		end)
		:catch(function(err)
			warn("[Leaderboard] Failed to submit score:", tostring(err))
		end)
end

--- Batch-submit multiple scores in a single transaction using multicall.
--- More gas-efficient when updating several players at once.
local function submitScoresBatch(entries: { { address: string, score: number } })
	local calls = {}
	for _, entry in entries do
		local scoreHex = string.format("0x%x", entry.score)
		-- populate() builds the Call object without executing
		local call = leaderboardWriter:populate("submit_score", { entry.address, scoreHex })
		table.insert(calls, call)
	end

	print(`[Leaderboard] Batch submitting {#calls} scores...`)

	serverAccount
		:execute(calls)
		:andThen(function(result)
			print("[Leaderboard] Batch submitted! Tx:", result.transactionHash)
			return serverAccount:waitForReceipt(result.transactionHash)
		end)
		:andThen(function(receipt)
			print("[Leaderboard] Batch confirmed in block:", receipt.block_number)
		end)
		:catch(function(err)
			warn("[Leaderboard] Batch submission failed:", tostring(err))
		end)
end

--------------------------------------------------------------------------------
-- Example usage
--------------------------------------------------------------------------------

-- Read current state
getHighScore()
getPlayerScore("0x_SOME_PLAYER_ADDRESS")

-- Submit a single score
submitScore("0x_SOME_PLAYER_ADDRESS", 42000)

-- Batch submit multiple scores (one transaction, saves gas)
submitScoresBatch({
	{ address = "0x_PLAYER_1", score = 15000 },
	{ address = "0x_PLAYER_2", score = 28500 },
	{ address = "0x_PLAYER_3", score = 42000 },
})

return {
	getPlayerScore = getPlayerScore,
	getHighScore = getHighScore,
	submitScore = submitScore,
	submitScoresBatch = submitScoresBatch,
}
