--!strict
local CallData = require("../../src/tx/CallData")
local StarkField = require("../../src/crypto/StarkField")
local BigInt = require("../../src/crypto/BigInt")
local Keccak = require("../../src/crypto/Keccak")

--------------------------------------------------------------------------------
-- encodeFelt
--------------------------------------------------------------------------------

describe("CallData - encodeFelt", function()
	it("encodes zero felt", function()
		local result = CallData.encodeFelt("0x0")
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x0")
	end)

	it("encodes small hex value", function()
		local result = CallData.encodeFelt("0x2a")
		expect(result[1]):toBe("0x2a")
	end)

	it("normalizes leading zeros", function()
		local result = CallData.encodeFelt("0x0123")
		expect(result[1]):toBe("0x123")
	end)

	it("encodes full-size felt", function()
		local result = CallData.encodeFelt("0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
		expect(result[1]):toBe("0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7")
	end)

	it("normalizes uppercase hex", function()
		local result = CallData.encodeFelt("0xDEADBEEF")
		expect(result[1]):toBe("0xdeadbeef")
	end)
end)

--------------------------------------------------------------------------------
-- encodeBool
--------------------------------------------------------------------------------

describe("CallData - encodeBool", function()
	it("true encodes as 0x1", function()
		local result = CallData.encodeBool(true)
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x1")
	end)

	it("false encodes as 0x0", function()
		local result = CallData.encodeBool(false)
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x0")
	end)
end)

--------------------------------------------------------------------------------
-- encodeShortString
--------------------------------------------------------------------------------

describe("CallData - encodeShortString", function()
	it("empty string encodes as zero", function()
		local result = CallData.encodeShortString("")
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x0")
	end)

	it("'hello' matches starknet.js encodeShortString", function()
		-- starknet.js: encodeShortString('hello') = '0x68656c6c6f'
		local result = CallData.encodeShortString("hello")
		expect(result[1]):toBe("0x68656c6c6f")
	end)

	it("'test' matches starknet.js", function()
		-- starknet.js: encodeShortString('test') = '0x74657374'
		-- decimal: 1952805748
		local result = CallData.encodeShortString("test")
		expect(result[1]):toBe("0x74657374")
	end)

	it("'Ok' matches starknet.js", function()
		-- starknet.js: encodeShortString('Ok') = '0x4f6b'
		local result = CallData.encodeShortString("Ok")
		expect(result[1]):toBe("0x4f6b")
	end)

	it("'SN_MAIN' matches starknet.js chain ID", function()
		-- starknet.js: encodeShortString('SN_MAIN') = '0x534e5f4d41494e'
		local result = CallData.encodeShortString("SN_MAIN")
		expect(result[1]):toBe("0x534e5f4d41494e")
	end)

	it("'SN_SEPOLIA' matches starknet.js chain ID", function()
		-- starknet.js: encodeShortString('SN_SEPOLIA') = '0x534e5f5345504f4c4941'
		local result = CallData.encodeShortString("SN_SEPOLIA")
		expect(result[1]):toBe("0x534e5f5345504f4c4941")
	end)

	it("encodes max 31-char string", function()
		local str31 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345"
		expect(#str31):toBe(31)
		local result = CallData.encodeShortString(str31)
		expect(#result):toBe(1)
		-- A=41, B=42, ..., Z=5a, 1=31, ..., 5=35
		expect(result[1]):toBe("0x4142434445464748494a4b4c4d4e4f505152535455565758595a3132333435")
	end)

	it("rejects string longer than 31 chars", function()
		expect(function()
			CallData.encodeShortString(string.rep("a", 32))
		end):toThrow()
	end)

	it("rejects non-ASCII characters", function()
		-- 0x80 = 128, first non-ASCII byte
		expect(function()
			CallData.encodeShortString("hello\128")
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- encodeU256
--------------------------------------------------------------------------------

describe("CallData - encodeU256", function()
	it("zero value produces two zero felts", function()
		local result = CallData.encodeU256("0x0")
		expect(#result):toBe(2)
		expect(result[1]):toBe("0x0")
		expect(result[2]):toBe("0x0")
	end)

	it("small value fits entirely in low felt", function()
		-- 252 = 0xfc, fits in 128 bits
		-- starknet.js: uint256(252) => { low: '252', high: '0' }
		local result = CallData.encodeU256("0xfc")
		expect(result[1]):toBe("0xfc")
		expect(result[2]):toBe("0x0")
	end)

	it("max 128-bit value is all in low felt", function()
		-- 2^128 - 1 = 0xffffffffffffffffffffffffffffffff
		local result = CallData.encodeU256("0xffffffffffffffffffffffffffffffff")
		expect(result[1]):toBe("0xffffffffffffffffffffffffffffffff")
		expect(result[2]):toBe("0x0")
	end)

	it("exactly 2^128 splits as low=0 high=1", function()
		-- 2^128 = 0x100000000000000000000000000000000
		local result = CallData.encodeU256("0x100000000000000000000000000000000")
		expect(result[1]):toBe("0x0")
		expect(result[2]):toBe("0x1")
	end)

	it("2^128 + 1 splits correctly", function()
		-- 2^128 + 1 = 0x100000000000000000000000000000001
		local result = CallData.encodeU256("0x100000000000000000000000000000001")
		expect(result[1]):toBe("0x1")
		expect(result[2]):toBe("0x1")
	end)

	it("large value splits into both halves", function()
		-- Value with distinct low and high halves
		-- 5 * 2^128 + 255 = 0x5000000000000000000000000000000ff
		local result = CallData.encodeU256("0x5000000000000000000000000000000ff")
		expect(result[1]):toBe("0xff")
		expect(result[2]):toBe("0x5")
	end)
end)

--------------------------------------------------------------------------------
-- encodeArray
--------------------------------------------------------------------------------

describe("CallData - encodeArray", function()
	it("empty array has length 0", function()
		local result = CallData.encodeArray({})
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x0")
	end)

	it("single element array", function()
		local result = CallData.encodeArray({ "0x1" })
		expect(#result):toBe(2)
		expect(result[1]):toBe("0x1") -- length
		expect(result[2]):toBe("0x1") -- element
	end)

	it("multiple elements with length prefix", function()
		-- starknet.js: [256n, 128n] => ['2', '256', '128']
		local result = CallData.encodeArray({ "0x100", "0x80" })
		expect(#result):toBe(3)
		expect(result[1]):toBe("0x2") -- length
		expect(result[2]):toBe("0x100") -- element 0
		expect(result[3]):toBe("0x80") -- element 1
	end)

	it("preserves element values without modification", function()
		local result = CallData.encodeArray({ "0xabc", "0xdef", "0x123" })
		expect(#result):toBe(4)
		expect(result[1]):toBe("0x3")
		expect(result[2]):toBe("0xabc")
		expect(result[3]):toBe("0xdef")
		expect(result[4]):toBe("0x123")
	end)
end)

--------------------------------------------------------------------------------
-- encodeStruct
--------------------------------------------------------------------------------

describe("CallData - encodeStruct", function()
	it("empty struct produces empty array", function()
		local result = CallData.encodeStruct({})
		expect(#result):toBe(0)
	end)

	it("single field struct", function()
		local result = CallData.encodeStruct({ "0x74657374" })
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x74657374")
	end)

	it("multiple fields concatenated without length prefix", function()
		-- Unlike arrays, structs have no length prefix
		local result = CallData.encodeStruct({ "0x1", "0x2", "0x3" })
		expect(#result):toBe(3)
		expect(result[1]):toBe("0x1")
		expect(result[2]):toBe("0x2")
		expect(result[3]):toBe("0x3")
	end)
end)

--------------------------------------------------------------------------------
-- encodeMulticall
--------------------------------------------------------------------------------

describe("CallData - encodeMulticall", function()
	it("empty calls produces single zero element", function()
		-- starknet.js: fromCallsToExecuteCalldata_cairo1([]) => ['0']
		local result = CallData.encodeMulticall({})
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x0")
	end)

	it("single call encodes correctly", function()
		local result = CallData.encodeMulticall({
			{
				contractAddress = "0x123",
				entrypoint = "transfer",
				calldata = { "0xa" },
			},
		})
		-- Expected: [num_calls, addr, selector, calldata_len, calldata]
		expect(#result):toBe(5)
		expect(result[1]):toBe("0x1") -- num_calls
		expect(result[2]):toBe("0x123") -- address
		-- transfer selector from Keccak
		local expectedSelector = StarkField.toHex(Keccak.getSelectorFromName("transfer"))
		expect(result[3]):toBe(expectedSelector)
		expect(result[4]):toBe("0x1") -- calldata length
		expect(result[5]):toBe("0xa") -- calldata
	end)

	it("transfer selector matches starknet.js", function()
		-- starknet.js: getSelectorFromName('transfer') =
		-- 0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e
		local result = CallData.encodeMulticall({
			{
				contractAddress = "0x1",
				entrypoint = "transfer",
				calldata = {},
			},
		})
		expect(result[3]):toBe("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e")
	end)

	it("multiple calls match starknet.js cross-reference vector", function()
		-- starknet.js test vector: fromCallsToExecuteCalldata_cairo1
		-- calls = [
		--   { contractAddress: '0x123', entrypoint: 'transfer', calldata: [10] },
		--   { contractAddress: '0x456', entrypoint: 'mint', calldata: ['0x2000', BigInt(10000000)] }
		-- ]
		local result = CallData.encodeMulticall({
			{
				contractAddress = "0x123",
				entrypoint = "transfer",
				calldata = { "0xa" }, -- 10
			},
			{
				contractAddress = "0x456",
				entrypoint = "mint",
				calldata = { "0x2000", "0x989680" }, -- 8192, 10000000
			},
		})

		-- Expected 10 elements
		expect(#result):toBe(10)

		-- num_calls = 2
		expect(result[1]):toBe("0x2")

		-- Call 0: address
		expect(result[2]):toBe("0x123")

		-- Call 0: transfer selector
		expect(result[3]):toBe("0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e")

		-- Call 0: calldata length = 1
		expect(result[4]):toBe("0x1")

		-- Call 0: calldata = [0xa]
		expect(result[5]):toBe("0xa")

		-- Call 1: address
		expect(result[6]):toBe("0x456")

		-- Call 1: mint selector
		expect(result[7]):toBe("0x2f0b3c5710379609eb5495f1ecd348cb28167711b73609fe565a72734550354")

		-- Call 1: calldata length = 2
		expect(result[8]):toBe("0x2")

		-- Call 1: calldata
		expect(result[9]):toBe("0x2000")
		expect(result[10]):toBe("0x989680")
	end)

	it("call with empty calldata", function()
		local result = CallData.encodeMulticall({
			{
				contractAddress = "0xabc",
				entrypoint = "get_balance",
				calldata = {},
			},
		})
		expect(#result):toBe(4)
		expect(result[1]):toBe("0x1") -- num_calls
		expect(result[2]):toBe("0xabc") -- address
		-- selector is computed
		expect(result[4]):toBe("0x0") -- calldata length = 0
	end)
end)

--------------------------------------------------------------------------------
-- numberToHex
--------------------------------------------------------------------------------

describe("CallData - numberToHex", function()
	it("zero", function()
		expect(CallData.numberToHex(0)):toBe("0x0")
	end)

	it("small number", function()
		expect(CallData.numberToHex(42)):toBe("0x2a")
	end)

	it("256", function()
		expect(CallData.numberToHex(256)):toBe("0x100")
	end)

	it("large number", function()
		expect(CallData.numberToHex(10000000)):toBe("0x989680")
	end)
end)

--------------------------------------------------------------------------------
-- concat
--------------------------------------------------------------------------------

describe("CallData - concat", function()
	it("concatenates multiple arrays", function()
		local result = CallData.concat({ "0x1" }, { "0x2", "0x3" })
		expect(#result):toBe(3)
		expect(result[1]):toBe("0x1")
		expect(result[2]):toBe("0x2")
		expect(result[3]):toBe("0x3")
	end)

	it("handles empty arrays", function()
		local result = CallData.concat({}, { "0x1" }, {})
		expect(#result):toBe(1)
		expect(result[1]):toBe("0x1")
	end)

	it("practical ERC-20 transfer calldata composition", function()
		-- Build calldata for transfer(recipient, u256_amount)
		local recipient = "0xdeadbeef"
		local amount = "0x100" -- 256

		-- Compose: felt(recipient) + u256(amount)
		local calldata = CallData.concat(
			CallData.encodeFelt(recipient),
			CallData.encodeU256(amount)
		)

		-- Expected: [recipient, amount_low, amount_high]
		expect(#calldata):toBe(3)
		expect(calldata[1]):toBe("0xdeadbeef") -- recipient
		expect(calldata[2]):toBe("0x100") -- amount low
		expect(calldata[3]):toBe("0x0") -- amount high

		-- Now wrap in multicall
		local multicall = CallData.encodeMulticall({
			{
				contractAddress = "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				entrypoint = "transfer",
				calldata = calldata,
			},
		})

		-- Expected: [1, contract, selector, 3, recipient, amount_low, amount_high]
		expect(#multicall):toBe(7)
		expect(multicall[1]):toBe("0x1") -- num_calls
		expect(multicall[4]):toBe("0x3") -- calldata_len = 3 (recipient + u256 low + u256 high)
		expect(multicall[5]):toBe("0xdeadbeef")
		expect(multicall[6]):toBe("0x100")
		expect(multicall[7]):toBe("0x0")
	end)
end)
