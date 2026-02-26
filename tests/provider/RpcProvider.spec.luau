--!strict
local serde = require("@lune/serde")

local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Mock RPC layer (pure function-level mock, no net.serve needed)
--------------------------------------------------------------------------------

--- Table of method handlers: method name -> function(params) -> result
local mockHandlers: { [string]: (params: any) -> any } = {}

--- Reset all handlers to defaults
local function resetHandlers()
	mockHandlers = {}

	mockHandlers["starknet_chainId"] = function(_params)
		return "0x534e5f5345504f4c4941" -- SN_SEPOLIA
	end

	mockHandlers["starknet_blockNumber"] = function(_params)
		return 123456
	end

	mockHandlers["starknet_specVersion"] = function(_params)
		return "0.7.1"
	end

	mockHandlers["starknet_getNonce"] = function(_params)
		return "0x5"
	end

	mockHandlers["starknet_call"] = function(_params)
		return { "0x1", "0x2" }
	end

	mockHandlers["starknet_estimateFee"] = function(_params)
		return {
			{
				gas_consumed = "0x1000",
				gas_price = "0x100",
				overall_fee = "0x100000",
				data_gas_consumed = "0x200",
				data_gas_price = "0x50",
				unit = "WEI",
			},
		}
	end

	mockHandlers["starknet_addInvokeTransaction"] = function(_params)
		return { transaction_hash = "0xabc123" }
	end

	mockHandlers["starknet_getTransactionReceipt"] = function(_params)
		return {
			transaction_hash = "0xabc123",
			actual_fee = { amount = "0x1234", unit = "WEI" },
			execution_status = "SUCCEEDED",
			finality_status = "ACCEPTED_ON_L2",
			block_hash = "0xblock1",
			block_number = 100,
			events = {},
		}
	end

	mockHandlers["starknet_getTransactionStatus"] = function(_params)
		return {
			finality_status = "ACCEPTED_ON_L2",
			execution_status = "SUCCEEDED",
		}
	end

	mockHandlers["starknet_getBlockWithTxHashes"] = function(_params)
		return {
			block_hash = "0xblock1",
			parent_hash = "0xblock0",
			block_number = 100,
			status = "ACCEPTED_ON_L2",
			timestamp = 1700000000,
			sequencer_address = "0xseq",
			transactions = { "0xtx1", "0xtx2" },
		}
	end

	mockHandlers["starknet_getClassHashAt"] = function(_params)
		return "0xclasshash123"
	end

	mockHandlers["starknet_getStorageAt"] = function(_params)
		return "0x42"
	end

	mockHandlers["starknet_getEvents"] = function(_params)
		return {
			events = {
				{
					from_address = "0xcontract1",
					keys = { "0xkey1" },
					data = { "0xdata1" },
					block_hash = "0xblock1",
					block_number = 100,
					transaction_hash = "0xtx1",
				},
			},
		}
	end
end

--- Track all requests received
local requestLog: { { method: string, params: any } } = {}

local function clearRequestLog()
	requestLog = {}
end

--- Create a mock HTTP function that processes requests through mockHandlers
local function createMockHttpRequest(): (request: RpcTypes.HttpRequest) -> RpcTypes.HttpResponse
	return function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
		local body = serde.decode("json", request.Body or "{}") :: any
		local method: string = body.method or ""
		local params: any = body.params
		local id: number = body.id or 0

		table.insert(requestLog, { method = method, params = params })

		local handler = mockHandlers[method]
		if handler then
			local ok, result = pcall(handler, params)
			if ok then
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						result = result,
					}),
					Success = true,
				}
			else
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						error = {
							code = -32000,
							message = tostring(result),
						},
					}),
					Success = true,
				}
			end
		end

		return {
			StatusCode = 200,
			Body = serde.encode("json", {
				jsonrpc = "2.0",
				id = id,
				error = {
					code = -32601,
					message = `Method not found: {method}`,
				},
			}),
			Success = true,
		}
	end
end

--------------------------------------------------------------------------------
-- Helper: create a provider with mock HTTP
--------------------------------------------------------------------------------

local function createTestProvider(overrides: { [string]: any }?): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockHttpRequest(),
		_sleep = function(_seconds: number) end, -- no-op for fast tests
		_clock = os.clock,
	}

	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local provider = RpcProvider.new(config)
	-- Inject MockPromise for Lune test environment
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

