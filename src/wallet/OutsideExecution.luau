--!strict
-- OutsideExecution: SNIP-9 Outside Execution support for meta-transactions
-- Enables third parties (e.g., paymasters) to submit execute_from_outside on a user's account
-- Supports V1 (SNIP-9 rev 0/Pedersen), V2 (rev 1/Poseidon), and V3-RC (with fee modes)
-- Reference: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-9.md

local Keccak = require("../crypto/Keccak")
local StarkField = require("../crypto/StarkField")
local HexUtils = require("../shared/HexUtils")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes
local Constants = require("../constants")

type Felt = StarkField.Felt

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local OutsideExecution = {}

-- Version constants
OutsideExecution.VERSION_V1 = "1"
OutsideExecution.VERSION_V2 = "2"
OutsideExecution.VERSION_V3_RC = "3"

-- Entrypoint names
OutsideExecution.ENTRYPOINT_V1 = "execute_from_outside"
OutsideExecution.ENTRYPOINT_V2 = "execute_from_outside_v2"
OutsideExecution.ENTRYPOINT_V3 = "execute_from_outside_v3"

-- Re-export ANY_CALLER for convenience
OutsideExecution.ANY_CALLER = Constants.ANY_CALLER

-- SNIP-9 Interface IDs
OutsideExecution.INTERFACE_ID_V1 = "0x68cfd18b92d1907b8ba3cc324900277f5a3622099431ea85dd8089255e4181"
OutsideExecution.INTERFACE_ID_V2 = "0x1d1144bb2138366ff28d8e9ab57456b1d332ac42196230c3a602003c89872"

--------------------------------------------------------------------------------
-- V1 Types (LEGACY / Pedersen / StarkNetDomain)
--------------------------------------------------------------------------------

local TYPES_V1 = {
	StarkNetDomain = {
		{ name = "name", type = "felt" },
		{ name = "version", type = "felt" },
		{ name = "chainId", type = "felt" },
	},
	OutsideExecution = {
		{ name = "caller", type = "felt" },
		{ name = "nonce", type = "felt" },
		{ name = "execute_after", type = "felt" },
		{ name = "execute_before", type = "felt" },
		{ name = "calls_len", type = "felt" },
		{ name = "calls", type = "OutsideCall*" },
	},
	OutsideCall = {
		{ name = "to", type = "felt" },
		{ name = "selector", type = "felt" },
		{ name = "calldata_len", type = "felt" },
		{ name = "calldata", type = "felt*" },
	},
}

--------------------------------------------------------------------------------
-- V2 Types (ACTIVE / Poseidon / StarknetDomain)
--------------------------------------------------------------------------------

local TYPES_V2 = {
	StarknetDomain = {
		{ name = "name", type = "shortstring" },
		{ name = "version", type = "shortstring" },
		{ name = "chainId", type = "shortstring" },
		{ name = "revision", type = "shortstring" },
	},
	OutsideExecution = {
		{ name = "Caller", type = "ContractAddress" },
		{ name = "Nonce", type = "felt" },
		{ name = "Execute After", type = "u128" },
		{ name = "Execute Before", type = "u128" },
		{ name = "Calls", type = "Call*" },
	},
	Call = {
		{ name = "To", type = "ContractAddress" },
		{ name = "Selector", type = "selector" },
		{ name = "Calldata", type = "felt*" },
	},
}

--------------------------------------------------------------------------------
-- V3-RC Types (ACTIVE / Poseidon / StarknetDomain + Fee Mode enum)
--------------------------------------------------------------------------------

local TYPES_V3 = {
	StarknetDomain = {
		{ name = "name", type = "shortstring" },
		{ name = "version", type = "shortstring" },
		{ name = "chainId", type = "shortstring" },
		{ name = "revision", type = "shortstring" },
	},
	OutsideExecution = {
		{ name = "Caller", type = "ContractAddress" },
		{ name = "Nonce", type = "felt" },
		{ name = "Execute After", type = "u128" },
		{ name = "Execute Before", type = "u128" },
		{ name = "Calls", type = "Call*" },
		{ name = "Fee", type = "enum", contains = "Fee Mode" },
	},
	Call = {
		{ name = "To", type = "ContractAddress" },
		{ name = "Selector", type = "selector" },
		{ name = "Calldata", type = "felt*" },
	},
	["Fee Mode"] = {
		{ name = "No Fee", type = "()" },
		{ name = "Pay Fee", type = "(FeeTransfer)" },
	},
	FeeTransfer = {
		{ name = "Fee Amount", type = "TokenAmount" },
		{ name = "Fee Receiver", type = "ContractAddress" },
	},
}

