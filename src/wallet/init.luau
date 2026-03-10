--!strict
-- Wallet module: Account derivation, nonce management (OZ, Argent), SNIP-12 TypedData, AccountFactory, OutsideExecution, OnboardingManager
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local Account = require(script.Account)
local TypedData = require(script.TypedData)
local AccountType = require(script.AccountType)
local AccountFactory = require(script.AccountFactory)
local OutsideExecution = require(script.OutsideExecution)
local KeyStore = require(script.KeyStore)
local OnboardingManager = require(script.OnboardingManager)

return {
	Account = Account,
	TypedData = TypedData,
	AccountType = AccountType,
	AccountFactory = AccountFactory,
	OutsideExecution = OutsideExecution,
	KeyStore = KeyStore,
	OnboardingManager = OnboardingManager,
}
