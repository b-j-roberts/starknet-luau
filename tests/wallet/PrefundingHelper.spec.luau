--!strict
local Account = require("../../src/wallet/Account")
local BigInt = require("../../src/crypto/BigInt")
local Constants = require("../../src/constants")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

local PRIVKEY_1 = TestUtils.TEST_PRIVATE_KEY
local PUBKEY_1 = TestUtils.TEST_PUBLIC_KEY
local OZ_CLASS_HASH = TestUtils.OZ_CLASS_HASH
local ARGENT_CLASS_HASH = TestUtils.ARGENT_CLASS_HASH

-- Pre-computed OZ address for PUBKEY_1 (from Account.spec.luau)
local EXPECTED_ADDR_1_OZ = "0x76d427e4760e8a0947f747c98263827154aca2c999b288a2087cd9655e2008d"

-- STRK/ETH token addresses
local STRK_TOKEN = Constants.STRK_TOKEN_ADDRESS
local ETH_TOKEN = Constants.ETH_TOKEN_ADDRESS

-- Keccak selectors (computed by Contract internally, we match in mock)
-- balance_of selector = starknet_keccak("balance_of") masked to 251 bits
-- We match on method ("starknet_call") and return balance regardless of selector

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

-- Override defaults with prefunding-specific handlers
local function resetHandlers()
	rpc.resetHandlers()

	mockHandlers["starknet_estimateFee"] = function(_params)
		return {
			{
				gas_consumed = "0x1000",
				gas_price = "0x100",
				overall_fee = "0x100000",
				data_gas_consumed = "0x200",
				data_gas_price = "0x50",
				unit = "FRI",
			},
		}
	end

	-- Default balance: 0x200000 (sufficient for deployment)
	mockHandlers["starknet_call"] = function(_params)
		return { "0x200000", "0x0" }
	end
end

local function createTestProvider(): any
	return rpc.createTestProvider()
end

resetHandlers()

--------------------------------------------------------------------------------
-- getDeploymentFeeEstimate
--------------------------------------------------------------------------------

describe("Account.getDeploymentFeeEstimate", function()
	it("returns fee estimate with default 1.5x multiplier", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		}):expect()

		-- overall_fee = 0x100000, multiplied by 1.5 = 0x180000
		expect(result.estimatedFee):toBe("0x180000")
		expect(result.gasConsumed):toBe("0x1000")
		expect(result.gasPrice):toBe("0x100")
		expect(result.rawEstimate).toBeTruthy()
	end)

	it("applies custom fee multiplier", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
			feeMultiplier = 2.0,
		}):expect()

		-- overall_fee = 0x100000, multiplied by 2.0 = 0x200000
		expect(result.estimatedFee):toBe("0x200000")
	end)

	it("applies 1.0x multiplier (no buffer)", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
			feeMultiplier = 1.0,
		}):expect()

		-- overall_fee = 0x100000, multiplied by 1.0 = 0x100000
		expect(result.estimatedFee):toBe("0x100000")
	end)

	it("sends estimateFee RPC with DEPLOY_ACCOUNT transaction", function()
		resetHandlers()
		local provider = createTestProvider()
		rpc.clearRequestLog()

		Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		}):expect()

		-- Should have sent starknet_estimateFee
		local foundEstimate = false
		for _, entry in requestLog do
			if entry.method == "starknet_estimateFee" then
				foundEstimate = true
				-- Verify it's a DEPLOY_ACCOUNT transaction
				local txArray = entry.params[1]
				expect(txArray[1].type):toBe("DEPLOY_ACCOUNT")
				expect(txArray[1].version):toBe("0x3")
			end
		end
		expect(foundEstimate).toBeTruthy()
	end)

	it("includes class hash and constructor calldata in RPC request", function()
		resetHandlers()
		local provider = createTestProvider()
		rpc.clearRequestLog()

		Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		}):expect()

		for _, entry in requestLog do
			if entry.method == "starknet_estimateFee" then
				local tx = entry.params[1][1]
				expect(tx.class_hash):toBe(OZ_CLASS_HASH)
				expect(tx.constructor_calldata[1]):toBe(PUBKEY_1)
				expect(tx.contract_address_salt):toBe(PUBKEY_1)
			end
		end
	end)

	it("returns raw estimate in result", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		}):expect()

		expect(result.rawEstimate.overall_fee):toBe("0x100000")
		expect(result.rawEstimate.gas_consumed):toBe("0x1000")
		expect(result.rawEstimate.unit):toBe("FRI")
	end)

	it("throws on missing provider", function()
		expect(function()
			Account.getDeploymentFeeEstimate({
				classHash = OZ_CLASS_HASH,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				contractAddress = EXPECTED_ADDR_1_OZ,
				provider = nil :: any,
			})
		end).toThrow()
	end)

	it("throws on missing classHash", function()
		local provider = createTestProvider()
		expect(function()
			Account.getDeploymentFeeEstimate({
				classHash = nil :: any,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				contractAddress = EXPECTED_ADDR_1_OZ,
				provider = provider,
			})
		end).toThrow()
	end)

	it("throws on missing contractAddress", function()
		local provider = createTestProvider()
		expect(function()
			Account.getDeploymentFeeEstimate({
				classHash = OZ_CLASS_HASH,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				contractAddress = nil :: any,
				provider = provider,
			})
		end).toThrow()
	end)

	it("propagates RPC error on fee estimation failure", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("Fee estimation failed")
		end
		local provider = createTestProvider()

		local promise = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		})
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("handles empty constructor calldata", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFeeEstimate({
			classHash = OZ_CLASS_HASH,
			constructorCalldata = {},
			salt = PUBKEY_1,
			contractAddress = EXPECTED_ADDR_1_OZ,
			provider = provider,
		}):expect()

		expect(result.estimatedFee):toBe("0x180000")
	end)
