--!strict
-- CallData: Encode Luau values into Starknet calldata (flat felt arrays)
-- All calldata values are hex strings with "0x" prefix matching Starknet JSON-RPC format
-- Reference: starknet.js CallData.compile, fromCallsToExecuteCalldata_cairo1

local BigInt = require("../crypto/BigInt")
local StarkField = require("../crypto/StarkField")
local Keccak = require("../crypto/Keccak")

local CallData = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type Call = {
	contractAddress: string,
	entrypoint: string,
	calldata: { string },
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Mask for 128-bit values: 2^128 - 1
local MASK_128 = BigInt.sub(BigInt.shl(BigInt.one(), 128), BigInt.one())

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Normalize a hex string through BigInt for consistent format (strips leading zeros, adds 0x prefix)
local function normalizeHex(hex: string): string
	return BigInt.toHex(BigInt.fromHex(hex))
end

--------------------------------------------------------------------------------
-- Single value encoders
--------------------------------------------------------------------------------

-- Encode a single felt value (hex string normalization)
function CallData.encodeFelt(hex: string): { string }
	return { normalizeHex(hex) }
end

-- Encode a boolean as "0x1" or "0x0"
function CallData.encodeBool(value: boolean): { string }
	return { if value then "0x1" else "0x0" }
end

-- Encode a short ASCII string (max 31 chars) as a single felt
-- Each ASCII byte becomes part of the felt value (big-endian byte order)
-- Reference: starknet.js encodeShortString
function CallData.encodeShortString(str: string): { string }
	if #str == 0 then
		return { "0x0" }
	end
	if #str > 31 then
		error("CallData: short string exceeds 31 characters")
	end
	for i = 1, #str do
		if string.byte(str, i) > 127 then
			error("CallData: short string must be ASCII only")
		end
	end
	local hexParts = {}
	for i = 1, #str do
		table.insert(hexParts, string.format("%02x", string.byte(str, i)))
	end
	return { "0x" .. table.concat(hexParts) }
end

--------------------------------------------------------------------------------
-- Multi-value encoders
--------------------------------------------------------------------------------

-- Encode a U256 value as two 128-bit felts: { low, high }
-- Input: hex string representing a value up to 2^256 - 1
function CallData.encodeU256(hex: string): { string }
	local bigVal = BigInt.fromHex(hex)
	local low = BigInt.band(bigVal, MASK_128)
	local high = BigInt.shr(bigVal, 128)
	return { BigInt.toHex(low), BigInt.toHex(high) }
end

-- Encode an array with length prefix: { length, ...elements }
-- Input: pre-encoded hex string elements
function CallData.encodeArray(elements: { string }): { string }
	local result: { string } = { string.format("0x%x", #elements) }
	for _, elem in elements do
		table.insert(result, elem)
	end
	return result
end

-- Encode a struct as ordered field concatenation (no length prefix)
-- Input: pre-encoded hex string fields in order
function CallData.encodeStruct(fields: { string }): { string }
	local result: { string } = {}
	for _, field in fields do
		table.insert(result, field)
	end
	return result
end

-- Encode multicall format for __execute__ (Cairo 1)
-- Format: [num_calls, to_0, selector_0, calldata_len_0, ...calldata_0, ...]
-- Reference: starknet.js fromCallsToExecuteCalldata_cairo1
function CallData.encodeMulticall(calls: { Call }): { string }
	local result: { string } = {}

	-- Number of calls (array length prefix)
	table.insert(result, string.format("0x%x", #calls))

	for _, call in calls do
		-- Contract address
		table.insert(result, normalizeHex(call.contractAddress))

		-- Selector computed from entrypoint name via snKeccak
		local selector = Keccak.getSelectorFromName(call.entrypoint)
		table.insert(result, StarkField.toHex(selector))

		-- Calldata as length-prefixed array
		table.insert(result, string.format("0x%x", #call.calldata))
		for _, cd in call.calldata do
			table.insert(result, cd)
		end
	end

	return result
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

-- Convert a number to hex felt string
function CallData.numberToHex(n: number): string
	return StarkField.toHex(StarkField.fromNumber(n))
end

-- Concatenate multiple encoded results into a single calldata array
function CallData.concat(...: { string }): { string }
	local result: { string } = {}
	for i = 1, select("#", ...) do
		local arr: { string } = select(i, ...)
		for _, v in arr do
			table.insert(result, v)
		end
	end
	return result
end

return CallData
