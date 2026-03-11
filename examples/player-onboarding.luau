--!strict
-- player-onboarding.luau
-- Full player lifecycle using KeyStore + OnboardingManager.
--
-- This example shows how to:
--   1. Configure KeyStore for encrypted private key persistence via DataStoreService
--   2. Configure OnboardingManager for one-call player setup
--   3. Handle PlayerAdded: create or load a wallet with getOrCreate → ensureDeployed
--   4. Query player status for UI display (hasAccount, isDeployed, address)
--   5. Clean up on PlayerRemoving
--
-- This is the recommended production pattern for Roblox games that need
-- per-player Starknet accounts. The server custodies encrypted keys;
-- players never see their private key.
--
-- Roblox-only: This script requires HttpService and DataStoreService enabled.
-- Runs in ServerScriptService. DataStoreService requires a published place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local KeyStore = StarknetLuau.wallet.KeyStore
local OnboardingManager = StarknetLuau.wallet.OnboardingManager
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Server secret for encrypting player private keys in DataStoreService.
-- MUST be at least 32 hex characters and kept secret.
-- In production, load this from a secure environment variable or config.
-- WARNING: If you lose this secret, all encrypted keys become unrecoverable.
local SERVER_SECRET = "0xaabbccdd00112233445566778899aabbccddeeff00112233445566778899aabb"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- KeyStore encrypts and persists private keys in DataStoreService.
-- Each player gets a unique encrypted record keyed by their UserId.
local keyStore = KeyStore.new({
	serverSecret = SERVER_SECRET,
	dataStoreName = "StarknetPlayerKeys", -- DataStore name (customizable)
	accountType = "oz", -- OpenZeppelin accounts (default)
})

-- OnboardingManager wraps KeyStore + deployment into a single call.
-- On first join: generates key → encrypts → stores → deploys account.
-- On subsequent joins: loads key → verifies deployment status.
local onboarding = OnboardingManager.new({
	keyStore = keyStore,
	provider = provider,
	-- Set to false to skip waiting for deploy confirmation (faster join times)
	waitForConfirmation = false,
})

-- Track active player accounts (in-memory, per-server)
local activeAccounts: { [number]: any } = {}

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

--- Called when a player joins the game server.
local function onPlayerAdded(player: Player)
	local playerId = tostring(player.UserId)
	print(`[Onboard] Player {player.Name} (ID: {playerId}) joined`)

	-- onboard() is the primary API — handles both new and returning players:
	--   New player: generate key → encrypt → store → compute address → deploy
	--   Returning player: decrypt key → load account → check deployment
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
			warn(`[Onboard] Failed to onboard {player.Name}: {tostring(result)}`)
		end
		return
	end

	activeAccounts[player.UserId] = result.account
	print(`[Onboard] {player.Name} onboarded:`)
	print(`  Address: {result.address}`)
	print(`  New account: {result.isNew}`)
	print(`  Was deployed: {result.wasDeployed}`)
	print(`  Already deployed: {result.alreadyDeployed}`)
end

--- Called when a player leaves the game server.
local function onPlayerRemoving(player: Player)
	print(`[Onboard] Player {player.Name} leaving — cleaning up`)

	-- Remove from in-memory cache
	activeAccounts[player.UserId] = nil

	-- removePlayer delegates to keyStore:deleteKey() — only call this
	-- if you want to wipe the player's key entirely (e.g., GDPR request).
	-- For normal departures, just clear the in-memory reference.
	-- onboarding:removePlayer(tostring(player.UserId))
end

--- Query a player's onboarding status (no RPC calls, no decryption).
--- Useful for UI display: show "Wallet Ready" vs "Setting Up...".
local function getPlayerStatus(player: Player)
	local playerId = tostring(player.UserId)
	local status = onboarding:getStatus(playerId)

	print(`[Onboard] Status for {player.Name}:`)
	print(`  Has account: {status.hasAccount}`)
	print(`  Is deployed: {status.isDeployed}`)
	if status.address then
		print(`  Address: {status.address}`)
	end

	return status
end

--- Ensure a player's account is deployed (call after funding if needed).
--- Errors if the player has no KeyStore record — call onboard() first.
local function ensurePlayerDeployed(player: Player)
	local playerId = tostring(player.UserId)
	print(`[Onboard] Ensuring account is deployed for {player.Name}...`)

	local ok, result = pcall(function()
		return onboarding:ensureDeployed(playerId)
	end)

	if not ok then
		warn(`[Onboard] Deploy failed for {player.Name}: {tostring(result)}`)
		return
	end

	if result.alreadyDeployed then
		print(`[Onboard] Account already deployed for {player.Name}`)
	else
		print(`[Onboard] Account deployed for {player.Name}:`)
		print(`  Tx hash: {result.transactionHash}`)
	end
end

--------------------------------------------------------------------------------
-- Connect to Roblox lifecycle events
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players already in the server (for late-loading scripts)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[Onboard] Player onboarding system initialized")

return {
	getPlayerStatus = getPlayerStatus,
	ensurePlayerDeployed = ensurePlayerDeployed,
	activeAccounts = activeAccounts,
}
