--!strict
-- typed-data.luau
-- SNIP-12 TypedData signing for structured off-chain messages.
--
-- This example shows how to:
--   1. Build a SNIP-12 TypedData structure with domain and message types
--   2. Hash the message with account:hashMessage()
--   3. Sign the message with account:signMessage()
--   4. Verify the signature using ECDSA
--
-- SNIP-12 TypedData is the Starknet equivalent of EIP-712 — it allows signing
-- structured data with clear type information, preventing blind-signing attacks.
-- Two revisions exist:
--   - Revision "0" (LEGACY): uses Pedersen hashing, domain type "StarkNetDomain"
--   - Revision "1" (ACTIVE): uses Poseidon hashing, domain type "StarknetDomain"
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local TypedData = StarknetLuau.wallet.TypedData
local ECDSA = StarknetLuau.crypto.ECDSA
local BigInt = StarknetLuau.crypto.BigInt
local Constants = StarknetLuau.constants
-- StarknetError available via StarknetLuau.errors.StarknetError for error handling

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- WARNING: Never hardcode private keys in production code.
local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

print("[TypedData] Account address:", account.address)

--------------------------------------------------------------------------------
-- Example 1: Simple typed data (Revision 1 / ACTIVE)
--------------------------------------------------------------------------------

print("[TypedData] --- Example 1: Simple message (Revision 1) ---")

-- Define a typed data structure for a game action confirmation.
-- This follows the SNIP-12 standard with Revision 1 (Poseidon hashing).
local gameActionTypedData = {
	types = {
		-- Domain type must be "StarknetDomain" for Revision 1
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		-- Custom message type
		GameAction = {
			{ name = "action", type = "shortstring" },
			{ name = "player", type = "ContractAddress" },
			{ name = "score", type = "u128" },
			{ name = "timestamp", type = "u128" },
		},
	},
	primaryType = "GameAction",
	domain = {
		name = "MyRobloxGame",
		version = "1",
		chainId = Constants.SN_SEPOLIA,
		revision = "1", -- Revision 1 = ACTIVE (Poseidon)
	},
	message = {
		action = "submit_score",
		player = account.address,
		score = "42000",
		timestamp = tostring(os.time()),
	},
}

-- Hash the typed data message
local messageHash = account:hashMessage(gameActionTypedData)
print("[TypedData] Message hash:", messageHash)

-- Sign the typed data message
-- Returns { r_hex, s_hex } — the ECDSA signature components
local signature = account:signMessage(gameActionTypedData)
print("[TypedData] Signature r:", signature[1])
print("[TypedData] Signature s:", signature[2])

-- Verify the signature using ECDSA
local publicKeyHex = account:getPublicKeyHex()
local isValid = ECDSA.verify(
	BigInt.fromHex(messageHash),
	{ r = BigInt.fromHex(signature[1]), s = BigInt.fromHex(signature[2]) },
	BigInt.fromHex(publicKeyHex)
)
print("[TypedData] Signature valid:", isValid)

--------------------------------------------------------------------------------
-- Example 2: Legacy typed data (Revision 0)
--------------------------------------------------------------------------------

print("[TypedData] --- Example 2: Legacy message (Revision 0) ---")

-- Revision 0 uses Pedersen hashing and "StarkNetDomain" (capital N).
-- Some older contracts and protocols still use this format.
local legacyTypedData = {
	types = {
		-- Note: "StarkNetDomain" (capital N) for Revision 0
		StarkNetDomain = {
			{ name = "name", type = "felt" },
			{ name = "version", type = "felt" },
			{ name = "chainId", type = "felt" },
		},
		-- Simple order type
		Order = {
			{ name = "item_id", type = "felt" },
			{ name = "price", type = "felt" },
			{ name = "buyer", type = "felt" },
		},
	},
	primaryType = "Order",
	domain = {
		name = "GameMarketplace",
		version = "1",
		chainId = Constants.SN_SEPOLIA,
	},
	message = {
		item_id = "0x42",
		price = "0xDE0B6B3A7640000", -- 1e18
		buyer = account.address,
	},
}

-- Identify which revision the typed data uses
local revision = TypedData.identifyRevision(legacyTypedData)
print("[TypedData] Detected revision:", revision) -- "0"

-- Hash and sign
local legacyHash = account:hashMessage(legacyTypedData)
print("[TypedData] Legacy message hash:", legacyHash)

local legacySignature = account:signMessage(legacyTypedData)
print("[TypedData] Legacy signature r:", legacySignature[1])
print("[TypedData] Legacy signature s:", legacySignature[2])

--------------------------------------------------------------------------------
-- Example 3: Complex nested types
--------------------------------------------------------------------------------

print("[TypedData] --- Example 3: Nested types ---")

-- TypedData supports nested structs, arrays, and enums.
local tradeOfferTypedData = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		TradeOffer = {
			{ name = "offerer", type = "ContractAddress" },
			{ name = "item", type = "GameItem" },
			{ name = "price", type = "u256" },
			{ name = "expiry", type = "u128" },
		},
		GameItem = {
			{ name = "collection", type = "ContractAddress" },
			{ name = "token_id", type = "u256" },
		},
	},
	primaryType = "TradeOffer",
	domain = {
		name = "GameTrading",
		version = "1",
		chainId = Constants.SN_SEPOLIA,
		revision = "1",
	},
	message = {
		offerer = account.address,
		item = {
			collection = "0x_NFT_CONTRACT_ADDRESS",
			token_id = { low = "0x1", high = "0x0" },
		},
		price = { low = "0xDE0B6B3A7640000", high = "0x0" }, -- 1 ETH in u256
		expiry = tostring(os.time() + 3600), -- 1 hour from now
	},
}

local tradeHash = account:hashMessage(tradeOfferTypedData)
print("[TypedData] Trade offer hash:", tradeHash)

local tradeSig = account:signMessage(tradeOfferTypedData)
print("[TypedData] Trade signature r:", tradeSig[1])
print("[TypedData] Trade signature s:", tradeSig[2])

-- The signature can be sent to a contract that verifies it on-chain
-- using the account's is_valid_signature() entrypoint (ERC-1271 / SNIP-6)

return {}
