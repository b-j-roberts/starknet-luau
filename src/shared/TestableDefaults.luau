--!strict
-- TestableDefaults: Shared defaults for _sleep/_clock dependency injection
-- Eliminates repeated anonymous function definitions across provider and paymaster modules

local TestableDefaults = {}

--- Default sleep: delegates to task.wait (Roblox runtime).
TestableDefaults.sleep = function(seconds: number)
	task.wait(seconds)
end

--- Default clock: delegates to os.clock.
TestableDefaults.clock = os.clock

return TestableDefaults
