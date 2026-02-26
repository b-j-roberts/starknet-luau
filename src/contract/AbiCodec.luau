--!strict
-- AbiCodec: Recursive ABI type resolution, encoding, and decoding for Cairo types
-- Supports: felt252, bool, u256, structs, enums, arrays, spans, tuples, Option, Result, ByteArray
-- Internal module consumed by Contract.luau — not exported through barrel init.luau
-- Reference: starknet.js CallData.compile / CallData.parse

local CallData = require("../tx/CallData")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

local AbiCodec = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type TypeDef = {
	kind: string, -- "felt" | "bool" | "u256" | "unit" | "struct" | "enum" | "array" | "tuple" | "bytearray"
	members: { { name: string, type: string } }?, -- for structs
	variants: { { name: string, type: string } }?, -- for enums
	elementType: string?, -- for arrays/spans
	tupleTypes: { string }?, -- for tuples
}

export type TypeMap = { [string]: TypeDef }

--- ABI entry types we handle
type AbiEntry = {
	type: string,
	name: string?,
	members: { { name: string, type: string } }?,
	variants: { { name: string, type: string } }?,
	items: { any }?,
	inputs: { { name: string, type: string } }?,
	outputs: { { name: string, type: string } }?,
	state_mutability: string?,
}

--------------------------------------------------------------------------------
-- Built-in type aliases
--------------------------------------------------------------------------------

local BUILTIN_TYPES: { [string]: TypeDef } = {
	-- felt aliases
	["core::felt252"] = { kind = "felt" },
	["felt252"] = { kind = "felt" },
	["core::starknet::contract_address::ContractAddress"] = { kind = "felt" },
	["ContractAddress"] = { kind = "felt" },
	["core::starknet::class_hash::ClassHash"] = { kind = "felt" },
	["ClassHash"] = { kind = "felt" },
	["core::starknet::eth_address::EthAddress"] = { kind = "felt" },
	["bytes31"] = { kind = "felt" },
	-- bool
	["core::bool"] = { kind = "bool" },
	["bool"] = { kind = "bool" },
	-- u256
	["core::integer::u256"] = { kind = "u256" },
	["u256"] = { kind = "u256" },
	-- unit
	["()"] = { kind = "unit" },
	-- bytearray
	["core::byte_array::ByteArray"] = { kind = "bytearray" },
	["ByteArray"] = { kind = "bytearray" },
}

-- Integer type patterns (single-felt encoding)
local INTEGER_PATTERNS = {
	"^core::integer::u%d+$",
	"^u%d+$",
	"^core::integer::i%d+$",
	"^i%d+$",
}

--------------------------------------------------------------------------------
-- Generic type parsing helpers
--------------------------------------------------------------------------------

--- Extract the inner type from a generic like "core::array::Array::<core::felt252>"
--- Returns nil if not a matching pattern
local function extractGenericInner(typeName: string, prefix: string): string?
	-- Match "prefix::<inner>" pattern
	local pat = "^" .. prefix .. "::<(.+)>$"
	local inner = string.match(typeName, pat)
	return inner
end

