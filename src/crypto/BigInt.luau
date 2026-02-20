--!strict
--!native
--!optimize 2
-- BigInt: Buffer-based arbitrary precision integer arithmetic
-- 11 limbs x 24 bits = 264 bits, little-endian, f64 values
-- Following rbx-cryptography's proven performance patterns

local LIMB_BITS = 24
local LIMB_BASE: number = 2 ^ LIMB_BITS -- 16777216
local NUM_LIMBS = 11
local LIMB_BYTES = 8 -- f64 per limb
local BUF_SIZE = NUM_LIMBS * LIMB_BYTES -- 88 bytes

local WIDE_LIMBS = 22
local WIDE_BUF_SIZE = WIDE_LIMBS * LIMB_BYTES -- 176 bytes

-- Half-limb for Horner reduction (12 bits, keeps intermediates under 264 bits)
local HALF_BITS = 12
local HALF_BASE: number = 2 ^ HALF_BITS -- 4096

export type BigInt = buffer

export type BarrettCtx = {
	m: buffer,
	mu: buffer,
	k: number,
}

local BigInt = {}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

local function newBuf(): buffer
	return buffer.create(BUF_SIZE)
end

local function clone(a: buffer): buffer
	local b = buffer.create(BUF_SIZE)
	buffer.copy(b, 0, a, 0, BUF_SIZE)
	return b
end

-- Carry-propagate all limbs so each is in [0, 2^24)
local function carry(buf: buffer): buffer
	for i = 0, NUM_LIMBS - 2 do
		local offset = i * LIMB_BYTES
		local v = buffer.readf64(buf, offset)
		local low = v % LIMB_BASE
		local c = (v - low) / LIMB_BASE
		buffer.writef64(buf, offset, low)
		buffer.writef64(buf, offset + LIMB_BYTES, buffer.readf64(buf, offset + LIMB_BYTES) + c)
	end
	local lastOff = (NUM_LIMBS - 1) * LIMB_BYTES
	buffer.writef64(buf, lastOff, buffer.readf64(buf, lastOff) % LIMB_BASE)
	return buf
end

local function isZeroBuf(a: buffer): boolean
	for i = 0, NUM_LIMBS - 1 do
		if buffer.readf64(a, i * LIMB_BYTES) ~= 0 then
			return false
		end
	end
	return true
end

-- Full 22-limb multiplication (no truncation)
local function mulWide(a: buffer, b: buffer): buffer
	local wide = buffer.create(WIDE_BUF_SIZE)
	for i = 0, NUM_LIMBS - 1 do
		local ai = buffer.readf64(a, i * LIMB_BYTES)
		if ai ~= 0 then
			for j = 0, NUM_LIMBS - 1 do
				local k = i + j
				local offset = k * LIMB_BYTES
				buffer.writef64(wide, offset, buffer.readf64(wide, offset) + ai * buffer.readf64(b, j * LIMB_BYTES))
			end
		end
	end
	-- Carry-propagate the wide result
	for i = 0, WIDE_LIMBS - 2 do
		local offset = i * LIMB_BYTES
		local v = buffer.readf64(wide, offset)
		local low = v % LIMB_BASE
		local c = (v - low) / LIMB_BASE
		buffer.writef64(wide, offset, low)
		buffer.writef64(wide, offset + LIMB_BYTES, buffer.readf64(wide, offset + LIMB_BYTES) + c)
	end
	local lastWide = (WIDE_LIMBS - 1) * LIMB_BYTES
	buffer.writef64(wide, lastWide, buffer.readf64(wide, lastWide) % LIMB_BASE)
	return wide
end

