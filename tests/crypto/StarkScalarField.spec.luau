--!strict
local BigInt = require("../../src/crypto/BigInt")
local StarkScalarField = require("../../src/crypto/StarkScalarField")

-- Curve order N
local CURVE_ORDER_HEX = "0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f"

describe("StarkScalarField - Constants", function()
	it("exposes the curve order N", function()
		expect(BigInt.toHex(StarkScalarField.N)):toBe(CURVE_ORDER_HEX)
	end)

	it("N has bit length 252", function()
		expect(BigInt.bitLength(StarkScalarField.N)):toBe(252)
	end)

	it("N differs from the Stark prime P", function()
		local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")
		expect(BigInt.eq(StarkScalarField.N, P)):toBe(false)
	end)
end)

describe("StarkScalarField - Constructors", function()
	it("zero() creates zero element", function()
		local z = StarkScalarField.zero()
		expect(StarkScalarField.isZero(z)):toBe(true)
		expect(StarkScalarField.toHex(z)):toBe("0x0")
	end)

	it("one() creates identity element", function()
		local one = StarkScalarField.one()
		expect(StarkScalarField.isZero(one)):toBe(false)
		expect(StarkScalarField.toHex(one)):toBe("0x1")
	end)

	it("fromNumber creates scalar element", function()
		local n = StarkScalarField.fromNumber(42)
		expect(StarkScalarField.toHex(n)):toBe("0x2a")
	end)

	it("fromHex creates scalar element", function()
		local n = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.toHex(n)):toBe("0xdeadbeef")
	end)

	it("fromHex reduces values >= N", function()
		-- N itself should reduce to 0
		local z = StarkScalarField.fromHex(CURVE_ORDER_HEX)
		expect(StarkScalarField.isZero(z)):toBe(true)
	end)

	it("fromHex reduces N + 1 to 1", function()
		local n = BigInt.fromHex(CURVE_ORDER_HEX)
		local nPlus1 = BigInt.add(n, BigInt.one())
		local scalar = StarkScalarField.fromHex(BigInt.toHex(nPlus1))
		expect(StarkScalarField.eq(scalar, StarkScalarField.one())):toBe(true)
	end)
end)

describe("StarkScalarField - Addition", function()
	it("adds small numbers", function()
		local a = StarkScalarField.fromNumber(123456789)
		local b = StarkScalarField.fromNumber(987654321)
		local c = StarkScalarField.add(a, b)
		expect(StarkScalarField.toHex(c)):toBe("0x423a35c6")
	end)

	it("add with zero is identity", function()
		local a = StarkScalarField.fromNumber(42)
		local c = StarkScalarField.add(a, StarkScalarField.zero())
		expect(StarkScalarField.eq(c, a)):toBe(true)
	end)

	it("add wraps around N", function()
		-- (N - 1) + 1 = 0 mod N
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		local result = StarkScalarField.add(nMinus1, StarkScalarField.one())
		expect(StarkScalarField.isZero(result)):toBe(true)
	end)

	it("add is commutative", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		local b = StarkScalarField.fromHex("0xcafebabe")
		expect(StarkScalarField.eq(StarkScalarField.add(a, b), StarkScalarField.add(b, a))):toBe(true)
	end)
end)

describe("StarkScalarField - Subtraction", function()
	it("subtracts small numbers (a > b)", function()
		local a = StarkScalarField.fromNumber(10)
		local b = StarkScalarField.fromNumber(3)
		local c = StarkScalarField.sub(a, b)
		expect(StarkScalarField.toHex(c)):toBe("0x7")
	end)

	it("sub wraps around N (a < b)", function()
		-- 0 - 1 mod N = N - 1
		local result = StarkScalarField.sub(StarkScalarField.zero(), StarkScalarField.one())
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		expect(BigInt.eq(result, nMinus1)):toBe(true)
	end)

	it("sub self equals zero", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.isZero(StarkScalarField.sub(a, a))):toBe(true)
	end)
end)

describe("StarkScalarField - Negation", function()
	it("neg of zero is zero", function()
		expect(StarkScalarField.isZero(StarkScalarField.neg(StarkScalarField.zero()))):toBe(true)
	end)

	it("a + neg(a) = 0", function()
		local a = StarkScalarField.fromNumber(123456789)
		local negA = StarkScalarField.neg(a)
		local sum = StarkScalarField.add(a, negA)
		expect(StarkScalarField.isZero(sum)):toBe(true)
	end)

	it("neg of 1 equals N - 1", function()
		local negOne = StarkScalarField.neg(StarkScalarField.one())
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		expect(BigInt.eq(negOne, nMinus1)):toBe(true)
	end)
end)

