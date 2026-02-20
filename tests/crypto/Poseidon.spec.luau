--!strict
local StarkField = require("../../src/crypto/StarkField")
local Poseidon = require("../../src/crypto/Poseidon")

-- Test vectors from starknet.js / @scure/starknet poseidonHash, poseidonHashSingle, poseidonHashMany

describe("Poseidon - hash(a, b)", function()
	it("hash(1, 2) matches starknet.js", function()
		local a = StarkField.fromNumber(1)
		local b = StarkField.fromNumber(2)
		local result = Poseidon.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x5d44a3decb2b2e0cc71071f7b802f45dd792d064f0fc7316c46514f70f9891a")
	end)

	it("hash(0, 0) matches starknet.js", function()
		local a = StarkField.zero()
		local b = StarkField.zero()
		local result = Poseidon.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x293d3e8a80f400daaaffdd5932e2bcc8814bab8f414a75dcacf87318f8b14c5")
	end)

	it("hash(1, 0) matches starknet.js", function()
		local a = StarkField.fromNumber(1)
		local b = StarkField.zero()
		local result = Poseidon.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x7752582c54a42fe0fa35c40f07293bb7d8efe90e21d8d2c06a7db52d7d9b7a1")
	end)

	it("hash(0, 1) matches starknet.js", function()
		local a = StarkField.zero()
		local b = StarkField.fromNumber(1)
		local result = Poseidon.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x5134197931125e849424475aa20cd6ca0ce8603b79177c3f76e2119c8f98c53")
	end)

	it("hash with large field elements matches starknet.js", function()
		local a = StarkField.fromHex("0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb")
		local b = StarkField.fromHex("0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a")
		local result = Poseidon.hash(a, b)
		expect(StarkField.toHex(result)):toBe("0x67c6a2e2d0c7867f97444ae17956dbc89d40ad22255bb06f5f6c515958926ed")
	end)

	it("hash is not commutative (hash(1,2) != hash(2,1))", function()
		local h12 = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		local h21 = Poseidon.hash(StarkField.fromNumber(2), StarkField.fromNumber(1))
		expect(StarkField.eq(h12, h21)):toBe(false)
	end)

	it("hash output is deterministic", function()
		local a = StarkField.fromNumber(42)
		local b = StarkField.fromNumber(99)
		local r1 = Poseidon.hash(a, b)
		local r2 = Poseidon.hash(a, b)
		expect(StarkField.eq(r1, r2)):toBe(true)
	end)
end)

describe("Poseidon - hashSingle(x)", function()
	it("hashSingle(1) matches starknet.js", function()
		local result = Poseidon.hashSingle(StarkField.fromNumber(1))
		expect(StarkField.toHex(result)):toBe("0x6d226d4c804cd74567f5ac59c6a4af1fe2a6eced19fb7560a9124579877da25")
	end)

	it("hashSingle(0) matches starknet.js", function()
		local result = Poseidon.hashSingle(StarkField.zero())
		expect(StarkField.toHex(result)):toBe("0x60009f680a43e6f760790f76214b26243464cdd4f31fdc460baf66d32897c1b")
	end)

	it("hashSingle differs from hash with same first arg", function()
		local single = Poseidon.hashSingle(StarkField.fromNumber(1))
		local double = Poseidon.hash(StarkField.fromNumber(1), StarkField.zero())
		-- hashSingle(1) = fn([1, 0, 1])[0], hash(1, 0) = fn([1, 0, 2])[0]
		-- These should differ because the capacity element differs (1 vs 2)
		expect(StarkField.eq(single, double)):toBe(false)
	end)
end)

describe("Poseidon - hashMany(values)", function()
	it("hashMany([1]) matches starknet.js", function()
		local result = Poseidon.hashMany({ StarkField.fromNumber(1) })
		expect(StarkField.toHex(result)):toBe("0x579e8877c7755365d5ec1ec7d3a94a457eff5d1f40482bbe9729c064cdead2")
	end)

	it("hashMany([1, 2]) matches starknet.js", function()
		local result = Poseidon.hashMany({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
		})
		expect(StarkField.toHex(result)):toBe("0x371cb6995ea5e7effcd2e174de264b5b407027a75a231a70c2c8d196107f0e7")
	end)

	it("hashMany([1, 2, 3]) matches starknet.js", function()
		local result = Poseidon.hashMany({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
			StarkField.fromNumber(3),
		})
		expect(StarkField.toHex(result)):toBe("0x2f0d8840bcf3bc629598d8a6cc80cb7c0d9e52d93dab244bbf9cd0dca0ad082")
	end)

	it("hashMany([1, 2, 3, 4]) matches starknet.js", function()
		local result = Poseidon.hashMany({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
			StarkField.fromNumber(3),
			StarkField.fromNumber(4),
		})
		expect(StarkField.toHex(result)):toBe("0x26e3ad8b876e02bc8a4fc43dad40a8f81a6384083cabffa190bcf40d512ae1d")
	end)

	it("hashMany([]) matches starknet.js (empty input)", function()
		local result = Poseidon.hashMany({})
		expect(StarkField.toHex(result)):toBe("0x2272be0f580fd156823304800919530eaa97430e972d7213ee13f4fbf7a5dbc")
	end)

	it("hashMany with single element differs from hashSingle", function()
		-- hashMany([1]) uses sponge construction with padding
		-- hashSingle(1) uses direct permutation [1, 0, 1]
		local many = Poseidon.hashMany({ StarkField.fromNumber(1) })
		local single = Poseidon.hashSingle(StarkField.fromNumber(1))
		expect(StarkField.eq(many, single)):toBe(false)
	end)

	it("hashMany with two elements differs from hash", function()
		-- hashMany([1,2]) uses sponge with padding
		-- hash(1,2) uses direct permutation [1, 2, 2]
		local many = Poseidon.hashMany({
			StarkField.fromNumber(1),
			StarkField.fromNumber(2),
		})
		local direct = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		expect(StarkField.eq(many, direct)):toBe(false)
	end)
end)

describe("Poseidon - Properties", function()
	it("hash output is non-zero for zero inputs", function()
		local result = Poseidon.hash(StarkField.zero(), StarkField.zero())
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("hashSingle output is non-zero for zero input", function()
		local result = Poseidon.hashSingle(StarkField.zero())
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("hashMany output is non-zero for empty input", function()
		local result = Poseidon.hashMany({})
		expect(StarkField.isZero(result)):toBe(false)
	end)

	it("different inputs produce different hashes", function()
		local h1 = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		local h2 = Poseidon.hash(StarkField.fromNumber(3), StarkField.fromNumber(4))
		expect(StarkField.eq(h1, h2)):toBe(false)
	end)

	it("hash output is a valid field element", function()
		local result = Poseidon.hash(StarkField.fromNumber(1), StarkField.fromNumber(2))
		-- Should be representable as a hex string
		local hex = StarkField.toHex(result)
		expect(string.sub(hex, 1, 2)):toBe("0x")
		-- And re-parseable
		local reparsed = StarkField.fromHex(hex)
		expect(StarkField.eq(result, reparsed)):toBe(true)
	end)
end)
