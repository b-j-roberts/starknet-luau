--!strict
-- Transaction module: building, hashing, calldata encoding (V3 INVOKE)
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local CallData = require(script.CallData)
local TransactionHash = require(script.TransactionHash)
local TransactionBuilder = require(script.TransactionBuilder)

return {
	CallData = CallData,
	TransactionHash = TransactionHash,
	TransactionBuilder = TransactionBuilder,
}
