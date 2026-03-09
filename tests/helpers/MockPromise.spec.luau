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

--------------------------------------------------------------------------------
-- MockPromise:finally
--------------------------------------------------------------------------------

describe("MockPromise:finally", function()
	it("runs callback on resolved promise", function()
		local called = false
		local result = MockPromise.resolve(42)
			:finally(function()
				called = true
			end)
			:expect()
		expect(called):toBe(true)
		expect(result):toBe(42)
	end)

	it("runs callback on rejected promise", function()
		local called = false
		local p = MockPromise.reject("err"):finally(function()
			called = true
		end)
		expect(called):toBe(true)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("preserves resolved value through finally", function()
		local result = MockPromise.resolve("hello")
			:finally(function() end)
			:expect()
		expect(result):toBe("hello")
	end)

	it("preserves rejection through finally", function()
		local p = MockPromise.reject("original-error"):finally(function() end)
		expect(p:getStatus()):toBe("Rejected")
		local caught = p:catch(function(err)
			return err
		end):expect()
		expect(caught):toBe("original-error")
	end)

	it("rejects if finally callback throws (resolved case)", function()
		local p = MockPromise.resolve(42):finally(function()
			error("finally-error")
		end)
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("rejects if finally callback throws (rejected case)", function()
		local p = MockPromise.reject("original"):finally(function()
			error("finally-error")
		end)
		expect(p:getStatus()):toBe("Rejected")
		-- The finally error replaces the original
		local caught = p:catch(function(err)
			return tostring(err)
		end):expect()
		expect(type(caught)):toBe("string")
	end)

	it("chains with andThen after finally", function()
		local result = MockPromise.resolve(10)
			:finally(function() end)
			:andThen(function(v)
				return v * 3
			end)
			:expect()
		expect(result):toBe(30)
	end)
end)

--------------------------------------------------------------------------------
-- MockPromise:cancel
--------------------------------------------------------------------------------

describe("MockPromise:cancel", function()
	it("cancels a pending promise", function()
		local p = MockPromise.new(function(_resolve, _reject)
			-- Don't resolve or reject — stays pending
			-- Note: in sync MockPromise this normally doesn't happen,
			-- but we can simulate by not calling either
		end)
		-- The executor ran but didn't call resolve/reject, so status is Started
		expect(p:getStatus()):toBe("Started")
		p:cancel()
		expect(p:getStatus()):toBe("Cancelled")
	end)

	it("is a no-op on resolved promise", function()
		local p = MockPromise.resolve(42)
		p:cancel()
		expect(p:getStatus()):toBe("Resolved")
		expect(p:expect()):toBe(42)
	end)

	it("is a no-op on rejected promise", function()
		local p = MockPromise.reject("err")
		p:cancel()
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("sets value to nil on cancel", function()
		local p = MockPromise.new(function() end)
		p:cancel()
		expect(p._value):toBeNil()
	end)
end)

--------------------------------------------------------------------------------
-- MockPromise.race
--------------------------------------------------------------------------------

describe("MockPromise.race", function()
	it("resolves with first resolved promise", function()
		local p1 = MockPromise.resolve("first")
		local p2 = MockPromise.resolve("second")
		local result = MockPromise.race({ p1, p2 }):expect()
		expect(result):toBe("first")
	end)

	it("rejects with first rejected promise", function()
		local p1 = MockPromise.reject("error1")
		local p2 = MockPromise.resolve("ok")
		local p = MockPromise.race({ p1, p2 })
		expect(p:getStatus()):toBe("Rejected")
	end)

	it("resolves even if later promises reject", function()
		local p1 = MockPromise.resolve("winner")
		local p2 = MockPromise.reject("loser")
		local result = MockPromise.race({ p1, p2 }):expect()
		expect(result):toBe("winner")
	end)

	it("returns pending promise for empty array", function()
		local p = MockPromise.race({})
		expect(p:getStatus()):toBe("Started")
	end)

	it("handles single promise", function()
		local p = MockPromise.race({ MockPromise.resolve(99) })
		expect(p:expect()):toBe(99)
	end)

	it("first rejection wins over later resolution", function()
		local p1 = MockPromise.reject("fail-first")
		local p2 = MockPromise.resolve("resolve-second")
		local p = MockPromise.race({ p1, p2 })
		expect(p:getStatus()):toBe("Rejected")
		local caught = p:catch(function(err)
			return err
		end):expect()
		expect(caught):toBe("fail-first")
	end)
end)

--------------------------------------------------------------------------------
-- MockPromise.allSettled
--------------------------------------------------------------------------------

describe("MockPromise.allSettled", function()
	it("settles all resolved promises", function()
		local p1 = MockPromise.resolve("a")
		local p2 = MockPromise.resolve("b")
		local results = MockPromise.allSettled({ p1, p2 }):expect()
		expect(#results):toBe(2)
		expect(results[1].status):toBe("Resolved")
		expect(results[1].value):toBe("a")
		expect(results[2].status):toBe("Resolved")
		expect(results[2].value):toBe("b")
	end)

	it("settles mix of resolved and rejected", function()
		local p1 = MockPromise.resolve("ok")
		local p2 = MockPromise.reject("fail")
		local p3 = MockPromise.resolve("also ok")
		local results = MockPromise.allSettled({ p1, p2, p3 }):expect()
		expect(#results):toBe(3)
		expect(results[1].status):toBe("Resolved")
		expect(results[1].value):toBe("ok")
		expect(results[2].status):toBe("Rejected")
		expect(results[2].value):toBe("fail")
		expect(results[3].status):toBe("Resolved")
		expect(results[3].value):toBe("also ok")
	end)

	it("handles all rejected", function()
		local p1 = MockPromise.reject("err1")
		local p2 = MockPromise.reject("err2")
		local results = MockPromise.allSettled({ p1, p2 }):expect()
		expect(#results):toBe(2)
		expect(results[1].status):toBe("Rejected")
		expect(results[2].status):toBe("Rejected")
	end)

	it("handles empty array", function()
		local results = MockPromise.allSettled({}):expect()
		expect(#results):toBe(0)
	end)

	it("preserves order", function()
		local p1 = MockPromise.resolve(10)
		local p2 = MockPromise.reject(20)
		local p3 = MockPromise.resolve(30)
		local results = MockPromise.allSettled({ p1, p2, p3 }):expect()
		expect(results[1].value):toBe(10)
		expect(results[2].value):toBe(20)
		expect(results[3].value):toBe(30)
	end)
end)

--------------------------------------------------------------------------------
-- beforeEach / afterEach hooks (test runner features)
--------------------------------------------------------------------------------

describe("beforeEach / afterEach hooks", function()
	local counter = 0
	local log: { string } = {}

	beforeEach(function()
		counter = 0
		table.clear(log)
	end)

	afterEach(function()
		table.insert(log, "cleanup")
	end)

	it("beforeEach resets state before each test", function()
		expect(counter):toBe(0)
		counter = 42
	end)

	it("beforeEach ran again for this test", function()
		-- counter was set to 42 in the previous test, but beforeEach resets it
		expect(counter):toBe(0)
	end)

	it("afterEach runs after each test", function()
		-- afterEach from the previous test ran, but beforeEach cleared the log
		-- So log should be empty at the start of this test
		expect(#log):toBe(0)
	end)
end)

describe("multiple beforeEach hooks", function()
	local a = 0
	local b = 0

	beforeEach(function()
		a = 10
	end)

	beforeEach(function()
		b = a + 5
	end)

	it("runs hooks in registration order", function()
		expect(a):toBe(10)
		expect(b):toBe(15)
	end)
end)
