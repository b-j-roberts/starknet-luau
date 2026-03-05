--!strict
local PaymasterPolicy = require("../../src/paymaster/PaymasterPolicy")
local BigInt = require("../../src/crypto/BigInt")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local GAME_CONTRACT = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
local TOKEN_CONTRACT = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
local OTHER_CONTRACT = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

local PLAYER_1 = 12345
local PLAYER_2 = 67890
local PLAYER_3 = 11111

local function makeCall(contractAddress: string, entrypoint: string, calldata: { string }?): any
	return {
		contractAddress = contractAddress,
		entrypoint = entrypoint,
		calldata = calldata or {},
	}
end

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("PaymasterPolicy.new", function()
	it("creates policy with minimal config", function()
		local policy = PaymasterPolicy.new({})
		expect(policy):toBeTruthy()
	end)

	it("creates policy with all options", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
			allowedPlayers = { { playerId = PLAYER_1 } },
			maxFeePerTx = "0x1000",
			maxTxPerPlayer = 5,
			timeWindow = 60,
		})
		expect(policy):toBeTruthy()
	end)

	it("accepts empty arrays (no restriction)", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = {},
			allowedMethods = {},
			allowedPlayers = {},
		})
		-- Empty arrays = no restriction, same as omitting
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("accepts maxFeePerTx as hex string", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0xDE0B6B3A7640000" })
		expect(policy):toBeTruthy()
	end)

	it("accepts maxFeePerTx as BigInt buffer", function()
		local fee = BigInt.fromHex("0xDE0B6B3A7640000")
		local policy = PaymasterPolicy.new({ maxFeePerTx = fee })
		expect(policy):toBeTruthy()
	end)

	it("rejects allowedContracts entry without address", function()
		expect(function()
			PaymasterPolicy.new({
				allowedContracts = { { address = "" } },
			})
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "allowedContracts entry must have an address", 1, true) ~= nil
		end)
	end)

	it("rejects allowedMethods entry without contract", function()
		expect(function()
			PaymasterPolicy.new({
				allowedMethods = { { contract = "", selector = "transfer" } },
			})
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "allowedMethods entry must have a contract address", 1, true) ~= nil
		end)
	end)

	it("rejects allowedMethods entry without selector", function()
		expect(function()
			PaymasterPolicy.new({
				allowedMethods = { { contract = GAME_CONTRACT, selector = "" } },
			})
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "allowedMethods entry must have a selector", 1, true) ~= nil
		end)
	end)

	it("rejects allowedPlayers entry without playerId", function()
		expect(function()
			PaymasterPolicy.new({
				allowedPlayers = { { playerId = nil :: any } },
			})
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "allowedPlayers entry must have a playerId", 1, true) ~= nil
		end)
	end)

	it("rejects maxTxPerPlayer <= 0", function()
		expect(function()
			PaymasterPolicy.new({ maxTxPerPlayer = 0, timeWindow = 60 })
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "maxTxPerPlayer must be a positive number", 1, true) ~= nil
		end)
	end)

	it("rejects negative maxTxPerPlayer", function()
		expect(function()
			PaymasterPolicy.new({ maxTxPerPlayer = -1, timeWindow = 60 })
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "maxTxPerPlayer must be a positive number", 1, true) ~= nil
		end)
	end)

	it("rejects timeWindow <= 0", function()
		expect(function()
			PaymasterPolicy.new({ maxTxPerPlayer = 5, timeWindow = 0 })
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "timeWindow must be a positive number", 1, true) ~= nil
		end)
	end)

	it("rejects maxTxPerPlayer without timeWindow", function()
		expect(function()
			PaymasterPolicy.new({ maxTxPerPlayer = 5 })
		end):toThrowMatching(function(err)
			return string.find(tostring(err), "timeWindow is required when maxTxPerPlayer is set", 1, true) ~= nil
		end)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Player whitelist
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — player whitelist", function()
	it("allows any player when no whitelist", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("allows whitelisted player", function()
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 }, { playerId = PLAYER_2 } },
		})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("rejects non-whitelisted player", function()
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 } },
		})
		local result = policy:validate(PLAYER_3, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("not in the allowed players list")
		expect(result.reason):toContain(tostring(PLAYER_3))
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Contract whitelist
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — contract whitelist", function()
	it("allows any contract when no whitelist", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, { makeCall(OTHER_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("allows whitelisted contract", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("rejects non-whitelisted contract", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, { makeCall(OTHER_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("not in the allowed contracts list")
	end)

	it("normalizes hex addresses for comparison", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = "0x00ABC" } },
		})
		-- Same address with different formatting
		local result = policy:validate(PLAYER_1, { makeCall("0x0abc", "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("normalizes uppercase vs lowercase", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = "0xABCDEF" } },
		})
		local result = policy:validate(PLAYER_1, { makeCall("0xabcdef", "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("validates all calls in multicall", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, {
			makeCall(GAME_CONTRACT, "approve"),
			makeCall(OTHER_CONTRACT, "transfer"),
		})
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("not in the allowed contracts list")
	end)

	it("allows multicall when all contracts whitelisted", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT }, { address = TOKEN_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, {
			makeCall(GAME_CONTRACT, "approve"),
			makeCall(TOKEN_CONTRACT, "transfer"),
		})
		expect(result.allowed):toBe(true)
	end)

	it("rejects call without contractAddress", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, { { entrypoint = "transfer" } })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("missing contractAddress")
	end)

	it("accepts 'to' as alias for contractAddress", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, { { to = GAME_CONTRACT, entrypoint = "transfer" } })
		expect(result.allowed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Method whitelist
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — method whitelist", function()
	it("allows any method when no whitelist", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "anything") })
		expect(result.allowed):toBe(true)
	end)

	it("allows whitelisted method", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("rejects non-whitelisted method", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "approve") })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("not allowed")
		expect(result.reason):toContain("approve")
	end)

	it("method whitelist is per-contract", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})
		-- Same method on different contract is not allowed
		local result = policy:validate(PLAYER_1, { makeCall(TOKEN_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)
	end)

	it("normalizes contract address in method whitelist", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = "0x00ABC", selector = "transfer" } },
		})
		local result = policy:validate(PLAYER_1, { makeCall("0xabc", "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("rejects call without entrypoint when methods restricted", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})
		local result = policy:validate(PLAYER_1, { { contractAddress = GAME_CONTRACT } })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("missing entrypoint")
	end)

	it("accepts 'selector' field on call as entrypoint alias", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})
		local result = policy:validate(PLAYER_1, { { contractAddress = GAME_CONTRACT, selector = "transfer" } })
		expect(result.allowed):toBe(true)
	end)

	it("allows multiple methods on same contract", function()
		local policy = PaymasterPolicy.new({
			allowedMethods = {
				{ contract = GAME_CONTRACT, selector = "transfer" },
				{ contract = GAME_CONTRACT, selector = "approve" },
			},
		})
		local r1 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		local r2 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "approve") })
		expect(r1.allowed):toBe(true)
		expect(r2.allowed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Rate limiting
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — rate limiting", function()
	it("allows transactions when no rate limit configured", function()
		local policy = PaymasterPolicy.new({})
		for _ = 1, 100 do
			local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
			expect(result.allowed):toBe(true)
		end
	end)

	it("allows transactions under limit", function()
		local clock, setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 3,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)
		-- 2 recorded, limit is 3 — should still allow
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("rejects transactions at limit", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 3,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)
		-- 3 recorded, limit is 3 — should reject
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("exceeded")
		expect(result.reason):toContain("3")
	end)

	it("allows transactions after time window expires", function()
		local currentTime = 1000
		local clock = function()
			return currentTime
		end
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 2,
			timeWindow = 60,
			_clock = clock,
		})

		-- Record 2 transactions
		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)

		-- At limit — should reject
		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)

		-- Advance time past window
		currentTime = 1061

		-- Should allow again
		local result2 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result2.allowed):toBe(true)
	end)

	it("tracks players independently", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 1,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)

		-- Player 1 at limit
		local r1 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r1.allowed):toBe(false)

		-- Player 2 has no usage
		local r2 = policy:validate(PLAYER_2, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r2.allowed):toBe(true)
	end)

	it("sliding window removes only expired entries", function()
		local currentTime = 1000
		local clock = function()
			return currentTime
		end
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 2,
			timeWindow = 60,
			_clock = clock,
		})

		-- Record at t=1000
		policy:recordUsage(PLAYER_1)

		-- Record at t=1030
		currentTime = 1030
		policy:recordUsage(PLAYER_1)

		-- At t=1050: both in window, should reject
		currentTime = 1050
		local r1 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r1.allowed):toBe(false)

		-- At t=1061: first expired, second still in window — 1 usage, allow
		currentTime = 1061
		local r2 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r2.allowed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Combined rules
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — combined rules", function()
	it("checks player first, then contracts, then methods", function()
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 } },
			allowedContracts = { { address = GAME_CONTRACT } },
			allowedMethods = { { contract = GAME_CONTRACT, selector = "transfer" } },
		})

		-- Unauthorized player with valid contract/method
		local r1 = policy:validate(PLAYER_3, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r1.allowed):toBe(false)
		expect(r1.reason):toContain("not in the allowed players list")

		-- Authorized player with invalid contract
		local r2 = policy:validate(PLAYER_1, { makeCall(OTHER_CONTRACT, "transfer") })
		expect(r2.allowed):toBe(false)
		expect(r2.reason):toContain("not in the allowed contracts list")

		-- Authorized player, valid contract, invalid method
		local r3 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "approve") })
		expect(r3.allowed):toBe(false)
		expect(r3.reason):toContain("not allowed")

		-- All valid
		local r4 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r4.allowed):toBe(true)
	end)

	it("rate limit checked after whitelist checks", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 } },
			allowedContracts = { { address = GAME_CONTRACT } },
			maxTxPerPlayer = 1,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)

		local result = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("exceeded")
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validate — Edge cases
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validate — edge cases", function()
	it("rejects empty calls array", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, {})
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("At least one call is required")
	end)

	it("handles nil calls", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validate(PLAYER_1, nil :: any)
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("At least one call is required")
	end)

	it("handles zero address correctly", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = "0x0" } },
		})
		local result = policy:validate(PLAYER_1, { makeCall("0x0000", "transfer") })
		expect(result.allowed):toBe(true)
	end)

	it("large multicall with all valid calls", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local calls = {}
		for i = 1, 20 do
			table.insert(calls, makeCall(GAME_CONTRACT, "method_" .. tostring(i)))
		end
		local result = policy:validate(PLAYER_1, calls)
		expect(result.allowed):toBe(true)
	end)

	it("rejects at first invalid call in multicall", function()
		local policy = PaymasterPolicy.new({
			allowedContracts = { { address = GAME_CONTRACT } },
		})
		local result = policy:validate(PLAYER_1, {
			makeCall(GAME_CONTRACT, "transfer"),
			makeCall(GAME_CONTRACT, "approve"),
			makeCall(OTHER_CONTRACT, "steal"),
			makeCall(GAME_CONTRACT, "finalize"),
		})
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain(OTHER_CONTRACT)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: validateFee
--------------------------------------------------------------------------------

describe("PaymasterPolicy:validateFee", function()
	it("allows any fee when no limit set", function()
		local policy = PaymasterPolicy.new({})
		local result = policy:validateFee(PLAYER_1, "0xFFFFFFFFFFFFFFFF")
		expect(result.allowed):toBe(true)
	end)

	it("allows fee under limit (hex string)", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0x1000" })
		local result = policy:validateFee(PLAYER_1, "0xFFF")
		expect(result.allowed):toBe(true)
	end)

	it("allows fee equal to limit", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0x1000" })
		local result = policy:validateFee(PLAYER_1, "0x1000")
		expect(result.allowed):toBe(true)
	end)

	it("rejects fee over limit", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0x1000" })
		local result = policy:validateFee(PLAYER_1, "0x1001")
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("exceeds maximum")
	end)

	it("works with BigInt buffer input", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0x1000" })
		local fee = BigInt.fromHex("0x2000")
		local result = policy:validateFee(PLAYER_1, fee)
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("exceeds maximum")
	end)

	it("works with large fee values (1 ETH)", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0xDE0B6B3A7640000" }) -- 1e18
		local r1 = policy:validateFee(PLAYER_1, "0xDE0B6B3A763FFFF") -- slightly under
		expect(r1.allowed):toBe(true)
		local r2 = policy:validateFee(PLAYER_1, "0xDE0B6B3A7640001") -- slightly over
		expect(r2.allowed):toBe(false)
	end)

	it("checks player whitelist for fee validation", function()
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 } },
			maxFeePerTx = "0x1000",
		})
		local result = policy:validateFee(PLAYER_3, "0x100")
		expect(result.allowed):toBe(false)
		expect(result.reason):toContain("not in the allowed players list")
	end)

	it("allows whitelisted player with valid fee", function()
		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 } },
			maxFeePerTx = "0x1000",
		})
		local result = policy:validateFee(PLAYER_1, "0x100")
		expect(result.allowed):toBe(true)
	end)

	it("allows any player when no player whitelist for fee validation", function()
		local policy = PaymasterPolicy.new({ maxFeePerTx = "0x1000" })
		local result = policy:validateFee(PLAYER_3, "0x100")
		expect(result.allowed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: recordUsage
--------------------------------------------------------------------------------

describe("PaymasterPolicy:recordUsage", function()
	it("no-op when rate limiting not configured", function()
		local policy = PaymasterPolicy.new({})
		-- Should not error
		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)
		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
	end)

	it("increments usage count", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})

		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
		policy:recordUsage(PLAYER_1)
		expect(policy:getUsageCount(PLAYER_1)):toBe(1)
		policy:recordUsage(PLAYER_1)
		expect(policy:getUsageCount(PLAYER_1)):toBe(2)
	end)

	it("tracks players separately", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_2)

		expect(policy:getUsageCount(PLAYER_1)):toBe(2)
		expect(policy:getUsageCount(PLAYER_2)):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: resetUsage
