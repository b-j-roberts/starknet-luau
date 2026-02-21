--!strict
local TransactionHash = require("../../src/tx/TransactionHash")

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
		local result = TransactionHash.encodeResourceBound("0x4c315f474153", "0x7c9", "0x1")
		expect(result):toBe("0x4c315f47415300000000000007c900000000000000000000000000000001")
	end)

	it("encodes L2_GAS with zero bounds", function()
		local result = TransactionHash.encodeResourceBound("0x4c325f474153", "0x0", "0x0")
		expect(result):toBe("0x4c325f474153000000000000000000000000000000000000000000000000")
	end)

	it("encodes L1_DATA with zero bounds", function()
		local result = TransactionHash.encodeResourceBound("0x4c315f44415441", "0x0", "0x0")
		expect(result):toBe("0x4c315f44415441000000000000000000000000000000000000000000000000")
	end)

	it("encodes L1_GAS with realistic Sepolia values", function()
		-- max_amount = 0x186a0, max_price = 0x5af3107a4000
		local result = TransactionHash.encodeResourceBound("0x4c315f474153", "0x186a0", "0x5af3107a4000")
		expect(result):toBe("0x4c315f47415300000000000186a0000000000000000000005af3107a4000")
	end)

	it("encodes L2_GAS with non-zero values", function()
		-- max_amount = 0x1388, max_price = 0x3b9aca00
		local result = TransactionHash.encodeResourceBound("0x4c325f474153", "0x1388", "0x3b9aca00")
		expect(result):toBe("0x4c325f47415300000000000013880000000000000000000000003b9aca00")
	end)

	it("encodes L1_DATA with non-zero values", function()
		-- max_amount = 0x64, max_price = 0x5f5e100
		local result = TransactionHash.encodeResourceBound("0x4c315f44415441", "0x64", "0x5f5e100")
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

describe("TransactionHash - chain ID constants", function()
	it("SN_MAIN is correct ASCII encoding", function()
		expect(TransactionHash.SN_MAIN):toBe("0x534e5f4d41494e")
	end)

	it("SN_SEPOLIA is correct ASCII encoding", function()
		expect(TransactionHash.SN_SEPOLIA):toBe("0x534e5f5345504f4c4941")
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
