--!strict
local BigInt = require("../../src/crypto/BigInt")
local StarkCurve = require("../../src/crypto/StarkCurve")
local StarkScalarField = require("../../src/crypto/StarkScalarField")
local ECDSA = require("../../src/crypto/ECDSA")

--------------------------------------------------------------------------------
-- Test vectors from @scure/starknet (compatible with starknet.js)
-- Source: https://github.com/paulmillr/scure-starknet/blob/main/test/stark.test.ts
--------------------------------------------------------------------------------

-- Vector set 1: private key used across 4 signing tests
local PRIVKEY_1 = BigInt.fromHex("0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c")

-- Vector set 2: different private key with 5 message hashes
local PRIVKEY_2 = BigInt.fromHex("0x7D0F499B250763F4CACF0D8D9E267D012C03503CE5DE876B33D3A3837DC90AF")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function toHex(b: buffer): string
	return BigInt.toHex(b)
end

describe("ECDSA - generateK (RFC 6979 deterministic nonce)", function()
	it("generates a deterministic k for the same inputs", function()
		local hash = BigInt.fromHex("0x1")
		local privKey = BigInt.fromHex("0x1")
		local k1 = ECDSA.generateK(hash, privKey)
		local k2 = ECDSA.generateK(hash, privKey)
		expect(BigInt.eq(k1, k2)):toBe(true)
	end)

	it("generates different k for different message hashes", function()
		local privKey = BigInt.fromHex("0x1")
		local k1 = ECDSA.generateK(BigInt.fromHex("0x1"), privKey)
		local k2 = ECDSA.generateK(BigInt.fromHex("0x2"), privKey)
		expect(BigInt.eq(k1, k2)):toBe(false)
	end)

	it("generates different k for different private keys", function()
		local hash = BigInt.fromHex("0x1")
		local k1 = ECDSA.generateK(hash, BigInt.fromHex("0x1"))
		local k2 = ECDSA.generateK(hash, BigInt.fromHex("0x2"))
		expect(BigInt.eq(k1, k2)):toBe(false)
	end)

	it("generates k in valid range [1, N-1]", function()
		local N = StarkScalarField.N
		local testKeys = {
			BigInt.fromHex("0x1"),
			BigInt.fromHex("0xdeadbeef"),
			PRIVKEY_1,
			PRIVKEY_2,
		}
		local testHashes = {
			BigInt.fromHex("0x1"),
			BigInt.fromHex("0xabcdef"),
			BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47"),
		}
		for _, privKey in testKeys do
			for _, hash in testHashes do
				local k = ECDSA.generateK(hash, privKey)
				expect(BigInt.isZero(k)):toBe(false)
				expect(BigInt.cmp(k, N) < 0):toBe(true)
			end
		end
	end)
end)

