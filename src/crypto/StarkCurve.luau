--!strict
--!native
--!optimize 2
-- StarkCurve: Elliptic curve point operations on the Stark curve
-- y² = x³ + αx + β (short Weierstrass with α=1)
-- Jacobian coordinates: (X, Y, Z) represents affine (X/Z², Y/Z³)

local BigInt = require("./BigInt")
local StarkField = require("./StarkField")
local StarkScalarField = require("./StarkScalarField")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

type Felt = StarkField.Felt

export type AffinePoint = {
	x: Felt,
	y: Felt,
}

export type JacobianPoint = {
	x: Felt,
	y: Felt,
	z: Felt,
}

local StarkCurve = {}

-- Curve parameters: y² = x³ + αx + β
local ALPHA = StarkField.one()
local BETA = StarkField.fromHex("0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89")

StarkCurve.ALPHA = ALPHA
StarkCurve.BETA = BETA

-- Generator point G
local GX = StarkField.fromHex("0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca")
local GY = StarkField.fromHex("0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f")
StarkCurve.G = { x = GX, y = GY } :: AffinePoint

-- Curve order N (imported from StarkScalarField — single source of truth)
StarkCurve.N = StarkScalarField.N

-- Point at infinity sentinel (affine representation for identity element)
-- Has no geometric meaning on the curve, but avoids nil returns from scalarMul(k=0).
-- Check with StarkCurve.isInfinityAffine(p).
StarkCurve.INFINITY = { x = StarkField.zero(), y = StarkField.zero() } :: AffinePoint

--------------------------------------------------------------------------------
-- Point predicates
--------------------------------------------------------------------------------

function StarkCurve.isInfinity(p: JacobianPoint): boolean
	return StarkField.isZero(p.z)
end

--- Check if an affine point is the INFINITY sentinel.
function StarkCurve.isInfinityAffine(p: AffinePoint): boolean
	return StarkField.isZero(p.x) and StarkField.isZero(p.y)
end

function StarkCurve.isOnCurve(p: AffinePoint): boolean
	-- Check y² = x³ + αx + β
	local x2 = StarkField.square(p.x)
	local x3 = StarkField.mul(x2, p.x)
	local ax = StarkField.mul(ALPHA, p.x)
	local rhs = StarkField.add(StarkField.add(x3, ax), BETA)
	local lhs = StarkField.square(p.y)
	return StarkField.eq(lhs, rhs)
end

function StarkCurve.affineEq(a: AffinePoint, b: AffinePoint): boolean
	return StarkField.eq(a.x, b.x) and StarkField.eq(a.y, b.y)
end

function StarkCurve.affineNeg(p: AffinePoint): AffinePoint
	return { x = p.x, y = StarkField.neg(p.y) }
end

--------------------------------------------------------------------------------
-- Coordinate conversion
--------------------------------------------------------------------------------

function StarkCurve.jacobianFromAffine(p: AffinePoint): JacobianPoint
	return {
		x = p.x,
		y = p.y,
		z = StarkField.one(),
	}
end

function StarkCurve.affineFromJacobian(p: JacobianPoint): AffinePoint
	if StarkField.isZero(p.z) then
		return StarkCurve.INFINITY
	end
	-- Affine = (X/Z², Y/Z³)
	local zInv = StarkField.inv(p.z)
	local zInv2 = StarkField.square(zInv)
	local zInv3 = StarkField.mul(zInv2, zInv)
	return {
		x = StarkField.mul(p.x, zInv2),
		y = StarkField.mul(p.y, zInv3),
	}
end

--------------------------------------------------------------------------------
-- Jacobian point doubling
-- Formula: dbl-2001-b from hyperelliptic.org/EFD for a=1
-- Cost: 1S + 5M + 8add (field operations)
--------------------------------------------------------------------------------

