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
	local current = self._type
	while current do
		if current == errorType then
			return true
		end
		local parents = TYPE_HIERARCHY[current]
		current = if parents then parents[1] else nil
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

--------------------------------------------------------------------------------
-- Internal helper: creates an error table with the given type and fields
--------------------------------------------------------------------------------

local function createError(errorType: string, fields: { [string]: any }): any
	fields._type = errorType
	return setmetatable(fields, ErrorProto)
end

--- Create a base StarknetError.
function StarknetError.new(message: string, code: number?, data: any?): any
	return createError("StarknetError", { message = message, code = code, data = data })
end

--- Create an RpcError (network / JSON-RPC errors).
function StarknetError.rpc(message: string, sdkCode: number?, rpcCode: number?, data: any?): any
	return createError("RpcError", { message = message, code = sdkCode, rpcCode = rpcCode, data = data })
end

--- Create a SigningError (ECDSA / key errors).
function StarknetError.signing(message: string, code: number?, data: any?): any
	return createError("SigningError", { message = message, code = code, data = data })
end

--- Create an AbiError (encoding / decoding / type resolution errors).
function StarknetError.abi(message: string, code: number?, data: any?): any
	return createError("AbiError", { message = message, code = code, data = data })
end

--- Create a ValidationError (input validation / required field errors).
function StarknetError.validation(message: string, code: number?, hint: string?, data: any?): any
	return createError("ValidationError", { message = message, code = code, hint = hint, data = data })
end

--- Create a TransactionError (tx execution / fee estimation errors).
function StarknetError.transaction(
	message: string,
	code: number?,
	revertReason: string?,
	executionTrace: any?,
	data: any?
): any
	return createError("TransactionError", {
		message = message,
		code = code,
		revertReason = revertReason,
		executionTrace = executionTrace,
		data = data,
	})
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
