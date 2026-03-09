--!strict
-- ErrorCodes: Numeric error code constants for the starknet-luau SDK
-- Codes are segmented by category for easy identification.
--
-- Code ranges:
--   1000-1099  Validation errors
--   2000-2099  RPC / Network errors
--   3000-3099  Signing / Crypto errors (3002 intentionally skipped)
--   4000-4099  ABI / Encoding errors
--   5000-5099  Transaction errors
--   6000-6099  Outside Execution (SNIP-9) errors
--   7000-7099  Paymaster (SNIP-29) errors
--
-- Domain crossover notes:
--   TRANSACTION_REVERTED (2004) and TRANSACTION_REJECTED (2005) live in the 2xxx RPC range
--   because they originate from RPC polling (waitForTransaction), but are raised via
--   StarknetError.transaction() since they represent transaction-level failures.

local ErrorCodes = {}

-- Helper: creates an error code entry. Name is auto-set from the table key below.
local function code(num: number): { code: number, name: string }
	return { code = num, name = "" }
end

-- 1000-1099: Validation errors
ErrorCodes.INVALID_ARGUMENT = code(1000)
ErrorCodes.REQUIRED_FIELD = code(1001)
-- 1002: removed (OUT_OF_RANGE was unused; KEY_OUT_OF_RANGE at 3003 serves range checks)
ErrorCodes.INVALID_FORMAT = code(1003)

-- 2000-2099: RPC / Network errors
ErrorCodes.RPC_ERROR = code(2000)
ErrorCodes.NETWORK_ERROR = code(2001)
ErrorCodes.RATE_LIMIT = code(2002)
ErrorCodes.TIMEOUT = code(2003)
-- 2004-2005: transaction status codes from RPC polling — see domain crossover note above
ErrorCodes.TRANSACTION_REVERTED = code(2004)
ErrorCodes.TRANSACTION_REJECTED = code(2005)
ErrorCodes.QUEUE_FULL = code(2010)
ErrorCodes.BATCH_ERROR = code(2011)
-- 2012: removed (CACHE_ERROR was unused)
ErrorCodes.NONCE_FETCH_ERROR = code(2013)
-- 2014: moved to 5004 (NONCE_EXHAUSTED — used with StarknetError.transaction())
ErrorCodes.NONCE_MANAGER_ERROR = code(2015)

-- 3000-3099: Signing / Crypto errors
ErrorCodes.SIGNING_ERROR = code(3000)
ErrorCodes.INVALID_PRIVATE_KEY = code(3001)
-- 3002: intentionally skipped (no current use case in signing range)
ErrorCodes.KEY_OUT_OF_RANGE = code(3003)
ErrorCodes.MATH_ERROR = code(3010)

-- 4000-4099: ABI / Encoding errors
ErrorCodes.ABI_ERROR = code(4000)
ErrorCodes.UNKNOWN_TYPE = code(4001)
ErrorCodes.ENCODE_ERROR = code(4002)
ErrorCodes.DECODE_ERROR = code(4003)
ErrorCodes.UNKNOWN_ENUM_VARIANT = code(4004)
ErrorCodes.FUNCTION_NOT_FOUND = code(4005)
ErrorCodes.ARGUMENT_COUNT = code(4006)

-- 5000-5099: Transaction errors
ErrorCodes.TRANSACTION_ERROR = code(5000)
ErrorCodes.FEE_ESTIMATION_FAILED = code(5001)
-- 5002: removed (INSUFFICIENT_BALANCE was unused)
ErrorCodes.BATCH_DEPLOY_ERROR = code(5003)
ErrorCodes.NONCE_EXHAUSTED = code(5004)

-- 6000-6099: Outside Execution (SNIP-9) errors
-- 6000: removed (OUTSIDE_EXECUTION_ERROR was generic; use specific codes below)
ErrorCodes.INVALID_VERSION = code(6001)
ErrorCodes.CALL_VALIDATION_FAILED = code(6002)
ErrorCodes.MISSING_FEE_MODE = code(6003)
ErrorCodes.INVALID_TIME_BOUNDS = code(6004)