describe("ECDSA - sign (Stark ECDSA signing)", function()
	it("signs and returns r and s components", function()
		local hash = BigInt.fromHex("0x1")
		local privKey = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(sig.r):toBeTruthy()
		expect(sig.s):toBeTruthy()
		expect(BigInt.isZero(sig.r)):toBe(false)
		expect(BigInt.isZero(sig.s)):toBe(false)
	end)

	it("produces deterministic signatures (same input -> same output)", function()
		local hash = BigInt.fromHex("0xdeadbeef")
		local privKey = BigInt.fromHex("0x42")
		local sig1 = ECDSA.sign(hash, privKey)
		local sig2 = ECDSA.sign(hash, privKey)
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(true)
		expect(BigInt.eq(sig1.s, sig2.s)):toBe(true)
	end)

	it("produces different signatures for different messages", function()
		local privKey = BigInt.fromHex("0x42")
		local sig1 = ECDSA.sign(BigInt.fromHex("0x1"), privKey)
		local sig2 = ECDSA.sign(BigInt.fromHex("0x2"), privKey)
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(false)
	end)

	it("produces different signatures for different keys", function()
		local hash = BigInt.fromHex("0x1")
		local sig1 = ECDSA.sign(hash, BigInt.fromHex("0x1"))
		local sig2 = ECDSA.sign(hash, BigInt.fromHex("0x2"))
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(false)
	end)

	-- Cross-reference: @scure/starknet test vector set 1, vector 1
	it("matches @scure/starknet vector: privkey_1, hash_1", function()
		local hash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47")
		local sig = ECDSA.sign(hash, PRIVKEY_1)
		expect(toHex(sig.r)):toBe("0x5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2")
		expect(toHex(sig.s)):toBe("0x4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3")
	end)

	-- Cross-reference: @scure/starknet test vector set 1, vector 3
	it("matches @scure/starknet vector: privkey_1, hash_3", function()
		local hash = BigInt.fromHex("0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47a")
		local sig = ECDSA.sign(hash, PRIVKEY_1)
		expect(toHex(sig.r)):toBe("0x233b88c4578f0807b4a7480c8076eca5cfefa29980dd8e2af3c46a253490e9c")
		expect(toHex(sig.s)):toBe("0x28b055e825bc507349edfb944740a35c6f22d377443c34742c04e0d82278cf1")
	end)

	-- Cross-reference: @scure/starknet test vector set 1, vector 4
	it("matches @scure/starknet vector: privkey_1, hash_4", function()
		local hash = BigInt.fromHex("0x7465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47a1")
		local sig = ECDSA.sign(hash, PRIVKEY_1)
		expect(toHex(sig.r)):toBe("0xb6bee8010f96a723f6de06b5fa06e820418712439c93850dd4e9bde43ddf")
		expect(toHex(sig.s)):toBe("0x1a3d2bc954ed77e22986f507d68d18115fa543d1901f5b4620db98e2f6efd80")
	end)

	-- Cross-reference: @scure/starknet test vector set 2, vector 1
	it("matches @scure/starknet vector: privkey_2, hash '0x00'", function()
		local hash = BigInt.fromHex("0x00")
		local sig = ECDSA.sign(hash, PRIVKEY_2)
		expect(toHex(sig.r)):toBe("0x443b6a567dfeae1c8c77dc589cdde204649f85ba45e54bead543299e5888233")
		expect(toHex(sig.s)):toBe("0x12bcacdadecfca0773945071b371adda1bc47fce319f80aa590b06d45a996f5")
	end)

	-- Cross-reference: @scure/starknet test vector set 2, vector 2
	it("matches @scure/starknet vector: privkey_2, long hash 1", function()
		local hash = BigInt.fromHex("0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F61")
		local sig = ECDSA.sign(hash, PRIVKEY_2)
		expect(toHex(sig.r)):toBe("0x78a73ac7f793e706e50871da2efc2f83c30852a90110cab71108ff6a3af864e")
		expect(toHex(sig.s)):toBe("0x49ec9e6aa783e7518ffc05ec054db3ddf2d8ad301e4ee790392841fa759431e")
	end)

	-- Cross-reference: @scure/starknet test vector set 2, vector 3
	it("matches @scure/starknet vector: privkey_2, long hash 2", function()
		local hash = BigInt.fromHex("0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C")
		local sig = ECDSA.sign(hash, PRIVKEY_2)
		expect(toHex(sig.r)):toBe("0x5864e5d2843d4469e70282042c7675e4fcb4b530d45dd6f02ae03c8d2f5431a")
		expect(toHex(sig.s)):toBe("0x2c512662f37585497683e2d98c655e098ad4504d41d3a3b17ad0f0f9db45ddb")
	end)

	-- Cross-reference: @scure/starknet test vector set 2, vector 4
	it("matches @scure/starknet vector: privkey_2, long hash 3", function()
		local hash = BigInt.fromHex("0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C1D")
		local sig = ECDSA.sign(hash, PRIVKEY_2)
		expect(toHex(sig.r)):toBe("0x7f313dc69e5f785a7071a9acc12a1294bce54d199a90b1ecdd39fd654c55190")
		expect(toHex(sig.s)):toBe("0x7a2902b67913c013557f0ea61902a1edc8539aa1321549bef9a47dbb9af0eba")
	end)

	-- Cross-reference: @scure/starknet test vector set 2, vector 5
	it("matches @scure/starknet vector: privkey_2, long hash 4", function()
		local hash = BigInt.fromHex("0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C1D00")
		local sig = ECDSA.sign(hash, PRIVKEY_2)
		expect(toHex(sig.r)):toBe("0x73bab8d7be901dc6bdba59f458c3ddeb4e0264657c60ff1b42a403d69e84718")
		expect(toHex(sig.s)):toBe("0x4cb6384d5b82bf873c87e02e11d32cefb1f10cc6d3d67895662d6c87c6df505")
	end)

	it("errors on zero private key", function()
		expect(function()
			ECDSA.sign(BigInt.fromHex("0x1"), BigInt.zero())
		end):toThrowType("SigningError")
	end)

	it("errors on private key >= N", function()
		expect(function()
			ECDSA.sign(BigInt.fromHex("0x1"), StarkScalarField.N)
		end):toThrowType("SigningError")
	end)
end)

