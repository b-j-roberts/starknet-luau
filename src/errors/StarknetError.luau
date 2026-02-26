--!strict
-- StarknetError: Typed error system for the starknet-luau SDK
-- Provides factory constructors, type hierarchy, and structured error data.

local ErrorCodes = require("./ErrorCodes")

--------------------------------------------------------------------------------
-- Type hierarchy
--------------------------------------------------------------------------------

-- Maps each error type to its parent(s) for :is() checks
local TYPE_HIERARCHY: { [string]: { string } } = {
	StarknetError = {},
	RpcError = { "StarknetError" },
	SigningError = { "StarknetError" },
	AbiError = { "StarknetError" },
	ValidationError = { "StarknetError" },
	TransactionError = { "StarknetError" },
}

--------------------------------------------------------------------------------
-- Error prototype (shared metatable)
--------------------------------------------------------------------------------

local ErrorProto = {}
ErrorProto.__index = ErrorProto

--- Check if this error is of the given type (including parent types).
--- e.g. an RpcError:is("RpcError") → true, :is("StarknetError") → true
function ErrorProto:is(errorType: string): boolean
	if self._type == errorType then
		return true
	end
	local parents = TYPE_HIERARCHY[self._type]
	if parents then
		for _, parent in parents do
			if parent == errorType then
				return true
			end
			-- Check grandparents
			local grandparents = TYPE_HIERARCHY[parent]
			if grandparents then
				for _, gp in grandparents do
					if gp == errorType then
						return true
					end
				end
			end
		end
	end
	return false
end

function ErrorProto:__tostring(): string
	local code = self.code
	if code then
		return `{self._type} [{code}]: {self.message}`
	end
	return `{self._type}: {self.message}`
end

--------------------------------------------------------------------------------
-- StarknetError module
--------------------------------------------------------------------------------

local StarknetError = {}

--- Re-export ErrorCodes for convenience
StarknetError.ErrorCodes = ErrorCodes

--- Create a base StarknetError.
--- @param message -- human-readable error message
--- @param code -- optional numeric error code (from ErrorCodes)
--- @param data -- optional arbitrary data payload
function StarknetError.new(message: string, code: number?, data: any?): any
	local err = setmetatable({
		_type = "StarknetError",
		message = message,
		code = code,
		data = data,
	}, ErrorProto)
	return err
end

--- Create an RpcError (network / JSON-RPC errors).
--- @param message -- human-readable error message
--- @param sdkCode -- optional SDK error code (from ErrorCodes)
--- @param rpcCode -- optional JSON-RPC error code from the node
--- @param data -- optional arbitrary data payload
function StarknetError.rpc(message: string, sdkCode: number?, rpcCode: number?, data: any?): any
	local err = setmetatable({
		_type = "RpcError",
		message = message,
		code = sdkCode,
		rpcCode = rpcCode,
		data = data,
	}, ErrorProto)
	return err
end

--- Create a SigningError (ECDSA / key errors).
--- @param message -- human-readable error message
--- @param code -- optional numeric error code (from ErrorCodes)
--- @param data -- optional arbitrary data payload
function StarknetError.signing(message: string, code: number?, data: any?): any
	local err = setmetatable({
		_type = "SigningError",
		message = message,
		code = code,
		data = data,
	}, ErrorProto)
	return err
end

--- Create an AbiError (encoding / decoding / type resolution errors).
--- @param message -- human-readable error message
--- @param code -- optional numeric error code (from ErrorCodes)
--- @param data -- optional arbitrary data payload
function StarknetError.abi(message: string, code: number?, data: any?): any
	local err = setmetatable({
		_type = "AbiError",
		message = message,
		code = code,
		data = data,
	}, ErrorProto)
	return err
end

--- Create a ValidationError (input validation / required field errors).
--- @param message -- human-readable error message
--- @param code -- optional numeric error code (from ErrorCodes)
--- @param hint -- optional hint with fix guidance
--- @param data -- optional arbitrary data payload
function StarknetError.validation(message: string, code: number?, hint: string?, data: any?): any
	local err = setmetatable({
		_type = "ValidationError",
		message = message,
		code = code,
		hint = hint,
		data = data,
	}, ErrorProto)
	return err
end

--- Create a TransactionError (tx execution / fee estimation errors).
--- @param message -- human-readable error message
--- @param code -- optional numeric error code (from ErrorCodes)
--- @param revertReason -- optional revert reason from the node
--- @param executionTrace -- optional execution trace data
--- @param data -- optional arbitrary data payload
function StarknetError.transaction(
	message: string,
	code: number?,
	revertReason: string?,
	executionTrace: any?,
	data: any?
): any
	local err = setmetatable({
		_type = "TransactionError",
		message = message,
		code = code,
		revertReason = revertReason,
		executionTrace = executionTrace,
		data = data,
	}, ErrorProto)
	return err
end

--- Duck-type checker: returns true if value looks like a StarknetError.
--- Works even if the value came from a different module instance.
function StarknetError.isStarknetError(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	return type(value._type) == "string"
		and type(value.message) == "string"
		and type(value.is) == "function"
		and TYPE_HIERARCHY[value._type] ~= nil
end

return StarknetError
