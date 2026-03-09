--!strict
-- MockPromise: Minimal synchronous Promise implementation for Lune tests
-- Compatible with evaera/promise core API (new, resolve, reject, andThen, catch, expect)
-- Executes all callbacks synchronously for deterministic testing

local MockPromise = {}
MockPromise.__index = MockPromise

export type Status = "Started" | "Resolved" | "Rejected" | "Cancelled"

export type MockPromise = {
	andThen: (self: MockPromise, onResolve: ((value: any) -> any)?) -> MockPromise,
	catch: (self: MockPromise, onReject: ((err: any) -> any)?) -> MockPromise,
	expect: (self: MockPromise) -> any,
	getStatus: (self: MockPromise) -> Status,
}

function MockPromise.new(executor: (resolve: (any) -> (), reject: (any) -> ()) -> ()): MockPromise
	local self = setmetatable({
		_status = "Started" :: Status,
		_value = nil :: any,
	}, MockPromise)

	local function resolve(value: any)
		if self._status == "Started" then
			self._status = "Resolved"
			self._value = value
		end
	end

	local function reject(reason: any)
		if self._status == "Started" then
			self._status = "Rejected"
			self._value = reason
		end
	end

	-- Execute synchronously
	local ok, err = pcall(executor, resolve, reject)
	if not ok and self._status == "Started" then
		self._status = "Rejected"
		self._value = err
	end

	return self :: any
end

function MockPromise.resolve(value: any): MockPromise
	return MockPromise.new(function(resolve, _reject)
		resolve(value)
	end)
end

function MockPromise.reject(reason: any): MockPromise
	return MockPromise.new(function(_resolve, reject)
		reject(reason)
	end)
end

function MockPromise:andThen(onResolve: ((value: any) -> any)?): MockPromise
	if self._status == "Resolved" and onResolve then
		local ok, result = pcall(onResolve, self._value)
		if ok then
			-- If result is a MockPromise, unwrap it
			if type(result) == "table" and getmetatable(result) == MockPromise then
				return result
			end
			return MockPromise.resolve(result)
		else
			return MockPromise.reject(result)
		end
	elseif self._status == "Rejected" then
		-- Pass through rejection
		return MockPromise.reject(self._value)
	end
	-- Still pending (shouldn't happen in sync execution)
	return self :: any
end

function MockPromise:catch(onReject: ((err: any) -> any)?): MockPromise
	if self._status == "Rejected" and onReject then
		local ok, result = pcall(onReject, self._value)
		if ok then
			if type(result) == "table" and getmetatable(result) == MockPromise then
				return result
			end
			return MockPromise.resolve(result)
		else
			return MockPromise.reject(result)
		end
	end
	return self :: any
end

function MockPromise:expect(): any
	if self._status == "Resolved" then
		return self._value
	elseif self._status == "Rejected" then
		-- Preserve structured error identity (tables pass through error() unchanged)
		-- Level 2 points stack trace at the caller, not this method
		error(self._value, 2)
	end
	error("Promise is still pending", 2)
end

function MockPromise:getStatus(): Status
	return self._status
end

--- Wait for all promises to resolve. Returns a promise resolving to an array of results.
--- If any promise rejects, the returned promise rejects with that error.
function MockPromise.all(promises: { MockPromise }): MockPromise
	return MockPromise.new(function(resolve, reject)
		local results = {}
		for i, p in promises do
			if p._status == "Rejected" then
				reject(p._value)
				return
			elseif p._status == "Resolved" then
				results[i] = p._value
			else
				reject("Promise.all: promise is still pending")
				return
			end
		end
		resolve(results)
	end)
end

--- Runs callback regardless of resolve/reject. The returned promise preserves
--- the original settlement (resolve/reject) unless the callback throws.
function MockPromise:finally(onFinally: () -> ()): MockPromise
	if self._status == "Resolved" then
		local ok, err = pcall(onFinally)
		if ok then
			return MockPromise.resolve(self._value)
		else
			return MockPromise.reject(err)
		end
	elseif self._status == "Rejected" then
		local ok, err = pcall(onFinally)
		if ok then
			return MockPromise.reject(self._value)
		else
			return MockPromise.reject(err)
		end
	end
	return self :: any
end

--- Cancel a pending promise. Sets status to "Cancelled".
--- No-op if already settled.
function MockPromise:cancel()
	if self._status == "Started" then
		self._status = "Cancelled"
		self._value = nil
	end
end

--- Returns a promise that settles with the first settled promise in the array.
--- If the array is empty, the returned promise stays pending.
function MockPromise.race(promises: { MockPromise }): MockPromise
	return MockPromise.new(function(resolve, reject)
		for _, p in promises do
			if p._status == "Resolved" then
				resolve(p._value)
				return
			elseif p._status == "Rejected" then
				reject(p._value)
				return
			end
		end
		-- All still pending — returned promise stays pending
	end)
end

--- Returns a promise that resolves when all promises have settled (resolved or rejected).
--- The result is an array of { status: string, value: any? } tables.
function MockPromise.allSettled(promises: { MockPromise }): MockPromise
	return MockPromise.new(function(resolve, reject)
		local results = {}
		for i, p in promises do
			if p._status == "Resolved" then
				results[i] = { status = "Resolved", value = p._value }
			elseif p._status == "Rejected" then
				results[i] = { status = "Rejected", value = p._value }
			else
				reject("Promise.allSettled: promise is still pending")
				return
			end
		end
		resolve(results)
	end)
end

return MockPromise
