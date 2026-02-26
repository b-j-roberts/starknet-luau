--!strict
local serde = require("@lune/serde")

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

-- OZ class hashes
local OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
local OZ_CLASS_HASH_2 = "0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003"

-- Expected OZ addresses (computed by starknet.js calculateContractAddressFromHash)
local EXPECTED_ADDR_1_OZ = "0x76d427e4760e8a0947f747c98263827154aca2c999b288a2087cd9655e2008d"
local EXPECTED_ADDR_2_OZ = "0x568f41175d86b1ea857a8daba89430ebe5b5da27c6848fa8234392151ea8b39"
local EXPECTED_ADDR_3_OZ = "0x2b5cea709ab25612f9d014a3312f1c6dbd988add3bf396c1866db1b03b09194"

local EXPECTED_ADDR_1_OZ2 = "0x38de74aab5907ad06a25dd88fafe0296a2ca303fedb8b37926edf15363aee67"
local EXPECTED_ADDR_2_OZ2 = "0x365ff7fefa7c4a5e0c41e2c27aa55d35b6439fa891ad5b85da1cdffeb736f08"
local EXPECTED_ADDR_3_OZ2 = "0x4235a538f2315ca101e7260ff94997456428a1a7138b71ab335a423602400d8"

-- Expected Argent X addresses (v0.4.0, calldata = [0, publicKey, 0])
local EXPECTED_ADDR_1_ARGENT = "0x4fa568d3d598d25e4d9ee7b826f6fc1ffbe1914fe9546019507ab662451623c"
local EXPECTED_ADDR_2_ARGENT = "0x42daaf2564a6231861945eba630e2ead610e1fd16af350b9450b28da60b3ef3"
local EXPECTED_ADDR_3_ARGENT = "0x1ace7c995fff4059266d7ae6b85abce75273bc3b2873531a45c038ed798d082"

-- Expected Argent X address with guardian
local EXPECTED_ADDR_1_ARGENT_GUARDIAN = "0x129c3b10ff728e0be8a1e23004df70de1b67875506b5857bde61d657eecf38a"

-- Expected Braavos addresses (base class hash, calldata = [publicKey])
local EXPECTED_ADDR_1_BRAAVOS = "0x2270cb3dcd6ea9349c122cf2dc3e17ffe0d19130a524b96ccbae577846eb533"
local EXPECTED_ADDR_2_BRAAVOS = "0x13f206265ce80c4dd163a66cd826276329430b3a9b94fe1d67207ec6b722381"
local EXPECTED_ADDR_3_BRAAVOS = "0x260565660443aa1bd7b49040bc600b36e3dd82c4dd8d06ee1a77b4dc595bae7"

local SN_SEPOLIA = "0x534e5f5345504f4c4941"

--------------------------------------------------------------------------------
-- Mock RPC layer (adapted from TransactionBuilder tests)
--------------------------------------------------------------------------------

local mockHandlers: { [string]: (params: any) -> any } = {}
local requestLog: { { method: string, params: any } } = {}

local function resetHandlers()
	mockHandlers = {}
	requestLog = {}

	mockHandlers["starknet_chainId"] = function(_params)
		return SN_SEPOLIA
	end

	mockHandlers["starknet_getNonce"] = function(_params)
		return "0x5"
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

	mockHandlers["starknet_addInvokeTransaction"] = function(_params)
		return { transaction_hash = "0xabc123" }
	end

	mockHandlers["starknet_getTransactionReceipt"] = function(_params)
		return {
			transaction_hash = "0xabc123",
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

local function createTestCalls(): { any }
	return {
		{
			contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
			entrypoint = "transfer",
			calldata = {
				"0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
				"0x3e8",
				"0x0",
			},
		},
	}
end

resetHandlers()

--------------------------------------------------------------------------------
-- computeAddress - OZ
--------------------------------------------------------------------------------

describe("Account.computeAddress - OZ class hash", function()
	it("computes correct address for privkey_1 (starknet.js vector)", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_1,
		})
		expect(addr):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("computes correct address for privkey_2 (starknet.js vector)", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_2,
		})
		expect(addr):toBe(EXPECTED_ADDR_2_OZ)
	end)

	it("computes correct address for privkey_3 (generator key, starknet.js vector)", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
		})
		expect(addr):toBe(EXPECTED_ADDR_3_OZ)
	end)
