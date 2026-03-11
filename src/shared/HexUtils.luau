--!strict
-- HexUtils: Shared hex string utility functions
-- Consolidates normalizeHex, asciiToHex, hasHexPrefix, parseHexToNumber
-- used across 8+ modules in the codebase

local BigInt = require("../crypto/BigInt")

local HexUtils = {}

--- Check if a string has a "0x" or "0X" hex prefix.
function HexUtils.hasHexPrefix(s: string): boolean
	return string.sub(s, 1, 2) == "0x" or string.sub(s, 1, 2) == "0X"
end

--- Normalize a hex string to canonical form (lowercase, no leading zeros, "0x" prefix).
--- Uses BigInt roundtrip for correctness.
function HexUtils.normalizeHex(hex: string): string
	return BigInt.toHex(BigInt.fromHex(hex))
end

--- Encode an ASCII string as a hex felt value (big-endian byte order, "0x" prefix).
--- Returns "0x0" for empty strings. Does NOT validate length or ASCII range —
--- callers (e.g., CallData.encodeShortString) add their own validation.
function HexUtils.asciiToHex(str: string): string
	if #str == 0 then
		return "0x0"
	end
	local hexParts = {}
	for i = 1, #str do
		table.insert(hexParts, string.format("%02x", string.byte(str, i)))
	end
	return "0x" .. table.concat(hexParts)
end

--- Parse a hex string to a Luau number.
--- Handles both "0x1a" and "1a" forms. Returns 0 on failure.
function HexUtils.parseHexToNumber(hex: string): number
	if HexUtils.hasHexPrefix(hex) then
		return tonumber(string.sub(hex, 3), 16) or 0
	end
	return tonumber(hex, 16) or 0
end

--- Decode a felt252 hex value to a UTF-8 short string.
--- Inverse of asciiToHex. Returns "" for "0x0" or empty input.
function HexUtils.feltToShortString(hex: string): string
	local stripped = hex
	if HexUtils.hasHexPrefix(stripped) then
		stripped = string.sub(stripped, 3)
	end
	-- Remove leading zeros
	stripped = string.gsub(stripped, "^0+", "")
	if stripped == "" then
		return ""
	end
	-- Pad to even length
	if #stripped % 2 ~= 0 then
		stripped = "0" .. stripped
	end
	local chars = {}
	for i = 1, #stripped, 2 do
		local byte = tonumber(string.sub(stripped, i, i + 1), 16)
		if byte then
			table.insert(chars, string.char(byte))
		end
	end
	return table.concat(chars)
end

return HexUtils
