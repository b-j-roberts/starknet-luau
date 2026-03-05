--!strict
local Account = require("../../src/wallet/Account")
local StarkSigner = require("../../src/signer/StarkSigner")
local MockPromise = require("../helpers/MockPromise")
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

-- OZ class hashes
local OZ_CLASS_HASH = TestUtils.OZ_CLASS_HASH
local OZ_CLASS_HASH_2 = TestUtils.OZ_CLASS_HASH_2

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

--------------------------------------------------------------------------------
-- Mock RPC layer (shared via TestUtils)
--------------------------------------------------------------------------------

local rpc = TestUtils.createMockRpcLayer()
local mockHandlers = rpc.mockHandlers
local requestLog = rpc.requestLog

local function createTestCalls(): { any }
	return TestUtils.createTestCalls()
end

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("derives correct address for privkey_2 with default OZ class hash", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_OZ)
	end)

	it("derives correct address for privkey_3 with default OZ class hash", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_OZ)
	end)

	it("uses custom class hash when provided", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			classHash = OZ_CLASS_HASH_2,
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ2)
	end)

	it("explicit accountType='oz' matches default", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "oz",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("errors when privateKey is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_ARGENT)
	end)

	it("derives correct Argent address for privkey_2", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_ARGENT)
	end)

	it("derives correct Argent address for privkey_3", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
			accountType = "argent",
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_ARGENT)
	end)

	it("derives correct Argent address with guardian", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
			guardian = "0xdeadbeef",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_ARGENT_GUARDIAN)
	end)

	it("Argent address differs from OZ address (same key)", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_1_BRAAVOS)
	end)

	it("derives correct Braavos address for privkey_2", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_2,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_2_BRAAVOS)
	end)

	it("derives correct Braavos address for privkey_3", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_3,
			provider = provider,
			accountType = "braavos",
		})
		expect(account.address):toBe(EXPECTED_ADDR_3_BRAAVOS)
	end)

	it("Braavos address differs from OZ and Argent addresses", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = provider,
				accountType = "unknown",
			})
		end):toThrow()
	end)

	it("errors on empty string accountType", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})
		expect(account:getPublicKeyHex()):toBe(PUBKEY_1)
	end)

	it("returns the correct public key for privkey_2", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
		})

		local result = account:getNonce():expect()
		expect(result):toBe("0x5")
	end)

	it("passes correct address to provider", function()
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()

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
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
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
		rpc.resetHandlers()
		rpc.clearRequestLog()
		local provider = rpc.createTestProvider()
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

--------------------------------------------------------------------------------
-- Paymaster helpers
--------------------------------------------------------------------------------

-- Transfer selector: starknet_keccak("transfer")
local TRANSFER_SELECTOR = "0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e"

-- Default paymaster typed data for testing (V2 style)
local function makePaymasterTypedData(outsideCalls: { { [string]: any } }?): { [string]: any }
	return {
		types = {
			StarknetDomain = {
				{ name = "name", type = "shortstring" },
				{ name = "version", type = "shortstring" },
				{ name = "chainId", type = "shortstring" },
				{ name = "revision", type = "shortstring" },
			},
			OutsideExecution = {
				{ name = "Caller", type = "ContractAddress" },
				{ name = "Nonce", type = "felt" },
				{ name = "Execute After", type = "u128" },
				{ name = "Execute Before", type = "u128" },
				{ name = "Calls", type = "Call*" },
			},
			Call = {
				{ name = "To", type = "ContractAddress" },
				{ name = "Selector", type = "selector" },
				{ name = "Calldata", type = "felt*" },
			},
		},
		primaryType = "OutsideExecution",
		domain = {
			name = "Account.execute_from_outside",
			version = "2",
			chainId = "SN_SEPOLIA",
			revision = "1",
		},
		message = {
			Caller = "0x414e595f43414c4c4552",
			Nonce = "0x1",
			["Execute After"] = "0x0",
			["Execute Before"] = "0xffffffffffffffff",
			Calls = outsideCalls or {},
		},
	}
end

-- Create a mock paymaster with configurable behavior
local function createMockPaymaster(overrides: { [string]: any }?): any
	local opts = overrides or {}
	local buildCalls: { { userAddress: string, calls: any, gasTokenAddress: string, options: any } } = {}
	local executeCalls: { { userAddress: string, typedData: any, signature: any, options: any } } = {}

	local paymaster = {}

	paymaster._buildCalls = buildCalls
	paymaster._executeCalls = executeCalls

	function paymaster:buildTypedData(
		userAddress: string,
		calls: { any },
		gasTokenAddress: string,
		options: any?
	): any
		table.insert(buildCalls, {
			userAddress = userAddress,
			calls = calls,
			gasTokenAddress = gasTokenAddress,
			options = options or {},
		})

		if opts.buildError then
			return MockPromise.reject(opts.buildError)
		end

		-- Convert submitted calls to outside call format (matching what a real paymaster returns)
		local outsideCalls: { { [string]: any } } = {}
		for _, call in calls do
			table.insert(outsideCalls, {
				To = call.contractAddress,
				Selector = TRANSFER_SELECTOR,
				Calldata = call.calldata or {},
			})
		end

		-- Allow overriding the returned calls (for validation tests)
		local returnedCalls = opts.returnedCalls or outsideCalls

		local typedData = opts.typedData or makePaymasterTypedData(returnedCalls)
		local feeEstimate = opts.feeEstimate or {
			gasTokenPrice = "0x3e8",
			estimatedFeeInStrk = "0x2710",
			estimatedFeeInGasToken = "0x9c40",
			suggestedMaxFeeInStrk = "0x3a98",
			suggestedMaxFeeInGasToken = "0xea60",
		}

		return MockPromise.resolve({
			typedData = typedData,
			feeEstimate = feeEstimate,
			deploymentData = nil,
		})
	end

	function paymaster:executeTransaction(userAddress: string, typedData: any, signature: { string }, options: any?): any
		table.insert(executeCalls, {
			userAddress = userAddress,
			typedData = typedData,
			signature = signature,
			options = options or {},
		})

		if opts.executeError then
			return MockPromise.reject(opts.executeError)
		end

		local result = opts.executeResult or {
			transactionHash = "0xpaymaster_tx_hash_abc",
			trackingId = "track-12345",
		}
		return MockPromise.resolve(result)
	end

	return paymaster
end

--------------------------------------------------------------------------------
-- Account:estimatePaymasterFee - validation
--------------------------------------------------------------------------------

describe("Account:estimatePaymasterFee - validation", function()
	it("rejects when paymaster is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		expect(function()
			account:estimatePaymasterFee(createTestCalls(), {
				feeMode = { mode = "sponsored" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
			})
		end):toThrow()
	end)

	it("rejects when feeMode.mode is 'default' but gasToken is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "default" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode.mode is invalid", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "invalid" },
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account:estimatePaymasterFee - sponsored mode
--------------------------------------------------------------------------------

describe("Account:estimatePaymasterFee - sponsored mode", function()
	it("returns fee estimate for sponsored mode", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.feeEstimate):toBeTruthy()
		expect(result.feeEstimate.estimatedFeeInStrk):toBe("0x2710")
	end)

	it("returns typed data alongside fee estimate", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.typedData):toBeTruthy()
		expect(result.typedData.primaryType):toBe("OutsideExecution")
	end)

	it("passes '0x0' as gasTokenAddress for sponsored mode", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(#paymaster._buildCalls):toBe(1)
		expect(paymaster._buildCalls[1].gasTokenAddress):toBe("0x0")
	end)

	it("passes correct user address to paymaster", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(paymaster._buildCalls[1].userAddress):toBe(EXPECTED_ADDR_1_OZ)
	end)
end)

--------------------------------------------------------------------------------
-- Account:estimatePaymasterFee - default/gasToken mode
--------------------------------------------------------------------------------

describe("Account:estimatePaymasterFee - gasToken mode", function()
	it("returns fee estimate for default/gasToken mode", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local tokenAddr = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		local result = account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "default", gasToken = tokenAddr },
			})
			:expect()

		expect(result.feeEstimate):toBeTruthy()
		expect(result.feeEstimate.estimatedFeeInGasToken):toBe("0x9c40")
	end)

	it("passes gasToken address to paymaster", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local tokenAddr = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
		account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "default", gasToken = tokenAddr },
			})
			:expect()

		expect(paymaster._buildCalls[1].gasTokenAddress):toBe(tokenAddr)
	end)
