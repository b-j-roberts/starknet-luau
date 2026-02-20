--!strict
--!native
--!optimize 2
-- Keccak-256: Ethereum-variant Keccak hash (NOT SHA-3) for Starknet function selectors
-- Uses bit32 for 32-bit word operations, 64-bit lanes split into {hi, lo} pairs
-- Keccak-256: rate=1088 bits (136 bytes), capacity=512 bits, padding=0x01
-- Reference: https://keccak.team/keccak_specs_summary.html

local StarkField = require("./StarkField")

type Felt = StarkField.Felt

local Keccak = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- 24 round constants for iota step (hi 32 bits of each 64-bit RC)
local RC_HI = {
	0x00000000,
	0x00000000,
	0x80000000,
	0x80000000,
	0x00000000,
	0x00000000,
	0x80000000,
	0x80000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x80000000,
	0x80000000,
	0x80000000,
	0x80000000,
	0x80000000,
	0x00000000,
	0x80000000,
	0x80000000,
	0x80000000,
	0x00000000,
	0x80000000,
}

-- 24 round constants for iota step (lo 32 bits of each 64-bit RC)
local RC_LO = {
	0x00000001,
	0x00008082,
	0x0000808A,
	0x80008000,
	0x0000808B,
	0x80000001,
	0x80008081,
	0x00008009,
	0x0000008A,
	0x00000088,
	0x80008009,
	0x8000000A,
	0x8000808B,
	0x0000008B,
	0x00008089,
	0x00008003,
	0x00008002,
	0x00000080,
	0x0000800A,
	0x8000000A,
	0x80008081,
	0x00008080,
	0x80000001,
	0x80008008,
}

-- Combined rho+pi: for each destination lane (1-based), the source lane index
-- Lane indexing: y*5 + x + 1 (1-based)
-- Pi: A'[x,y] = A[(x+3y) mod 5, x]
local PI_FROM = {
	1,
	7,
	13,
	19,
	25,
	4,
	10,
	11,
	17,
	23,
	2,
	8,
	14,
	20,
	21,
	5,
	6,
	12,
	18,
	24,
	3,
	9,
	15,
	16,
	22,
}

-- Combined rho+pi: rotation amount for the source lane
local PI_ROT = {
	0,
	44,
	43,
	21,
	14,
	28,
	20,
	3,
	45,
	61,
	1,
	6,
	25,
	8,
	18,
	27,
	36,
	10,
	15,
	56,
	62,
	55,
	39,
	41,
	2,
}

-- Rate in bytes for Keccak-256 (1088 bits / 8)
local RATE = 136

-- Number of rate lanes (RATE / 8)
local RATE_LANES = 17

--------------------------------------------------------------------------------
-- Keccak-f[1600] permutation (24 rounds)
--------------------------------------------------------------------------------

