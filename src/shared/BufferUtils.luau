--!strict
--!native
--!optimize 2
-- BufferUtils: Shared buffer utility functions
-- Consolidates bufferToHex, concatBuffers, singleByte, readBE32, writeBE32
-- extracted from Keccak, SHA256, and ECDSA modules

local BufferUtils = {}

--- Hex character lookup string (1-indexed: position 1='0', position 16='f')
local HEX_CHARS = "0123456789abcdef"

--- Convert a buffer to a lowercase hex string (no "0x" prefix).
function BufferUtils.bufferToHex(buf: buffer): string
	local parts = table.create(buffer.len(buf))
	for i = 0, buffer.len(buf) - 1 do
		local byte = buffer.readu8(buf, i)
		local hi = math.floor(byte / 16) + 1
		local lo = (byte % 16) + 1
		parts[i + 1] = string.sub(HEX_CHARS, hi, hi) .. string.sub(HEX_CHARS, lo, lo)
	end
	return table.concat(parts)
end

--- Concatenate multiple buffers into one.
function BufferUtils.concatBuffers(...: buffer): buffer
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

--- Create a single-byte buffer with the given value.
function BufferUtils.singleByte(v: number): buffer
	local b = buffer.create(1)
	buffer.writeu8(b, 0, v)
	return b
end

--- Read a 32-bit big-endian value from a buffer at the given offset.
function BufferUtils.readBE32(buf: buffer, offset: number): number
	return buffer.readu8(buf, offset) * 0x1000000
		+ buffer.readu8(buf, offset + 1) * 0x10000
		+ buffer.readu8(buf, offset + 2) * 0x100
		+ buffer.readu8(buf, offset + 3)
end

--- Write a 32-bit value as 4 big-endian bytes into a buffer at the given offset.
function BufferUtils.writeBE32(buf: buffer, offset: number, value: number)
	buffer.writeu8(buf, offset, bit32.band(bit32.rshift(value, 24), 0xFF))
	buffer.writeu8(buf, offset + 1, bit32.band(bit32.rshift(value, 16), 0xFF))
	buffer.writeu8(buf, offset + 2, bit32.band(bit32.rshift(value, 8), 0xFF))
	buffer.writeu8(buf, offset + 3, bit32.band(value, 0xFF))
end

return BufferUtils
