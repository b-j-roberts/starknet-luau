--!strict
local AccountType = require("../../src/wallet/AccountType")
local AccountFactory = require("../../src/wallet/AccountFactory")
local StarkSigner = require("../../src/signer/StarkSigner")
local TestUtils = require("../helpers/TestUtils")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

-- Private keys (must be < curve order N)
local PRIVKEY_1 = TestUtils.TEST_PRIVATE_KEY
local PRIVKEY_2 = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F"
local PRIVKEY_3 = "0x1"
local PRIVKEY_4 = "0x2"
local PRIVKEY_5 = "0x3"

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers

-- Override defaults with deploy-specific handlers
local function resetHandlers()
	rpc.resetHandlers()

	-- Default: getNonce errors (account not deployed) -- triggers deployment flow
	mockHandlers["starknet_getNonce"] = function(_params)
		error("Contract not found")
	end

	mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
		return {
			transaction_hash = "0xdeploy123",
			contract_address = "0xdeployed",
		}
	end
end

local function createTestProvider(): any
	return rpc.createTestProvider()
end

resetHandlers()

-- Simple deterministic key generator for testing
local keyIndex = 0
local testKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3, PRIVKEY_4, PRIVKEY_5 }
local function resetKeyGen()
	keyIndex = 0
end
local function testKeyGenerator(): string
	keyIndex += 1
	return testKeys[keyIndex]
end

--------------------------------------------------------------------------------
-- batchCreate - validation
--------------------------------------------------------------------------------