-- Shift a 22-limb wide buffer right, return low 11 limbs
local function wideShiftRight(wide: buffer, bits: number): buffer
	local result = newBuf()
	local limbShift = math.floor(bits / LIMB_BITS)
	local bitShift = bits % LIMB_BITS

	for i = 0, NUM_LIMBS - 1 do
		local srcIdx = i + limbShift
		local val = 0
		if srcIdx < WIDE_LIMBS then
			val = math.floor(buffer.readf64(wide, srcIdx * LIMB_BYTES) / (2 ^ bitShift))
		end
		if bitShift > 0 and srcIdx + 1 < WIDE_LIMBS then
			val += (buffer.readf64(wide, (srcIdx + 1) * LIMB_BYTES) % (2 ^ bitShift)) * (2 ^ (LIMB_BITS - bitShift))
		end
		buffer.writef64(result, i * LIMB_BYTES, val)
	end
	return result
end

-- Extract low `bits` from a 22-limb wide buffer into an 11-limb BigInt
local function wideTruncate(wide: buffer, bits: number): buffer
	local result = newBuf()
	local fullLimbs = math.floor(bits / LIMB_BITS)
	local remainBits = bits % LIMB_BITS

	local copyLimbs = math.min(fullLimbs, NUM_LIMBS)
	for i = 0, copyLimbs - 1 do
		buffer.writef64(result, i * LIMB_BYTES, buffer.readf64(wide, i * LIMB_BYTES))
	end
	if remainBits > 0 and fullLimbs < NUM_LIMBS then
		local mask = (2 ^ remainBits) - 1
		local v = buffer.readf64(wide, fullLimbs * LIMB_BYTES)
		buffer.writef64(result, fullLimbs * LIMB_BYTES, v % (mask + 1))
	end
	return result
end

--------------------------------------------------------------------------------
-- Constructors
--------------------------------------------------------------------------------

function BigInt.zero(): BigInt
	return newBuf()
end

function BigInt.one(): BigInt
	local b = newBuf()
	buffer.writef64(b, 0, 1)
	return b
end

function BigInt.fromNumber(n: number): BigInt
	local b = newBuf()
	if n == 0 then
		return b
	end
	n = math.floor(math.abs(n))
	local i = 0
	while n > 0 and i < NUM_LIMBS do
		buffer.writef64(b, i * LIMB_BYTES, n % LIMB_BASE)
		n = math.floor(n / LIMB_BASE)
		i += 1
	end
	return b
end

