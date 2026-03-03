--!strict
local serde = require("@lune/serde")

local AccountType = require("../../src/wallet/AccountType")
local AccountFactory = require("../../src/wallet/AccountFactory")
local Account = require("../../src/wallet/Account")
local StarkSigner = require("../../src/signer/StarkSigner")
local RpcProvider = require("../../src/provider/RpcProvider")
local RpcTypes = require("../../src/provider/RpcTypes")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Test constants
--------------------------------------------------------------------------------

-- Private keys from StarkSigner test suite
local PRIVKEY_1 = "0x2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c"
local PRIVKEY_2 = "0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F"
local PRIVKEY_3 = "0x1"

-- Public keys (verified from StarkSigner tests)
local PUBKEY_1 = "0x499f65ae2f71d5298d2d88823b2e5e19596a71aac1984710479e406a002439"
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

local SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Mock RPC layer
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function resetHandlers()
	mockHandlers = {}
	requestLog = {}

	mockHandlers["starknet_chainId"] = function(_params)
		return SN_SEPOLIA
	end

	-- Default: getNonce errors (account not deployed) — triggers deployment flow
	mockHandlers["starknet_getNonce"] = function(_params)
		error("Contract not found")
	end

	mockHandlers["starknet_estimateFee"] = function(_params)
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

	mockHandlers["starknet_addDeployAccountTransaction"] = function(_params)
		return {
			transaction_hash = "0xdeploy123",
			contract_address = "0xdeployed",
		}
	end

	mockHandlers["starknet_getTransactionReceipt"] = function(_params)
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

	mockHandlers["starknet_getTransactionStatus"] = function(_params)
		return {
			finality_status = "ACCEPTED_ON_L2",
			execution_status = "SUCCEEDED",
		}
	end
end

local function createMockHttpRequest(): (request: RpcTypes.HttpRequest) -> RpcTypes.HttpResponse
	return function(request: RpcTypes.HttpRequest): RpcTypes.HttpResponse
		local body = serde.decode("json", request.Body or "{}") :: any
		local method: string = body.method or ""
		local params: any = body.params
		local id: number = body.id or 0

		table.insert(requestLog, { method = method, params = params })

		local handler = mockHandlers[method]
		if handler then
			local ok, result = pcall(handler, params)
			if ok then
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						result = result,
					}),
					Success = true,
				}
			else
				return {
					StatusCode = 200,
					Body = serde.encode("json", {
						jsonrpc = "2.0",
						id = id,
						error = {
							code = -32000,
							message = tostring(result),
						},
					}),
					Success = true,
				}
			end
		end

		return {
			StatusCode = 200,
			Body = serde.encode("json", {
				jsonrpc = "2.0",
				id = id,
				error = {
					code = -32601,
					message = `Method not found: {method}`,
				},
			}),
			Success = true,
		}
	end
end

local function createTestProvider(): any
	local config: any = {
		nodeUrl = "http://mock-rpc.test",
		retryAttempts = 1,
		retryDelay = 0.01,
		_httpRequest = createMockHttpRequest(),
		_sleep = function(_seconds: number) end,
		_clock = os.clock,
	}

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

resetHandlers()

--------------------------------------------------------------------------------
-- AccountType - class hash constants
--------------------------------------------------------------------------------

describe("AccountType - class hash constants", function()
	it("exposes OZ_CLASS_HASH matching Account constant", function()
		expect(AccountType.OZ_CLASS_HASH):toBe(Account.OZ_CLASS_HASH)
	end)

	it("exposes ARGENT_CLASS_HASH matching Account constant", function()
		expect(AccountType.ARGENT_CLASS_HASH):toBe(Account.ARGENT_CLASS_HASH)
	end)

	it("OZ config has correct type", function()
		expect(AccountType.OZ.type):toBe("oz")
	end)

	it("OZ config has correct classHash", function()
		expect(AccountType.OZ.classHash):toBe(AccountType.OZ_CLASS_HASH)
	end)

	it("Argent config has correct type", function()
		expect(AccountType.Argent.type):toBe("argent")
	end)

	it("Argent config has correct classHash", function()
		expect(AccountType.Argent.classHash):toBe(AccountType.ARGENT_CLASS_HASH)
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
		expect(AccountType.OZ_CLASS_HASH):toBe(
			"0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
		)
	end)

	it("Argent class hash matches expected v0.4.0 value", function()
		expect(AccountType.ARGENT_CLASS_HASH):toBe(
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