--- Parse a tuple type string "(T1, T2, ...)" into component types
--- Handles nested generics by counting angle bracket depth
local function parseTupleTypes(typeName: string): { string }?
	-- Must start with ( and end with )
	if string.sub(typeName, 1, 1) ~= "(" or string.sub(typeName, #typeName, #typeName) ~= ")" then
		return nil
	end

	-- Empty tuple
	local inner = string.sub(typeName, 2, #typeName - 1)
	if inner == "" then
		return {}
	end

	local types: { string } = {}
	local depth = 0
	local start = 1

	for i = 1, #inner do
		local ch = string.sub(inner, i, i)
		if ch == "<" or ch == "(" then
			depth += 1
		elseif ch == ">" or ch == ")" then
			depth -= 1
		elseif ch == "," and depth == 0 then
			local t = string.match(string.sub(inner, start, i - 1), "^%s*(.-)%s*$") or ""
			table.insert(types, t)
			start = i + 1
		end
	end

	-- Last element
	local t = string.match(string.sub(inner, start), "^%s*(.-)%s*$") or ""
	if t ~= "" then
		table.insert(types, t)
	end

	return types
end

--------------------------------------------------------------------------------
-- Type Map Builder
--------------------------------------------------------------------------------

--- Build a TypeMap from a full Cairo ABI array.
--- Parses struct and enum definitions, registers built-in aliases.
function AbiCodec.buildTypeMap(abi: { any }): TypeMap
	local typeMap: TypeMap = table.clone(BUILTIN_TYPES)

	-- Parse ABI entries
	for _, entry_ in abi do
		local entry = entry_ :: AbiEntry
		if entry.type == "struct" and entry.name then
			-- Skip core::bool which is handled as built-in
			if entry.name ~= "core::bool" then
				typeMap[entry.name :: string] = {
					kind = "struct",
					members = entry.members or {},
				}
			end
		elseif entry.type == "enum" and entry.name then
			-- Skip core::bool and core::option::Option and core::result::Result
			-- (these are handled as generics at resolve time)
			if
				entry.name ~= "core::bool"
				and not string.match(entry.name :: string, "^core::option::Option")
				and not string.match(entry.name :: string, "^core::result::Result")
			then
				typeMap[entry.name :: string] = {
					kind = "enum",
					variants = entry.variants or {},
				}
			end
		end
	end

	return typeMap
end

--------------------------------------------------------------------------------
-- Type Resolution
--------------------------------------------------------------------------------

--- Resolve a type name to a TypeDef. Handles generics, tuples, and caching.
function AbiCodec.resolveType(typeName: string, typeMap: TypeMap): TypeDef
	-- Check cache/map first
	local cached = typeMap[typeName]
	if cached then
		return cached
	end

	-- Check integer patterns (single felt)
	for _, pattern in INTEGER_PATTERNS do
		if string.match(typeName, pattern) then
			local def: TypeDef = { kind = "felt" }
			typeMap[typeName] = def
			return def
		end
	end

	-- Array generic: core::array::Array::<T>
	local arrayInner = extractGenericInner(typeName, "core::array::Array")
	if arrayInner then
		local def: TypeDef = { kind = "array", elementType = arrayInner }
		typeMap[typeName] = def
		return def
	end

	-- Span generic: core::array::Span::<T>
	local spanInner = extractGenericInner(typeName, "core::array::Span")
	if spanInner then
		local def: TypeDef = { kind = "array", elementType = spanInner }
		typeMap[typeName] = def
		return def
	end

	-- Option generic: core::option::Option::<T>
	local optionInner = extractGenericInner(typeName, "core::option::Option")
	if optionInner then
		local def: TypeDef = {
			kind = "enum",
			variants = {
				{ name = "Some", type = optionInner },
				{ name = "None", type = "()" },
			},
		}
		typeMap[typeName] = def
		return def
	end

	-- Result generic: core::result::Result::<T, E>
	local resultInner = extractGenericInner(typeName, "core::result::Result")
	if resultInner then
		-- Parse T, E from "T, E" string
		local types = parseTupleTypes("(" .. resultInner .. ")")
		if types and #types == 2 then
			local def: TypeDef = {
				kind = "enum",
				variants = {
					{ name = "Ok", type = types[1] },
					{ name = "Err", type = types[2] },
				},
			}
			typeMap[typeName] = def
			return def
		end
	end

	-- Tuple: (T1, T2, ...)
	local tupleTypes = parseTupleTypes(typeName)
	if tupleTypes then
		local def: TypeDef = { kind = "tuple", tupleTypes = tupleTypes }
		typeMap[typeName] = def
		return def
	end

	-- Fallback: treat as felt (backward compat)
	local def: TypeDef = { kind = "felt" }
	typeMap[typeName] = def
	return def
end

--------------------------------------------------------------------------------
-- ByteArray Encoding/Decoding
--------------------------------------------------------------------------------

--- Encode a Luau string as a Cairo ByteArray.
--- Output: { num_full_chunks, chunk0_hex, ..., pending_word_hex, pending_word_len }
--- Each chunk is 31 bytes of ASCII packed big-endian into a felt.
function AbiCodec.encodeByteArray(str: string): { string }
	local CHUNK_SIZE = 31
	local len = #str
	local numFullChunks = math.floor(len / CHUNK_SIZE)
	local pendingLen = len - (numFullChunks * CHUNK_SIZE)

	local result: { string } = {}

	-- Number of full 31-byte chunks
	table.insert(result, string.format("0x%x", numFullChunks))

	-- Encode each full chunk
	for i = 0, numFullChunks - 1 do
		local chunk = string.sub(str, i * CHUNK_SIZE + 1, (i + 1) * CHUNK_SIZE)
		local hexParts = {}
		for j = 1, #chunk do
			table.insert(hexParts, string.format("%02x", string.byte(chunk, j)))
		end
		table.insert(result, "0x" .. table.concat(hexParts))
	end

	-- Pending word (remaining bytes < 31)
	if pendingLen > 0 then
		local pending = string.sub(str, numFullChunks * CHUNK_SIZE + 1)
		local hexParts = {}
		for j = 1, #pending do
			table.insert(hexParts, string.format("%02x", string.byte(pending, j)))
		end
		table.insert(result, "0x" .. table.concat(hexParts))
	else
		table.insert(result, "0x0")
	end

	-- Pending word length
	table.insert(result, string.format("0x%x", pendingLen))

	return result
end

--- Decode a Cairo ByteArray from result felts starting at offset.
--- Returns (string, felts_consumed).
function AbiCodec.decodeByteArray(results: { string }, offset: number): (string, number)
	-- Read number of full chunks
	local numChunksHex = results[offset]
	local numChunks = tonumber(numChunksHex, 16) or tonumber(string.sub(numChunksHex, 3), 16) or 0
	local consumed = 1

	local parts: { string } = {}

	-- Read each full 31-byte chunk
	for _ = 1, numChunks do
		local chunkHex = results[offset + consumed]
		consumed += 1
		-- Convert hex to 31 bytes
		local hex = string.sub(chunkHex, 3) -- strip "0x"
		-- Pad to 62 chars (31 bytes)
		while #hex < 62 do
			hex = "0" .. hex
		end
		local bytes = {}
		for j = 1, 62, 2 do
			local byte = tonumber(string.sub(hex, j, j + 1), 16) or 0
			table.insert(bytes, string.char(byte))
		end
		table.insert(parts, table.concat(bytes))
	end

	-- Read pending word
	local pendingHex = results[offset + consumed]
	consumed += 1

	-- Read pending word length
	local pendingLenHex = results[offset + consumed]
	consumed += 1
	local pendingLen = tonumber(pendingLenHex, 16) or tonumber(string.sub(pendingLenHex, 3), 16) or 0

	-- Decode pending bytes
	if pendingLen > 0 then
		local hex = string.sub(pendingHex, 3) -- strip "0x"
		-- Pad to 2*pendingLen
		while #hex < pendingLen * 2 do
			hex = "0" .. hex
		end
		local bytes = {}
		for j = 1, pendingLen * 2, 2 do
			local byte = tonumber(string.sub(hex, j, j + 1), 16) or 0
			table.insert(bytes, string.char(byte))
		end
		table.insert(parts, table.concat(bytes))
	end

	return table.concat(parts), consumed
end

--------------------------------------------------------------------------------
-- Recursive Encoder
--------------------------------------------------------------------------------

--- Encode a value into calldata felts based on resolved type.
--- Returns an array of hex strings.
function AbiCodec.encode(value: any, typeName: string, typeMap: TypeMap): { string }
	local typeDef = AbiCodec.resolveType(typeName, typeMap)
	local kind = typeDef.kind

	if kind == "felt" then
		return CallData.encodeFelt(tostring(value))
	elseif kind == "bool" then
		return CallData.encodeBool(value :: boolean)
	elseif kind == "u256" then
		return CallData.encodeU256(tostring(value))
	elseif kind == "unit" then
		return {}
	elseif kind == "bytearray" then
		return AbiCodec.encodeByteArray(value :: string)
	elseif kind == "struct" then
		local members = typeDef.members or {}
		local result: { string } = {}
		for _, member in members do
			local memberValue = (value :: any)[member.name]
			local encoded = AbiCodec.encode(memberValue, member.type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
		end
		return result
	elseif kind == "enum" then
		local variants = typeDef.variants or {}
		return AbiCodec.encodeEnum(value, variants, typeMap)
	elseif kind == "array" then
		local elementType = typeDef.elementType or "core::felt252"
		local arr = value :: { any }
		local result: { string } = {}
		-- Length prefix
		table.insert(result, string.format("0x%x", #arr))
		-- Encode each element
		for _, elem in arr do
			local encoded = AbiCodec.encode(elem, elementType, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
		end
		return result
	elseif kind == "tuple" then
		local tupleTypes = typeDef.tupleTypes or {}
		local arr = value :: { any }
		local result: { string } = {}
		for i, elemType in tupleTypes do
			local encoded = AbiCodec.encode(arr[i], elemType, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
		end
		return result
	end

	-- Fallback: treat as felt
	return CallData.encodeFelt(tostring(value))
end

--- Encode an enum value. Handles Option, Result, and custom enums.
--- Accepted formats:
---   Option: { Some = val } | { None = true } | nil (→ None)
---   Result: { Ok = val } | { Err = val }
---   Custom: { variant = "Name", value = data }
function AbiCodec.encodeEnum(value: any, variants: { { name: string, type: string } }, typeMap: TypeMap): { string }
	-- Check if this is an Option-like enum (Some/None)
	local isOption = #variants == 2 and variants[1].name == "Some" and variants[2].name == "None"

	-- Check if this is a Result-like enum (Ok/Err)
	local isResult = #variants == 2 and variants[1].name == "Ok" and variants[2].name == "Err"

	if isOption then
		-- Accept { Some = val } or { None = true } or nil
		if value == nil then
			-- None variant (index 1)
			local result: { string } = { "0x1" }
			local encoded = AbiCodec.encode(nil, variants[2].type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
			return result
		end

		local tbl = value :: any
		if type(tbl) == "table" and tbl.None ~= nil then
			local result: { string } = { "0x1" }
			local encoded = AbiCodec.encode(nil, variants[2].type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
			return result
		end

		if type(tbl) == "table" and tbl.Some ~= nil then
			local result: { string } = { "0x0" }
			local encoded = AbiCodec.encode(tbl.Some, variants[1].type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
			return result
		end

		-- Bare value → treat as Some
		local result: { string } = { "0x0" }
		local encoded = AbiCodec.encode(value, variants[1].type, typeMap)
		for _, felt in encoded do
			table.insert(result, felt)
		end
		return result
	end

	if isResult then
		local tbl = value :: any
		if type(tbl) == "table" and tbl.Ok ~= nil then
			local result: { string } = { "0x0" }
			local encoded = AbiCodec.encode(tbl.Ok, variants[1].type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
			return result
		elseif type(tbl) == "table" and tbl.Err ~= nil then
			local result: { string } = { "0x1" }
			local encoded = AbiCodec.encode(tbl.Err, variants[2].type, typeMap)
			for _, felt in encoded do
				table.insert(result, felt)
			end
			return result
		end
		error(StarknetError.abi("AbiCodec: Result value must have Ok or Err key", ErrorCodes.ENCODE_ERROR.code))
	end

	-- Custom enum: { variant = "Name", value = data }
	local tbl = value :: any
	if type(tbl) == "table" and tbl.variant then
		for i, variant in variants do
			if variant.name == tbl.variant then
				local result: { string } = { string.format("0x%x", i - 1) }
				local variantData = tbl.value
				local encoded = AbiCodec.encode(variantData, variant.type, typeMap)
				for _, felt in encoded do
					table.insert(result, felt)
				end
				return result
			end
		end
		error(StarknetError.abi(`AbiCodec: unknown enum variant "{tbl.variant}"`, ErrorCodes.UNKNOWN_ENUM_VARIANT.code))
	end

	error(
		StarknetError.abi(
			"AbiCodec: enum value must be a table with variant key or Option/Result format",
			ErrorCodes.ENCODE_ERROR.code
		)
	)
end

--------------------------------------------------------------------------------
-- Recursive Decoder
--------------------------------------------------------------------------------

--- Decode a value from result felts starting at offset.
--- Returns (decoded_value, felts_consumed).
function AbiCodec.decode(results: { string }, offset: number, typeName: string, typeMap: TypeMap): (any, number)
	local typeDef = AbiCodec.resolveType(typeName, typeMap)
	local kind = typeDef.kind

	if kind == "felt" then
		return results[offset], 1
	elseif kind == "bool" then
		return results[offset] == "0x1", 1
	elseif kind == "u256" then
		local low = results[offset]
		local high = results[offset + 1]
		return { low = low, high = high }, 2
	elseif kind == "unit" then
		return nil, 0
	elseif kind == "bytearray" then
		return AbiCodec.decodeByteArray(results, offset)
	elseif kind == "struct" then
		local members = typeDef.members or {}
		local decoded: { [string]: any } = {}
		local totalConsumed = 0
		for _, member in members do
			local val, consumed = AbiCodec.decode(results, offset + totalConsumed, member.type, typeMap)
			decoded[member.name] = val
			totalConsumed += consumed
		end
		return decoded, totalConsumed
	elseif kind == "enum" then
		local variants = typeDef.variants or {}
		return AbiCodec.decodeEnum(results, offset, variants, typeMap)
	elseif kind == "array" then
		local elementType = typeDef.elementType or "core::felt252"
		-- Read length
		local lenHex = results[offset]
		local len = tonumber(lenHex, 16) or tonumber(string.sub(lenHex, 3), 16) or 0
		local totalConsumed = 1

		local arr: { any } = {}
		for _ = 1, len do
			local val, consumed = AbiCodec.decode(results, offset + totalConsumed, elementType, typeMap)
			table.insert(arr, val)
			totalConsumed += consumed
		end
		return arr, totalConsumed
	elseif kind == "tuple" then
		local tupleTypes = typeDef.tupleTypes or {}
		local arr: { any } = {}
		local totalConsumed = 0
		for _, elemType in tupleTypes do
			local val, consumed = AbiCodec.decode(results, offset + totalConsumed, elemType, typeMap)
			table.insert(arr, val)
			totalConsumed += consumed
		end
		return arr, totalConsumed
	end

	-- Fallback: single felt
	return results[offset], 1
end

--- Decode an enum value from result felts.
--- Returns (decoded_value, felts_consumed).
function AbiCodec.decodeEnum(
	results: { string },
	offset: number,
	variants: { { name: string, type: string } },
	typeMap: TypeMap
): (any, number)
	-- Read variant index
	local idxHex = results[offset]
	local idx = tonumber(idxHex, 16) or tonumber(string.sub(idxHex, 3), 16) or 0
	local totalConsumed = 1

	local variant = variants[idx + 1] -- 1-indexed
	if not variant then
		error(StarknetError.abi(`AbiCodec: invalid enum variant index {idx}`, ErrorCodes.DECODE_ERROR.code))
	end

	-- Decode variant data
	local val, consumed = AbiCodec.decode(results, offset + totalConsumed, variant.type, typeMap)
	totalConsumed += consumed

	return { variant = variant.name, value = val }, totalConsumed
end

--------------------------------------------------------------------------------
-- Convenience: encode/decode a full function's inputs/outputs
--------------------------------------------------------------------------------

--- Encode all function inputs into a flat calldata array.
function AbiCodec.encodeInputs(args: { any }, inputs: { { name: string, type: string } }, typeMap: TypeMap): { string }
	local calldata: { string } = {}
	for i, input in inputs do
		local encoded = AbiCodec.encode(args[i], input.type, typeMap)
		for _, felt in encoded do
			table.insert(calldata, felt)
		end
	end
	return calldata
end

--- Decode function outputs from a result felt array.
--- Returns a single value for single output, or a table keyed by output name for multiple.
function AbiCodec.decodeOutputs(results: { string }, outputs: { { name: string, type: string } }, typeMap: TypeMap): any
	if #outputs == 0 then
		return results
	end

	if #outputs == 1 then
		local decoded, _ = AbiCodec.decode(results, 1, outputs[1].type, typeMap)
		return decoded
	end

	-- Multiple outputs: keyed by name
	local parsed: { [string]: any } = {}
	local offset = 1
	for _, output in outputs do
		local decoded, consumed = AbiCodec.decode(results, offset, output.type, typeMap)
		local key = if output.name ~= "" then output.name else tostring(offset)
		parsed[key] = decoded
		offset += consumed
	end
	return parsed
end

--------------------------------------------------------------------------------
-- Event decoding
--------------------------------------------------------------------------------

--- Parsed event definition from ABI
export type EventDef = {
	name: string,
	selector: string, -- hex string of sn_keccak(event_name)
	keyMembers: { { name: string, type: string } }, -- members with kind="key"
	dataMembers: { { name: string, type: string } }, -- members with kind="data"
}

--- Decode event keys and data using an event definition.
--- keys[1] is the selector (skipped), keys[2..] are key members, data[1..] are data members.
--- Returns a table of decoded fields keyed by member name.
function AbiCodec.decodeEvent(
	keys: { string },
	data: { string },
	eventDef: EventDef,
	typeMap: TypeMap
): { [string]: any }
	local fields: { [string]: any } = {}

	-- Decode key members from keys[2..] (keys[1] is the selector)
	local keyOffset = 2
	for _, member in eventDef.keyMembers do
		if keyOffset <= #keys then
			local decoded, consumed = AbiCodec.decode(keys, keyOffset, member.type, typeMap)
			fields[member.name] = decoded
			keyOffset += consumed
		end
	end

	-- Decode data members from data[1..]
	local dataOffset = 1
	for _, member in eventDef.dataMembers do
		if dataOffset <= #data then
			local decoded, consumed = AbiCodec.decode(data, dataOffset, member.type, typeMap)
			fields[member.name] = decoded
			dataOffset += consumed
		end
	end

	return fields
end

return AbiCodec
