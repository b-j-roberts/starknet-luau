--!strict
local StarkField = require("../../src/crypto/StarkField")
local fieldTestSuite = require("./fieldTestSuite")

local STARK_PRIME_HEX = "0x800000000000011000000000000000000000000000000000000000000000001"

-- Run the shared field test suite against StarkField
fieldTestSuite(StarkField, StarkField.P, STARK_PRIME_HEX, "StarkField")

-- StarkField-specific: sqrt() via Tonelli-Shanks
describe("StarkField - Square Root", function()
	it("sqrt of zero is zero", function()
		local root = StarkField.sqrt(StarkField.zero())
		expect(root ~= nil):toBe(true)
		expect(StarkField.isZero(root :: buffer)):toBe(true)
	end)

	it("sqrt of one is one", function()
		local root = StarkField.sqrt(StarkField.one())
		expect(root ~= nil):toBe(true)
		expect(StarkField.eq(root :: buffer, StarkField.one())):toBe(true)
	end)

	it("sqrt of 4 squares back to 4", function()
		local four = StarkField.fromNumber(4)
		local root = StarkField.sqrt(four)
		expect(root ~= nil):toBe(true)
		local squared = StarkField.square(root :: buffer)
		expect(StarkField.eq(squared, four)):toBe(true)
	end)

	it("sqrt of perfect square (49)", function()
		local n = StarkField.fromNumber(49)
		local root = StarkField.sqrt(n)
		expect(root ~= nil):toBe(true)
		local squared = StarkField.square(root :: buffer)
		expect(StarkField.eq(squared, n)):toBe(true)
	end)

	it("sqrt of a^2 squares back correctly for large value", function()
		local a = StarkField.fromHex("0xdeadbeef12345678")
		local aSq = StarkField.square(a)
		local root = StarkField.sqrt(aSq)
		expect(root ~= nil):toBe(true)
		local rootSq = StarkField.square(root :: buffer)
		expect(StarkField.eq(rootSq, aSq)):toBe(true)
	end)

	it("sqrt returns nil for non-residue", function()
		-- 3 is a known quadratic non-residue mod P
		local three = StarkField.fromNumber(3)
		local root = StarkField.sqrt(three)
		expect(root == nil):toBe(true)
	end)
end)