describe("ECDSA - verify (Stark ECDSA verification)", function()
	it("verifies a valid signature (round-trip with sign)", function()
		local hash = BigInt.fromHex("0x1")
		local privKey = BigInt.fromHex("0x1")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("verifies with various private keys and messages", function()
		local testCases = {
			{ key = "0x2", hash = "0x3" },
			{ key = "0xdeadbeef", hash = "0xcafebabe" },
			{ key = "0x42", hash = "0x0" },
			{
				key = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c",
				hash = "0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47",
			},
		}
		for _, tc in testCases do
			local privKey = BigInt.fromHex(tc.key)
			local hash = BigInt.fromHex(tc.hash)
			local pubKey = StarkCurve.getPublicKey(privKey)
			local sig = ECDSA.sign(hash, privKey)
			expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
		end
	end)

	it("rejects signature with wrong message hash", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local sig = ECDSA.sign(BigInt.fromHex("0x1"), privKey)
		-- Verify with different message
		expect(ECDSA.verify(BigInt.fromHex("0x2"), pubKey, sig)):toBe(false)
	end)

	it("rejects signature with wrong public key", function()
		local privKey1 = BigInt.fromHex("0x1")
		local privKey2 = BigInt.fromHex("0x2")
		local pubKey2 = StarkCurve.getPublicKey(privKey2)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey1)
		-- Verify with wrong public key
		expect(ECDSA.verify(hash, pubKey2, sig)):toBe(false)
	end)

	it("rejects signature with tampered r", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		-- Tamper with r
		local tamperedR = BigInt.add(sig.r, BigInt.one())
		expect(ECDSA.verify(hash, pubKey, { r = tamperedR, s = sig.s })):toBe(false)
	end)

	it("rejects signature with tampered s", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		-- Tamper with s
		local tamperedS = BigInt.add(sig.s, BigInt.one())
		expect(ECDSA.verify(hash, pubKey, { r = sig.r, s = tamperedS })):toBe(false)
	end)

	it("rejects signature with r = 0", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, { r = BigInt.zero(), s = sig.s })):toBe(false)
	end)

	it("rejects signature with s = 0", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, { r = sig.r, s = BigInt.zero() })):toBe(false)
	end)

	it("rejects signature with r >= N", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, { r = StarkScalarField.N, s = sig.s })):toBe(false)
	end)

	it("rejects signature with s >= N", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, { r = sig.r, s = StarkScalarField.N })):toBe(false)
	end)

	-- Verify the @scure/starknet test vectors
	it("verifies @scure/starknet vector set 1 signatures", function()
		local pubKey = StarkCurve.getPublicKey(PRIVKEY_1)
		local vectors = {
			{
				hash = "0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47",
				r = "0x5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2",
				s = "0x4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3",
			},
			{
				hash = "0xc465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47a",
				r = "0x233b88c4578f0807b4a7480c8076eca5cfefa29980dd8e2af3c46a253490e9c",
				s = "0x28b055e825bc507349edfb944740a35c6f22d377443c34742c04e0d82278cf1",
			},
		}
		for _, v in vectors do
			local hash = BigInt.fromHex(v.hash)
			local sig = { r = BigInt.fromHex(v.r), s = BigInt.fromHex(v.s) }
			expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
		end
	end)

	it("verifies @scure/starknet vector set 2 signatures", function()
		local pubKey = StarkCurve.getPublicKey(PRIVKEY_2)
		local vectors = {
			{
				hash = "0x00",
				r = "0x443b6a567dfeae1c8c77dc589cdde204649f85ba45e54bead543299e5888233",
				s = "0x12bcacdadecfca0773945071b371adda1bc47fce319f80aa590b06d45a996f5",
			},
			{
				hash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F61",
				r = "0x78a73ac7f793e706e50871da2efc2f83c30852a90110cab71108ff6a3af864e",
				s = "0x49ec9e6aa783e7518ffc05ec054db3ddf2d8ad301e4ee790392841fa759431e",
			},
			{
				hash = "0x40DC8ABE9797B6EF5C0886AD4A78405CD393493D2B6A8733B77250F610C",
				r = "0x5864e5d2843d4469e70282042c7675e4fcb4b530d45dd6f02ae03c8d2f5431a",
				s = "0x2c512662f37585497683e2d98c655e098ad4504d41d3a3b17ad0f0f9db45ddb",
			},
		}
		for _, v in vectors do
			local hash = BigInt.fromHex(v.hash)
			local sig = { r = BigInt.fromHex(v.r), s = BigInt.fromHex(v.s) }
			expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
		end
	end)
