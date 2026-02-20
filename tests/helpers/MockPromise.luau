--!strict
-- MockPromise: Minimal synchronous Promise implementation for Lune tests
-- Compatible with evaera/promise core API (new, resolve, reject, andThen, catch, expect)
-- Executes all callbacks synchronously for deterministic testing

local MockPromise = {}
MockPromise.__index = MockPromise

export type Status = "Started" | "Resolved" | "Rejected"

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
		if type(self._value) == "table" and self._value.message then
			error(self._value.message)
		end
		error(tostring(self._value))
	end
	error("Promise is still pending")
end

function MockPromise:getStatus(): Status
	return self._status
end

return MockPromise
