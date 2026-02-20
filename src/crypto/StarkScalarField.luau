--!strict
--!native
--!optimize 2
-- StarkScalarField: Modular arithmetic over the Stark curve order N
-- Used for ECDSA scalar operations: s = k^(-1) * (hash + r*privKey) mod N
-- Same API pattern as StarkField but with modulus N instead of P

local BigInt = require("./BigInt")

export type Scalar = buffer

local StarkScalarField = {}

-- Curve order N
local N = BigInt.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f")
StarkScalarField.N = N

-- Pre-computed Barrett context for fast modular multiplication
local barrettCtx = BigInt.createBarrettCtx(N)

-- N - 2 for Fermat inversion: a^(N-2) mod N
local N_MINUS_2 = BigInt.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2d")

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Reduce a BigInt modulo N (ensures result is in [0, N))
local function reduce(a: buffer): buffer
	if BigInt.cmp(a, N) >= 0 then
		return BigInt.mod(a, N)
	end
	return a
end

-- Modular exponentiation using Barrett context for performance
local function powmodBarrett(base: buffer, exp: buffer): buffer
	if BigInt.isZero(exp) then
		return BigInt.one()
	end

	local b = reduce(base)
	local result = BigInt.one()
	local eBitLen = BigInt.bitLength(exp)

	for i = 0, eBitLen - 1 do
		if BigInt.getBit(exp, i) == 1 then
			result = BigInt.mulmodB(result, b, barrettCtx)
		end
		if i < eBitLen - 1 then
			b = BigInt.mulmodB(b, b, barrettCtx)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- Constructors
--------------------------------------------------------------------------------

function StarkScalarField.zero(): Scalar
	return BigInt.zero()
end

function StarkScalarField.one(): Scalar
	return BigInt.one()
end

function StarkScalarField.fromNumber(n: number): Scalar
	local b = BigInt.fromNumber(n)
	return reduce(b)
end

function StarkScalarField.fromHex(hex: string): Scalar
	local b = BigInt.fromHex(hex)
	return reduce(b)
end

--------------------------------------------------------------------------------
-- Arithmetic (all results reduced mod N)
--------------------------------------------------------------------------------

function StarkScalarField.add(a: Scalar, b: Scalar): Scalar
	return BigInt.addmod(a, b, N)
end

function StarkScalarField.sub(a: Scalar, b: Scalar): Scalar
	return BigInt.submod(a, b, N)
end

function StarkScalarField.mul(a: Scalar, b: Scalar): Scalar
	return BigInt.mulmodB(a, b, barrettCtx)
end

function StarkScalarField.square(a: Scalar): Scalar
	return BigInt.mulmodB(a, a, barrettCtx)
end

function StarkScalarField.neg(a: Scalar): Scalar
	if BigInt.isZero(a) then
		return BigInt.zero()
	end
	return BigInt.sub(N, a)
end

function StarkScalarField.inv(a: Scalar): Scalar
	if BigInt.isZero(a) then
		error("StarkScalarField: cannot invert zero")
	end
	-- Fermat's little theorem: a^(N-2) mod N
	return powmodBarrett(a, N_MINUS_2)
end

--------------------------------------------------------------------------------
-- Conversions
--------------------------------------------------------------------------------

function StarkScalarField.toHex(a: Scalar): string
	return BigInt.toHex(a)
end

function StarkScalarField.toBigInt(a: Scalar): BigInt.BigInt
	return BigInt.clone(a)
end

function StarkScalarField.eq(a: Scalar, b: Scalar): boolean
	return BigInt.eq(a, b)
end

function StarkScalarField.isZero(a: Scalar): boolean
	return BigInt.isZero(a)
end

return StarkScalarField
