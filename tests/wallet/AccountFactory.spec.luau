--!strict
local AccountType = require("../../src/wallet/AccountType")
local AccountFactory = require("../../src/wallet/AccountFactory")
local Account = require("../../src/wallet/Account")
local Constants = require("../../src/constants")
local StarkSigner = require("../../src/signer/StarkSigner")
local TestUtils = require("../helpers/TestUtils")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

-- Private keys from StarkSigner test suite
local PRIVKEY_1 = TestUtils.TEST_PRIVATE_KEY
local PRIVKEY_2 = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F"
local PRIVKEY_3 = "0x1"

-- Public keys (verified from StarkSigner tests)
local PUBKEY_1 = TestUtils.TEST_PUBLIC_KEY
local PUBKEY_2 = "0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf"
local PUBKEY_3 = "0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca"

-- Expected addresses (from Account.spec.luau, verified against starknet.js)
local EXPECTED_ADDR_1_OZ = "0x76d427e4760e8a0947f747c98263827154aca2c999b288a2087cd9655e2008d"
local EXPECTED_ADDR_2_OZ = "0x568f41175d86b1ea857a8daba89430ebe5b5da27c6848fa8234392151ea8b39"
local EXPECTED_ADDR_3_OZ = "0x2b5cea709ab25612f9d014a3312f1c6dbd988add3bf396c1866db1b03b09194"

local EXPECTED_ADDR_1_ARGENT = "0x4fa568d3d598d25e4d9ee7b826f6fc1ffbe1914fe9546019507ab662451623c"
local EXPECTED_ADDR_2_ARGENT = "0x42daaf2564a6231861945eba630e2ead610e1fd16af350b9450b28da60b3ef3"
local EXPECTED_ADDR_3_ARGENT = "0x1ace7c995fff4059266d7ae6b85abce75273bc3b2873531a45c038ed798d082"

local EXPECTED_ADDR_1_ARGENT_GUARDIAN = "0x129c3b10ff728e0be8a1e23004df70de1b67875506b5857bde61d657eecf38a"

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers

-- Override defaults with factory-specific handlers
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

--------------------------------------------------------------------------------
-- AccountType - class hash constants
--------------------------------------------------------------------------------

describe("AccountType - class hash constants from Constants", function()
	it("OZ classHash matches Constants.OZ_ACCOUNT_CLASS_HASH", function()
		expect(AccountType.OZ.classHash):toBe(Constants.OZ_ACCOUNT_CLASS_HASH)
	end)

	it("Argent classHash matches Constants.ARGENT_ACCOUNT_CLASS_HASH", function()
		expect(AccountType.Argent.classHash):toBe(Constants.ARGENT_ACCOUNT_CLASS_HASH)
	end)

	it("Braavos classHash matches Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH", function()
		expect(AccountType.Braavos.classHash):toBe(Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH)
	end)

	it("OZ config has correct type", function()
		expect(AccountType.OZ.type):toBe("oz")
	end)

	it("Argent config has correct type", function()
		expect(AccountType.Argent.type):toBe("argent")
	end)

	it("Braavos config has correct type", function()
		expect(AccountType.Braavos.type):toBe("braavos")
	end)
end)

--------------------------------------------------------------------------------
-- AccountType.OZ - constructor calldata builder
--------------------------------------------------------------------------------

