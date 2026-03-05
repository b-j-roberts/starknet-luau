--!strict
-- JsonRpcClient: Shared JSON-RPC infrastructure for Starknet RPC and Paymaster clients
-- Provides: rate limiter, HTTP helpers, JSON encode/decode, raw request, retry logic, Promise loading
-- Both RpcProvider and PaymasterRpc delegate to this module for their core transport layer

local RpcTypes = require("./RpcTypes")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- Configuration for creating a JsonRpcClient
export type JsonRpcClientConfig = {
	nodeUrl: string,
	headers: { [string]: string }?,
	maxRequestsPerMinute: number?,
	retryAttempts: number?,
	retryDelay: number?,
	--- Optional: maps a decoded JSON-RPC error to an SDK error (then throws).
	--- If nil, the default handler throws StarknetError.rpc() with RPC_ERROR code.
	errorMapper: ((decoded: RpcTypes.JsonRpcError) -> never)?,
	--- Optional: determines whether to retry a caught error.
	--- Return true to retry, false to immediately re-throw.
	--- If nil, the default predicate skips retry on RpcError with code == RPC_ERROR.
	shouldRetry: ((err: any) -> boolean)?,
	--- Name used in error messages (e.g. "RpcProvider", "PaymasterRpc")
	clientName: string?,
	-- Internal overrides for testing (not part of public API)
	_httpRequest: ((request: RpcTypes.HttpRequest) -> RpcTypes.HttpResponse)?,
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

--- Rate limiter state
type RateLimiter = {
	tokens: number,
	maxTokens: number,
	refillRate: number, -- tokens per second
	lastRefill: number, -- os.clock() timestamp
}

--------------------------------------------------------------------------------
-- Rate limiter: token bucket algorithm
--------------------------------------------------------------------------------

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
-- JsonRpcClient class
--------------------------------------------------------------------------------

local JsonRpcClientClass = {}
JsonRpcClientClass.__index = JsonRpcClientClass

--- Create a new JsonRpcClient.
--- @param config -- JsonRpcClientConfig with nodeUrl and optional settings
function JsonRpcClientClass.new(config: JsonRpcClientConfig): any
	if not config.nodeUrl or config.nodeUrl == "" then
		local name = config.clientName or "JsonRpcClient"
		error(StarknetError.validation(`{name}: nodeUrl is required`, ErrorCodes.REQUIRED_FIELD.code))
	end

	local clockFn = config._clock or os.clock
	local maxRpm = config.maxRequestsPerMinute or 450

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
		_errorMapper = config.errorMapper,
		_shouldRetry = config.shouldRetry,
		_clientName = config.clientName or "JsonRpcClient",
	}, JsonRpcClientClass)

	-- Load Promise module (skip in test mode where _httpRequest is injected)
	if not config._httpRequest then
		local ok, promiseMod = pcall(function()
			return require("@Packages/Promise") :: any
		end)
		if ok then
			self._PromiseModule = promiseMod
		end
	end

	return self
end

--- Get the configured node URL
function JsonRpcClientClass:getNodeUrl(): string
	return self._nodeUrl
end

--- Get the Promise constructor
function JsonRpcClientClass:_getPromise(): any
	if self._PromiseModule then
		return self._PromiseModule
	end
	error(
		StarknetError.validation(
			`{self._clientName}: Promise module not available. In tests, set _PromiseModule on the instance.`,
			ErrorCodes.REQUIRED_FIELD.code
		)
	)
end

--- Perform an HTTP request (with injection point for testing)
function JsonRpcClientClass:_doHttpRequest(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
	if self._httpRequest then
		return self._httpRequest(request)
	end
	-- Default: use Roblox HttpService
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:RequestAsync(request)
end

--- JSON encode
function JsonRpcClientClass:_jsonEncode(value: any): string
	if self._httpRequest then
		-- In test/Lune environment, use the injected serde
		local serde = require("@lune/serde") :: any
		return serde.encode("json", value)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONEncode(value)
end

--- JSON decode
function JsonRpcClientClass:_jsonDecode(json: string): any
	if self._httpRequest then
		local serde = require("@lune/serde") :: any
		return serde.decode("json", json)
	end
	local HttpService = (game :: any):GetService("HttpService")
	return HttpService:JSONDecode(json)
end

--- Build HTTP headers with Content-Type and configured custom headers.
function JsonRpcClientClass:_buildHeaders(): { [string]: string }
	local headers: { [string]: string } = {
		["Content-Type"] = "application/json",
	}
	for k, v in self._headers do
		headers[k] = v
	end
	return headers
end

--- Spin-wait to acquire a rate limit token. Throws on timeout.
function JsonRpcClientClass:_acquireRateLimitToken()
	local maxWait = 10 -- seconds
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
end

--- Wait for rate limit token, then perform a single JSON-RPC request.
--- Uses the configured errorMapper for JSON-RPC error responses.
function JsonRpcClientClass:_rawRequest(method: string, params: any): any
	self:_acquireRateLimitToken()

	-- Build JSON-RPC request
	self._requestId += 1
	local rpcRequest: RpcTypes.JsonRpcRequest = {
		jsonrpc = "2.0",
		method = method,
		params = params,
		id = self._requestId,
	}

	local body = self:_jsonEncode(rpcRequest)
	local headers = self:_buildHeaders()

	local httpRequest: RpcTypes.HttpRequest = {
		Url = self._nodeUrl,
		Method = "POST",
		Headers = headers,
		Body = body,
	}

	local response = self:_doHttpRequest(httpRequest)

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

	if decoded.error then
		if self._errorMapper then
			-- Custom error mapping (e.g. paymaster SNIP-29 codes)
			self._errorMapper(decoded.error)
		else
			-- Default: throw as generic RPC error
			error(
				StarknetError.rpc(
					decoded.error.message or "Unknown RPC error",
					ErrorCodes.RPC_ERROR.code,
					decoded.error.code,
					decoded.error.data
				)
			)
		end
	end

	return decoded.result
end

--- Perform a JSON-RPC request with retry logic.
--- Uses the configured shouldRetry predicate to determine non-retryable errors.
function JsonRpcClientClass:_requestWithRetry(method: string, params: any): any
	local lastErr: any = nil
	for attempt = 1, self._retryAttempts do
		local ok, result = pcall(function()
			return self:_rawRequest(method, params)
		end)
		if ok then
			return result
		end

		lastErr = result

		-- Check if this error should not be retried
		if self._shouldRetry then
			if not self._shouldRetry(result) then
				error(result)
			end
		else
			-- Default: don't retry on RPC errors (they're deterministic)
			if
				typeof(result) == "table"
				and result._type == "RpcError"
				and result.code == ErrorCodes.RPC_ERROR.code
			then
				error(result)
			end
		end

		-- Retry on transient errors (network, rate limit) with exponential backoff
		if attempt < self._retryAttempts then
			local delay = self._retryDelay * math.pow(2, attempt - 1)
			self._sleep(delay)
		end
	end

	error(lastErr)
end

--- Raw RPC call returning a Promise.
--- This is the simple direct-path fetch (no queue, no cache).
function JsonRpcClientClass:fetch(method: string, params: any): any
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

--- Get the rate limiter state (for metrics).
function JsonRpcClientClass:getRateLimiter(): RateLimiter
	return self._rateLimiter
end

--- Expose tryAcquire for consumers that need batch-level rate limiting.
JsonRpcClientClass.tryAcquire = tryAcquire

return JsonRpcClientClass
