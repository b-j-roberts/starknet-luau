--!strict
-- Contract: ABI-driven contract interaction for reading state and building transaction calls
-- Supports dynamic method dispatch via __index metamethod based on function state_mutability
-- Reference: starknet.js Contract class

local Keccak = require("../crypto/Keccak")
local StarkField = require("../crypto/StarkField")
local CallData = require("../tx/CallData")
local AbiCodec = require("./AbiCodec")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- A single ABI function input/output parameter
export type AbiParameter = {
	name: string,
	type: string,
}

--- A single ABI function entry
export type AbiFunction = {
	type: string, -- "function" | "l1_handler" | "constructor" | "event" | "struct" | "enum" | "interface" | "impl"
	name: string,
	inputs: { AbiParameter }?,
	outputs: { AbiParameter }?,
	state_mutability: string?, -- "view" | "external"
}

--- Full ABI is an array of entries
export type Abi = { AbiFunction }

--- Configuration for creating a Contract instance
export type ContractConfig = {
	abi: Abi,
	address: string,
	provider: any,
	account: any?, -- optional, required for invoke()
}

--- A Call object for multicall batching (re-export from CallData)
export type Call = CallData.Call

--- Result of a call() operation (array of hex strings from RPC)
export type CallResult = { string }

--- Options for invoke() operations (passed through to account.execute)
export type InvokeOptions = {
	nonce: string?,
	maxFee: string?,
	feeMultiplier: number?,
	dryRun: boolean?,
}

--------------------------------------------------------------------------------
-- Internal: ABI parsing
--------------------------------------------------------------------------------

--- Parsed function metadata from ABI
type ParsedFunction = {
	name: string,
	inputs: { AbiParameter },
	outputs: { AbiParameter },
	stateMutability: string, -- "view" | "external"
	selector: string, -- hex string of the snKeccak selector
}

--- Parse an ABI array into a lookup table of functions keyed by name.
--- Also extracts functions from "interface" entries (nested items).
local function parseAbi(abi: Abi): ({ [string]: ParsedFunction }, AbiCodec.TypeMap)
	local functions: { [string]: ParsedFunction } = {}

	local function addFunction(entry: AbiFunction)
		local selector = Keccak.getSelectorFromName(entry.name)
		functions[entry.name] = {
			name = entry.name,
			inputs = entry.inputs or {},
			outputs = entry.outputs or {},
			stateMutability = entry.state_mutability or "external",
			selector = StarkField.toHex(selector),
		}
	end

	for _, entry in abi do
		if entry.type == "function" then
			addFunction(entry)
		elseif entry.type == "interface" then
			-- Extract nested function items from interface entries
			local items = (entry :: any).items
			if items then
				for _, item in items :: { any } do
					local fn = item :: AbiFunction
					if fn.type == "function" then
						addFunction(fn)
					end
				end
			end
		end
	end

	local typeMap = AbiCodec.buildTypeMap(abi :: { any })
	return functions, typeMap
end

-- NOTE: Type encoding/decoding is now handled by AbiCodec module

--------------------------------------------------------------------------------
-- Contract class
--------------------------------------------------------------------------------

local Contract = {}

