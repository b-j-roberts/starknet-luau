--!strict
-- Paymaster module: SNIP-29 paymaster client for sponsored transactions
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local PaymasterRpc = require(script.PaymasterRpc)
local AvnuPaymaster = require(script.AvnuPaymaster)
local PaymasterPolicy = require(script.PaymasterPolicy)
local PaymasterBudget = require(script.PaymasterBudget)
local SponsoredExecutor = require(script.SponsoredExecutor)

return {
	PaymasterRpc = PaymasterRpc,
	AvnuPaymaster = AvnuPaymaster,
	PaymasterPolicy = PaymasterPolicy,
	PaymasterBudget = PaymasterBudget,
	SponsoredExecutor = SponsoredExecutor,
}
