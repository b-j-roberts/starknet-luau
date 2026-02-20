--!strict
-- Signer module: StarkSigner with RFC 6979 deterministic signing

local StarkSigner = require(script.StarkSigner)

return {
	StarkSigner = StarkSigner,
}
