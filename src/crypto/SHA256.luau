--!strict
--!native
--!optimize 2
-- SHA-256: FIPS 180-4 compliant hash + HMAC-SHA-256 (RFC 2104)
-- Used for RFC 6979 deterministic nonce generation in ECDSA signing
-- 64 rounds with precomputed K constants, 512-bit (64-byte) blocks
-- Reference: https://csrc.nist.gov/publications/detail/fips/180/4/final

local SHA256 = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- 64 round constants: first 32 bits of fractional parts of cube roots of first 64 primes
local K = {
	0x428a2f98,
	0x71374491,
	0xb5c0fbcf,
	0xe9b5dba5,
	0x3956c25b,
	0x59f111f1,
	0x923f82a4,
	0xab1c5ed5,
	0xd807aa98,
	0x12835b01,
	0x243185be,
	0x550c7dc3,
	0x72be5d74,
	0x80deb1fe,
	0x9bdc06a7,
	0xc19bf174,
	0xe49b69c1,
	0xefbe4786,
	0x0fc19dc6,
	0x240ca1cc,
	0x2de92c6f,
	0x4a7484aa,
	0x5cb0a9dc,
	0x76f988da,
	0x983e5152,
	0xa831c66d,
	0xb00327c8,
	0xbf597fc7,
	0xc6e00bf3,
	0xd5a79147,
	0x06ca6351,
	0x14292967,
	0x27b70a85,
	0x2e1b2138,
	0x4d2c6dfc,
	0x53380d13,
	0x650a7354,
	0x766a0abb,
	0x81c2c92e,
	0x92722c85,
	0xa2bfe8a1,
	0xa81a664b,
	0xc24b8b70,
	0xc76c51a3,
	0xd192e819,
	0xd6990624,
	0xf40e3585,
	0x106aa070,
	0x19a4c116,
	0x1e376c08,
	0x2748774c,
	0x34b0bcb5,
	0x391c0cb3,
	0x4ed8aa4a,
	0x5b9cca4f,
	0x682e6ff3,
	0x748f82ee,
	0x78a5636f,
	0x84c87814,
	0x8cc70208,
	0x90befffa,
	0xa4506ceb,
	0xbef9a3f7,
	0xc67178f2,
}

-- Initial hash values: first 32 bits of fractional parts of square roots of first 8 primes
local H_INIT = {
	0x6a09e667,
	0xbb67ae85,
	0x3c6ef372,
	0xa54ff53a,
	0x510e527f,
	0x9b05688c,
	0x1f83d9ab,
	0x5be0cd19,
}

-- Block size in bytes (512 bits)
local BLOCK_SIZE = 64

-- Modular wrap constant (2^32)
local MOD32 = 0x100000000

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Right-rotate a 32-bit word by n bits
local function rotr(x: number, n: number): number
	return bit32.bor(bit32.rshift(x, n), bit32.lshift(x, 32 - n))
end

-- Read a 32-bit big-endian value from buffer
local function readBE32(buf: buffer, offset: number): number
	return buffer.readu8(buf, offset) * 0x1000000
		+ buffer.readu8(buf, offset + 1) * 0x10000
		+ buffer.readu8(buf, offset + 2) * 0x100
		+ buffer.readu8(buf, offset + 3)
end

-- Write a 32-bit value as 4 big-endian bytes into buffer
local function writeBE32(buf: buffer, offset: number, value: number)
	buffer.writeu8(buf, offset, bit32.band(bit32.rshift(value, 24), 0xFF))
	buffer.writeu8(buf, offset + 1, bit32.band(bit32.rshift(value, 16), 0xFF))
	buffer.writeu8(buf, offset + 2, bit32.band(bit32.rshift(value, 8), 0xFF))
	buffer.writeu8(buf, offset + 3, bit32.band(value, 0xFF))
end

--------------------------------------------------------------------------------
-- SHA-256 hash (FIPS 180-4)
--------------------------------------------------------------------------------

