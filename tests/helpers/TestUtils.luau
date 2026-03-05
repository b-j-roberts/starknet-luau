--!strict
-- TestUtils: Shared test infrastructure for starknet-luau specs
-- Factory-based design — each test file gets isolated mock state

local serde = require("@lune/serde")

local RpcProvider = require("../../src/provider/RpcProvider")
local MockPromise = require("./MockPromise")

local TestUtils = {}

--------------------------------------------------------------------------------
-- Shared test constants
--------------------------------------------------------------------------------

TestUtils.SN_SEPOLIA = "0x534e5f5345504f4c4941"

TestUtils.TEST_PRIVATE_KEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
TestUtils.TEST_PUBLIC_KEY = "0x499f65ae2f71d5298d2d88823b2e5e19596a71aac1984710479e406a002439"

TestUtils.TEST_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
TestUtils.ETH_TOKEN_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

TestUtils.OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
TestUtils.OZ_CLASS_HASH_2 = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003"

TestUtils.ARGENT_CLASS_HASH = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"
TestUtils.BRAAVOS_CLASS_HASH = "0x00816dd0297efc55dc1e7559020a3a825e81ef734b558f03c83325d4da7e6253"

--------------------------------------------------------------------------------
-- Mock RPC layer factory
--------------------------------------------------------------------------------

export type MockRpcLayer = {
	mockHandlers: { [string]: (params: any) -> any },
	requestLog: { { method: string, params: any } },
	clearRequestLog: () -> (),
	resetHandlers: () -> (),
	createMockHttpRequest: () -> (request: any) -> any,
	createTestProvider: (overrides: { [string]: any }?) -> any,
}

--[=[
	Creates an isolated mock RPC layer for a test file.
	Returns a table with mockHandlers, requestLog, helper functions,
	and a createTestProvider factory.

	Usage:
	```
	local rpc = TestUtils.createMockRpcLayer()
	rpc.resetHandlers()
	rpc.mockHandlers["starknet_getNonce"] = function(_) return "0x10" end
	local provider = rpc.createTestProvider()
	```
]=]
function TestUtils.createMockRpcLayer(): MockRpcLayer
	local layer: MockRpcLayer = {} :: any

	layer.mockHandlers = {}
	layer.requestLog = {}

	function layer.clearRequestLog()
		table.clear(layer.requestLog)
	end

	function layer.resetHandlers()
		table.clear(layer.mockHandlers)
		table.clear(layer.requestLog)

		layer.mockHandlers["starknet_chainId"] = function(_params)
			return TestUtils.SN_SEPOLIA
		end

		layer.mockHandlers["starknet_getNonce"] = function(_params)
			return "0x5"
		end

		layer.mockHandlers["starknet_estimateFee"] = function(_params)
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

		layer.mockHandlers["starknet_addInvokeTransaction"] = function(_params)
			return { transaction_hash = "0xabc123" }
		end

		layer.mockHandlers["starknet_getTransactionReceipt"] = function(_params)
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

		layer.mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return {
				finality_status = "ACCEPTED_ON_L2",
				execution_status = "SUCCEEDED",
			}
		end

		layer.mockHandlers["starknet_call"] = function(_params)
			return { "0x1" }
		end
	end

	function layer.createMockHttpRequest(): (request: any) -> any
		return function(request: any): any
			local body = serde.decode("json", request.Body or "{}") :: any

			-- Handle batch requests (array of JSON-RPC calls)
			if type(body) == "table" and #body > 0 and type(body[1]) == "table" and body[1].jsonrpc then
				local responses: { any } = {}
				for _, req in body do
					local method: string = req.method or ""
					local params: any = req.params
					table.insert(layer.requestLog, { method = method, params = params })

					local handler = layer.mockHandlers[method]
					if handler then
						local ok, result = pcall(handler, params)
						if ok then
							table.insert(responses, { jsonrpc = "2.0", id = req.id, result = result })
						else
							table.insert(
								responses,
								{ jsonrpc = "2.0", id = req.id, error = { code = -32000, message = tostring(result) } }
							)
						end
					else
						table.insert(responses, {
							jsonrpc = "2.0",
							id = req.id,
							error = { code = -32601, message = `Method not found: {method}` },
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
			local method: string = body.method or ""
			local params: any = body.params
			local id: number = body.id or 0

			table.insert(layer.requestLog, { method = method, params = params })

			local handler = layer.mockHandlers[method]
			if handler then
				local ok, result = pcall(handler, params)
				if ok then
					return {
						StatusCode = 200,
						Body = serde.encode("json", { jsonrpc = "2.0", id = id, result = result }),
						Success = true,
					}
				else
					return {
						StatusCode = 200,
						Body = serde.encode("json", {
							jsonrpc = "2.0",
							id = id,
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
					id = id,
					error = { code = -32601, message = `Method not found: {method}` },
				}),
				Success = true,
			}
		end
	end

	function layer.createTestProvider(overrides: { [string]: any }?): any
		local config: any = {
			nodeUrl = "http://mock-rpc.test",
			retryAttempts = 1,
			retryDelay = 0.01,
			_httpRequest = layer.createMockHttpRequest(),
			_sleep = function(_seconds: number) end,
			_clock = os.clock,
		}

		if overrides then
			for k, v in overrides do
				config[k] = v
			end
		end

		local provider = RpcProvider.new(config)
		;(provider :: any)._PromiseModule = MockPromise
		return provider
	end

	-- Initialize with default handlers
	layer.resetHandlers()

	return layer
end

--------------------------------------------------------------------------------
-- Clock mock helper
--------------------------------------------------------------------------------

--[=[
	Creates a controllable clock for testing time-dependent behavior.
	Returns (getClock, setClock) where getClock() returns current time
	and setClock(newTime) sets it.
]=]
function TestUtils.makeClock(startTime: number): (() -> number, (number) -> ())
	local time = startTime
	local function getClock(): number
		return time
	end
	local function setClock(newTime: number)
		time = newTime
	end
	return getClock, setClock
end

--------------------------------------------------------------------------------
-- Common test helpers
--------------------------------------------------------------------------------

--[=[
	Creates a standard set of test calls for TransactionBuilder/Account tests.
]=]
function TestUtils.createTestCalls(): { any }
	return {
		{
			contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			entrypoint = "transfer",
			calldata = {
				"0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
				"0x3e8",
				"0x0",
			},
		},
	}
end

return TestUtils