end)

describe("Account.computeAddress - alternate class hash", function()
	it("computes correct address for privkey_1 with OZ v0.14", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH_2,
			publicKey = PUBKEY_1,
		})
		expect(addr):toBe(EXPECTED_ADDR_1_OZ2)
	end)

	it("computes correct address for privkey_2 with OZ v0.14", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH_2,
			publicKey = PUBKEY_2,
		})
		expect(addr):toBe(EXPECTED_ADDR_2_OZ2)
	end)

	it("computes correct address for privkey_3 with OZ v0.14", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH_2,
			publicKey = PUBKEY_3,
		})
		expect(addr):toBe(EXPECTED_ADDR_3_OZ2)
	end)
end)

describe("Account.computeAddress - deployer and salt", function()
	it("computes correct address with non-zero deployer (starknet.js vector)", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
			deployer = "0x1234abcd",
		})
		expect(addr):toBe("0x2fc571eae3a2def65072a216ed75275fcc7a54fe4e386500d5b74cf77028b44")
	end)

	it("computes correct address with custom salt (starknet.js vector)", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
			salt = "0xdeadbeef",
		})
		expect(addr):toBe("0x452c8719749629fcdd8a1fc541ac2b9108cbdb33a63095125c4eeedeec052c7")
	end)

	it("defaults deployer to zero", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
		})
		expect(addr):toBe(EXPECTED_ADDR_3_OZ)
	end)

	it("defaults salt to publicKey", function()
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
			salt = PUBKEY_3,
		})
		expect(addr):toBe(EXPECTED_ADDR_3_OZ)
	end)
end)

describe("Account.computeAddress - custom constructor calldata", function()
	it("uses explicit constructorCalldata when provided", function()
		local addrDefault = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
		})
		local addrCustom = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
			constructorCalldata = { PUBKEY_3, "0x0" },
		})
		expect(addrCustom ~= addrDefault):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- computeAddress - Argent X
--------------------------------------------------------------------------------

