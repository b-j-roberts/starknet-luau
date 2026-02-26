--!strict
local BigInt = require("../../src/crypto/BigInt")
local StarkCurve = require("../../src/crypto/StarkCurve")
local ECDSA = require("../../src/crypto/ECDSA")
local StarkSigner = require("../../src/signer/StarkSigner")

--------------------------------------------------------------------------------
-- Test vectors (reuse from ECDSA spec for cross-validation)
--------------------------------------------------------------------------------

local PRIVKEY_HEX_1 = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local PRIVKEY_HEX_2 = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function toHex(b: buffer): string
	return BigInt.toHex(b)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("StarkSigner - constructor", function()
	it("creates a signer from a hex private key", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		expect(signer):toBeTruthy()
	end)

	it("accepts hex string without 0x prefix", function()
		local signer = StarkSigner.new("2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c")
		expect(signer):toBeTruthy()
	end)

	it("errors on zero private key", function()
		expect(function()
			StarkSigner.new("0x0")
		end):toThrowType("SigningError")
	end)

	it("errors on private key >= N", function()
		local N_hex = toHex(StarkCurve.N)
		expect(function()
			StarkSigner.new(N_hex)
		end):toThrowType("SigningError")
	end)
end)

describe("StarkSigner - getPubKey", function()
	it("derives the correct public key", function()
		local signer = StarkSigner.new("0x1")
		local pubKey = signer:getPubKey()
		-- Private key 0x1 should give the generator point G
		expect(StarkCurve.affineEq(pubKey, StarkCurve.G)):toBe(true)
	end)

	it("caches the public key across calls", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local pk1 = signer:getPubKey()
		local pk2 = signer:getPubKey()
		-- Same table reference (cached, not recomputed)
		expect(pk1 == pk2):toBe(true)
	end)

	it("matches @scure/starknet public key test vector", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_2)
		local pubKey = signer:getPubKey()
		expect(toHex(pubKey.x)):toBe("0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf")
	end)
end)

describe("StarkSigner - getPublicKeyHex", function()
	it("returns the public key x-coordinate as hex", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_2)
		local hex = signer:getPublicKeyHex()
		expect(hex):toBe("0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf")
	end)

	it("returns hex with 0x prefix", function()
		local signer = StarkSigner.new("0x1")
		local hex = signer:getPublicKeyHex()
		expect(string.sub(hex, 1, 2)):toBe("0x")
	end)
end)

describe("StarkSigner - signRaw", function()
	it("signs a message hash and returns r and s", function()
		local signer = StarkSigner.new("0x1")
		local hash = BigInt.fromHex("0x1")
		local sig = signer:signRaw(hash)
		expect(sig.r):toBeTruthy()
		expect(sig.s):toBeTruthy()
		expect(BigInt.isZero(sig.r)):toBe(false)
		expect(BigInt.isZero(sig.s)):toBe(false)
	end)

	it("produces deterministic signatures", function()
		local signer = StarkSigner.new("0x42")
		local hash = BigInt.fromHex("0xdeadbeef")
		local sig1 = signer:signRaw(hash)
		local sig2 = signer:signRaw(hash)
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(true)
		expect(BigInt.eq(sig1.s, sig2.s)):toBe(true)
	end)

	it("matches direct ECDSA.sign output", function()
		local privKey = BigInt.fromHex(PRIVKEY_HEX_1)
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47")
		local sigDirect = ECDSA.sign(hash, privKey)
		local sigSigner = signer:signRaw(hash)
		expect(BigInt.eq(sigDirect.r, sigSigner.r)):toBe(true)
		expect(BigInt.eq(sigDirect.s, sigSigner.s)):toBe(true)
	end)

	it("matches @scure/starknet vector: privkey_1, hash_1", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47")
		local sig = signer:signRaw(hash)
		expect(toHex(sig.r)):toBe("0x5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2")
		expect(toHex(sig.s)):toBe("0x4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3")
	end)

	it("produces verifiable signatures", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = BigInt.fromHex("0xdeadbeef")
		local sig = signer:signRaw(hash)
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)
end)

describe("StarkSigner - signTransaction", function()
	it("returns a two-element array of hex strings", function()
		local signer = StarkSigner.new("0x42")
		local txHash = BigInt.fromHex("0x1")
		local result = signer:signTransaction(txHash)
		expect(#result):toBe(2)
		expect(type(result[1])):toBe("string")
		expect(type(result[2])):toBe("string")
	end)

	it("returns hex strings with 0x prefix", function()
		local signer = StarkSigner.new("0x42")
		local txHash = BigInt.fromHex("0x1")
		local result = signer:signTransaction(txHash)
		expect(string.sub(result[1], 1, 2)):toBe("0x")
		expect(string.sub(result[2], 1, 2)):toBe("0x")
	end)

	it("matches signRaw output as hex", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local txHash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47")
		local rawSig = signer:signRaw(txHash)
		local txSig = signer:signTransaction(txHash)
		expect(txSig[1]):toBe(toHex(rawSig.r))
		expect(txSig[2]):toBe(toHex(rawSig.s))
	end)

	it("matches @scure/starknet vector as hex array", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local txHash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47")
		local result = signer:signTransaction(txHash)
		expect(result[1]):toBe("0x5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2")
		expect(result[2]):toBe("0x4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3")
	end)

	it("transaction signature is verifiable", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local txHash = BigInt.fromHex("0xabcdef123456")
		local result = signer:signTransaction(txHash)
		-- Reconstruct signature from hex and verify
		local sig = { r = BigInt.fromHex(result[1]), s = BigInt.fromHex(result[2]) }
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(txHash, pubKey, sig)):toBe(true)
	end)
end)

describe("StarkSigner - multiple signers", function()
	it("different private keys produce different public keys", function()
		local signer1 = StarkSigner.new("0x1")
		local signer2 = StarkSigner.new("0x2")
		expect(StarkCurve.affineEq(signer1:getPubKey(), signer2:getPubKey())):toBe(false)
	end)

	it("different private keys produce different signatures for same message", function()
		local signer1 = StarkSigner.new("0x1")
		local signer2 = StarkSigner.new("0x2")
		local hash = BigInt.fromHex("0x1")
		local sig1 = signer1:signRaw(hash)
		local sig2 = signer2:signRaw(hash)
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(false)
	end)
end)
