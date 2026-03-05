--!strict
-- ByteArray: Shared Cairo ByteArray encode/decode logic
-- Consolidates duplicate implementations from AbiCodec.luau and TypedData.luau
-- ByteArray format: [numFullChunks, chunk0..N, pendingWord, pendingLen]
-- Each chunk is 31 bytes of ASCII packed big-endian into a felt.

local HexUtils = require("./HexUtils")

local ByteArray = {}

local CHUNK_SIZE = 31

--- Convert a hex string (with "0x" prefix) to a Luau string of the given byte length.
--- Left-pads hex to the required width before decoding.
function ByteArray.hexToString(hex: string, numBytes: number): string
	local raw = string.sub(hex, 3) -- strip "0x"
	local targetLen = numBytes * 2
	while #raw < targetLen do
		raw = "0" .. raw
	end
	local bytes = {}
	for j = 1, targetLen, 2 do
		local byte = tonumber(string.sub(raw, j, j + 1), 16) or 0
		table.insert(bytes, string.char(byte))
	end
	return table.concat(bytes)
end

--- Encode a Luau string as a Cairo ByteArray calldata.
--- Output: { num_full_chunks_hex, chunk0_hex, ..., pending_word_hex, pending_word_len_hex }
function ByteArray.encode(str: string): { string }
	local len = #str
	local numFullChunks = math.floor(len / CHUNK_SIZE)
	local pendingLen = len - (numFullChunks * CHUNK_SIZE)

	local result: { string } = {}

	-- Number of full 31-byte chunks
	table.insert(result, string.format("0x%x", numFullChunks))

	-- Encode each full chunk
	for i = 0, numFullChunks - 1 do
		local chunk = string.sub(str, i * CHUNK_SIZE + 1, (i + 1) * CHUNK_SIZE)
		table.insert(result, HexUtils.asciiToHex(chunk))
	end

	-- Pending word (remaining bytes < 31)
	if pendingLen > 0 then
		local pending = string.sub(str, numFullChunks * CHUNK_SIZE + 1)
		table.insert(result, HexUtils.asciiToHex(pending))
	else
		table.insert(result, "0x0")
	end

	-- Pending word length
	table.insert(result, string.format("0x%x", pendingLen))

	return result
end

--- Decode a Cairo ByteArray from result felts starting at offset.
--- Returns (decoded_string, felts_consumed).
function ByteArray.decode(results: { string }, offset: number): (string, number)
	-- Read number of full chunks
	local numChunksHex = results[offset]
	local numChunks = HexUtils.parseHexToNumber(numChunksHex)
	local consumed = 1

	local parts: { string } = {}

	-- Read each full 31-byte chunk
	for _ = 1, numChunks do
		local chunkHex = results[offset + consumed]
		consumed += 1
		table.insert(parts, ByteArray.hexToString(chunkHex, CHUNK_SIZE))
	end

	-- Read pending word
	local pendingHex = results[offset + consumed]
	consumed += 1

	-- Read pending word length
	local pendingLenHex = results[offset + consumed]
	consumed += 1
	local pendingLen = HexUtils.parseHexToNumber(pendingLenHex)

	-- Decode pending bytes
	if pendingLen > 0 then
		table.insert(parts, ByteArray.hexToString(pendingHex, pendingLen))
	end

	return table.concat(parts), consumed
end

return ByteArray