--------------------------------------------------------------------------------

describe("PaymasterPolicy:resetUsage", function()
	it("resets specific player", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_2)
		policy:resetUsage(PLAYER_1)

		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
		expect(policy:getUsageCount(PLAYER_2)):toBe(1)
	end)

	it("resets all players when nil", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		policy:recordUsage(PLAYER_2)
		policy:resetUsage()

		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
		expect(policy:getUsageCount(PLAYER_2)):toBe(0)
	end)

	it("allows transactions after reset", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 1,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1)
		local r1 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r1.allowed):toBe(false)

		policy:resetUsage(PLAYER_1)
		local r2 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "transfer") })
		expect(r2.allowed):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getUsageCount
--------------------------------------------------------------------------------

describe("PaymasterPolicy:getUsageCount", function()
	it("returns 0 when no rate limit configured", function()
		local policy = PaymasterPolicy.new({})
		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
	end)

	it("returns 0 for unknown player", function()
		local clock, _setClock = TestUtils.makeClock(1000)
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})
		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
	end)

	it("excludes expired entries", function()
		local currentTime = 1000
		local clock = function()
			return currentTime
		end
		local policy = PaymasterPolicy.new({
			maxTxPerPlayer = 10,
			timeWindow = 60,
			_clock = clock,
		})

		policy:recordUsage(PLAYER_1) -- at t=1000
		currentTime = 1030
		policy:recordUsage(PLAYER_1) -- at t=1030

		-- At t=1050: both in window
		currentTime = 1050
		expect(policy:getUsageCount(PLAYER_1)):toBe(2)

		-- At t=1061: first expired
		currentTime = 1061
		expect(policy:getUsageCount(PLAYER_1)):toBe(1)

		-- At t=1091: both expired
		currentTime = 1091
		expect(policy:getUsageCount(PLAYER_1)):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Full integration scenario
--------------------------------------------------------------------------------

describe("PaymasterPolicy — integration scenario", function()
	it("game server policy: whitelisted players + contracts + rate limit + fee cap", function()
		local currentTime = 1000
		local clock = function()
			return currentTime
		end

		local policy = PaymasterPolicy.new({
			allowedPlayers = { { playerId = PLAYER_1 }, { playerId = PLAYER_2 } },
			allowedContracts = { { address = GAME_CONTRACT }, { address = TOKEN_CONTRACT } },
			allowedMethods = {
				{ contract = GAME_CONTRACT, selector = "move" },
				{ contract = GAME_CONTRACT, selector = "attack" },
				{ contract = TOKEN_CONTRACT, selector = "transfer" },
			},
			maxFeePerTx = "0x2386F26FC10000", -- 0.01 ETH
			maxTxPerPlayer = 10,
			timeWindow = 300, -- 5 minutes
			_clock = clock,
		})

		-- Player 1 makes a valid game action
		local r1 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "move") })
		expect(r1.allowed):toBe(true)
		local f1 = policy:validateFee(PLAYER_1, "0x5AF3107A4000") -- 0.0001 ETH
		expect(f1.allowed):toBe(true)
		policy:recordUsage(PLAYER_1)

		-- Player 1 tries multicall: game action + token transfer
		local r2 = policy:validate(PLAYER_1, {
			makeCall(GAME_CONTRACT, "attack"),
			makeCall(TOKEN_CONTRACT, "transfer"),
		})
		expect(r2.allowed):toBe(true)
		policy:recordUsage(PLAYER_1)

		-- Unauthorized player 3 tries
		local r3 = policy:validate(PLAYER_3, { makeCall(GAME_CONTRACT, "move") })
		expect(r3.allowed):toBe(false)

		-- Player 1 tries unauthorized contract
		local r4 = policy:validate(PLAYER_1, { makeCall(OTHER_CONTRACT, "steal") })
		expect(r4.allowed):toBe(false)

		-- Player 1 tries unauthorized method
		local r5 = policy:validate(PLAYER_1, { makeCall(GAME_CONTRACT, "admin_reset") })
		expect(r5.allowed):toBe(false)

		-- Player 1 tries excessive fee
		local f2 = policy:validateFee(PLAYER_1, "0xDE0B6B3A7640000") -- 1 ETH
		expect(f2.allowed):toBe(false)

		-- Use up the rate limit for player 2
		for _ = 1, 10 do
			policy:recordUsage(PLAYER_2)
		end
		local r6 = policy:validate(PLAYER_2, { makeCall(GAME_CONTRACT, "move") })
		expect(r6.allowed):toBe(false)
		expect(r6.reason):toContain("exceeded")

		-- After time window, player 2 can transact again
		currentTime = 1301
		local r7 = policy:validate(PLAYER_2, { makeCall(GAME_CONTRACT, "move") })
		expect(r7.allowed):toBe(true)
	end)

	it("open policy: no restrictions except fee cap", function()
		local policy = PaymasterPolicy.new({
			maxFeePerTx = "0x2386F26FC10000",
		})

		-- Anyone, any contract, any method
		local r1 = policy:validate(99999, { makeCall(OTHER_CONTRACT, "anything") })
		expect(r1.allowed):toBe(true)

		-- But fee is capped
		local f1 = policy:validateFee(99999, "0xDE0B6B3A7640000")
		expect(f1.allowed):toBe(false)
	end)
end)
