--!strict
-- TypedData: SNIP-12 typed data hashing for off-chain message signing
-- Implements structured data encoding and hashing per SNIP-12 specification
-- Supports both revision 0 (LEGACY/Pedersen) and revision 1 (ACTIVE/Poseidon)
-- Reference: starknet.js src/utils/typedData.ts

local BigInt = require("../crypto/BigInt")
local StarkField = require("../crypto/StarkField")
local Pedersen = require("../crypto/Pedersen")
local Poseidon = require("../crypto/Poseidon")
local Keccak = require("../crypto/Keccak")

type Felt = StarkField.Felt

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local REVISION_LEGACY = "0"
local REVISION_ACTIVE = "1"

-- Stark prime P for i128 negative handling (raw BigInt, NOT field-reduced)
local STARK_PRIME = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")

-- Preset types (ACTIVE revision only)
local PRESET_TYPES: { [string]: { { name: string, type: string } } } = {
	u256 = { { name = "low", type = "u128" }, { name = "high", type = "u128" } },
	TokenAmount = {
		{ name = "token_address", type = "ContractAddress" },
		{ name = "amount", type = "u256" },
	},
	NftId = {
		{ name = "collection_address", type = "ContractAddress" },
		{ name = "token_id", type = "u256" },
	},
}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Encode a short ASCII string (max 31 chars) as a hex felt value.
local function encodeShortString(str: string): string
	if #str == 0 then
		return "0x0"
	end
	local hexParts = {}
	for i = 1, #str do
		table.insert(hexParts, string.format("%02x", string.byte(str, i)))
	end
	return "0x" .. table.concat(hexParts)
end

--- Normalize a value to a hex string.
--- Handles: hex strings, numbers, short strings (non-hex strings).
local function getHex(value: any): string
	if type(value) == "number" then
		return BigInt.toHex(BigInt.fromNumber(value))
	end
	if type(value) == "boolean" then
		return if value then "0x1" else "0x0"
	end
	if type(value) == "string" then
		local s: string = value :: string
		if string.sub(s, 1, 2) == "0x" or string.sub(s, 1, 2) == "0X" then
			return BigInt.toHex(BigInt.fromHex(s))
		end
		-- Try parsing as a decimal number (starknet.js BigInt("1") → 1n)
		local numVal = tonumber(s)
		if numVal ~= nil then
			return BigInt.toHex(BigInt.fromNumber(numVal))
		end
		-- Treat as short string (ASCII → felt)
		return BigInt.toHex(BigInt.fromHex(encodeShortString(s)))
	end
	error(`TypedData: cannot convert value to hex: {tostring(value)}`)
end

