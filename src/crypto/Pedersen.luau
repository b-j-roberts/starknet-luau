--!strict
--!native
--!optimize 2
-- Pedersen: Hash function over the Stark curve using elliptic curve point operations
-- H(a, b) = [shift + a_low*P0 + a_high*P1 + b_low*P2 + b_high*P3].x
-- where a_low/b_low = lower 248 bits, a_high/b_high = upper 4 bits
-- Uses precomputed lookup tables for efficient bit-by-bit point addition
-- Reference: https://docs.starkware.co/starkex/crypto/pedersen-hash-function.html

local BigInt = require("./BigInt")
local StarkField = require("./StarkField")
local StarkCurve = require("./StarkCurve")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

type Felt = StarkField.Felt
type AffinePoint = StarkCurve.AffinePoint
type JacobianPoint = StarkCurve.JacobianPoint

local Pedersen = {}

--------------------------------------------------------------------------------
-- Constant base points (from pedersen_params.json CONSTANT_POINTS, derived from π)
-- Indices: SHIFT=0, P0=2, P1=250, P2=254, P3=502
-- SHIFT_POINT: prevents point-at-infinity during computation
-- P0: generator for low 248 bits of first input
-- P1: generator for high 4 bits of first input
-- P2: generator for low 248 bits of second input
-- P3: generator for high 4 bits of second input
--------------------------------------------------------------------------------

local SHIFT_POINT: AffinePoint = {
	x = StarkField.fromHex("0x049ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804"),
	y = StarkField.fromHex("0x03ca0cfe4b3bc6ddf346d49d06ea0ed34e621062c0e056c1d0405d266e10268a"),
}

local P0: AffinePoint = {
	x = StarkField.fromHex("0x0234287dcbaffe7f969c748655fca9e58fa8120b6d56eb0c1080d17957ebe47b"),
	y = StarkField.fromHex("0x03b056f100f96fb21e889527d41f4e39940135dd7a6c94cc6ed0268ee89e5615"),
}

local P1: AffinePoint = {
	x = StarkField.fromHex("0x04fa56f376c83db33f9dab2656558f3399099ec1de5e3018b7a6932dba8aa378"),
	y = StarkField.fromHex("0x03fa0984c931c9e38113e0c0e47e4401562761f92a7a23b45168f4e80ff5b54d"),
}

local P2: AffinePoint = {
	x = StarkField.fromHex("0x04ba4cc166be8dec764910f75b45f74b40c690c74709e90f3aa372f0bd2d6997"),
	y = StarkField.fromHex("0x0040301cf5c1751f4b971e46c4ede85fcac5c59a5ce5ae7c48151f27b24b219c"),
}

local P3: AffinePoint = {
	x = StarkField.fromHex("0x054302dcb0e6cc1c6e44cca8f61a63bb2ca65048d53fb325d36ff12c49a58202"),
	y = StarkField.fromHex("0x01b77b3e37d13504b348046268d8ae25ce98ad783c25561a879dcc77e99c2426"),
}

--------------------------------------------------------------------------------
-- Precomputed lookup tables (lazily initialized)
-- POINTS1[j] = 2^(j-1) * P0 for j=1..248, 2^(j-249) * P1 for j=249..252
-- POINTS2[j] = 2^(j-1) * P2 for j=1..248, 2^(j-249) * P3 for j=249..252
--------------------------------------------------------------------------------

local POINTS1: { JacobianPoint }? = nil
local POINTS2: { JacobianPoint }? = nil

local function precomputeTable(pLow: AffinePoint, pHigh: AffinePoint): { JacobianPoint }
	local tbl: { JacobianPoint } = {}

	-- First 248 entries: 2^0 * pLow, 2^1 * pLow, ..., 2^247 * pLow
	local current = StarkCurve.jacobianFromAffine(pLow)
	for j = 1, 248 do
		tbl[j] = { x = current.x, y = current.y, z = current.z }
		current = StarkCurve.jacobianDouble(current)
	end

	-- Last 4 entries: 2^0 * pHigh, 2^1 * pHigh, ..., 2^3 * pHigh
	current = StarkCurve.jacobianFromAffine(pHigh)
	for j = 249, 252 do
		tbl[j] = { x = current.x, y = current.y, z = current.z }
		current = StarkCurve.jacobianDouble(current)
	end

	return tbl
end

local function ensureTables()
	if POINTS1 == nil then
		POINTS1 = precomputeTable(P0, P1)
		POINTS2 = precomputeTable(P2, P3)
	end
end

--------------------------------------------------------------------------------
-- Process a single element: iterate through 252 bits, adding precomputed points
-- for each set bit in the value
--------------------------------------------------------------------------------

local function processSingleElement(acc: JacobianPoint, value: buffer, points: { JacobianPoint }): JacobianPoint
	for j = 0, 251 do
		if BigInt.getBit(value, j) == 1 then
			acc = StarkCurve.jacobianAdd(acc, points[j + 1])
		end
	end
	return acc
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- hash(a, b): Pedersen hash of two field elements
-- Returns the x-coordinate of: shift + a_low*P0 + a_high*P1 + b_low*P2 + b_high*P3
function Pedersen.hash(a: Felt, b: Felt): Felt
	ensureTables()

	local aInt = StarkField.toBigInt(a)
	local bInt = StarkField.toBigInt(b)

	local acc = StarkCurve.jacobianFromAffine(SHIFT_POINT)
	acc = processSingleElement(acc, aInt, POINTS1 :: { JacobianPoint })
	acc = processSingleElement(acc, bInt, POINTS2 :: { JacobianPoint })

	local result = StarkCurve.affineFromJacobian(acc)
	if result == nil then
		error(StarknetError.new("Pedersen: hash resulted in point at infinity", ErrorCodes.MATH_ERROR.code))
	end
	return (result :: AffinePoint).x
end

return Pedersen
