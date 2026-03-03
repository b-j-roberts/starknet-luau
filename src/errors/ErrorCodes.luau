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
ErrorCodes.NONCE_FETCH_ERROR = { code = 2013, name = "NONCE_FETCH_ERROR" }
ErrorCodes.NONCE_EXHAUSTED = { code = 2014, name = "NONCE_EXHAUSTED" }
ErrorCodes.NONCE_MANAGER_ERROR = { code = 2015, name = "NONCE_MANAGER_ERROR" }

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
ErrorCodes.INSUFFICIENT_BALANCE = { code = 5002, name = "INSUFFICIENT_BALANCE" }
ErrorCodes.BATCH_DEPLOY_ERROR = { code = 5003, name = "BATCH_DEPLOY_ERROR" }

-- 6000-6099: Outside Execution (SNIP-9) errors
ErrorCodes.OUTSIDE_EXECUTION_ERROR = { code = 6000, name = "OUTSIDE_EXECUTION_ERROR" }
ErrorCodes.INVALID_VERSION = { code = 6001, name = "INVALID_VERSION" }
ErrorCodes.CALL_VALIDATION_FAILED = { code = 6002, name = "CALL_VALIDATION_FAILED" }
ErrorCodes.MISSING_FEE_MODE = { code = 6003, name = "MISSING_FEE_MODE" }
ErrorCodes.INVALID_TIME_BOUNDS = { code = 6004, name = "INVALID_TIME_BOUNDS" }

-- 7000-7099: Paymaster (SNIP-29) errors
ErrorCodes.PAYMASTER_ERROR = { code = 7000, name = "PAYMASTER_ERROR" }
ErrorCodes.PAYMASTER_UNAVAILABLE = { code = 7001, name = "PAYMASTER_UNAVAILABLE" }
ErrorCodes.PAYMASTER_TOKEN_NOT_SUPPORTED = { code = 7002, name = "PAYMASTER_TOKEN_NOT_SUPPORTED" }
ErrorCodes.PAYMASTER_INVALID_SIGNATURE = { code = 7003, name = "PAYMASTER_INVALID_SIGNATURE" }
ErrorCodes.PAYMASTER_MAX_AMOUNT_TOO_LOW = { code = 7004, name = "PAYMASTER_MAX_AMOUNT_TOO_LOW" }
ErrorCodes.PAYMASTER_INVALID_DEPLOYMENT_DATA = { code = 7005, name = "PAYMASTER_INVALID_DEPLOYMENT_DATA" }
ErrorCodes.PAYMASTER_EXECUTION_ERROR = { code = 7006, name = "PAYMASTER_EXECUTION_ERROR" }
ErrorCodes.PAYMASTER_INVALID_ADDRESS = { code = 7007, name = "PAYMASTER_INVALID_ADDRESS" }
ErrorCodes.PAYMASTER_CLASS_HASH_NOT_SUPPORTED = { code = 7008, name = "PAYMASTER_CLASS_HASH_NOT_SUPPORTED" }
ErrorCodes.PAYMASTER_CALL_VALIDATION_FAILED = { code = 7009, name = "PAYMASTER_CALL_VALIDATION_FAILED" }
ErrorCodes.PAYMASTER_POLICY_REJECTED = { code = 7010, name = "PAYMASTER_POLICY_REJECTED" }
ErrorCodes.BUDGET_ERROR = { code = 7011, name = "BUDGET_ERROR" }
ErrorCodes.INSUFFICIENT_BUDGET = { code = 7012, name = "INSUFFICIENT_BUDGET" }
ErrorCodes.DATASTORE_ERROR = { code = 7013, name = "DATASTORE_ERROR" }
ErrorCodes.INVALID_AMOUNT = { code = 7014, name = "INVALID_AMOUNT" }

return ErrorCodes