function StarkCurve.jacobianDouble(p: JacobianPoint): JacobianPoint
	if StarkField.isZero(p.z) or StarkField.isZero(p.y) then
		return { x = StarkField.one(), y = StarkField.one(), z = StarkField.zero() }
	end

	local F = StarkField
	local XX = F.square(p.x) -- X1²
	local YY = F.square(p.y) -- Y1²
	local YYYY = F.square(YY) -- Y1⁴
	local ZZ = F.square(p.z) -- Z1²

	-- S = 2*((X1+YY)² - XX - YYYY) = 4*X1*Y1²
	local S = F.sub(F.sub(F.square(F.add(p.x, YY)), XX), YYYY)
	S = F.add(S, S)

	-- M = 3*XX + α*ZZ² (α=1, so M = 3*XX + ZZ²)
	local ZZZZ = F.square(ZZ)
	local M = F.add(F.add(XX, F.add(XX, XX)), ZZZZ)

	-- X3 = M² - 2*S
	local X3 = F.sub(F.square(M), F.add(S, S))

	-- Y3 = M*(S - X3) - 8*YYYY
	local YYYY2 = F.add(YYYY, YYYY)
	local YYYY4 = F.add(YYYY2, YYYY2)
	local YYYY8 = F.add(YYYY4, YYYY4)
	local Y3 = F.sub(F.mul(M, F.sub(S, X3)), YYYY8)

	-- Z3 = (Y1+Z1)² - YY - ZZ = 2*Y1*Z1
	local Z3 = F.sub(F.sub(F.square(F.add(p.y, p.z)), YY), ZZ)

	return { x = X3, y = Y3, z = Z3 }
end

--------------------------------------------------------------------------------
-- Jacobian point addition
-- Standard Jacobian addition (avoids field inversions)
-- Handles P1=P2 (delegates to doubling) and P1=-P2 (returns identity)
--------------------------------------------------------------------------------

function StarkCurve.jacobianAdd(p1: JacobianPoint, p2: JacobianPoint): JacobianPoint
	if StarkField.isZero(p1.z) then
		return p2
	end
	if StarkField.isZero(p2.z) then
		return p1
	end

	local F = StarkField
	local Z1Z1 = F.square(p1.z)
	local Z2Z2 = F.square(p2.z)
	local U1 = F.mul(p1.x, Z2Z2)
	local U2 = F.mul(p2.x, Z1Z1)
	local S1 = F.mul(F.mul(p1.y, p2.z), Z2Z2) -- Y1 * Z2³
	local S2 = F.mul(F.mul(p2.y, p1.z), Z1Z1) -- Y2 * Z1³

	local H = F.sub(U2, U1)
	local R = F.sub(S2, S1)

	if F.isZero(H) then
		if F.isZero(R) then
			-- Same point: delegate to doubling
			return StarkCurve.jacobianDouble(p1)
		end
		-- Inverse points: return identity
		return { x = F.one(), y = F.one(), z = F.zero() }
	end

	local HH = F.square(H)
	local HHH = F.mul(H, HH)
	local V = F.mul(U1, HH)

	-- X3 = R² - H³ - 2*V
	local X3 = F.sub(F.sub(F.square(R), HHH), F.add(V, V))

	-- Y3 = R*(V - X3) - S1*H³
	local Y3 = F.sub(F.mul(R, F.sub(V, X3)), F.mul(S1, HHH))

	-- Z3 = Z1 * Z2 * H
	local Z3 = F.mul(F.mul(p1.z, p2.z), H)

	return { x = X3, y = Y3, z = Z3 }
end

--------------------------------------------------------------------------------
-- Scalar multiplication (4-bit windowed method)
-- Precomputes table[1..15] = i*P, then processes scalar in 4-bit windows.
-- Reduces additions from ~126 to ~63 for 252-bit scalars (~40% fewer additions).
-- Returns INFINITY sentinel for k=0.
--------------------------------------------------------------------------------