end)

--------------------------------------------------------------------------------
-- Account:estimatePaymasterFee - deployment data
--------------------------------------------------------------------------------

describe("Account:estimatePaymasterFee - deploymentData", function()
	it("passes deployment data when provided", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local deployData = {
			classHash = "0xclass123",
			calldata = { "0xpk" },
			salt = "0xsalt123",
		}
		account
			:estimatePaymasterFee(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
				deploymentData = deployData,
			})
			:expect()

		expect(paymaster._buildCalls[1].options.deploymentData):toBeTruthy()
		expect(paymaster._buildCalls[1].options.deploymentData.classHash):toBe("0xclass123")
	end)
end)

--------------------------------------------------------------------------------
-- Account:estimatePaymasterFee - error propagation
--------------------------------------------------------------------------------

describe("Account:estimatePaymasterFee - error propagation", function()
	it("propagates buildTypedData errors", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster({
			buildError = "paymaster unavailable",
		})

		local ok, err = pcall(function()
			account
				:estimatePaymasterFee(createTestCalls(), {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "paymaster unavailable", 1, true) ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - validation
--------------------------------------------------------------------------------

describe("Account:executePaymaster - validation", function()
	it("rejects when paymaster is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		expect(function()
			account:executePaymaster(createTestCalls(), {
				feeMode = { mode = "sponsored" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
			})
		end):toThrow()
	end)

	it("rejects when calls is empty", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:executePaymaster({}, {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode.mode is 'default' but gasToken is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "default" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode.mode is invalid", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "bogus" },
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - full flow (sponsored)
--------------------------------------------------------------------------------

describe("Account:executePaymaster - sponsored mode", function()
	it("full flow: buildTypedData -> validate -> sign -> execute", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
		expect(result.trackingId):toBe("track-12345")
	end)

	it("passes '0x0' as gasTokenAddress for sponsored mode", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(paymaster._buildCalls[1].gasTokenAddress):toBe("0x0")
	end)

	it("passes correct user address to paymaster", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(paymaster._buildCalls[1].userAddress):toBe(EXPECTED_ADDR_1_OZ)
		expect(paymaster._executeCalls[1].userAddress):toBe(EXPECTED_ADDR_1_OZ)
	end)

	it("signs typed data with account signer", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		-- Verify signature was passed to executeTransaction
		local sig = paymaster._executeCalls[1].signature
		expect(sig):toBeTruthy()
		expect(#sig):toBe(2)
		expect(string.sub(sig[1], 1, 2)):toBe("0x")
		expect(string.sub(sig[2], 1, 2)):toBe("0x")
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - gasToken mode
--------------------------------------------------------------------------------

describe("Account:executePaymaster - gasToken mode", function()
	it("full flow with gasToken mode", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local tokenAddr = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		local result = account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "default", gasToken = tokenAddr },
			})
			:expect()

		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
		expect(paymaster._buildCalls[1].gasTokenAddress):toBe(tokenAddr)
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - deployment data
--------------------------------------------------------------------------------

describe("Account:executePaymaster - deploymentData", function()
	it("passes deployment data for deploy-via-paymaster", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local deployData = {
			classHash = "0xclass456",
			calldata = { "0xpubkey" },
			salt = "0xsalt456",
		}
		account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
				deploymentData = deployData,
			})
			:expect()

		expect(paymaster._buildCalls[1].options.deploymentData.classHash):toBe("0xclass456")
		expect(paymaster._executeCalls[1].options.deploymentData.classHash):toBe("0xclass456")
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - call validation
--------------------------------------------------------------------------------

describe("Account:executePaymaster - call validation", function()
	it("succeeds when returned calls match submitted calls", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		-- Default mock returns matching calls
		local paymaster = createMockPaymaster()

		local result = account
			:executePaymaster(createTestCalls(), {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBeTruthy()
	end)

	it("succeeds when returned calls = submitted + 1 appended fee transfer", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- The paymaster returns the submitted call + an extra fee transfer call
		local calls = createTestCalls()
		local returnedCalls = {
			{
				To = calls[1].contractAddress,
				Selector = TRANSFER_SELECTOR,
				Calldata = calls[1].calldata,
			},
			{
				To = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				Selector = TRANSFER_SELECTOR,
				Calldata = { "0xfee_receiver", "0x100", "0x0" },
			},
		}

		local paymaster = createMockPaymaster({ returnedCalls = returnedCalls })

		local result = account
			:executePaymaster(calls, {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBeTruthy()
	end)

	it("rejects when returned calls don't match submitted calls", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- Paymaster returns a completely different call
		local returnedCalls = {
			{
				To = "0xmalicious_contract",
				Selector = "0xmalicious_selector",
				Calldata = { "0xsteal_funds" },
			},
		}

		local paymaster = createMockPaymaster({ returnedCalls = returnedCalls })

		local ok, err = pcall(function()
			account
				:executePaymaster(createTestCalls(), {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "do not match submitted calls", 1, true) ~= nil):toBe(true)
	end)

	it("rejects when returned calls have modified calldata", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		local calls = createTestCalls()
		-- Same To/Selector but different calldata
		local returnedCalls = {
			{
				To = calls[1].contractAddress,
				Selector = TRANSFER_SELECTOR,
				Calldata = { "0xdifferent_recipient", "0x999999", "0x0" },
			},
		}

		local paymaster = createMockPaymaster({ returnedCalls = returnedCalls })

		local ok, err = pcall(function()
			account
				:executePaymaster(calls, {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "do not match submitted calls", 1, true) ~= nil):toBe(true)
	end)

	it("rejects when paymaster drops a submitted call", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- Paymaster returns empty calls
		local paymaster = createMockPaymaster({ returnedCalls = {} })

		local ok, _ = pcall(function()
			account
				:executePaymaster(createTestCalls(), {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - error propagation
--------------------------------------------------------------------------------

describe("Account:executePaymaster - error propagation", function()
	it("propagates buildTypedData errors", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster({
			buildError = "paymaster service unavailable",
		})

		local ok, err = pcall(function()
			account
				:executePaymaster(createTestCalls(), {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "paymaster service unavailable", 1, true) ~= nil):toBe(true)
	end)

	it("propagates executeTransaction errors", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster({
			executeError = "execution failed on paymaster",
		})

		local ok, err = pcall(function()
			account
				:executePaymaster(createTestCalls(), {
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(err), "execution failed on paymaster", 1, true) ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - integration with AvnuPaymaster interface
--------------------------------------------------------------------------------

describe("Account:executePaymaster - interface compatibility", function()
	it("works with any paymaster implementing buildTypedData + executeTransaction", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- Another mock that mimics AvnuPaymaster (same interface)
		local avnuLikePaymaster = createMockPaymaster({
			executeResult = {
				transactionHash = "0xavnu_hash_123",
				trackingId = "avnu-track-001",
			},
		})

		local result = account
			:executePaymaster(createTestCalls(), {
				paymaster = avnuLikePaymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBe("0xavnu_hash_123")
		expect(result.trackingId):toBe("avnu-track-001")
	end)
end)

--------------------------------------------------------------------------------
-- Account:executePaymaster - multiple calls
--------------------------------------------------------------------------------

describe("Account:executePaymaster - multiple calls", function()
	it("handles multiple calls in a batch", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local calls = {
			{
				contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				entrypoint = "transfer",
				calldata = { "0xrecipient1", "0x100", "0x0" },
			},
			{
				contractAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
				entrypoint = "transfer",
				calldata = { "0xrecipient2", "0x200", "0x0" },
			},
		}

		local result = account
			:executePaymaster(calls, {
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBeTruthy()
		expect(#paymaster._buildCalls[1].calls):toBe(2)
	end)
end)

--------------------------------------------------------------------------------
-- Account:getDeploymentData
--------------------------------------------------------------------------------

describe("Account:getDeploymentData", function()
	it("returns correct deployment data for OZ account", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		local dd = account:getDeploymentData()
		expect(dd.classHash):toBe(OZ_CLASS_HASH)
		expect(dd.salt):toBe(PUBKEY_1)
		expect(dd.calldata[1]):toBe(PUBKEY_1)
		expect(#dd.calldata):toBe(1)
		expect(dd.unique):toBe(false)
		expect(dd.version):toBe(1)
	end)

	it("returns correct deployment data for Argent account", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})

		local dd = account:getDeploymentData()
		expect(dd.classHash):toBe(Account.ARGENT_CLASS_HASH)
		expect(dd.salt):toBe(PUBKEY_1)
		-- Argent calldata: [0, publicKey, 0] (no guardian)
		expect(#dd.calldata):toBe(3)
		expect(dd.calldata[1]):toBe("0x0")
		expect(dd.calldata[2]):toBe(PUBKEY_1)
		expect(dd.calldata[3]):toBe("0x0")
	end)

	it("returns correct deployment data for Argent account with guardian", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
			guardian = "0xguardian123",
		})

		local dd = account:getDeploymentData()
		-- Argent calldata with guardian: [0, publicKey, 1, 0, guardianKey]
		expect(#dd.calldata):toBe(5)
		expect(dd.calldata[1]):toBe("0x0")
		expect(dd.calldata[2]):toBe(PUBKEY_1)
		expect(dd.calldata[3]):toBe("0x1")
		expect(dd.calldata[4]):toBe("0x0")
		expect(dd.calldata[5]):toBe("0xguardian123")
	end)

	it("returns correct deployment data for Braavos account", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "braavos",
		})

		local dd = account:getDeploymentData()
		expect(dd.classHash):toBe(Account.BRAAVOS_BASE_CLASS_HASH)
		expect(dd.salt):toBe(PUBKEY_1)
		expect(dd.calldata[1]):toBe(PUBKEY_1)
		expect(#dd.calldata):toBe(1)
	end)

	it("uses custom classHash when provided", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local customClassHash = "0xcustom_class_hash_abc123"
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			classHash = customClassHash,
		})

		local dd = account:getDeploymentData()
		expect(dd.classHash):toBe(customClassHash)
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - validation
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - validation", function()
	it("rejects when paymaster is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		expect(function()
			account:deployWithPaymaster({
				feeMode = { mode = "sponsored" },
			})
		end):toThrow()
	end)

	it("rejects when feeMode is missing", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:deployWithPaymaster({
				paymaster = paymaster,
			})
		end):toThrow()
	end)

	it("rejects when feeMode.mode is invalid", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "invalid" },
			})
		end):toThrow()
	end)

	it("rejects when default mode is missing gasToken", function()
		rpc.resetHandlers()
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		expect(function()
			account:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "default" },
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - idempotency
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - idempotency", function()
	it("returns alreadyDeployed when getNonce succeeds", function()
		rpc.resetHandlers()
		-- Default mock returns nonce successfully (account exists)
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.alreadyDeployed):toBe(true)
		expect(result.transactionHash):toBe("0x0")
		expect(result.contractAddress):toBe(account.address)
		-- Paymaster should NOT have been called
		expect(#paymaster._buildCalls):toBe(0)
		expect(#paymaster._executeCalls):toBe(0)
	end)

	it("proceeds with deployment when getNonce fails (undeployed account)", function()
		rpc.resetHandlers()
		-- Override getNonce to fail (account not deployed)
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.alreadyDeployed):toBe(nil)
		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
		expect(result.contractAddress):toBe(account.address)
		expect(result.trackingId):toBe("track-12345")
		-- Paymaster should have been called
		expect(#paymaster._buildCalls):toBe(1)
		expect(#paymaster._executeCalls):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - sponsored mode (no calls)
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - sponsored mode (deploy only)", function()
	it("deploys with correct deploymentData and zero gas token", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		-- Verify buildTypedData was called with correct params
		local buildCall = paymaster._buildCalls[1]
		expect(buildCall.userAddress):toBe(account.address)
		expect(buildCall.gasTokenAddress):toBe("0x0") -- sponsored mode
		expect(#buildCall.calls):toBe(0) -- no user calls

		-- Verify deploymentData was passed
		local dd = buildCall.options.deploymentData
		expect(dd):toBeTruthy()
		expect(dd.classHash):toBe(OZ_CLASS_HASH)
		expect(dd.salt):toBe(PUBKEY_1)
		expect(dd.calldata[1]):toBe(PUBKEY_1)
		expect(dd.unique):toBe(false)
		expect(dd.version):toBe(1)

		-- Verify executeTransaction also received deploymentData
		local execCall = paymaster._executeCalls[1]
		expect(execCall.options.deploymentData):toBeTruthy()
		expect(execCall.options.deploymentData.classHash):toBe(OZ_CLASS_HASH)

		-- Verify result
		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
		expect(result.contractAddress):toBe(account.address)
		expect(result.trackingId):toBe("track-12345")
	end)

	it("signs the typed data from the paymaster", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		-- Verify signature was passed to executeTransaction
		local execCall = paymaster._executeCalls[1]
		expect(execCall.signature):toBeTruthy()
		expect(#execCall.signature):toBe(2) -- [r, s]
		expect(type(execCall.signature[1])):toBe("string")
		expect(type(execCall.signature[2])):toBe("string")
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - default/gasToken mode
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - default mode", function()
	it("deploys with specified gas token", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local gasToken = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "default", gasToken = gasToken },
			})
			:expect()

		local buildCall = paymaster._buildCalls[1]
		expect(buildCall.gasTokenAddress):toBe(gasToken)
		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - combined deploy + initial calls
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - combined deploy + calls", function()
	it("bundles initial calls with deployment in a single atomic call", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local calls = createTestCalls()
		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			}, {
				calls = calls,
			})
			:expect()

		-- Verify calls were passed to buildTypedData
		local buildCall = paymaster._buildCalls[1]
		expect(#buildCall.calls):toBe(1)
		expect(buildCall.calls[1].entrypoint):toBe("transfer")

		-- Verify deploymentData was also passed
		expect(buildCall.options.deploymentData):toBeTruthy()

		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
	end)

	it("validates returned calls match submitted calls", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- Create paymaster that returns mismatched calls
		local paymaster = createMockPaymaster({
			returnedCalls = {
				{
					To = "0xmalicious_contract",
					Selector = TRANSFER_SELECTOR,
					Calldata = { "0xattacker", "0x999999", "0x0" },
				},
			},
		})

		local calls = createTestCalls()
		local ok, err = pcall(function()
			return account
				:deployWithPaymaster({
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				}, {
					calls = calls,
				})
				:expect()
		end)

		expect(ok):toBe(false)
		-- Should contain validation failure message
		expect(string.find(tostring(err), "do not match", 1, true) ~= nil):toBe(true)
	end)

	it("skips call validation when no calls are provided", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })

		-- Even with returnedCalls set, deploy-only should succeed (no validation)
		local paymaster = createMockPaymaster({
			returnedCalls = {
				{
					To = "0xsome_contract",
					Selector = TRANSFER_SELECTOR,
					Calldata = {},
				},
			},
		})

		-- No calls → no validation needed
		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(result.transactionHash):toBe("0xpaymaster_tx_hash_abc")
	end)

	it("handles multiple initial calls", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local calls = {
			{
				contractAddress = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
				entrypoint = "transfer",
				calldata = { "0xrecipient1", "0x100", "0x0" },
			},
			{
				contractAddress = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
				entrypoint = "transfer",
				calldata = { "0xrecipient2", "0x200", "0x0" },
			},
		}

		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			}, {
				calls = calls,
			})
			:expect()

		expect(#paymaster._buildCalls[1].calls):toBe(2)
		expect(result.transactionHash):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - waitForConfirmation
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - waitForConfirmation", function()
	it("waits for confirmation when requested", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end

		local waitCalled = false
		local originalHandler = mockHandlers["starknet_getTransactionStatus"]
		mockHandlers["starknet_getTransactionStatus"] = function(params)
			waitCalled = true
			return originalHandler(params)
		end

		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local result = account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			}, {
				waitForConfirmation = true,
			})
			:expect()

		expect(result.transactionHash):toBeTruthy()
		expect(waitCalled):toBe(true)
	end)

	it("does not wait for confirmation by default", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end

		local waitCalled = false
		local originalHandler = mockHandlers["starknet_getTransactionStatus"]
		mockHandlers["starknet_getTransactionStatus"] = function(params)
			waitCalled = true
			return originalHandler(params)
		end

		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		expect(waitCalled):toBe(false)
	end)

	it("rejects when waitForTransaction fails", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		mockHandlers["starknet_getTransactionStatus"] = function(_params)
			return {
				finality_status = "REJECTED",
				execution_status = "REVERTED",
			}
		end

		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		local ok, _err = pcall(function()
			return account
				:deployWithPaymaster({
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				}, {
					waitForConfirmation = true,
				})
				:expect()
		end)

		expect(ok):toBe(false)
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - error propagation
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - error propagation", function()
	it("propagates buildTypedData errors", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster({ buildError = "paymaster build failed" })

		local ok, err = pcall(function()
			return account
				:deployWithPaymaster({
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)

		expect(ok):toBe(false)
		expect(string.find(tostring(err), "paymaster build failed", 1, true) ~= nil):toBe(true)
	end)

	it("propagates executeTransaction errors", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster({ executeError = "paymaster execute failed" })

		local ok, err = pcall(function()
			return account
				:deployWithPaymaster({
					paymaster = paymaster,
					feeMode = { mode = "sponsored" },
				})
				:expect()
		end)

		expect(ok):toBe(false)
		expect(string.find(tostring(err), "paymaster execute failed", 1, true) ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - Argent account type
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - Argent account", function()
	it("passes correct Argent deploymentData", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({
			privateKey = PRIVKEY_1,
			provider = provider,
			accountType = "argent",
		})
		local paymaster = createMockPaymaster()

		account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		local dd = paymaster._buildCalls[1].options.deploymentData
		expect(dd.classHash):toBe(Account.ARGENT_CLASS_HASH)
		expect(#dd.calldata):toBe(3)
		expect(dd.calldata[1]):toBe("0x0")
		expect(dd.calldata[2]):toBe(PUBKEY_1)
		expect(dd.calldata[3]):toBe("0x0")
	end)
end)

--------------------------------------------------------------------------------
-- Account:deployWithPaymaster - integration with SponsoredExecutor
--------------------------------------------------------------------------------

describe("Account:deployWithPaymaster - getDeploymentData integration", function()
	it("getDeploymentData output matches what deployWithPaymaster sends", function()
		rpc.resetHandlers()
		mockHandlers["starknet_getNonce"] = function(_params)
			error("Contract not found")
		end
		local provider = rpc.createTestProvider()
		local account = Account.fromPrivateKey({ privateKey = PRIVKEY_1, provider = provider })
		local paymaster = createMockPaymaster()

		-- Get deployment data directly
		local dd = account:getDeploymentData()

		-- Deploy via paymaster
		account
			:deployWithPaymaster({
				paymaster = paymaster,
				feeMode = { mode = "sponsored" },
			})
			:expect()

		-- Verify they match
		local sentDd = paymaster._buildCalls[1].options.deploymentData
		expect(sentDd.classHash):toBe(dd.classHash)
		expect(sentDd.salt):toBe(dd.salt)
		expect(sentDd.unique):toBe(dd.unique)
		expect(sentDd.version):toBe(dd.version)
		expect(#sentDd.calldata):toBe(#dd.calldata)
		for i, v in dd.calldata do
			expect(sentDd.calldata[i]):toBe(v)
		end
	end)
end)
