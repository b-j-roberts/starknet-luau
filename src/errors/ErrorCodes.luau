--!strict
-- ErrorCodes: Numeric error code constants for the starknet-luau SDK
-- Codes are segmented by category for easy identification.

local ErrorCodes = {}

-- 1000-1099: Validation errors
ErrorCodes.INVALID_ARGUMENT = { code = 1000, name = "INVALID_ARGUMENT" }
ErrorCodes.REQUIRED_FIELD = { code = 1001, name = "REQUIRED_FIELD" }
ErrorCodes.OUT_OF_RANGE = { code = 1002, name = "OUT_OF_RANGE" }
ErrorCodes.INVALID_FORMAT = { code = 1003, name = "INVALID_FORMAT" }

-- 2000-2099: RPC / Network errors
ErrorCodes.RPC_ERROR = { code = 2000, name = "RPC_ERROR" }
ErrorCodes.NETWORK_ERROR = { code = 2001, name = "NETWORK_ERROR" }
ErrorCodes.RATE_LIMIT = { code = 2002, name = "RATE_LIMIT" }
ErrorCodes.TIMEOUT = { code = 2003, name = "TIMEOUT" }
ErrorCodes.TRANSACTION_REVERTED = { code = 2004, name = "TRANSACTION_REVERTED" }
ErrorCodes.TRANSACTION_REJECTED = { code = 2005, name = "TRANSACTION_REJECTED" }
ErrorCodes.QUEUE_FULL = { code = 2010, name = "QUEUE_FULL" }
ErrorCodes.BATCH_ERROR = { code = 2011, name = "BATCH_ERROR" }
ErrorCodes.CACHE_ERROR = { code = 2012, name = "CACHE_ERROR" }

-- 3000-3099: Signing / Crypto errors
ErrorCodes.SIGNING_ERROR = { code = 3000, name = "SIGNING_ERROR" }
ErrorCodes.INVALID_PRIVATE_KEY = { code = 3001, name = "INVALID_PRIVATE_KEY" }
ErrorCodes.KEY_OUT_OF_RANGE = { code = 3003, name = "KEY_OUT_OF_RANGE" }
ErrorCodes.MATH_ERROR = { code = 3010, name = "MATH_ERROR" }

-- 4000-4099: ABI / Encoding errors
ErrorCodes.ABI_ERROR = { code = 4000, name = "ABI_ERROR" }
ErrorCodes.UNKNOWN_TYPE = { code = 4001, name = "UNKNOWN_TYPE" }
ErrorCodes.ENCODE_ERROR = { code = 4002, name = "ENCODE_ERROR" }
ErrorCodes.DECODE_ERROR = { code = 4003, name = "DECODE_ERROR" }
ErrorCodes.UNKNOWN_ENUM_VARIANT = { code = 4004, name = "UNKNOWN_ENUM_VARIANT" }
ErrorCodes.FUNCTION_NOT_FOUND = { code = 4005, name = "FUNCTION_NOT_FOUND" }
ErrorCodes.ARGUMENT_COUNT = { code = 4006, name = "ARGUMENT_COUNT" }

-- 5000-5099: Transaction errors
ErrorCodes.TRANSACTION_ERROR = { code = 5000, name = "TRANSACTION_ERROR" }
ErrorCodes.FEE_ESTIMATION_FAILED = { code = 5001, name = "FEE_ESTIMATION_FAILED" }

return ErrorCodes
