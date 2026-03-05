--!strict
--!native
--!optimize 2
-- StarkField: Modular arithmetic over the Stark prime P = 2^251 + 17*2^192 + 1
-- Built via FieldFactory; extends with sqrt() (Tonelli-Shanks).

local BigInt = require("./BigInt")
local FieldFactory = require("./FieldFactory")

export type Felt = buffer

-- Stark prime P = 2^251 + 17 * 2^192 + 1
local P = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")

-- P - 2 for Fermat inversion: a^(P-2) mod P
local P_MINUS_2 = BigInt.fromHex("0x800000000000010ffffffffffffffffffffffffffffffffffffffffffffffff")

-- Pre-computed Barrett context for fast modular multiplication
local barrettCtx = BigInt.createBarrettCtx(P)

-- Generate the base field with all shared operations
local base = FieldFactory.createField(P, P_MINUS_2, barrettCtx, "StarkField")

local StarkField = {}

-- Re-export the modulus
StarkField.P = P

-- Re-export all base field operations
StarkField.zero = base.zero
StarkField.one = base.one
StarkField.fromNumber = base.fromNumber
StarkField.fromHex = base.fromHex
StarkField.add = base.add
StarkField.sub = base.sub
StarkField.mul = base.mul
StarkField.square = base.square
StarkField.neg = base.neg
StarkField.inv = base.inv
StarkField.toHex = base.toHex
StarkField.toBigInt = base.toBigInt
StarkField.eq = base.eq
StarkField.isZero = base.isZero

--------------------------------------------------------------------------------
-- sqrt() extension — Tonelli-Shanks (not applicable to scalar field)
-- The scalar field (curve order N) is used for ECDSA scalars where sqrt is
-- never needed, so only StarkField gets this method.
--------------------------------------------------------------------------------

-- Tonelli-Shanks parameters for sqrt
-- P - 1 = 2^192 * Q where Q = 0x800000000000011
local TS_S = 192
local TS_Q = BigInt.fromHex("0x800000000000011")
-- z = 3 is a quadratic non-residue mod P
local TS_Z = BigInt.fromNumber(3)

function StarkField.sqrt(a: Felt): Felt?
	if BigInt.isZero(a) then
		return BigInt.zero()
	end

	-- Tonelli-Shanks algorithm
	-- P - 1 = 2^S * Q where S = 192, Q = 0x800000000000011
	-- z = 3 is a quadratic non-residue

	local M = TS_S
	local c = base.powmod(TS_Z, TS_Q)
	local t = base.powmod(a, TS_Q)
	local R = base.powmod(a, BigInt.shr(BigInt.add(TS_Q, BigInt.one()), 1)) -- a^((Q+1)/2)

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

return StarkField
