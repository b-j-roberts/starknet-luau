--!strict
local OutsideExecution = require("../../src/wallet/OutsideExecution")
local TypedData = require("../../src/wallet/TypedData")
local BigInt = require("../../src/crypto/BigInt")
local StarkField = require("../../src/crypto/StarkField")
local Keccak = require("../../src/crypto/Keccak")
local StarkCurve = require("../../src/crypto/StarkCurve")
local ECDSA = require("../../src/crypto/ECDSA")
local StarkSigner = require("../../src/signer/StarkSigner")
local Constants = require("../../src/constants")

--------------------------------------------------------------------------------
-- Test fixtures
--------------------------------------------------------------------------------

local TEST_CHAIN_ID = "0x534e5f5345504f4c4941" -- SN_SEPOLIA
local TEST_CALLER = "0x414e595f43414c4c4552" -- ANY_CALLER
local TEST_NONCE = "0x1"
local TEST_PRIVKEY = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local TEST_ACCOUNT_ADDR = "0x65a822fbee1ae79e898688b5a4f7f5e6568f0b5cee3eb17bba58a4dea99ef1a"

-- A simple Call for testing
local function makeTestCall(entrypoint: string?, calldata: { string }?): { [string]: any }
	return {
		contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
		entrypoint = entrypoint or "transfer",
		calldata = calldata or { "0xdeadbeef", "0x1000", "0x0" },
	}
end

local function makeTestOptions(): { caller: string, execute_after: number | string, execute_before: number | string }
	return {
		caller = TEST_CALLER,
		execute_after = 0,
		execute_before = 999999999,
	}
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

describe("OutsideExecution - Constants", function()
	it("exports VERSION_V1 as '1'", function()
		expect(OutsideExecution.VERSION_V1):toBe("1")
	end)

	it("exports VERSION_V2 as '2'", function()
		expect(OutsideExecution.VERSION_V2):toBe("2")
	end)

	it("exports VERSION_V3_RC as '3'", function()
		expect(OutsideExecution.VERSION_V3_RC):toBe("3")
	end)

	it("exports ENTRYPOINT_V1", function()
		expect(OutsideExecution.ENTRYPOINT_V1):toBe("execute_from_outside")
	end)

	it("exports ENTRYPOINT_V2", function()
		expect(OutsideExecution.ENTRYPOINT_V2):toBe("execute_from_outside_v2")
	end)

	it("exports ENTRYPOINT_V3", function()
		expect(OutsideExecution.ENTRYPOINT_V3):toBe("execute_from_outside_v3")
	end)
end)

describe("OutsideExecution - ANY_CALLER", function()
	it("matches short string encoding of 'ANY_CALLER'", function()
		-- "ANY_CALLER" in ASCII hex = 0x414e595f43414c4c4552
		expect(OutsideExecution.ANY_CALLER):toBe("0x414e595f43414c4c4552")
	end)

	it("matches Constants.ANY_CALLER", function()
		expect(OutsideExecution.ANY_CALLER):toBe(Constants.ANY_CALLER)
	end)
end)

--------------------------------------------------------------------------------
-- getEntrypoint
--------------------------------------------------------------------------------

describe("OutsideExecution.getEntrypoint", function()
	it("returns execute_from_outside for V1", function()
		expect(OutsideExecution.getEntrypoint("1")):toBe("execute_from_outside")
	end)

	it("returns execute_from_outside_v2 for V2", function()
		expect(OutsideExecution.getEntrypoint("2")):toBe("execute_from_outside_v2")
	end)

	it("returns execute_from_outside_v3 for V3", function()
		expect(OutsideExecution.getEntrypoint("3")):toBe("execute_from_outside_v3")
	end)

	it("throws for invalid version", function()
		expect(function()
			OutsideExecution.getEntrypoint("4")
		end):toThrowCode(6001)
	end)
end)

--------------------------------------------------------------------------------
-- getOutsideCall
--------------------------------------------------------------------------------