function BigInt.fromHex(hex: string): BigInt
	local b = newBuf()
	-- Strip 0x prefix
	if string.sub(hex, 1, 2) == "0x" or string.sub(hex, 1, 2) == "0X" then
		hex = string.sub(hex, 3)
	end
	-- Remove leading zeros
	hex = string.gsub(hex, "^0+", "")
	if hex == "" then
		return b
	end
	-- Pad to multiple of 6 hex chars (24 bits per limb)
	local padLen = (6 - (#hex % 6)) % 6
	hex = string.rep("0", padLen) .. hex

	-- Parse from right (LSB) to left (MSB)
	local limbIndex = 0
	local pos = #hex
	while pos > 0 and limbIndex < NUM_LIMBS do
		local chunk = string.sub(hex, pos - 5, pos)
		buffer.writef64(b, limbIndex * LIMB_BYTES, tonumber(chunk, 16) or 0)
		limbIndex += 1
		pos -= 6
	end
	return b
end

function BigInt.fromBytes(bytes: buffer): BigInt
	local b = newBuf()
	local len = buffer.len(bytes)
	if len == 0 then
		return b
	end

	-- Big-endian bytes -> 24-bit little-endian limbs
	local bitAcc = 0
	local bitsInAcc = 0
	local limbIndex = 0

	for i = len - 1, 0, -1 do
		bitAcc += buffer.readu8(bytes, i) * (2 ^ bitsInAcc)
		bitsInAcc += 8
		while bitsInAcc >= LIMB_BITS and limbIndex < NUM_LIMBS do
			buffer.writef64(b, limbIndex * LIMB_BYTES, bitAcc % LIMB_BASE)
			bitAcc = math.floor(bitAcc / LIMB_BASE)
			bitsInAcc -= LIMB_BITS
			limbIndex += 1
		end
	end
	if bitsInAcc > 0 and limbIndex < NUM_LIMBS then
		buffer.writef64(b, limbIndex * LIMB_BYTES, bitAcc)
	end
	return b
end

--------------------------------------------------------------------------------
-- Conversions
--------------------------------------------------------------------------------

function BigInt.toHex(a: BigInt): string
	local top = -1
	for i = NUM_LIMBS - 1, 0, -1 do
		if buffer.readf64(a, i * LIMB_BYTES) ~= 0 then
			top = i
			break
		end
	end
	if top == -1 then
		return "0x0"
	end

	local parts: { string } = {}
	for i = top, 0, -1 do
		local val = buffer.readf64(a, i * LIMB_BYTES)
		if i == top then
			table.insert(parts, string.format("%x", val))
		else
			table.insert(parts, string.format("%06x", val))
		end
	end
	return "0x" .. table.concat(parts)
end

function BigInt.toBytes(a: BigInt): buffer
	local bitLen = BigInt.bitLength(a)
	if bitLen == 0 then
		local out = buffer.create(1)
		return out
	end
	local byteLen = math.ceil(bitLen / 8)
	local out = buffer.create(byteLen)

	-- Extract bytes big-endian from little-endian limbs
	local bytePos = byteLen - 1
	local limbIndex = 0
	local bitAcc = 0
	local bitsInAcc = 0

	while bytePos >= 0 do
		while bitsInAcc < 8 and limbIndex < NUM_LIMBS do
			bitAcc += buffer.readf64(a, limbIndex * LIMB_BYTES) * (2 ^ bitsInAcc)
			bitsInAcc += LIMB_BITS
			limbIndex += 1
		end
		buffer.writeu8(out, bytePos, math.floor(bitAcc) % 256)
		bitAcc = math.floor(bitAcc / 256)
		bitsInAcc -= 8
		bytePos -= 1
	end
	return out
end

function BigInt.toNumber(a: BigInt): number
	local result = 0
	local base = 1
	for i = 0, NUM_LIMBS - 1 do
		result += buffer.readf64(a, i * LIMB_BYTES) * base
		base *= LIMB_BASE
	end
	return result
end

--------------------------------------------------------------------------------
-- Comparison
--------------------------------------------------------------------------------

function BigInt.isZero(a: BigInt): boolean
	return isZeroBuf(a)
end

function BigInt.eq(a: BigInt, b: BigInt): boolean
	for i = 0, NUM_LIMBS - 1 do
		if buffer.readf64(a, i * LIMB_BYTES) ~= buffer.readf64(b, i * LIMB_BYTES) then
			return false
		end
	end
	return true
end

function BigInt.cmp(a: BigInt, b: BigInt): number
	for i = NUM_LIMBS - 1, 0, -1 do
		local va = buffer.readf64(a, i * LIMB_BYTES)
		local vb = buffer.readf64(b, i * LIMB_BYTES)
		if va > vb then
			return 1
		elseif va < vb then
			return -1
		end
	end
	return 0
end

function BigInt.lt(a: BigInt, b: BigInt): boolean
	return BigInt.cmp(a, b) == -1
end

function BigInt.lte(a: BigInt, b: BigInt): boolean
	return BigInt.cmp(a, b) <= 0
end

--------------------------------------------------------------------------------
-- Basic Arithmetic
--------------------------------------------------------------------------------

function BigInt.add(a: BigInt, b: BigInt): BigInt
	local result = newBuf()
	for i = 0, NUM_LIMBS - 1 do
		local offset = i * LIMB_BYTES
		buffer.writef64(result, offset, buffer.readf64(a, offset) + buffer.readf64(b, offset))
	end
	return carry(result)
end

function BigInt.sub(a: BigInt, b: BigInt): BigInt
	-- Unsigned subtraction. Caller must ensure a >= b.
	local result = newBuf()
	local borrow = 0
	for i = 0, NUM_LIMBS - 1 do
		local offset = i * LIMB_BYTES
		local diff = buffer.readf64(a, offset) - buffer.readf64(b, offset) - borrow
		if diff < 0 then
			diff += LIMB_BASE
			borrow = 1
		else
			borrow = 0
		end
		buffer.writef64(result, offset, diff)
	end
	return result
end

function BigInt.mul(a: BigInt, b: BigInt): BigInt
	-- Schoolbook multiplication, truncated to 11 limbs (264 bits).
	-- Use mulmod for modular multiplication that needs the full product.
	local wide = mulWide(a, b)
	local result = newBuf()
	buffer.copy(result, 0, wide, 0, BUF_SIZE)
	return result
end

--------------------------------------------------------------------------------
-- Bitwise Operations
--------------------------------------------------------------------------------

function BigInt.bitLength(a: BigInt): number
	for i = NUM_LIMBS - 1, 0, -1 do
		local v = buffer.readf64(a, i * LIMB_BYTES)
		if v ~= 0 then
			local bits = 0
			while v >= 1 do
				v = math.floor(v / 2)
				bits += 1
			end
			return i * LIMB_BITS + bits
		end
	end
	return 0
end

function BigInt.getBit(a: BigInt, index: number): number
	local limbIdx = math.floor(index / LIMB_BITS)
	if limbIdx >= NUM_LIMBS then
		return 0
	end
	local bitIdx = index % LIMB_BITS
	return math.floor(buffer.readf64(a, limbIdx * LIMB_BYTES) / (2 ^ bitIdx)) % 2
end

function BigInt.shl(a: BigInt, bits: number): BigInt
	if bits == 0 then
		return clone(a)
	end
	local result = newBuf()
	local limbShift = math.floor(bits / LIMB_BITS)
	local bitShift = bits % LIMB_BITS

	if bitShift == 0 then
		for i = limbShift, NUM_LIMBS - 1 do
			buffer.writef64(result, i * LIMB_BYTES, buffer.readf64(a, (i - limbShift) * LIMB_BYTES))
		end
	else
		for i = NUM_LIMBS - 1, limbShift, -1 do
			local srcIdx = i - limbShift
			local val = buffer.readf64(a, srcIdx * LIMB_BYTES) * (2 ^ bitShift)
			if srcIdx > 0 then
				val += math.floor(buffer.readf64(a, (srcIdx - 1) * LIMB_BYTES) / (2 ^ (LIMB_BITS - bitShift)))
			end
			buffer.writef64(result, i * LIMB_BYTES, val % LIMB_BASE)
		end
		-- Handle the lowest shifted limb
		if limbShift < NUM_LIMBS then
			buffer.writef64(result, limbShift * LIMB_BYTES, (buffer.readf64(a, 0) * (2 ^ bitShift)) % LIMB_BASE)
		end
	end
	return result
end

function BigInt.shr(a: BigInt, bits: number): BigInt
	if bits == 0 then
		return clone(a)
	end
	local result = newBuf()
	local limbShift = math.floor(bits / LIMB_BITS)
	local bitShift = bits % LIMB_BITS

	if bitShift == 0 then
		for i = 0, NUM_LIMBS - 1 - limbShift do
			buffer.writef64(result, i * LIMB_BYTES, buffer.readf64(a, (i + limbShift) * LIMB_BYTES))
		end
	else
		for i = 0, NUM_LIMBS - 1 do
			local srcIdx = i + limbShift
			local val = 0
			if srcIdx < NUM_LIMBS then
				val = math.floor(buffer.readf64(a, srcIdx * LIMB_BYTES) / (2 ^ bitShift))
			end
			if srcIdx + 1 < NUM_LIMBS then
				val += (buffer.readf64(a, (srcIdx + 1) * LIMB_BYTES) % (2 ^ bitShift)) * (2 ^ (LIMB_BITS - bitShift))
			end
			buffer.writef64(result, i * LIMB_BYTES, val)
		end
	end
	return result
end

function BigInt.band(a: BigInt, b: BigInt): BigInt
	local result = newBuf()
	for i = 0, NUM_LIMBS - 1 do
		local offset = i * LIMB_BYTES
		buffer.writef64(result, offset, bit32.band(buffer.readf64(a, offset), buffer.readf64(b, offset)))
	end
	return result
end

function BigInt.bor(a: BigInt, b: BigInt): BigInt
	local result = newBuf()
	for i = 0, NUM_LIMBS - 1 do
		local offset = i * LIMB_BYTES
		buffer.writef64(result, offset, bit32.bor(buffer.readf64(a, offset), buffer.readf64(b, offset)))
	end
	return result
end

--------------------------------------------------------------------------------
-- Division
--------------------------------------------------------------------------------

function BigInt.divmod(a: BigInt, b: BigInt): (BigInt, BigInt)
	if isZeroBuf(b) then
		error("BigInt: division by zero")
	end

	local cmpResult = BigInt.cmp(a, b)
	if cmpResult == -1 then
		return BigInt.zero(), clone(a)
	end
	if cmpResult == 0 then
		return BigInt.one(), BigInt.zero()
	end

	local quotient = newBuf()
	local remainder = clone(a)
	local bBitLen = BigInt.bitLength(b)
	local aBitLen = BigInt.bitLength(a)
	local shift = aBitLen - bBitLen
	local shiftedB = BigInt.shl(b, shift)

	for i = shift, 0, -1 do
		if BigInt.cmp(remainder, shiftedB) >= 0 then
			remainder = BigInt.sub(remainder, shiftedB)
			local limbIdx = math.floor(i / LIMB_BITS)
			local bitIdx = i % LIMB_BITS
			buffer.writef64(
				quotient,
				limbIdx * LIMB_BYTES,
				buffer.readf64(quotient, limbIdx * LIMB_BYTES) + (2 ^ bitIdx)
			)
		end
		shiftedB = BigInt.shr(shiftedB, 1)
	end

	return quotient, remainder
end

function BigInt.div(a: BigInt, b: BigInt): BigInt
	local q, _ = BigInt.divmod(a, b)
	return q
end

function BigInt.mod(a: BigInt, b: BigInt): BigInt
	local _, r = BigInt.divmod(a, b)
	return r
end

--------------------------------------------------------------------------------
-- Modular Arithmetic
--------------------------------------------------------------------------------

-- Reduce a 22-limb wide product modulo m using Horner's method with 12-bit chunks.
-- At each step: result < m < 2^252, result * 2^12 < 2^264 (fits in 11 limbs).
local function reduceWide(wide: buffer, m: buffer): buffer
	-- Find the highest non-zero limb in the wide buffer
	local topLimb = -1
	for i = WIDE_LIMBS - 1, 0, -1 do
		if buffer.readf64(wide, i * LIMB_BYTES) ~= 0 then
			topLimb = i
			break
		end
	end
	if topLimb == -1 then
		return BigInt.zero()
	end

	-- Check if the product already fits in 11 limbs (no reduction needed beyond mod)
	if topLimb < NUM_LIMBS then
		local low = newBuf()
		buffer.copy(low, 0, wide, 0, BUF_SIZE)
		if BigInt.cmp(low, m) < 0 then
			return low
		end
		return BigInt.mod(low, m)
	end

	-- Horner's method processing each 24-bit limb as two 12-bit halves
	-- V = sum(limb[i] * 2^(24*i)) = Horner with 12-bit base
	local result = newBuf()

	for i = topLimb, 0, -1 do
		local limbVal = buffer.readf64(wide, i * LIMB_BYTES)
		local hi12 = math.floor(limbVal / HALF_BASE) -- upper 12 bits
		local lo12 = limbVal % HALF_BASE -- lower 12 bits

		-- Step 1: result = result * 2^12 + hi12
		-- Shift result left by 12 bits (result < m < 2^252, so result*2^12 < 2^264)
		local carryVal = hi12
		for j = 0, NUM_LIMBS - 1 do
			local offset = j * LIMB_BYTES
			local v = buffer.readf64(result, offset) * HALF_BASE + carryVal
			buffer.writef64(result, offset, v % LIMB_BASE)
			carryVal = math.floor(v / LIMB_BASE)
		end
		-- Reduce mod m
		if BigInt.cmp(result, m) >= 0 then
			local _, r = BigInt.divmod(result, m)
			result = r
		end

		-- Step 2: result = result * 2^12 + lo12
		carryVal = lo12
		for j = 0, NUM_LIMBS - 1 do
			local offset = j * LIMB_BYTES
			local v = buffer.readf64(result, offset) * HALF_BASE + carryVal
			buffer.writef64(result, offset, v % LIMB_BASE)
			carryVal = math.floor(v / LIMB_BASE)
		end
		-- Reduce mod m
		if BigInt.cmp(result, m) >= 0 then
			local _, r = BigInt.divmod(result, m)
			result = r
		end
	end

	return result
end

function BigInt.addmod(a: BigInt, b: BigInt, m: BigInt): BigInt
	local sum = BigInt.add(a, b)
	if BigInt.cmp(sum, m) >= 0 then
		return BigInt.sub(sum, m)
	end
	return sum
end

function BigInt.submod(a: BigInt, b: BigInt, m: BigInt): BigInt
	if BigInt.cmp(a, b) >= 0 then
		local diff = BigInt.sub(a, b)
		if BigInt.cmp(diff, m) >= 0 then
			return BigInt.mod(diff, m)
		end
		return diff
	else
		-- a < b: result = m - ((b - a) mod m)
		local diff = BigInt.sub(b, a)
		local r = BigInt.mod(diff, m)
		if isZeroBuf(r) then
			return BigInt.zero()
		end
		return BigInt.sub(m, r)
	end
end

function BigInt.mulmod(a: BigInt, b: BigInt, m: BigInt): BigInt
	local wide = mulWide(a, b)
	return reduceWide(wide, m)
end

function BigInt.powmod(a: BigInt, e: BigInt, m: BigInt): BigInt
	if isZeroBuf(m) then
		error("BigInt: modulus cannot be zero")
	end
	if isZeroBuf(e) then
		return BigInt.one()
	end

	local base = BigInt.mod(a, m)
	local result = BigInt.one()
	local eBitLen = BigInt.bitLength(e)

	for i = 0, eBitLen - 1 do
		if BigInt.getBit(e, i) == 1 then
			result = BigInt.mulmod(result, base, m)
		end
		if i < eBitLen - 1 then
			base = BigInt.mulmod(base, base, m)
		end
	end
	return result
end

function BigInt.invmod(a: BigInt, m: BigInt): BigInt
	-- Extended Euclidean Algorithm with sign tracking
	if isZeroBuf(a) then
		error("BigInt: cannot invert zero")
	end

	local old_r = BigInt.mod(a, m)
	local r = clone(m)
	local old_s = BigInt.one()
	local s = BigInt.zero()
	local old_s_neg = false
	local s_neg = false

	while not isZeroBuf(r) do
		local q, rem = BigInt.divmod(old_r, r)

		-- Save current s values before overwriting
		local temp_s = s
		local temp_neg = s_neg

		-- Compute new_s = old_s_signed - q * s_signed
		local qs = BigInt.mul(q, s) -- magnitude of q * |s|

		local new_s: buffer
		local new_s_neg: boolean

		if old_s_neg == s_neg then
			-- old_s and q*s have the same sign: subtract magnitudes
			if BigInt.cmp(old_s, qs) >= 0 then
				new_s = BigInt.sub(old_s, qs)
				new_s_neg = old_s_neg
			else
				new_s = BigInt.sub(qs, old_s)
				new_s_neg = not old_s_neg
			end
		else
			-- Different signs: add magnitudes, keep old_s's sign
			new_s = BigInt.add(old_s, qs)
			new_s_neg = old_s_neg
		end

		-- Shift: old <- current, current <- new
		old_r = r
		r = rem
		old_s = temp_s
		old_s_neg = temp_neg
		s = new_s
		s_neg = new_s_neg
	end

	-- old_r should be 1 (gcd)
	if not BigInt.eq(old_r, BigInt.one()) then
		error("BigInt: not invertible (gcd != 1)")
	end

	if old_s_neg then
		local reduced = BigInt.mod(old_s, m)
		if isZeroBuf(reduced) then
			return BigInt.zero()
		end
		return BigInt.sub(m, reduced)
	else
		return BigInt.mod(old_s, m)
	end
end

--------------------------------------------------------------------------------
-- Barrett Reduction
--------------------------------------------------------------------------------

function BigInt.createBarrettCtx(m: BigInt): BarrettCtx
	local k = BigInt.bitLength(m)

	-- Compute mu = floor(2^(2k) / m) via bit-by-bit long division.
	-- The dividend is 2^(2k) which has a single 1 bit at position 2k.
	-- We iterate from bit (2k-1) down to 0, tracking the remainder.
	local mu = newBuf()
	local remainder = BigInt.one() -- Represents the leading 1 bit of 2^(2k)

	for i = 2 * k - 1, 0, -1 do
		-- Shift remainder left by 1
		for j = NUM_LIMBS - 1, 1, -1 do
			local offset = j * LIMB_BYTES
			local prev = (j - 1) * LIMB_BYTES
			local v = buffer.readf64(remainder, offset) * 2
			v += math.floor(buffer.readf64(remainder, prev) / (LIMB_BASE / 2))
			buffer.writef64(remainder, offset, v % LIMB_BASE)
		end
		buffer.writef64(remainder, 0, (buffer.readf64(remainder, 0) * 2) % LIMB_BASE)

		-- Bit i of dividend is 0 (only bit 2k is 1, already accounted for)
		if BigInt.cmp(remainder, m) >= 0 then
			remainder = BigInt.sub(remainder, m)
			-- Set bit i in mu
			local limbIdx = math.floor(i / LIMB_BITS)
			local bitIdx = i % LIMB_BITS
			if limbIdx < NUM_LIMBS then
				buffer.writef64(mu, limbIdx * LIMB_BYTES, buffer.readf64(mu, limbIdx * LIMB_BYTES) + (2 ^ bitIdx))
			end
		end
	end

	return {
		m = clone(m),
		mu = mu,
		k = k,
	}
end

function BigInt.mulmodB(a: BigInt, b: BigInt, ctx: BarrettCtx): BigInt
	-- Barrett modular multiplication:
	-- x = a * b (full product, 22 limbs)
	-- q1 = x >> (k-1)
	-- q2 = q1 * mu (22 limbs)
	-- q3 = q2 >> (k+1)
	-- r = (x mod 2^(k+1)) - (q3 * m mod 2^(k+1))
	-- While r >= m: r -= m
	local k = ctx.k

	-- Step 0: full product
	local x = mulWide(a, b)

	-- Step 1: q1 = x >> (k-1) -- fits in 11 limbs
	local q1 = wideShiftRight(x, k - 1)

	-- Step 2: q2 = q1 * mu -- 22 limbs
	local q2 = mulWide(q1, ctx.mu)

	-- Step 3: q3 = q2 >> (k+1) -- fits in 11 limbs
	local q3 = wideShiftRight(q2, k + 1)

	-- Step 4: r = x_low - q3m_low (mod 2^(k+1))
	local x_low = wideTruncate(x, k + 1)
	local q3m = mulWide(q3, ctx.m)
	local q3m_low = wideTruncate(q3m, k + 1)

	local r: buffer
	if BigInt.cmp(x_low, q3m_low) >= 0 then
		r = BigInt.sub(x_low, q3m_low)
	else
		-- Add 2^(k+1) to handle underflow
		local pow = BigInt.shl(BigInt.one(), k + 1)
		r = BigInt.sub(BigInt.add(x_low, pow), q3m_low)
	end

	-- Step 5: at most 2-3 corrections
	while BigInt.cmp(r, ctx.m) >= 0 do
		r = BigInt.sub(r, ctx.m)
	end

	return r
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function BigInt.clone(a: BigInt): BigInt
	return clone(a)
end

return BigInt