describe("Account.computeAddress - Argent X", function()
	it("computes correct Argent address for pubkey_1 (no guardian)", function()
		local addr = Account.computeAddress({
			classHash = Account.ARGENT_CLASS_HASH,
			publicKey = PUBKEY_1,
			constructorCalldata = { "0x0", PUBKEY_1, "0x0" },
		})
		expect(addr):toBe(EXPECTED_ADDR_1_ARGENT)
	end)

	it("computes correct Argent address for pubkey_2 (no guardian)", function()
		local addr = Account.computeAddress({
			classHash = Account.ARGENT_CLASS_HASH,
			publicKey = PUBKEY_2,
			constructorCalldata = { "0x0", PUBKEY_2, "0x0" },
		})
		expect(addr):toBe(EXPECTED_ADDR_2_ARGENT)
	end)

	it("computes correct Argent address for pubkey_3 (no guardian)", function()
		local addr = Account.computeAddress({
			classHash = Account.ARGENT_CLASS_HASH,
			publicKey = PUBKEY_3,
			constructorCalldata = { "0x0", PUBKEY_3, "0x0" },
		})
		expect(addr):toBe(EXPECTED_ADDR_3_ARGENT)
	end)

	it("computes correct Argent address with guardian", function()
		local guardianKey = "0xdeadbeef"
		local addr = Account.computeAddress({
			classHash = Account.ARGENT_CLASS_HASH,
			publicKey = PUBKEY_1,
			constructorCalldata = { "0x0", PUBKEY_1, "0x1", "0x0", guardianKey },
		})
		expect(addr):toBe(EXPECTED_ADDR_1_ARGENT_GUARDIAN)
	end)

	it("Argent addresses differ from OZ addresses (same key)", function()
		expect(EXPECTED_ADDR_1_ARGENT ~= EXPECTED_ADDR_1_OZ):toBe(true)
		expect(EXPECTED_ADDR_2_ARGENT ~= EXPECTED_ADDR_2_OZ):toBe(true)
		expect(EXPECTED_ADDR_3_ARGENT ~= EXPECTED_ADDR_3_OZ):toBe(true)
	end)

	it("guardian changes the derived address", function()
		expect(EXPECTED_ADDR_1_ARGENT_GUARDIAN ~= EXPECTED_ADDR_1_ARGENT):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- computeAddress - Braavos
--------------------------------------------------------------------------------

describe("Account.computeAddress - Braavos", function()
	it("computes correct Braavos address for pubkey_1 (base class hash)", function()
		local addr = Account.computeAddress({
			classHash = Account.BRAAVOS_BASE_CLASS_HASH,
			publicKey = PUBKEY_1,
			constructorCalldata = { PUBKEY_1 },
		})
		expect(addr):toBe(EXPECTED_ADDR_1_BRAAVOS)
	end)

	it("computes correct Braavos address for pubkey_2 (base class hash)", function()
		local addr = Account.computeAddress({
			classHash = Account.BRAAVOS_BASE_CLASS_HASH,
			publicKey = PUBKEY_2,
			constructorCalldata = { PUBKEY_2 },
		})
		expect(addr):toBe(EXPECTED_ADDR_2_BRAAVOS)
	end)

	it("computes correct Braavos address for pubkey_3 (base class hash)", function()
		local addr = Account.computeAddress({
			classHash = Account.BRAAVOS_BASE_CLASS_HASH,
			publicKey = PUBKEY_3,
			constructorCalldata = { PUBKEY_3 },
		})
		expect(addr):toBe(EXPECTED_ADDR_3_BRAAVOS)
	end)

	it("Braavos addresses differ from OZ addresses (same key)", function()
		expect(EXPECTED_ADDR_1_BRAAVOS ~= EXPECTED_ADDR_1_OZ):toBe(true)
		expect(EXPECTED_ADDR_2_BRAAVOS ~= EXPECTED_ADDR_2_OZ):toBe(true)
		expect(EXPECTED_ADDR_3_BRAAVOS ~= EXPECTED_ADDR_3_OZ):toBe(true)
	end)

	it("Braavos addresses differ from Argent addresses (same key)", function()
		expect(EXPECTED_ADDR_1_BRAAVOS ~= EXPECTED_ADDR_1_ARGENT):toBe(true)
		expect(EXPECTED_ADDR_2_BRAAVOS ~= EXPECTED_ADDR_2_ARGENT):toBe(true)
		expect(EXPECTED_ADDR_3_BRAAVOS ~= EXPECTED_ADDR_3_ARGENT):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account.new (constructor)
--------------------------------------------------------------------------------

describe("Account.new", function()
	it("creates an account with address, signer, and provider", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)

		local account = Account.new({
			address = EXPECTED_ADDR_1_OZ,
			signer = signer,
			provider = provider,
		})
		expect(account):toBeTruthy()
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("errors when address is missing", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)

		expect(function()
			Account.new({
				address = nil :: any,
				signer = signer,
				provider = provider,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when signer is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.new({
				address = EXPECTED_ADDR_1_OZ,
				signer = nil :: any,
				provider = provider,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when provider is missing", function()
		local signer = StarkSigner.new(PRIVKEY_1)

		expect(function()
			Account.new({
				address = EXPECTED_ADDR_1_OZ,
				signer = signer,
				provider = nil :: any,
			})
		end):toThrowType("ValidationError")
	end)
end)

--------------------------------------------------------------------------------
-- Account.fromPrivateKey - OZ (default)
--------------------------------------------------------------------------------

describe("Account.fromPrivateKey - OZ (default)", function()
	it("derives correct address for privkey_1 with default OZ class hash", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("derives correct address for privkey_2 with default OZ class hash", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_OZ)
	end)

	it("derives correct address for privkey_3 with default OZ class hash", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_OZ)
	end)

	it("uses custom class hash when provided", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			classHash = OZ_CLASS_HASH_2,
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ2)
	end)

	it("explicit accountType='oz' matches default", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "oz",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("errors when privateKey is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = nil :: any,
				provider = provider,
			})
		end):toThrowType("ValidationError")
	end)

	it("errors when provider is missing", function()
		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = nil :: any,
			})
		end):toThrowType("ValidationError")
	end)

	it("stores the signer for later use", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		expect(account.signer):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Account.fromPrivateKey - Argent X
--------------------------------------------------------------------------------

describe("Account.fromPrivateKey - Argent X", function()
	it("derives correct Argent address for privkey_1", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_ARGENT)
	end)

	it("derives correct Argent address for privkey_2", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_ARGENT)
	end)

	it("derives correct Argent address for privkey_3", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_ARGENT)
	end)

	it("derives correct Argent address with guardian", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
			guardian = "0xdeadbeef",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_ARGENT_GUARDIAN)
	end)

	it("Argent address differs from OZ address (same key)", function()
		resetHandlers()
		local provider = createTestProvider()

		local ozAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		local argentAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		expect(argentAccount.address ~= ozAccount.address):toBe(true)
	end)

	it("supports custom class hash override for Argent", function()
		resetHandlers()
		local provider = createTestProvider()

		-- Use a custom Argent class hash — address should differ from default
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
			classHash = "0x029927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b", -- v0.3.1
		})
		expect(account.address ~= EXPECTED_ADDR_1_ARGENT):toBe(true)
	end)

	it("errors when guardian is used with non-Argent account", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = provider,
				accountType = "oz",
				guardian = "0xdeadbeef",
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account.fromPrivateKey - Braavos
--------------------------------------------------------------------------------

describe("Account.fromPrivateKey - Braavos", function()
	it("derives correct Braavos address for privkey_1", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_BRAAVOS)
	end)

	it("derives correct Braavos address for privkey_2", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_BRAAVOS)
	end)

	it("derives correct Braavos address for privkey_3", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_BRAAVOS)
	end)

	it("Braavos address differs from OZ and Argent addresses", function()
		resetHandlers()
		local provider = createTestProvider()

		local ozAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		local argentAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		local braavosAccount = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "braavos",
		})
		expect(braavosAccount.address ~= ozAccount.address):toBe(true)
		expect(braavosAccount.address ~= argentAccount.address):toBe(true)
	end)

	it("errors when guardian is used with Braavos account", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = provider,
				accountType = "braavos",
				guardian = "0xdeadbeef",
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account.fromPrivateKey - validation
--------------------------------------------------------------------------------

describe("Account.fromPrivateKey - accountType validation", function()
	it("errors on unsupported accountType", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = provider,
				accountType = "unknown",
			})
		end):toThrow()
	end)

	it("errors on empty string accountType", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = provider,
				accountType = "",
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account.detectAccountType
--------------------------------------------------------------------------------

describe("Account.detectAccountType", function()
	it("detects OZ class hash", function()
		expect(Account.detectAccountType(Account.OZ_CLASS_HASH)):toBe("oz")
	end)

	it("detects OZ v0.14 class hash", function()
		local result = Account.detectAccountType(OZ_CLASS_HASH_2)
		expect(result):toBe("oz")
	end)

	it("detects Argent X class hash (v0.4.0)", function()
		expect(Account.detectAccountType(Account.ARGENT_CLASS_HASH)):toBe("argent")
	end)

	it("detects Argent X class hash (v0.3.1)", function()
		expect(Account.detectAccountType("0x029927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b")):toBe(
			"argent"
		)
	end)

	it("detects Braavos base class hash", function()
		expect(Account.detectAccountType(Account.BRAAVOS_BASE_CLASS_HASH)):toBe("braavos")
	end)

	it("detects Braavos implementation class hash", function()
		expect(Account.detectAccountType(Account.BRAAVOS_CLASS_HASH)):toBe("braavos")
	end)

	it("returns nil for unknown class hash", function()
		expect(Account.detectAccountType("0xdeadbeef")):toBe(nil)
	end)

	it("handles padded class hash (leading zeros)", function()
		-- Same hash but with leading zero differences — BigInt normalization should handle it
		local result = Account.detectAccountType(
			"0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"
		)
		expect(result):toBe("argent")
	end)
end)

--------------------------------------------------------------------------------
-- Account.getConstructorCalldata
--------------------------------------------------------------------------------

describe("Account.getConstructorCalldata", function()
	it("returns [publicKey] for OZ accounts", function()
		local calldata = Account.getConstructorCalldata("oz", PUBKEY_1)
		expect(#calldata):toBe(1)
		expect(calldata[1]):toBe(PUBKEY_1)
	end)

	it("returns [0, publicKey, 0] for Argent accounts (no guardian)", function()
		local calldata = Account.getConstructorCalldata("argent", PUBKEY_1)
		expect(#calldata):toBe(3)
		expect(calldata[1]):toBe("0x0")
		expect(calldata[2]):toBe(PUBKEY_1)
		expect(calldata[3]):toBe("0x0")
	end)

	it("returns [0, publicKey, 1, 0, guardianKey] for Argent accounts (with guardian)", function()
		local guardianKey = "0xdeadbeef"
		local calldata = Account.getConstructorCalldata("argent", PUBKEY_1, guardianKey)
		expect(#calldata):toBe(5)
		expect(calldata[1]):toBe("0x0")
		expect(calldata[2]):toBe(PUBKEY_1)
		expect(calldata[3]):toBe("0x1")
		expect(calldata[4]):toBe("0x0")
		expect(calldata[5]):toBe(guardianKey)
	end)

	it("returns [publicKey] for Braavos accounts", function()
		local calldata = Account.getConstructorCalldata("braavos", PUBKEY_1)
		expect(#calldata):toBe(1)
		expect(calldata[1]):toBe(PUBKEY_1)
	end)
end)

--------------------------------------------------------------------------------
-- Account constants
--------------------------------------------------------------------------------

describe("Account constants", function()
	it("exposes OZ_CLASS_HASH", function()
		expect(Account.OZ_CLASS_HASH):toBe(OZ_CLASS_HASH)
	end)

	it("OZ_CLASS_HASH is a valid hex string", function()
		expect(string.sub(Account.OZ_CLASS_HASH, 1, 2)):toBe("0x")
		expect(#Account.OZ_CLASS_HASH > 2):toBe(true)
	end)

	it("exposes ARGENT_CLASS_HASH", function()
		expect(Account.ARGENT_CLASS_HASH):toBeTruthy()
		expect(string.sub(Account.ARGENT_CLASS_HASH, 1, 2)):toBe("0x")
	end)

	it("exposes BRAAVOS_CLASS_HASH", function()
		expect(Account.BRAAVOS_CLASS_HASH):toBeTruthy()
		expect(string.sub(Account.BRAAVOS_CLASS_HASH, 1, 2)):toBe("0x")
	end)

	it("exposes BRAAVOS_BASE_CLASS_HASH", function()
		expect(Account.BRAAVOS_BASE_CLASS_HASH):toBeTruthy()
		expect(string.sub(Account.BRAAVOS_BASE_CLASS_HASH, 1, 2)):toBe("0x")
	end)

	it("exposes account type constants", function()
		expect(Account.ACCOUNT_TYPE_OZ):toBe("oz")
		expect(Account.ACCOUNT_TYPE_ARGENT):toBe("argent")
		expect(Account.ACCOUNT_TYPE_BRAAVOS):toBe("braavos")
	end)

	it("all class hashes are distinct", function()
		expect(Account.OZ_CLASS_HASH ~= Account.ARGENT_CLASS_HASH):toBe(true)
		expect(Account.OZ_CLASS_HASH ~= Account.BRAAVOS_CLASS_HASH):toBe(true)
		expect(Account.OZ_CLASS_HASH ~= Account.BRAAVOS_BASE_CLASS_HASH):toBe(true)
		expect(Account.ARGENT_CLASS_HASH ~= Account.BRAAVOS_CLASS_HASH):toBe(true)
		expect(Account.ARGENT_CLASS_HASH ~= Account.BRAAVOS_BASE_CLASS_HASH):toBe(true)
		expect(Account.BRAAVOS_CLASS_HASH ~= Account.BRAAVOS_BASE_CLASS_HASH):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- account:getPublicKeyHex
--------------------------------------------------------------------------------

describe("Account:getPublicKeyHex", function()
	it("returns the correct public key for privkey_1", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		expect(account:getPublicKeyHex()):toBe(PUBKEY_1)
	end)

	it("returns the correct public key for privkey_2", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
		})
		expect(account:getPublicKeyHex()):toBe(PUBKEY_2)
	end)
end)

--------------------------------------------------------------------------------
-- account:getNonce
--------------------------------------------------------------------------------

describe("Account:getNonce", function()
	it("fetches nonce from provider", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local result = account:getNonce():expect()
		expect(result):toBe("0x5")
	end)

	it("passes correct address to provider", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		account:getNonce():expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				found = true
				local params = entry.params
				expect(params[2]):toBe(EXPECTED_ADDR_1_OZ)
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- account:estimateFee
--------------------------------------------------------------------------------

describe("Account:estimateFee", function()
	it("returns a fee estimate for calls", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local estimate = account:estimateFee(calls):expect()
		expect(estimate):toBeTruthy()
		expect(estimate.gas_consumed):toBe("0x1000")
		expect(estimate.gas_price):toBe("0x100")
	end)
end)

--------------------------------------------------------------------------------
-- account:execute
--------------------------------------------------------------------------------

describe("Account:execute", function()
	it("executes a transaction and returns hash", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result):toBeTruthy()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("passes options through to builder", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls, {
			nonce = "0x10",
			feeMultiplier = 2.0,
		}):expect()
		expect(result.transactionHash):toBeTruthy()
	end)

	it("supports dryRun mode", function()
		resetHandlers()
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls, { dryRun = true }):expect()
		expect(result.transactionHash):toBeTruthy()
		expect(result.transaction):toBeTruthy()
		expect(result.signature):toBeTruthy()
	end)

	it("uses the derived address as sender", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local calls = createTestCalls()
		account:execute(calls):expect()

		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				found = true
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(EXPECTED_ADDR_1_OZ)
			end
		end
		expect(found):toBe(true)
	end)

	it("works with Argent account type", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result.transactionHash):toBeTruthy()

		-- Verify the Argent-derived address was used
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(EXPECTED_ADDR_1_ARGENT)
			end
		end
	end)

	it("works with Braavos account type", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "braavos",
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result.transactionHash):toBeTruthy()

		-- Verify the Braavos-derived address was used
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(EXPECTED_ADDR_1_BRAAVOS)
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Account.new - explicit address
--------------------------------------------------------------------------------

describe("Account.new - explicit address", function()
	it("uses the provided address (not derived)", function()
		resetHandlers()
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local customAddress = "0xdeadbeef"

		local account = Account.new({
			address = customAddress,
			signer = signer,
			provider = provider,
		})

		expect(account.address):toBe(customAddress)
	end)

	it("can execute transactions with explicit address", function()
		resetHandlers()
		requestLog = {}
		local provider = createTestProvider()
		local signer = StarkSigner.new(PRIVKEY_1)
		local customAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

		local account = Account.new({
			address = customAddress,
			signer = signer,
			provider = provider,
		})

		local calls = createTestCalls()
		local result = account:execute(calls):expect()
		expect(result.transactionHash):toBeTruthy()

		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(customAddress)
			end
		end
	end)
end)
