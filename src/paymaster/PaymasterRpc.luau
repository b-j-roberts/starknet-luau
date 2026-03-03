--!strict
-- PaymasterRpc: Generic SNIP-29 paymaster JSON-RPC client
-- Supports any SNIP-29-compliant paymaster service (AVNU, Cartridge, self-hosted)
-- All public methods return Promises for async operation
-- Reference: https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-29.md

local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- Promise-like type for return annotations
export type Promise<T> = {
	andThen: (self: Promise<T>, onResolve: (value: T) -> any) -> Promise<any>,
	catch: (self: Promise<T>, onReject: (err: any) -> any) -> Promise<any>,
	expect: (self: Promise<T>) -> T,
}

export type HttpRequest = {
	Url: string,
	Method: string,
	Headers: { [string]: string },
	Body: string?,
}

export type HttpResponse = {
	StatusCode: number,
	Body: string,
	Headers: { [string]: string }?,
	Success: boolean,
}

--- Paymaster configuration
export type PaymasterConfig = {
	nodeUrl: string,
	headers: { [string]: string }?,
	retryAttempts: number?,
	retryDelay: number?,
	maxRequestsPerMinute: number?,
	-- Testing injection points (same pattern as RpcProvider)
	_httpRequest: ((request: HttpRequest) -> HttpResponse)?,
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

--- A single call to be executed
export type Call = {
	contractAddress: string,
	entrypoint: string,
	calldata: { string },
}

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
	isAvailable: (self: PaymasterRpc) -> Promise<boolean>,
	getSupportedTokens: (self: PaymasterRpc) -> Promise<{ TokenData }>,
	buildTypedData: (
		self: PaymasterRpc,
		userAddress: string,
		calls: { Call },
		gasTokenAddress: string,
		options: BuildTypedDataOptions?
	) -> Promise<BuildTypedDataResult>,
	executeTransaction: (
		self: PaymasterRpc,
		userAddress: string,
		typedData: any,
		signature: { string },
		options: BuildTypedDataOptions?
	) -> Promise<ExecuteResult>,
	trackingIdToLatestHash: (self: PaymasterRpc, trackingId: string) -> Promise<TrackingResult>,
	getNodeUrl: (self: PaymasterRpc) -> string,
	fetch: (self: PaymasterRpc, method: string, params: any) -> Promise<any>,
}

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

--------------------------------------------------------------------------------
-- Rate limiter: token bucket (same algorithm as RpcProvider)
--------------------------------------------------------------------------------

type RateLimiter = {
	tokens: number,
	maxTokens: number,
	refillRate: number,
	lastRefill: number,
}

local function createRateLimiter(maxPerMinute: number, clockFn: () -> number): RateLimiter
	return {
		tokens = maxPerMinute,
		maxTokens = maxPerMinute,
		refillRate = maxPerMinute / 60,
		lastRefill = clockFn(),
	}
end

local function tryAcquire(limiter: RateLimiter, clockFn: () -> number): boolean
	local now = clockFn()
	local elapsed = now - limiter.lastRefill
	local newTokens = elapsed * limiter.refillRate
	limiter.tokens = math.min(limiter.maxTokens, limiter.tokens + newTokens)
	limiter.lastRefill = now

	if limiter.tokens >= 1 then
		limiter.tokens -= 1
		return true
	end
	return false
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

	local clockFn = config._clock or os.clock
	local maxRpm = config.maxRequestsPerMinute or 120

	local self = setmetatable({
		_nodeUrl = config.nodeUrl,
		_headers = config.headers or {},
		_retryAttempts = config.retryAttempts or 3,
		_retryDelay = config.retryDelay or 1,
		_requestId = 0,
		_rateLimiter = createRateLimiter(maxRpm, clockFn),
		_httpRequest = config._httpRequest,
		_sleep = config._sleep or function(seconds: number)
			task.wait(seconds)
		end,
		_clock = clockFn,
		_PromiseModule = nil :: any,
	}, PaymasterRpcClass)

	-- Load Promise module (skip in test mode where _httpRequest is injected)
	if not config._httpRequest then
		local ok, promiseMod = pcall(function()
			return require("@Packages/Promise") :: any
		end)
		if ok then
			self._PromiseModule = promiseMod
		end
	end

	return self :: any
end

--- Get the configured paymaster endpoint URL
function PaymasterRpcClass:getNodeUrl(): string
	return self._nodeUrl
end

--------------------------------------------------------------------------------
-- Internal: Promise, HTTP, JSON helpers
--------------------------------------------------------------------------------

function PaymasterRpcClass:_getPromise(): any
	if self._PromiseModule then
		return self._PromiseModule
	end
	error(
		StarknetError.validation(
			"PaymasterRpc: Promise module not available. In tests, set _PromiseModule on the instance.",
			ErrorCodes.REQUIRED_FIELD.code
		)
	)
