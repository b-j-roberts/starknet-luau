--!strict
-- Tests for JSON-RPC batch dispatch behavior in RpcProvider
-- Batch logic lives in RpcProvider._dispatchBatch(); tested here via integration.
local serde = require("@lune/serde")

local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Mock infrastructure
--------------------------------------------------------------------------------

--- Create a mock HTTP that processes JSON-RPC requests (single or batch)
local function createBatchMockHttp(handlers: { [string]: (params: any) -> any })
	local httpCallCount = 0
	local lastBodies: { any } = {}

	local function httpRequest(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
		httpCallCount += 1
		local body = serde.decode("json", request.Body or "{}") :: any
		table.insert(lastBodies, body)

		-- Batch request: body is an array
		if type(body) == "table" and #body > 0 and type(body[1]) == "table" and body[1].jsonrpc then
			local responses: { any } = {}
			for _, req in body do
				local handler = handlers[req.method]
				if handler then
					local ok, result = pcall(handler, req.params)
					if ok then
						table.insert(responses, {
							jsonrpc = "2.0",
							id = req.id,
							result = result,
						})
					else
						table.insert(responses, {
							jsonrpc = "2.0",
							id = req.id,
							error = { code = -32000, message = tostring(result) },
						})
					end
				else
					table.insert(responses, {
						jsonrpc = "2.0",
						id = req.id,
						error = { code = -32601, message = `Method not found: {req.method}` },
					})
				end
			end
			return {
				StatusCode = 200,
				Body = serde.encode("json", responses),
				Success = true,
			}
		end

		-- Single request
		local handler = handlers[body.method]
		if handler then
			local ok, result = pcall(handler, body.params)
			if ok then
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						result = result,
					}),
					Success = true,
				}
			else
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = body.id,
						error = { code = -32000, message = tostring(result) },
					}),
					Success = true,
				}
			end
		end

		return {
			StatusCode = 200,
			Body = serde.encode("json", {
				jsonrpc = "2.0",
				id = body.id,
				error = { code = -32601, message = `Method not found: {body.method}` },
			}),
			Success = true,
		}
	end

	return httpRequest, function()
		return httpCallCount
	end, function()
		return lastBodies
	end
end