-- Expose type tables for testing and external use
OutsideExecution.TYPES_V1 = TYPES_V1
OutsideExecution.TYPES_V2 = TYPES_V2
OutsideExecution.TYPES_V3 = TYPES_V3

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

local normalizeHex = HexUtils.normalizeHex

--- Convert outside calls to the Capitalized key format used by V2/V3 TypedData.
local function toTypedDataCalls(outsideCalls: { { [string]: any } }): { { [string]: any } }
	local result: { { [string]: any } } = {}
	for _, oc in outsideCalls do
		table.insert(result, {
			To = oc.to,
			Selector = oc.selector,
			Calldata = oc.calldata,
		})
	end
	return result
end

--- Encode a number-or-string value as a hex felt string for calldata.
--- Handles Lua numbers, hex strings (0x-prefixed), and decimal number strings.
local function toHexFelt(value: any): string
	if type(value) == "number" then
		return string.format("0x%x", value)
	end
	local str = tostring(value)
	if string.sub(str, 1, 2) == "0x" or string.sub(str, 1, 2) == "0X" then
		return normalizeHex(str)
	end
	-- Decimal number string: convert to hex via tonumber
	local num = tonumber(str)
	if num then
		return string.format("0x%x", num)
	end
	return str
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Get the entrypoint name for a given SNIP-9 version.
function OutsideExecution.getEntrypoint(version: string): string
	if version == "1" then
		return OutsideExecution.ENTRYPOINT_V1
	elseif version == "2" then
		return OutsideExecution.ENTRYPOINT_V2
	elseif version == "3" then
		return OutsideExecution.ENTRYPOINT_V3
	end
	error(StarknetError.validation(`Invalid outside execution version: {version}`, ErrorCodes.INVALID_VERSION.code))
end

--- Convert a Call (with named entrypoint) to an OutsideCall (with selector hash).
--- If the entrypoint already starts with 0x, it is used as-is (normalized).
--- Otherwise, the selector is computed via starknet_keccak.
function OutsideExecution.getOutsideCall(call: { [string]: any }): { [string]: any }
	local entrypoint = call.entrypoint :: string
	local selector: string

	if string.sub(entrypoint, 1, 2) == "0x" or string.sub(entrypoint, 1, 2) == "0X" then
		selector = normalizeHex(entrypoint)
	else
		selector = StarkField.toHex(Keccak.getSelectorFromName(entrypoint))
	end

	return {
		to = call.contractAddress,
		selector = selector,
		calldata = call.calldata or {},
	}
end

export type GetTypedDataConfig = {
	chainId: string,
	caller: string,
	execute_after: number | string,
	execute_before: number | string,
	nonce: number | string,
	calls: { { [string]: any } },
	version: string,
	feeMode: { [string]: any }?,
}

