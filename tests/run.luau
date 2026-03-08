--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")

-- Minimal test runner

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "table" then
		for k, v in a do
			if not deepEqual(v, (b :: any)[k]) then
				return false
			end
		end
		for k in b :: any do
			if (a :: any)[k] == nil then
				return false
			end
		end
		return true
	end
	if type(a) == "buffer" then
		local bufA = a :: buffer
		local bufB = b :: buffer
		if buffer.len(bufA) ~= buffer.len(bufB) then
			return false
		end
		for i = 0, buffer.len(bufA) - 1 do
			if buffer.readu8(bufA, i) ~= buffer.readu8(bufB, i) then
				return false
			end
		end
		return true
	end
	return false
end

local totalPassed = 0
local totalFailed = 0
local failures: { string } = {}

type TestCase = {
	name: string,
	fn: () -> (),
}

local currentSuite = ""
local tests: { TestCase } = {}

-- Public API
function describe(name: string, fn: () -> ())
	currentSuite = name
	tests = {}
	fn()

	print(`\n--- {name} ---`)
	for _, test in tests do
		local ok, err = pcall(test.fn)
		if ok then
			totalPassed += 1
			print(`  PASS  {test.name}`)
		else
			totalFailed += 1
			local msg = `{name} > {test.name}: {err}`
			table.insert(failures, msg)
			print(`  FAIL  {test.name}`)
			print(`         {err}`)
		end
	end
end

function it(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

function expect(value: any)
	return {
		toBe = function(_, expected: any)
			if value ~= expected then
				error(`Expected {expected}, got {value}`, 2)
			end
		end,
		toEqual = function(_, expected: any)
			if not deepEqual(value, expected) then
				error(`Expected {expected}, got {value}`, 2)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`Expected truthy, got {value}`, 2)
			end
		end,
		toBeFalsy = function()
			if value then
				error(`Expected falsy, got {value}`, 2)
			end
		end,
		toContain = function(_, substring: string)
			if type(value) ~= "string" or not string.find(value, substring, 1, true) then
				error(`Expected string containing '{substring}', got {tostring(value)}`, 2)
			end
		end,
		toBeNil = function()
			if value ~= nil then
				error(`Expected nil, got {value}`, 2)
			end
		end,
		toBeGreaterThan = function(_, expected: number)
			if type(value) ~= "number" or value <= expected then
				error(`Expected {value} > {expected}`, 2)
			end
		end,
		toBeGreaterThanOrEqual = function(_, expected: number)
			if type(value) ~= "number" or value < expected then
				error(`Expected {value} >= {expected}`, 2)
			end
		end,
		toThrow = function()
			if typeof(value) ~= "function" then
				error("Expected a function for toThrow", 2)
			end
			local ok, _ = pcall(value)
			if ok then
				error("Expected function to throw, but it did not", 2)
			end
		end,
		toThrowType = function(_, errorType: string)
			if typeof(value) ~= "function" then
				error("Expected a function for toThrowType", 2)
			end
			local ok, err = pcall(value)
			if ok then
				error("Expected function to throw, but it did not", 2)
			end
			if typeof(err) ~= "table" or typeof(err.is) ~= "function" then
				error(`Expected a StarknetError, got {typeof(err)}: {tostring(err)}`, 2)
			end
			if not err:is(errorType) then
				error(`Expected error type "{errorType}", got "{err._type}"`, 2)
			end
		end,
		toThrowCode = function(_, expectedCode: number)
			if typeof(value) ~= "function" then
				error("Expected a function for toThrowCode", 2)
			end
			local ok, err = pcall(value)
			if ok then
				error("Expected function to throw, but it did not", 2)
			end
			if typeof(err) ~= "table" then
				error(`Expected a StarknetError table, got {typeof(err)}: {tostring(err)}`, 2)
			end
			if err.code ~= expectedCode then
				error(`Expected error code {expectedCode}, got {err.code}`, 2)
			end
		end,
		toThrowMatching = function(_, predicate: (any) -> boolean)
			if typeof(value) ~= "function" then
				error("Expected a function for toThrowMatching", 2)
			end
			local ok, err = pcall(value)
			if ok then
				error("Expected function to throw, but it did not", 2)
			end
			if not predicate(err) then
				error(`Error did not match predicate: {tostring(err)}`, 2)
			end
		end,
	}
end

-- Recursively discover and run .spec.luau files
local function discoverTests(dir: string)
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			discoverTests(path)
		elseif string.match(entry, "%.spec%.luau$") then
			require(`../{string.gsub(path, "%.luau$", "")}`)
		end
	end
end

discoverTests("tests")

-- Summary
print(`\n=============================`)
print(`  {totalPassed} passed, {totalFailed} failed`)
print(`=============================`)

if totalFailed > 0 then
	print("\nFailures:")
	for _, msg in failures do
		print(`  {msg}`)
	end
	process.exit(1)
end
