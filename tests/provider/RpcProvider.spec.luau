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

	mockHandlers["starknet_getBlockWithTxs"] = function(_params)
		return {
			block_hash = "0xblock1",
			parent_hash = "0xblock0",
			block_number = 100,
			status = "ACCEPTED_ON_L2",
			timestamp = 1700000000,
			sequencer_address = "0xseq",
			transactions = {
				{
					transaction_hash = "0xtx1",
					type = "INVOKE",
					version = "0x3",
					sender_address = "0xsender1",
					calldata = { "0x1", "0x2" },
					signature = { "0xr", "0xs" },
					nonce = "0x0",
				},
				{
					transaction_hash = "0xtx2",
					type = "INVOKE",
					version = "0x3",
					sender_address = "0xsender2",
					calldata = { "0x3" },
					signature = { "0xr2", "0xs2" },
					nonce = "0x1",
				},
			},
		}
	end

	mockHandlers["starknet_getBlockWithReceipts"] = function(_params)
		return {
			block_hash = "0xblock1",
			parent_hash = "0xblock0",
			block_number = 100,
			status = "ACCEPTED_ON_L2",
			timestamp = 1700000000,
			sequencer_address = "0xseq",
			transactions = {
				{
					transaction = {
						transaction_hash = "0xtx1",
						type = "INVOKE",
						version = "0x3",
						sender_address = "0xsender1",
					},
					receipt = {
						transaction_hash = "0xtx1",
						actual_fee = { amount = "0x1234", unit = "WEI" },
						execution_status = "SUCCEEDED",
						finality_status = "ACCEPTED_ON_L2",
						events = {},
					},
				},
			},
		}
	end

	mockHandlers["starknet_getTransactionByHash"] = function(_params)
		return {
			transaction_hash = "0xtx1",
			type = "INVOKE",
			version = "0x3",
			sender_address = "0xsender1",
			calldata = { "0x1", "0x2" },
			signature = { "0xr", "0xs" },
			nonce = "0x5",
		}
	end

	mockHandlers["starknet_getClass"] = function(_params)
		return {
			sierra_program = { "0x1", "0x2", "0x3" },
			contract_class_version = "0.1.0",
			entry_points_by_type = {
				EXTERNAL = { { selector = "0xsel1", function_idx = 0 } },
				L1_HANDLER = {},
				CONSTRUCTOR = {},
			},
			abi = '[{"type":"function","name":"transfer"}]',
		}
	end

	mockHandlers["starknet_getClassAt"] = function(_params)
		return {
			sierra_program = { "0xa", "0xb" },
			contract_class_version = "0.1.0",
			entry_points_by_type = {
				EXTERNAL = {},
				L1_HANDLER = {},
				CONSTRUCTOR = {},
			},
			abi = '[{"type":"function","name":"balance_of"}]',
		}
	end

	mockHandlers["starknet_estimateMessageFee"] = function(_params)
		return {
			gas_consumed = "0x2000",
			gas_price = "0x200",
			overall_fee = "0x400000",
			data_gas_consumed = "0x100",
			data_gas_price = "0x50",
			unit = "WEI",
		}
	end

	mockHandlers["starknet_syncing"] = function(_params)
		return {
			starting_block_hash = "0xstart",
			starting_block_num = 0,
			current_block_hash = "0xcurrent",
			current_block_num = 50000,
			highest_block_hash = "0xhighest",
			highest_block_num = 100000,
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

--------------------------------------------------------------------------------
-- Tests: Response caching
--------------------------------------------------------------------------------

describe("RpcProvider - cache enablement", function()
	it("cache is disabled by default", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		-- Two calls should both hit network
		provider:getChainId():expect()
		provider:getChainId():expect()
		expect(#requestLog):toBe(2)
	end)

	it("cache can be enabled via enableCache", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getChainId():expect()
		provider:getChainId():expect()
		-- Second call should be served from cache
		expect(#requestLog):toBe(1)
	end)

	it("flushCache is safe when cache is disabled", function()
		resetHandlers()
		local provider = createTestProvider()
		-- Should not error
		provider:flushCache()
	end)
end)

describe("RpcProvider - cache hit/miss", function()
	it("second getChainId call is served from cache (no HTTP)", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local r1 = provider:getChainId():expect()
		local r2 = provider:getChainId():expect()
		expect(r1):toBe(r2)
		expect(#requestLog):toBe(1)
	end)

	it("second getSpecVersion call is served from cache", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local r1 = provider:getSpecVersion():expect()
		local r2 = provider:getSpecVersion():expect()
		expect(r1):toBe(r2)
		expect(#requestLog):toBe(1)
	end)

	it("second getClassHashAt call is served from cache", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local r1 = provider:getClassHashAt("0xaddr1"):expect()
		local r2 = provider:getClassHashAt("0xaddr1"):expect()
		expect(r1):toBe(r2)
		expect(#requestLog):toBe(1)
	end)

	it("different params produce separate cache entries", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getClassHashAt("0xaddr1"):expect()
		provider:getClassHashAt("0xaddr2"):expect()
		-- Different params = different cache keys = 2 HTTP calls
		expect(#requestLog):toBe(2)
	end)

	it("getStorageAt is cached with 30s default TTL", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		expect(#requestLog):toBe(1)
	end)

	it("call is cached with 30s default TTL", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local request = {
			contract_address = "0xaddr",
			entry_point_selector = "0xsel",
			calldata = { "0x1" },
		}
		provider:call(request):expect()
		provider:call(request):expect()
		expect(#requestLog):toBe(1)
	end)

	it("getBlockNumber is cached briefly", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getBlockNumber():expect()
		provider:getBlockNumber():expect()
		-- Second call triggers cache hit for the raw fetch, but still goes through andThen
		-- The raw starknet_blockNumber call should only happen once
		expect(#requestLog):toBe(1)
	end)
end)

describe("RpcProvider - uncacheable methods", function()
	it("getNonce is never cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getNonce("0xaddr"):expect()
		provider:getNonce("0xaddr"):expect()
		expect(#requestLog):toBe(2)
	end)

	it("estimateFee is never cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local tx = {
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
		provider:estimateFee({ tx }):expect()
		provider:estimateFee({ tx }):expect()
		expect(#requestLog):toBe(2)
	end)

	it("addInvokeTransaction is never cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local tx = {
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
		provider:addInvokeTransaction(tx):expect()
		provider:addInvokeTransaction(tx):expect()
		expect(#requestLog):toBe(2)
	end)

	it("getTransactionReceipt is never cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getTransactionReceipt("0xtx1"):expect()
		provider:getTransactionReceipt("0xtx1"):expect()
		expect(#requestLog):toBe(2)
	end)

	it("getTransactionStatus is never cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getTransactionStatus("0xtx1"):expect()
		provider:getTransactionStatus("0xtx1"):expect()
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - cache TTL expiration", function()
	it("storage cache expires after TTL", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		local provider = createTestProvider({
			enableCache = true,
			cacheConfig = { storageTTL = 5 },
			_clock = function()
				return currentTime
			end,
		})
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		expect(#requestLog):toBe(1)
		-- Advance past TTL
		currentTime = 5
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		expect(#requestLog):toBe(2)
	end)

	it("chainId cache never expires (TTL=0)", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getChainId():expect()
		currentTime = 999999
		provider:getChainId():expect()
		expect(#requestLog):toBe(1)
	end)

	it("custom TTL overrides default", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		local provider = createTestProvider({
			enableCache = true,
			cacheConfig = { callTTL = 2 },
			_clock = function()
				return currentTime
			end,
		})
		local request = {
			contract_address = "0xaddr",
			entry_point_selector = "0xsel",
			calldata = {},
		}
		provider:call(request):expect()
		currentTime = 1
		provider:call(request):expect() -- still cached
		expect(#requestLog):toBe(1)
		currentTime = 2
		provider:call(request):expect() -- expired
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - cache bypass", function()
	it("bypassCache skips cache lookup", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getChainId():expect() -- populates cache
		expect(#requestLog):toBe(1)
		-- Bypass cache — should hit network again
		provider:fetch("starknet_chainId", {}, { bypassCache = true }):expect()
		expect(#requestLog):toBe(2)
	end)

	it("bypassCache does not store result in cache", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		-- First call with bypass — should not populate cache
		provider:fetch("starknet_chainId", {}, { bypassCache = true }):expect()
		-- Second normal call — should still miss cache
		provider:getChainId():expect()
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - block-based cache invalidation", function()
	it("new block number invalidates storage cache", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end

		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		-- Cache storage
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		expect(#requestLog):toBe(1)

		-- First getBlockNumber — sets baseline, no invalidation
		provider:getBlockNumber():expect()
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		expect(#requestLog):toBe(2) -- blockNumber was a miss, storage was a hit

		-- Advance past blockNumber TTL so next getBlockNumber fetches from network
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect()
		-- This should invalidate storage cache (block changed from 100 to 101)
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		-- blockNumber(network, cached expired) + storage(network, invalidated) = 2 more
		expect(#requestLog):toBe(4)
	end)

	it("new block does NOT invalidate chainId cache", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end

		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getChainId():expect()
		expect(#requestLog):toBe(1)

		-- Set baseline block
		provider:getBlockNumber():expect()

		-- Advance past blockNumber TTL, new block
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect()

		-- chainId should still be cached
		provider:getChainId():expect()
		local chainIdRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_chainId" then
				chainIdRequests += 1
			end
		end
		expect(chainIdRequests):toBe(1)
	end)

	it("new block does NOT invalidate classHash cache", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end

		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getClassHashAt("0xaddr"):expect()
		expect(#requestLog):toBe(1)

		-- Set baseline block
		provider:getBlockNumber():expect()

		-- Advance past blockNumber TTL, new block
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect()

		provider:getClassHashAt("0xaddr"):expect()
		local classHashRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getClassHashAt" then
				classHashRequests += 1
			end
		end
		expect(classHashRequests):toBe(1)
	end)

	it("new block invalidates call cache", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end

		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		local request = {
			contract_address = "0xaddr",
			entry_point_selector = "0xsel",
			calldata = {},
		}
		provider:call(request):expect()

		-- Set baseline block
		provider:getBlockNumber():expect()

		-- Advance past blockNumber TTL, new block
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect()

		provider:call(request):expect()
		local callRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_call" then
				callRequests += 1
			end
		end
		expect(callRequests):toBe(2) -- original + after invalidation
	end)

	it("same block number does not invalidate", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return 100
		end

		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		provider:getBlockNumber():expect() -- sets baseline to 100

		-- Expire blockNumber TTL, but same block
		currentTime = 11
		provider:getBlockNumber():expect()
		-- Storage should still be cached (same block, no invalidation)
		provider:getStorageAt("0xaddr", "0xkey"):expect()
		local storageRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getStorageAt" then
				storageRequests += 1
			end
		end
		expect(storageRequests):toBe(1)
	end)
end)

describe("RpcProvider - flushCache", function()
	it("clears all cached entries", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getChainId():expect()
		provider:getClassHashAt("0xaddr"):expect()
		expect(#requestLog):toBe(2)

		provider:flushCache()

		-- Both should miss cache now
		provider:getChainId():expect()
		provider:getClassHashAt("0xaddr"):expect()
		expect(#requestLog):toBe(4)
	end)
end)

describe("RpcProvider - cache metrics", function()
	it("reports cache metrics when cache is enabled", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })

		local m0 = provider:getMetrics()
		expect(m0.cacheHits):toBe(0)
		expect(m0.cacheMisses):toBe(0)
		expect(m0.cacheSize):toBe(0)

		provider:getChainId():expect() -- miss + store
		local m1 = provider:getMetrics()
		expect(m1.cacheMisses):toBe(1)
		expect(m1.cacheSize):toBe(1)

		provider:getChainId():expect() -- hit
		local m2 = provider:getMetrics()
		expect(m2.cacheHits):toBe(1)
		expect(m2.cacheSize):toBe(1)
	end)

	it("reports zero cache metrics when cache is disabled", function()
		resetHandlers()
		local provider = createTestProvider()
		local m = provider:getMetrics()
		expect(m.cacheHits):toBe(0)
		expect(m.cacheMisses):toBe(0)
		expect(m.cacheEvictions):toBe(0)
		expect(m.cacheSize):toBe(0)
	end)

	it("cache evictions are tracked in metrics", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({
			enableCache = true,
			cacheConfig = { maxEntries = 1 },
		})

		provider:getChainId():expect() -- stores chainId
		provider:getSpecVersion():expect() -- evicts chainId, stores specVersion
		local m = provider:getMetrics()
		expect(m.cacheEvictions):toBe(1)
		expect(m.cacheSize):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Expanded RPC method coverage (Phase 2.10)
--------------------------------------------------------------------------------

describe("RpcProvider - getBlockWithTxs", function()
	it("returns block with full transaction objects", function()
		resetHandlers()
		local provider = createTestProvider()
		local block = provider:getBlockWithTxs():expect()
		expect(block.block_hash):toBe("0xblock1")
		expect(block.block_number):toBe(100)
		expect(#block.transactions):toBe(2)
		expect(block.transactions[1].transaction_hash):toBe("0xtx1")
		expect(block.transactions[1].type):toBe("INVOKE")
		expect(block.transactions[1].sender_address):toBe("0xsender1")
		expect(block.transactions[2].transaction_hash):toBe("0xtx2")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithTxs():expect()
		expect(requestLog[#requestLog].method):toBe("starknet_getBlockWithTxs")
	end)

	it("uses latest block by default", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithTxs():expect()
		expect(requestLog[#requestLog].params[1]):toBe("latest")
	end)

	it("accepts block hash as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithTxs("0xblockhash"):expect()
		expect(requestLog[#requestLog].params[1].block_hash):toBe("0xblockhash")
	end)

	it("accepts block number as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithTxs("42"):expect()
		expect(requestLog[#requestLog].params[1].block_number):toBe(42)
	end)

	it("accepts pending as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithTxs("pending"):expect()
		expect(requestLog[#requestLog].params[1]):toBe("pending")
	end)

	it("is cached with blockTTL", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getBlockWithTxs():expect()
		provider:getBlockWithTxs():expect()
		expect(#requestLog):toBe(1)
	end)

	it("is invalidated on new block", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end
		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getBlockWithTxs():expect()
		provider:getBlockNumber():expect() -- baseline
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect() -- triggers invalidation
		provider:getBlockWithTxs():expect()
		local blockTxsRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getBlockWithTxs" then
				blockTxsRequests += 1
			end
		end
		expect(blockTxsRequests):toBe(2)
	end)
end)

describe("RpcProvider - getBlockWithReceipts", function()
	it("returns block with transaction receipts", function()
		resetHandlers()
		local provider = createTestProvider()
		local block = provider:getBlockWithReceipts():expect()
		expect(block.block_hash):toBe("0xblock1")
		expect(block.block_number):toBe(100)
		expect(#block.transactions):toBe(1)
		expect(block.transactions[1].transaction.transaction_hash):toBe("0xtx1")
		expect(block.transactions[1].receipt.execution_status):toBe("SUCCEEDED")
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithReceipts():expect()
		expect(requestLog[#requestLog].method):toBe("starknet_getBlockWithReceipts")
	end)

	it("uses latest block by default", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithReceipts():expect()
		expect(requestLog[#requestLog].params[1]):toBe("latest")
	end)

	it("accepts block hash as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getBlockWithReceipts("0xblockhash"):expect()
		expect(requestLog[#requestLog].params[1].block_hash):toBe("0xblockhash")
	end)

	it("is cached with blockTTL", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getBlockWithReceipts():expect()
		provider:getBlockWithReceipts():expect()
		expect(#requestLog):toBe(1)
	end)

	it("is invalidated on new block", function()
		resetHandlers()
		clearRequestLog()
		local blockNum = 100
		local currentTime = 0
		mockHandlers["starknet_blockNumber"] = function(_params)
			return blockNum
		end
		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getBlockWithReceipts():expect()
		provider:getBlockNumber():expect()
		currentTime = 11
		blockNum = 101
		provider:getBlockNumber():expect()
		provider:getBlockWithReceipts():expect()
		local methodRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getBlockWithReceipts" then
				methodRequests += 1
			end
		end
		expect(methodRequests):toBe(2)
	end)
end)

describe("RpcProvider - getTransactionByHash", function()
	it("returns full transaction details", function()
		resetHandlers()
		local provider = createTestProvider()
		local tx = provider:getTransactionByHash("0xtx1"):expect()
		expect(tx.transaction_hash):toBe("0xtx1")
		expect(tx.type):toBe("INVOKE")
		expect(tx.version):toBe("0x3")
		expect(tx.sender_address):toBe("0xsender1")
		expect(tx.nonce):toBe("0x5")
	end)

	it("sends correct JSON-RPC method and params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getTransactionByHash("0xmytx"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getTransactionByHash")
		expect(lastReq.params[1]):toBe("0xmytx")
	end)

	it("includes calldata and signature", function()
		resetHandlers()
		local provider = createTestProvider()
		local tx = provider:getTransactionByHash("0xtx1"):expect()
		expect(#tx.calldata):toBe(2)
		expect(tx.calldata[1]):toBe("0x1")
		expect(#tx.signature):toBe(2)
	end)

	it("is not cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getTransactionByHash("0xtx1"):expect()
		provider:getTransactionByHash("0xtx1"):expect()
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - getClass", function()
	it("returns the contract class definition", function()
		resetHandlers()
		local provider = createTestProvider()
		local class = provider:getClass("0xclasshash1"):expect()
		expect(class.contract_class_version):toBe("0.1.0")
		expect(#class.sierra_program):toBe(3)
		expect(class.abi):toBeTruthy()
	end)

	it("sends correct JSON-RPC method and params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClass("0xclasshash1"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getClass")
		expect(lastReq.params[1]):toBe("latest")
		expect(lastReq.params[2]):toBe("0xclasshash1")
	end)

	it("accepts block hash as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClass("0xclasshash1", "0xblockhash"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1].block_hash):toBe("0xblockhash")
	end)

	it("accepts block number as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClass("0xclasshash1", "50"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1].block_number):toBe(50)
	end)

	it("includes entry_points_by_type", function()
		resetHandlers()
		local provider = createTestProvider()
		local class = provider:getClass("0xclasshash1"):expect()
		expect(class.entry_points_by_type):toBeTruthy()
		expect(#class.entry_points_by_type.EXTERNAL):toBe(1)
	end)

	it("is cached indefinitely (classTTL=0)", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getClass("0xclasshash1"):expect()
		currentTime = 999999
		provider:getClass("0xclasshash1"):expect()
		local classRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getClass" then
				classRequests += 1
			end
		end
		expect(classRequests):toBe(1)
	end)

	it("different class hashes produce separate cache entries", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getClass("0xhash1"):expect()
		provider:getClass("0xhash2"):expect()
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - getClassAt", function()
	it("returns the contract class at an address", function()
		resetHandlers()
		local provider = createTestProvider()
		local class = provider:getClassAt("0xcontract1"):expect()
		expect(class.contract_class_version):toBe("0.1.0")
		expect(#class.sierra_program):toBe(2)
	end)

	it("sends correct JSON-RPC method and params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClassAt("0xcontract1"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_getClassAt")
		expect(lastReq.params[1]):toBe("latest")
		expect(lastReq.params[2]):toBe("0xcontract1")
	end)

	it("accepts block hash as blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getClassAt("0xcontract1", "0xblockhash"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[1].block_hash):toBe("0xblockhash")
	end)

	it("is cached indefinitely (classTTL=0)", function()
		resetHandlers()
		clearRequestLog()
		local currentTime = 0
		local provider = createTestProvider({
			enableCache = true,
			_clock = function()
				return currentTime
			end,
		})
		provider:getClassAt("0xcontract1"):expect()
		currentTime = 999999
		provider:getClassAt("0xcontract1"):expect()
		local classAtRequests = 0
		for _, req in requestLog do
			if req.method == "starknet_getClassAt" then
				classAtRequests += 1
			end
		end
		expect(classAtRequests):toBe(1)
	end)
end)

describe("RpcProvider - estimateMessageFee", function()
	it("returns fee estimate for L1->L2 message", function()
		resetHandlers()
		local provider = createTestProvider()
		local fee = provider:estimateMessageFee({
			from_address = "0xL1Sender",
			to_address = "0xL2Contract",
			entry_point_selector = "0xselector1",
			payload = { "0x1", "0x2" },
		}):expect()
		expect(fee.gas_consumed):toBe("0x2000")
		expect(fee.overall_fee):toBe("0x400000")
		expect(fee.unit):toBe("WEI")
	end)

	it("sends correct JSON-RPC method and params", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:estimateMessageFee({
			from_address = "0xL1Sender",
			to_address = "0xL2Contract",
			entry_point_selector = "0xselector1",
			payload = { "0x1" },
		}):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.method):toBe("starknet_estimateMessageFee")
		expect(lastReq.params[1].from_address):toBe("0xL1Sender")
		expect(lastReq.params[1].to_address):toBe("0xL2Contract")
		expect(lastReq.params[1].entry_point_selector):toBe("0xselector1")
		expect(#lastReq.params[1].payload):toBe(1)
		expect(lastReq.params[2]):toBe("latest") -- default blockId
	end)

	it("accepts custom blockId", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:estimateMessageFee({
			from_address = "0xL1Sender",
			to_address = "0xL2Contract",
			entry_point_selector = "0xselector1",
			payload = {},
		}, "pending"):expect()
		local lastReq = requestLog[#requestLog]
		expect(lastReq.params[2]):toBe("pending")
	end)

	it("is not cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		local msg = {
			from_address = "0xL1Sender",
			to_address = "0xL2Contract",
			entry_point_selector = "0xselector1",
			payload = { "0x1" },
		}
		provider:estimateMessageFee(msg):expect()
		provider:estimateMessageFee(msg):expect()
		expect(#requestLog):toBe(2)
	end)

	it("returns all fee fields", function()
		resetHandlers()
		local provider = createTestProvider()
		local fee = provider:estimateMessageFee({
			from_address = "0xL1Sender",
			to_address = "0xL2Contract",
			entry_point_selector = "0xselector1",
			payload = {},
		}):expect()
		expect(fee.gas_consumed):toBeTruthy()
		expect(fee.gas_price):toBeTruthy()
		expect(fee.overall_fee):toBeTruthy()
		expect(fee.data_gas_consumed):toBeTruthy()
		expect(fee.data_gas_price):toBeTruthy()
	end)
end)

describe("RpcProvider - getSyncingStats", function()
	it("returns syncing status when node is syncing", function()
		resetHandlers()
		local provider = createTestProvider()
		local status = provider:getSyncingStats():expect()
		expect(status.starting_block_hash):toBe("0xstart")
		expect(status.starting_block_num):toBe(0)
		expect(status.current_block_num):toBe(50000)
		expect(status.highest_block_num):toBe(100000)
	end)

	it("sends correct JSON-RPC method", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider()
		provider:getSyncingStats():expect()
		expect(requestLog[#requestLog].method):toBe("starknet_syncing")
	end)

	it("returns false when node is not syncing", function()
		resetHandlers()
		mockHandlers["starknet_syncing"] = function(_params)
			return false
		end
		local provider = createTestProvider()
		local status = provider:getSyncingStats():expect()
		expect(status):toBe(false)
	end)

	it("is not cached", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({ enableCache = true })
		provider:getSyncingStats():expect()
		provider:getSyncingStats():expect()
		expect(#requestLog):toBe(2)
	end)
end)

describe("RpcProvider - new methods work with queue", function()
	it("all new methods work with queue enabled", function()
		resetHandlers()
		clearRequestLog()
		local provider = createTestProvider({
			enableQueue = true,
			_defer = function(fn: () -> ())
				fn()
			end,
		})
		expect(provider:getBlockWithTxs():expect()).toBeTruthy()
		expect(provider:getBlockWithReceipts():expect()).toBeTruthy()
		expect(provider:getTransactionByHash("0xtx1"):expect()).toBeTruthy()
		expect(provider:getClass("0xhash1"):expect()).toBeTruthy()
		expect(provider:getClassAt("0xaddr1"):expect()).toBeTruthy()
		expect(provider:estimateMessageFee({
			from_address = "0xL1",
			to_address = "0xL2",
			entry_point_selector = "0xsel",
			payload = {},
		}):expect()).toBeTruthy()
		expect(provider:getSyncingStats():expect()).toBeTruthy()
	end)
end)