end)

--------------------------------------------------------------------------------
-- checkDeploymentBalance
--------------------------------------------------------------------------------

describe("Account.checkDeploymentBalance", function()
	it("returns hasSufficientBalance=true when balance exceeds fee", function()
		resetHandlers()
		-- Balance: 0x200000 (low), 0x0 (high) = 0x200000
		-- Fee: 0x100000 * 1.5 = 0x180000
		-- 0x200000 > 0x180000 -> sufficient
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(true)
		expect(result.balance):toBe("0x200000")
		expect(result.estimatedFee):toBe("0x180000")
		expect(result.token):toBe("STRK")
		expect(result.deficit):toBe(nil)
	end)

	it("returns hasSufficientBalance=false with deficit when balance is insufficient", function()
		resetHandlers()
		-- Balance: 0x1000 (low), 0x0 (high) = 0x1000
		-- Fee: 0x100000 * 1.5 = 0x180000
		-- 0x1000 < 0x180000 -> insufficient
		mockHandlers["starknet_call"] = function(_params)
			return { "0x1000", "0x0" }
		end
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(false)
		expect(result.balance):toBe("0x1000")
		expect(result.estimatedFee):toBe("0x180000")
		-- deficit = 0x180000 - 0x1000 = 0x17f000
		expect(result.deficit):toBe("0x17f000")
	end)

	it("returns hasSufficientBalance=true when balance equals fee exactly", function()
		resetHandlers()
		-- Balance exactly = fee estimate (0x180000)
		mockHandlers["starknet_call"] = function(_params)
			return { "0x180000", "0x0" }
		end
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(true)
		expect(result.deficit):toBe(nil)
	end)

	it("handles zero balance", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x0" }
		end
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(false)
		expect(result.balance):toBe("0x0")
		expect(result.deficit):toBe("0x180000")
	end)

	it("converts u256 high word correctly", function()
		resetHandlers()
		-- Balance: low=0x0, high=0x1 -> 2^128 which is a huge number, certainly sufficient
		mockHandlers["starknet_call"] = function(_params)
			return { "0x0", "0x1" }
		end
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(true)
		-- Balance = 1 * 2^128 = 0x100000000000000000000000000000000
		expect(result.balance):toBe("0x100000000000000000000000000000000")
	end)

	it("converts u256 with both low and high words", function()
		resetHandlers()
		-- Balance: low=0xff, high=0x1 -> 2^128 + 0xff
		mockHandlers["starknet_call"] = function(_params)
			return { "0xff", "0x1" }
		end
		local provider = createTestProvider()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.hasSufficientBalance):toBe(true)
		expect(result.balance):toBe("0x1000000000000000000000000000000ff")
	end)

	it("defaults to STRK token", function()
		resetHandlers()
		local provider = createTestProvider()
		rpc.clearRequestLog()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.token):toBe("STRK")

		-- Verify the call was made to the STRK token contract
		local foundCall = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				foundCall = true
				expect(entry.params[1].contract_address):toBe(STRK_TOKEN)
			end
		end
		expect(foundCall).toBeTruthy()
	end)

	it("supports ETH token selection", function()
		resetHandlers()
		local provider = createTestProvider()
		rpc.clearRequestLog()

		local result = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
			token = "ETH",
		}):expect()

		expect(result.token):toBe("ETH")

		-- Verify the call was made to the ETH token contract
		local foundCall = false
		for _, entry in requestLog do
			if entry.method == "starknet_call" then
				foundCall = true
				expect(entry.params[1].contract_address):toBe(ETH_TOKEN)
			end
		end
		expect(foundCall).toBeTruthy()
	end)

	it("rejects unsupported token", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.checkDeploymentBalance({
				address = EXPECTED_ADDR_1_OZ,
				classHash = OZ_CLASS_HASH,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				provider = provider,
				token = "USDC",
			})
		end).toThrow()
	end)

	it("uses custom fee multiplier", function()
		resetHandlers()
		-- Balance: 0x190000 -- between 1.5x (0x180000) and 2x (0x200000)
		mockHandlers["starknet_call"] = function(_params)
			return { "0x190000", "0x0" }
		end
		local provider = createTestProvider()

		-- With default 1.5x: sufficient
		local result1 = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		}):expect()
		expect(result1.hasSufficientBalance):toBe(true)

		-- With 2.0x: insufficient (0x190000 < 0x200000)
		local result2 = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
			feeMultiplier = 2.0,
		}):expect()
		expect(result2.hasSufficientBalance):toBe(false)
		expect(result2.estimatedFee):toBe("0x200000")
	end)

	it("throws on missing provider", function()
		expect(function()
			Account.checkDeploymentBalance({
				address = EXPECTED_ADDR_1_OZ,
				classHash = OZ_CLASS_HASH,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				provider = nil :: any,
			})
		end).toThrow()
	end)

	it("throws on missing address", function()
		local provider = createTestProvider()
		expect(function()
			Account.checkDeploymentBalance({
				address = nil :: any,
				classHash = OZ_CLASS_HASH,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				provider = provider,
			})
		end).toThrow()
	end)

	it("throws on missing classHash", function()
		local provider = createTestProvider()
		expect(function()
			Account.checkDeploymentBalance({
				address = EXPECTED_ADDR_1_OZ,
				classHash = nil :: any,
				constructorCalldata = { PUBKEY_1 },
				salt = PUBKEY_1,
				provider = provider,
			})
		end).toThrow()
	end)

	it("propagates RPC error on balance fetch failure", function()
		resetHandlers()
		mockHandlers["starknet_call"] = function(_params)
			error("Balance fetch failed")
		end
		local provider = createTestProvider()

		local promise = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		})
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("propagates RPC error on fee estimation failure", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("Fee estimation failed")
		end
		local provider = createTestProvider()

		local promise = Account.checkDeploymentBalance({
			address = EXPECTED_ADDR_1_OZ,
			classHash = OZ_CLASS_HASH,
			constructorCalldata = { PUBKEY_1 },
			salt = PUBKEY_1,
			provider = provider,
		})
		expect(promise:getStatus()):toBe("Rejected")
	end)
