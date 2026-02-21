--!strict
-- TransactionHash: V3 INVOKE transaction hash computation using Poseidon
-- Follows the Starknet transaction hash specification (SNIP-8)
-- Reference: starknet.js hash/transactionHash/v3.ts

local BigInt = require("../crypto/BigInt")
local StarkField = require("../crypto/StarkField")
local Poseidon = require("../crypto/Poseidon")

type Felt = StarkField.Felt

local TransactionHash = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type ResourceBound = {
	maxAmount: string, -- hex string (max 64 bits)
	maxPricePerUnit: string, -- hex string (max 128 bits)
}

export type ResourceBounds = {
	l1Gas: ResourceBound,
	l2Gas: ResourceBound,
	l1DataGas: ResourceBound,
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Transaction hash prefix: ASCII encoding of "invoke"
local INVOKE_PREFIX = StarkField.fromHex("0x696e766f6b65")

-- Default V3 transaction version
local V3_VERSION = StarkField.fromHex("0x3")

-- Resource name ASCII encodings
local L1_GAS_NAME = BigInt.fromHex("0x4c315f474153") -- "L1_GAS"
local L2_GAS_NAME = BigInt.fromHex("0x4c325f474153") -- "L2_GAS"
local L1_DATA_NAME = BigInt.fromHex("0x4c315f44415441") -- "L1_DATA"

-- Chain ID constants
TransactionHash.SN_MAIN = "0x534e5f4d41494e"
TransactionHash.SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Encode a single resource bound as Felt: (name << 192) | (max_amount << 128) | max_price_per_unit
local function encodeResourceBoundInternal(resourceName: buffer, maxAmount: string, maxPricePerUnit: string): Felt
	local namePart = BigInt.shl(resourceName, 192)
	local amountPart = BigInt.shl(BigInt.fromHex(maxAmount), 128)
	local pricePart = BigInt.fromHex(maxPricePerUnit)
	return BigInt.bor(BigInt.bor(namePart, amountPart), pricePart)
end

-- Convert array of hex strings to Felt array for Poseidon hashing
local function hexArrayToFelts(hexArray: { string }): { Felt }
	local felts: { Felt } = {}
	for _, hex in hexArray do
		table.insert(felts, StarkField.fromHex(hex))
	end
	return felts
end

-- Encode DA mode as Felt: (nonce_da_mode << 32) | fee_da_mode
local function encodeDAModeInternal(nonceDAMode: number, feeDAMode: number): Felt
	local noncePart = BigInt.shl(BigInt.fromNumber(nonceDAMode), 32)
	return BigInt.bor(noncePart, BigInt.fromNumber(feeDAMode))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Encode a single resource bound: (resource_name << 192) | (max_amount << 128) | max_price_per_unit
-- resourceName: hex-encoded ASCII name (e.g., "0x4c315f474153" for "L1_GAS")
function TransactionHash.encodeResourceBound(resourceName: string, maxAmount: string, maxPricePerUnit: string): string
	local nameBig = BigInt.fromHex(resourceName)
	return BigInt.toHex(encodeResourceBoundInternal(nameBig, maxAmount, maxPricePerUnit))
end

-- Hash fee field: poseidonHashMany([tip, l1_bound, l2_bound, l1_data_bound])
function TransactionHash.hashFeeField(tip: string, resourceBounds: ResourceBounds): string
	local tipFelt = StarkField.fromHex(tip)
	local l1Bound =
		encodeResourceBoundInternal(L1_GAS_NAME, resourceBounds.l1Gas.maxAmount, resourceBounds.l1Gas.maxPricePerUnit)
	local l2Bound =
		encodeResourceBoundInternal(L2_GAS_NAME, resourceBounds.l2Gas.maxAmount, resourceBounds.l2Gas.maxPricePerUnit)
	local l1DataBound = encodeResourceBoundInternal(
		L1_DATA_NAME,
		resourceBounds.l1DataGas.maxAmount,
		resourceBounds.l1DataGas.maxPricePerUnit
	)
	return StarkField.toHex(Poseidon.hashMany({ tipFelt, l1Bound, l2Bound, l1DataBound }))
end

-- Encode DA mode: (nonce_da_mode << 32) | fee_da_mode
function TransactionHash.hashDAMode(nonceDAMode: number, feeDAMode: number): string
	return BigInt.toHex(encodeDAModeInternal(nonceDAMode, feeDAMode))
end

-- Calculate V3 INVOKE transaction hash
-- Returns hex string of the Poseidon hash
function TransactionHash.calculateInvokeTransactionHash(params: {
	senderAddress: string,
	compiledCalldata: { string },
	chainId: string,
	nonce: string,
	resourceBounds: ResourceBounds,
	version: string?,
	tip: string?,
	paymasterData: { string }?,
	accountDeploymentData: { string }?,
	nonceDataAvailabilityMode: number?,
	feeDataAvailabilityMode: number?,
}): string
	local versionFelt = if params.version then StarkField.fromHex(params.version) else V3_VERSION
	local tip = params.tip or "0x0"
	local paymasterData = params.paymasterData or {}
	local accountDeploymentData = params.accountDeploymentData or {}
	local nonceDAMode = params.nonceDataAvailabilityMode or 0
	local feeDAMode = params.feeDataAvailabilityMode or 0

	-- Compute fee field hash: poseidonHashMany([tip, l1_bound, l2_bound, l1_data_bound])
	local tipFelt = StarkField.fromHex(tip)
	local l1Bound = encodeResourceBoundInternal(
		L1_GAS_NAME,
		params.resourceBounds.l1Gas.maxAmount,
		params.resourceBounds.l1Gas.maxPricePerUnit
	)
	local l2Bound = encodeResourceBoundInternal(
		L2_GAS_NAME,
		params.resourceBounds.l2Gas.maxAmount,
		params.resourceBounds.l2Gas.maxPricePerUnit
	)
	local l1DataBound = encodeResourceBoundInternal(
		L1_DATA_NAME,
		params.resourceBounds.l1DataGas.maxAmount,
		params.resourceBounds.l1DataGas.maxPricePerUnit
	)
	local feeFieldHash = Poseidon.hashMany({ tipFelt, l1Bound, l2Bound, l1DataBound })

	-- Hash paymaster data and account deployment data
	local paymasterHash = Poseidon.hashMany(hexArrayToFelts(paymasterData))
	local accountDeployHash = Poseidon.hashMany(hexArrayToFelts(accountDeploymentData))

	-- Hash compiled calldata
	local calldataHash = Poseidon.hashMany(hexArrayToFelts(params.compiledCalldata))

	-- Encode DA mode: (nonce_da_mode << 32) | fee_da_mode
	local daMode = encodeDAModeInternal(nonceDAMode, feeDAMode)

	-- poseidonHashMany([prefix, version, sender, fee_hash, paymaster_hash, chain_id, nonce, da_mode, deploy_data_hash, calldata_hash])
	local dataToHash: { Felt } = {
		INVOKE_PREFIX,
		versionFelt,
		StarkField.fromHex(params.senderAddress),
		feeFieldHash,
		paymasterHash,
		StarkField.fromHex(params.chainId),
		StarkField.fromHex(params.nonce),
		daMode,
		accountDeployHash,
		calldataHash,
	}

	return StarkField.toHex(Poseidon.hashMany(dataToHash))
end

return TransactionHash