describe("OutsideExecution.getOutsideCall", function()
	it("converts named entrypoint to selector via starknet_keccak", function()
		local call = makeTestCall("transfer", {})
		local oc = OutsideExecution.getOutsideCall(call)
		local expectedSelector = StarkField.toHex(Keccak.getSelectorFromName("transfer"))
		expect(oc.selector):toBe(expectedSelector)
	end)

	it("passes through hex selector", function()
		local call = {
			contractAddress = "0xabc",
			entrypoint = "0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e",
			calldata = {},
		}
		local oc = OutsideExecution.getOutsideCall(call)
		-- Should normalize the hex
		local expected = BigInt.toHex(BigInt.fromHex("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e"))
		expect(oc.selector):toBe(expected)
	end)

	it("normalizes hex selector (strips leading zeros)", function()
		local call = {
			contractAddress = "0xabc",
			entrypoint = "0x00000123",
			calldata = {},
		}
		local oc = OutsideExecution.getOutsideCall(call)
		expect(oc.selector):toBe("0x123")
	end)

	it("defaults empty calldata when nil", function()
		local call = { contractAddress = "0xabc", entrypoint = "foo" }
		local oc = OutsideExecution.getOutsideCall(call)
		expect(#(oc.calldata :: { any })):toBe(0)
	end)

	it("preserves calldata array", function()
		local call = makeTestCall("transfer", { "0x1", "0x2", "0x3" })
		local oc = OutsideExecution.getOutsideCall(call)
		local cd = oc.calldata :: { string }
		expect(#cd):toBe(3)
		expect(cd[1]):toBe("0x1")
		expect(cd[2]):toBe("0x2")
		expect(cd[3]):toBe("0x3")
	end)

	it("sets to from contractAddress", function()
		local call = makeTestCall("transfer", {})
		local oc = OutsideExecution.getOutsideCall(call)
		expect(oc.to):toBe(call.contractAddress)
	end)
end)

--------------------------------------------------------------------------------
-- getTypedData - V1
--------------------------------------------------------------------------------

describe("OutsideExecution.getTypedData - V1", function()
	it("uses StarkNetDomain (capital N)", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		local types = td.types :: { [string]: any }
		expect(types["StarkNetDomain"] ~= nil):toBeTruthy()
		expect(types["StarknetDomain"]):toBe(nil)
	end)

	it("primaryType is OutsideExecution", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect(td.primaryType):toBe("OutsideExecution")
	end)

	it("domain name is Account.execute_from_outside", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect((td.domain :: any).name):toBe("Account.execute_from_outside")
	end)

	it("domain version is 1", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect((td.domain :: any).version):toBe("1")
	end)

	it("domain chainId matches input", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect((td.domain :: any).chainId):toBe(TEST_CHAIN_ID)
	end)

	it("message has calls_len field", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect((td.message :: any).calls_len):toBe(1)
	end)

	it("message calls have calldata_len field", function()
		local call = makeTestCall("transfer", { "0x1", "0x2" })
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { call }, "1")
		local calls = (td.message :: any).calls :: { any }
		expect((calls[1] :: any).calldata_len):toBe(2)
	end)

	it("encodes caller and nonce in message", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		local msg = td.message :: any
		expect(msg.caller):toBe(TEST_CALLER)
		expect(msg.nonce):toBe(TEST_NONCE)
	end)

	it("OutsideExecution type hash matches SNIP-9 spec", function()
		local typeHash = TypedData.getTypeHash(OutsideExecution.TYPES_V1, "OutsideExecution", "0")
		expect(typeHash):toBe("0x11ff76fe3f640fa6f3d60bbd94a3b9d47141a2c96f87fdcfbeb2af1d03f7050")
	end)

	it("OutsideCall type hash matches SNIP-9 spec", function()
		local typeHash = TypedData.getTypeHash(OutsideExecution.TYPES_V1, "OutsideCall", "0")
		expect(typeHash):toBe("0xf00de1fccbb286f9a020ba8821ee936b1deea42a5c485c11ccdc82c8bebb3a")
	end)
end)

--------------------------------------------------------------------------------
-- getTypedData - V2
--------------------------------------------------------------------------------

describe("OutsideExecution.getTypedData - V2", function()
	it("uses StarknetDomain (lowercase n)", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local types = td.types :: { [string]: any }
		expect(types["StarknetDomain"] ~= nil):toBeTruthy()
		expect(types["StarkNetDomain"]):toBe(nil)
	end)

	it("domain has revision 1", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		expect((td.domain :: any).revision):toBe("1")
	end)

	it("domain version is 2", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		expect((td.domain :: any).version):toBe("2")
	end)

	it("message uses PascalCase fields", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local msg = td.message :: any
		expect(msg.Caller):toBe(TEST_CALLER)
		expect(msg.Nonce):toBe(TEST_NONCE)
		expect(msg["Execute After"] ~= nil):toBeTruthy()
		expect(msg["Execute Before"] ~= nil):toBeTruthy()
		expect(msg.Calls ~= nil):toBeTruthy()
	end)

	it("message Calls use Call struct with PascalCase", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local calls = (td.message :: any).Calls :: { any }
		local call = calls[1] :: any
		expect(call.To ~= nil):toBeTruthy()
		expect(call.Selector ~= nil):toBeTruthy()
		expect(call.Calldata ~= nil):toBeTruthy()
	end)

	it("Call type has selector type for Selector field", function()
		local types = OutsideExecution.TYPES_V2
		local callFields = types.Call :: { any }
		local selectorField: any = nil
		for _, f in callFields do
			if (f :: any).name == "Selector" then
				selectorField = f
				break
			end
		end
		expect(selectorField ~= nil):toBeTruthy()
		expect(selectorField.type):toBe("selector")
	end)

	it("no calls_len or calldata_len in V2", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local msg = td.message :: any
		expect(msg.calls_len):toBe(nil)
		local calls = msg.Calls :: { any }
		expect((calls[1] :: any).calldata_len):toBe(nil)
	end)

	it("OutsideExecution type hash matches SNIP-9 spec", function()
		local typeHash = TypedData.getTypeHash(OutsideExecution.TYPES_V2, "OutsideExecution", "1")
		expect(typeHash):toBe("0x312b56c05a7965066ddbda31c016d8d05afc305071c0ca3cdc2192c3c2f1f0f")
	end)

	it("encodeType produces correct V2 string", function()
		local encoded = TypedData.encodeType(OutsideExecution.TYPES_V2, "OutsideExecution", "1")
		local expected = '"OutsideExecution"("Caller":"ContractAddress","Nonce":"felt","Execute After":"u128","Execute Before":"u128","Calls":"Call*")"Call"("To":"ContractAddress","Selector":"selector","Calldata":"felt*")'
		expect(encoded):toBe(expected)
	end)
end)

--------------------------------------------------------------------------------
-- getTypedData - V3-RC
--------------------------------------------------------------------------------

describe("OutsideExecution.getTypedData - V3-RC", function()
	local noFeeFeeMode = { noFee = true }
	local payFeeFeeMode = {
		payFee = {
			tokenAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			amount = { low = "0x1000", high = "0x0" },
			receiver = "0xabc123",
		},
	}

	it("domain version is 3", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", noFeeFeeMode
		)
		expect((td.domain :: any).version):toBe("3")
	end)

	it("domain has revision 1", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", noFeeFeeMode
		)
		expect((td.domain :: any).revision):toBe("1")
	end)

	it("includes Fee field in OutsideExecution type definition", function()
		local oeFields = OutsideExecution.TYPES_V3.OutsideExecution :: { any }
		local hasFee = false
		for _, f in oeFields do
			if (f :: any).name == "Fee" then
				hasFee = true
				expect((f :: any).type):toBe("enum")
				expect((f :: any).contains):toBe("Fee Mode")
			end
		end
		expect(hasFee):toBeTruthy()
	end)

	it("types include Fee Mode enum", function()
		local feeModeType = OutsideExecution.TYPES_V3["Fee Mode"]
		expect(feeModeType ~= nil):toBeTruthy()
		local variants = feeModeType :: { any }
		expect(#variants):toBe(2)
		expect((variants[1] :: any).name):toBe("No Fee")
		expect((variants[1] :: any).type):toBe("()")
		expect((variants[2] :: any).name):toBe("Pay Fee")
		expect((variants[2] :: any).type):toBe("(FeeTransfer)")
	end)

	it("types include FeeTransfer struct", function()
		local ftType = OutsideExecution.TYPES_V3.FeeTransfer
		expect(ftType ~= nil):toBeTruthy()
		local fields = ftType :: { any }
		expect(#fields):toBe(2)
		expect((fields[1] :: any).name):toBe("Fee Amount")
		expect((fields[1] :: any).type):toBe("TokenAmount")
		expect((fields[2] :: any).name):toBe("Fee Receiver")
		expect((fields[2] :: any).type):toBe("ContractAddress")
	end)

	it("NoFee encodes as empty enum variant in message", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", noFeeFeeMode
		)
		local fee = (td.message :: any).Fee :: { [string]: any }
		expect(fee["No Fee"] ~= nil):toBeTruthy()
		local noFeeData = fee["No Fee"] :: { any }
		expect(#noFeeData):toBe(0) -- empty table for empty tuple
	end)

	it("PayFee encodes with FeeTransfer data in message", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", payFeeFeeMode
		)
		local fee = (td.message :: any).Fee :: { [string]: any }
		expect(fee["Pay Fee"] ~= nil):toBeTruthy()
		local payFeeData = fee["Pay Fee"] :: { any }
		expect(#payFeeData):toBe(1) -- single FeeTransfer element in tuple
		local ft = payFeeData[1] :: { [string]: any }
		expect(ft["Fee Amount"] ~= nil):toBeTruthy()
		expect(ft["Fee Receiver"]):toBe("0xabc123")
	end)

	it("requires feeMode parameter for V3", function()
		expect(function()
			OutsideExecution.getTypedData(
				TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3"
			)
		end):toThrowCode(6003)
	end)

	it("rejects feeMode without noFee or payFee", function()
		expect(function()
			OutsideExecution.getTypedData(
				TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", { invalid = true }
			)
		end):toThrowCode(6003)
	end)
end)

--------------------------------------------------------------------------------
-- validateCalls
--------------------------------------------------------------------------------

describe("OutsideExecution.validateCalls", function()
	it("returns true for exact match - single call", function()
		local calls = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1", "0x2" } },
		}
		expect(OutsideExecution.validateCalls(calls, calls)):toBeTruthy()
	end)

	it("returns true for exact match - multiple calls", function()
		local calls = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
			{ to = "0xdef", selector = "0x456", calldata = { "0x2", "0x3" } },
		}
		expect(OutsideExecution.validateCalls(calls, calls)):toBeTruthy()
	end)

	it("returns true with one appended transfer call", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
			{ to = "0xfee", selector = "0x789", calldata = { "0xpayment" } },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeTruthy()
	end)

	it("returns false for different call count (not +1)", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
			{ to = "0xfee", selector = "0x789", calldata = {} },
			{ to = "0xbad", selector = "0x999", calldata = {} },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("returns false for different to address", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
		}
		local returned = {
			{ to = "0xdef", selector = "0x123", calldata = {} },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("returns false for different selector", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
		}
		local returned = {
			{ to = "0xabc", selector = "0x456", calldata = {} },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("returns false for different calldata", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x2" } },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("returns false for different calldata length", function()
		local submitted = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1", "0x2" } },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("normalizes hex for comparison", function()
		local submitted = {
			{ to = "0x00abc", selector = "0x0123", calldata = { "0x001" } },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1" } },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeTruthy()
	end)

	it("returns false for empty submitted vs non-empty returned (not +1)", function()
		local submitted: { { [string]: any } } = {}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
			{ to = "0xdef", selector = "0x456", calldata = {} },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeFalsy()
	end)

	it("supports contractAddress key as fallback for to", function()
		local submitted = {
			{ contractAddress = "0xabc", selector = "0x123", calldata = {} },
		}
		local returned = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
		}
		expect(OutsideExecution.validateCalls(submitted, returned)):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- buildExecuteFromOutsideCall
--------------------------------------------------------------------------------

describe("OutsideExecution.buildExecuteFromOutsideCall", function()
	local simpleExecution = {
		caller = TEST_CALLER,
		nonce = "0x1",
		execute_after = "0x0",
		execute_before = "0x3b9ac9ff",
		calls = {
			{ to = "0xabc", selector = "0x123", calldata = { "0x1", "0x2" } },
		},
	}

	it("targets signer address", function()
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, simpleExecution, { "0xr", "0xs" }, "1"
		)
		expect(result.contractAddress):toBe(TEST_ACCOUNT_ADDR)
	end)

	it("uses correct V1 entrypoint", function()
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, simpleExecution, { "0xr", "0xs" }, "1"
		)
		expect(result.entrypoint):toBe("execute_from_outside")
	end)

	it("uses correct V2 entrypoint", function()
		local v2Execution = {
			Caller = TEST_CALLER,
			Nonce = "0x1",
			["Execute After"] = "0x0",
			["Execute Before"] = "0x3b9ac9ff",
			Calls = {
				{ To = "0xabc", Selector = "0x123", Calldata = { "0x1" } },
			},
		}
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, v2Execution, { "0xr", "0xs" }, "2"
		)
		expect(result.entrypoint):toBe("execute_from_outside_v2")
	end)

	it("uses correct V3 entrypoint", function()
		local v3Execution = {
			Caller = TEST_CALLER,
			Nonce = "0x1",
			["Execute After"] = "0x0",
			["Execute Before"] = "0x3b9ac9ff",
			Calls = {
				{ To = "0xabc", Selector = "0x123", Calldata = {} },
			},
			Fee = { ["No Fee"] = {} },
		}
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, v3Execution, { "0xr", "0xs" }, "3"
		)
		expect(result.entrypoint):toBe("execute_from_outside_v3")
	end)

	it("encodes calls with length prefix", function()
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, simpleExecution, { "0xr", "0xs" }, "1"
		)
		local cd = result.calldata :: { string }
		-- calldata: [caller, nonce, exec_after, exec_before, calls_len(1), to, selector, cd_len(2), 0x1, 0x2, sig_len(2), 0xr, 0xs]
		expect(cd[1]):toBe(TEST_CALLER)         -- caller
		expect(cd[2]):toBe("0x1")               -- nonce
		expect(cd[3]):toBe("0x0")               -- execute_after
		expect(cd[4]):toBe("0x3b9ac9ff")        -- execute_before
		expect(cd[5]):toBe("0x1")               -- calls_len = 1
		expect(cd[6]):toBe("0xabc")             -- call.to
		expect(cd[7]):toBe("0x123")             -- call.selector
		expect(cd[8]):toBe("0x2")               -- calldata_len = 2
		expect(cd[9]):toBe("0x1")               -- calldata[1]
		expect(cd[10]):toBe("0x2")              -- calldata[2]
	end)

	it("encodes signature with length prefix", function()
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, simpleExecution, { "0xr", "0xs" }, "1"
		)
		local cd = result.calldata :: { string }
		-- Last 3 elements: sig_len, r, s
		expect(cd[#cd - 2]):toBe("0x2")   -- signature length
		expect(cd[#cd - 1]):toBe("0xr")   -- r
		expect(cd[#cd]):toBe("0xs")       -- s
	end)

	it("encodes V3 NoFee variant", function()
		local v3Execution = {
			Caller = TEST_CALLER,
			Nonce = "0x1",
			["Execute After"] = "0x0",
			["Execute Before"] = "0x3b9ac9ff",
			Calls = {
				{ To = "0xabc", Selector = "0x123", Calldata = {} },
			},
			Fee = { ["No Fee"] = {} },
		}
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, v3Execution, { "0xr", "0xs" }, "3"
		)
		local cd = result.calldata :: { string }
		-- After calls: fee variant (0x0), then sig
		-- calls_len=1, to, selector, cd_len=0 → indices 5,6,7,8
		-- fee variant index at 9
		expect(cd[9]):toBe("0x0") -- NoFee variant index
		expect(cd[10]):toBe("0x2") -- sig_len
	end)

	it("encodes V3 PayFee variant", function()
		local v3Execution = {
			Caller = TEST_CALLER,
			Nonce = "0x1",
			["Execute After"] = "0x0",
			["Execute Before"] = "0x3b9ac9ff",
			Calls = {
				{ To = "0xabc", Selector = "0x123", Calldata = {} },
			},
			Fee = {
				["Pay Fee"] = {
					{
						["Fee Amount"] = {
							token_address = "0xtoken",
							amount = { low = "0x1000", high = "0x0" },
						},
						["Fee Receiver"] = "0xreceiver",
					},
				},
			},
		}
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, v3Execution, { "0xr", "0xs" }, "3"
		)
		local cd = result.calldata :: { string }
		-- After calls: fee variant (0x1), token_address, amount_low, amount_high, receiver, then sig
		expect(cd[9]):toBe("0x1")        -- PayFee variant index
		expect(cd[10]):toBe("0xtoken")   -- token_address
		expect(cd[11]):toBe("0x1000")    -- amount.low
		expect(cd[12]):toBe("0x0")       -- amount.high
		expect(cd[13]):toBe("0xreceiver") -- receiver
		expect(cd[14]):toBe("0x2")       -- sig_len
	end)

	it("handles numeric nonce and timestamps", function()
		local execution = {
			caller = TEST_CALLER,
			nonce = 42,
			execute_after = 0,
			execute_before = 1000,
			calls = {},
		}
		-- This will fail on empty calls at entrypoint encoding, so let's add a call
		execution.calls = {
			{ to = "0xabc", selector = "0x123", calldata = {} },
		}
		local result = OutsideExecution.buildExecuteFromOutsideCall(
			TEST_ACCOUNT_ADDR, execution, { "0xsig" }, "1"
		)
		local cd = result.calldata :: { string }
		expect(cd[2]):toBe("0x2a")       -- nonce = 42
		expect(cd[3]):toBe("0x0")        -- execute_after = 0
		expect(cd[4]):toBe("0x3e8")      -- execute_before = 1000
	end)
end)

--------------------------------------------------------------------------------
-- Error handling
--------------------------------------------------------------------------------

describe("OutsideExecution - Error handling", function()
	it("throws INVALID_VERSION for invalid version in getTypedData", function()
		expect(function()
			OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "99")
		end):toThrowCode(6001)
	end)

	it("throws for empty calls array", function()
		expect(function()
			OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, {}, "1")
		end):toThrowCode(6000)
	end)

	it("throws INVALID_TIME_BOUNDS for execute_after >= execute_before", function()
		expect(function()
			local opts = { caller = TEST_CALLER, execute_after = 1000, execute_before = 100 }
			OutsideExecution.getTypedData(TEST_CHAIN_ID, opts, TEST_NONCE, { makeTestCall() }, "1")
		end):toThrowCode(6004)
	end)

	it("throws INVALID_TIME_BOUNDS for equal timestamps", function()
		expect(function()
			local opts = { caller = TEST_CALLER, execute_after = 500, execute_before = 500 }
			OutsideExecution.getTypedData(TEST_CHAIN_ID, opts, TEST_NONCE, { makeTestCall() }, "1")
		end):toThrowCode(6004)
	end)

	it("throws MISSING_FEE_MODE for V3 without feeMode", function()
		expect(function()
			OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3")
		end):toThrowCode(6003)
	end)
end)