end

function PaymasterRpcClass:_doHttpRequest(request: HttpRequest): HttpResponse
	if self._httpRequest then
		return self._httpRequest(request)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:RequestAsync(request)
end

function PaymasterRpcClass:_jsonEncode(value: any): string
	if self._httpRequest then
		local serde = require("@lune/serde") :: any
		return serde.encode("json", value)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONEncode(value)
end

function PaymasterRpcClass:_jsonDecode(json: string): any
	if self._httpRequest then
		local serde = require("@lune/serde") :: any
		return serde.decode("json", json)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONDecode(json)
end

--------------------------------------------------------------------------------
-- Internal: JSON-RPC request mechanics
--------------------------------------------------------------------------------

--- Map a paymaster JSON-RPC error code to an SDK error, then throw
local function mapPaymasterError(rpcCode: number, message: string, data: any): never
	local mapped = PAYMASTER_RPC_ERROR_MAP[rpcCode]
	if mapped then
		error(StarknetError.rpc(message, mapped.code, rpcCode, data))
	end
	-- Unmapped code: use generic PAYMASTER_ERROR
	error(StarknetError.rpc(message, ErrorCodes.PAYMASTER_ERROR.code, rpcCode, data))
end

--- Perform a single JSON-RPC request (rate-limited, synchronous).
function PaymasterRpcClass:_rawRequest(method: string, params: any): any
	-- Rate limiting
	local maxWait = 10
	local startTime = self._clock()
	while not tryAcquire(self._rateLimiter, self._clock) do
		if self._clock() - startTime > maxWait then
			error(
				StarknetError.rpc(
					"Rate limit exceeded: could not acquire token within timeout",
					ErrorCodes.RATE_LIMIT.code
				)
			)
		end
		self._sleep(0.05)
	end

	-- Build JSON-RPC 2.0 request
	self._requestId += 1
	local rpcRequest = {
		jsonrpc = "2.0",
		method = method,
		params = params,
		id = self._requestId,
	}

	local body = self:_jsonEncode(rpcRequest)
	local headers: { [string]: string } = {
		["Content-Type"] = "application/json",
	}
	for k, v in self._headers do
		headers[k] = v
	end

	local httpRequest: HttpRequest = {
		Url = self._nodeUrl,
		Method = "POST",
		Headers = headers,
		Body = body,
	}

	local response = self:_doHttpRequest(httpRequest)

	-- HTTP-level error
	if not response.Success and response.StatusCode ~= 200 then
		error(
			StarknetError.rpc(
				`HTTP {response.StatusCode}: {response.Body}`,
				ErrorCodes.NETWORK_ERROR.code,
				response.StatusCode
			)
		)
	end

	local decoded = self:_jsonDecode(response.Body)

	-- JSON-RPC error response
	if decoded.error then
		local rpcCode = decoded.error.code or 0
		local message = decoded.error.message or "Unknown paymaster error"
		local data = decoded.error.data
		mapPaymasterError(rpcCode, message, data)
	end

	return decoded.result
end

--- Perform a JSON-RPC request with retry logic.
--- Does NOT retry on paymaster-specific errors (they're deterministic).
function PaymasterRpcClass:_requestWithRetry(method: string, params: any): any
	local lastErr: any = nil
	for attempt = 1, self._retryAttempts do
		local ok, result = pcall(function()
			return self:_rawRequest(method, params)
		end)
		if ok then
			return result
		end

		lastErr = result

		-- Don't retry on paymaster-specific RPC errors (deterministic)
		if typeof(result) == "table" and result._type == "RpcError" then
			local code = result.code
			if
				code == ErrorCodes.PAYMASTER_TOKEN_NOT_SUPPORTED.code
				or code == ErrorCodes.PAYMASTER_INVALID_SIGNATURE.code
				or code == ErrorCodes.PAYMASTER_MAX_AMOUNT_TOO_LOW.code
				or code == ErrorCodes.PAYMASTER_INVALID_DEPLOYMENT_DATA.code
				or code == ErrorCodes.PAYMASTER_EXECUTION_ERROR.code
				or code == ErrorCodes.PAYMASTER_INVALID_ADDRESS.code
				or code == ErrorCodes.PAYMASTER_CLASS_HASH_NOT_SUPPORTED.code
				or code == ErrorCodes.PAYMASTER_ERROR.code
			then
				error(result)
			end
		end

		-- Retry on transient errors with exponential backoff
		if attempt < self._retryAttempts then
			local delay = self._retryDelay * math.pow(2, attempt - 1)
			self._sleep(delay)
		end
	end

	error(lastErr)
end

--------------------------------------------------------------------------------
-- Public: fetch (raw RPC call, Promise-based)
--------------------------------------------------------------------------------

--- Raw paymaster RPC call. Returns a Promise that resolves to the JSON-RPC result.
function PaymasterRpcClass:fetch(method: string, params: any): any
	local Promise = self:_getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local ok, result = pcall(function()
			return self:_requestWithRetry(method, params)
		end)
		if ok then
			resolve(result)
		else
			reject(result)
		end
	end)
