--!strict
-- starknet-luau: Pure Luau SDK for Starknet blockchain interaction
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local crypto = require(script.crypto)
local signer = require(script.signer)
local provider = require(script.provider)
local tx = require(script.tx)
local wallet = require(script.wallet)
local contract = require(script.contract)
local constants = require(script.constants)
local errors = require(script.errors)
local paymaster = require(script.paymaster)

return {
	crypto = crypto,
	signer = signer,
	provider = provider,
	tx = tx,
	wallet = wallet,
	contract = contract,
	constants = constants,
	errors = errors,
	paymaster = paymaster,
}