describe("batchCreate - validation", function()
	it("errors when count is zero", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(0, { privateKeys = {} })
		end):toThrowType("ValidationError")
	end)

	it("errors when count is negative", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(-1, { keyGenerator = testKeyGenerator })
		end):toThrowType("ValidationError")
	end)

	it("errors when count is not an integer", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(2.5, { keyGenerator = testKeyGenerator })
		end):toThrowType("ValidationError")
	end)

	it("errors when count exceeds max batch size", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(101, { keyGenerator = testKeyGenerator })
		end):toThrowType("ValidationError")
	end)

	it("errors when neither privateKeys nor keyGenerator provided", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(3, {})
		end):toThrowType("ValidationError")
	end)

	it("errors when both privateKeys and keyGenerator provided", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(1, {
				privateKeys = { PRIVKEY_1 },
				keyGenerator = testKeyGenerator,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when privateKeys length does not match count", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchCreate(3, { privateKeys = { PRIVKEY_1, PRIVKEY_2 } })
		end):toThrowType("ValidationError")
	end)

	it("accepts count at max batch size boundary (100)", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		-- Generate 100 unique keys
		local keys = {}
		for i = 1, 100 do
			table.insert(keys, `0x{string.format("%x", i)}`)
		end

		local results = factory:batchCreate(100, { privateKeys = keys })
		expect(#results):toBe(100)
	end)
end)

--------------------------------------------------------------------------------
-- batchCreate - with privateKeys
--------------------------------------------------------------------------------

describe("batchCreate - with privateKeys", function()
	it("creates correct number of accounts", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		expect(#results):toBe(3)
	end)

	it("each account has unique address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})

		local addresses = {}
		for _, entry in results do
			expect(addresses[entry.address]):toBeFalsy()
			addresses[entry.address] = true
		end
	end)

	it("each entry has account, address, signer, and deployTx", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		for _, entry in results do
			expect(entry.account):toBeTruthy()
			expect(entry.address):toBeTruthy()
			expect(entry.signer):toBeTruthy()
			expect(type(entry.deployTx)):toBe("function")
		end
	end)

	it("addresses match createAccount addresses", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer1 = StarkSigner.new(PRIVKEY_1)
		local signer2 = StarkSigner.new(PRIVKEY_2)

		-- Create via batch
		local factory = AccountFactory.new(provider, AccountType.OZ, signer1)
		local batch = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		-- Create individually
		local f1 = AccountFactory.new(provider, AccountType.OZ, signer1)
		local f2 = AccountFactory.new(provider, AccountType.OZ, signer2)
		local single1 = f1:createAccount()
		local single2 = f2:createAccount()

		expect(batch[1].address):toBe(single1.address)
		expect(batch[2].address):toBe(single2.address)
	end)

	it("signers are distinct StarkSigner instances", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		-- Signers produce different public keys
		local pk1 = results[1].signer:getPublicKeyHex()
		local pk2 = results[2].signer:getPublicKeyHex()
		expect(pk1 ~= pk2):toBe(true)
	end)

	it("single account batch works", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		expect(#results):toBe(1)
		expect(results[1].address):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- batchCreate - with keyGenerator
--------------------------------------------------------------------------------

describe("batchCreate - with keyGenerator", function()
	it("creates correct number of accounts from generator", function()
		resetHandlers()
		resetKeyGen()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local results = factory:batchCreate(3, { keyGenerator = testKeyGenerator })
		expect(#results):toBe(3)
	end)

	it("calls keyGenerator exactly count times", function()
		resetHandlers()
		local callCount = 0
		local keys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 }
		local function countingGen(): string
			callCount += 1
			return keys[callCount]
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		factory:batchCreate(3, { keyGenerator = countingGen })
		expect(callCount):toBe(3)
	end)

	it("produces same addresses as privateKeys for same keys", function()
		resetHandlers()
		resetKeyGen()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local fromGen = factory:batchCreate(3, { keyGenerator = testKeyGenerator })

		local fromKeys = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})

		for i = 1, 3 do
			expect(fromGen[i].address):toBe(fromKeys[i].address)
		end
	end)
end)

--------------------------------------------------------------------------------
-- batchCreate - with Argent account type
--------------------------------------------------------------------------------

describe("batchCreate - Argent accounts", function()
	it("creates Argent accounts without guardian", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local results = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		-- Argent addresses differ from OZ for same keys
		local ozFactory = AccountFactory.new(provider, AccountType.OZ, StarkSigner.new(PRIVKEY_1))
		local ozResult = ozFactory:createAccount()
		expect(results[1].address ~= ozResult.address):toBe(true)
	end)

	it("creates Argent accounts with guardian", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local withGuardian = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
			guardian = "0xdeadbeef",
		})
		local withoutGuardian = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		expect(withGuardian[1].address ~= withoutGuardian[1].address):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- batchCreate - with custom classHash
--------------------------------------------------------------------------------

describe("batchCreate - custom classHash", function()
	it("overrides classHash for all batch accounts", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local customHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003"
		local customBatch = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
			classHash = customHash,
		})
		local defaultBatch = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})

		-- Custom class hash produces different addresses
		expect(customBatch[1].address ~= defaultBatch[1].address):toBe(true)
		expect(customBatch[2].address ~= defaultBatch[2].address):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - validation
--------------------------------------------------------------------------------

describe("batchDeploy - validation", function()
	it("errors when accounts array is empty", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		expect(function()
			factory:batchDeploy({})
		end):toThrowType("ValidationError")
	end)

	it("errors when maxConcurrency is zero", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })

		expect(function()
			factory:batchDeploy(accounts, { maxConcurrency = 0, dryRun = true })
		end):toThrowType("ValidationError")
	end)

	it("errors when maxConcurrency is negative", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })

		expect(function()
			factory:batchDeploy(accounts, { maxConcurrency = -1, dryRun = true })
		end):toThrowType("ValidationError")
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - sequential (default)
--------------------------------------------------------------------------------