end)

describe("ECDSA - edge cases", function()
	it("handles message hash of zero", function()
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.zero()
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("handles small private key (0x1)", function()
		local privKey = BigInt.fromHex("0x1")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0xdeadbeef")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("handles large message hash near field boundary", function()
		-- Hash close to the Stark prime P
		local privKey = BigInt.fromHex("0x42")
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("handles private key = N - 1 (maximum valid)", function()
		local privKey = BigInt.sub(StarkScalarField.N, BigInt.one())
		local pubKey = StarkCurve.getPublicKey(privKey)
		local hash = BigInt.fromHex("0x1")
		local sig = ECDSA.sign(hash, privKey)
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("signature r and s are in valid range [1, N-1]", function()
		local N = StarkScalarField.N
		local testCases = {
			{ key = "0x1", hash = "0x1" },
			{ key = "0x42", hash = "0xdeadbeef" },
			{ key = "0xdeadbeef", hash = "0x42" },
		}
		for _, tc in testCases do
			local sig = ECDSA.sign(BigInt.fromHex(tc.hash), BigInt.fromHex(tc.key))
			expect(BigInt.isZero(sig.r)):toBe(false)
			expect(BigInt.cmp(sig.r, N) < 0):toBe(true)
			expect(BigInt.isZero(sig.s)):toBe(false)
			expect(BigInt.cmp(sig.s, N) < 0):toBe(true)
		end
	end)
end)

describe("ECDSA - public key derivation cross-check", function()
	it("private key 0x1 gives generator point G as public key", function()
		local privKey = BigInt.fromHex("0x1")
		local pubKey = StarkCurve.getPublicKey(privKey)
		expect(StarkCurve.affineEq(pubKey, StarkCurve.G)):toBe(true)
	end)

	-- Cross-reference: @scure/starknet public key test vector
	it("matches @scure/starknet getPublicKey test vector", function()
		local privKey = BigInt.fromHex("0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F")
		local pubKey = StarkCurve.getPublicKey(privKey)
		expect(toHex(pubKey.x)):toBe("0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf")
	end)
end)