-- State: shi[1..25] = hi 32 bits of each lane, slo[1..25] = lo 32 bits
-- Lane index = y*5 + x + 1 (1-based), x=0..4, y=0..4
local function keccakF(shi: { number }, slo: { number })
	local bhi = table.create(25, 0)
	local blo = table.create(25, 0)

	for round = 1, 24 do
		-- === Theta ===
		-- Column parities: C[x] = XOR of all 5 lanes in column x
		local c0h = bit32.bxor(shi[1], shi[6], shi[11], shi[16], shi[21])
		local c0l = bit32.bxor(slo[1], slo[6], slo[11], slo[16], slo[21])
		local c1h = bit32.bxor(shi[2], shi[7], shi[12], shi[17], shi[22])
		local c1l = bit32.bxor(slo[2], slo[7], slo[12], slo[17], slo[22])
		local c2h = bit32.bxor(shi[3], shi[8], shi[13], shi[18], shi[23])
		local c2l = bit32.bxor(slo[3], slo[8], slo[13], slo[18], slo[23])
		local c3h = bit32.bxor(shi[4], shi[9], shi[14], shi[19], shi[24])
		local c3l = bit32.bxor(slo[4], slo[9], slo[14], slo[19], slo[24])
		local c4h = bit32.bxor(shi[5], shi[10], shi[15], shi[20], shi[25])
		local c4l = bit32.bxor(slo[5], slo[10], slo[15], slo[20], slo[25])

		-- D[x] = C[(x-1) mod 5] XOR rot(C[(x+1) mod 5], 1)
		-- rot64 by 1: new_hi = (hi<<1)|(lo>>31), new_lo = (lo<<1)|(hi>>31)
		local d0h = bit32.bxor(c4h, bit32.bor(bit32.lshift(c1h, 1), bit32.rshift(c1l, 31)))
		local d0l = bit32.bxor(c4l, bit32.bor(bit32.lshift(c1l, 1), bit32.rshift(c1h, 31)))
		local d1h = bit32.bxor(c0h, bit32.bor(bit32.lshift(c2h, 1), bit32.rshift(c2l, 31)))
		local d1l = bit32.bxor(c0l, bit32.bor(bit32.lshift(c2l, 1), bit32.rshift(c2h, 31)))
		local d2h = bit32.bxor(c1h, bit32.bor(bit32.lshift(c3h, 1), bit32.rshift(c3l, 31)))
		local d2l = bit32.bxor(c1l, bit32.bor(bit32.lshift(c3l, 1), bit32.rshift(c3h, 31)))
		local d3h = bit32.bxor(c2h, bit32.bor(bit32.lshift(c4h, 1), bit32.rshift(c4l, 31)))
		local d3l = bit32.bxor(c2l, bit32.bor(bit32.lshift(c4l, 1), bit32.rshift(c4h, 31)))
		local d4h = bit32.bxor(c3h, bit32.bor(bit32.lshift(c0h, 1), bit32.rshift(c0l, 31)))
		local d4l = bit32.bxor(c3l, bit32.bor(bit32.lshift(c0l, 1), bit32.rshift(c0h, 31)))

		-- XOR D[x] into each lane of column x
		shi[1] = bit32.bxor(shi[1], d0h)
		slo[1] = bit32.bxor(slo[1], d0l)
		shi[6] = bit32.bxor(shi[6], d0h)
		slo[6] = bit32.bxor(slo[6], d0l)
		shi[11] = bit32.bxor(shi[11], d0h)
		slo[11] = bit32.bxor(slo[11], d0l)
		shi[16] = bit32.bxor(shi[16], d0h)
		slo[16] = bit32.bxor(slo[16], d0l)
		shi[21] = bit32.bxor(shi[21], d0h)
		slo[21] = bit32.bxor(slo[21], d0l)

		shi[2] = bit32.bxor(shi[2], d1h)
		slo[2] = bit32.bxor(slo[2], d1l)
		shi[7] = bit32.bxor(shi[7], d1h)
		slo[7] = bit32.bxor(slo[7], d1l)
		shi[12] = bit32.bxor(shi[12], d1h)
		slo[12] = bit32.bxor(slo[12], d1l)
		shi[17] = bit32.bxor(shi[17], d1h)
		slo[17] = bit32.bxor(slo[17], d1l)
		shi[22] = bit32.bxor(shi[22], d1h)
		slo[22] = bit32.bxor(slo[22], d1l)

		shi[3] = bit32.bxor(shi[3], d2h)
		slo[3] = bit32.bxor(slo[3], d2l)
		shi[8] = bit32.bxor(shi[8], d2h)
		slo[8] = bit32.bxor(slo[8], d2l)
		shi[13] = bit32.bxor(shi[13], d2h)
		slo[13] = bit32.bxor(slo[13], d2l)
		shi[18] = bit32.bxor(shi[18], d2h)
		slo[18] = bit32.bxor(slo[18], d2l)
		shi[23] = bit32.bxor(shi[23], d2h)
		slo[23] = bit32.bxor(slo[23], d2l)

		shi[4] = bit32.bxor(shi[4], d3h)
		slo[4] = bit32.bxor(slo[4], d3l)
		shi[9] = bit32.bxor(shi[9], d3h)
		slo[9] = bit32.bxor(slo[9], d3l)
		shi[14] = bit32.bxor(shi[14], d3h)
		slo[14] = bit32.bxor(slo[14], d3l)
		shi[19] = bit32.bxor(shi[19], d3h)
		slo[19] = bit32.bxor(slo[19], d3l)
		shi[24] = bit32.bxor(shi[24], d3h)
		slo[24] = bit32.bxor(slo[24], d3l)

		shi[5] = bit32.bxor(shi[5], d4h)
		slo[5] = bit32.bxor(slo[5], d4l)
		shi[10] = bit32.bxor(shi[10], d4h)
		slo[10] = bit32.bxor(slo[10], d4l)
		shi[15] = bit32.bxor(shi[15], d4h)
		slo[15] = bit32.bxor(slo[15], d4l)
		shi[20] = bit32.bxor(shi[20], d4h)
		slo[20] = bit32.bxor(slo[20], d4l)
		shi[25] = bit32.bxor(shi[25], d4h)
		slo[25] = bit32.bxor(slo[25], d4l)

		-- === Rho + Pi (combined) ===
		-- B[dst] = rot64(A[src], r) where src=PI_FROM[dst], r=PI_ROT[dst]
		for dst = 1, 25 do
			local src = PI_FROM[dst]
			local r = PI_ROT[dst]
			local h, l = shi[src], slo[src]

			if r == 0 then
				bhi[dst] = h
				blo[dst] = l
			elseif r < 32 then
				bhi[dst] = bit32.bor(bit32.lshift(h, r), bit32.rshift(l, 32 - r))
				blo[dst] = bit32.bor(bit32.lshift(l, r), bit32.rshift(h, 32 - r))
			else -- r > 32 (no r==32 in our table)
				r -= 32
				bhi[dst] = bit32.bor(bit32.lshift(l, r), bit32.rshift(h, 32 - r))
				blo[dst] = bit32.bor(bit32.lshift(h, r), bit32.rshift(l, 32 - r))
			end
		end

		-- === Chi ===
		-- A'[x,y] = B[x,y] XOR ((NOT B[(x+1)%5,y]) AND B[(x+2)%5,y])
		for y = 0, 4 do
			local base = y * 5
			local b0h, b0l = bhi[base + 1], blo[base + 1]
			local b1h, b1l = bhi[base + 2], blo[base + 2]
			local b2h, b2l = bhi[base + 3], blo[base + 3]
			local b3h, b3l = bhi[base + 4], blo[base + 4]
			local b4h, b4l = bhi[base + 5], blo[base + 5]

			shi[base + 1] = bit32.bxor(b0h, bit32.band(bit32.bnot(b1h), b2h))
			slo[base + 1] = bit32.bxor(b0l, bit32.band(bit32.bnot(b1l), b2l))
			shi[base + 2] = bit32.bxor(b1h, bit32.band(bit32.bnot(b2h), b3h))
			slo[base + 2] = bit32.bxor(b1l, bit32.band(bit32.bnot(b2l), b3l))
			shi[base + 3] = bit32.bxor(b2h, bit32.band(bit32.bnot(b3h), b4h))
			slo[base + 3] = bit32.bxor(b2l, bit32.band(bit32.bnot(b3l), b4l))
			shi[base + 4] = bit32.bxor(b3h, bit32.band(bit32.bnot(b4h), b0h))
			slo[base + 4] = bit32.bxor(b3l, bit32.band(bit32.bnot(b4l), b0l))
			shi[base + 5] = bit32.bxor(b4h, bit32.band(bit32.bnot(b0h), b1h))
			slo[base + 5] = bit32.bxor(b4l, bit32.band(bit32.bnot(b0l), b1l))
		end

		-- === Iota ===
		shi[1] = bit32.bxor(shi[1], RC_HI[round])
		slo[1] = bit32.bxor(slo[1], RC_LO[round])
	end
