--!strict
local Constants = require("../src/constants")

--------------------------------------------------------------------------------
-- Chain ID tests
--------------------------------------------------------------------------------

describe("Constants - Chain IDs", function()
	it("SN_MAIN is ASCII encoding of 'SN_MAIN'", function()
		expect(Constants.SN_MAIN):toBe("0x534e5f4d41494e")
	end)

	it("SN_SEPOLIA is ASCII encoding of 'SN_SEPOLIA'", function()
		expect(Constants.SN_SEPOLIA):toBe("0x534e5f5345504f4c4941")
	end)
end)

--------------------------------------------------------------------------------
-- Class hash tests
--------------------------------------------------------------------------------

describe("Constants - Class Hashes", function()
	it("OZ_ACCOUNT_CLASS_HASH matches known OpenZeppelin Cairo 1 class hash", function()
		expect(Constants.OZ_ACCOUNT_CLASS_HASH):toBe(
			"0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"
		)
	end)
end)

--------------------------------------------------------------------------------
-- Contract address prefix
--------------------------------------------------------------------------------

describe("Constants - Contract Address Prefix", function()
	it("CONTRACT_ADDRESS_PREFIX is ASCII encoding of 'STARKNET_CONTRACT_ADDRESS'", function()
		expect(Constants.CONTRACT_ADDRESS_PREFIX):toBe(
			"0x535441524b4e45545f434f4e54524143545f41444452455353"
		)
	end)
end)

--------------------------------------------------------------------------------
-- Token address tests
--------------------------------------------------------------------------------

describe("Constants - Token Addresses", function()
	it("ETH_TOKEN_ADDRESS matches well-known Starknet ETH address", function()
		expect(Constants.ETH_TOKEN_ADDRESS):toBe(
			"0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		)
	end)

	it("STRK_TOKEN_ADDRESS matches well-known Starknet STRK address", function()
		expect(Constants.STRK_TOKEN_ADDRESS):toBe(
			"0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
		)
	end)
end)

--------------------------------------------------------------------------------
-- Transaction version tests
--------------------------------------------------------------------------------

describe("Constants - Transaction Versions", function()
	it("INVOKE_TX_V3 is 0x3", function()
		expect(Constants.INVOKE_TX_V3):toBe("0x3")
	end)

	it("DEPLOY_ACCOUNT_TX_V3 is 0x3", function()
		expect(Constants.DEPLOY_ACCOUNT_TX_V3):toBe("0x3")
	end)

	it("DECLARE_TX_V3 is 0x3", function()
		expect(Constants.DECLARE_TX_V3):toBe("0x3")
	end)
end)

--------------------------------------------------------------------------------
-- Completeness test
--------------------------------------------------------------------------------

describe("Constants - Module Completeness", function()
	it("exports all expected fields", function()
		-- Chain IDs
		expect(Constants.SN_MAIN ~= nil):toBe(true)
		expect(Constants.SN_SEPOLIA ~= nil):toBe(true)
		-- Class hashes
		expect(Constants.OZ_ACCOUNT_CLASS_HASH ~= nil):toBe(true)
		-- Prefix
		expect(Constants.CONTRACT_ADDRESS_PREFIX ~= nil):toBe(true)
		-- Token addresses
		expect(Constants.ETH_TOKEN_ADDRESS ~= nil):toBe(true)
		expect(Constants.STRK_TOKEN_ADDRESS ~= nil):toBe(true)
		-- Transaction versions
		expect(Constants.INVOKE_TX_V3 ~= nil):toBe(true)
		expect(Constants.DEPLOY_ACCOUNT_TX_V3 ~= nil):toBe(true)
		expect(Constants.DECLARE_TX_V3 ~= nil):toBe(true)
	end)
end)