--------------------------------------------------------------------------------
-- TypedData integration (message hash computation)
--------------------------------------------------------------------------------

describe("OutsideExecution - TypedData message hash integration", function()
	it("V1 typed data produces a valid message hash", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)
		-- Must be a valid hex string
		expect(string.sub(msgHash, 1, 2)):toBe("0x")
		expect(#msgHash > 4):toBeTruthy()
	end)

	it("V2 typed data produces a valid message hash", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)
		expect(string.sub(msgHash, 1, 2)):toBe("0x")
		expect(#msgHash > 4):toBeTruthy()
	end)

	it("V3-RC NoFee typed data produces a valid message hash", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", { noFee = true }
		)
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)
		expect(string.sub(msgHash, 1, 2)):toBe("0x")
		expect(#msgHash > 4):toBeTruthy()
	end)

	it("V3-RC PayFee typed data produces a valid message hash", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", {
				payFee = {
					tokenAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
					amount = { low = "0x1000", high = "0x0" },
					receiver = "0xabc123",
				},
			}
		)
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)
		expect(string.sub(msgHash, 1, 2)):toBe("0x")
		expect(#msgHash > 4):toBeTruthy()
	end)

	it("V1 identifies as LEGACY revision", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		expect(TypedData.identifyRevision(td)):toBe("0")
	end)

	it("V2 identifies as ACTIVE revision", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		expect(TypedData.identifyRevision(td)):toBe("1")
	end)

	it("different nonces produce different hashes", function()
		local td1 = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), "0x1", { makeTestCall() }, "1")
		local td2 = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), "0x2", { makeTestCall() }, "1")
		local hash1 = TypedData.getMessageHash(td1, TEST_ACCOUNT_ADDR)
		local hash2 = TypedData.getMessageHash(td2, TEST_ACCOUNT_ADDR)
		expect(hash1 ~= hash2):toBeTruthy()
	end)

	it("different callers produce different hashes", function()
		local opts1 = { caller = TEST_CALLER, execute_after = 0, execute_before = 999999999 }
		local opts2 = { caller = "0xdeadbeef", execute_after = 0, execute_before = 999999999 }
		local td1 = OutsideExecution.getTypedData(TEST_CHAIN_ID, opts1, TEST_NONCE, { makeTestCall() }, "2")
		local td2 = OutsideExecution.getTypedData(TEST_CHAIN_ID, opts2, TEST_NONCE, { makeTestCall() }, "2")
		local hash1 = TypedData.getMessageHash(td1, TEST_ACCOUNT_ADDR)
		local hash2 = TypedData.getMessageHash(td2, TEST_ACCOUNT_ADDR)
		expect(hash1 ~= hash2):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Signing integration (sign -> verify roundtrip)
--------------------------------------------------------------------------------

describe("OutsideExecution - Signing integration", function()
	local signer = StarkSigner.new(TEST_PRIVKEY)
	local pubKeyPoint = StarkCurve.getPublicKey(BigInt.fromHex(TEST_PRIVKEY))

	it("V1: sign -> verify roundtrip", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "1")
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)

		local hashBuf = BigInt.fromHex(msgHash)
		local sig = signer:signRaw(hashBuf)

		local verified = ECDSA.verify(hashBuf, pubKeyPoint, sig)
		expect(verified):toBeTruthy()
	end)

	it("V2: sign -> verify roundtrip", function()
		local td = OutsideExecution.getTypedData(TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "2")
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)

		local hashBuf = BigInt.fromHex(msgHash)
		local sig = signer:signRaw(hashBuf)

		local verified = ECDSA.verify(hashBuf, pubKeyPoint, sig)
		expect(verified):toBeTruthy()
	end)

	it("V3-RC: sign -> verify roundtrip with NoFee", function()
		local td = OutsideExecution.getTypedData(
			TEST_CHAIN_ID, makeTestOptions(), TEST_NONCE, { makeTestCall() }, "3", { noFee = true }
		)
		local msgHash = TypedData.getMessageHash(td, TEST_ACCOUNT_ADDR)

		local hashBuf = BigInt.fromHex(msgHash)
		local sig = signer:signRaw(hashBuf)

		local verified = ECDSA.verify(hashBuf, pubKeyPoint, sig)
		expect(verified):toBeTruthy()
	end)
end)
