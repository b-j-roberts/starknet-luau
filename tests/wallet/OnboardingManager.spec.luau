--!strict
local OnboardingManager = require("../../src/wallet/OnboardingManager")
local KeyStore = require("../../src/wallet/KeyStore")
local ErrorCodes = require("../../src/errors/ErrorCodes")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local TEST_SECRET = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"

local PLAYER_1 = 12345
local PLAYER_2 = 67890

--- Create deterministic "random" bytes for reproducible tests.
local function makeDeterministicRandom(): (n: number) -> buffer
	local callCount = 0
	return function(n: number): buffer
		callCount += 1
		local buf = buffer.create(n)
		for i = 0, n - 1 do
			buffer.writeu8(buf, i, (i * 37 + 13 + callCount * 7) % 256)
		end
		return buf
	end
end

--- Create a mock DataStore.
local function createMockDataStore(): (any, { [string]: any })
	local data: { [string]: any } = {}
	local store = {}

	function store:GetAsync(key: string): any?
		return data[key]
	end

	function store:SetAsync(key: string, value: any, _userIds: { number }?): ()
		data[key] = value
	end

	function store:RemoveAsync(key: string): ()
		data[key] = nil
	end

	return store, data
end

--- Create a KeyStore with test config.
local function createTestKeyStore(overrides: { [string]: any }?): (any, any, { [string]: any })
	local mockDS, data = createMockDataStore()
	local config: any = {
		serverSecret = TEST_SECRET,
		_dataStore = mockDS,
		_clock = function()
			return 1000
		end,
		_randomBytes = makeDeterministicRandom(),
	}
	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end
	local ks = KeyStore.new(config)
	return ks, mockDS, data
end

--- Create a mock provider that simulates undeployed account (getNonce errors).
local function createUndeployedProvider(): (any, any)
	local rpc = TestUtils.createMockRpcLayer()
	rpc.resetHandlers()

	-- getNonce errors → account not deployed (triggers deploy flow)
	rpc.mockHandlers["starknet_getNonce"] = function(_params)
		error("Contract not found")
	end

	-- Deploy succeeds
	rpc.mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
		return { transaction_hash = "0xdeploy123", contract_address = "0xaddr123" }
	end

	-- Fee estimation
	rpc.mockHandlers["starknet_estimateFee"] = function(_params)
		return {
			{
				gas_consumed = "0x1000",
				gas_price = "0x100",
				overall_fee = "0x100000",
				data_gas_consumed = "0x200",
				data_gas_price = "0x50",
				unit = "WEI",
			},
		}
	end

	return rpc.createTestProvider(), rpc
end

--- Create a mock provider that simulates already-deployed account (getNonce succeeds).
local function createDeployedProvider(): (any, any)
	local rpc = TestUtils.createMockRpcLayer()
	rpc.resetHandlers()

	rpc.mockHandlers["starknet_getNonce"] = function(_params)
		return "0x0"
	end

	return rpc.createTestProvider(), rpc
