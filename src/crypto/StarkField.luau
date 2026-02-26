--!strict
--!native
--!optimize 2
-- StarkField: Modular arithmetic over the Stark prime P = 2^251 + 17*2^192 + 1
-- Dedicated Felt type backed by buffer, using BigInt with pre-computed Barrett context

local BigInt = require("./BigInt")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

export type Felt = buffer

local StarkField = {}

-- Stark prime P = 2^251 + 17 * 2^192 + 1
local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")
StarkField.P = P

-- Pre-computed Barrett context for fast modular multiplication
local barrettCtx = BigInt.createBarrettCtx(P)

-- P - 2 for Fermat inversion: a^(P-2) mod P
local P_MINUS_2 = BigInt.fromHex("0x800000000000010ffffffffffffffffffffffffffffffffffffffffffffffff")

-- Tonelli-Shanks parameters for sqrt
-- P - 1 = 2^192 * Q where Q = 0x800000000000011
local TS_S = 192
local TS_Q = BigInt.fromHex("0x800000000000011")
-- z = 3 is a quadratic non-residue mod P
local TS_Z = BigInt.fromNumber(3)

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Reduce a BigInt modulo P (ensures result is in [0, P))
local function reduce(a: buffer): buffer
	if BigInt.cmp(a, P) >= 0 then
		return BigInt.mod(a, P)
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

function StarkField.zero(): Felt
	return BigInt.zero()
end

function StarkField.one(): Felt
	return BigInt.one()
end

function StarkField.fromNumber(n: number): Felt
	local b = BigInt.fromNumber(n)
	return reduce(b)
end

function StarkField.fromHex(hex: string): Felt
	local b = BigInt.fromHex(hex)
	return reduce(b)
end

--------------------------------------------------------------------------------
-- Arithmetic (all results reduced mod P)
--------------------------------------------------------------------------------

function StarkField.add(a: Felt, b: Felt): Felt
	return BigInt.addmod(a, b, P)
end

function StarkField.sub(a: Felt, b: Felt): Felt
	return BigInt.submod(a, b, P)
end

function StarkField.mul(a: Felt, b: Felt): Felt
	return BigInt.mulmodB(a, b, barrettCtx)
end

function StarkField.square(a: Felt): Felt
	return BigInt.mulmodB(a, a, barrettCtx)
end

function StarkField.neg(a: Felt): Felt
	if BigInt.isZero(a) then
		return BigInt.zero()
	end
	return BigInt.sub(P, a)
end

function StarkField.inv(a: Felt): Felt
	if BigInt.isZero(a) then
		error(StarknetError.validation("StarkField: cannot invert zero", ErrorCodes.MATH_ERROR.code))
	end
	-- Fermat's little theorem: a^(P-2) mod P
	return powmodBarrett(a, P_MINUS_2)
end

function StarkField.sqrt(a: Felt): Felt?
	if BigInt.isZero(a) then
		return BigInt.zero()
	end

	-- Tonelli-Shanks algorithm
	-- P - 1 = 2^S * Q where S = 192, Q = 0x800000000000011
	-- z = 3 is a quadratic non-residue

	local M = TS_S
	local c = powmodBarrett(TS_Z, TS_Q)
	local t = powmodBarrett(a, TS_Q)
	local R = powmodBarrett(a, BigInt.shr(BigInt.add(TS_Q, BigInt.one()), 1)) -- a^((Q+1)/2)

	while true do
		if BigInt.isZero(t) then
			return BigInt.zero()
		end
		if BigInt.eq(t, BigInt.one()) then
			return R
		end

		-- Find the least i such that t^(2^i) = 1
		local i = 0
		local tmp = t
		while not BigInt.eq(tmp, BigInt.one()) do
			tmp = BigInt.mulmodB(tmp, tmp, barrettCtx)
			i += 1
			if i >= M then
				-- a is not a quadratic residue
				return nil
			end
		end

		-- Update: b = c^(2^(M-i-1)), M = i, c = b^2, t = t*b^2, R = R*b
		local b = c
		for _ = 1, M - i - 1 do
			b = BigInt.mulmodB(b, b, barrettCtx)
		end

		M = i
		c = BigInt.mulmodB(b, b, barrettCtx)
		t = BigInt.mulmodB(t, c, barrettCtx)
		R = BigInt.mulmodB(R, b, barrettCtx)
	end
end

--------------------------------------------------------------------------------
-- Conversions
--------------------------------------------------------------------------------

function StarkField.toHex(a: Felt): string
	return BigInt.toHex(a)
end

function StarkField.toBigInt(a: Felt): BigInt.BigInt
	return BigInt.clone(a)
end

function StarkField.eq(a: Felt, b: Felt): boolean
	return BigInt.eq(a, b)
end

function StarkField.isZero(a: Felt): boolean
	return BigInt.isZero(a)
end

return StarkField