end)

--------------------------------------------------------------------------------
-- getDeploymentFundingInfo
--------------------------------------------------------------------------------

describe("Account.getDeploymentFundingInfo", function()
	it("returns correct address for OZ account", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("returns all required fields", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.address).toBeTruthy()
		expect(result.estimatedFee).toBeTruthy()
		expect(result.token):toBe("STRK")
		expect(result.tokenAddress):toBe(STRK_TOKEN)
		expect(result.classHash).toBeTruthy()
		expect(result.constructorCalldata).toBeTruthy()
		expect(result.salt).toBeTruthy()
	end)

	it("defaults to OZ account type", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		-- OZ class hash (as-is from constant, not normalized)
		expect(result.classHash):toBe(OZ_CLASS_HASH)
		-- OZ constructor calldata = [publicKey]
		expect(#result.constructorCalldata):toBe(1)
		expect(result.constructorCalldata[1]):toBe(PUBKEY_1)
	end)

	it("uses OZ class hash by default", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.classHash):toBe(Account.OZ_CLASS_HASH)
	end)

	it("supports Argent account type", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			accountType = "argent",
		}):expect()

		expect(result.classHash):toBe(Account.ARGENT_CLASS_HASH)
		-- Argent constructor calldata (no guardian) = [0x0, publicKey, 0x0]
		expect(#result.constructorCalldata):toBe(3)
		expect(result.constructorCalldata[1]):toBe("0x0")
		expect(result.constructorCalldata[2]):toBe(PUBKEY_1)
		expect(result.constructorCalldata[3]):toBe("0x0")
	end)

	it("supports Argent with guardian", function()
		resetHandlers()
		local provider = createTestProvider()
		local guardianKey = "0xabc123"

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			accountType = "argent",
			guardian = guardianKey,
		}):expect()

		-- Argent with guardian = [0x0, publicKey, 0x1, 0x0, guardianKey]
		expect(#result.constructorCalldata):toBe(5)
		expect(result.constructorCalldata[1]):toBe("0x0")
		expect(result.constructorCalldata[3]):toBe("0x1")
		expect(result.constructorCalldata[5]):toBe(guardianKey)
	end)

	it("supports custom class hash", function()
		resetHandlers()
		local provider = createTestProvider()
		local customClassHash = "0x12345"

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			classHash = customClassHash,
		}):expect()

		expect(result.classHash):toBe(customClassHash)
	end)

	it("supports custom salt", function()
		resetHandlers()
		local provider = createTestProvider()
		local customSalt = "0xdeadbeef"

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			salt = customSalt,
		}):expect()

		expect(result.salt):toBe(customSalt)
	end)

	it("defaults salt to publicKey", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.salt):toBe(PUBKEY_1)
	end)

	it("includes estimated fee with default multiplier", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		-- overall_fee 0x100000 * 1.5 = 0x180000
		expect(result.estimatedFee):toBe("0x180000")
	end)

	it("applies custom fee multiplier", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			feeMultiplier = 2.0,
		}):expect()

		expect(result.estimatedFee):toBe("0x200000")
	end)

	it("always returns STRK as token", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		expect(result.token):toBe("STRK")
		expect(result.tokenAddress):toBe(STRK_TOKEN)
	end)

	it("throws on missing provider", function()
		expect(function()
			Account.getDeploymentFundingInfo({
				publicKey = PUBKEY_1,
				provider = nil :: any,
			})
		end).toThrow()
	end)

	it("throws on missing publicKey", function()
		local provider = createTestProvider()
		expect(function()
			Account.getDeploymentFundingInfo({
				publicKey = nil :: any,
				provider = provider,
			})
		end).toThrow()
	end)

	it("rejects unsupported account type", function()
		local provider = createTestProvider()
		expect(function()
			Account.getDeploymentFundingInfo({
				publicKey = PUBKEY_1,
				provider = provider,
				accountType = "unknown",
			})
		end).toThrow()
	end)

	it("propagates RPC error on fee estimation failure", function()
		resetHandlers()
		mockHandlers["starknet_estimateFee"] = function(_params)
			error("Fee estimation failed")
		end
		local provider = createTestProvider()

		local promise = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		})
		expect(promise:getStatus()):toBe("Rejected")
	end)

	it("computed address matches Account.computeAddress for OZ", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
		}):expect()

		local directAddress = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_1,
		})

		expect(result.address):toBe(directAddress)
	end)

	it("computed address matches Account.computeAddress for Argent", function()
		resetHandlers()
		local provider = createTestProvider()

		local result = Account.getDeploymentFundingInfo({
			publicKey = PUBKEY_1,
			provider = provider,
			accountType = "argent",
		}):expect()

		local directAddress = Account.computeAddress({
			classHash = ARGENT_CLASS_HASH,
			publicKey = PUBKEY_1,
			constructorCalldata = { "0x0", PUBKEY_1, "0x0" },
		})

		expect(result.address):toBe(directAddress)
	end)
end)
