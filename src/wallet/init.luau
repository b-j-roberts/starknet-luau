--!strict
-- Wallet module: Account derivation, nonce management (OZ, Argent), SNIP-12 TypedData

local Account = require(script.Account)
local TypedData = require(script.TypedData)

return {
	Account = Account,
	TypedData = TypedData,
}