end

--------------------------------------------------------------------------------
-- Keccak-256 sponge construction
--------------------------------------------------------------------------------

-- keccak256: Compute raw Keccak-256 hash (32-byte buffer output)
function Keccak.keccak256(input: buffer): buffer
	local inputLen = buffer.len(input)

	-- Padding: append 0x01, zeros, then set last byte of block |= 0x80
	-- Total length must be a multiple of RATE (136 bytes)
	local padLen = RATE - (inputLen % RATE)
	if padLen == 0 then
		padLen = RATE
	end
	local totalLen = inputLen + padLen

	local padded = buffer.create(totalLen)
	if inputLen > 0 then
		buffer.copy(padded, 0, input, 0, inputLen)
	end

	-- Keccak padding (NOT SHA-3): domain byte = 0x01
	buffer.writeu8(padded, inputLen, 0x01)
	-- Zeros are implicit from buffer.create
	-- Set MSB of last byte in the rate block
	local lastIdx = totalLen - 1
	buffer.writeu8(padded, lastIdx, bit32.bor(buffer.readu8(padded, lastIdx), 0x80))

	-- Initialize state: 25 zero lanes
	local shi = table.create(25, 0)
	local slo = table.create(25, 0)

	-- Absorb: process input in RATE-byte blocks
	local numBlocks = totalLen / RATE
	for blk = 0, numBlocks - 1 do
		local offset = blk * RATE
		for lane = 0, RATE_LANES - 1 do
			local off = offset + lane * 8
			-- Read 8 bytes as little-endian u64 -> {lo, hi} 32-bit halves
			local lo = buffer.readu8(padded, off)
				+ buffer.readu8(padded, off + 1) * 0x100
				+ buffer.readu8(padded, off + 2) * 0x10000
				+ buffer.readu8(padded, off + 3) * 0x1000000
			local hi = buffer.readu8(padded, off + 4)
				+ buffer.readu8(padded, off + 5) * 0x100
				+ buffer.readu8(padded, off + 6) * 0x10000
				+ buffer.readu8(padded, off + 7) * 0x1000000
			slo[lane + 1] = bit32.bxor(slo[lane + 1], lo)
			shi[lane + 1] = bit32.bxor(shi[lane + 1], hi)
		end
		keccakF(shi, slo)
	end

	-- Squeeze: output 32 bytes (4 lanes) in little-endian byte order
	local result = buffer.create(32)
	for lane = 0, 3 do
		local off = lane * 8
		local lo = slo[lane + 1]
		local hi = shi[lane + 1]
		buffer.writeu8(result, off, bit32.band(lo, 0xFF))
		buffer.writeu8(result, off + 1, bit32.band(bit32.rshift(lo, 8), 0xFF))
		buffer.writeu8(result, off + 2, bit32.band(bit32.rshift(lo, 16), 0xFF))
		buffer.writeu8(result, off + 3, bit32.band(bit32.rshift(lo, 24), 0xFF))
		buffer.writeu8(result, off + 4, bit32.band(hi, 0xFF))
		buffer.writeu8(result, off + 5, bit32.band(bit32.rshift(hi, 8), 0xFF))
		buffer.writeu8(result, off + 6, bit32.band(bit32.rshift(hi, 16), 0xFF))
		buffer.writeu8(result, off + 7, bit32.band(bit32.rshift(hi, 24), 0xFF))
	end

	return result