-- hash: Compute SHA-256 hash (32-byte buffer output)
function SHA256.hash(data: buffer): buffer
	local dataLen = buffer.len(data)

	-- Preprocessing: padding
	-- Append 0x80 byte, then zeros, then 64-bit big-endian bit length
	-- Total padded length must be a multiple of 64 bytes (512 bits)
	local padLen = BLOCK_SIZE - ((dataLen + 9) % BLOCK_SIZE)
	if padLen == BLOCK_SIZE then
		padLen = 0
	end
	local totalLen = dataLen + 1 + padLen + 8

	local padded = buffer.create(totalLen)
	if dataLen > 0 then
		buffer.copy(padded, 0, data, 0, dataLen)
	end

	-- Append 0x80 byte (bit '1' followed by zeros)
	buffer.writeu8(padded, dataLen, 0x80)
	-- Zeros are implicit from buffer.create

	-- Append 64-bit big-endian bit length
	local bitLen = dataLen * 8
	local lenOff = totalLen - 8
	writeBE32(padded, lenOff, math.floor(bitLen / MOD32))
	writeBE32(padded, lenOff + 4, bitLen % MOD32)

	-- Initialize hash state
	local h0, h1, h2, h3 = H_INIT[1], H_INIT[2], H_INIT[3], H_INIT[4]
	local h4, h5, h6, h7 = H_INIT[5], H_INIT[6], H_INIT[7], H_INIT[8]

	-- Message schedule array (reused across blocks)
	local W = table.create(64, 0)

	-- Process each 512-bit (64-byte) block
	local numBlocks = totalLen / BLOCK_SIZE
	for blk = 0, numBlocks - 1 do
		local offset = blk * BLOCK_SIZE

		-- W[1..16]: read block as 16 big-endian 32-bit words
		for i = 1, 16 do
			W[i] = readBE32(padded, offset + (i - 1) * 4)
		end

		-- W[17..64]: message schedule extension
		-- W[t] = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]
		for i = 17, 64 do
			local w2 = W[i - 2]
			local w15 = W[i - 15]
			-- σ0(x) = ROTR(7,x) XOR ROTR(18,x) XOR SHR(3,x)
			local s0 = bit32.bxor(rotr(w15, 7), rotr(w15, 18), bit32.rshift(w15, 3))
			-- σ1(x) = ROTR(17,x) XOR ROTR(19,x) XOR SHR(10,x)
			local s1 = bit32.bxor(rotr(w2, 17), rotr(w2, 19), bit32.rshift(w2, 10))
			W[i] = (s1 + W[i - 7] + s0 + W[i - 16]) % MOD32
		end

		-- Initialize working variables from current hash state
		local a, b, c, d = h0, h1, h2, h3
		local e, f, g, h = h4, h5, h6, h7

		-- 64 rounds of compression
		for i = 1, 64 do
			-- Σ1(e) = ROTR(6,e) XOR ROTR(11,e) XOR ROTR(25,e)
			local S1 = bit32.bxor(rotr(e, 6), rotr(e, 11), rotr(e, 25))
			-- Ch(e,f,g) = (e AND f) XOR ((NOT e) AND g)
			local ch = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
			-- T1 = h + Σ1(e) + Ch(e,f,g) + K[i] + W[i]
			local T1 = (h + S1 + ch + K[i] + W[i]) % MOD32

			-- Σ0(a) = ROTR(2,a) XOR ROTR(13,a) XOR ROTR(22,a)
			local S0 = bit32.bxor(rotr(a, 2), rotr(a, 13), rotr(a, 22))
			-- Maj(a,b,c) = (a AND b) XOR (a AND c) XOR (b AND c)
			local maj = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
			-- T2 = Σ0(a) + Maj(a,b,c)
			local T2 = (S0 + maj) % MOD32

			h = g
			g = f
			f = e
			e = (d + T1) % MOD32
			d = c
			c = b
			b = a
			a = (T1 + T2) % MOD32
		end

		-- Add compressed chunk to hash state
		h0 = (h0 + a) % MOD32
		h1 = (h1 + b) % MOD32
		h2 = (h2 + c) % MOD32
		h3 = (h3 + d) % MOD32
		h4 = (h4 + e) % MOD32
		h5 = (h5 + f) % MOD32
		h6 = (h6 + g) % MOD32
		h7 = (h7 + h) % MOD32
	end

	-- Produce 32-byte big-endian hash output
	local result = buffer.create(32)
	writeBE32(result, 0, h0)
	writeBE32(result, 4, h1)
	writeBE32(result, 8, h2)
	writeBE32(result, 12, h3)
	writeBE32(result, 16, h4)
	writeBE32(result, 20, h5)
	writeBE32(result, 24, h6)
	writeBE32(result, 28, h7)

	return result
