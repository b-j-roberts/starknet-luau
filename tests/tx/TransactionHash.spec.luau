--!strict
local TransactionHash = require("../../src/tx/TransactionHash")
local Constants = require("../../src/constants")

-- Default zero resource bounds for convenience
local ZERO_BOUNDS: TransactionHash.ResourceBounds = {
	l1Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
	l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
	l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
}

--------------------------------------------------------------------------------
-- Resource bound encoding
--------------------------------------------------------------------------------

describe("TransactionHash - encodeResourceBound", function()
	it("encodes L1_GAS with max_amount and max_price", function()
		-- L1_GAS name = 0x4c315f474153, max_amount = 0x7c9, max_price = 0x1
		local result = TransactionHash._encodeResourceBound("0x4c315f474153", "0x7c9", "0x1")
		expect(result):toBe("0x4c315f47415300000000000007c900000000000000000000000000000001")
	end)

	it("encodes L2_GAS with zero bounds", function()
		local result = TransactionHash._encodeResourceBound("0x4c325f474153", "0x0", "0x0")
		expect(result):toBe("0x4c325f474153000000000000000000000000000000000000000000000000")
	end)

	it("encodes L1_DATA with zero bounds", function()
		local result = TransactionHash._encodeResourceBound("0x4c315f44415441", "0x0", "0x0")
		expect(result):toBe("0x4c315f44415441000000000000000000000000000000000000000000000000")
	end)

	it("encodes L1_GAS with realistic Sepolia values", function()
		-- max_amount = 0x186a0, max_price = 0x5af3107a4000
		local result = TransactionHash._encodeResourceBound("0x4c315f474153", "0x186a0", "0x5af3107a4000")
		expect(result):toBe("0x4c315f47415300000000000186a0000000000000000000005af3107a4000")
	end)

	it("encodes L2_GAS with non-zero values", function()
		-- max_amount = 0x1388, max_price = 0x3b9aca00
		local result = TransactionHash._encodeResourceBound("0x4c325f474153", "0x1388", "0x3b9aca00")
		expect(result):toBe("0x4c325f47415300000000000013880000000000000000000000003b9aca00")
	end)

	it("encodes L1_DATA with non-zero values", function()
		-- max_amount = 0x64, max_price = 0x5f5e100
		local result = TransactionHash._encodeResourceBound("0x4c315f44415441", "0x64", "0x5f5e100")
		expect(result):toBe("0x4c315f44415441000000000000006400000000000000000000000005f5e100")
	end)
end)

--------------------------------------------------------------------------------
-- DA mode encoding
--------------------------------------------------------------------------------

describe("TransactionHash - hashDAMode", function()
	it("L1/L1 mode returns 0x0", function()
		local result = TransactionHash.hashDAMode(0, 0)
		expect(result):toBe("0x0")
	end)

	it("L1/L2 mode returns 0x1", function()
		local result = TransactionHash.hashDAMode(0, 1)
		expect(result):toBe("0x1")
	end)

	it("L2/L1 mode returns 0x100000000", function()
		local result = TransactionHash.hashDAMode(1, 0)
		expect(result):toBe("0x100000000")
	end)

	it("L2/L2 mode returns 0x100000001", function()
		local result = TransactionHash.hashDAMode(1, 1)
		expect(result):toBe("0x100000001")
	end)
end)

--------------------------------------------------------------------------------
-- Fee field hash
--------------------------------------------------------------------------------

describe("TransactionHash - hashFeeField", function()
	it("hashes fee field with l1_gas bounds (test vector 1)", function()
		local bounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x7c9", maxPricePerUnit = "0x1" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}
		local result = TransactionHash.hashFeeField("0x0", bounds)
		expect(result):toBe("0x71c27bf166cee2a086fa06601d8ae6a0fcd62e814685edccbb5699d6674cd71")
	end)

	it("hashes fee field with Sepolia bounds (test vector 2)", function()
		local bounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
			l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		}
		local result = TransactionHash.hashFeeField("0x0", bounds)
		expect(result):toBe("0x2bcec8ea072f16785d1e183204a1db2758994b95f7382acaea68fb54af31c5e")
	end)

	it("hashes fee field with non-zero tip and all bounds (test vector 4)", function()
		local bounds: TransactionHash.ResourceBounds = {
			l1Gas = { maxAmount = "0x2710", maxPricePerUnit = "0x174876e800" },
			l2Gas = { maxAmount = "0x1388", maxPricePerUnit = "0x3b9aca00" },
			l1DataGas = { maxAmount = "0x64", maxPricePerUnit = "0x5f5e100" },
		}
		local result = TransactionHash.hashFeeField("0x123", bounds)
		expect(result):toBe("0x3f8de8d026434ccb2f0d34918bbb507bef2a0a3d0d70426aa72a13f8b7dd3fa")
	end)

	it("hashes fee field with all-zero bounds", function()
		local result = TransactionHash.hashFeeField("0x0", ZERO_BOUNDS)
		-- Fee field hash with zero tip and zero bounds should be deterministic
		local result2 = TransactionHash.hashFeeField("0x0", ZERO_BOUNDS)
		expect(result):toBe(result2)
	end)