describe("AccountType.OZ - calldata builder", function()
	it("produces [publicKey] for a single public key", function()
		local calldata = AccountType.OZ(PUBKEY_1)
		expect(#calldata):toBe(1)
		expect(calldata[1]):toBe(PUBKEY_1)
	end)

	it("produces [publicKey] for generator key", function()
		local calldata = AccountType.OZ(PUBKEY_3)
		expect(#calldata):toBe(1)
		expect(calldata[1]):toBe(PUBKEY_3)
	end)

	it("matches Account.getConstructorCalldata for oz type", function()
		local fromType = AccountType.OZ(PUBKEY_1)
		local fromAccount = Account.getConstructorCalldata("oz", PUBKEY_1)
		expect(#fromType):toBe(#fromAccount)
		for i, v in fromType do
			expect(v):toBe(fromAccount[i])
		end
	end)
end)

--------------------------------------------------------------------------------
-- AccountType.Argent - constructor calldata builder
--------------------------------------------------------------------------------

describe("AccountType.Argent - calldata builder", function()
	it("produces [0, ownerKey, 0] without guardian", function()
		local calldata = AccountType.Argent(PUBKEY_1)
		expect(#calldata):toBe(3)
		expect(calldata[1]):toBe("0x0")
		expect(calldata[2]):toBe(PUBKEY_1)
		expect(calldata[3]):toBe("0x0")
	end)

	it("produces [0, ownerKey, 1, 0, guardianKey] with guardian", function()
		local guardianKey = "0xdeadbeef"
		local calldata = AccountType.Argent(PUBKEY_1, guardianKey)
		expect(#calldata):toBe(5)
		expect(calldata[1]):toBe("0x0")
		expect(calldata[2]):toBe(PUBKEY_1)
		expect(calldata[3]):toBe("0x1")
		expect(calldata[4]):toBe("0x0")
		expect(calldata[5]):toBe(guardianKey)
	end)

	it("matches Account.getConstructorCalldata for argent type (no guardian)", function()
		local fromType = AccountType.Argent(PUBKEY_2)
		local fromAccount = Account.getConstructorCalldata("argent", PUBKEY_2)
		expect(#fromType):toBe(#fromAccount)
		for i, v in fromType do
			expect(v):toBe(fromAccount[i])
		end
	end)

	it("matches Account.getConstructorCalldata for argent type (with guardian)", function()
		local guardian = "0xdeadbeef"
		local fromType = AccountType.Argent(PUBKEY_1, guardian)
		local fromAccount = Account.getConstructorCalldata("argent", PUBKEY_1, guardian)
		expect(#fromType):toBe(#fromAccount)
		for i, v in fromType do
			expect(v):toBe(fromAccount[i])
		end
	end)
end)

--------------------------------------------------------------------------------
-- AccountType.custom
--------------------------------------------------------------------------------

describe("AccountType.custom", function()
	it("creates a callable account type with custom classHash", function()
		local customHash = "0xcustom_class_hash"
		local custom = AccountType.custom({
			type = "oz",
			classHash = customHash,
			buildCalldata = function(publicKey: string): { string }
				return { publicKey }
			end,
		})
		expect(custom.type):toBe("oz")
		expect(custom.classHash):toBe(customHash)
	end)

	it("custom type is callable", function()
		local custom = AccountType.custom({
			type = "oz",
			classHash = "0xabc",
			buildCalldata = function(publicKey: string): { string }
				return { publicKey }
			end,
		})
		local calldata = custom(PUBKEY_1)
		expect(#calldata):toBe(1)
		expect(calldata[1]):toBe(PUBKEY_1)
	end)

	it("custom type supports custom calldata formats", function()
		local custom = AccountType.custom({
			type = "custom_wallet",
			classHash = "0xdef",
			buildCalldata = function(key1: string, key2: string): { string }
				return { key1, key2, "0x42" }
			end,
		})
		local calldata = custom(PUBKEY_1, PUBKEY_2)
		expect(#calldata):toBe(3)
		expect(calldata[1]):toBe(PUBKEY_1)
		expect(calldata[2]):toBe(PUBKEY_2)
		expect(calldata[3]):toBe("0x42")
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory.new - validation
--------------------------------------------------------------------------------

describe("AccountFactory.new - validation", function()
	it("creates a factory with valid arguments", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)

		local factory = AccountFactory.new(provider, AccountType.OZ, signer)
		expect(factory):toBeTruthy()
	end)

	it("errors when provider is missing", function()
		local signer = StarkSigner.new(PRIVKEY_1)
		expect(function()
			AccountFactory.new(nil :: any, AccountType.OZ, signer)
		end):toThrowType("ValidationError")
	end)

	it("errors when accountType is missing", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		expect(function()
			AccountFactory.new(provider, nil :: any, signer)
		end):toThrowType("ValidationError")
	end)

	it("errors when accountType lacks type field", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		expect(function()
			AccountFactory.new(provider, { classHash = "0x123" }, signer)
		end):toThrowType("ValidationError")
	end)

	it("errors when accountType lacks classHash field", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		expect(function()
			AccountFactory.new(provider, { type = "oz" }, signer)
		end):toThrowType("ValidationError")
	end)

	it("errors when signer is missing", function()
		resetHandlers()
		local provider = createTestProvider()
		expect(function()
			AccountFactory.new(provider, AccountType.OZ, nil :: any)
		end):toThrowType("ValidationError")
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - OZ
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - OZ", function()
	it("returns { account, address, deployTx }", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.account):toBeTruthy()
		expect(result.address):toBeTruthy()
		expect(type(result.deployTx)):toBe("function")
	end)

	it("computes correct OZ address for privkey_1", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("computes correct OZ address for privkey_2", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_2)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_2_OZ)
	end)

	it("computes correct OZ address for privkey_3", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_3)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_3_OZ)
	end)

	it("account has correct address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("account has correct signer", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		expect(result.account.signer):toBe(signer)
	end)

	it("matches Account.fromPrivateKey address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local factoryResult = factory:createAccount()
		local directAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "oz",
		})
		expect(factoryResult.address):toBe(directAccount.address)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - Argent (no guardian)
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - Argent (no guardian)", function()
	it("computes correct Argent address for privkey_1", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_1_ARGENT)
	end)

	it("computes correct Argent address for privkey_2", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_2)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_2_ARGENT)
	end)

	it("computes correct Argent address for privkey_3", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_3)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local result = factory:createAccount()
		expect(result.address):toBe(EXPECTED_ADDR_3_ARGENT)
	end)

	it("matches Account.fromPrivateKey address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local factoryResult = factory:createAccount()
		local directAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		expect(factoryResult.address):toBe(directAccount.address)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - Argent (with guardian)
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - Argent (with guardian)", function()
	it("computes correct address with guardian key", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local result = factory:createAccount({ guardian = "0xdeadbeef" })
		expect(result.address):toBe(EXPECTED_ADDR_1_ARGENT_GUARDIAN)
	end)

	it("guardian changes the derived address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local withoutGuardian = factory:createAccount()
		local withGuardian = factory:createAccount({ guardian = "0xdeadbeef" })
		expect(withGuardian.address ~= withoutGuardian.address):toBe(true)
	end)

	it("matches Account.fromPrivateKey address with guardian", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.Argent, signer)

		local factoryResult = factory:createAccount({ guardian = "0xdeadbeef" })
		local directAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
			guardian = "0xdeadbeef",
		})
		expect(factoryResult.address):toBe(directAccount.address)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - custom options
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - custom options", function()
	it("overrides classHash from options", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local defaultResult = factory:createAccount()
		local customResult = factory:createAccount({
			classHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003",
		})
		expect(customResult.address ~= defaultResult.address):toBe(true)
	end)

	it("custom classHash produces correct address (OZ v0.14)", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount({
			classHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003",
		})
		-- Should match the OZ v0.14 expected address from Account tests
		expect(result.address):toBe("0x38de74aab5907ad06a25dd88fafe0296a2ca303fedb8b37926edf15363aee67")
	end)

	it("custom salt changes address", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local defaultResult = factory:createAccount()
		local customSalt = factory:createAccount({ salt = "0xdeadbeef" })
		expect(customSalt.address ~= defaultResult.address):toBe(true)
	end)

	it("default salt is publicKey", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local defaultResult = factory:createAccount()
		local explicitSalt = factory:createAccount({ salt = PUBKEY_1 })
		expect(explicitSalt.address):toBe(defaultResult.address)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - custom AccountType
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - custom AccountType", function()
	it("works with AccountType.custom()", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local customType = AccountType.custom({
			type = "oz",
			classHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003",
			buildCalldata = function(publicKey: string): { string }
				return { publicKey }
			end,
		})
		local factory = AccountFactory.new(provider, customType, signer)

		local result = factory:createAccount()
		-- Custom OZ hash with same OZ calldata format
		expect(result.address):toBe("0x38de74aab5907ad06a25dd88fafe0296a2ca303fedb8b37926edf15363aee67")
	end)

	it("produces different address than default OZ", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local customType = AccountType.custom({
			type = "oz",
			classHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003",
			buildCalldata = function(publicKey: string): { string }
				return { publicKey }
			end,
		})
		local factory = AccountFactory.new(provider, customType, signer)
		local defaultFactory = AccountFactory.new(provider, AccountType.OZ, signer)

		local customResult = factory:createAccount()
		local defaultResult = defaultFactory:createAccount()
		expect(customResult.address ~= defaultResult.address):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory:createAccount - deployTx
--------------------------------------------------------------------------------

describe("AccountFactory:createAccount - deployTx", function()
	it("deployTx returns a Promise", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		local promise = result.deployTx({ dryRun = true })
		expect(promise):toBeTruthy()
		expect(type(promise.andThen)):toBe("function")
	end)

	it("deployTx passes options through to account:deployAccount", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		-- dryRun should produce a result with transaction/signature fields
		local deployResult = result.deployTx({ dryRun = true }):expect()
		expect(deployResult):toBeTruthy()
		expect(deployResult.contractAddress):toBeTruthy()
		-- dryRun includes transaction and signature
		expect(deployResult.transaction):toBeTruthy()
		expect(deployResult.signature):toBeTruthy()
	end)

	it("deployTx returns alreadyDeployed when account exists", function()
		resetHandlers()
		-- Override getNonce to succeed (account already deployed)
		mockHandlers["starknet_getNonce"] = function(_params)
			return "0x5"
		end

		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result = factory:createAccount()
		local deployResult = result.deployTx():expect()
		expect(deployResult.alreadyDeployed):toBe(true)
		expect(deployResult.transactionHash):toBe("0x0")
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory - multiple accounts from same factory
--------------------------------------------------------------------------------

describe("AccountFactory - multiple accounts", function()
	it("same factory + signer always produces the same account", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local result1 = factory:createAccount()
		local result2 = factory:createAccount()
		expect(result1.address):toBe(result2.address)
	end)

	it("different signers produce different accounts", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer1 = StarkSigner.new(PRIVKEY_1)
		local signer2 = StarkSigner.new(PRIVKEY_2)
		local factory1 = AccountFactory.new(provider, AccountType.OZ, signer1)
		local factory2 = AccountFactory.new(provider, AccountType.OZ, signer2)

		local result1 = factory1:createAccount()
		local result2 = factory2:createAccount()
		expect(result1.address ~= result2.address):toBe(true)
	end)

	it("different account types produce different accounts for same signer", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local ozFactory = AccountFactory.new(provider, AccountType.OZ, signer)
		local argentFactory = AccountFactory.new(provider, AccountType.Argent, signer)

		local ozResult = ozFactory:createAccount()
		local argentResult = argentFactory:createAccount()
		expect(ozResult.address ~= argentResult.address):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- AccountFactory - class hash versioning
--------------------------------------------------------------------------------

describe("AccountFactory - class hash versioning", function()
	it("OZ class hash matches expected v0.8.1 value", function()
		expect(AccountType.OZ.classHash):toBe(
			"0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
		)
	end)

	it("Argent class hash matches expected v0.4.0 value", function()
		expect(AccountType.Argent.classHash):toBe(
			"0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"
		)
	end)

	it("class hashes are configurable via custom account type", function()
		local newHash = "0xdeadbeef1234"
		local custom = AccountType.custom({
			type = "oz",
			classHash = newHash,
			buildCalldata = function(publicKey: string): { string }
				return { publicKey }
			end,
		})
		expect(custom.classHash):toBe(newHash)
	end)

	it("class hashes are configurable via createAccount options", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local factory = AccountFactory.new(provider, AccountType.OZ, signer)

		local overrideHash = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003"
		local result = factory:createAccount({ classHash = overrideHash })
		-- Should produce a different address than default
		expect(result.address ~= EXPECTED_ADDR_1_OZ):toBe(true)
	end)
end)
