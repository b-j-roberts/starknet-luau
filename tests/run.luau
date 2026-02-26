--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")

-- Minimal test runner
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
			if value ~= expected then
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
