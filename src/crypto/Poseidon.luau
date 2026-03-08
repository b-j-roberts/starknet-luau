--!strict
--!native
--!optimize 2
-- Poseidon: Hash function over the Stark field using the Hades permutation strategy
-- State width=3, rate=2, capacity=1, S-box=x^3
-- Round structure: 4 full + 83 partial + 4 full = 91 total rounds
-- MDS matrix: [[3, 1, 1], [1, -1, 1], [1, 1, -2]]
-- Reference: https://github.com/starkware-industries/poseidon (poseidon3.txt)

local StarkField = require("./StarkField")
local RC_HEX = require("./PoseidonConstants")

type Felt = StarkField.Felt

local Poseidon = {}

-- Round parameters
local HALF_FULL = 4
local ROUNDS_PARTIAL = 83
local TOTAL_ROUNDS = 91

-- Round constants (lazily initialized on first use to avoid 273 StarkField.fromHex() calls at require time)
local RC: { { buffer } }? = nil

local function ensureConstants(): { { buffer } }
	if RC == nil then
		local parsed: { { buffer } } = {}
		for i = 1, TOTAL_ROUNDS do
			local row: { buffer } = {}
			for j = 1, 3 do
				row[j] = StarkField.fromHex(RC_HEX[i][j])
			end
			parsed[i] = row
		end
		RC = parsed
	end
	return RC :: { { buffer } }
end

--------------------------------------------------------------------------------
-- MDS matrix multiplication (inlined for [[3,1,1],[1,-1,1],[1,1,-2]])
-- s0' = 3*s0 + s1 + s2
-- s1' = s0 - s1 + s2
-- s2' = s0 + s1 - 2*s2
--------------------------------------------------------------------------------

local function mdsMultiply(s0: buffer, s1: buffer, s2: buffer): (buffer, buffer, buffer)
	local s0_plus_s1 = StarkField.add(s0, s1)
	local s0_plus_s2 = StarkField.add(s0, s2)
	-- s0' = (s0 + s1) + (s0 + s2) + s0 = 3*s0 + s1 + s2
	local new_s0 = StarkField.add(s0_plus_s1, s0_plus_s2)
	new_s0 = StarkField.add(new_s0, s0)
	-- s1' = (s0 + s2) - s1
	local new_s1 = StarkField.sub(s0_plus_s2, s1)
	-- s2' = (s0 + s1) - 2*s2
	local new_s2 = StarkField.sub(s0_plus_s1, StarkField.add(s2, s2))
	return new_s0, new_s1, new_s2
end

--------------------------------------------------------------------------------
-- S-box: x^3 (cube) using StarkField.square + mul
--------------------------------------------------------------------------------

local function sbox(x: buffer): buffer
	return StarkField.mul(StarkField.square(x), x)
end

--------------------------------------------------------------------------------
-- Hades permutation: state = [s0, s1, s2]
-- 4 full rounds + 83 partial rounds + 4 full rounds = 91 total
-- In partial rounds, only s2 gets the S-box (reversePartialPowIdx)
--------------------------------------------------------------------------------

local function permute(s0: buffer, s1: buffer, s2: buffer): (buffer, buffer, buffer)
	local rc = ensureConstants()
	local round = 1

	-- First 4 full rounds
	for _ = 1, HALF_FULL do
		-- Add round constants
		s0 = StarkField.add(s0, rc[round][1])
		s1 = StarkField.add(s1, rc[round][2])
		s2 = StarkField.add(s2, rc[round][3])
		-- S-box on all elements
		s0 = sbox(s0)
		s1 = sbox(s1)
		s2 = sbox(s2)
		-- MDS
		s0, s1, s2 = mdsMultiply(s0, s1, s2)
		round += 1
	end

	-- 83 partial rounds (S-box only on s2)
	for _ = 1, ROUNDS_PARTIAL do
		-- Add round constants
		s0 = StarkField.add(s0, rc[round][1])
		s1 = StarkField.add(s1, rc[round][2])
		s2 = StarkField.add(s2, rc[round][3])
		-- S-box only on last element
		s2 = sbox(s2)
		-- MDS
		s0, s1, s2 = mdsMultiply(s0, s1, s2)
		round += 1
	end

	-- Last 4 full rounds
	for _ = 1, HALF_FULL do
		-- Add round constants
		s0 = StarkField.add(s0, rc[round][1])
		s1 = StarkField.add(s1, rc[round][2])
		s2 = StarkField.add(s2, rc[round][3])
		-- S-box on all elements
		s0 = sbox(s0)
		s1 = sbox(s1)
		s2 = sbox(s2)
		-- MDS
		s0, s1, s2 = mdsMultiply(s0, s1, s2)
		round += 1
	end

	return s0, s1, s2
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- hash(a, b): Poseidon hash of two field elements
-- Initial state: [a, b, 2], return state[0] after permutation
function Poseidon.hash(a: Felt, b: Felt): Felt
	local s0, _, _ = permute(a, b, StarkField.fromNumber(2))
	return s0
end

-- hashSingle(x): Poseidon hash of a single field element
-- Initial state: [x, 0, 1], return state[0] after permutation
function Poseidon.hashSingle(x: Felt): Felt
	local s0, _, _ = permute(x, StarkField.zero(), StarkField.one())
	return s0
end

-- hashMany(values): Poseidon hash of variable-length input via sponge construction
-- Pads with [1, 0, 0, ...] to multiple of rate (2), then absorbs in chunks of 2
function Poseidon.hashMany(values: { Felt }): Felt
	-- Pad: append 1, then zeros until length is multiple of 2 (rate)
	local padded: { Felt } = {}
	for _, v in values do
		table.insert(padded, v)
	end
	table.insert(padded, StarkField.one())
	while #padded % 2 ~= 0 do
		table.insert(padded, StarkField.zero())
	end

	-- Initialize state
	local s0 = StarkField.zero()
	local s1 = StarkField.zero()
	local s2 = StarkField.zero()

	-- Absorb: add rate elements to state[0] and state[1], then permute
	for i = 1, #padded, 2 do
		s0 = StarkField.add(s0, padded[i])
		s1 = StarkField.add(s1, padded[i + 1])
		s0, s1, s2 = permute(s0, s1, s2)
	end

	return s0
end

return Poseidon