describe("StarkScalarField - Multiplication", function()
	it("multiplies small numbers", function()
		local a = StarkScalarField.fromNumber(123456789)
		local b = StarkScalarField.fromNumber(987654321)
		local c = StarkScalarField.mul(a, b)
		-- 123456789 * 987654321 = 121932631112635269
		expect(StarkScalarField.toHex(c)):toBe("0x1b13114fbff5385")
	end)

	it("mul by zero is zero", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.isZero(StarkScalarField.mul(a, StarkScalarField.zero()))):toBe(true)
	end)

	it("mul by one is identity", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.eq(StarkScalarField.mul(a, StarkScalarField.one()), a)):toBe(true)
	end)

	it("(N-1) * (N-1) = 1 mod N", function()
		-- (-1) * (-1) = 1
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		local result = StarkScalarField.mul(nMinus1, nMinus1)
		expect(StarkScalarField.eq(result, StarkScalarField.one())):toBe(true)
	end)

	it("mul is commutative", function()
		local a = StarkScalarField.fromHex("0xdeadbeef12345678")
		local b = StarkScalarField.fromHex("0xcafebabe87654321")
		expect(StarkScalarField.eq(StarkScalarField.mul(a, b), StarkScalarField.mul(b, a))):toBe(true)
	end)

	it("mul is associative", function()
		local a = StarkScalarField.fromNumber(7)
		local b = StarkScalarField.fromNumber(11)
		local c = StarkScalarField.fromNumber(13)
		local ab_c = StarkScalarField.mul(StarkScalarField.mul(a, b), c)
		local a_bc = StarkScalarField.mul(a, StarkScalarField.mul(b, c))
		expect(StarkScalarField.eq(ab_c, a_bc)):toBe(true)
	end)

	it("mul distributes over add", function()
		local a = StarkScalarField.fromNumber(5)
		local b = StarkScalarField.fromNumber(7)
		local c = StarkScalarField.fromNumber(11)
		local lhs = StarkScalarField.mul(a, StarkScalarField.add(b, c))
		local rhs = StarkScalarField.add(StarkScalarField.mul(a, b), StarkScalarField.mul(a, c))
		expect(StarkScalarField.eq(lhs, rhs)):toBe(true)
	end)
end)

describe("StarkScalarField - Square", function()
	it("square of small number", function()
		local a = StarkScalarField.fromNumber(7)
		local sq = StarkScalarField.square(a)
		expect(StarkScalarField.eq(sq, StarkScalarField.fromNumber(49))):toBe(true)
	end)

	it("square equals mul(a, a)", function()
		local a = StarkScalarField.fromHex("0xdeadbeef12345678cafebabe")
		expect(StarkScalarField.eq(StarkScalarField.square(a), StarkScalarField.mul(a, a))):toBe(true)
	end)

	it("square of zero is zero", function()
		expect(StarkScalarField.isZero(StarkScalarField.square(StarkScalarField.zero()))):toBe(true)
	end)

	it("square of one is one", function()
		expect(StarkScalarField.eq(StarkScalarField.square(StarkScalarField.one()), StarkScalarField.one())):toBe(true)
	end)
end)

describe("StarkScalarField - Inversion", function()
	it("inv of 1 is 1", function()
		local inv = StarkScalarField.inv(StarkScalarField.one())
		expect(StarkScalarField.eq(inv, StarkScalarField.one())):toBe(true)
	end)

	it("a * inv(a) = 1", function()
		local a = StarkScalarField.fromNumber(123456789)
		local inv = StarkScalarField.inv(a)
		local product = StarkScalarField.mul(a, inv)
		expect(StarkScalarField.eq(product, StarkScalarField.one())):toBe(true)
	end)

	it("inv of large value", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		local inv = StarkScalarField.inv(a)
		local product = StarkScalarField.mul(a, inv)
		expect(StarkScalarField.eq(product, StarkScalarField.one())):toBe(true)
	end)

	it("inv of N-1 is N-1 (since (-1)^(-1) = -1)", function()
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		local inv = StarkScalarField.inv(nMinus1)
		expect(BigInt.eq(inv, nMinus1)):toBe(true)
	end)

	it("inv of zero throws", function()
		expect(function()
			StarkScalarField.inv(StarkScalarField.zero())
		end):toThrow()
	end)

	it("double inversion returns original", function()
		local a = StarkScalarField.fromHex("0xcafebabe87654321")
		local inv2 = StarkScalarField.inv(StarkScalarField.inv(a))
		expect(StarkScalarField.eq(inv2, a)):toBe(true)
	end)

	it("inv with 252-bit value near N", function()
		-- A value close to N to stress-test edge cases
		local a = StarkScalarField.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2e")
		local inv = StarkScalarField.inv(a)
		local product = StarkScalarField.mul(a, inv)
		expect(StarkScalarField.eq(product, StarkScalarField.one())):toBe(true)
	end)
end)