end

--------------------------------------------------------------------------------
-- Public SNIP-29 methods
--------------------------------------------------------------------------------

--- Check if the paymaster service is operational.
--- @return Promise<boolean> -- true if available, false otherwise
function PaymasterRpcClass:isAvailable(): any
	local Promise = self:_getPromise()

	return Promise.new(function(resolve: (any) -> (), _reject: (any) -> ())
		local ok, result = pcall(function()
			return self:_rawRequest("paymaster_isAvailable", {})
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

	local transaction: any = {
		type = "INVOKE",
		invoke = {
			user_address = userAddress,
			calls = formattedCalls,
		},
	}

	-- Include deployment data if provided (deploy-via-paymaster)
	local opts = options or {}
	if opts.deploymentData then
		local dd = opts.deploymentData
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

		transaction = {
			type = "DEPLOY_AND_INVOKE",
			deploy_and_invoke = {
				user_address = userAddress,
				calls = formattedCalls,
				deployment_data = deployData,
			},
		}
	elseif opts.accountClassHash then
		-- When accountClassHash is provided without full deploymentData, pass it
		-- in the deploy_and_invoke variant for the paymaster to use
		transaction.invoke.account_class_hash = opts.accountClassHash
	end

	-- Build SNIP-29 "parameters"
	local parameters: any = {
		version = "0x1",
		fee_mode = {
			mode = "default",
			gas_token = gasTokenAddress,
		},
	}

	-- Sponsored mode: gasTokenAddress "0x0" signals sponsored
	if gasTokenAddress == "0x0" or gasTokenAddress == "" then
		parameters.fee_mode = {
			mode = "sponsored",
		}
	end

	local rpcParams = {
		transaction,
		parameters,
	}

	return self:fetch("paymaster_buildTypedData", rpcParams):andThen(function(result: any)
		-- Normalize response
		local buildResult: BuildTypedDataResult = {
			typedData = result.typed_data or result.typedData,
			feeEstimate = nil,
			deploymentData = result.deployment_data or result.deploymentData,
		}

		-- Parse fee estimate if present
		local rawFee = result.fee_estimate or result.feeEstimate
		if rawFee then
			buildResult.feeEstimate = {
				gasTokenPrice = rawFee.gas_token_price or rawFee.gasTokenPrice,
				estimatedFeeInStrk = rawFee.estimated_fee_in_strk or rawFee.estimatedFeeInStrk,
				estimatedFeeInGasToken = rawFee.estimated_fee_in_gas_token or rawFee.estimatedFeeInGasToken,
				suggestedMaxFeeInStrk = rawFee.suggested_max_fee_in_strk or rawFee.suggestedMaxFeeInStrk,
				suggestedMaxFeeInGasToken = rawFee.suggested_max_fee_in_gas_token
					or rawFee.suggestedMaxFeeInGasToken,
			}
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
	-- Build the SNIP-29 "transaction" parameter for execution
	local transaction: any = {
		type = "INVOKE",
		invoke = {
			user_address = userAddress,
			typed_data = typedData,
			signature = signature,
		},
	}

	-- Include deployment data if provided
	local opts = options or {}
	if opts.deploymentData then
		local dd = opts.deploymentData
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

		transaction = {
			type = "DEPLOY_AND_INVOKE",
			deploy_and_invoke = {
				user_address = userAddress,
				typed_data = typedData,
				signature = signature,
				deployment_data = deployData,
			},
		}
	end

	-- Parameters
	local parameters: any = {
		version = "0x1",
		fee_mode = {
			mode = "sponsored",
		},
	}

	local rpcParams = {
		transaction,
		parameters,
	}

	return self:fetch("paymaster_executeTransaction", rpcParams):andThen(function(result: any)
		return {
			trackingId = result.tracking_id or result.trackingId,
			transactionHash = result.transaction_hash or result.transactionHash,
		} :: ExecuteResult
	end)
end

--- Map a tracking ID to the latest transaction hash and status.
--- @param trackingId -- the tracking ID from executeTransaction
--- @return Promise<TrackingResult>
function PaymasterRpcClass:trackingIdToLatestHash(trackingId: string): any
	return self:fetch("paymaster_trackingIdToLatestHash", { trackingId }):andThen(function(result: any)
		return {
			transactionHash = result.transaction_hash or result.transactionHash,
			status = result.status or "active",
		} :: TrackingResult
	end)
end

return PaymasterRpcClass