end

--------------------------------------------------------------------------------
-- Starknet sn_keccak and selector functions
--------------------------------------------------------------------------------

-- Convert a 32-byte hash buffer to a hex string (no prefix)
local HEX_CHARS = "0123456789abcdef"
local function bufferToHex(buf: buffer): string
	local parts = table.create(buffer.len(buf))
	for i = 0, buffer.len(buf) - 1 do
		local byte = buffer.readu8(buf, i)
		local hi = math.floor(byte / 16) + 1
		local lo = (byte % 16) + 1
		parts[i + 1] = string.sub(HEX_CHARS, hi, hi) .. string.sub(HEX_CHARS, lo, lo)
	end
	return table.concat(parts)
end

-- snKeccak: keccak256 masked to 250 bits, returned as a StarkField Felt
function Keccak.snKeccak(input: buffer): Felt
	local hash = Keccak.keccak256(input)
	-- Mask to 250 bits: clear top 6 bits of byte 0 (MSB of 256-bit number)
	buffer.writeu8(hash, 0, bit32.band(buffer.readu8(hash, 0), 0x03))
	-- Convert to hex and parse as Felt
	local hex = bufferToHex(hash)
	return StarkField.fromHex("0x" .. hex)
end

-- getSelectorFromName: compute Starknet function selector from ASCII name
function Keccak.getSelectorFromName(name: string): Felt
	-- Special entry points return zero
	if name == "__default__" or name == "__l1_default__" then
		return StarkField.zero()
	end
	-- Encode name as ASCII buffer
	local buf = buffer.create(#name)
	for i = 1, #name do
		buffer.writeu8(buf, i - 1, string.byte(name, i))
	end
	return Keccak.snKeccak(buf)
end

--------------------------------------------------------------------------------
-- Utility: bufferToHex (exposed for testing/debugging)
--------------------------------------------------------------------------------

function Keccak.bufferToHex(buf: buffer): string
	return bufferToHex(buf)
end

return Keccak
