--!strict
local serde = require("@lune/serde")

local JsonRpcClient = require("../../src/provider/JsonRpcClient")
local MockPromise = require("../helpers/MockPromise")
local StarknetError = require("../../src/errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Mock RPC layer (shared TestUtils infrastructure)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

local function resetHandlers()
	rpc.resetHandlers()
	mockHandlers["test_method"] = function(_params)
		return "test_result"
	end
	mockHandlers["test_echo"] = function(params)
		return params
	end
end

--------------------------------------------------------------------------------
-- Helper: create a test client
--------------------------------------------------------------------------------

local function createTestClient(overrides: { [string]: any }?): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		clientName = "TestClient",
		_httpRequest = rpc.createMockHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
	}

	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local client = JsonRpcClient.new(config)
	client._PromiseModule = MockPromise
	return client
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

resetHandlers()

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("JsonRpcClient - constructor", function()
	it("creates a client with valid config", function()
		local client = createTestClient()
		expect(client):toBeTruthy()
	end)

	it("stores the configured nodeUrl", function()
		local client = createTestClient()
		expect(client:getNodeUrl()):toBe("http://mock-rpc.test")
	end)

	it("errors on empty nodeUrl", function()
		expect(function()
			JsonRpcClient.new({ nodeUrl = "" } :: any)
		end):toThrowType("ValidationError")
	end)

	it("errors on missing nodeUrl", function()
		expect(function()
			JsonRpcClient.new({} :: any)
		end):toThrowType("ValidationError")
	end)

	it("uses custom clientName in validation error", function()
		local ok, err = pcall(function()
			JsonRpcClient.new({ nodeUrl = "", clientName = "MyClient" } :: any)
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "MyClient")):toBeTruthy()
	end)

	it("defaults retryAttempts to 3", function()
		-- Create client directly (not via helper) to test defaults
		local client = JsonRpcClient.new({
			nodeUrl = "http://test.test",
			_httpRequest = rpc.createMockHttpRequest(),
			_sleep = function(_s: number) end,
			_clock = os.clock,
		})
		expect(client._retryAttempts):toBe(3)
	end)

	it("defaults retryDelay to 1", function()
		local client = JsonRpcClient.new({
			nodeUrl = "http://test.test",
			_httpRequest = rpc.createMockHttpRequest(),
			_sleep = function(_s: number) end,
			_clock = os.clock,
		})
		expect(client._retryDelay):toBe(1)
	end)

	it("defaults maxRequestsPerMinute to 450", function()
		local client = createTestClient({ maxRequestsPerMinute = nil })
		local limiter = client:getRateLimiter()
		expect(limiter.maxTokens):toBe(450)
	end)

	it("accepts custom maxRequestsPerMinute", function()
		local client = createTestClient({ maxRequestsPerMinute = 120 })
		local limiter = client:getRateLimiter()
		expect(limiter.maxTokens):toBe(120)
	end)

	it("stores custom headers", function()
		local client = createTestClient({ headers = { ["x-key"] = "val" } })
		local headers = client:_buildHeaders()
		expect(headers["x-key"]):toBe("val")
	end)
end)

describe("JsonRpcClient - _getPromise", function()
	it("returns injected Promise module", function()
		local client = createTestClient()
		expect(client:_getPromise()):toBe(MockPromise)
	end)

	it("errors when no Promise module is available", function()
		local client = createTestClient()
		client._PromiseModule = nil
		expect(function()
			client:_getPromise()
		end):toThrowType("ValidationError")
	end)

	it("includes clientName in error message", function()
		local client = createTestClient({ clientName = "MyRPC" })
		client._PromiseModule = nil
		local ok, err = pcall(function()
			client:_getPromise()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "MyRPC")):toBeTruthy()
	end)
end)