function StarkCurve.scalarMul(p: AffinePoint, k: buffer): AffinePoint
	local bitLen = BigInt.bitLength(k)
	if bitLen == 0 then
		return StarkCurve.INFINITY
	end

	local jP = StarkCurve.jacobianFromAffine(p)

	-- Precompute: precomp[i] = i * P for i = 1..15
	local precomp = table.create(15)
	precomp[1] = jP
	precomp[2] = StarkCurve.jacobianDouble(jP)
	for i = 3, 15 do
		precomp[i] = StarkCurve.jacobianAdd(precomp[i - 1], jP)
	end

	-- Process first partial window (1-4 bits)
	local firstWindowSize = ((bitLen - 1) % 4) + 1
	local topBit = bitLen - 1
	local windowVal = 0
	for b = 0, firstWindowSize - 1 do
		windowVal = windowVal * 2 + BigInt.getBit(k, topBit - b)
	end

	local result: JacobianPoint
	if windowVal > 0 then
		result = precomp[windowVal]
	else
		result = { x = StarkField.one(), y = StarkField.one(), z = StarkField.zero() }
	end
	topBit = topBit - firstWindowSize

	-- Process remaining full 4-bit windows
	while topBit >= 0 do
		result = StarkCurve.jacobianDouble(result)
		result = StarkCurve.jacobianDouble(result)
		result = StarkCurve.jacobianDouble(result)
		result = StarkCurve.jacobianDouble(result)

		windowVal = BigInt.getBit(k, topBit) * 8
			+ BigInt.getBit(k, topBit - 1) * 4
			+ BigInt.getBit(k, topBit - 2) * 2
			+ BigInt.getBit(k, topBit - 3)

		if windowVal > 0 then
			result = StarkCurve.jacobianAdd(result, precomp[windowVal])
		end
		topBit = topBit - 4
	end

	return StarkCurve.affineFromJacobian(result)
end

--------------------------------------------------------------------------------
-- Shamir's trick: simultaneous scalar multiplication
-- Computes k1*p1 + k2*p2 in a single pass using joint bit scanning.
-- Precomputes table: T[1]=p2, T[2]=p1, T[3]=p1+p2
-- ~50% faster than two independent scalarMul calls for ECDSA verify.
--------------------------------------------------------------------------------

function StarkCurve.shamirMul(p1: AffinePoint, k1: buffer, p2: AffinePoint, k2: buffer): AffinePoint
	local bitLen1 = BigInt.bitLength(k1)
	local bitLen2 = BigInt.bitLength(k2)

	if bitLen1 == 0 and bitLen2 == 0 then
		return StarkCurve.INFINITY
	end
	if bitLen1 == 0 then
		return StarkCurve.scalarMul(p2, k2)
	end
	if bitLen2 == 0 then
		return StarkCurve.scalarMul(p1, k1)
	end

	local bitLen = math.max(bitLen1, bitLen2)

	-- Precompute: T[1]=P2, T[2]=P1, T[3]=P1+P2
	local jP1 = StarkCurve.jacobianFromAffine(p1)
	local jP2 = StarkCurve.jacobianFromAffine(p2)
	local jSum = StarkCurve.jacobianAdd(jP1, jP2)
	local T = { jP2, jP1, jSum }

	local result: JacobianPoint = { x = StarkField.one(), y = StarkField.one(), z = StarkField.zero() }

	for i = bitLen - 1, 0, -1 do
		result = StarkCurve.jacobianDouble(result)
		local idx = BigInt.getBit(k1, i) * 2 + BigInt.getBit(k2, i)
		if idx > 0 then
			result = StarkCurve.jacobianAdd(result, T[idx])
		end
	end

	return StarkCurve.affineFromJacobian(result)
end

--------------------------------------------------------------------------------
-- Public key derivation: publicKey = privateKey * G
-- privateKey must be in [1, N-1]
--------------------------------------------------------------------------------

function StarkCurve.getPublicKey(privateKey: buffer): AffinePoint
	if BigInt.isZero(privateKey) then
		error(StarknetError.signing("StarkCurve: private key cannot be zero", ErrorCodes.INVALID_PRIVATE_KEY.code))
	end
	if BigInt.cmp(privateKey, StarkCurve.N) >= 0 then
		error(
			StarknetError.signing(
				"StarkCurve: private key must be less than curve order N",
				ErrorCodes.KEY_OUT_OF_RANGE.code
			)
		)
	end
	local result = StarkCurve.scalarMul(StarkCurve.G, privateKey)
	if StarkCurve.isInfinityAffine(result) then
		error(
			StarknetError.signing(
				"StarkCurve: invalid private key (maps to infinity)",
				ErrorCodes.INVALID_PRIVATE_KEY.code
			)
		)
	end
	return result
end

return StarkCurve