describe("StarkScalarField - Conversions", function()
	it("toHex round-trips", function()
		local hex = "0xdeadbeef12345678cafebabe"
		local scalar = StarkScalarField.fromHex(hex)
		expect(StarkScalarField.toHex(scalar)):toBe(hex)
	end)

	it("toBigInt creates independent copy", function()
		local scalar = StarkScalarField.fromNumber(42)
		local bi = StarkScalarField.toBigInt(scalar)
		expect(BigInt.eq(scalar, bi)):toBe(true)
	end)

	it("eq returns true for equal values", function()
		local a = StarkScalarField.fromNumber(42)
		local b = StarkScalarField.fromNumber(42)
		expect(StarkScalarField.eq(a, b)):toBe(true)
	end)

	it("eq returns false for different values", function()
		local a = StarkScalarField.fromNumber(42)
		local b = StarkScalarField.fromNumber(43)
		expect(StarkScalarField.eq(a, b)):toBe(false)
	end)
end)

describe("StarkScalarField - Field Properties", function()
	it("additive identity: a + 0 = a", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.eq(StarkScalarField.add(a, StarkScalarField.zero()), a)):toBe(true)
	end)

	it("multiplicative identity: a * 1 = a", function()
		local a = StarkScalarField.fromHex("0xdeadbeef")
		expect(StarkScalarField.eq(StarkScalarField.mul(a, StarkScalarField.one()), a)):toBe(true)
	end)

	it("additive inverse: a + (-a) = 0", function()
		local a = StarkScalarField.fromHex("0xdeadbeef12345678")
		expect(StarkScalarField.isZero(StarkScalarField.add(a, StarkScalarField.neg(a)))):toBe(true)
	end)

	it("multiplicative inverse: a * a^(-1) = 1", function()
		local a = StarkScalarField.fromHex("0xdeadbeef12345678")
		expect(StarkScalarField.eq(StarkScalarField.mul(a, StarkScalarField.inv(a)), StarkScalarField.one())):toBe(true)
	end)

	it("subtraction is add + neg: a - b = a + (-b)", function()
		local a = StarkScalarField.fromNumber(5)
		local b = StarkScalarField.fromNumber(8)
		local sub = StarkScalarField.sub(a, b)
		local addNeg = StarkScalarField.add(a, StarkScalarField.neg(b))
		expect(StarkScalarField.eq(sub, addNeg)):toBe(true)
	end)

	it("division via mul + inv: a/b = a * inv(b)", function()
		local a = StarkScalarField.fromNumber(42)
		local b = StarkScalarField.fromNumber(7)
		local quotient = StarkScalarField.mul(a, StarkScalarField.inv(b))
		expect(StarkScalarField.eq(quotient, StarkScalarField.fromNumber(6))):toBe(true)
	end)
end)

describe("StarkScalarField - ECDSA Scalar Patterns", function()
	it("simulates s = k_inv * (hash + r * privKey) mod N", function()
		-- Use small test values to verify the computation pattern
		local k = StarkScalarField.fromNumber(7)
		local hash = StarkScalarField.fromNumber(42)
		local r = StarkScalarField.fromNumber(11)
		local privKey = StarkScalarField.fromNumber(13)

		local k_inv = StarkScalarField.inv(k)
		local r_priv = StarkScalarField.mul(r, privKey) -- 143
		local inner = StarkScalarField.add(hash, r_priv) -- 42 + 143 = 185
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

describe("StarkScalarField - Edge Cases", function()
	it("max scalar value N-1", function()
		local nMinus1 = BigInt.sub(StarkScalarField.N, BigInt.one())
		local nMinus1Hex = BigInt.toHex(nMinus1)
		local scalar = StarkScalarField.fromHex(nMinus1Hex)
		expect(StarkScalarField.isZero(scalar)):toBe(false)
		expect(StarkScalarField.toHex(scalar)):toBe(nMinus1Hex)
	end)

	it("N reduces to zero", function()
		expect(StarkScalarField.isZero(StarkScalarField.fromHex(CURVE_ORDER_HEX))):toBe(true)
	end)

	it("2N reduces to zero", function()
		local twoN = BigInt.add(StarkScalarField.N, StarkScalarField.N)
		local scalar = StarkScalarField.fromHex(BigInt.toHex(twoN))
		expect(StarkScalarField.isZero(scalar)):toBe(true)
	end)

	it("operations chain correctly", function()
		-- (a + b) * c - a*c should equal b*c
		local a = StarkScalarField.fromNumber(17)
		local b = StarkScalarField.fromNumber(23)
		local c = StarkScalarField.fromNumber(31)
		local lhs = StarkScalarField.sub(StarkScalarField.mul(StarkScalarField.add(a, b), c), StarkScalarField.mul(a, c))
		local rhs = StarkScalarField.mul(b, c)
		expect(StarkScalarField.eq(lhs, rhs)):toBe(true)
	end)

	it("large value arithmetic near N", function()
		-- Test with values close to N
		local a = StarkScalarField.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
		local b = StarkScalarField.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
		local sum = StarkScalarField.add(a, b)
		-- sum should be < N (properly reduced)
		expect(BigInt.cmp(sum, StarkScalarField.N) < 0):toBe(true)
	end)
end)