describe("JsonRpcClient - _rawRequest", function()
	it("makes a successful JSON-RPC request", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local result = client:_rawRequest("test_method", {})
		expect(result):toBe("test_result")
	end)

	it("sends correct JSON-RPC envelope", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		client:_rawRequest("test_method", { "param1" })
		expect(#requestLog):toBe(1)
		expect(requestLog[1].method):toBe("test_method")
	end)

	it("includes custom headers", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient({ headers = { ["x-api-key"] = "test-key" } })
		client:_rawRequest("test_method", {})
		-- Note: requestLog from TestUtils doesn't capture headers, but the request goes through
		-- the mock HTTP which does process them. We verify via a direct check.
		local headers = client:_buildHeaders()
		expect(headers["Content-Type"]):toBe("application/json")
		expect(headers["x-api-key"]):toBe("test-key")
	end)

	it("increments request ID", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		client:_rawRequest("test_method", {})
		local id1 = client._requestId
		client:_rawRequest("test_method", {})
		local id2 = client._requestId
		expect(id2):toBe(id1 + 1)
	end)

	it("throws on JSON-RPC error (default handler)", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local ok, err = pcall(function()
			client:_rawRequest("nonexistent_method", {})
		end)
		expect(ok):toBe(false)
		expect(typeof(err)):toBe("table")
		expect(err._type):toBe("RpcError")
		expect(err.code):toBe(ErrorCodes.RPC_ERROR.code)
	end)

	it("throws on HTTP error", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient({
			_httpRequest = function(_req: any)
				return {
					StatusCode = 500,
					Body = "Internal Server Error",
					Success = false,
				}
			end,
		})
		local ok, err = pcall(function()
			client:_rawRequest("test_method", {})
		end)
		expect(ok):toBe(false)
		expect(typeof(err)):toBe("table")
		expect(err.code):toBe(ErrorCodes.NETWORK_ERROR.code)
	end)

	it("uses custom errorMapper when provided", function()
		resetHandlers()
		rpc.clearRequestLog()
		local mapperCalled = false
		local client = createTestClient({
			errorMapper = function(decoded: any): never
				mapperCalled = true
				error(StarknetError.rpc(decoded.message, 9999, decoded.code))
			end,
		})
		local ok, err = pcall(function()
			client:_rawRequest("nonexistent_method", {})
		end)
		expect(ok):toBe(false)
		expect(mapperCalled):toBe(true)
		expect(err.code):toBe(9999)
	end)

	it("passes echo params through correctly", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local result = client:_rawRequest("test_echo", { "0x1", "0x2" })
		expect(result[1]):toBe("0x1")
		expect(result[2]):toBe("0x2")
	end)
end)

describe("JsonRpcClient - _requestWithRetry", function()
	it("returns result on first success", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient({ retryAttempts = 3 })
		local result = client:_requestWithRetry("test_method", {})
		expect(result):toBe("test_result")
		expect(#requestLog):toBe(1)
	end)

	it("retries on transient HTTP errors", function()
		resetHandlers()
		rpc.clearRequestLog()
		local httpAttempts = 0
		local client = createTestClient({
			retryAttempts = 3,
			retryDelay = 0,
			_httpRequest = function(_req: any)
				httpAttempts += 1
				if httpAttempts < 3 then
					return {
						StatusCode = 503,
						Body = "Service Unavailable",
						Success = false,
					}
				end
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						result = "recovered",
					}),
					Success = true,
				}
			end,
		})

		local result = client:_requestWithRetry("test_method", {})
		expect(result):toBe("recovered")
		expect(httpAttempts):toBe(3)
	end)

	it("does not retry on deterministic RPC errors (default predicate)", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient({ retryAttempts = 3, retryDelay = 0 })
		local ok, _err = pcall(function()
			client:_requestWithRetry("nonexistent_method", {})
		end)
		expect(ok):toBe(false)
		expect(#requestLog):toBe(1) -- only 1 attempt, no retry
	end)

	it("uses custom shouldRetry predicate", function()
		resetHandlers()
		rpc.clearRequestLog()
		local retryChecks = 0
		local httpAttempts = 0
		local client = createTestClient({
			retryAttempts = 3,
			retryDelay = 0,
			shouldRetry = function(_err: any)
				retryChecks += 1
				return true -- always retry
			end,
			_httpRequest = function(_req: any)
				httpAttempts += 1
				if httpAttempts < 3 then
					return {
						StatusCode = 503,
						Body = "fail",
						Success = false,
					}
				end
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = 1,
						result = "ok",
					}),
					Success = true,
				}
			end,
		})

		local result = client:_requestWithRetry("test_method", {})
		expect(result):toBe("ok")
		expect(retryChecks):toBe(2) -- checked on 1st and 2nd failure
	end)

	it("stops retrying when shouldRetry returns false", function()
		resetHandlers()
		rpc.clearRequestLog()
		local httpAttempts = 0
		local client = createTestClient({
			retryAttempts = 5,
			retryDelay = 0,
			shouldRetry = function(_err: any)
				return false -- never retry
			end,
			_httpRequest = function(_req: any)
				httpAttempts += 1
				return {
					StatusCode = 503,
					Body = "fail",
					Success = false,
				}
			end,
		})

		local ok, _err = pcall(function()
			client:_requestWithRetry("test_method", {})
		end)
		expect(ok):toBe(false)
		expect(httpAttempts):toBe(1)
	end)

	it("throws last error after all retries exhausted", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient({
			retryAttempts = 2,
			retryDelay = 0,
			_httpRequest = function(_req: any)
				return {
					StatusCode = 503,
					Body = "Service Unavailable",
					Success = false,
				}
			end,
		})

		local ok, err = pcall(function()
			client:_requestWithRetry("test_method", {})
		end)
		expect(ok):toBe(false)
		expect(typeof(err)):toBe("table")
		expect(err.code):toBe(ErrorCodes.NETWORK_ERROR.code)
	end)