end)

--------------------------------------------------------------------------------
-- Chain ID constants
--------------------------------------------------------------------------------

describe("Constants - chain ID constants", function()
	it("SN_MAIN is correct ASCII encoding", function()
		expect(Constants.SN_MAIN):toBe("0x534e5f4d41494e")
	end)

	it("SN_SEPOLIA is correct ASCII encoding", function()
		expect(Constants.SN_SEPOLIA):toBe("0x534e5f5345504f4c4941")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 1: Simple demo
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (simple demo)", function()
	it("matches expected hash for simple invoke", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x12fd538",
			compiledCalldata = { "0x11", "0x26" },
			chainId = "0x31",
			nonce = "0x9",
			resourceBounds = {
				l1Gas = { maxAmount = "0x7c9", maxPricePerUnit = "0x1" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x713c8f6b968aa65dfd450eaf29511809bd08d10e1d24dea890916edf207f395")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 2: Sepolia multicall
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (Sepolia multicall)", function()
	it("matches expected hash for 16-element calldata", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x3f6f3bc663aedc5285d6013cc3ffcbc4341d86ab488b8b68d297f8258793c41",
			compiledCalldata = {
				"0x2",
				"0x4c312760dfd17a954cdd09e76aa9f149f806d88ec3e402ffaf5c4926f568a42",
				"0x31aafc75f498fdfa7528880ad27246b4c15af4954f96228c9a132b328de1c92",
				"0x0",
				"0x6",
				"0x450703c32370cf7ffff540b9352e7ee4ad583af143a361155f2b485c0c39684",
				"0xb17d8a2731ba7ca1816631e6be14f0fc1b8390422d649fa27f0fbb0c91eea8",
				"0x6",
				"0x0",
				"0x6",
				"0x6333f10b24ed58cc33e9bac40b0d52e067e32a175a97ca9e2ce89fe2b002d82",
				"0x3",
				"0x602e89fe5703e5b093d13d0a81c9e6d213338dc15c59f4d3ff3542d1d7dfb7d",
				"0x20d621301bea11ffd9108af1d65847e9049412159294d0883585d4ad43ad61b",
				"0x276faadb842bfcbba834f3af948386a2eb694f7006e118ad6c80305791d3247",
				"0x613816405e6334ab420e53d4b38a0451cb2ebca2755171315958c87d303cf6",
			},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x8a9",
			resourceBounds = {
				l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x6b68ec8759c56f2d9a4f7355019c0ba1450ca026dc61d0506dbad1d0f8070e5")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 3: Minimal (empty calldata)
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (minimal)", function()
	it("matches expected hash for empty calldata", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(hash):toBe("0x81c846c1ddc1e68c081a731132dbd6748081423a8cb7ed698e61f9dbe3bd66")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 4: Non-zero tip, all gas types
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (tip + all gas types)", function()
	it("matches expected hash with tip and all resource bounds", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0xabc123",
			compiledCalldata = { "0x1", "0x2", "0x3" },
			chainId = "0x534e5f4d41494e",
			nonce = "0x2a",
			tip = "0x123",
			resourceBounds = {
				l1Gas = { maxAmount = "0x2710", maxPricePerUnit = "0x174876e800" },
				l2Gas = { maxAmount = "0x1388", maxPricePerUnit = "0x3b9aca00" },
				l1DataGas = { maxAmount = "0x64", maxPricePerUnit = "0x5f5e100" },
			},
		})
		expect(hash):toBe("0x7eb1aea92dfdbad0e03246c3dade1b21b21e348ca66c6aa09bdc8d1cbad8c08")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 5: Paymaster + deploy data
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (paymaster + deploy data)", function()
	it("matches expected hash with paymaster and account deployment data", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x12fd538",
			compiledCalldata = { "0x42", "0x43" },
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x1",
			paymasterData = { "0xaaa", "0xbbb" },
			accountDeploymentData = { "0xdead", "0xbeef" },
			resourceBounds = {
				l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x5ac1bb61673b66a1f3faf2f101ac157c5a72fef6a097de4e59d51f5fb2c5257")
	end)
end)

--------------------------------------------------------------------------------
-- calculateInvokeTransactionHash - Test Vector 6: L2 DA mode
--------------------------------------------------------------------------------

describe("TransactionHash - V3 INVOKE hash (L2 DA mode)", function()
	it("matches expected hash with L2 data availability", function()
		local hash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x12fd538",
			compiledCalldata = { "0x1" },
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			nonceDataAvailabilityMode = 1,
			feeDataAvailabilityMode = 1,
			resourceBounds = ZERO_BOUNDS,
		})
		expect(hash):toBe("0x6e126cf89d494a93eb29761aa558df6524e9a1a4bcf084f96c53766707aec5d")
	end)
end)

--------------------------------------------------------------------------------
-- Default parameter handling
--------------------------------------------------------------------------------

describe("TransactionHash - default parameters", function()
	it("uses version 0x3 by default", function()
		-- Same inputs, explicit vs implicit version
		local explicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			version = "0x3",
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses tip 0x0 by default", function()
		local explicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			tip = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses L1 DA mode by default", function()
		local explicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			nonceDataAvailabilityMode = 0,
			feeDataAvailabilityMode = 0,
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses empty paymaster data by default", function()
		local explicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			paymasterData = {},
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses empty account deployment data by default", function()
		local explicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			accountDeploymentData = {},
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)
end)

--------------------------------------------------------------------------------
-- Different versions produce different hashes
--------------------------------------------------------------------------------

describe("TransactionHash - version sensitivity", function()
	it("V3 and F3 produce different hashes", function()
		local base = {
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		}
		local v3Hash = TransactionHash.calculateInvokeTransactionHash(base)

		-- F3 = fee estimation version
		base.version = "0x100000000000000000000000000000003"
		local f3Hash = TransactionHash.calculateInvokeTransactionHash(base)

		expect(v3Hash ~= f3Hash):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 1: Minimal
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (minimal)", function()
	it("matches expected hash for minimal deploy", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(hash):toBe("0x62211985366cf450239fdec126d1b5729a6f140e20b757ebcb04651deab7a85")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 2: OZ account on Sepolia
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (OZ Sepolia)", function()
	it("matches expected hash for OZ account deployment", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
			constructorCalldata = { "0x5cd65f3d7daea6c63939d659b8473ea0c5cd81576035a4d34e52fb06840196c" },
			contractAddress = "0x2fab82e4aef1d8664874e1f194951856d48463c3e6bf9a8c68e234a629a6f50",
			salt = "0x5cd65f3d7daea6c63939d659b8473ea0c5cd81576035a4d34e52fb06840196c",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x544e9d636e1a8e663064a77da86a377d05aad6c1776477ea10353de01ed9e1d")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 3: Multi-arg constructor
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (multi-arg constructor)", function()
	it("matches expected hash for multi-arg constructor calldata", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x65bcf29c898ff912fa2bdd4c6cd94b9142da0399127601ef35dfc9babc7a691",
			constructorCalldata = { "0x21b", "0x151" },
			contractAddress = "0x219bea54dc352c0d6853de34019644758620fa6298c4608829228c3f5f8db33",
			salt = "0x12fd537",
			chainId = "0x32",
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x7c9", maxPricePerUnit = "0x1" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x3aa44d769a27ab568d71e8f25a7b0f7fe004d35da589175528c066a631b12c4")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 4: Paymaster data
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (paymaster data)", function()
	it("matches expected hash with paymaster data on mainnet", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
			constructorCalldata = { "0x33434ad846cdd5f23eb73ff09fe6fddd568284a0fb7d1be20ee482f044dabe2" },
			contractAddress = "0x6b86e40118f29ebe393a75469b4d926c7a44c2e2681b6d319520b7c1156d114",
			salt = "0x33434ad846cdd5f23eb73ff09fe6fddd568284a0fb7d1be20ee482f044dabe2",
			chainId = "0x534e5f4d41494e",
			nonce = "0x0",
			paymasterData = { "0xdead", "0xbeef" },
			resourceBounds = {
				l1Gas = { maxAmount = "0x2710", maxPricePerUnit = "0x174876e800" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x2dd5cec3d2c0d4f433eb77d90e01709d8185abe223b735b226f14d6749ae493")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 5: Tip + L2 gas
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (tip + L2 gas)", function()
	it("matches expected hash with non-zero tip and L2 gas bounds", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0xdeadbeefdeadbeefdeadbeefdeadbeef",
			constructorCalldata = {},
			contractAddress = "0x1234567890abcdef1234567890abcdef12345678",
			salt = "0xabc",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x1",
			tip = "0x5",
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x3e8" },
				l2Gas = { maxAmount = "0x200", maxPricePerUnit = "0x1f4" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(hash):toBe("0x3f4a88286d111ecf280334aed5c794faebac755d13321d80fb1f4a1cdb5fe41")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Test Vector 6: L2 DA mode
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash (L2 DA mode)", function()
	it("matches expected hash with L2 data availability", function()
		local hash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = { "0x1" },
			contractAddress = "0x12fd538",
			salt = "0x1",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			nonceDataAvailabilityMode = 1,
			feeDataAvailabilityMode = 1,
			resourceBounds = ZERO_BOUNDS,
		})
		expect(hash):toBe("0x3648c77dc2d3134fa2562f3fa0b2505a0bb7cb541c71fc8dd84693c0eaa165a")
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Determinism
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash determinism", function()
	it("produces the same hash for the same inputs", function()
		local params = {
			classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
			constructorCalldata = { "0x5cd65f3d7daea6c63939d659b8473ea0c5cd81576035a4d34e52fb06840196c" },
			contractAddress = "0x2fab82e4aef1d8664874e1f194951856d48463c3e6bf9a8c68e234a629a6f50",
			salt = "0x5cd65f3d7daea6c63939d659b8473ea0c5cd81576035a4d34e52fb06840196c",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = {
				l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		}
		local hash1 = TransactionHash.calculateDeployAccountTransactionHash(params)
		local hash2 = TransactionHash.calculateDeployAccountTransactionHash(params)
		expect(hash1):toBe(hash2)
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Field sensitivity
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash field sensitivity", function()
	local baseParams = {
		classHash = "0x1",
		constructorCalldata = { "0x1" },
		contractAddress = "0x1",
		salt = "0x1",
		chainId = "0x534e5f5345504f4c4941",
		nonce = "0x0",
		resourceBounds = ZERO_BOUNDS,
	}

	local function withOverride(overrides: { [string]: any }): string
		local params: any = {}
		for k, v in baseParams :: any do
			params[k] = v
		end
		for k, v in overrides do
			params[k] = v
		end
		return TransactionHash.calculateDeployAccountTransactionHash(params)
	end

	local baseHash = ""

	it("computes base hash", function()
		baseHash = withOverride({})
		expect(baseHash):toBeTruthy()
	end)

	it("different classHash produces different hash", function()
		local h = withOverride({ classHash = "0x2" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different constructorCalldata produces different hash", function()
		local h = withOverride({ constructorCalldata = { "0x2" } })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different contractAddress produces different hash", function()
		local h = withOverride({ contractAddress = "0x2" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different salt produces different hash", function()
		local h = withOverride({ salt = "0x2" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different chainId produces different hash", function()
		local h = withOverride({ chainId = "0x534e5f4d41494e" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different nonce produces different hash", function()
		local h = withOverride({ nonce = "0x1" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("non-zero tip produces different hash", function()
		local h = withOverride({ tip = "0x1" })
		expect(h ~= baseHash):toBe(true)
	end)

	it("paymaster data produces different hash", function()
		local h = withOverride({ paymasterData = { "0xdead" } })
		expect(h ~= baseHash):toBe(true)
	end)

	it("L2 DA mode produces different hash", function()
		local h = withOverride({ nonceDataAvailabilityMode = 1 })
		expect(h ~= baseHash):toBe(true)
	end)

	it("different resource bounds produces different hash", function()
		local h = withOverride({
			resourceBounds = {
				l1Gas = { maxAmount = "0x100", maxPricePerUnit = "0x200" },
				l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
				l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
			},
		})
		expect(h ~= baseHash):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- calculateDeployAccountTransactionHash - Default parameter handling
--------------------------------------------------------------------------------

describe("TransactionHash - V3 DEPLOY_ACCOUNT hash defaults", function()
	it("uses version 0x3 by default", function()
		local base = {
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		}
		local explicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			version = "0x3",
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateDeployAccountTransactionHash(base)
		expect(explicit):toBe(implicit)
	end)

	it("uses tip 0x0 by default", function()
		local explicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			tip = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses L1 DA mode by default", function()
		local explicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			nonceDataAvailabilityMode = 0,
			feeDataAvailabilityMode = 0,
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)

	it("uses empty paymaster data by default", function()
		local explicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			paymasterData = {},
			resourceBounds = ZERO_BOUNDS,
		})
		local implicit = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x1",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(explicit):toBe(implicit)
	end)
end)

--------------------------------------------------------------------------------
-- DEPLOY_ACCOUNT vs INVOKE produce different hashes (prefix difference)
--------------------------------------------------------------------------------

describe("TransactionHash - DEPLOY_ACCOUNT vs INVOKE hash prefix", function()
	it("deploy and invoke produce different hashes for same address/nonce/chain/bounds", function()
		local invokeHash = TransactionHash.calculateInvokeTransactionHash({
			senderAddress = "0x1",
			compiledCalldata = {},
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		local deployHash = TransactionHash.calculateDeployAccountTransactionHash({
			classHash = "0x0",
			constructorCalldata = {},
			contractAddress = "0x1",
			salt = "0x0",
			chainId = "0x534e5f5345504f4c4941",
			nonce = "0x0",
			resourceBounds = ZERO_BOUNDS,
		})
		expect(invokeHash ~= deployHash):toBe(true)
	end)
end)