--- Build SNIP-12 TypedData for outside execution signing.
--- The returned TypedData object can be passed directly to Account:signMessage().
function OutsideExecution.getTypedData(config: GetTypedDataConfig): { [string]: any }
	local chainId = config.chainId
	local version = config.version
	local nonce = config.nonce
	local calls = config.calls
	local feeMode = config.feeMode
	if version ~= "1" and version ~= "2" and version ~= "3" then
		error(StarknetError.validation(`Invalid outside execution version: {version}`, ErrorCodes.INVALID_VERSION.code))
	end

	if #calls == 0 then
		error(
			StarknetError.validation(
				"Outside execution requires at least one call",
				ErrorCodes.CALL_VALIDATION_FAILED.code
			)
		)
	end

	local executeAfter = config.execute_after
	local executeBefore = config.execute_before
	if type(executeAfter) == "number" and type(executeBefore) == "number" then
		if (executeAfter :: number) >= (executeBefore :: number) then
			error(
				StarknetError.validation(
					"execute_after must be less than execute_before",
					ErrorCodes.INVALID_TIME_BOUNDS.code
				)
			)
		end
	end

	-- Convert calls to outside calls
	local outsideCalls: { { [string]: any } } = {}
	for _, call in calls do
		table.insert(outsideCalls, OutsideExecution.getOutsideCall(call))
	end

	-- V1: LEGACY revision (Pedersen, StarkNetDomain)
	if version == "1" then
		local v1Calls: { { [string]: any } } = {}
		for _, oc in outsideCalls do
			local cd = oc.calldata :: { string }
			table.insert(v1Calls, {
				to = oc.to,
				selector = oc.selector,
				calldata_len = #cd,
				calldata = cd,
			})
		end

		return {
			types = TYPES_V1,
			primaryType = "OutsideExecution",
			domain = {
				name = "Account.execute_from_outside",
				version = "1",
				chainId = chainId,
			},
			message = {
				caller = config.caller,
				nonce = nonce,
				execute_after = executeAfter,
				execute_before = executeBefore,
				calls_len = #outsideCalls,
				calls = v1Calls,
			},
		}
	end

	-- V2/V3 share the same call conversion (Capitalized keys)
	local typedDataCalls = toTypedDataCalls(outsideCalls)

	-- V2: ACTIVE revision (Poseidon, StarknetDomain)
	if version == "2" then
		return {
			types = TYPES_V2,
			primaryType = "OutsideExecution",
			domain = {
				name = "Account.execute_from_outside",
				version = "2",
				chainId = chainId,
				revision = "1",
			},
			message = {
				Caller = config.caller,
				Nonce = nonce,
				["Execute After"] = executeAfter,
				["Execute Before"] = executeBefore,
				Calls = typedDataCalls,
			},
		}
	end

	-- V3-RC: ACTIVE revision + Fee Mode enum
	if not feeMode then
		error(
			StarknetError.validation(
				"feeMode is required for V3-RC outside execution",
				ErrorCodes.MISSING_FEE_MODE.code
			)
		)
	end

	-- Build Fee field value based on feeMode
	local feeValue: { [string]: any }
	if (feeMode :: any).noFee then
		feeValue = { ["No Fee"] = {} }
	elseif (feeMode :: any).payFee then
		local pf = (feeMode :: any).payFee :: { [string]: any }
		feeValue = {
			["Pay Fee"] = {
				{
					["Fee Amount"] = {
						token_address = pf.tokenAddress,
						amount = pf.amount,
					},
					["Fee Receiver"] = pf.receiver,
				},
			},
		}
	else
		error(StarknetError.validation("feeMode must specify noFee or payFee", ErrorCodes.MISSING_FEE_MODE.code))
	end

	return {
		types = TYPES_V3,
		primaryType = "OutsideExecution",
		domain = {
			name = "Account.execute_from_outside",
			version = "3",
			chainId = chainId,
			revision = "1",
		},
		message = {
			Caller = config.caller,
			Nonce = nonce,
			["Execute After"] = executeAfter,
			["Execute Before"] = executeBefore,
			Calls = typedDataCalls,
			Fee = feeValue,
		},
	}
end