-- 7000-7099: Paymaster (SNIP-29) errors
-- 7000 is the generic fallback for unmapped paymaster RPC error codes (157, 160, 163)
ErrorCodes.PAYMASTER_ERROR = code(7000)
ErrorCodes.PAYMASTER_UNAVAILABLE = code(7001)
ErrorCodes.PAYMASTER_TOKEN_NOT_SUPPORTED = code(7002)
ErrorCodes.PAYMASTER_INVALID_SIGNATURE = code(7003)
ErrorCodes.PAYMASTER_MAX_AMOUNT_TOO_LOW = code(7004)
ErrorCodes.PAYMASTER_INVALID_DEPLOYMENT_DATA = code(7005)
ErrorCodes.PAYMASTER_EXECUTION_ERROR = code(7006)
ErrorCodes.PAYMASTER_INVALID_ADDRESS = code(7007)
ErrorCodes.PAYMASTER_CLASS_HASH_NOT_SUPPORTED = code(7008)
ErrorCodes.PAYMASTER_CALL_VALIDATION_FAILED = code(7009)
ErrorCodes.PAYMASTER_POLICY_REJECTED = code(7010)
ErrorCodes.BUDGET_ERROR = code(7011)
ErrorCodes.INSUFFICIENT_BUDGET = code(7012)
ErrorCodes.DATASTORE_ERROR = code(7013)
ErrorCodes.INVALID_AMOUNT = code(7014)
ErrorCodes.SPONSORED_EXECUTION_FAILED = code(7020)

-- 8000-8099: KeyStore / Onboarding errors
ErrorCodes.KEY_STORE_ERROR = code(8000)
ErrorCodes.KEY_STORE_DECRYPT_ERROR = code(8001)
ErrorCodes.KEY_STORE_SECRET_INVALID = code(8002)
ErrorCodes.ONBOARDING_ERROR = code(8010)

-- Auto-generate `name` from the table key to prevent key/name divergence
for key, entry in pairs(ErrorCodes) do
	if type(entry) == "table" and entry.code then
		entry.name = key
	end
end

--- Transient error codes that may succeed on retry.
local TRANSIENT_CODES: { [number]: boolean } = {
	[ErrorCodes.NETWORK_ERROR.code] = true,
	[ErrorCodes.RATE_LIMIT.code] = true,
	[ErrorCodes.PAYMASTER_UNAVAILABLE.code] = true,
}

--- Deterministic paymaster error codes that should NOT be retried.
local NON_RETRYABLE_PAYMASTER_CODES: { [number]: boolean } = {
	[ErrorCodes.PAYMASTER_ERROR.code] = true,
	[ErrorCodes.PAYMASTER_TOKEN_NOT_SUPPORTED.code] = true,
	[ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code] = true,
	[ErrorCodes.PAYMASTER_MAX_AMOUNT_TOO_LOW.code] = true,
	[ErrorCodes.PAYMASTER_INVALID_DEPLOYMENT_DATA.code] = true,
	[ErrorCodes.PAYMASTER_EXECUTION_ERROR.code] = true,
	[ErrorCodes.PAYMASTER_INVALID_ADDRESS.code] = true,
	[ErrorCodes.PAYMASTER_CLASS_HASH_NOT_SUPPORTED.code] = true,
}

--- Check if an error code represents a transient (retryable) error.
function ErrorCodes.isTransient(errorCode: number): boolean
	return TRANSIENT_CODES[errorCode] == true
end

--- Check if a paymaster error code is deterministic (should not be retried).
function ErrorCodes.isNonRetryablePaymaster(errorCode: number): boolean
	return NON_RETRYABLE_PAYMASTER_CODES[errorCode] == true
end

return ErrorCodes