resetHandlers()

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("RpcProvider - constructor", function()
	it("creates a provider with a valid nodeUrl", function()
		local provider = createTestProvider()
		expect(provider):toBeTruthy()
	end)

	it("stores the configured nodeUrl", function()
		local provider = createTestProvider()
		expect(provider:getNodeUrl()):toBe("http://mock-rpc.test")
	end)

	it("errors on empty nodeUrl", function()
		expect(function()
			RpcProvider.new({ nodeUrl = "" } :: any)
		end):toThrowType("ValidationError")
	end)

	it("errors on missing nodeUrl", function()
		expect(function()
			RpcProvider.new({} :: any)
		end):toThrowType("ValidationError")
	end)

	it("accepts custom headers", function()
		local provider = createTestProvider({ headers = { ["X-API-Key"] = "test123" } })
		expect(provider):toBeTruthy()
	end)
end)

describe("RpcProvider - getChainId", function()
	it("returns the chain ID from the RPC node", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getChainId():expect()
		expect(result):toBe("0x534e5f5345504f4c4941")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getChainId():expect()
		expect(#requestLog >= 1):toBe(true)
		expect(requestLog[#requestLog].method):toBe("starknet_chainId")
	end)
end)

describe("RpcProvider - getBlockNumber", function()
	it("returns a number", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getBlockNumber():expect()
		expect(result):toBe(123456)
	end)
end)

describe("RpcProvider - getSpecVersion", function()
	it("returns the spec version string", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getSpecVersion():expect()
		expect(result):toBe("0.7.1")
	end)
end)

describe("RpcProvider - getNonce", function()
	it("returns the nonce for a contract address", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getNonce("0x1234"):expect()
		expect(result):toBe("0x5")
	end)

	it("sends the contract address in params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0xaddr1"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getNonce")
		expect(lastReq.params[2]):toBe("0xaddr1")
	end)

	it("uses latest block by default", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0xaddr1"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1]):toBe("latest")
	end)

	it("accepts a block hash as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0xaddr1", "0xblockhash"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1].block_hash):toBe("0xblockhash")
	end)

	it("accepts a block number as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0xaddr1", "100"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1].block_number):toBe(100)
	end)

	it("accepts pending as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0xaddr1", "pending"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1]):toBe("pending")
	end)
end)