--- Custom __index that supports dynamic method dispatch.
--- Looks up ABI function names and returns bound call/invoke/populate wrappers.
function Contract:__index(key: string): any
	-- First check the Contract class methods
	local classMethod = rawget(Contract, key)
	if classMethod ~= nil then
		return classMethod
	end

	-- Then check the instance fields
	local self_: any = self
	local raw = rawget(self_, key)
	if raw ~= nil then
		return raw
	end

	-- Dynamic dispatch: look up ABI functions
	local functions: { [string]: ParsedFunction } = rawget(self_, "_functions")
	if functions then
		local fn = functions[key]
		if fn then
			if fn.stateMutability == "view" then
				-- View function -> return a callable that does contract:call()
				return function(_selfArg: any, ...: any)
					return Contract.call(self_, key, { ... })
				end
			else
				-- External function -> return a callable that does contract:invoke()
				return function(_selfArg: any, ...: any)
					local args = { ... }
					-- Last arg might be options table
					local lastArg = args[#args]
					local options: InvokeOptions? = nil
					local fnArgs: { any }

					if type(lastArg) == "table" and #args > #fn.inputs then
						options = lastArg :: any
						fnArgs = {}
						for i = 1, #args - 1 do
							table.insert(fnArgs, args[i])
						end
					else
						fnArgs = args
					end

					return Contract.invoke(self_, key, fnArgs, options)
				end
			end
		end
	end

	return nil
end

--- Create a new Contract instance.
--- @param config -- { abi, address, provider, account? }
function Contract.new(config: ContractConfig): any
	if not config.abi then
		error("Contract: abi is required")
	end
	if not config.address then
		error("Contract: address is required")
	end
	if not config.provider then
		error("Contract: provider is required")
	end

	local functions, typeMap = parseAbi(config.abi)

	local self = setmetatable({
		abi = config.abi,
		address = config.address,
		_provider = config.provider,
		_account = config.account,
		_functions = functions,
		_typeMap = typeMap,
	}, Contract)

	return self
end

--- Read-only contract call (view functions).
--- @param method -- function name from ABI
--- @param args -- optional array of argument values
--- @param blockId -- optional block identifier (default "latest")
--- @return Promise resolving to parsed result
function Contract:call(method: string, args: { any }?, blockId: string?): any
	local self_: any = self
	local functions: { [string]: ParsedFunction } = self_._functions
	local fn = functions[method]
	if not fn then
		error(`Contract: function "{method}" not found in ABI`)
	end

	local callArgs = args or {}
	local inputs = fn.inputs
	local typeMap: AbiCodec.TypeMap = self_._typeMap

	if #callArgs ~= #inputs then
		error(`Contract: {method} expects {#inputs} arguments, got {#callArgs}`)
	end

	-- Encode calldata via AbiCodec
	local calldata = AbiCodec.encodeInputs(callArgs, inputs, typeMap)

	-- Build the RPC call request
	local request = {
		contract_address = self_.address,
		entry_point_selector = fn.selector,
		calldata = calldata,
	}

	local provider: any = self_._provider

	-- Call provider and parse result via AbiCodec
	return provider:call(request, blockId):andThen(function(results: { string })
		return AbiCodec.decodeOutputs(results, fn.outputs, typeMap)
	end)
end

--- Build a Call object for multicall batching (no execution).
--- @param method -- function name from ABI
--- @param args -- optional array of argument values
--- @return Call object { contractAddress, entrypoint, calldata }
function Contract:populate(method: string, args: { any }?): Call
	local self_: any = self
	local functions: { [string]: ParsedFunction } = self_._functions
	local fn = functions[method]
	if not fn then
		error(`Contract: function "{method}" not found in ABI`)
	end

	local callArgs = args or {}
	local inputs = fn.inputs
	local typeMap: AbiCodec.TypeMap = self_._typeMap

	if #callArgs ~= #inputs then
		error(`Contract: {method} expects {#inputs} arguments, got {#callArgs}`)
	end

	-- Encode calldata via AbiCodec
	local calldata = AbiCodec.encodeInputs(callArgs, inputs, typeMap)

	return {
		contractAddress = self_.address,
		entrypoint = method,
		calldata = calldata,
	}
end

--- Write transaction (external functions).
--- Requires an account to be set on the contract.
--- @param method -- function name from ABI
--- @param args -- optional array of argument values
--- @param options -- optional execute options (nonce, feeMultiplier, dryRun, etc.)
--- @return Promise resolving to { transactionHash: string }
function Contract:invoke(method: string, args: { any }?, options: InvokeOptions?): any
	local self_: any = self
	local account: any = self_._account
	if not account then
		error("Contract: account is required for invoke(). Pass account in Contract.new config.")
	end

	local call = Contract.populate(self_, method, args)
	return account:execute({ call }, options)
end

--- Get the list of function names in the ABI.
function Contract:getFunctions(): { string }
	local self_: any = self
	local functions: { [string]: ParsedFunction } = self_._functions
	local names: { string } = {}
	for name, _ in functions do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Get parsed function metadata by name.
function Contract:getFunction(name: string): ParsedFunction?
	local self_: any = self
	local functions: { [string]: ParsedFunction } = self_._functions
	return functions[name]
end

--- Check if a function exists in the ABI.
function Contract:hasFunction(name: string): boolean
	local self_: any = self
	local functions: { [string]: ParsedFunction } = self_._functions
	return functions[name] ~= nil
end

return Contract
