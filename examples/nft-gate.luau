--!strict
-- nft-gate.luau
-- Check NFT ownership to gate access to game content.
--
-- This example shows how to:
--   1. Prompt a player for their Starknet address
--   2. Check their ERC-721 NFT balance for a specific collection
--   3. Optionally verify ownership of a specific token ID
--   4. Grant or deny access based on the result
--
-- Usage: Place this Script under ServerScriptService (requires HttpService enabled).
--        Create a RemoteFunction named "GetStarknetAddress" in ReplicatedStorage
--        so that players can submit their address from a client UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local ERC721 = StarknetLuau.contract.ERC721

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Replace with your NFT collection contract address on Starknet
local NFT_CONTRACT_ADDRESS = "0x07606a2c55c090e27b3940e2e898e18bea30998c2bfacff643a34f452fac2200"

-- Minimum number of NFTs required to access gated content
local REQUIRED_NFT_COUNT = 1

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

local nftContract = ERC721.new(NFT_CONTRACT_ADDRESS, provider)

-- Track which players have verified NFT ownership
local verifiedPlayers: { [number]: boolean } = {}

--------------------------------------------------------------------------------
-- NFT verification logic
--------------------------------------------------------------------------------

--- Check if a Starknet address owns at least `requiredCount` NFTs.
--- Returns a Promise<boolean>.
local function checkNFTOwnership(playerAddress: string, requiredCount: number): any
	return nftContract:balance_of(playerAddress):andThen(function(balance)
		-- balance is { low: string, high: string } (u256)
		-- For NFT counts, the low field is sufficient (high will be "0x0")
		local count = tonumber(balance.low, 16) or 0
		print(`[NFT Gate] Address {playerAddress} owns {count} NFTs`)
		return count >= requiredCount
	end)
end

--- Check if a Starknet address owns a specific token ID.
--- Returns a Promise<boolean>.
local function checkSpecificNFT(playerAddress: string, tokenId: string): any
	-- owner_of takes a u256 token ID
	return nftContract
		:owner_of(tokenId)
		:andThen(function(owner: string)
			-- Compare addresses (case-insensitive hex comparison)
			local ownsIt = string.lower(owner) == string.lower(playerAddress)
			print(`[NFT Gate] Token {tokenId} owned by {owner}, player match: {ownsIt}`)
			return ownsIt
		end)
		:catch(function(err)
			-- Token may not exist or call may fail
			warn(`[NFT Gate] Failed to check token {tokenId}:`, tostring(err))
			return false
		end)
end

--------------------------------------------------------------------------------
-- Player connection handling
--------------------------------------------------------------------------------

-- Create a RemoteFunction for players to submit their Starknet address
-- In a real game, you'd have a client-side UI for this
local getAddress = Instance.new("RemoteFunction")
getAddress.Name = "VerifyStarknetNFT"
getAddress.Parent = ReplicatedStorage

-- Server handler: player submits their Starknet address for verification
getAddress.OnServerInvoke = function(player: Player, address: string): boolean
	if type(address) ~= "string" or #address < 10 then
		warn(`[NFT Gate] Invalid address from {player.Name}`)
		return false
	end

	print(`[NFT Gate] Verifying NFT ownership for {player.Name} at {address}`)

	-- Check balance-based ownership
	local hasNFT = checkNFTOwnership(address, REQUIRED_NFT_COUNT)
		:andThen(function(result: boolean)
			return result
		end)
		:catch(function(err)
			warn(`[NFT Gate] Verification failed for {player.Name}:`, tostring(err))
			return false
		end)
		:expect()

	if hasNFT then
		verifiedPlayers[player.UserId] = true
		print(`[NFT Gate] {player.Name} VERIFIED - granting access`)
	else
		print(`[NFT Gate] {player.Name} NOT VERIFIED - insufficient NFTs`)
	end

	return hasNFT
end

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player: Player)
	verifiedPlayers[player.UserId] = nil
end)

--- Utility for other scripts to check if a player is verified.
--- Example: if isPlayerVerified(player) then allowEntry() end
local function isPlayerVerified(player: Player): boolean
	return verifiedPlayers[player.UserId] == true
end

print("[NFT Gate] NFT gating system initialized")
print(`[NFT Gate] Collection: {NFT_CONTRACT_ADDRESS}`)
print(`[NFT Gate] Required NFTs: {REQUIRED_NFT_COUNT}`)

return {
	isPlayerVerified = isPlayerVerified,
	checkNFTOwnership = checkNFTOwnership,
	checkSpecificNFT = checkSpecificNFT,
}
