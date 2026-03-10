--!strict
-- AccountType: Account type configurations with constructor calldata builders
-- Each account type carries its class hash and is callable to produce constructor calldata.
-- Usage:
--   AccountType.OZ("0xpubkey") → { "0xpubkey" }
--   AccountType.Argent("0xownerKey") → { "0x0", "0xownerKey", "0x0" }
--   AccountType.Argent("0xownerKey", "0xguardianKey") → { "0x0", "0xownerKey", "0x1", "0x0", "0xguardianKey" }
--   AccountType.Braavos("0xpubkey") → { "0xpubkey" }
--
-- Class hash versioning:
--   OZ v0.8.1:     0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f
--   Argent v0.4.0:  0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f
--   These hashes correspond to specific on-chain contract versions. When new contract versions
--   are deployed, use AccountType.custom() to supply updated class hashes.

local Constants = require("../constants")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = require("../errors/ErrorCodes")

local AccountType = {}

--------------------------------------------------------------------------------
-- OZ account type
--------------------------------------------------------------------------------

-- OpenZeppelin account type configuration.
-- Callable: AccountType.OZ(publicKey) → { publicKey }
AccountType.OZ = setmetatable({
	type = "oz" :: string,
	classHash = Constants.OZ_ACCOUNT_CLASS_HASH :: string,
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
	classHash = Constants.ARGENT_ACCOUNT_CLASS_HASH :: string,
}, {
	__call = function(_self: any, ownerKey: string, guardianKey: string?): { string }
		if guardianKey then
			return { "0x0", ownerKey, "0x1", "0x0", guardianKey }
		end
		return { "0x0", ownerKey, "0x0" }
	end,
})

--------------------------------------------------------------------------------
-- Braavos account type
--------------------------------------------------------------------------------

-- Braavos account type configuration (v1.2.0).
-- Uses the base class hash for address computation.
-- Callable: AccountType.Braavos(publicKey) → { publicKey }
AccountType.Braavos = setmetatable({
	type = "braavos" :: string,
	classHash = Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH :: string,
}, {
	__call = function(_self: any, publicKey: string): { string }
		return { publicKey }
	end,
})

--------------------------------------------------------------------------------
-- Type lookup
--------------------------------------------------------------------------------

-- Lookup table for getting an account type by name string.
local TYPE_REGISTRY: { [string]: any } = {
	oz = AccountType.OZ,
	argent = AccountType.Argent,
	braavos = AccountType.Braavos,
}

--- Get an account type configuration by name.
--- Returns the callable account type object, or nil if not found.
function AccountType.get(typeName: string): any
	return TYPE_REGISTRY[typeName]
end

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
	if not config or type(config) ~= "table" then
		error(StarknetError.validation("AccountType.custom: config is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.type or type(config.type) ~= "string" then
		error(
			StarknetError.validation(
				"AccountType.custom: config.type must be a string",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end
	if not config.classHash or type(config.classHash) ~= "string" then
		error(
			StarknetError.validation(
				"AccountType.custom: config.classHash must be a string",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end
	if not config.buildCalldata or type(config.buildCalldata) ~= "function" then
		error(
			StarknetError.validation(
				"AccountType.custom: config.buildCalldata must be a function",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end
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