--- Create a test provider with queue enabled and synchronous defer
local function createQueueProvider(overrides: { [string]: any }?)
	local handlers = {
		["starknet_chainId"] = function(_p: any)
			return "0x534e5f5345504f4c4941"
		end,
		["starknet_blockNumber"] = function(_p: any)
			return 123456
		end,
		["starknet_specVersion"] = function(_p: any)
			return "0.7.1"
		end,
		["starknet_getNonce"] = function(_p: any)
			return "0x5"
		end,
		["starknet_getEvents"] = function(_p: any)
			return { events = {} }
		end,
		["starknet_addInvokeTransaction"] = function(_p: any)
			return { transaction_hash = "0xabc123" }
		end,
		["starknet_estimateFee"] = function(_p: any)
			return { { overall_fee = "0x100000" } }
		end,
	}

	local httpRequest, getCallCount, getBodies = createBatchMockHttp(handlers)
	local deferFns: { () -> () } = {}

	local config: any = {
		nodeUrl = "http://mock-batch.test",
		retryAttempts = 1,
		retryDelay = 0.001,
		enableQueue = true,
		_httpRequest = httpRequest,
		_sleep = function(_s: number) end,
		_clock = os.clock,
		_defer = function(fn: () -> ())
			table.insert(deferFns, fn)
		end,
	}

	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise

	local function drainDeferred()
		while #deferFns > 0 do
			local fn = table.remove(deferFns, 1)
			if fn then
				fn()
			end
		end
	end

	return provider, getCallCount, getBodies, drainDeferred
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("RequestBatcher - batch dispatch", function()
	it("batches multiple batchable reads into one HTTP call", function()
		local provider, getCallCount, getBodies, drainDeferred = createQueueProvider()
		-- Enqueue 3 batchable reads (all deferred)
		local p1 = provider:getChainId()
		local p2 = provider:getBlockNumber()
		local p3 = provider:getSpecVersion()
		-- Drain — should batch all 3
		drainDeferred()
		-- Only 1 HTTP call for 3 requests (batched)
		expect(getCallCount()):toBe(1)
		-- All promises resolved correctly
		expect(p1:expect()):toBe("0x534e5f5345504f4c4941")
		expect(p2:expect()):toBe(123456)
		expect(p3:expect()):toBe("0.7.1")
	end)

	it("sends batch as JSON array in request body", function()
		local provider, getCallCount, getBodies, drainDeferred = createQueueProvider()
		provider:getChainId()
		provider:getNonce("0x1")
		drainDeferred()
		local bodies = getBodies()
		expect(#bodies):toBe(1)
		-- Body should be an array of 2 RPC requests
		local batch = bodies[1]
		expect(#batch):toBe(2)
		expect(batch[1].jsonrpc):toBe("2.0")
		expect(batch[2].jsonrpc):toBe("2.0")
	end)

	it("resolves each request individually from batch response", function()
		local provider, _, _, drainDeferred = createQueueProvider()
		local p1 = provider:getChainId()
		local p2 = provider:getNonce("0x1")
		drainDeferred()
		expect(p1:expect()):toBe("0x534e5f5345504f4c4941")
		expect(p2:expect()):toBe("0x5")
	end)

	it("non-batchable items bypass batching", function()
		local provider, getCallCount, _, drainDeferred = createQueueProvider()
		-- addInvokeTransaction is HIGH and non-batchable — use raw fetch to avoid andThen
		local p1 = provider:fetch("starknet_addInvokeTransaction", {
			{
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
			},
		})
		local p2 = provider:fetch("starknet_chainId", {})
		drainDeferred()
		-- HIGH dispatched individually (1 call), then NORMAL batched as single item (1 call)
		expect(getCallCount()):toBe(2)
		expect((p1:expect() :: any).transaction_hash):toBe("0xabc123")
		expect(p2:expect()):toBe("0x534e5f5345504f4c4941")
	end)

	it("single batchable item is sent as individual request (not batch)", function()
		local provider, getCallCount, getBodies, drainDeferred = createQueueProvider()
		local p1 = provider:getChainId()
		drainDeferred()
		expect(getCallCount()):toBe(1)
		local bodies = getBodies()
		-- Should be a single RPC request, not an array
		expect(bodies[1].jsonrpc):toBe("2.0")
		expect(bodies[1].method):toBe("starknet_chainId")
		expect(p1:expect()):toBe("0x534e5f5345504f4c4941")
	end)
end)

describe("RequestBatcher - batch HTTP failure", function()
	it("rejects all items when batch HTTP request fails", function()
		local failHttp = function(_request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
			return {
				StatusCode = 502,
				Body = "Bad Gateway",
				Success = false,
			}
		end
		local provider, _, _, drainDeferred = createQueueProvider({
			_httpRequest = failHttp,
		})
		local p1 = provider:getChainId()
		local p2 = provider:getBlockNumber()
		drainDeferred()
		expect(function()
			p1:expect()
		end):toThrow()
		expect(function()
			p2:expect()
		end):toThrow()
	end)
end)

describe("RequestBatcher - batching disabled", function()
	it("dispatches all items individually when enableBatching is false", function()
		local provider, getCallCount, _, drainDeferred = createQueueProvider({
			queueConfig = { enableBatching = false },
		})
		provider:getChainId()
		provider:getBlockNumber()
		provider:getSpecVersion()
		drainDeferred()
		-- Each dispatched individually
		expect(getCallCount()):toBe(3)
	end)
end)

describe("RequestBatcher - metrics tracking", function()
	it("tracks batchesSent and totalBatched in metrics", function()
		local provider, _, _, drainDeferred = createQueueProvider()
		provider:getChainId()
		provider:getBlockNumber()
		drainDeferred()
		local metrics = provider:getMetrics()
		expect(metrics.batchesSent):toBe(1)
		expect(metrics.totalBatched):toBe(2)
		expect(metrics.totalCompleted):toBe(2)
	end)

	it("increments totalFailed on batch RPC errors", function()
		local failHandlers = {
			["starknet_chainId"] = function(_p: any)
				error("fail")
			end,
		}
		local failHttp, _, _ = createBatchMockHttp(failHandlers)
		local provider, _, _, drainDeferred = createQueueProvider({
			_httpRequest = failHttp,
		})
		local p = provider:getChainId()
		drainDeferred()
		p:catch(function() end) -- swallow
		local metrics = provider:getMetrics()
		-- Single item sent individually (not batched), but it errored via RPC
		expect(metrics.totalFailed):toBe(1)
	end)
end)

describe("RequestBatcher - maxBatchSize", function()
	it("respects maxBatchSize limit", function()
		local provider, getCallCount, getBodies, drainDeferred = createQueueProvider({
			queueConfig = { maxBatchSize = 2 },
		})
		provider:getChainId()
		provider:getBlockNumber()
		provider:getSpecVersion()
		drainDeferred()
		-- Should produce 2 HTTP calls: batch of 2 + individual 1
		expect(getCallCount()):toBe(2)
	end)
end)