describe("RpcProvider - call", function()
	it("returns an array of felt strings", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:call({
			contract_address = "0xcontract",
			entry_point_selector = "0xselector",
			calldata = { "0x1" },
		}):expect()
		expect(#result):toBe(2)
		expect(result[1]):toBe("0x1")
		expect(result[2]):toBe("0x2")
	end)

	it("sends correct params structure", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:call({
			contract_address = "0xcontract",
			entry_point_selector = "0xselector",
			calldata = { "0x1", "0x2" },
		}):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_call")
		expect(lastReq.params[1].contract_address):toBe("0xcontract")
		expect(lastReq.params[1].entry_point_selector):toBe("0xselector")
	end)
end)

describe("RpcProvider - estimateFee", function()
	it("returns an array of fee estimates", function()
		resetHandlers()
		local provider = createTestProvider()
		local tx: RpcTypes.InvokeTransactionV3 = {
			type = "INVOKE",
			version = "0x3",
			sender_address = "0xsender",
			calldata = { "0x1" },
			signature = { "0xr", "0xs" },
			nonce = "0x0",
			resource_bounds = {
				l1_gas = { max_amount = "0x100", max_price_per_unit = "0x10" },
				l2_gas = { max_amount = "0x0", max_price_per_unit = "0x0" },
			},
			tip = "0x0",
			paymaster_data = {},
			nonce_data_availability_mode = "L1",
			fee_data_availability_mode = "L1",
			account_deployment_data = {},
		}
		local result = provider:estimateFee({ tx }):expect()
		expect(#result):toBe(1)
		expect(result[1].overall_fee):toBe("0x100000")
	end)
end)

describe("RpcProvider - addInvokeTransaction", function()
	it("returns the transaction hash", function()
		resetHandlers()
		local provider = createTestProvider()
		local tx: RpcTypes.InvokeTransactionV3 = {
			type = "INVOKE",
			version = "0x3",
			sender_address = "0xsender",
			calldata = { "0x1" },
			signature = { "0xr", "0xs" },
			nonce = "0x0",
			resource_bounds = {
				l1_gas = { max_amount = "0x100", max_price_per_unit = "0x10" },
				l2_gas = { max_amount = "0x0", max_price_per_unit = "0x0" },
			},
			tip = "0x0",
			paymaster_data = {},
			nonce_data_availability_mode = "L1",
			fee_data_availability_mode = "L1",
			account_deployment_data = {},
		}
		local result = provider:addInvokeTransaction(tx):expect()
		expect(result):toBe("0xabc123")
	end)
end)

describe("RpcProvider - getTransactionReceipt", function()
	it("returns the full receipt", function()
		resetHandlers()
		local provider = createTestProvider()
		local receipt = provider:getTransactionReceipt("0xabc123"):expect()
		expect(receipt.transaction_hash):toBe("0xabc123")
		expect(receipt.execution_status):toBe("SUCCEEDED")
		expect(receipt.finality_status):toBe("ACCEPTED_ON_L2")
		expect(receipt.block_number):toBe(100)
	end)
end)

describe("RpcProvider - getTransactionStatus", function()
	it("returns finality and execution status", function()
		resetHandlers()
		local provider = createTestProvider()
		local status = provider:getTransactionStatus("0xabc123"):expect()
		expect(status.finality_status):toBe("ACCEPTED_ON_L2")
		expect(status.execution_status):toBe("SUCCEEDED")
	end)
end)

describe("RpcProvider - getBlockWithTxHashes", function()
	it("returns block with transaction hashes", function()
		resetHandlers()
		local provider = createTestProvider()
		local block = provider:getBlockWithTxHashes():expect()
		expect(block.block_hash):toBe("0xblock1")
		expect(block.block_number):toBe(100)
		expect(#block.transactions):toBe(2)
	end)
end)

describe("RpcProvider - getClassHashAt", function()
	it("returns the class hash for a contract", function()
		resetHandlers()
		local provider = createTestProvider()
		local classHash = provider:getClassHashAt("0xcontract"):expect()
		expect(classHash):toBe("0xclasshash123")
	end)

	it("sends correct params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClassHashAt("0xcontract", "latest"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getClassHashAt")
		expect(lastReq.params[2]):toBe("0xcontract")
	end)
end)

describe("RpcProvider - getStorageAt", function()
	it("returns the storage value", function()
		resetHandlers()
		local provider = createTestProvider()
		local value = provider:getStorageAt("0xcontract", "0xkey"):expect()
		expect(value):toBe("0x42")
	end)

	it("sends contract address, key, and block id in params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getStorageAt("0xcontract", "0xkey", "latest"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getStorageAt")
		expect(lastReq.params[1]):toBe("0xcontract")
		expect(lastReq.params[2]):toBe("0xkey")
	end)
end)

describe("RpcProvider - getEvents", function()
	it("returns events matching filter", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getEvents({
			address = "0xcontract1",
			chunk_size = 10,
		}):expect()
		expect(#result.events):toBe(1)
		expect(result.events[1].from_address):toBe("0xcontract1")
	end)
end)

describe("RpcProvider - fetch (raw)", function()
	it("returns raw result for any method", function()
		resetHandlers()
		mockHandlers["starknet_customMethod"] = function(_params)
			return { custom = "data" }
		end
		local provider = createTestProvider()
		local result = provider:fetch("starknet_customMethod", {}):expect()
		expect(result.custom):toBe("data")
	end)

	it("rejects on unknown method", function()
		resetHandlers()
		local provider = createTestProvider()
		local promise = provider:fetch("starknet_unknownMethod", {})
		expect(function()
			promise:expect()
		end):toThrow()
	end)
end)

describe("RpcProvider - JSON-RPC compliance", function()
	it("sends jsonrpc 2.0 in request", function()
		resetHandlers()
		local capturedBody: string? = nil
		local provider = createTestProvider({
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				capturedBody = request.Body
				return createMockHttpRequest()(request)
			end,
		})
		provider:getChainId():expect()
		expect(capturedBody ~= nil):toBe(true)
		local parsed = serde.decode("json", capturedBody :: string) :: any
		expect(parsed.jsonrpc):toBe("2.0")
		expect(type(parsed.id)):toBe("number")
		expect(parsed.method):toBe("starknet_chainId")
	end)

	it("increments request IDs", function()
		resetHandlers()
		local capturedIds: { number } = {}
		local provider = createTestProvider({
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				local parsed = serde.decode("json", request.Body :: string) :: any
				table.insert(capturedIds, parsed.id)
				return createMockHttpRequest()(request)
			end,
		})
		provider:getChainId():expect()
		provider:getBlockNumber():expect()
		expect(#capturedIds):toBe(2)
		expect(capturedIds[2] > capturedIds[1]):toBe(true)
	end)

	it("sends Content-Type application/json header", function()
		resetHandlers()
		local capturedHeaders: { [string]: string }? = nil
		local provider = createTestProvider({
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				capturedHeaders = request.Headers
				return createMockHttpRequest()(request)
			end,
		})
		provider:getChainId():expect()
		expect(capturedHeaders ~= nil):toBe(true)
		expect((capturedHeaders :: any)["Content-Type"]):toBe("application/json")
	end)

	it("includes custom headers in requests", function()
		resetHandlers()
		local capturedHeaders: { [string]: string }? = nil
		local provider = createTestProvider({
			headers = { ["X-API-Key"] = "mykey" },
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				capturedHeaders = request.Headers
				return createMockHttpRequest()(request)
			end,
		})
		provider:getChainId():expect()
		expect((capturedHeaders :: any)["X-API-Key"]):toBe("mykey")
	end)

	it("uses POST method", function()
		resetHandlers()
		local capturedMethod: string? = nil
		local provider = createTestProvider({
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				capturedMethod = request.Method
				return createMockHttpRequest()(request)
			end,
		})
		provider:getChainId():expect()
		expect(capturedMethod):toBe("POST")
	end)
end)

describe("RpcProvider - error handling", function()
	it("rejects with RPC_ERROR on JSON-RPC error response", function()
		resetHandlers()
		mockHandlers["starknet_chainId"] = function(_params)
			error("Contract not found")
		end
		local provider = createTestProvider()
		local promise = provider:getChainId()
		expect(function()
			promise:expect()
		end):toThrow()
	end)

	it("rejects with NETWORK_ERROR on HTTP failure", function()
		local provider = createTestProvider({
			_httpRequest = function(_request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				return {
					StatusCode = 500,
					Body = "Internal Server Error",
					Success = false,
				}
			end,
		})
		local promise = provider:getChainId()
		expect(function()
			promise:expect()
		end):toThrow()
	end)

	it("rejects when httpRequest throws", function()
		local provider = createTestProvider({
			_httpRequest = function(_request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				error("Connection refused")
			end,
		})
		local promise = provider:getChainId()
		expect(function()
			promise:expect()
		end):toThrow()
	end)

	it("includes RPC error code in rejection", function()
		resetHandlers()
		local provider = createTestProvider({
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				local body = serde.decode("json", request.Body :: string) :: any
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						error = { code = -32601, message = "Method not found" },
					}),
					Success = true,
				}
			end,
		})
		local promise = provider:getChainId()
		expect(function()
			promise:expect()
		end):toThrow()
	end)
end)

describe("RpcProvider - retry logic", function()
	it("retries on transient network errors", function()
		resetHandlers()
		local callCount = 0
		local provider = createTestProvider({
			retryAttempts = 3,
			retryDelay = 0.001,
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				callCount += 1
				if callCount < 3 then
					error("Connection timeout")
				end
				return createMockHttpRequest()(request)
			end,
		})
		local result = provider:getChainId():expect()
		expect(result):toBe("0x534e5f5345504f4c4941")
		expect(callCount):toBe(3)
	end)

	it("does not retry on RPC errors (deterministic)", function()
		resetHandlers()
		local httpCallCount = 0
		local provider = createTestProvider({
			retryAttempts = 3,
			retryDelay = 0.001,
			_httpRequest = function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				httpCallCount += 1
				local body = serde.decode("json", request.Body :: string) :: any
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						error = { code = 20, message = "Contract not found" },
					}),
					Success = true,
				}
			end,
		})
		expect(function()
			provider:getNonce("0x1"):expect()
		end):toThrow()
		-- RPC errors should not be retried
		expect(httpCallCount):toBe(1)
	end)

	it("gives up after max retry attempts", function()
		local callCount = 0
		local provider = createTestProvider({
			retryAttempts = 2,
			retryDelay = 0.001,
			_httpRequest = function(_request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				callCount += 1
				error("Network timeout")
			end,
		})
		expect(function()
			provider:getChainId():expect()
		end):toThrow()
		expect(callCount):toBe(2)
	end)

	it("uses exponential backoff between retries", function()
		local sleepTimes: { number } = {}
		local callCount = 0
		local provider = createTestProvider({
			retryAttempts = 3,
			retryDelay = 1,
			_sleep = function(seconds: number)
				table.insert(sleepTimes, seconds)
			end,
			_httpRequest = function(_request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
				callCount += 1
				if callCount <= 3 then
					error("Network error")
				end
				return { StatusCode = 200, Body = "{}", Success = true }
			end,
		})
		expect(function()
			provider:getChainId():expect()
		end):toThrow()
		-- Should have 2 sleep calls (between attempts 1-2 and 2-3)
		-- First delay: 1 * 2^0 = 1, Second delay: 1 * 2^1 = 2
		expect(#sleepTimes >= 2):toBe(true)
		expect(sleepTimes[1]):toBe(1)
		expect(sleepTimes[2]):toBe(2)
	end)
end)

describe("RpcProvider - rate limiting", function()
	it("allows requests under the rate limit", function()
		resetHandlers()
		local provider = createTestProvider({ maxRequestsPerMinute = 100 })
		for _ = 1, 5 do
			provider:getChainId():expect()
		end
		expect(true):toBe(true)
	end)

	it("rate limits when burst exceeds token count", function()
		resetHandlers()
		local sleepCallCount = 0
		local mockTime = 0
		local provider = createTestProvider({
			maxRequestsPerMinute = 2,
			_sleep = function(_seconds: number)
				sleepCallCount += 1
				mockTime += 31
				if sleepCallCount > 10 then
					error("Rate limit stuck in infinite loop")
				end
			end,
			_clock = function()
				return mockTime
			end,
		})
		-- First 2 requests consume all tokens
		provider:getChainId():expect()
		provider:getBlockNumber():expect()
		-- Third request triggers rate limiter
		provider:getSpecVersion():expect()
		expect(sleepCallCount > 0):toBe(true)
	end)

	it("refills tokens over time", function()
		resetHandlers()
		local mockTime = 0
		local provider = createTestProvider({
			maxRequestsPerMinute = 60, -- 1 token/sec
			_clock = function()
				return mockTime
			end,
		})
		-- Consume all 60 tokens
		for _ = 1, 60 do
			provider:getChainId():expect()
		end
		-- Advance time by 5 seconds (should refill 5 tokens)
		mockTime += 5
		for _ = 1, 5 do
			provider:getChainId():expect()
		end
		expect(true):toBe(true)
	end)
end)

describe("RpcProvider - waitForTransaction", function()
	it("returns receipt when transaction is confirmed", function()
		resetHandlers()
		local provider = createTestProvider()
		local receipt = provider:waitForTransaction("0xabc123", {
			retryInterval = 0.001,
			maxAttempts = 3,
		}):expect()
		expect(receipt.transaction_hash):toBe("0xabc123")
		expect(receipt.execution_status):toBe("SUCCEEDED")
	end)

	it("polls until transaction is confirmed", function()
		resetHandlers()
		local pollCount = 0
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			pollCount += 1
			if pollCount < 3 then
				return { finality_status = "RECEIVED" }
			end
			return { finality_status = "ACCEPTED_ON_L2", execution_status = "SUCCEEDED" }
		end
		local provider = createTestProvider()
		local receipt = provider:waitForTransaction("0xabc123", {
			retryInterval = 0.001,
			maxAttempts = 10,
		}):expect()
		expect(receipt.transaction_hash):toBe("0xabc123")
		expect(pollCount):toBe(3)
	end)

	it("rejects on reverted transaction", function()
		resetHandlers()
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return { finality_status = "ACCEPTED_ON_L2", execution_status = "REVERTED" }
		end
		mockHandlers["starknet_getTransactionReceipt"] = function(_params)
			return {
				transaction_hash = "0xabc123",
				actual_fee = { amount = "0x1234", unit = "WEI" },
				execution_status = "REVERTED",
				finality_status = "ACCEPTED_ON_L2",
				events = {},
				revert_reason = "Insufficient balance",
			}
		end
		local provider = createTestProvider()
		expect(function()
			provider:waitForTransaction("0xabc123", {
				retryInterval = 0.001,
				maxAttempts = 3,
			}):expect()
		end):toThrow()
	end)

	it("rejects on rejected transaction", function()
		resetHandlers()
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return { finality_status = "REJECTED" }
		end
		local provider = createTestProvider()
		expect(function()
			provider:waitForTransaction("0xabc123", {
				retryInterval = 0.001,
				maxAttempts = 3,
			}):expect()
		end):toThrow()
	end)

	it("rejects after max attempts timeout", function()
		resetHandlers()
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return { finality_status = "RECEIVED" }
		end
		local provider = createTestProvider()
		expect(function()
			provider:waitForTransaction("0xabc123", {
				retryInterval = 0.001,
				maxAttempts = 2,
			}):expect()
		end):toThrow()
	end)

	it("uses default options when none provided", function()
		resetHandlers()
		local provider = createTestProvider()
		local receipt = provider:waitForTransaction("0xabc123"):expect()
		expect(receipt.transaction_hash):toBe("0xabc123")
	end)
end)

describe("RpcProvider - Promise chaining", function()
	it("supports andThen chaining", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getChainId():andThen(function(chainId)
			return `chain:{chainId}`
		end):expect()
		expect(result):toBe("chain:0x534e5f5345504f4c4941")
	end)

	it("supports catch for error recovery", function()
		resetHandlers()
		mockHandlers["starknet_chainId"] = function(_params)
			error("Test error")
		end
		local provider = createTestProvider()
		local result = provider:getChainId():catch(function(_err)
			return "fallback"
		end):expect()
		expect(result):toBe("fallback")
	end)

	it("supports multi-step chaining", function()
		resetHandlers()
		local provider = createTestProvider()
		local result = provider:getChainId():andThen(function(chainId)
			return string.len(chainId)
		end):andThen(function(len)
			return len > 0
		end):expect()
		expect(result):toBe(true)
	end)
end)

describe("RpcProvider - block ID formatting", function()
	it("formats nil as latest", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0x1"):expect()
		expect(requestLog[#requestLog].params[1]):toBe("latest")
	end)

	it("formats 'latest' as string", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0x1", "latest"):expect()
		expect(requestLog[#requestLog].params[1]):toBe("latest")
	end)

	it("formats 'pending' as string", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0x1", "pending"):expect()
		expect(requestLog[#requestLog].params[1]):toBe("pending")
	end)

	it("formats hex string as block_hash object", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0x1", "0xabcdef"):expect()
		expect(requestLog[#requestLog].params[1].block_hash):toBe("0xabcdef")
	end)

	it("formats numeric string as block_number object", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getNonce("0x1", "42"):expect()
		expect(requestLog[#requestLog].params[1].block_number):toBe(42)
	end)
end)

--------------------------------------------------------------------------------
-- Queue integration tests
--------------------------------------------------------------------------------

describe("RpcProvider - queue enableQueue flag", function()
	it("creates a queue when enableQueue is true", function()
		resetHandlers()
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		expect(provider):toBeTruthy()
		-- Queue exists internally
		expect((provider :: any)._queue ~= nil):toBe(true)
	end)

	it("does not create a queue when enableQueue is false", function()
		resetHandlers()
		local provider = createTestProvider()
		expect((provider :: any)._queue == nil):toBe(true)
	end)

	it("routes requests through queue when enabled", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		local result = provider:getChainId():expect()
		expect(result):toBe("0x534e5f5345504f4c4941")
	end)

	it("all existing methods work with queue enabled", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		-- Verify multiple methods work
		expect(provider:getChainId():expect()):toBe("0x534e5f5345504f4c4941")
		expect(provider:getBlockNumber():expect()):toBe(123456)
		expect(provider:getSpecVersion():expect()):toBe("0.7.1")
		expect(provider:getNonce("0x1"):expect()):toBe("0x5")
	end)

	it("backward compat: without enableQueue all tests pass unchanged", function()
		resetHandlers()
		local provider = createTestProvider()
		expect(provider:getChainId():expect()):toBe("0x534e5f5345504f4c4941")
		expect(provider:getBlockNumber():expect()):toBe(123456)
	end)
end)

describe("RpcProvider - queue backpressure", function()
	it("rejects with QUEUE_FULL when queue is full", function()
		resetHandlers()
		local deferFns: { () -> () } = {}
		local provider = createTestProvider({
			enableQueue = true,
			queueConfig = { maxQueueDepth = 2 },
			_defer = function(fn: () -> ())
				table.insert(deferFns, fn)
			end,
		})

		-- Enqueue 2 items (deferred, not yet drained)
		provider:getChainId()
		provider:getBlockNumber()

		-- 3rd should be rejected (queue depth = 2)
		local promise3 = provider:getSpecVersion()
		-- MockPromise converts table error to string via .message, so check the string
		expect(function()
			promise3:expect()
		end):toThrowMatching(function(err: any)
			return type(err) == "string" and string.find(err, "queue full") ~= nil
		end)
	end)

	it("tracks dropped count on backpressure", function()
		resetHandlers()
		local deferFns: { () -> () } = {}
		local provider = createTestProvider({
			enableQueue = true,
			queueConfig = { maxQueueDepth = 1 },
			_defer = function(fn: () -> ())
				table.insert(deferFns, fn)
			end,
		})
		provider:getChainId()
		provider:getChainId() -- dropped
		local metrics = provider:getMetrics()
		expect(metrics.totalDropped):toBe(1)
	end)
end)

describe("RpcProvider - getMetrics", function()
	it("returns basic metrics when queue is disabled", function()
		resetHandlers()
		local provider = createTestProvider()
		local metrics = provider:getMetrics()
		expect(metrics.totalRequests):toBe(0)
		expect(metrics.totalCompleted):toBe(0)
		expect(metrics.totalFailed):toBe(0)
		expect(metrics.currentQueueDepth):toBe(0)
		expect(type(metrics.rateLimitTokens)):toBe("number")
		expect(type(metrics.rateLimitMax)):toBe("number")
	end)

	it("returns queue metrics when queue is enabled", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		provider:getChainId():expect()
		provider:getBlockNumber():expect()
		local metrics = provider:getMetrics()
		expect(metrics.totalRequests):toBe(2)
		expect(metrics.totalCompleted):toBe(2)
		expect(metrics.currentQueueDepth):toBe(0) -- drained
	end)

	it("tracks failed requests in metrics", function()
		resetHandlers()
		mockHandlers["starknet_chainId"] = function(_params)
			error("Test error")
		end
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		local p = provider:getChainId()
		p:catch(function() end) -- swallow error
		local metrics = provider:getMetrics()
		expect(metrics.totalRequests):toBe(1)
		expect(metrics.totalFailed):toBe(1)
	end)

	it("includes rate limiter info in metrics", function()
		resetHandlers()
		local provider = createTestProvider({
			maxRequestsPerMinute = 100,
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		local metrics = provider:getMetrics()
		expect(metrics.rateLimitMax):toBe(100)
	end)
end)

describe("RpcProvider - queue priority ordering", function()
	it("dispatches HIGH before NORMAL before LOW", function()
		resetHandlers()
		clearRequestLog()
		local deferFns: { () -> () } = {}
		local provider = createTestProvider({
			enableQueue = true,
			queueConfig = { enableBatching = false },
			_defer = function(fn: () -> ())
				table.insert(deferFns, fn)
			end,
		})

		-- Enqueue in reverse priority order
		provider:getEvents({ chunk_size = 10 }) -- LOW
		provider:getChainId() -- NORMAL
		provider:addInvokeTransaction({
			type = "INVOKE",
			version = "0x3",
			sender_address = "0xsender",
			calldata = { "0x1" },
			signature = { "0xr", "0xs" },
			nonce = "0x0",
			resource_bounds = {
				l1_gas = { max_amount = "0x100", max_price_per_unit = "0x10" },
				l2_gas = { max_amount = "0x0", max_price_per_unit = "0x0" },
			},
			tip = "0x0",
			paymaster_data = {},
			nonce_data_availability_mode = "L1",
			fee_data_availability_mode = "L1",
			account_deployment_data = {},
		}) -- HIGH

		-- Now drain all deferred callbacks
		for _, fn in deferFns do
			fn()
		end

		-- First request should be addInvokeTransaction (HIGH)
		expect(#requestLog >= 3):toBe(true)
		expect(requestLog[1].method):toBe("starknet_addInvokeTransaction")
	end)
end)
