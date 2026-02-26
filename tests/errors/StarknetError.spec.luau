--!strict
local StarknetError = require("../../src/errors/StarknetError")
local ErrorCodes = require("../../src/errors/ErrorCodes")

describe("StarknetError", function()
	-- ============================================================
	-- ErrorCodes
	-- ============================================================

	describe("ErrorCodes", function()
		it("has validation codes in 1000 range", function()
			expect(ErrorCodes.INVALID_ARGUMENT.code):toBe(1000)
			expect(ErrorCodes.REQUIRED_FIELD.code):toBe(1001)
			expect(ErrorCodes.OUT_OF_RANGE.code):toBe(1002)
			expect(ErrorCodes.INVALID_FORMAT.code):toBe(1003)
		end)

		it("has RPC codes in 2000 range", function()
			expect(ErrorCodes.RPC_ERROR.code):toBe(2000)
			expect(ErrorCodes.NETWORK_ERROR.code):toBe(2001)
			expect(ErrorCodes.RATE_LIMIT.code):toBe(2002)
			expect(ErrorCodes.TIMEOUT.code):toBe(2003)
			expect(ErrorCodes.TRANSACTION_REVERTED.code):toBe(2004)
			expect(ErrorCodes.TRANSACTION_REJECTED.code):toBe(2005)
		end)

		it("has signing codes in 3000 range", function()
			expect(ErrorCodes.SIGNING_ERROR.code):toBe(3000)
			expect(ErrorCodes.INVALID_PRIVATE_KEY.code):toBe(3001)
			expect(ErrorCodes.KEY_OUT_OF_RANGE.code):toBe(3003)
			expect(ErrorCodes.MATH_ERROR.code):toBe(3010)
		end)

		it("has ABI codes in 4000 range", function()
			expect(ErrorCodes.ABI_ERROR.code):toBe(4000)
			expect(ErrorCodes.UNKNOWN_TYPE.code):toBe(4001)
			expect(ErrorCodes.ENCODE_ERROR.code):toBe(4002)
			expect(ErrorCodes.DECODE_ERROR.code):toBe(4003)
			expect(ErrorCodes.UNKNOWN_ENUM_VARIANT.code):toBe(4004)
			expect(ErrorCodes.FUNCTION_NOT_FOUND.code):toBe(4005)
			expect(ErrorCodes.ARGUMENT_COUNT.code):toBe(4006)
		end)

		it("has transaction codes in 5000 range", function()
			expect(ErrorCodes.TRANSACTION_ERROR.code):toBe(5000)
			expect(ErrorCodes.FEE_ESTIMATION_FAILED.code):toBe(5001)
		end)

		it("each code has a name field", function()
			expect(ErrorCodes.REQUIRED_FIELD.name):toBe("REQUIRED_FIELD")
			expect(ErrorCodes.RPC_ERROR.name):toBe("RPC_ERROR")
			expect(ErrorCodes.SIGNING_ERROR.name):toBe("SIGNING_ERROR")
		end)
	end)

	-- ============================================================
	-- Factory constructors
	-- ============================================================

	describe("StarknetError.new", function()
		it("creates a base error with message", function()
			local err = StarknetError.new("something went wrong")
			expect(err._type):toBe("StarknetError")
			expect(err.message):toBe("something went wrong")
			expect(err.code == nil):toBeTruthy()
			expect(err.data == nil):toBeTruthy()
		end)

		it("creates a base error with code and data", function()
			local err = StarknetError.new("bad input", 1000, { field = "name" })
			expect(err.code):toBe(1000)
			expect(err.data.field):toBe("name")
		end)
	end)

	describe("StarknetError.rpc", function()
		it("creates an RpcError with rpcCode", function()
			local err = StarknetError.rpc("node error", 2000, -32600, { raw = "data" })
			expect(err._type):toBe("RpcError")
			expect(err.message):toBe("node error")
			expect(err.code):toBe(2000)
			expect(err.rpcCode):toBe(-32600)
			expect(err.data.raw):toBe("data")
		end)

		it("works without optional fields", function()
			local err = StarknetError.rpc("timeout")
			expect(err._type):toBe("RpcError")
			expect(err.code == nil):toBeTruthy()
			expect(err.rpcCode == nil):toBeTruthy()
		end)
	end)

	describe("StarknetError.signing", function()
		it("creates a SigningError", function()
			local err = StarknetError.signing("bad key", 3001)
			expect(err._type):toBe("SigningError")
			expect(err.message):toBe("bad key")
			expect(err.code):toBe(3001)
		end)
	end)

	describe("StarknetError.abi", function()
		it("creates an AbiError", function()
			local err = StarknetError.abi("unknown type", 4001)
			expect(err._type):toBe("AbiError")
			expect(err.message):toBe("unknown type")
			expect(err.code):toBe(4001)
		end)
	end)

	describe("StarknetError.validation", function()
		it("creates a ValidationError with hint", function()
			local err = StarknetError.validation("missing address", 1001, "Pass address in config")
			expect(err._type):toBe("ValidationError")
			expect(err.message):toBe("missing address")
			expect(err.code):toBe(1001)
			expect(err.hint):toBe("Pass address in config")
		end)

		it("works without hint", function()
			local err = StarknetError.validation("bad value", 1000)
			expect(err.hint == nil):toBeTruthy()
		end)
	end)

	describe("StarknetError.transaction", function()
		it("creates a TransactionError with revertReason and executionTrace", function()
			local err = StarknetError.transaction("tx reverted", 2004, "out of gas", { trace = "..." }, { hash = "0x1" })
			expect(err._type):toBe("TransactionError")
			expect(err.message):toBe("tx reverted")
			expect(err.code):toBe(2004)
			expect(err.revertReason):toBe("out of gas")
			expect(err.executionTrace.trace):toBe("...")
			expect(err.data.hash):toBe("0x1")
		end)

		it("works without optional fields", function()
			local err = StarknetError.transaction("rejected")
			expect(err.revertReason == nil):toBeTruthy()
			expect(err.executionTrace == nil):toBeTruthy()
		end)
	end)

	-- ============================================================
	-- :is() type hierarchy
	-- ============================================================

	describe(":is() hierarchy", function()
		it("base error is StarknetError", function()
			local err = StarknetError.new("msg")
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("base error is not RpcError", function()
			local err = StarknetError.new("msg")
			expect(err:is("RpcError")):toBeFalsy()
		end)

		it("RpcError is RpcError and StarknetError", function()
			local err = StarknetError.rpc("msg")
			expect(err:is("RpcError")):toBeTruthy()
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("RpcError is not SigningError", function()
			local err = StarknetError.rpc("msg")
			expect(err:is("SigningError")):toBeFalsy()
		end)

		it("SigningError is SigningError and StarknetError", function()
			local err = StarknetError.signing("msg")
			expect(err:is("SigningError")):toBeTruthy()
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("AbiError is AbiError and StarknetError", function()
			local err = StarknetError.abi("msg")
			expect(err:is("AbiError")):toBeTruthy()
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("ValidationError is ValidationError and StarknetError", function()
			local err = StarknetError.validation("msg")
			expect(err:is("ValidationError")):toBeTruthy()
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("TransactionError is TransactionError and StarknetError", function()
			local err = StarknetError.transaction("msg")
			expect(err:is("TransactionError")):toBeTruthy()
			expect(err:is("StarknetError")):toBeTruthy()
		end)

		it("unknown type returns false", function()
			local err = StarknetError.new("msg")
			expect(err:is("UnknownType")):toBeFalsy()
		end)

		it("sibling types are not each other", function()
			local rpc = StarknetError.rpc("msg")
			local signing = StarknetError.signing("msg")
			local abi = StarknetError.abi("msg")
			local validation = StarknetError.validation("msg")
			local tx = StarknetError.transaction("msg")

			expect(rpc:is("SigningError")):toBeFalsy()
			expect(signing:is("AbiError")):toBeFalsy()
			expect(abi:is("ValidationError")):toBeFalsy()
			expect(validation:is("TransactionError")):toBeFalsy()
			expect(tx:is("RpcError")):toBeFalsy()
		end)
	end)

	-- ============================================================
	-- tostring
	-- ============================================================

	describe("tostring", function()
		it("formats with type and code", function()
			local err = StarknetError.new("bad input", 1000)
			expect(tostring(err)):toBe("StarknetError [1000]: bad input")
		end)

		it("formats without code", function()
			local err = StarknetError.new("bad input")
			expect(tostring(err)):toBe("StarknetError: bad input")
		end)

		it("formats subtype with code", function()
			local err = StarknetError.rpc("node down", 2001)
			expect(tostring(err)):toBe("RpcError [2001]: node down")
		end)

		it("formats subtype without code", function()
			local err = StarknetError.signing("bad key")
			expect(tostring(err)):toBe("SigningError: bad key")
		end)
	end)

	-- ============================================================
	-- isStarknetError
	-- ============================================================

	describe("isStarknetError", function()
		it("returns true for base error", function()
			local err = StarknetError.new("msg")
			expect(StarknetError.isStarknetError(err)):toBeTruthy()
		end)

		it("returns true for subtypes", function()
			expect(StarknetError.isStarknetError(StarknetError.rpc("msg"))):toBeTruthy()
			expect(StarknetError.isStarknetError(StarknetError.signing("msg"))):toBeTruthy()
			expect(StarknetError.isStarknetError(StarknetError.abi("msg"))):toBeTruthy()
			expect(StarknetError.isStarknetError(StarknetError.validation("msg"))):toBeTruthy()
			expect(StarknetError.isStarknetError(StarknetError.transaction("msg"))):toBeTruthy()
		end)

		it("returns false for plain string", function()
			expect(StarknetError.isStarknetError("some error")):toBeFalsy()
		end)

		it("returns false for nil", function()
			expect(StarknetError.isStarknetError(nil)):toBeFalsy()
		end)

		it("returns false for number", function()
			expect(StarknetError.isStarknetError(42)):toBeFalsy()
		end)

		it("returns false for plain table without _type", function()
			expect(StarknetError.isStarknetError({ message = "test" })):toBeFalsy()
		end)

		it("returns false for table with unknown _type", function()
			expect(StarknetError.isStarknetError({ _type = "FakeError", message = "test", is = function() end })):toBeFalsy()
		end)
	end)

	-- ============================================================
	-- pcall round-trip
	-- ============================================================

	describe("pcall round-trip", function()
		it("error() preserves table identity through pcall", function()
			local original = StarknetError.signing("key too small", 3001)
			local ok, caught = pcall(function()
				error(original)
			end)
			expect(ok):toBeFalsy()
			expect(caught):toBe(original)
		end)

		it("caught error retains :is() method", function()
			local original = StarknetError.rpc("timeout", 2003)
			local _, caught = pcall(function()
				error(original)
			end)
			expect(caught:is("RpcError")):toBeTruthy()
			expect(caught:is("StarknetError")):toBeTruthy()
		end)

		it("caught error retains fields", function()
			local original = StarknetError.transaction("reverted", 2004, "out of gas")
			local _, caught = pcall(function()
				error(original)
			end)
			expect(caught.revertReason):toBe("out of gas")
			expect(caught.code):toBe(2004)
		end)
	end)

	-- ============================================================
	-- Re-exported ErrorCodes
	-- ============================================================

	describe("re-exported ErrorCodes", function()
		it("StarknetError.ErrorCodes is the same as ErrorCodes module", function()
			expect(StarknetError.ErrorCodes.RPC_ERROR.code):toBe(2000)
			expect(StarknetError.ErrorCodes.REQUIRED_FIELD.code):toBe(1001)
		end)
	end)
end)
