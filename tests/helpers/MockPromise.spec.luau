--!strict
-- Tests for MockPromise helper (synchronous Promise shim for Lune tests)

local MockPromise = require("./MockPromise")

--------------------------------------------------------------------------------
-- MockPromise.all
--------------------------------------------------------------------------------

describe("MockPromise.all", function()
	it("resolves array of resolved promises", function()
		local p1 = MockPromise.resolve("a")
		local p2 = MockPromise.resolve("b")
		local result = MockPromise.all({ p1, p2 }):expect()
		expect(result[1]):toBe("a")
		expect(result[2]):toBe("b")
	end)

	it("rejects if any promise is rejected", function()
		local p1 = MockPromise.resolve("ok")
		local p2 = MockPromise.reject("fail")

		local p = MockPromise.all({ p1, p2 })
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("handles empty array", function()
		local result = MockPromise.all({}):expect()
		expect(#result):toBe(0)
	end)

	it("preserves order", function()
		local p1 = MockPromise.resolve(10)
		local p2 = MockPromise.resolve(20)
		local p3 = MockPromise.resolve(30)
		local result = MockPromise.all({ p1, p2, p3 }):expect()
		expect(result[1]):toBe(10)
		expect(result[2]):toBe(20)
		expect(result[3]):toBe(30)
	end)
end)

--------------------------------------------------------------------------------
-- MockPromise.resolve / reject / expect / getStatus
--------------------------------------------------------------------------------

describe("MockPromise - core API", function()
	it("resolve creates a resolved promise", function()
		local p = MockPromise.resolve(42)
		expect(p:getStatus()):toBe("Resolved")
		expect(p:expect()):toBe(42)
	end)

	it("reject creates a rejected promise", function()
		local p = MockPromise.reject("err")
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("expect on rejected promise throws the rejection value", function()
		local p = MockPromise.reject("boom")
		expect(function()
			p:expect()
		end):toThrow()
	end)

	it("andThen chains resolved values", function()
		local result = MockPromise.resolve(10)
			:andThen(function(v)
				return v * 2
			end)
			:expect()
		expect(result):toBe(20)
	end)

	it("catch handles rejected promises", function()
		local result = MockPromise.reject("fail")
			:catch(function(_err)
				return "recovered"
			end)
			:expect()
		expect(result):toBe("recovered")
	end)

	it("andThen passes through rejection", function()
		local p = MockPromise.reject("fail"):andThen(function(v)
			return v
		end)
		expect(p:getStatus()):toBe("Rejected")
	end)
end)
