--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local task = require("@lune/task")

--------------------------------------------------------------------------------
-- CLI argument parsing
--------------------------------------------------------------------------------

local parallelMode = false
local singleFile: string? = nil
local jsonOutput = false

for i, arg in process.args do
	if arg == "--parallel" then
		parallelMode = true
	elseif arg == "--file" and process.args[i + 1] then
		singleFile = process.args[i + 1]
	elseif arg == "--json" then
		jsonOutput = true
	end
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Test framework state
--------------------------------------------------------------------------------

local totalPassed = 0
local totalFailed = 0
local failures: { string } = {}
local slowTests: { { name: string, elapsed: number } } = {}

local SLOW_THRESHOLD = 1.0 -- seconds

type TestCase = {
	name: string,
	fn: () -> (),
}

local currentSuite = ""
local tests: { TestCase } = {}
local beforeEachFns: { () -> () } = {}
local afterEachFns: { () -> () } = {}

--------------------------------------------------------------------------------
-- Public API: describe / it / beforeEach / afterEach / expect
--------------------------------------------------------------------------------

function describe(name: string, fn: () -> ())
	currentSuite = name
	tests = {}
	beforeEachFns = {}
	afterEachFns = {}
	fn()

	if not jsonOutput then
		print(`\n--- {name} ---`)
	end

	for _, testCase in tests do
		-- Run beforeEach hooks
		local hookFailed = false
		for _, hook in beforeEachFns do
			local hookOk, hookErr = pcall(hook)
			if not hookOk then
				totalFailed += 1
				local msg = `{name} > {testCase.name} [beforeEach]: {hookErr}`
				table.insert(failures, msg)
				if not jsonOutput then
					print(`  FAIL  {testCase.name} [beforeEach failed]`)
					print(`         {hookErr}`)
				end
				hookFailed = true
				break
			end
		end

		if hookFailed then
			continue
		end

		-- Run the test with timing
		local startTime = os.clock()
		local ok, err = pcall(testCase.fn)
		local elapsed = os.clock() - startTime

		-- Run afterEach hooks (always, even on test failure)
		for _, hook in afterEachFns do
			pcall(hook)
		end

		if ok then
			totalPassed += 1
			if not jsonOutput then
				if elapsed >= SLOW_THRESHOLD then
					print(`  PASS  {testCase.name} ({string.format("%.2fs", elapsed)})`)
					table.insert(slowTests, { name = `{name} > {testCase.name}`, elapsed = elapsed })
				else
					print(`  PASS  {testCase.name}`)
				end
			end
		else
			totalFailed += 1
			local msg = `{name} > {testCase.name}: {err}`
			table.insert(failures, msg)
			if not jsonOutput then
				print(`  FAIL  {testCase.name}`)
				print(`         {err}`)
			end
		end
	end
end

function it(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

function beforeEach(fn: () -> ())
	table.insert(beforeEachFns, fn)
end

function afterEach(fn: () -> ())
	table.insert(afterEachFns, fn)
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

--------------------------------------------------------------------------------
-- Spec file discovery
--------------------------------------------------------------------------------

local function discoverSpecFiles(dir: string): { string }
	local specFiles: { string } = {}
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			for _, subFile in discoverSpecFiles(path) do
				table.insert(specFiles, subFile)
			end
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(specFiles, path)
		end
	end
	return specFiles
end

--------------------------------------------------------------------------------
-- Sequential execution (default)
--------------------------------------------------------------------------------

local function runSequential()
	local specFiles = discoverSpecFiles("tests")
	for _, path in specFiles do
		require(`../{string.gsub(path, "%.luau$", "")}`)
	end
end

--------------------------------------------------------------------------------
-- Single-file execution (used by --parallel subprocesses)
--------------------------------------------------------------------------------

local function runSingleFile(filePath: string)
	require(`../{string.gsub(filePath, "%.luau$", "")}`)
end

--------------------------------------------------------------------------------
-- Parallel execution (--parallel flag)
--------------------------------------------------------------------------------

local function runParallel()
	local specFiles = discoverSpecFiles("tests")
	local pending = #specFiles

	type FileResult = {
		file: string,
		passed: number,
		failed: number,
		failures: { string },
		elapsed: number,
	}

	local results: { FileResult } = {}
	local completedCount = 0

	print(`Running {#specFiles} spec files in parallel...\n`)
	local suiteStart = os.clock()

	for i, specFile in specFiles do
		task.spawn(function()
			local fileStart = os.clock()
			local result = process.exec("lune", { "run", "tests/run", "--file", specFile, "--json" })
			local fileElapsed = os.clock() - fileStart

			local fileResult: FileResult = {
				file = specFile,
				passed = 0,
				failed = 0,
				failures = {},
				elapsed = fileElapsed,
			}

			if result.ok then
				-- Parse JSON summary from last line of stdout
				local trimmed = string.gsub(result.stdout, "%s+$", "")
				local lastNewline = string.find(trimmed, "\n[^\n]*$")
				local lastLine = if lastNewline then string.sub(trimmed, lastNewline + 1) else trimmed

				local parseOk, parsed = pcall(serde.decode, "json" :: any, lastLine)
				if parseOk and type(parsed) == "table" then
					fileResult.passed = (parsed :: any).passed or 0
					fileResult.failed = (parsed :: any).failed or 0
					local parsedFailures = (parsed :: any).failures
					if type(parsedFailures) == "table" then
						for _, f in parsedFailures :: { any } do
							table.insert(fileResult.failures, tostring(f))
						end
					end
				end
			else
				fileResult.failed = 1
				local errMsg = if #result.stderr > 0 then result.stderr else result.stdout
				table.insert(fileResult.failures, `{specFile}: process exited with code {result.code}\n{errMsg}`)
			end

			results[i] = fileResult
			completedCount += 1

			-- Progress indicator
			local status = if fileResult.failed > 0 then "FAIL" else "PASS"
			print(
				`  [{completedCount}/{#specFiles}] {status}  {specFile} ({string.format("%.2fs", fileElapsed)})`
			)

			pending -= 1
		end)
	end

	-- Wait for all subprocesses to complete
	while pending > 0 do
		task.wait(0.01)
	end

	local suiteElapsed = os.clock() - suiteStart

	-- Aggregate results
	for _, r in results do
		totalPassed += r.passed
		totalFailed += r.failed
		for _, f in r.failures do
			table.insert(failures, f)
		end
	end

	print(`\nParallel execution completed in {string.format("%.2fs", suiteElapsed)}`)
end

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------

if singleFile then
	runSingleFile(singleFile)
elseif parallelMode then
	runParallel()
else
	runSequential()
end

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

if jsonOutput then
	-- Structured output for subprocess communication
	print(serde.encode("json" :: any, {
		passed = totalPassed,
		failed = totalFailed,
		failures = failures,
	}))
else
	print(`\n=============================`)
	print(`  {totalPassed} passed, {totalFailed} failed`)
	print(`=============================`)

	if #slowTests > 0 then
		print("\nSlow tests (>1s):")
		table.sort(slowTests, function(a, b)
			return a.elapsed > b.elapsed
		end)
		for _, slow in slowTests do
			print(`  {string.format("%.2fs", slow.elapsed)}  {slow.name}`)
		end
	end

	if totalFailed > 0 then
		print("\nFailures:")
		for _, msg in failures do
			print(`  {msg}`)
		end
		process.exit(1)
	end
end