--- Pedersen-based hash method (LEGACY revision).
--- Equivalent to computePedersenHashOnElements: [...data, #data].reduce(pedersen, 0)
local function hashPedersen(data: { string }): string
	local result = StarkField.zero()
	for _, hex in data do
		result = Pedersen.hash(result, StarkField.fromHex(hex))
	end
	result = Pedersen.hash(result, StarkField.fromNumber(#data))
	return StarkField.toHex(result)
end

--- Poseidon-based hash method (ACTIVE revision).
--- Equivalent to computePoseidonHashOnElements: poseidonHashMany(data)
local function hashPoseidon(data: { string }): string
	local felts: { Felt } = {}
	for _, hex in data do
		table.insert(felts, StarkField.fromHex(hex))
	end
	return StarkField.toHex(Poseidon.hashMany(felts))
end

--- Pairwise Pedersen hash (for Merkle tree, LEGACY).
local function hashPairPedersen(a: string, b: string): string
	return StarkField.toHex(Pedersen.hash(StarkField.fromHex(a), StarkField.fromHex(b)))
end

--- Pairwise Poseidon hash (for Merkle tree, ACTIVE).
local function hashPairPoseidon(a: string, b: string): string
	return StarkField.toHex(Poseidon.hash(StarkField.fromHex(a), StarkField.fromHex(b)))
end

--- Get the hash method for a given revision.
local function getHashMethod(revision: string): (data: { string }) -> string
	if revision == REVISION_ACTIVE then
		return hashPoseidon
	end
	return hashPedersen
end

--- Get the merkle hash method for a given revision.
local function getMerkleHashMethod(revision: string): (a: string, b: string) -> string
	if revision == REVISION_ACTIVE then
		return hashPairPoseidon
	end
	return hashPairPedersen
end

--- Escape type string based on revision.
--- ACTIVE: wraps in quotes. LEGACY: identity.
local function escapeTypeString(s: string, revision: string): string
	if revision == REVISION_ACTIVE then
		return `"{s}"`
	end
	return s
end

--- Build a ByteArray encoding of a string (for ACTIVE revision string type).
--- Returns array of hex strings: [numChunks, chunk0..N, pendingWord, pendingLen]
local function encodeByteArray(str: string): { string }
	local CHUNK_SIZE = 31
	local len = #str
	local chunks: { string } = {}

	-- Split into 31-byte chunks
	local i = 1
	while i <= len do
		local chunk = string.sub(str, i, math.min(i + CHUNK_SIZE - 1, len))
		table.insert(chunks, chunk)
		i += CHUNK_SIZE
	end

	-- If the last chunk is exactly 31 bytes, it's a full chunk (no pending)
	local numFullChunks: number
	local pendingWord: string
	local pendingLen: number

	if #chunks == 0 then
		numFullChunks = 0
		pendingWord = "0x0"
		pendingLen = 0
	elseif #chunks[#chunks] == CHUNK_SIZE then
		numFullChunks = #chunks
		pendingWord = "0x0"
		pendingLen = 0
	else
		numFullChunks = #chunks - 1
		local lastChunk = chunks[#chunks]
		pendingLen = #lastChunk
		local hexParts = {}
		for j = 1, #lastChunk do
			table.insert(hexParts, string.format("%02x", string.byte(lastChunk, j)))
		end
		pendingWord = "0x" .. table.concat(hexParts)
		table.remove(chunks)
	end

	local result: { string } = {}
	-- Number of full chunks (as a BigNumberish element for Poseidon)
	table.insert(result, string.format("0x%x", numFullChunks))

	-- Encode each full chunk as a short string hex
	for _, chunk in chunks do
		table.insert(result, encodeShortString(chunk))
	end

	-- Pending word and length
	table.insert(result, pendingWord)
	table.insert(result, string.format("0x%x", pendingLen))

	return result
end

--------------------------------------------------------------------------------
-- Merkle Tree
--------------------------------------------------------------------------------

--- Build a Merkle tree root from leaf hashes.
--- Pairs are sorted (ascending BigInt comparison) before hashing.
--- Odd-length: last unpaired leaf is hashed with 0x0.
local function merkleRoot(leaves: { string }, hashPair: (string, string) -> string): string
	if #leaves == 0 then
		return "0x0"
	end
	if #leaves == 1 then
		return leaves[1]
	end

	local newLeaves: { string } = {}
	for i = 1, #leaves, 2 do
		if i + 1 > #leaves then
			-- Odd: pair with 0x0
			local a = BigInt.fromHex(leaves[i])
			local b = BigInt.fromHex("0x0")
			-- Sort ascending
			if BigInt.cmp(a, b) >= 0 then
				table.insert(newLeaves, hashPair(BigInt.toHex(b), BigInt.toHex(a)))
			else
				table.insert(newLeaves, hashPair(BigInt.toHex(a), BigInt.toHex(b)))
			end
		else
			local a = BigInt.fromHex(leaves[i])
			local b = BigInt.fromHex(leaves[i + 1])
			-- Sort ascending
			if BigInt.cmp(a, b) >= 0 then
				table.insert(newLeaves, hashPair(BigInt.toHex(b), BigInt.toHex(a)))
			else
				table.insert(newLeaves, hashPair(BigInt.toHex(a), BigInt.toHex(b)))
			end
		end
	end

	return merkleRoot(newLeaves, hashPair)
end

--------------------------------------------------------------------------------
-- TypedData module
--------------------------------------------------------------------------------

local TypedData = {}

TypedData.REVISION_LEGACY = REVISION_LEGACY
TypedData.REVISION_ACTIVE = REVISION_ACTIVE

--------------------------------------------------------------------------------
-- Revision detection
--------------------------------------------------------------------------------

--- Identify the SNIP-12 revision from a TypedData object.
--- Returns "0" (LEGACY) or "1" (ACTIVE).
function TypedData.identifyRevision(typedData: { [string]: any }): string
	local types = typedData.types :: { [string]: any }
	local domain = typedData.domain :: { [string]: any }

	-- ACTIVE: types contains "StarknetDomain" and domain.revision is "1" or 1
	if types["StarknetDomain"] then
		local rev = domain.revision
		if rev ~= nil and tostring(rev) == "1" then
			return REVISION_ACTIVE
		end
	end

	-- LEGACY: types contains "StarkNetDomain" and domain.revision is nil or "0"
	if types["StarkNetDomain"] then
		local rev = domain.revision
		if rev == nil or tostring(rev) == "0" then
			return REVISION_LEGACY
		end
	end

	-- Default to LEGACY
	return REVISION_LEGACY
end

--------------------------------------------------------------------------------
-- Type encoding
--------------------------------------------------------------------------------

--- Check if a table contains a value.
local function tableContains(t: { string }, val: string): boolean
	for _, v in t do
		if v == val then
			return true
		end
	end
	return false
end

--- Recursively get all type dependencies.
function TypedData.getDependencies(
	types: { [string]: any },
	typeName: string,
	dependencies: { string }?,
	contains: string?,
	revision: string?
): { string }
	local deps: { string } = dependencies or {}
	local rev = revision or REVISION_LEGACY

	-- Determine the actual dependency types to process
	local dependencyTypes: { string } = { typeName }

	-- Strip array pointer
	if string.sub(typeName, -1) == "*" then
		dependencyTypes = { string.sub(typeName, 1, -2) }
	elseif rev == REVISION_ACTIVE then
		-- enum base
		if typeName == "enum" and contains then
			dependencyTypes = { contains :: string }
		-- enum element types (parenthesized tuple)
		elseif string.match(typeName, "^%(.*%)$") then
			local inner = string.sub(typeName, 2, -2)
			dependencyTypes = {}
			for part in string.gmatch(inner, "[^,]+") do
				if string.sub(part, -1) == "*" then
					table.insert(dependencyTypes, string.sub(part, 1, -2))
				else
					table.insert(dependencyTypes, part)
				end
			end
		end
	end

	-- Filter and recurse
	local result: { string } = {}
	for _, depType in dependencyTypes do
		if not tableContains(deps, depType) and not tableContains(result, depType) and types[depType] then
			table.insert(result, depType)

			-- Recurse on all fields of this type
			local fields = types[depType] :: { any }
			local subDeps: { string } = {}
			for _, v in result do
				table.insert(subDeps, v)
			end

			for _, field in fields do
				local fieldType = (field :: any).type :: string
				local fieldContains = (field :: any).contains :: string?
				local sub = TypedData.getDependencies(types, fieldType, subDeps, fieldContains, rev)
				for _, s in sub do
					if not tableContains(result, s) and not tableContains(subDeps, s) then
						table.insert(result, s)
						table.insert(subDeps, s)
					end
				end
			end
		end
	end

	return result
end

--- Encode a type string for hashing (canonical representation).
function TypedData.encodeType(types: { [string]: any }, typeName: string, revision: string?): string
	local rev = revision or REVISION_LEGACY

	-- Merge preset types for ACTIVE revision
	local allTypes: { [string]: any } = {}
	for k, v in types :: { [string]: any } do
		allTypes[k] = v
	end
	if rev == REVISION_ACTIVE then
		for k, v in PRESET_TYPES do
			if not allTypes[k] then
				allTypes[k] = v
			end
		end
	end

	local allDeps = TypedData.getDependencies(allTypes, typeName, nil, nil, rev)
	if #allDeps == 0 then
		return ""
	end

	-- Primary is first, rest sorted alphabetically
	local primary = allDeps[1]
	local rest: { string } = {}
	for i = 2, #allDeps do
		table.insert(rest, allDeps[i])
	end
	table.sort(rest)

	local newTypes: { string } = { primary }
	for _, r in rest do
		table.insert(newTypes, r)
	end

	local parts: { string } = {}
	for _, dep in newTypes do
		local fields = allTypes[dep] :: { any }
		local fieldStrs: { string } = {}
		for _, field in fields do
			local f = field :: any
			local fieldName: string = f.name
			local fieldType: string = f.type
			local fieldContains: string? = f.contains

			-- For enum fields in ACTIVE revision, use the contains reference
			local targetType = fieldType
			if fieldType == "enum" and rev == REVISION_ACTIVE and fieldContains then
				targetType = fieldContains :: string
			end

			-- Handle parenthesized tuple types
			local typeString: string
			if string.match(targetType, "^%(.*%)$") then
				-- Parse inner elements and escape each individually
				local inner = string.sub(targetType, 2, -2)
				local escapedParts: { string } = {}
				for part in string.gmatch(inner, "[^,]+") do
					table.insert(escapedParts, escapeTypeString(part, rev))
				end
				-- Handle empty tuple "()"
				if inner == "" then
					typeString = "()"
				else
					typeString = "(" .. table.concat(escapedParts, ",") .. ")"
				end
			else
				typeString = escapeTypeString(targetType, rev)
			end

			table.insert(fieldStrs, escapeTypeString(fieldName, rev) .. ":" .. typeString)
		end
		table.insert(parts, escapeTypeString(dep, rev) .. "(" .. table.concat(fieldStrs, ",") .. ")")
	end

	return table.concat(parts)
end

--- Compute the type hash (starknet_keccak of the encoded type string).
function TypedData.getTypeHash(types: { [string]: any }, typeName: string, revision: string?): string
	local encoded = TypedData.encodeType(types, typeName, revision)
	return StarkField.toHex(Keccak.getSelectorFromName(encoded))
end

--------------------------------------------------------------------------------
-- Value encoding
--------------------------------------------------------------------------------

-- Forward declarations for mutual recursion
local encodeValue: (types: { [string]: any }, typeName: string, data: any, ctx: { parent: string?, key: string? }?, revision: string?) -> (string, string)
local encodeData: (types: { [string]: any }, typeName: string, data: any, revision: string?) -> ({ string }, { string })
local getStructHash: (types: { [string]: any }, typeName: string, data: any, revision: string?) -> string

--- Get the Merkle tree leaf type from context.
local function getMerkleTreeType(types: { [string]: any }, ctx: { parent: string?, key: string? }?): string
	if ctx and ctx.parent and ctx.key then
		local parentType = types[ctx.parent :: string] :: { any }
		for _, field in parentType do
			local f = field :: any
			if f.name == ctx.key then
				if f.type ~= "merkletree" then
					error(`{ctx.key} is not a merkle tree`)
				end
				return f.contains :: string
			end
		end
	end
	return "raw"
end

--- Prepare a selector value (convert name to selector hash, or pass through hex).
local function prepareSelector(data: string): string
	if string.sub(data, 1, 2) == "0x" or string.sub(data, 1, 2) == "0X" then
		return BigInt.toHex(BigInt.fromHex(data))
	end
	return StarkField.toHex(Keccak.getSelectorFromName(data))
end

encodeValue = function(types, typeName, data, ctx, revision)
	local rev = revision or REVISION_LEGACY

	-- Custom struct type
	if types[typeName] then
		return typeName, getStructHash(types, typeName, data, rev)
	end

	-- Preset types (ACTIVE only)
	if rev == REVISION_ACTIVE and PRESET_TYPES[typeName] then
		return typeName, getStructHash(PRESET_TYPES :: any, typeName, data, rev)
	end

	-- Array types (ends with *)
	if string.sub(typeName, -1) == "*" then
		local baseType = string.sub(typeName, 1, -2)
		local hashes: { string } = {}
		local arr = data :: { any }
		for _, entry in arr do
			local _, encoded = encodeValue(types, baseType, entry, nil, rev)
			table.insert(hashes, encoded)
		end
		local hashMethod = getHashMethod(rev)
		return typeName, hashMethod(hashes)
	end

	-- Switch on type name
	if typeName == "enum" then
		if rev == REVISION_ACTIVE then
			-- Extract variant key and data from the table
			local variantKey: string = ""
			local variantData: any = nil
			for k, v in data :: { [string]: any } do
				variantKey = k
				variantData = v
				break
			end

			-- Find parent type and enum type
			local parentType = types[(ctx :: any).parent :: string] :: { any }
			local enumContains: string = ""
			for _, field in parentType do
				local f = field :: any
				if f.name == (ctx :: any).key then
					enumContains = f.contains :: string
					break
				end
			end

			local enumType = types[enumContains] :: { any }
			local variantIndex: number = -1
			local variantType: string = ""
			for i, variant in enumType do
				local v = variant :: any
				if v.name == variantKey then
					variantIndex = i - 1 -- 0-indexed
					variantType = v.type :: string
					break
				end
			end

			-- Encode sub-values from the variant's tuple type
			local elements: { string } = { string.format("0x%x", variantIndex) }

			-- Parse tuple type "(type1,type2,...)" or "()"
			local inner = string.sub(variantType, 2, -2)
			if inner ~= "" then
				local subtypes: { string } = {}
				for part in string.gmatch(inner, "[^,]+") do
					table.insert(subtypes, part)
				end

				local variantDataArr = variantData :: { any }
				for idx, subtype in subtypes do
					local _, encoded = encodeValue(types, subtype, variantDataArr[idx], nil, rev)
					table.insert(elements, encoded)
				end
			else
				-- Empty tuple "()" — starknet.js includes an empty string element
				-- which converts to 0 via BigInt("") → 0n
				table.insert(elements, "0x0")
			end

			local hashMethod = getHashMethod(rev)
			return typeName, hashMethod(elements)
		end
		-- LEGACY: just convert to hex
		return typeName, getHex(data)
	end

	if typeName == "merkletree" then
		local merkleType = getMerkleTreeType(types, ctx)
		local structHashes: { string } = {}
		local arr = data :: { any }
		for _, item in arr do
			local _, encoded = encodeValue(types, merkleType, item, nil, rev)
			table.insert(structHashes, encoded)
		end
		local hashPair = getMerkleHashMethod(rev)
		local root = merkleRoot(structHashes, hashPair)
		return "felt", root
	end

	if typeName == "selector" then
		return "felt", prepareSelector(data :: string)
	end

	if typeName == "string" then
		if rev == REVISION_ACTIVE then
			-- ByteArray encoding
			local elements = encodeByteArray(data :: string)
			local hashMethod = getHashMethod(rev)
			return typeName, hashMethod(elements)
		end
		return typeName, getHex(data)
	end

	if typeName == "i128" then
		if rev == REVISION_ACTIVE then
			local value: number
			if type(data) == "number" then
				value = data :: number
			else
				-- Parse string to number
				local s = data :: string
				if string.sub(s, 1, 2) == "0x" or string.sub(s, 1, 2) == "0X" then
					value = tonumber(s, 16) :: number
				else
					value = tonumber(s) :: number
				end
			end
			if value < 0 then
				-- Two's complement in field: P + value
				local bigVal = BigInt.fromNumber(-value)
				local result = BigInt.sub(STARK_PRIME, bigVal)
				return typeName, BigInt.toHex(result)
			end
			return typeName, getHex(data)
		end
		return typeName, getHex(data)
	end

	if typeName == "timestamp" or typeName == "u128" then
		return typeName, getHex(data)
	end

	if typeName == "felt" or typeName == "shortstring" then
		return typeName, getHex(data)
	end

	if typeName == "ClassHash" or typeName == "ContractAddress" then
		return typeName, getHex(data)
	end

	if typeName == "bool" then
		return typeName, getHex(data)
	end

	-- Default: try to convert to hex (LEGACY allows unknown types)
	if rev == REVISION_ACTIVE then
		error(`TypedData: unsupported type: {typeName}`)
	end
	return typeName, getHex(data)
end

--- Encode all data fields for a type.
encodeData = function(types, typeName, data, revision)
	local rev = revision or REVISION_LEGACY
	local targetType = types[typeName]
	if not targetType and rev == REVISION_ACTIVE then
		targetType = PRESET_TYPES[typeName]
	end

	local returnTypes: { string } = { "felt" }
	local values: { string } = { TypedData.getTypeHash(types, typeName, rev) }

	local fields = targetType :: { any }
	for _, field in fields do
		local f = field :: any
		local fieldName: string = f.name
		local fieldType: string = f.type
		local fieldData = (data :: any)[fieldName]

		local ctx = { parent = typeName, key = fieldName }
		local t, encoded = encodeValue(types, fieldType, fieldData, ctx, rev)
		table.insert(returnTypes, t)
		table.insert(values, encoded)
	end

	return returnTypes, values
end

--- Get the struct hash (hash of encoded data).
getStructHash = function(types, typeName, data, revision)
	local rev = revision or REVISION_LEGACY
	local _, values = encodeData(types, typeName, data, rev)
	local hashMethod = getHashMethod(rev)
	return hashMethod(values)
end

-- Export the functions
TypedData.encodeValue = encodeValue
TypedData.encodeData = encodeData
TypedData.getStructHash = getStructHash

--------------------------------------------------------------------------------
-- Message hash (main entry point)
--------------------------------------------------------------------------------

--- Compute the SNIP-12 message hash for signing.
--- This is the hash that should be signed with ECDSA.
function TypedData.getMessageHash(typedData: { [string]: any }, accountAddress: string): string
	local revision = TypedData.identifyRevision(typedData)
	local domainType = if revision == REVISION_ACTIVE then "StarknetDomain" else "StarkNetDomain"
	local hashMethod = getHashMethod(revision)

	local prefix = encodeShortString("StarkNet Message")
	local domainHash = getStructHash(typedData.types :: any, domainType, typedData.domain, revision)
	local accountHex = BigInt.toHex(BigInt.fromHex(accountAddress))
	local messageHash =
		getStructHash(typedData.types :: any, typedData.primaryType :: string, typedData.message, revision)

	return hashMethod({ prefix, domainHash, accountHex, messageHash })
end

--------------------------------------------------------------------------------
-- Merkle tree (exposed for testing)
--------------------------------------------------------------------------------

TypedData.merkleRoot = merkleRoot

return TypedData
