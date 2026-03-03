--!strict
-- AccountType: Account type configurations with constructor calldata builders
-- Each account type carries its class hash and is callable to produce constructor calldata.
-- Usage:
--   AccountType.OZ("0xpubkey") → { "0xpubkey" }
--   AccountType.Argent("0xownerKey") → { "0x0", "0xownerKey", "0x0" }
--   AccountType.Argent("0xownerKey", "0xguardianKey") → { "0x0", "0xownerKey", "0x1", "0x0", "0xguardianKey" }
--
-- Class hash versioning:
--   OZ v0.8.1:     0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f
--   Argent v0.4.0:  0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f
--   These hashes correspond to specific on-chain contract versions. When new contract versions
--   are deployed, use AccountType.custom() to supply updated class hashes.

local AccountType = {}

--------------------------------------------------------------------------------
-- Class hash constants
--------------------------------------------------------------------------------

-- OpenZeppelin Account class hash (Cairo 1, v0.8.1)
AccountType.OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

-- Argent X Account class hash (Cairo 1, v0.4.0)
AccountType.ARGENT_CLASS_HASH = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"

--------------------------------------------------------------------------------
-- OZ account type
--------------------------------------------------------------------------------

-- OpenZeppelin account type configuration.
-- Callable: AccountType.OZ(publicKey) → { publicKey }
AccountType.OZ = setmetatable({
	type = "oz" :: string,
	classHash = AccountType.OZ_CLASS_HASH :: string,
}, {
	__call = function(_self: any, publicKey: string): { string }
		return { publicKey }
	end,
})

--------------------------------------------------------------------------------
-- Argent account type
--------------------------------------------------------------------------------

-- Argent X account type configuration (v0.4.0+).
-- Uses Cairo enum serialization for constructor calldata:
--   Signer::Starknet(pubkey) = [0, pubkey]
--   Option::None = [0], Option::Some(Signer::Starknet(guardian)) = [1, 0, guardianKey]
-- Callable:
--   AccountType.Argent(ownerKey) → { "0x0", ownerKey, "0x0" }
--   AccountType.Argent(ownerKey, guardianKey) → { "0x0", ownerKey, "0x1", "0x0", guardianKey }
AccountType.Argent = setmetatable({
	type = "argent" :: string,
	classHash = AccountType.ARGENT_CLASS_HASH :: string,
}, {
	__call = function(_self: any, ownerKey: string, guardianKey: string?): { string }
		if guardianKey then
			return { "0x0", ownerKey, "0x1", "0x0", guardianKey }
		end
		return { "0x0", ownerKey, "0x0" }
	end,
})

--------------------------------------------------------------------------------
-- Custom account type
--------------------------------------------------------------------------------

--- Create a custom account type configuration with a user-supplied class hash and calldata builder.
--- Useful when new contract versions are deployed with different class hashes.
---
--- Example:
---   local myType = AccountType.custom({
---       type = "oz",
---       classHash = "0xnew_oz_class_hash",
---       buildCalldata = function(publicKey) return { publicKey } end,
---   })
---   local calldata = myType("0xpubkey") -- { "0xpubkey" }
function AccountType.custom(config: {
	type: string,
	classHash: string,
	buildCalldata: (...any) -> { string },
}): any
	return setmetatable({
		type = config.type,
		classHash = config.classHash,
	}, {
		__call = function(_self: any, ...: any): { string }
			return config.buildCalldata(...)
		end,
	})
end

return AccountType