end

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("OnboardingManager.new", function()
	it("creates with valid config", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()
		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		expect(om):toBeTruthy()
	end)

	it("rejects missing keyStore", function()
		local provider = createDeployedProvider()
		expect(function()
			OnboardingManager.new({ keyStore = nil :: any, provider = provider })
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)

	it("rejects missing provider", function()
		local ks = createTestKeyStore()
		expect(function()
			OnboardingManager.new({ keyStore = ks, provider = nil :: any })
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)

	it("defaults waitForConfirmation to true and dryRun to false", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()
		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		expect(om):toBeTruthy()
		expect(om._waitForConfirmation):toBe(true)
		expect(om._dryRun):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: onboard — new player
--------------------------------------------------------------------------------

describe("OnboardingManager:onboard — new player", function()
	it("creates key and deploys", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:onboard(PLAYER_1)
		expect(result.account):toBeTruthy()
		expect(result.address):toBeTruthy()
		expect(result.isNew):toBe(true)
		expect(result.wasDeployed):toBe(true)
		expect(result.alreadyDeployed):toBe(false)
	end)

	it("marks deployed in KeyStore after deploy", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		expect(ks:isDeployed(PLAYER_1)):toBe(false)
		om:onboard(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
	end)

	it("returns transaction hash", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:onboard(PLAYER_1)
		expect(result.transactionHash):toBeTruthy()
	end)

	it("handles different players independently", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local r2 = om:onboard(PLAYER_2)
		expect(r1.address ~= r2.address):toBe(true)
		expect(r1.isNew):toBe(true)
		expect(r2.isNew):toBe(true)
	end)

	it("dryRun mode does not mark deployed", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
			dryRun = true,
		})

		om:onboard(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)

	it("dryRun still returns wasDeployed true", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
			dryRun = true,
		})

		local result = om:onboard(PLAYER_1)
		expect(result.wasDeployed):toBe(true)
		expect(result.alreadyDeployed):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: onboard — existing player (already deployed in KeyStore)
--------------------------------------------------------------------------------

describe("OnboardingManager:onboard — already deployed", function()
	it("returns early when KeyStore says deployed", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		-- Pre-populate: generate key and mark deployed
		ks:getOrCreate(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:onboard(PLAYER_1)
		expect(result.wasDeployed):toBe(false)
		expect(result.alreadyDeployed):toBe(true)
		expect(result.isNew):toBe(false)
	end)

	it("loads existing key (isNew = false)", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local initial = ks:getOrCreate(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:onboard(PLAYER_1)
		expect(result.isNew):toBe(false)
		expect(result.address):toBe(initial.account.address)
	end)

	it("handles chain-level idempotency (deployed on chain but not in KeyStore)", function()
		local ks = createTestKeyStore()
		-- Provider returns getNonce success → account is deployed on chain
		local provider = createDeployedProvider()

		-- Pre-populate key but DON'T mark deployed
		ks:getOrCreate(PLAYER_1, provider)
		expect(ks:isDeployed(PLAYER_1)):toBe(false)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:onboard(PLAYER_1)
		-- deployAccount's idempotency check returns alreadyDeployed=true
		expect(result.alreadyDeployed):toBe(true)
		expect(result.wasDeployed):toBe(false)
		-- Should have synced KeyStore state
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: onboard — idempotent re-calls
--------------------------------------------------------------------------------

describe("OnboardingManager:onboard — idempotency", function()
	it("second call returns alreadyDeployed after first deploys", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		expect(r1.wasDeployed):toBe(true)

		-- Second call: KeyStore now knows it's deployed
		local r2 = om:onboard(PLAYER_1)
		expect(r2.wasDeployed):toBe(false)
		expect(r2.alreadyDeployed):toBe(true)
		expect(r2.address):toBe(r1.address)
	end)

	it("preserves same address across calls", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local r2 = om:onboard(PLAYER_1)
		expect(r1.address):toBe(r2.address)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: onboard — deployment failure
--------------------------------------------------------------------------------

describe("OnboardingManager:onboard — deploy failure", function()
	it("wraps deployment errors with ONBOARDING_ERROR", function()
		local ks = createTestKeyStore()
		local rpc = TestUtils.createMockRpcLayer()
		rpc.resetHandlers()

		-- getNonce errors (undeployed)
		rpc.mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end

		-- estimateFee errors
		rpc.mockHandlers["starknet_estimateFee"] = function(_params)
			error("estimation failed")
		end

		local provider = rpc.createTestProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		expect(function()
			om:onboard(PLAYER_1)
		end):toThrowCode(ErrorCodes.ONBOARDING_ERROR.code)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getStatus
--------------------------------------------------------------------------------

describe("OnboardingManager:getStatus", function()
	it("returns no account for unknown player", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()
		local om = OnboardingManager.new({ keyStore = ks, provider = provider })

		local status = om:getStatus(PLAYER_1)
		expect(status.hasAccount):toBe(false)
		expect(status.isDeployed):toBe(false)
		expect(status.address):toBeNil()
	end)

	it("returns undeployed for account without deployedAt", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		local status = om:getStatus(PLAYER_1)
		expect(status.hasAccount):toBe(true)
		expect(status.isDeployed):toBe(false)
		expect(status.address):toBeTruthy()
	end)

	it("returns deployed after markDeployed", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		local status = om:getStatus(PLAYER_1)
		expect(status.hasAccount):toBe(true)
		expect(status.isDeployed):toBe(true)
		expect(status.address):toBeTruthy()
	end)

	it("returns no account after removePlayer", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		om:removePlayer(PLAYER_1)

		local status = om:getStatus(PLAYER_1)
		expect(status.hasAccount):toBe(false)
		expect(status.isDeployed):toBe(false)
	end)

	it("returns correct address", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		local result = ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		local status = om:getStatus(PLAYER_1)
		expect(status.address):toBe(result.account.address)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: ensureDeployed
--------------------------------------------------------------------------------

describe("OnboardingManager:ensureDeployed", function()
	it("deploys if account exists but not deployed", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:ensureDeployed(PLAYER_1)
		expect(result.wasDeployed):toBe(true)
		expect(result.alreadyDeployed):toBe(false)
		expect(result.isNew):toBe(false)
	end)

	it("marks deployed after successful deploy", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		om:ensureDeployed(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
	end)

	it("returns early when already deployed", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:ensureDeployed(PLAYER_1)
		expect(result.wasDeployed):toBe(false)
		expect(result.alreadyDeployed):toBe(true)
		expect(result.account):toBeTruthy()
	end)

	it("errors when no account exists", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()
		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		expect(function()
			om:ensureDeployed(PLAYER_1)
		end):toThrowCode(ErrorCodes.ONBOARDING_ERROR.code)
	end)

	it("handles chain-level idempotency", function()
		local ks = createTestKeyStore()
		-- Provider says deployed (getNonce succeeds)
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)
		-- NOT marked deployed in KeyStore

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:ensureDeployed(PLAYER_1)
		expect(result.alreadyDeployed):toBe(true)
		-- Should have synced KeyStore
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
	end)

	it("dryRun mode does not mark deployed", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
			dryRun = true,
		})

		om:ensureDeployed(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)

	it("returns transaction hash from deploy", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local result = om:ensureDeployed(PLAYER_1)
		expect(result.transactionHash):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Tests: removePlayer
--------------------------------------------------------------------------------

describe("OnboardingManager:removePlayer", function()
	it("delegates to keyStore:deleteKey", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)
		expect(ks:hasAccount(PLAYER_1)):toBe(true)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		om:removePlayer(PLAYER_1)

		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("no error for non-existent player", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })
		-- Should not throw
		om:removePlayer(PLAYER_1)
	end)

	it("cleanup verified via getStatus", function()
		local ks = createTestKeyStore()
		local provider = createDeployedProvider()

		ks:getOrCreate(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)

		local om = OnboardingManager.new({ keyStore = ks, provider = provider })

		local statusBefore = om:getStatus(PLAYER_1)
		expect(statusBefore.hasAccount):toBe(true)
		expect(statusBefore.isDeployed):toBe(true)

		om:removePlayer(PLAYER_1)

		local statusAfter = om:getStatus(PLAYER_1)
		expect(statusAfter.hasAccount):toBe(false)
		expect(statusAfter.isDeployed):toBe(false)
	end)

	it("onboard after remove creates fresh key", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local firstAddress = r1.address

		om:removePlayer(PLAYER_1)

		local r2 = om:onboard(PLAYER_1)
		expect(r2.isNew):toBe(true)
		-- Different key → different address (with overwhelming probability)
		-- The deterministic random produces different bytes on each call
		expect(r2.address ~= firstAddress):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Integration — full lifecycle
--------------------------------------------------------------------------------

describe("OnboardingManager — integration", function()
	it("full lifecycle: onboard → getStatus → removePlayer → onboard", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		-- 1. First onboard
		local r1 = om:onboard(PLAYER_1)
		expect(r1.isNew):toBe(true)
		expect(r1.wasDeployed):toBe(true)

		-- 2. Check status
		local status = om:getStatus(PLAYER_1)
		expect(status.hasAccount):toBe(true)
		expect(status.isDeployed):toBe(true)
		expect(status.address):toBe(r1.address)

		-- 3. Remove
		om:removePlayer(PLAYER_1)
		local statusAfter = om:getStatus(PLAYER_1)
		expect(statusAfter.hasAccount):toBe(false)

		-- 4. Re-onboard (fresh key)
		local r2 = om:onboard(PLAYER_1)
		expect(r2.isNew):toBe(true)
		expect(r2.wasDeployed):toBe(true)
	end)

	it("multi-player onboarding", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local r2 = om:onboard(PLAYER_2)

		expect(r1.address ~= r2.address):toBe(true)
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
		expect(ks:isDeployed(PLAYER_2)):toBe(true)
	end)

	it("idempotency across multiple onboard calls", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local r2 = om:onboard(PLAYER_1)
		local r3 = om:onboard(PLAYER_1)

		expect(r1.address):toBe(r2.address)
		expect(r2.address):toBe(r3.address)
		expect(r1.wasDeployed):toBe(true)
		expect(r2.wasDeployed):toBe(false)
		expect(r3.wasDeployed):toBe(false)
	end)

	it("ensureDeployed after onboard is idempotent", function()
		local ks = createTestKeyStore()
		local provider = createUndeployedProvider()

		local om = OnboardingManager.new({
			keyStore = ks,
			provider = provider,
			waitForConfirmation = false,
		})

		local r1 = om:onboard(PLAYER_1)
		local r2 = om:ensureDeployed(PLAYER_1)

		expect(r2.alreadyDeployed):toBe(true)
		expect(r2.wasDeployed):toBe(false)
		expect(r2.address):toBe(r1.address)
	end)
end)
