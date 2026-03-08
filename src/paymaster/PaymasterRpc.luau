--!strict
-- PaymasterRpc: Generic SNIP-29 paymaster JSON-RPC client
-- Supports any SNIP-29-compliant paymaster service (AVNU, Cartridge, self-hosted)
-- All public methods return Promises for async operation
-- Delegates core JSON-RPC transport to JsonRpcClient
-- Reference: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-29.md

local RpcTypes = require("../provider/RpcTypes")
local JsonRpcClient = require("../provider/JsonRpcClient")
local CallData = require("../tx/CallData")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- Paymaster configuration
export type PaymasterConfig = {
	nodeUrl: string,
	headers: { [string]: string }?,
	retryAttempts: number?,
	retryDelay: number?,
	maxRequestsPerMinute: number?,
	rateLimitTimeout: number?, -- max seconds to wait for a rate-limit token (default 10)
	-- Testing injection points (same pattern as RpcProvider)
	_httpRequest: ((request: RpcTypes.HttpRequest) -> RpcTypes.HttpResponse)?,
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

--- A single call to be executed (re-exported from CallData)
export type Call = CallData.Call

--- SNIP-29 user parameters
export type UserParameters = {
	version: string, -- "0x1"
	feeMode: FeeMode,
	timeBounds: TimeBounds?,
}

--- Fee mode: sponsored (game pays) or default (user pays in alt token)
export type FeeMode = {
	mode: "sponsored" | "default",
	gasToken: string?, -- required for "default" mode
}

--- Time bounds for outside execution
export type TimeBounds = {
	executeAfter: (string | number)?,
	executeBefore: (string | number)?,
}

--- Deployment data for undeployed accounts
export type DeploymentData = {
	classHash: string,
	calldata: { string },
	salt: string,
	unique: boolean?,
	sigdata: { string }?,
	version: number?,
}

--- Options for buildTypedData
export type BuildTypedDataOptions = {
	accountClassHash: string?,
	deploymentData: DeploymentData?,
}

--- Token data returned by getSupportedTokens
export type TokenData = {
	tokenAddress: string,
	decimals: number,
	priceInStrk: string,
}

--- Fee estimate returned by buildTypedData
export type FeeEstimate = {
	gasTokenPrice: string?,
	estimatedFeeInStrk: string?,
	estimatedFeeInGasToken: string?,
	suggestedMaxFeeInStrk: string?,
	suggestedMaxFeeInGasToken: string?,
}

--- Result from buildTypedData
export type BuildTypedDataResult = {
	typedData: any, -- SNIP-12 typed data object
	feeEstimate: FeeEstimate?,
	deploymentData: any?, -- echoed back for deploy requests
}

--- Result from executeTransaction
export type ExecuteResult = {
	trackingId: string?,
	transactionHash: string,
}

--- Result from trackingIdToLatestHash
export type TrackingResult = {
	transactionHash: string,
	status: string, -- "active" | "accepted" | "dropped"
}

--- The PaymasterRpc class type
export type PaymasterRpc = {
	isAvailable: (self: PaymasterRpc) -> RpcTypes.Promise<boolean>,
	getSupportedTokens: (self: PaymasterRpc) -> RpcTypes.Promise<{ TokenData }>,
	buildTypedData: (
		self: PaymasterRpc,
		userAddress: string,
		calls: { Call },
		gasTokenAddress: string,
		options: BuildTypedDataOptions?
	) -> RpcTypes.Promise<BuildTypedDataResult>,
	executeTransaction: (
		self: PaymasterRpc,
		userAddress: string,
		typedData: any,
		signature: { string },
		options: BuildTypedDataOptions?
	) -> RpcTypes.Promise<ExecuteResult>,
	trackingIdToLatestHash: (self: PaymasterRpc, trackingId: string) -> RpcTypes.Promise<TrackingResult>,
	getNodeUrl: (self: PaymasterRpc) -> string,
	fetch: (self: PaymasterRpc, method: string, params: any) -> RpcTypes.Promise<any>,
	getPromise: (self: PaymasterRpc) -> any,
	resolveImmediate: (self: PaymasterRpc, value: any) -> RpcTypes.Promise<any>,
}

--------------------------------------------------------------------------------
-- Helpers: shared construction & normalization
--------------------------------------------------------------------------------

--- Convert SDK DeploymentData into the SNIP-29 wire format.
local function formatDeploymentData(dd: DeploymentData): any
	local deployData: any = {
		class_hash = dd.classHash,
		constructor_calldata = dd.calldata,
		salt = dd.salt,
		unique = if dd.unique ~= nil then dd.unique else false,
		version = dd.version or 1,
	}
	if dd.sigdata then
		deployData.sigdata = dd.sigdata
	end
	return deployData
end

--- Wrap an invoke body in an INVOKE or DEPLOY_AND_INVOKE envelope.
--- If opts.deploymentData is present, converts to DEPLOY_AND_INVOKE.
local function wrapWithDeployment(invokeBody: any, opts: BuildTypedDataOptions?): any
	local o = opts or {}
	if o.deploymentData then
		invokeBody.deployment_data = formatDeploymentData(o.deploymentData)
		return {
			type = "DEPLOY_AND_INVOKE",
			deploy_and_invoke = invokeBody,
		}
	end
	return {
		type = "INVOKE",
		invoke = invokeBody,
	}
end

--- Build SNIP-29 fee parameters.
--- Nil or "0x0" or "" gasTokenAddress → sponsored mode; otherwise default mode.
local function buildParameters(gasTokenAddress: string?): any
	local parameters: any = { version = "0x1" }
	if not gasTokenAddress or gasTokenAddress == "0x0" or gasTokenAddress == "" then
		parameters.fee_mode = { mode = "sponsored" }
	else
		parameters.fee_mode = { mode = "default", gas_token = gasTokenAddress }
	end
	return parameters
end

--- Normalize a response table from snake_case to camelCase using a key map.
--- keyMap: { camelKey = "snake_key" }
local function normalizeKeys(raw: any, keyMap: { [string]: string }): { [string]: any }
	local result: { [string]: any } = {}
	for camelKey, snakeKey in keyMap do
		result[camelKey] = raw[snakeKey] or raw[camelKey]
	end
	return result
end

-- Response normalization key maps
local FEE_ESTIMATE_KEYS = {
	gasTokenPrice = "gas_token_price",
	estimatedFeeInStrk = "estimated_fee_in_strk",
	estimatedFeeInGasToken = "estimated_fee_in_gas_token",
	suggestedMaxFeeInStrk = "suggested_max_fee_in_strk",
	suggestedMaxFeeInGasToken = "suggested_max_fee_in_gas_token",
}
local BUILD_RESULT_KEYS = { typedData = "typed_data", deploymentData = "deployment_data" }
local EXECUTE_RESULT_KEYS = { trackingId = "tracking_id", transactionHash = "transaction_hash" }
local TRACKING_RESULT_KEYS = { transactionHash = "transaction_hash", status = "status" }

--------------------------------------------------------------------------------
-- SNIP-29 paymaster JSON-RPC error code mapping
--------------------------------------------------------------------------------

-- Maps SNIP-29 paymaster error codes to SDK error codes
local PAYMASTER_RPC_ERROR_MAP: { [number]: { code: number, name: string } } = {
	[150] = ErrorCodes.PAYMASTER_INVALID_ADDRESS,
	[151] = ErrorCodes.PAYMASTER_TOKEN_NOT_SUPPORTED,
	[153] = ErrorCodes.PAYMASTER_INVALID_SIGNATURE,
	[154] = ErrorCodes.PAYMASTER_MAX_AMOUNT_TOO_LOW,
	[155] = ErrorCodes.PAYMASTER_CLASS_HASH_NOT_SUPPORTED,
	[156] = ErrorCodes.PAYMASTER_EXECUTION_ERROR,
	[157] = ErrorCodes.PAYMASTER_ERROR, -- INVALID_TIME_BOUNDS from paymaster
	[158] = ErrorCodes.PAYMASTER_INVALID_DEPLOYMENT_DATA,
	[160] = ErrorCodes.PAYMASTER_ERROR, -- INVALID_ID for tracking
	[163] = ErrorCodes.PAYMASTER_ERROR, -- UNKNOWN_ERROR
}

--- Map a paymaster JSON-RPC error code to an SDK error, then throw
local function mapPaymasterError(decoded: RpcTypes.JsonRpcError): never
	local rpcCode = decoded.code or 0
	local message = decoded.message or "Unknown paymaster error"
	local data = decoded.data
	local mapped = PAYMASTER_RPC_ERROR_MAP[rpcCode]
	if mapped then
		error(StarknetError.rpc(message, mapped.code, rpcCode, data))
	end
	-- Unmapped code: use generic PAYMASTER_ERROR
	error(StarknetError.rpc(message, ErrorCodes.PAYMASTER_ERROR.code, rpcCode, data))
end

--- Determine whether a paymaster error should be retried.
--- Returns false for deterministic paymaster-specific errors.
local function shouldRetryPaymasterError(err: any): boolean
	if typeof(err) == "table" and err._type == "RpcError" then
		if ErrorCodes.isNonRetryablePaymaster(err.code or 0) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- PaymasterRpc class
--------------------------------------------------------------------------------

local PaymasterRpcClass = {}
PaymasterRpcClass.__index = PaymasterRpcClass

--- Create a new PaymasterRpc client.
--- @param config -- PaymasterConfig with nodeUrl and optional settings
function PaymasterRpcClass.new(config: PaymasterConfig): PaymasterRpc
	if not config.nodeUrl or config.nodeUrl == "" then
		error(StarknetError.validation("PaymasterRpc: nodeUrl is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	-- Create the shared JSON-RPC transport client with paymaster-specific customizations
	local client = JsonRpcClient.new({
		nodeUrl = config.nodeUrl,
		headers = config.headers,
		maxRequestsPerMinute = config.maxRequestsPerMinute or 120,
		rateLimitTimeout = config.rateLimitTimeout,
		retryAttempts = config.retryAttempts,
		retryDelay = config.retryDelay,
		clientName = "PaymasterRpc",
		errorMapper = mapPaymasterError,
		shouldRetry = shouldRetryPaymasterError,
		_httpRequest = config._httpRequest,
		_sleep = config._sleep,
		_clock = config._clock,
	})

	local self = setmetatable({
		_client = client,
		-- Expose _PromiseModule for test injection compatibility
		_PromiseModule = client._PromiseModule,
	}, PaymasterRpcClass)

	return self :: any
end

--- Get the configured paymaster endpoint URL
function PaymasterRpcClass:getNodeUrl(): string
	return self._client:getNodeUrl()
end

--- Get the Promise constructor.
--- Syncs externally-injected _PromiseModule (test pattern) to the internal client.
function PaymasterRpcClass:getPromise(): any
	if self._PromiseModule and self._PromiseModule ~= self._client._PromiseModule then
		self._client._PromiseModule = self._PromiseModule
	end
	return self._client:getPromise()
end

--- Wrap a value in a resolved Promise. Useful for returning cached data
--- in the same async shape as a network call.
function PaymasterRpcClass:resolveImmediate(value: any): any
	local Promise = self:getPromise()
	return Promise.resolve(value)
end

--------------------------------------------------------------------------------
-- Public: fetch (raw RPC call, Promise-based)
--------------------------------------------------------------------------------

--- Raw paymaster RPC call. Returns a Promise that resolves to the JSON-RPC result.
function PaymasterRpcClass:fetch(method: string, params: any): any
	-- Ensure _PromiseModule sync before network call (getPromise handles this)
	self:getPromise()
	return self._client:fetch(method, params)
end

--------------------------------------------------------------------------------
-- Public SNIP-29 methods
--------------------------------------------------------------------------------

--- Check if the paymaster service is operational.
--- @return Promise<boolean> -- true if available, false otherwise
function PaymasterRpcClass:isAvailable(): any
	local Promise = self:getPromise()

	return Promise.new(function(resolve: (any) -> (), _reject: (any) -> ())
		local ok, result = pcall(function()
			return self._client:_requestWithRetry("paymaster_isAvailable", {})
		end)
		if ok then
			resolve(result == true)
		else
			-- If the service is unreachable, resolve false rather than rejecting
			resolve(false)
		end
	end)
end

--- Get the list of tokens supported by this paymaster, with STRK pricing.
--- @return Promise<{ TokenData }>
function PaymasterRpcClass:getSupportedTokens(): any
	return self:fetch("paymaster_getSupportedTokens", {}):andThen(function(result: any)
		-- Normalize response: snake_case from SNIP-29 → camelCase for SDK
		local tokens: { TokenData } = {}
		if type(result) == "table" then
			for _, raw in result do
				table.insert(tokens, {
					tokenAddress = raw.token_address or raw.tokenAddress or "",
					decimals = raw.decimals or 0,
					priceInStrk = raw.price_in_strk or raw.priceInStrk or "0",
				})
			end
		end
		return tokens
	end)
end

--- Build SNIP-12 typed data for a sponsored/gasless transaction.
--- The paymaster wraps the user's calls in an OutsideExecution and returns typed data ready to sign.
--- @param userAddress -- the user's account address
--- @param calls -- the calls the user wants to execute
--- @param gasTokenAddress -- which token to pay fees in (or "0x0" for sponsored)
--- @param options -- optional: accountClassHash, deploymentData
--- @return Promise<BuildTypedDataResult>
function PaymasterRpcClass:buildTypedData(
	userAddress: string,
	calls: { Call },
	gasTokenAddress: string,
	options: BuildTypedDataOptions?
): any
	-- Build the SNIP-29 "transaction" parameter
	local formattedCalls = {}
	for _, call in calls do
		table.insert(formattedCalls, {
			contract_address = call.contractAddress,
			entry_point = call.entrypoint,
			calldata = call.calldata,
		})
	end

	local opts = options or {}
	local invokeBody: any = { user_address = userAddress, calls = formattedCalls }
	if opts.accountClassHash and not opts.deploymentData then
		invokeBody.account_class_hash = opts.accountClassHash
	end

	local rpcParams = {
		wrapWithDeployment(invokeBody, opts),
		buildParameters(gasTokenAddress),
	}

	return self:fetch("paymaster_buildTypedData", rpcParams):andThen(function(result: any)
		local buildResult: BuildTypedDataResult = normalizeKeys(result, BUILD_RESULT_KEYS) :: any
		buildResult.feeEstimate = nil

		local rawFee = result.fee_estimate or result.feeEstimate
		if rawFee then
			buildResult.feeEstimate = normalizeKeys(rawFee, FEE_ESTIMATE_KEYS) :: FeeEstimate
		end

		return buildResult
	end)
end

--- Execute a signed transaction through the paymaster.
--- @param userAddress -- the user's account address
--- @param typedData -- the SNIP-12 typed data (from buildTypedData)
--- @param signature -- the user's signature over the typed data [r, s]
--- @param options -- optional: deploymentData for deploy-via-paymaster
--- @return Promise<ExecuteResult>
function PaymasterRpcClass:executeTransaction(
	userAddress: string,
	typedData: any,
	signature: { string },
	options: BuildTypedDataOptions?
): any
	local invokeBody: any = {
		user_address = userAddress,
		typed_data = typedData,
		signature = signature,
	}

	local rpcParams = {
		wrapWithDeployment(invokeBody, options),
		buildParameters(), -- always sponsored for execution
	}

	return self:fetch("paymaster_executeTransaction", rpcParams):andThen(function(result: any)
		return normalizeKeys(result, EXECUTE_RESULT_KEYS) :: ExecuteResult
	end)
end

--- Map a tracking ID to the latest transaction hash and status.
--- @param trackingId -- the tracking ID from executeTransaction
--- @return Promise<TrackingResult>
function PaymasterRpcClass:trackingIdToLatestHash(trackingId: string): any
	return self:fetch("paymaster_trackingIdToLatestHash", { trackingId }):andThen(function(result: any)
		local trackResult = normalizeKeys(result, TRACKING_RESULT_KEYS)
		trackResult.status = trackResult.status or "active"
		return trackResult :: TrackingResult
	end)
end

return PaymasterRpcClass
