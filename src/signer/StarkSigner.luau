--!strict
-- StarkSigner: Stark curve signer wrapping ECDSA operations behind a clean interface
-- Handles key derivation, raw signing, and transaction signature formatting

local BigInt = require("../crypto/BigInt")
local StarkCurve = require("../crypto/StarkCurve")
local ECDSA = require("../crypto/ECDSA")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

export type StarkSigner = {
	getPubKey: (self: StarkSigner) -> StarkCurve.AffinePoint,
	getPublicKeyHex: (self: StarkSigner) -> string,
	signRaw: (self: StarkSigner, msgHash: buffer) -> ECDSA.Signature,
	signTransaction: (self: StarkSigner, txHash: buffer) -> { string },
}

local StarkSignerClass = {}
StarkSignerClass.__index = StarkSignerClass

--- Create a new StarkSigner from a hex-encoded private key.
--- @param privateKeyHex -- hex string (with or without "0x" prefix)
function StarkSignerClass.new(privateKeyHex: string): StarkSigner
	local privKey = BigInt.fromHex(privateKeyHex)

	-- Validate private key range: must be in [1, N-1]
	if BigInt.isZero(privKey) then
		error(StarknetError.signing("StarkSigner: private key must not be zero", ErrorCodes.INVALID_PRIVATE_KEY.code))
	end
	if BigInt.cmp(privKey, StarkCurve.N) >= 0 then
		error(
			StarknetError.signing(
				"StarkSigner: private key must be less than curve order N",
				ErrorCodes.KEY_OUT_OF_RANGE.code
			)
		)
	end

	local self = setmetatable({
		_privateKey = privKey,
		_publicKey = nil :: StarkCurve.AffinePoint?,
	}, StarkSignerClass)

	return self :: any
end

--- Derive and cache the public key (expensive EC scalar multiplication on first call).
function StarkSignerClass:getPubKey(): StarkCurve.AffinePoint
	if self._publicKey == nil then
		self._publicKey = StarkCurve.getPublicKey(self._privateKey)
	end
	return self._publicKey :: StarkCurve.AffinePoint
end

--- Return the public key x-coordinate as a hex string (with "0x" prefix).
function StarkSignerClass:getPublicKeyHex(): string
	local pubKey = self:getPubKey()
	return BigInt.toHex(pubKey.x)
end

--- Sign a message hash using Stark ECDSA.
--- @param msgHash -- BigInt buffer representing the hash to sign
--- @return Signature { r: buffer, s: buffer }
function StarkSignerClass:signRaw(msgHash: buffer): ECDSA.Signature
	return ECDSA.sign(msgHash, self._privateKey)
end

--- Sign a transaction hash and return the signature as a felt array [r_hex, s_hex].
--- This is the format expected by Starknet transaction submission.
--- @param txHash -- BigInt buffer representing the transaction hash
--- @return { string } -- array of two hex strings
function StarkSignerClass:signTransaction(txHash: buffer): { string }
	local sig = ECDSA.sign(txHash, self._privateKey)
	return { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }
end

return StarkSignerClass