describe("batchDeploy - sequential dryRun", function()
	it("deploys single account in dryRun", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(report.deployed):toBe(1)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(0)
		expect(#report.results):toBe(1)
		expect(report.results[1].status):toBe("deployed")
	end)

	it("deploys multiple accounts in dryRun", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(report.deployed):toBe(3)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(0)
		expect(#report.results):toBe(3)
	end)

	it("results have correct index values", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(report.results[1].index):toBe(1)
		expect(report.results[2].index):toBe(2)
		expect(report.results[3].index):toBe(3)
	end)

	it("results include addresses", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(report.results[1].address):toBe(accounts[1].address)
		expect(report.results[2].address):toBe(accounts[2].address)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - with actual mock RPC (non-dryRun)
--------------------------------------------------------------------------------

describe("batchDeploy - with mock RPC", function()
	it("deploys single account via RPC", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		expect(report.deployed):toBe(1)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(0)
		expect(report.results[1].transactionHash):toBeTruthy()
	end)

	it("deploys multiple accounts via RPC", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		expect(report.deployed):toBe(3)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - skipped (already deployed)
--------------------------------------------------------------------------------

describe("batchDeploy - already deployed accounts", function()
	it("skips already deployed accounts", function()
		resetHandlers()
		-- All accounts already deployed (getNonce succeeds)
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x5"
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts):expect()

		expect(report.deployed):toBe(0)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(3)
	end)

	it("skipped results have correct status", function()
		resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x1"
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts):expect()

		expect(report.results[1].status):toBe("skipped")
		expect(report.results[1].transactionHash):toBe("0x0")
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - error tolerance
--------------------------------------------------------------------------------

describe("batchDeploy - error tolerance", function()
	it("continues on individual deploy failure", function()
		resetHandlers()
		local deployCount = 0

		-- First deploy succeeds, second fails, third succeeds
		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			deployCount += 1
			if deployCount == 2 then
				error("Deployment failed: insufficient funds")
			end
			return {
				transaction_hash = `0xdeploy{deployCount}`,
				contract_address = "0xdeployed",
			}
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		expect(report.deployed):toBe(2)
		expect(report.failed):toBe(1)
		expect(report.skipped):toBe(0)
		expect(#report.results):toBe(3)
	end)

	it("failed result includes error", function()
		resetHandlers()
		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			error("Deployment failed")
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		expect(report.failed):toBe(1)
		expect(report.results[1].status):toBe("failed")
		expect(report.results[1].error):toBeTruthy()
	end)

	it("mixed results: deployed + failed + skipped", function()
		resetHandlers()
		local nonceCallCount = 0
		local deployCallCount = 0

		-- Account 1: already deployed, Account 2: deploy succeeds, Account 3: deploy fails
		mockHandlers["starknet_getNonce"] = function(_params)
			nonceCallCount += 1
			if nonceCallCount == 1 then
				return "0x5" -- already deployed
			end
			error("Contract not found") -- needs deployment
		end

		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			deployCallCount += 1
			if deployCallCount == 2 then
				error("Insufficient funds")
			end
			return {
				transaction_hash = "0xdeployed",
				contract_address = "0xaddr",
			}
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		expect(report.deployed + report.failed + report.skipped):toBe(3)
		expect(report.skipped >= 1):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - progress callback
--------------------------------------------------------------------------------

describe("batchDeploy - progress callback", function()
	it("calls onDeployProgress for each account", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local progressCalls: { { index: number, total: number, status: string } } = {}

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		factory
			:batchDeploy(accounts, {
				dryRun = true,
				onDeployProgress = function(index: number, total: number, result: any)
					table.insert(progressCalls, {
						index = index,
						total = total,
						status = result.status,
					})
				end,
			})
			:expect()

		expect(#progressCalls):toBe(3)
	end)

	it("progress callback receives correct index and total", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local calls: { { index: number, total: number } } = {}

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		factory
			:batchDeploy(accounts, {
				dryRun = true,
				onDeployProgress = function(index: number, total: number, _result: any)
					table.insert(calls, { index = index, total = total })
				end,
			})
			:expect()

		-- Sequential: called in order 1, 2, 3
		expect(calls[1].index):toBe(1)
		expect(calls[1].total):toBe(3)
		expect(calls[2].index):toBe(2)
		expect(calls[2].total):toBe(3)
		expect(calls[3].index):toBe(3)
		expect(calls[3].total):toBe(3)
	end)

	it("progress callback receives result with status field", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local statuses: { string } = {}

		local accounts = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})
		factory
			:batchDeploy(accounts, {
				dryRun = true,
				onDeployProgress = function(_index: number, _total: number, result: any)
					table.insert(statuses, result.status)
				end,
			})
			:expect()

		expect(statuses[1]):toBe("deployed")
		expect(statuses[2]):toBe("deployed")
	end)

	it("progress callback fires even on failure", function()
		resetHandlers()
		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			error("Deploy failed")
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local callCount = 0

		local accounts = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})
		factory
			:batchDeploy(accounts, {
				waitForConfirmation = false,
				onDeployProgress = function(_index: number, _total: number, _result: any)
					callCount += 1
				end,
			})
			:expect()

		expect(callCount):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - parallel (maxConcurrency > 1)
--------------------------------------------------------------------------------

describe("batchDeploy - parallel (maxConcurrency)", function()
	it("deploys with maxConcurrency=2 in dryRun", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(4, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3, PRIVKEY_4 },
		})
		local report = factory
			:batchDeploy(accounts, {
				dryRun = true,
				maxConcurrency = 2,
			})
			:expect()

		expect(report.deployed):toBe(4)
		expect(report.failed):toBe(0)
		expect(report.skipped):toBe(0)
		expect(#report.results):toBe(4)
	end)

	it("deploys with maxConcurrency equal to account count", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory
			:batchDeploy(accounts, {
				dryRun = true,
				maxConcurrency = 3,
			})
			:expect()

		expect(report.deployed):toBe(3)
		expect(report.failed):toBe(0)
	end)

	it("deploys with maxConcurrency greater than account count", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})
		local report = factory
			:batchDeploy(accounts, {
				dryRun = true,
				maxConcurrency = 10,
			})
			:expect()

		expect(report.deployed):toBe(2)
	end)

	it("parallel handles mixed success/failure", function()
		resetHandlers()
		local deployCount = 0

		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			deployCount += 1
			if deployCount == 2 then
				error("Deploy failed")
			end
			return {
				transaction_hash = `0xdeploy{deployCount}`,
				contract_address = "0xdeployed",
			}
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory
			:batchDeploy(accounts, {
				waitForConfirmation = false,
				maxConcurrency = 2,
			})
			:expect()

		expect(report.deployed + report.failed):toBe(3)
		expect(report.failed):toBe(1)
	end)

	it("parallel fires progress callback for all accounts", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local progressCount = 0

		local accounts = factory:batchCreate(4, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3, PRIVKEY_4 },
		})
		factory
			:batchDeploy(accounts, {
				dryRun = true,
				maxConcurrency = 2,
				onDeployProgress = function(_index: number, _total: number, _result: any)
					progressCount += 1
				end,
			})
			:expect()

		expect(progressCount):toBe(4)
	end)

	it("maxConcurrency is floored to integer", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(2, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2 },
		})
		-- maxConcurrency 2.9 should be floored to 2
		local report = factory
			:batchDeploy(accounts, {
				dryRun = true,
				maxConcurrency = 2.9,
			})
			:expect()

		expect(report.deployed):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - deploy options passthrough
--------------------------------------------------------------------------------

describe("batchDeploy - deploy options", function()
	it("passes waitForConfirmation option", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })

		-- waitForConfirmation=false should not call getTransactionReceipt
		local receiptCalled = false
		mockHandlers["starknet_getTransactionReceipt"] = function(_params)
			receiptCalled = true
			return {
				transaction_hash = "0xdeploy123",
				actual_fee = { amount = "0x1234", unit = "WEI" },
				execution_status = "SUCCEEDED",
				finality_status = "ACCEPTED_ON_L2",
				block_hash = "0xblock1",
				block_number = 100,
				events = {},
			}
		end

		factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()
		expect(receiptCalled):toBeFalsy()
	end)

	it("dryRun does not submit transactions", function()
		resetHandlers()
		local deployCalled = false
		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			deployCalled = true
			return {
				transaction_hash = "0xdeploy",
				contract_address = "0xaddr",
			}
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(deployCalled):toBeFalsy()
	end)
end)

--------------------------------------------------------------------------------
-- batchDeploy - summary report
--------------------------------------------------------------------------------

describe("batchDeploy - summary report", function()
	it("report has all required fields", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		expect(type(report.deployed)):toBe("number")
		expect(type(report.failed)):toBe("number")
		expect(type(report.skipped)):toBe("number")
		expect(type(report.results)):toBe("table")
	end)

	it("counts sum to total accounts", function()
		resetHandlers()
		local nonceCallCount = 0
		local deployCallCount = 0

		mockHandlers["starknet_getNonce"] = function(_params)
			nonceCallCount += 1
			if nonceCallCount == 1 then
				return "0x3" -- already deployed
			end
			error("Contract not found")
		end

		mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
			deployCallCount += 1
			if deployCallCount == 1 then
				error("Insufficient funds")
			end
			return {
				transaction_hash = "0xdeploy",
				contract_address = "0xaddr",
			}
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(3, {
			privateKeys = { PRIVKEY_1, PRIVKEY_2, PRIVKEY_3 },
		})
		local report = factory:batchDeploy(accounts, { waitForConfirmation = false }):expect()

		local total = report.deployed + report.failed + report.skipped
		expect(total):toBe(3)
	end)

	it("result entries have correct status strings", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local accounts = factory:batchCreate(1, { privateKeys = { PRIVKEY_1 } })
		local report = factory:batchDeploy(accounts, { dryRun = true }):expect()

		local status = report.results[1].status
		expect(status == "deployed" or status == "failed" or status == "skipped"):toBe(true)
	end)
end)

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
