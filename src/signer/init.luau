--!strict
-- Signer module: StarkSigner with RFC 6979 deterministic signing
-- Barrel export: uses require(script.X) (Roblox Instance-based). Source modules use require("./X") (relative path).

local StarkSigner = require(script.StarkSigner)

return {
	StarkSigner = StarkSigner,
}
