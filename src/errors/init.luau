--!strict
-- errors: Barrel export for error system
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local StarknetError = require(script.StarknetError)
local ErrorCodes = require(script.ErrorCodes)

return {
	StarknetError = StarknetError,
	ErrorCodes = ErrorCodes,
}
