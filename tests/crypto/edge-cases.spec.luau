--!strict
-- R.5.5: Signer & Crypto Edge Case Tests
-- Tests boundary conditions for StarkSigner, Pedersen, Poseidon, ECDSA,
-- TransactionHash determinism, and cross-module integration pipelines.

local BigInt = require("../../src/crypto/BigInt")
local StarkField = require("../../src/crypto/StarkField")
local StarkScalarField = require("../../src/crypto/StarkScalarField")
local StarkCurve = require("../../src/crypto/StarkCurve")
local Pedersen = require("../../src/crypto/Pedersen")
local Poseidon = require("../../src/crypto/Poseidon")
local ECDSA = require("../../src/crypto/ECDSA")
local StarkSigner = require("../../src/signer/StarkSigner")
local TransactionHash = require("../../src/tx/TransactionHash")
local ErrorCodes = require("../../src/errors/ErrorCodes")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local N_HEX = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f"
local N_MINUS_1_HEX = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2e"
local N_PLUS_1_HEX = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d30"

local PRIVKEY_HEX_1 = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"

--------------------------------------------------------------------------------
-- StarkSigner - key boundary tests
--------------------------------------------------------------------------------

describe("StarkSigner - key boundary edge cases", function()
	it("accepts key = N-1 (maximum valid private key)", function()
		local signer = StarkSigner.new(N_MINUS_1_HEX)
		expect(signer):toBeTruthy()
	end)

	it("rejects key = N+1 (one above curve order)", function()
		expect(function()
			StarkSigner.new(N_PLUS_1_HEX)
		end):toThrowCode(ErrorCodes.KEY_OUT_OF_RANGE.code)
	end)

	it("rejects key = N (exactly curve order)", function()
		expect(function()
			StarkSigner.new(N_HEX)
		end):toThrowCode(ErrorCodes.KEY_OUT_OF_RANGE.code)
	end)

	it("key = N-1 derives a valid public key", function()
		local signer = StarkSigner.new(N_MINUS_1_HEX)
		local pubKey = signer:getPubKey()
		expect(StarkCurve.isOnCurve(pubKey)):toBe(true)
	end)

	it("key = N-1 public key has same x as generator G (negated point)", function()
		-- (N-1) * G = -G, which has same x-coordinate as G
		local signer = StarkSigner.new(N_MINUS_1_HEX)
		local pubKey = signer:getPubKey()
		expect(BigInt.toHex(pubKey.x)):toBe(BigInt.toHex(StarkCurve.G.x))
	end)

	it("key = 0x1 derives generator point G", function()
		local signer = StarkSigner.new("0x1")
		local pubKey = signer:getPubKey()
		expect(StarkCurve.affineEq(pubKey, StarkCurve.G)):toBe(true)
	end)

	it("key = N-1 produces verifiable signatures", function()
		local signer = StarkSigner.new(N_MINUS_1_HEX)
		local hash = BigInt.fromHex("0xdeadbeef")
		local sig = signer:signRaw(hash)
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- StarkSigner - signRaw with extreme hash values
--------------------------------------------------------------------------------

describe("StarkSigner - signRaw extreme hash values", function()
	it("signRaw(zero) produces a valid signature", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local sig = signer:signRaw(BigInt.zero())
		expect(BigInt.isZero(sig.r)):toBe(false)
		expect(BigInt.isZero(sig.s)):toBe(false)
	end)

	it("signRaw(zero) is verifiable", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = BigInt.zero()
		local sig = signer:signRaw(hash)
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("signRaw(zero) matches expected vector", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local sig = signer:signRaw(BigInt.zero())
		expect(BigInt.toHex(sig.r)):toBe("0x201d95f398a7acd45f1fc0ff3d3cb69273f84041569be2077011adcf737b29b")
		expect(BigInt.toHex(sig.s)):toBe("0x16f0dca53de96a3e328ce4c6a53a011b2f244740eb123a57152b361a8600efb")
	end)

	it("signRaw(N) produces same result as signRaw(zero) (N mod N = 0)", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local sigZero = signer:signRaw(BigInt.zero())
		local sigN = signer:signRaw(StarkCurve.N)
		-- N mod N = 0, so these should be identical
		expect(BigInt.eq(sigZero.r, sigN.r)):toBe(true)
		expect(BigInt.eq(sigZero.s, sigN.s)):toBe(true)
	end)

	it("signRaw(N) is verifiable", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = StarkCurve.N
		local sig = signer:signRaw(hash)
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)

	it("signRaw with large hash near field boundary is verifiable", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)
		local hash = BigInt.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
		local sig = signer:signRaw(hash)
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(hash, pubKey, sig)):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Pedersen - additional hash vectors and hashChain
--------------------------------------------------------------------------------

describe("Pedersen - additional hash vectors", function()
	it("hash(3, 7) matches computed vector", function()
		local result = Pedersen.hash(StarkField.fromNumber(3), StarkField.fromNumber(7))
		expect(StarkField.toHex(result)):toBe("0x6c505c52f8e4437726927802452574a00e3e4e1b9c88ad1e683de626cecb04d")
	end)

	it("hash(42, 99) matches computed vector", function()
		local result = Pedersen.hash(StarkField.fromNumber(42), StarkField.fromNumber(99))
		expect(StarkField.toHex(result)):toBe("0x338a5804a5a73c5ac7dd89b1818a633191884ecff79d798861399cfd58009da")
	end)

	it("hash(0, 1) matches computed vector", function()
		local result = Pedersen.hash(StarkField.zero(), StarkField.fromNumber(1))
		expect(StarkField.toHex(result)):toBe("0x46c9aeb066cc2f41c7124af30514f9e607137fbac950524f5fdace5788f9d43")
	end)

	it("hash(1, 0) matches computed vector", function()
		local result = Pedersen.hash(StarkField.fromNumber(1), StarkField.zero())
		expect(StarkField.toHex(result)):toBe("0x268a9d47dde48af4b6e2c33932ed1c13adec25555abaa837c376af4ea2f8a94")
	end)

	it("hash(0, 1) differs from hash(1, 0)", function()
		local h01 = Pedersen.hash(StarkField.zero(), StarkField.fromNumber(1))
		local h10 = Pedersen.hash(StarkField.fromNumber(1), StarkField.zero())
		expect(StarkField.eq(h01, h10)):toBe(false)
	end)
end)

describe("Pedersen - hashChain", function()
	it("hashChain([]) returns pedersen(0, 0)", function()
		local result = Pedersen.hashChain({})
		-- hashChain([]) = pedersen(0, 0) since start=0, then hash with length=0
		expect(StarkField.toHex(result)):toBe("0x49ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804")
	end)

	it("hashChain([1]) matches expected", function()
		local result = Pedersen.hashChain({ StarkField.fromNumber(1) })
		expect(StarkField.toHex(result)):toBe("0x78d74f61aeaa8286418fd34b3a12a610445eba11d00ecc82ecac2542d55f7a4")
	end)

	it("hashChain([1, 2]) matches expected", function()
		local result = Pedersen.hashChain({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
		})
		expect(StarkField.toHex(result)):toBe("0x501a3a8e6cd4f5241c639c74052aaa34557aafa84dd4ba983d6443c590ab7df")
	end)

	it("hashChain([1, 2, 3]) matches expected", function()
		local result = Pedersen.hashChain({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
			StarkField.fromNumber(3),
		})
		expect(StarkField.toHex(result)):toBe("0xf9d95fbf356fbeda26538c92f7040abe51bf142350f73c9ee5ba7c660bae71")
	end)

	it("hashChain with large field elements matches expected", function()
		local result = Pedersen.hashChain({
			StarkField.fromHex("0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb"),
			StarkField.fromHex("0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a"),
		})
		expect(StarkField.toHex(result)):toBe("0x34bfe5fcf62f931181b7ce515b3d7f9ebb76bee88ee301d950769ecd0118280")
	end)

	it("hashChain is deterministic", function()
		local elems = { StarkField.fromNumber(1), StarkField.fromNumber(2), StarkField.fromNumber(3) }
		local r1 = Pedersen.hashChain(elems)
		local r2 = Pedersen.hashChain(elems)
		expect(StarkField.eq(r1, r2)):toBe(true)
	end)

	it("hashChain with different element order produces different result", function()
		local h12 = Pedersen.hashChain({ StarkField.fromNumber(1), StarkField.fromNumber(2) })
		local h21 = Pedersen.hashChain({ StarkField.fromNumber(2), StarkField.fromNumber(1) })
		expect(StarkField.eq(h12, h21)):toBe(false)
	end)

	it("hashChain([x]) differs from hashChain([x, y]) (length encoding prevents collision)", function()
		local h1 = Pedersen.hashChain({ StarkField.fromNumber(1) })
		local h12 = Pedersen.hashChain({ StarkField.fromNumber(1), StarkField.fromNumber(2) })
		expect(StarkField.eq(h1, h12)):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Poseidon - hashMany with larger inputs and sponge padding
--------------------------------------------------------------------------------

describe("Poseidon - hashMany with larger inputs", function()
	it("hashMany with 5 elements (odd count, tests padding)", function()
		local felts = {}
		for i = 1, 5 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		expect(StarkField.toHex(Poseidon.hashMany(felts))):toBe(
			"0x159f4ab3b9bdc95a6a4a9ffb36456ad33290ea1fa809e0445bc449b0ad62da4"
		)
	end)

	it("hashMany with 7 elements (odd count)", function()
		local felts = {}
		for i = 1, 7 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		expect(StarkField.toHex(Poseidon.hashMany(felts))):toBe(
			"0x16763d80d82ae53e5442d7ac5f76765d3c2780fe9428d4bc3082d4cf3dbfb4f"
		)
	end)

	it("hashMany with 8 elements (multiple absorption rounds)", function()
		local felts = {}
		for i = 1, 8 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		expect(StarkField.toHex(Poseidon.hashMany(felts))):toBe(
			"0x50aa63018b2c4abe73dc6f9db08dbb0fd2f4217f62e9c861a4a91d2e3c0f50"
		)
	end)

	it("hashMany with 16 elements", function()
		local felts = {}
		for i = 1, 16 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		expect(StarkField.toHex(Poseidon.hashMany(felts))):toBe(
			"0x5428484c3fd00f9f0d31476a2844755e70bb196662777dbf731258c83c334ca"
		)
	end)

	it("hashMany with 100 elements (stress test for sponge construction)", function()
		local felts = {}
		for i = 1, 100 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		expect(StarkField.toHex(Poseidon.hashMany(felts))):toBe(
			"0x351fe7b1d8b412ac1e3b46df0e0b51a0bac700edcbad3d6ca8600430c277a00"
		)
	end)

	it("hashMany is deterministic for large inputs", function()
		local felts = {}
		for i = 1, 50 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		local r1 = Poseidon.hashMany(felts)
		local r2 = Poseidon.hashMany(felts)
		expect(StarkField.eq(r1, r2)):toBe(true)
	end)

	it("hashMany with all-zero elements (100 zeros)", function()
		local felts = {}
		for _ = 1, 100 do
			table.insert(felts, StarkField.zero())
		end
		local result = Poseidon.hashMany(felts)
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("adding one more element changes the hash (length sensitivity)", function()
		local felts8 = {}
		for i = 1, 8 do
			table.insert(felts8, StarkField.fromNumber(i))
		end
		local felts9 = {}
		for i = 1, 9 do
			table.insert(felts9, StarkField.fromNumber(i))
		end
		local h8 = Poseidon.hashMany(felts8)
		local h9 = Poseidon.hashMany(felts9)
		expect(StarkField.eq(h8, h9)):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- TransactionHash - determinism property tests
--------------------------------------------------------------------------------

describe("TransactionHash - determinism", function()
	local function makeParams(overrides: { [string]: any }?)
		local base = {
			senderAddress = "0x123",
			compiledCalldata = { "0x1", "0x2" },
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x1",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x1000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}
		if overrides then
			for k, v in overrides do
				(base :: any)[k] = v
			end
		end
		return base
	end

	it("same inputs produce identical INVOKE hashes", function()
		local params = makeParams()
		local h1 = TransactionHash.calculateInvokeTransactionHash(params)
		local h2 = TransactionHash.calculateInvokeTransactionHash(params)
		expect(h1):toBe(h2)
	end)

	it("same inputs produce identical DEPLOY_ACCOUNT hashes", function()
		local params = {
			classHash = "0xabc",
			constructorCalldata = { "0x1" },
			contractAddress = "0x456",
			salt = "0x789",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x1000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}
		local h1 = TransactionHash.calculateDeployAccountTransactionHash(params)
		local h2 = TransactionHash.calculateDeployAccountTransactionHash(params)
		expect(h1):toBe(h2)
	end)

	it("different sender address produces different hash", function()
		local h1 = TransactionHash.calculateInvokeTransactionHash(makeParams({ senderAddress = "0x123" }))
		local h2 = TransactionHash.calculateInvokeTransactionHash(makeParams({ senderAddress = "0x456" }))
		expect(h1 ~= h2):toBe(true)
	end)

	it("different nonce produces different hash", function()
		local h1 = TransactionHash.calculateInvokeTransactionHash(makeParams({ nonce = "0x1" }))
		local h2 = TransactionHash.calculateInvokeTransactionHash(makeParams({ nonce = "0x2" }))
		expect(h1 ~= h2):toBe(true)
	end)

	it("different calldata produces different hash", function()
		local h1 = TransactionHash.calculateInvokeTransactionHash(makeParams({ compiledCalldata = { "0x1" } }))
		local h2 = TransactionHash.calculateInvokeTransactionHash(makeParams({ compiledCalldata = { "0x2" } }))
		expect(h1 ~= h2):toBe(true)
	end)

	it("different chain ID produces different hash", function()
		local h1 = TransactionHash.calculateInvokeTransactionHash(makeParams({ chainId = "0x534e5f5345504f4c4941" }))
		local h2 = TransactionHash.calculateInvokeTransactionHash(makeParams({ chainId = "0x534e5f4d41494e" }))
		expect(h1 ~= h2):toBe(true)
	end)

	it("hash output is a valid hex string", function()
		local h = TransactionHash.calculateInvokeTransactionHash(makeParams())
		expect(string.sub(h, 1, 2)):toBe("0x")
		expect(#h > 2):toBe(true)
	end)

	it("repeatedly hashing (10x) always yields the same result", function()
		local params = makeParams()
		local first = TransactionHash.calculateInvokeTransactionHash(params)
		for _ = 1, 10 do
			expect(TransactionHash.calculateInvokeTransactionHash(params)):toBe(first)
		end
	end)
end)

--------------------------------------------------------------------------------
-- Integration: Poseidon → StarkField → BigInt pipeline
--------------------------------------------------------------------------------

describe("Integration - Poseidon → StarkField → BigInt pipeline", function()
	it("Poseidon hash output round-trips through StarkField and BigInt", function()
		local a = StarkField.fromNumber(42)
		local b = StarkField.fromNumber(99)
		local hashResult = Poseidon.hash(a, b)

		-- StarkField → hex → BigInt → hex → StarkField round-trip
		local hex = StarkField.toHex(hashResult)
		local bigint = BigInt.fromHex(hex)
		local hexBack = BigInt.toHex(bigint)
		local feltBack = StarkField.fromHex(hexBack)

		expect(StarkField.eq(hashResult, feltBack)):toBe(true)
	end)

	it("Poseidon hashMany output is a valid StarkField element (< P)", function()
		local felts = {}
		for i = 1, 10 do
			table.insert(felts, StarkField.fromNumber(i))
		end
		local result = Poseidon.hashMany(felts)
		local hex = StarkField.toHex(result)
		-- Re-parse: if >= P, StarkField.fromHex would reduce it mod P
		local reparsed = StarkField.fromHex(hex)
		expect(StarkField.eq(result, reparsed)):toBe(true)
	end)

	it("StarkField arithmetic on Poseidon output preserves field properties", function()
		local h = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		-- a + 0 = a
		local sum = StarkField.add(h, StarkField.zero())
		expect(StarkField.eq(h, sum)):toBe(true)
		-- a * 1 = a
		local prod = StarkField.mul(h, StarkField.fromNumber(1))
		expect(StarkField.eq(h, prod)):toBe(true)
	end)

	it("BigInt operations on Poseidon output: comparison with P", function()
		local h = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		-- Hash output should be < P (Stark prime)
		local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")
		expect(BigInt.cmp(h, P) < 0):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Integration: ECDSA → StarkCurve → StarkScalarField pipeline
--------------------------------------------------------------------------------

describe("Integration - ECDSA → StarkCurve → StarkScalarField pipeline", function()
	it("full sign-verify cycle with key derivation", function()
		local privKey = BigInt.fromHex(PRIVKEY_HEX_1)
		local pubKey = StarkCurve.getPublicKey(privKey)
		expect(StarkCurve.isOnCurve(pubKey)):toBe(true)

		local msgHash = BigInt.fromHex("0xabcdef")
		local sig = ECDSA.sign(msgHash, privKey)

		-- Signature components are in scalar field [1, N-1]
		expect(BigInt.cmp(sig.r, StarkCurve.N) < 0):toBe(true)
		expect(BigInt.cmp(sig.s, StarkCurve.N) < 0):toBe(true)
		expect(BigInt.isZero(sig.r)):toBe(false)
		expect(BigInt.isZero(sig.s)):toBe(false)

		expect(ECDSA.verify(msgHash, pubKey, sig)):toBe(true)
	end)

	it("scalar multiplication preserves on-curve property", function()
		local scalar = BigInt.fromHex("0xdeadbeef")
		local point = StarkCurve.scalarMul(StarkCurve.G, scalar)
		expect(StarkCurve.isOnCurve(point)):toBe(true)
	end)

	it("scalar field reduction: (N + k) mod N = k", function()
		local k = BigInt.fromNumber(42)
		local nPlusK = BigInt.add(StarkCurve.N, k)
		local reduced = BigInt.mod(nPlusK, StarkCurve.N)
		expect(BigInt.eq(reduced, k)):toBe(true)
	end)

	it("scalar field inverse: a * a^(-1) mod N = 1", function()
		local a = BigInt.fromHex("0xdeadbeef")
		local aInv = StarkScalarField.inv(a)
		local product = StarkScalarField.mul(a, aInv)
		expect(BigInt.eq(product, BigInt.fromNumber(1))):toBe(true)
	end)

	it("ECDSA sign with Poseidon-hashed message (cross-module pipeline)", function()
		-- Simulate transaction-like flow: hash inputs → sign → verify
		local input1 = StarkField.fromHex("0x123")
		local input2 = StarkField.fromHex("0x456")
		local msgHash = Poseidon.hash(input1, input2)

		local privKey = BigInt.fromHex(PRIVKEY_HEX_1)
		local pubKey = StarkCurve.getPublicKey(privKey)
		local sig = ECDSA.sign(msgHash, privKey)
		expect(ECDSA.verify(msgHash, pubKey, sig)):toBe(true)
	end)

	it("ECDSA sign with Pedersen-hashed message (cross-module pipeline)", function()
		local a = StarkField.fromHex("0xabc")
		local b = StarkField.fromHex("0xdef")
		local msgHash = Pedersen.hash(a, b)

		local privKey = BigInt.fromHex(PRIVKEY_HEX_1)
		local pubKey = StarkCurve.getPublicKey(privKey)
		local sig = ECDSA.sign(msgHash, privKey)
		expect(ECDSA.verify(msgHash, pubKey, sig)):toBe(true)
	end)

	it("StarkSigner → TransactionHash → verify full pipeline", function()
		local signer = StarkSigner.new(PRIVKEY_HEX_1)

		-- Compute a transaction hash
		local txHash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x123",
			compiledCalldata = { "0x1" },
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x1000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})

		-- Sign the hash
		local sigHex = signer:signHash(BigInt.fromHex(txHash))
		expect(#sigHex):toBe(2)

		-- Verify the signature
		local sig = { r = BigInt.fromHex(sigHex[1]), s = BigInt.fromHex(sigHex[2]) }
		local pubKey = signer:getPubKey()
		expect(ECDSA.verify(BigInt.fromHex(txHash), pubKey, sig)):toBe(true)
	end)

	it("multiple keys signing same hash produce different signatures", function()
		local hash = BigInt.fromHex("0xdeadbeef")
		local signer1 = StarkSigner.new("0x1")
		local signer2 = StarkSigner.new("0x2")
		local signer3 = StarkSigner.new(PRIVKEY_HEX_1)

		local sig1 = signer1:signRaw(hash)
		local sig2 = signer2:signRaw(hash)
		local sig3 = signer3:signRaw(hash)

		-- All r values should differ (different k from RFC 6979)
		expect(BigInt.eq(sig1.r, sig2.r)):toBe(false)
		expect(BigInt.eq(sig2.r, sig3.r)):toBe(false)
		expect(BigInt.eq(sig1.r, sig3.r)):toBe(false)

		-- All should be independently verifiable
		expect(ECDSA.verify(hash, signer1:getPubKey(), sig1)):toBe(true)
		expect(ECDSA.verify(hash, signer2:getPubKey(), sig2)):toBe(true)
		expect(ECDSA.verify(hash, signer3:getPubKey(), sig3)):toBe(true)
	end)
end)