end

--------------------------------------------------------------------------------
-- HMAC-SHA-256 (RFC 2104)
--------------------------------------------------------------------------------

-- hmac: Compute HMAC-SHA-256 (32-byte buffer output)
-- HMAC(K, m) = H((K' ⊕ opad) || H((K' ⊕ ipad) || m))
function SHA256.hmac(key: buffer, message: buffer): buffer
	local keyLen = buffer.len(key)

	-- Normalize key to exactly BLOCK_SIZE bytes
	-- If key > block size, hash it first; if shorter, zero-pad
	local keyBlock = buffer.create(BLOCK_SIZE)
	if keyLen > BLOCK_SIZE then
		local hashed = SHA256.hash(key)
		buffer.copy(keyBlock, 0, hashed, 0, 32)
	elseif keyLen > 0 then
		buffer.copy(keyBlock, 0, key, 0, keyLen)
	end
	-- Remaining bytes are zeros from buffer.create

	-- Compute ipad (key XOR 0x36) and opad (key XOR 0x5c)
	local ipad = buffer.create(BLOCK_SIZE)
	local opad = buffer.create(BLOCK_SIZE)
	for i = 0, BLOCK_SIZE - 1 do
		local kb = buffer.readu8(keyBlock, i)
		buffer.writeu8(ipad, i, bit32.bxor(kb, 0x36))
		buffer.writeu8(opad, i, bit32.bxor(kb, 0x5c))
	end

	-- Inner hash: SHA-256(ipad || message)
	local msgLen = buffer.len(message)
	local innerInput = buffer.create(BLOCK_SIZE + msgLen)
	buffer.copy(innerInput, 0, ipad, 0, BLOCK_SIZE)
	if msgLen > 0 then
		buffer.copy(innerInput, BLOCK_SIZE, message, 0, msgLen)
	end
	local innerHash = SHA256.hash(innerInput)

	-- Outer hash: SHA-256(opad || inner_hash)
	local outerInput = buffer.create(BLOCK_SIZE + 32)
	buffer.copy(outerInput, 0, opad, 0, BLOCK_SIZE)
	buffer.copy(outerInput, BLOCK_SIZE, innerHash, 0, 32)

	return SHA256.hash(outerInput)
end

--------------------------------------------------------------------------------
-- Utility: bufferToHex (exposed for testing/debugging)
--------------------------------------------------------------------------------

local HEX_CHARS = "0123456789abcdef"

function SHA256.bufferToHex(buf: buffer): string
	local parts = table.create(buffer.len(buf))
	for i = 0, buffer.len(buf) - 1 do
		local byte = buffer.readu8(buf, i)
		local hi = math.floor(byte / 16) + 1
		local lo = (byte % 16) + 1
		parts[i + 1] = string.sub(HEX_CHARS, hi, hi) .. string.sub(HEX_CHARS, lo, lo)
	end
	return table.concat(parts)
end

return SHA256
