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

--- Resource bound for a single gas type (used in hash computation).
--- NOTE: This uses camelCase field names and includes 3 gas types (l1Gas, l2Gas, l1DataGas)
--- because the Poseidon hash computation (SNIP-8) requires all three bounds.
--- This differs from RpcTypes.ResourceBounds which uses snake_case (l1_gas, l2_gas) and
--- only 2 fields, because the Starknet JSON-RPC wire format does not include l1_data_gas
--- in the submitted resource_bounds object. See TransactionBuilder.toRpcResourceBounds()
--- which maps from this type to the wire format, intentionally omitting l1DataGas.
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

-- Transaction hash prefix: ASCII encoding of "deploy_account"
local DEPLOY_ACCOUNT_PREFIX = StarkField.fromHex("0x6465706c6f795f6163636f756e74")

-- Default V3 transaction version
local V3_VERSION = StarkField.fromHex("0x3")

-- Resource name ASCII encodings
local L1_GAS_NAME = BigInt.fromHex("0x4c315f474153") -- "L1_GAS"
local L2_GAS_NAME = BigInt.fromHex("0x4c325f474153") -- "L2_GAS"
local L1_DATA_NAME = BigInt.fromHex("0x4c315f44415441") -- "L1_DATA"

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

-- Internal: compute fee field hash as Felt (shared by hashFeeField and calculate*TransactionHash)
local function computeFeeFieldHash(tip: string, resourceBounds: ResourceBounds): Felt
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
	return Poseidon.hashMany({ tipFelt, l1Bound, l2Bound, l1DataBound })
end

-- Internal: extract common defaults and compute shared fields for V3 transaction hashes
local function prepareCommonFields(
	params: {
		version: string?,
		tip: string?,
		paymasterData: { string }?,
		nonceDataAvailabilityMode: number?,
		feeDataAvailabilityMode: number?,
		resourceBounds: ResourceBounds,
	}
): { feeFieldHash: Felt, paymasterHash: Felt, daMode: Felt, versionFelt: Felt }
	local tip = params.tip or "0x0"
	local paymasterData = params.paymasterData or {}
	local nonceDAMode = params.nonceDataAvailabilityMode or 0
	local feeDAMode = params.feeDataAvailabilityMode or 0

	return {
		feeFieldHash = computeFeeFieldHash(tip, params.resourceBounds),
		paymasterHash = Poseidon.hashMany(hexArrayToFelts(paymasterData)),
		daMode = encodeDAModeInternal(nonceDAMode, feeDAMode),
		versionFelt = if params.version then StarkField.fromHex(params.version) else V3_VERSION,
	}
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Internal: Encode a single resource bound: (resource_name << 192) | (max_amount << 128) | max_price_per_unit
-- resourceName: hex-encoded ASCII name (e.g., "0x4c315f474153" for "L1_GAS")
-- Prefixed with _ to signal this is not part of the public API.
function TransactionHash._encodeResourceBound(resourceName: string, maxAmount: string, maxPricePerUnit: string): string
	local nameBig = BigInt.fromHex(resourceName)
	return BigInt.toHex(encodeResourceBoundInternal(nameBig, maxAmount, maxPricePerUnit))
end

-- Hash fee field: poseidonHashMany([tip, l1_bound, l2_bound, l1_data_bound])
function TransactionHash.hashFeeField(tip: string, resourceBounds: ResourceBounds): string
	return StarkField.toHex(computeFeeFieldHash(tip, resourceBounds))
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
	local common = prepareCommonFields(params)
	local accountDeploymentData = params.accountDeploymentData or {}
	local accountDeployHash = Poseidon.hashMany(hexArrayToFelts(accountDeploymentData))
	local calldataHash = Poseidon.hashMany(hexArrayToFelts(params.compiledCalldata))

	return StarkField.toHex(Poseidon.hashMany({
		INVOKE_PREFIX,
		common.versionFelt,
		StarkField.fromHex(params.senderAddress),
		common.feeFieldHash,
		common.paymasterHash,
		StarkField.fromHex(params.chainId),
		StarkField.fromHex(params.nonce),
		common.daMode,
		accountDeployHash,
		calldataHash,
	}))
end

-- Calculate V3 DEPLOY_ACCOUNT transaction hash
-- Returns hex string of the Poseidon hash
-- Follows SNIP-8: poseidon("deploy_account", version, contract_address,
--   fee_hash, paymaster_hash, chain_id, nonce, da_mode,
--   constructor_calldata_hash, class_hash, contract_address_salt)
function TransactionHash.calculateDeployAccountTransactionHash(params: {
	classHash: string,
	constructorCalldata: { string },
	contractAddress: string,
	salt: string,
	chainId: string,
	nonce: string,
	resourceBounds: ResourceBounds,
	version: string?,
	tip: string?,
	paymasterData: { string }?,
	nonceDataAvailabilityMode: number?,
	feeDataAvailabilityMode: number?,
}): string
	local common = prepareCommonFields(params)
	local constructorCalldataHash = Poseidon.hashMany(hexArrayToFelts(params.constructorCalldata))

	return StarkField.toHex(Poseidon.hashMany({
		DEPLOY_ACCOUNT_PREFIX,
		common.versionFelt,
		StarkField.fromHex(params.contractAddress),
		common.feeFieldHash,
		common.paymasterHash,
		StarkField.fromHex(params.chainId),
		StarkField.fromHex(params.nonce),
		common.daMode,
		constructorCalldataHash,
		StarkField.fromHex(params.classHash),
		StarkField.fromHex(params.salt),
	}))
end

return TransactionHash
