--!strict
--!native
--!optimize 2
-- FieldFactory: Generates modular arithmetic modules parameterized by a prime modulus.
-- Eliminates duplication between StarkField and StarkScalarField.

local BigInt = require("./BigInt")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

export type FieldElement = buffer

export type Field = {
	modulus: buffer,
	barrettCtx: BigInt.BarrettCtx,
	zero: () -> FieldElement,
	one: () -> FieldElement,
	fromNumber: (n: number) -> FieldElement,
	fromHex: (hex: string) -> FieldElement,
	add: (a: FieldElement, b: FieldElement) -> FieldElement,
	sub: (a: FieldElement, b: FieldElement) -> FieldElement,
	mul: (a: FieldElement, b: FieldElement) -> FieldElement,
	square: (a: FieldElement) -> FieldElement,
	neg: (a: FieldElement) -> FieldElement,
	inv: (a: FieldElement) -> FieldElement,
	toHex: (a: FieldElement) -> string,
	toBigInt: (a: FieldElement) -> BigInt.BigInt,
	eq: (a: FieldElement, b: FieldElement) -> boolean,
	isZero: (a: FieldElement) -> boolean,
	powmod: (base: FieldElement, exp: buffer) -> FieldElement,
}

local FieldFactory = {}

function FieldFactory.createField(modulus: buffer, modulusMinus2: buffer, barrettCtx: BigInt.BarrettCtx, name: string): Field
	local F = {} :: Field
	F.modulus = modulus
	F.barrettCtx = barrettCtx

	-- Internal: reduce a BigInt modulo the field prime
	local function reduce(a: buffer): buffer
		if BigInt.cmp(a, modulus) >= 0 then
			return BigInt.mod(a, modulus)
		end
		return a
	end

	-- Constructors
	function F.zero(): FieldElement
		return BigInt.zero()
	end

	function F.one(): FieldElement
		return BigInt.one()
	end

	function F.fromNumber(n: number): FieldElement
		local b = BigInt.fromNumber(n)
		return reduce(b)
	end

	function F.fromHex(hex: string): FieldElement
		local b = BigInt.fromHex(hex)
		return reduce(b)
	end

	-- Arithmetic (all results reduced mod modulus)
	function F.add(a: FieldElement, b: FieldElement): FieldElement
		return BigInt.addmod(a, b, modulus)
	end

	function F.sub(a: FieldElement, b: FieldElement): FieldElement
		return BigInt.submod(a, b, modulus)
	end

	function F.mul(a: FieldElement, b: FieldElement): FieldElement
		return BigInt.mulmodB(a, b, barrettCtx)
	end

	function F.square(a: FieldElement): FieldElement
		return BigInt.mulmodB(a, a, barrettCtx)
	end

	function F.neg(a: FieldElement): FieldElement
		if BigInt.isZero(a) then
			return BigInt.zero()
		end
		return BigInt.sub(modulus, a)
	end

	function F.inv(a: FieldElement): FieldElement
		if BigInt.isZero(a) then
			error(StarknetError.validation(name .. ": cannot invert zero", ErrorCodes.MATH_ERROR.code))
		end
		-- Fermat's little theorem: a^(mod-2) mod mod
		return BigInt.powmodB(a, modulusMinus2, barrettCtx)
	end

	-- Modular exponentiation (exposed for sqrt and other extensions)
	function F.powmod(base: FieldElement, exp: buffer): FieldElement
		return BigInt.powmodB(base, exp, barrettCtx)
	end

	-- Conversions
	function F.toHex(a: FieldElement): string
		return BigInt.toHex(a)
	end

	function F.toBigInt(a: FieldElement): BigInt.BigInt
		return BigInt.clone(a)
	end

	function F.eq(a: FieldElement, b: FieldElement): boolean
		return BigInt.eq(a, b)
	end

	function F.isZero(a: FieldElement): boolean
		return BigInt.isZero(a)
	end

	return F
end

return FieldFactory