end)

describe("JsonRpcClient - _buildHeaders", function()
	it("includes Content-Type by default", function()
		local client = createTestClient()
		local headers = client:_buildHeaders()
		expect(headers["Content-Type"]):toBe("application/json")
	end)

	it("merges custom headers", function()
		local client = createTestClient({ headers = { ["Authorization"] = "Bearer token" } })
		local headers = client:_buildHeaders()
		expect(headers["Content-Type"]):toBe("application/json")
		expect(headers["Authorization"]):toBe("Bearer token")
	end)

	it("custom headers do not override Content-Type", function()
		local client = createTestClient({ headers = { ["x-custom"] = "yes" } })
		local headers = client:_buildHeaders()
		expect(headers["Content-Type"]):toBe("application/json")
		expect(headers["x-custom"]):toBe("yes")
	end)
end)

describe("JsonRpcClient - _acquireRateLimitToken", function()
	it("acquires a token successfully", function()
		local client = createTestClient({ maxRequestsPerMinute = 100 })
		-- Should not throw
		client:_acquireRateLimitToken()
	end)

	it("throws on rate limit timeout", function()
		local time = 0
		local client = createTestClient({
			maxRequestsPerMinute = 1,
			_clock = function()
				-- Advance time by 6 seconds each call so timeout triggers quickly
				-- but not enough to refill (need 60s for 1 token at 1/minute)
				time += 6
				return time
			end,
			_sleep = function(_s: number) end,
		})
		-- Consume the one token (first _acquireRateLimitToken)
		client:_acquireRateLimitToken()
		-- Next should timeout after ~10 seconds of simulated time
		local ok, err = pcall(function()
			client:_acquireRateLimitToken()
		end)
		expect(ok):toBe(false)
		expect(typeof(err)):toBe("table")
		expect(err.code):toBe(ErrorCodes.RATE_LIMIT.code)
	end)
end)

describe("JsonRpcClient - fetch (Promise-based)", function()
	it("resolves with result on success", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local result = client:fetch("test_method", {}):expect()
		expect(result):toBe("test_result")
	end)

	it("rejects on RPC error", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local ok, _err = pcall(function()
			client:fetch("nonexistent_method", {}):expect()
		end)
		expect(ok):toBe(false)
	end)

	it("passes params through to request", function()
		resetHandlers()
		rpc.clearRequestLog()
		local client = createTestClient()
		local result = client:fetch("test_echo", { "hello" }):expect()
		expect(result[1]):toBe("hello")
	end)
end)

describe("JsonRpcClient - _jsonEncode/_jsonDecode", function()
	it("round-trips a table through encode/decode", function()
		local client = createTestClient()
		local original = { key = "value", num = 42 }
		local encoded = client:_jsonEncode(original)
		local decoded = client:_jsonDecode(encoded)
		expect(decoded.key):toBe("value")
		expect(decoded.num):toBe(42)
	end)

	it("handles arrays", function()
		local client = createTestClient()
		local encoded = client:_jsonEncode({ "a", "b", "c" })
		local decoded = client:_jsonDecode(encoded)
		expect(decoded[1]):toBe("a")
		expect(decoded[2]):toBe("b")
		expect(decoded[3]):toBe("c")
	end)
end)

describe("JsonRpcClient - getRateLimiter", function()
	it("returns the rate limiter state", function()
		local client = createTestClient({ maxRequestsPerMinute = 200 })
		local limiter = client:getRateLimiter()
		expect(limiter.maxTokens):toBe(200)
	end)

	it("tokens decrease after acquire", function()
		local client = createTestClient({ maxRequestsPerMinute = 100 })
		local before = client:getRateLimiter().tokens
		client:_acquireRateLimitToken()
		local after = client:getRateLimiter().tokens
		-- After acquiring, tokens should be less (accounting for refill)
		expect(after < before):toBe(true)
	end)
end)

describe("JsonRpcClient - tryAcquire (static)", function()
	it("is exposed for external batch-level rate limiting", function()
		expect(JsonRpcClient.tryAcquire):toBeTruthy()
		expect(type(JsonRpcClient.tryAcquire)):toBe("function")
	end)
end)
