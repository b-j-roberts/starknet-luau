--!strict
-- Parameterized field test suite: runs the same algebraic property tests against
-- any Field produced by FieldFactory. Eliminates duplication between StarkField
-- and StarkScalarField spec files.

local BigInt = require("../../src/crypto/BigInt")

type FieldModule = {
	zero: () -> buffer,
	one: () -> buffer,
	fromNumber: (n: number) -> buffer,
	fromHex: (hex: string) -> buffer,
	add: (a: buffer, b: buffer) -> buffer,
	sub: (a: buffer, b: buffer) -> buffer,
	mul: (a: buffer, b: buffer) -> buffer,
	square: (a: buffer) -> buffer,
	neg: (a: buffer) -> buffer,
	inv: (a: buffer) -> buffer,
	toHex: (a: buffer) -> string,
	toBigInt: (a: buffer) -> buffer,
	eq: (a: buffer, b: buffer) -> boolean,
	isZero: (a: buffer) -> boolean,
}

local function fieldTestSuite(Field: FieldModule, modulus: buffer, modulusHex: string, name: string)
	describe(`{name} - Constants`, function()
		it("exposes the correct modulus", function()
			expect(BigInt.toHex(modulus)):toBe(modulusHex)
		end)

		it("modulus has bit length 252", function()
			expect(BigInt.bitLength(modulus)):toBe(252)
		end)
	end)

	describe(`{name} - Constructors`, function()
		it("zero() creates zero element", function()
			local z = Field.zero()
			expect(Field.isZero(z)):toBe(true)
			expect(Field.toHex(z)):toBe("0x0")
		end)

		it("one() creates identity element", function()
			local one = Field.one()
			expect(Field.isZero(one)):toBe(false)
			expect(Field.toHex(one)):toBe("0x1")
		end)

		it("fromNumber creates element", function()
			local n = Field.fromNumber(42)
			expect(Field.toHex(n)):toBe("0x2a")
		end)

		it("fromHex creates element", function()
			local n = Field.fromHex("0xdeadbeef")
			expect(Field.toHex(n)):toBe("0xdeadbeef")
		end)

		it("fromHex reduces values >= modulus", function()
			local z = Field.fromHex(modulusHex)
			expect(Field.isZero(z)):toBe(true)
		end)

		it("fromHex reduces modulus + 1 to 1", function()
			local mPlus1 = BigInt.add(modulus, BigInt.one())
			local elem = Field.fromHex(BigInt.toHex(mPlus1))
			expect(Field.eq(elem, Field.one())):toBe(true)
		end)
	end)

	describe(`{name} - Addition`, function()
		it("adds small numbers", function()
			local a = Field.fromNumber(123456789)
			local b = Field.fromNumber(987654321)
			local c = Field.add(a, b)
			expect(Field.toHex(c)):toBe("0x423a35c6")
		end)

		it("add with zero is identity", function()
			local a = Field.fromNumber(42)
			local c = Field.add(a, Field.zero())
			expect(Field.eq(c, a)):toBe(true)
		end)

		it("add wraps around modulus", function()
			local mMinus1 = BigInt.sub(modulus, BigInt.one())
			local result = Field.add(mMinus1, Field.one())
			expect(Field.isZero(result)):toBe(true)
		end)

		it("add is commutative", function()
			local a = Field.fromHex("0xdeadbeef")
			local b = Field.fromHex("0xcafebabe")
			expect(Field.eq(Field.add(a, b), Field.add(b, a))):toBe(true)
		end)
	end)

	describe(`{name} - Subtraction`, function()
		it("subtracts small numbers (a > b)", function()
			local a = Field.fromNumber(10)
			local b = Field.fromNumber(3)
			local c = Field.sub(a, b)
			expect(Field.toHex(c)):toBe("0x7")
		end)

		it("sub wraps around modulus (a < b)", function()
			local result = Field.sub(Field.zero(), Field.one())
			local mMinus1 = BigInt.sub(modulus, BigInt.one())
			expect(BigInt.eq(result, mMinus1)):toBe(true)
		end)

		it("sub self equals zero", function()
			local a = Field.fromHex("0xdeadbeef")
			expect(Field.isZero(Field.sub(a, a))):toBe(true)
		end)
	end)

	describe(`{name} - Negation`, function()
		it("neg of zero is zero", function()
			expect(Field.isZero(Field.neg(Field.zero()))):toBe(true)
		end)

		it("a + neg(a) = 0", function()
			local a = Field.fromNumber(123456789)
			local negA = Field.neg(a)
			local sum = Field.add(a, negA)
			expect(Field.isZero(sum)):toBe(true)
		end)

		it("neg of 1 equals modulus - 1", function()
			local negOne = Field.neg(Field.one())
			local mMinus1 = BigInt.sub(modulus, BigInt.one())
			expect(BigInt.eq(negOne, mMinus1)):toBe(true)
		end)
	end)

	describe(`{name} - Multiplication`, function()
		it("multiplies small numbers", function()
			local a = Field.fromNumber(123456789)
			local b = Field.fromNumber(987654321)
			local c = Field.mul(a, b)
			expect(Field.toHex(c)):toBe("0x1b13114fbff5385")
		end)

		it("mul by zero is zero", function()
			local a = Field.fromHex("0xdeadbeef")
			expect(Field.isZero(Field.mul(a, Field.zero()))):toBe(true)
		end)

		it("mul by one is identity", function()
			local a = Field.fromHex("0xdeadbeef")
			expect(Field.eq(Field.mul(a, Field.one()), a)):toBe(true)
		end)

		it("(mod-1) * (mod-1) = 1", function()
			local mMinus1 = BigInt.sub(modulus, BigInt.one())
			local result = Field.mul(mMinus1, mMinus1)
			expect(Field.eq(result, Field.one())):toBe(true)
		end)

		it("mul is commutative", function()
			local a = Field.fromHex("0xdeadbeef12345678")
			local b = Field.fromHex("0xcafebabe87654321")
			expect(Field.eq(Field.mul(a, b), Field.mul(b, a))):toBe(true)
		end)

		it("mul is associative", function()
			local a = Field.fromNumber(7)
			local b = Field.fromNumber(11)
			local c = Field.fromNumber(13)
			local ab_c = Field.mul(Field.mul(a, b), c)
			local a_bc = Field.mul(a, Field.mul(b, c))
			expect(Field.eq(ab_c, a_bc)):toBe(true)
		end)

		it("mul distributes over add", function()
			local a = Field.fromNumber(5)
			local b = Field.fromNumber(7)
			local c = Field.fromNumber(11)
			local lhs = Field.mul(a, Field.add(b, c))
			local rhs = Field.add(Field.mul(a, b), Field.mul(a, c))
			expect(Field.eq(lhs, rhs)):toBe(true)
		end)
	end)

	describe(`{name} - Square`, function()
		it("square of small number", function()
			local a = Field.fromNumber(7)
			local sq = Field.square(a)
			expect(Field.eq(sq, Field.fromNumber(49))):toBe(true)
		end)

		it("square equals mul(a, a)", function()
			local a = Field.fromHex("0xdeadbeef12345678cafebabe")
			expect(Field.eq(Field.square(a), Field.mul(a, a))):toBe(true)
		end)

		it("square of zero is zero", function()
			expect(Field.isZero(Field.square(Field.zero()))):toBe(true)
		end)

		it("square of one is one", function()
			expect(Field.eq(Field.square(Field.one()), Field.one())):toBe(true)
		end)
	end)

	describe(`{name} - Inversion`, function()
		it("inv of 1 is 1", function()
			local inv = Field.inv(Field.one())
			expect(Field.eq(inv, Field.one())):toBe(true)
		end)

		it("a * inv(a) = 1", function()
			local a = Field.fromNumber(123456789)
			local inv = Field.inv(a)
			local product = Field.mul(a, inv)
			expect(Field.eq(product, Field.one())):toBe(true)
		end)

		it("inv of large value", function()
			local a = Field.fromHex("0xdeadbeef")
			local inv = Field.inv(a)
			local product = Field.mul(a, inv)
			expect(Field.eq(product, Field.one())):toBe(true)
		end)

		it("inv of mod-1 is mod-1 (since (-1)^(-1) = -1)", function()
			local mMinus1 = BigInt.sub(modulus, BigInt.one())
			local inv = Field.inv(mMinus1)
			expect(BigInt.eq(inv, mMinus1)):toBe(true)
		end)

		it("inv of zero throws", function()
			expect(function()
				Field.inv(Field.zero())
			end):toThrow()
		end)

		it("double inversion returns original", function()
			local a = Field.fromHex("0xcafebabe87654321")
			local inv2 = Field.inv(Field.inv(a))
			expect(Field.eq(inv2, a)):toBe(true)
		end)
	end)

	describe(`{name} - Conversions`, function()
		it("toHex round-trips", function()
			local hex = "0xdeadbeef12345678cafebabe"
			local elem = Field.fromHex(hex)
			expect(Field.toHex(elem)):toBe(hex)
		end)

		it("toBigInt creates independent copy", function()
			local elem = Field.fromNumber(42)
			local bi = Field.toBigInt(elem)
			expect(BigInt.eq(elem, bi)):toBe(true)
		end)

		it("eq returns true for equal values", function()
			local a = Field.fromNumber(42)
			local b = Field.fromNumber(42)
			expect(Field.eq(a, b)):toBe(true)
		end)

		it("eq returns false for different values", function()
			local a = Field.fromNumber(42)
			local b = Field.fromNumber(43)
			expect(Field.eq(a, b)):toBe(false)
		end)
	end)

	describe(`{name} - Field Properties`, function()
		it("additive identity: a + 0 = a", function()
			local a = Field.fromHex("0xdeadbeef")
			expect(Field.eq(Field.add(a, Field.zero()), a)):toBe(true)
		end)

		it("multiplicative identity: a * 1 = a", function()
			local a = Field.fromHex("0xdeadbeef")
			expect(Field.eq(Field.mul(a, Field.one()), a)):toBe(true)
		end)

		it("additive inverse: a + (-a) = 0", function()
			local a = Field.fromHex("0xdeadbeef12345678")
			expect(Field.isZero(Field.add(a, Field.neg(a)))):toBe(true)
		end)

		it("multiplicative inverse: a * a^(-1) = 1", function()
			local a = Field.fromHex("0xdeadbeef12345678")
			expect(Field.eq(Field.mul(a, Field.inv(a)), Field.one())):toBe(true)
		end)

		it("subtraction is add + neg: a - b = a + (-b)", function()
			local a = Field.fromNumber(5)
			local b = Field.fromNumber(8)
			local sub = Field.sub(a, b)
			local addNeg = Field.add(a, Field.neg(b))
			expect(Field.eq(sub, addNeg)):toBe(true)
		end)

		it("division via mul + inv: a/b = a * inv(b)", function()
			local a = Field.fromNumber(42)
			local b = Field.fromNumber(7)
			local quotient = Field.mul(a, Field.inv(b))
			expect(Field.eq(quotient, Field.fromNumber(6))):toBe(true)
		end)
	end)

	describe(`{name} - Edge Cases`, function()
		it("modulus reduces to zero", function()
			expect(Field.isZero(Field.fromHex(modulusHex))):toBe(true)
		end)

		it("2 * modulus reduces to zero", function()
			local doubled = BigInt.add(modulus, modulus)
			local elem = Field.fromHex(BigInt.toHex(doubled))
			expect(Field.isZero(elem)):toBe(true)
		end)

		it("operations chain correctly", function()
			-- (a + b) * c - a*c should equal b*c
			local a = Field.fromNumber(17)
			local b = Field.fromNumber(23)
			local c = Field.fromNumber(31)
			local lhs = Field.sub(Field.mul(Field.add(a, b), c), Field.mul(a, c))
			local rhs = Field.mul(b, c)
			expect(Field.eq(lhs, rhs)):toBe(true)
		end)

		it("large value arithmetic near modulus", function()
			local a = Field.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
			local b = Field.fromHex("0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
			local sum = Field.add(a, b)
			expect(BigInt.cmp(sum, modulus) < 0):toBe(true)
		end)
	end)
end

return fieldTestSuite
