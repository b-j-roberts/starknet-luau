--!strict
--!native
--!optimize 2
-- ECDSA: Stark ECDSA signing with RFC 6979 deterministic nonce generation
-- Implements sign/verify for the Stark curve using HMAC-SHA-256 based RFC 6979
-- Reference: RFC 6979 (https://tools.ietf.org/html/rfc6979#section-3.2)
-- Compatible with @scure/starknet / noble-curves signing behavior

local BigInt = require("./BigInt")
local StarkScalarField = require("./StarkScalarField")
local StarkCurve = require("./StarkCurve")
local SHA256 = require("./SHA256")

local ECDSA = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Curve order N and bit length
local N = StarkScalarField.N
local N_BIT_LENGTH = 252 -- nBitLength for the Stark curve
local BYTE_LENGTH = 32 -- ceil(N_BIT_LENGTH / 8)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type Signature = {
	r: buffer,
	s: buffer,
}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Convert a BigInt to exactly 32 bytes (big-endian, zero-padded on the left)
local function toBytes32(x: buffer): buffer
	local bytes = BigInt.toBytes(x)
	local len = buffer.len(bytes)
	if len == BYTE_LENGTH then
		return bytes
	end
	local out = buffer.create(BYTE_LENGTH)
	if len < BYTE_LENGTH then
		buffer.copy(out, BYTE_LENGTH - len, bytes, 0, len)
	else
		-- Truncate from the left (shouldn't happen for valid field elements)
		buffer.copy(out, 0, bytes, len - BYTE_LENGTH, BYTE_LENGTH)
	end
	return out
end

-- bits2int: convert byte string to integer, truncating to N_BIT_LENGTH bits
-- Matches @scure/starknet: strips leading zero bytes before computing delta
-- Per RFC 6979 section 2.3.2 with Starknet-specific leading-zero stripping
local function bits2int(bytes: buffer): buffer
	-- Strip leading zero bytes (matches @scure/starknet behavior)
	local start = 0
	local len = buffer.len(bytes)
	while start < len and buffer.readu8(bytes, start) == 0 do
		start += 1
	end
	if start > 0 then
		if start >= len then
			return BigInt.zero()
		end
		local stripped = buffer.create(len - start)
		buffer.copy(stripped, 0, bytes, start, len - start)
		bytes = stripped
		len = len - start
	end

	local num = BigInt.fromBytes(bytes)
	local blen = len * 8
	local delta = blen - N_BIT_LENGTH
	if delta > 0 then
		num = BigInt.shr(num, delta)
	end
	return num
end

-- bits2int_modN: matches @scure/starknet custom behavior
-- When the numeric hex representation has exactly 63 chars (values 2^248..2^252),
-- appends a trailing '0' (multiply by 16) before bits2int to cancel the 4-bit shift.
-- This ensures Starknet felts are used directly without truncation.
local function bits2intModN(bytes: buffer): buffer
	local num = BigInt.fromBytes(bytes)
	local hex = BigInt.toHex(num) -- "0x..." format
	local hexDigits = string.sub(hex, 3) -- strip "0x" prefix

	if #hexDigits == 63 then
		-- Multiply by 16 (append trailing '0'), then bits2int will right-shift by 4,
		-- giving back the original value
		local shifted = BigInt.shl(num, 4)
		local newBytes = BigInt.toBytes(shifted)
		local z = bits2int(newBytes)
		if BigInt.cmp(z, N) >= 0 then
			z = BigInt.mod(z, N)
		end
		return z
	end

	local z = bits2int(bytes)
	if BigInt.cmp(z, N) >= 0 then
		z = BigInt.mod(z, N)
	end
	return z
end

-- bits2octets: bits2int -> mod N -> encode as 32 bytes
-- Per RFC 6979 section 2.3.4
local function bits2octets(bytes: buffer): buffer
	return toBytes32(bits2intModN(bytes))
end

-- Concatenate multiple buffers into one
local function concatBuffers(...: buffer): buffer
	local args = { ... }
	local totalLen = 0
	for _, buf in args do
		totalLen += buffer.len(buf)
	end
	local out = buffer.create(totalLen)
	local offset = 0
	for _, buf in args do
		local len = buffer.len(buf)
		buffer.copy(out, offset, buf, 0, len)
		offset += len
	end
	return out
end

-- Create a single-byte buffer
local function singleByte(v: number): buffer
	local b = buffer.create(1)
	buffer.writeu8(b, 0, v)
	return b
end

--------------------------------------------------------------------------------
-- RFC 6979: Deterministic K generation
-- Reference: https://tools.ietf.org/html/rfc6979#section-3.2
--------------------------------------------------------------------------------

--- Generate deterministic nonce k for ECDSA signing.
--- Exposed for testing; normally called internally by sign().
function ECDSA.generateK(messageHash: buffer, privateKey: buffer): buffer
	-- h1 = H(m) is already computed (messageHash is the hash value)
	-- Use canonical byte representation (variable length, matches noble-curves)
	local h1Bytes = BigInt.toBytes(messageHash)

	-- Prepare seed components per RFC 6979:
	-- int2octets(x) = private key as exactly 32 bytes
	-- bits2octets(h1) = bits2int(h1) mod N, as exactly 32 bytes
	local xOctets = toBytes32(privateKey)
	local h1Octets = bits2octets(h1Bytes)

	-- Step b: V = 0x01 repeated 32 times
	local V = buffer.create(BYTE_LENGTH)
	for i = 0, BYTE_LENGTH - 1 do
		buffer.writeu8(V, i, 0x01)
	end

	-- Step c: K = 0x00 repeated 32 times
	local K = buffer.create(BYTE_LENGTH)

	-- Step d: K = HMAC_K(V || 0x00 || int2octets(x) || bits2octets(h1))
	K = SHA256.hmac(K, concatBuffers(V, singleByte(0x00), xOctets, h1Octets))

	-- Step e: V = HMAC_K(V)
	V = SHA256.hmac(K, V)

	-- Step f: K = HMAC_K(V || 0x01 || int2octets(x) || bits2octets(h1))
	K = SHA256.hmac(K, concatBuffers(V, singleByte(0x01), xOctets, h1Octets))

	-- Step g: V = HMAC_K(V)
	V = SHA256.hmac(K, V)

	-- Step h: Generate k candidates until valid
	for _ = 1, 1000 do
		-- h.1-h.2: Generate candidate T (one HMAC call = 32 bytes >= rlen)
		V = SHA256.hmac(K, V)

		-- h.3: k = bits2int(T), check 1 <= k < N
		local k = bits2int(V)

		if not BigInt.isZero(k) and BigInt.cmp(k, N) < 0 then
			return k
		end

		-- h.3 (retry): K = HMAC_K(V || 0x00), V = HMAC_K(V)
		K = SHA256.hmac(K, concatBuffers(V, singleByte(0x00)))
		V = SHA256.hmac(K, V)
	end

	error("RFC 6979: failed to generate valid k after 1000 iterations")
end

--------------------------------------------------------------------------------
-- ECDSA Sign
--------------------------------------------------------------------------------

--- Sign a message hash with a private key.
--- messageHash: BigInt buffer representing the hash to sign
--- privateKey: BigInt buffer representing the private key (must be in [1, N-1])
--- Returns signature { r, s } where r and s are BigInt buffers
function ECDSA.sign(messageHash: buffer, privateKey: buffer): Signature
	-- Validate private key: must be in [1, N-1]
	if BigInt.isZero(privateKey) then
		error("ECDSA.sign: private key must not be zero")
	end
	if BigInt.cmp(privateKey, N) >= 0 then
		error("ECDSA.sign: private key must be less than curve order N")
	end

	-- Compute message scalar: m = bits2int_modN(h1Bytes)
	local h1Bytes = BigInt.toBytes(messageHash)
	local m = bits2intModN(h1Bytes)

	-- Generate deterministic nonce k via RFC 6979
	local k = ECDSA.generateK(messageHash, privateKey)

	-- Compute R = k * G
	local R = StarkCurve.scalarMul(StarkCurve.G, k)
	if R == nil then
		error("ECDSA.sign: k * G produced identity point")
	end

	-- r = R.x mod N
	local r = BigInt.mod(R.x, N)
	if BigInt.isZero(r) then
		error("ECDSA.sign: r is zero")
	end

	-- s = k^(-1) * (m + r * privateKey) mod N
	local kInv = StarkScalarField.inv(k)
	local rTimesD = StarkScalarField.mul(r, privateKey)
	local sum = StarkScalarField.add(m, rTimesD)
	local s = StarkScalarField.mul(kInv, sum)

	if BigInt.isZero(s) then
		error("ECDSA.sign: s is zero")
	end

	return { r = r, s = s }
end

--------------------------------------------------------------------------------
-- ECDSA Verify
--------------------------------------------------------------------------------

--- Verify a signature against a message hash and public key.
--- Returns true if the signature is valid, false otherwise.
function ECDSA.verify(messageHash: buffer, publicKey: StarkCurve.AffinePoint, signature: Signature): boolean
	local r = signature.r
	local s = signature.s

	-- Validate signature components: must be in [1, N-1]
	if BigInt.isZero(r) or BigInt.cmp(r, N) >= 0 then
		return false
	end
	if BigInt.isZero(s) or BigInt.cmp(s, N) >= 0 then
		return false
	end

	-- Validate public key is on the curve
	if not StarkCurve.isOnCurve(publicKey) then
		return false
	end

	-- Compute message scalar: m = bits2int_modN(h1Bytes)
	local h1Bytes = BigInt.toBytes(messageHash)
	local m = bits2intModN(h1Bytes)

	-- w = s^(-1) mod N
	local w = StarkScalarField.inv(s)

	-- u1 = m * w mod N, u2 = r * w mod N
	local u1 = StarkScalarField.mul(m, w)
	local u2 = StarkScalarField.mul(r, w)

	-- R' = u1 * G + u2 * publicKey
	local p1 = StarkCurve.scalarMul(StarkCurve.G, u1)
	local p2 = StarkCurve.scalarMul(publicKey, u2)

	if p1 == nil and p2 == nil then
		return false
	end

	local RPrime: StarkCurve.AffinePoint
	if p1 == nil then
		RPrime = p2 :: StarkCurve.AffinePoint
	elseif p2 == nil then
		RPrime = p1
	else
		local j1 = StarkCurve.jacobianFromAffine(p1)
		local j2 = StarkCurve.jacobianFromAffine(p2)
		local jSum = StarkCurve.jacobianAdd(j1, j2)
		local result = StarkCurve.affineFromJacobian(jSum)
		if result == nil then
			return false
		end
		RPrime = result
	end

	-- Check R'.x mod N == r
	local rPrime = BigInt.mod(RPrime.x, N)
	return BigInt.eq(rPrime, r)
end

return ECDSA
