--!strict
-- Contract: ABI-driven contract interaction for reading state and building transaction calls
-- Supports dynamic method dispatch via __index metamethod based on function state_mutability
-- Reference: starknet.js Contract class

local Keccak = require("../crypto/Keccak")
local StarkField = require("../crypto/StarkField")
local CallData = require("../tx/CallData")

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

--- Parse an ABI array into a lookup table of functions keyed by name
local function parseAbi(abi: Abi): { [string]: ParsedFunction }
	local functions: { [string]: ParsedFunction } = {}

	for _, entry in abi do
		if entry.type == "function" then
			local selector = Keccak.getSelectorFromName(entry.name)
			functions[entry.name] = {
				name = entry.name,
				inputs = entry.inputs or {},
				outputs = entry.outputs or {},
				stateMutability = entry.state_mutability or "external",
				selector = StarkField.toHex(selector),
			}
		end
	end

	return functions
end

--------------------------------------------------------------------------------
-- Internal: Basic type encoding/decoding
--------------------------------------------------------------------------------

--- Encode a single argument value to calldata felts based on ABI type.
--- MVP types: felt252, ContractAddress, bool, u8-u128, u256
local function encodeArg(value: any, abiType: string): { string }
	if abiType == "core::felt252" or abiType == "felt252" then
		return CallData.encodeFelt(tostring(value))
	elseif
		abiType == "core::starknet::contract_address::ContractAddress"
		or abiType == "ContractAddress"
		or abiType == "core::starknet::class_hash::ClassHash"
		or abiType == "ClassHash"
	then
		return CallData.encodeFelt(tostring(value))
	elseif abiType == "core::bool" or abiType == "bool" then
		return CallData.encodeBool(value :: boolean)
	elseif abiType == "core::integer::u256" or abiType == "u256" then
		return CallData.encodeU256(tostring(value))
	elseif
		string.match(abiType, "^core::integer::u%d+$")
		or string.match(abiType, "^u%d+$")
		or string.match(abiType, "^core::integer::i%d+$")
		or string.match(abiType, "^i%d+$")
	then
		-- u8, u16, u32, u64, u128, i8, i16, etc. -- single felt
		return CallData.encodeFelt(tostring(value))
	else
		-- Fallback: treat as felt
		return CallData.encodeFelt(tostring(value))
	end
end

--- Decode a single output value from result felts based on ABI type.
--- Returns (decoded_value, felts_consumed).
--- MVP: returns raw hex strings; u256 returns two-element table { low, high }.
local function decodeResult(results: { string }, offset: number, abiType: string): (any, number)
	if abiType == "core::integer::u256" or abiType == "u256" then
		-- u256 occupies 2 felts: low, high
		local low = results[offset]
		local high = results[offset + 1]
		return { low = low, high = high }, 2
	elseif abiType == "core::bool" or abiType == "bool" then
		return results[offset] == "0x1", 1
	else
		-- Everything else is a single felt
		return results[offset], 1
	end
end

--- Parse a full call result array based on ABI output types.
--- Returns a table keyed by output parameter name (or positional index if unnamed).
local function parseCallResult(results: { string }, outputs: { AbiParameter }): any
	if #outputs == 0 then
		return results
	end

	-- Single output: return the decoded value directly
	if #outputs == 1 then
		local decoded, _ = decodeResult(results, 1, outputs[1].type)
		return decoded
	end

	-- Multiple outputs: return a table keyed by name
	local parsed: { [string]: any } = {}
	local offset = 1
	for _, output in outputs do
		local decoded, consumed = decodeResult(results, offset, output.type)
		local key = if output.name ~= "" then output.name else tostring(offset)
		parsed[key] = decoded
		offset += consumed
	end
	return parsed
end

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

	local functions = parseAbi(config.abi)

	local self = setmetatable({
		abi = config.abi,
		address = config.address,
		_provider = config.provider,
		_account = config.account,
		_functions = functions,
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

	if #callArgs ~= #inputs then
		error(`Contract: {method} expects {#inputs} arguments, got {#callArgs}`)
	end

	-- Encode calldata
	local calldata: { string } = {}
	for i, input in inputs do
		local encoded = encodeArg(callArgs[i], input.type)
		for _, felt in encoded do
			table.insert(calldata, felt)
		end
	end

	-- Build the RPC call request
	local request = {
		contract_address = self_.address,
		entry_point_selector = fn.selector,
		calldata = calldata,
	}

	local provider: any = self_._provider

	-- Call provider and parse result
	return provider:call(request, blockId):andThen(function(results: { string })
		return parseCallResult(results, fn.outputs)
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

	if #callArgs ~= #inputs then
		error(`Contract: {method} expects {#inputs} arguments, got {#callArgs}`)
	end

	-- Encode calldata
	local calldata: { string } = {}
	for i, input in inputs do
		local encoded = encodeArg(callArgs[i], input.type)
		for _, felt in encoded do
			table.insert(calldata, felt)
		end
	end

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