--- Normalize a call's hex fields once, returning a canonical representation.
local function normalizeCall(call: { [string]: any }): { to: string, selector: string, calldata: { string } }
	local cd = (call.calldata or {}) :: { string }
	local normalizedCd: { string } = table.create(#cd)
	for i, felt in cd do
		normalizedCd[i] = normalizeHex(felt)
	end
	return {
		to = normalizeHex(call.to or call.contractAddress),
		selector = normalizeHex(call.selector),
		calldata = normalizedCd,
	}
end

--- Validate that returned calls match submitted calls.
--- Returns true if:
--- 1. All calls match exactly (hex-normalized comparison), OR
--- 2. Returned calls match submitted calls plus one appended transfer call (fee payment).
function OutsideExecution.validateCalls(
	submittedCalls: { { [string]: any } },
	returnedCalls: { { [string]: any } }
): boolean
	-- Pre-normalize all calls once upfront
	local normSubmitted: { { to: string, selector: string, calldata: { string } } } = table.create(#submittedCalls)
	for i, call in submittedCalls do
		normSubmitted[i] = normalizeCall(call)
	end
	local normReturned: { { to: string, selector: string, calldata: { string } } } = table.create(#returnedCalls)
	for i, call in returnedCalls do
		normReturned[i] = normalizeCall(call)
	end

	local function callsMatch(
		a: { { to: string, selector: string, calldata: { string } } },
		aLen: number,
		b: { { to: string, selector: string, calldata: { string } } },
		bLen: number
	): boolean
		if aLen ~= bLen then
			return false
		end
		for i = 1, aLen do
			local callA = a[i]
			local callB = b[i]
			if callA.to ~= callB.to then
				return false
			end
			if callA.selector ~= callB.selector then
				return false
			end
			local cdA = callA.calldata
			local cdB = callB.calldata
			if #cdA ~= #cdB then
				return false
			end
			for j = 1, #cdA do
				if cdA[j] ~= cdB[j] then
					return false
				end
			end
		end
		return true
	end

	-- Case 1: exact match
	if callsMatch(normSubmitted, #normSubmitted, normReturned, #normReturned) then
		return true
	end

	-- Case 2: returned = submitted + 1 appended transfer call
	if #normReturned == #normSubmitted + 1 then
		if callsMatch(normSubmitted, #normSubmitted, normReturned, #normSubmitted) then
			return true
		end
	end

	return false
end

--- Build a Call to submit the outside execution on-chain.
--- The returned Call targets the signer's account contract with the correct entrypoint
--- and encoded calldata (outside execution parameters + signature).
function OutsideExecution.buildExecuteFromOutsideCall(
	signerAddress: string,
	outsideExecution: { [string]: any },
	signature: { string },
	version: string
): { [string]: any }
	local entrypoint = OutsideExecution.getEntrypoint(version)
	local calldata: { string } = {}

	-- Normalize dual-key convention: resolve to single key set
	local caller = outsideExecution.caller or outsideExecution.Caller
	local nonce = outsideExecution.nonce or outsideExecution.Nonce
	local execAfter = outsideExecution.execute_after or outsideExecution["Execute After"]
	local execBefore = outsideExecution.execute_before or outsideExecution["Execute Before"]
	local calls = (outsideExecution.calls or outsideExecution.Calls) :: { { [string]: any } }

	table.insert(calldata, tostring(caller))
	table.insert(calldata, toHexFelt(nonce))
	table.insert(calldata, toHexFelt(execAfter))
	table.insert(calldata, toHexFelt(execBefore))

	-- Calls array
	table.insert(calldata, string.format("0x%x", #calls))
	for _, call in calls do
		table.insert(calldata, tostring(call.to or call.To))
		table.insert(calldata, tostring(call.selector or call.Selector))
		local cd = (call.calldata or call.Calldata or {}) :: { string }
		table.insert(calldata, string.format("0x%x", #cd))
		for _, felt in cd do
			table.insert(calldata, felt)
		end
	end

	-- Fee mode (V3 only)
	if version == "3" then
		local fee = outsideExecution.Fee
		if fee then
			if fee["No Fee"] then
				table.insert(calldata, "0x0") -- variant index 0
			elseif fee["Pay Fee"] then
				table.insert(calldata, "0x1") -- variant index 1
				local payFeeData = fee["Pay Fee"] :: { any }
				local feeTransfer = payFeeData[1] :: { [string]: any }
				local feeAmount = feeTransfer["Fee Amount"] :: { [string]: any }
				table.insert(calldata, tostring(feeAmount.token_address))
				local amount = feeAmount.amount :: { [string]: any }
				table.insert(calldata, tostring(amount.low))
				table.insert(calldata, tostring(amount.high))
				table.insert(calldata, tostring(feeTransfer["Fee Receiver"]))
			end
		end
	end

	-- Signature array
	table.insert(calldata, string.format("0x%x", #signature))
	for _, sig in signature do
		table.insert(calldata, sig)
	end

	return {
		contractAddress = signerAddress,
		entrypoint = entrypoint,
		calldata = calldata,
	}
end

return OutsideExecution
