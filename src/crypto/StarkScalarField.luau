--!strict
--!native
--!optimize 2
-- StarkScalarField: Modular arithmetic over the Stark curve order N
-- Used for ECDSA scalar operations: s = k^(-1) * (hash + r*privKey) mod N
-- Built via FieldFactory. No sqrt() — scalar field is only used for signing math.

local BigInt = require("./BigInt")
local FieldFactory = require("./FieldFactory")

export type Scalar = buffer

-- Curve order N
local N = BigInt.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f")

-- N - 2 for Fermat inversion: a^(N-2) mod N
local N_MINUS_2 = BigInt.fromHex("0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2d")

-- Pre-computed Barrett context for fast modular multiplication
local barrettCtx = BigInt.createBarrettCtx(N)

-- Generate the field with all shared operations
local base = FieldFactory.createField(N, N_MINUS_2, barrettCtx, "StarkScalarField")

local StarkScalarField = {}

-- Re-export the modulus
StarkScalarField.N = N

-- Re-export all base field operations
StarkScalarField.zero = base.zero
StarkScalarField.one = base.one
StarkScalarField.fromNumber = base.fromNumber
StarkScalarField.fromHex = base.fromHex
StarkScalarField.add = base.add
StarkScalarField.sub = base.sub
StarkScalarField.mul = base.mul
StarkScalarField.square = base.square
StarkScalarField.neg = base.neg
StarkScalarField.inv = base.inv
StarkScalarField.toHex = base.toHex
StarkScalarField.toBigInt = base.toBigInt
StarkScalarField.eq = base.eq
StarkScalarField.isZero = base.isZero

return StarkScalarField
