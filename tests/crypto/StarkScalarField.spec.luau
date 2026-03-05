--!strict
local BigInt = require("../../src/crypto/BigInt")
local StarkScalarField = require("../../src/crypto/StarkScalarField")
local fieldTestSuite = require("./fieldTestSuite")

local CURVE_ORDER_HEX = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f"

-- Run the shared field test suite against StarkScalarField
fieldTestSuite(StarkScalarField, StarkScalarField.N, CURVE_ORDER_HEX, "StarkScalarField")

-- StarkScalarField-specific: N differs from P
describe("StarkScalarField - Distinct from StarkField", function()
	it("N differs from the Stark prime P", function()
		local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")
		expect(BigInt.eq(StarkScalarField.N, P)):toBe(false)
	end)
end)

-- StarkScalarField-specific: ECDSA scalar patterns
describe("StarkScalarField - ECDSA Scalar Patterns", function()
	it("simulates s = k_inv * (hash + r * privKey) mod N", function()
		local k = StarkScalarField.fromNumber(7)
		local hash = StarkScalarField.fromNumber(42)
		local r = StarkScalarField.fromNumber(11)
		local privKey = StarkScalarField.fromNumber(13)

		local k_inv = StarkScalarField.inv(k)
		local r_priv = StarkScalarField.mul(r, privKey)
		local inner = StarkScalarField.add(hash, r_priv)
		local s = StarkScalarField.mul(k_inv, inner)

		-- Verify: s * k = hash + r * privKey
		local check = StarkScalarField.mul(s, k)
		expect(StarkScalarField.eq(check, inner)):toBe(true)
	end)

	it("scalar operations with large hex values", function()
		local k = StarkScalarField.fromHex("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
		local hash = StarkScalarField.fromHex("0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321")
		local r = StarkScalarField.fromHex("0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
		local privKey = StarkScalarField.fromHex("0x111111111111111111111111111111111111111111111111111111111111111")

		local k_inv = StarkScalarField.inv(k)
		local r_priv = StarkScalarField.mul(r, privKey)
		local inner = StarkScalarField.add(hash, r_priv)
		local s = StarkScalarField.mul(k_inv, inner)

		-- Verify round-trip: s * k = inner mod N
		local check = StarkScalarField.mul(s, k)
		expect(StarkScalarField.eq(check, inner)):toBe(true)
	end)
end)

-- StarkScalarField-specific: inv with 252-bit value near N
describe("StarkScalarField - Near-boundary Inversion", function()
	it("inv with 252-bit value near N", function()
		local a = StarkScalarField.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2e")
		local inv = StarkScalarField.inv(a)
		local product = StarkScalarField.mul(a, inv)
		expect(StarkScalarField.eq(product, StarkScalarField.one())):toBe(true)
	end)
end)
