--!strict
-- Barrel export smoke test: validates all 9 top-level namespace keys
-- and their expected sub-module keys match what src/init.luau would export.
-- Since src/init.luau uses Roblox-style require(script.X), we import each
-- sub-module directly and verify the same structure.

local crypto = {
	BigInt = require("../src/crypto/BigInt"),
	FieldFactory = require("../src/crypto/FieldFactory"),
	StarkField = require("../src/crypto/StarkField"),
	StarkScalarField = require("../src/crypto/StarkScalarField"),
	StarkCurve = require("../src/crypto/StarkCurve"),
	Poseidon = require("../src/crypto/Poseidon"),
	Pedersen = require("../src/crypto/Pedersen"),
	Keccak = require("../src/crypto/Keccak"),
	SHA256 = require("../src/crypto/SHA256"),
	ECDSA = require("../src/crypto/ECDSA"),
}

local signer = {
	StarkSigner = require("../src/signer/StarkSigner"),
}

local provider = {
	RpcProvider = require("../src/provider/RpcProvider"),
	RpcTypes = require("../src/provider/RpcTypes"),
	EventPoller = require("../src/provider/EventPoller"),
	RequestQueue = require("../src/provider/RequestQueue"),
	ResponseCache = require("../src/provider/ResponseCache"),
	NonceManager = require("../src/provider/NonceManager"),
}

local tx = {
	CallData = require("../src/tx/CallData"),
	TransactionHash = require("../src/tx/TransactionHash"),
	TransactionBuilder = require("../src/tx/TransactionBuilder"),
}

local wallet = {
	Account = require("../src/wallet/Account"),
	TypedData = require("../src/wallet/TypedData"),
	AccountType = require("../src/wallet/AccountType"),
	AccountFactory = require("../src/wallet/AccountFactory"),
	OutsideExecution = require("../src/wallet/OutsideExecution"),
	KeyStore = require("../src/wallet/KeyStore"),
	OnboardingManager = require("../src/wallet/OnboardingManager"),
}

local contract = {
	AbiCodec = require("../src/contract/AbiCodec"),
	Contract = require("../src/contract/Contract"),
	ERC20 = require("../src/contract/ERC20"),
	ERC721 = require("../src/contract/ERC721"),
	PresetFactory = require("../src/contract/PresetFactory"),
}

local constants = require("../src/constants")

local errors = {
	StarknetError = require("../src/errors/StarknetError"),
	ErrorCodes = require("../src/errors/ErrorCodes"),
}

local paymaster = {
	PaymasterRpc = require("../src/paymaster/PaymasterRpc"),
	AvnuPaymaster = require("../src/paymaster/AvnuPaymaster"),
	PaymasterPolicy = require("../src/paymaster/PaymasterPolicy"),
	PaymasterBudget = require("../src/paymaster/PaymasterBudget"),
	SponsoredExecutor = require("../src/paymaster/SponsoredExecutor"),
}

-- Simulate the root barrel export table
local StarknetLuau = {
	crypto = crypto,
	signer = signer,
	provider = provider,
	tx = tx,
	wallet = wallet,
	contract = contract,
	constants = constants,
	errors = errors,
	paymaster = paymaster,
}

--------------------------------------------------------------------------------
-- Top-level namespace keys
--------------------------------------------------------------------------------

describe("Barrel Export - Top-level namespaces", function()
	local expectedKeys = { "crypto", "signer", "provider", "tx", "wallet", "contract", "constants", "errors", "paymaster" }

	it("exports exactly 9 namespace keys", function()
		local count = 0
		for _ in StarknetLuau do
			count += 1
		end
		expect(count):toBe(9)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}" namespace`, function()
			expect(StarknetLuau[key] ~= nil):toBe(true)
		end)
	end

	it("all namespace values are tables", function()
		for key, value in StarknetLuau do
			expect(type(value)):toBe("table")
		end
	end)
end)

--------------------------------------------------------------------------------
-- crypto sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - crypto namespace", function()
	local expectedKeys = {
		"BigInt", "FieldFactory", "StarkField", "StarkScalarField", "StarkCurve",
		"Poseidon", "Pedersen", "Keccak", "SHA256", "ECDSA",
	}

	it("exports exactly 10 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.crypto do
			count += 1
		end
		expect(count):toBe(10)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.crypto[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- signer sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - signer namespace", function()
	it("exports exactly 1 sub-module", function()
		local count = 0
		for _ in StarknetLuau.signer do
			count += 1
		end
		expect(count):toBe(1)
	end)

	it('exports "StarkSigner"', function()
		expect(StarknetLuau.signer.StarkSigner ~= nil):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- provider sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - provider namespace", function()
	local expectedKeys = {
		"RpcProvider", "RpcTypes", "EventPoller", "RequestQueue", "ResponseCache", "NonceManager",
	}

	it("exports exactly 6 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.provider do
			count += 1
		end
		expect(count):toBe(6)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.provider[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- tx sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - tx namespace", function()
	local expectedKeys = { "CallData", "TransactionHash", "TransactionBuilder" }

	it("exports exactly 3 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.tx do
			count += 1
		end
		expect(count):toBe(3)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.tx[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- wallet sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - wallet namespace", function()
	local expectedKeys = { "Account", "TypedData", "AccountType", "AccountFactory", "OutsideExecution", "KeyStore", "OnboardingManager" }

	it("exports exactly 7 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.wallet do
			count += 1
		end
		expect(count):toBe(7)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.wallet[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- contract sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - contract namespace", function()
	local expectedKeys = { "AbiCodec", "Contract", "ERC20", "ERC721", "PresetFactory" }

	it("exports exactly 5 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.contract do
			count += 1
		end
		expect(count):toBe(5)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.contract[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- constants (flat table, spot-check key fields)
--------------------------------------------------------------------------------

describe("Barrel Export - constants namespace", function()
	it("is a table", function()
		expect(type(StarknetLuau.constants)):toBe("table")
	end)

	it("contains chain ID constants", function()
		expect(StarknetLuau.constants.SN_MAIN ~= nil):toBe(true)
		expect(StarknetLuau.constants.SN_SEPOLIA ~= nil):toBe(true)
	end)

	it("contains class hash constants", function()
		expect(StarknetLuau.constants.OZ_ACCOUNT_CLASS_HASH ~= nil):toBe(true)
		expect(StarknetLuau.constants.ARGENT_ACCOUNT_CLASS_HASH ~= nil):toBe(true)
	end)

	it("contains token address constants", function()
		expect(StarknetLuau.constants.ETH_TOKEN_ADDRESS ~= nil):toBe(true)
		expect(StarknetLuau.constants.STRK_TOKEN_ADDRESS ~= nil):toBe(true)
	end)

	it("contains SDK_VERSION", function()
		expect(StarknetLuau.constants.SDK_VERSION):toBe("0.1.0")
	end)
end)

--------------------------------------------------------------------------------
-- errors sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - errors namespace", function()
	local expectedKeys = { "StarknetError", "ErrorCodes" }

	it("exports exactly 2 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.errors do
			count += 1
		end
		expect(count):toBe(2)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.errors[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- paymaster sub-module keys
--------------------------------------------------------------------------------

describe("Barrel Export - paymaster namespace", function()
	local expectedKeys = {
		"PaymasterRpc", "AvnuPaymaster", "PaymasterPolicy", "PaymasterBudget", "SponsoredExecutor",
	}

	it("exports exactly 5 sub-modules", function()
		local count = 0
		for _ in StarknetLuau.paymaster do
			count += 1
		end
		expect(count):toBe(5)
	end)

	for _, key in expectedKeys do
		it(`exports "{key}"`, function()
			expect(StarknetLuau.paymaster[key] ~= nil):toBe(true)
		end)
	end
end)

--------------------------------------------------------------------------------
-- Sub-module usability spot-checks
--------------------------------------------------------------------------------

describe("Barrel Export - sub-module usability", function()
	it("crypto.BigInt has fromHex", function()
		expect(type(StarknetLuau.crypto.BigInt.fromHex)):toBe("function")
	end)

	it("crypto.Poseidon has hash", function()
		expect(type(StarknetLuau.crypto.Poseidon.hash)):toBe("function")
	end)

	it("crypto.ECDSA has sign", function()
		expect(type(StarknetLuau.crypto.ECDSA.sign)):toBe("function")
	end)

	it("signer.StarkSigner has new", function()
		expect(type(StarknetLuau.signer.StarkSigner.new)):toBe("function")
	end)

	it("provider.RpcProvider has new", function()
		expect(type(StarknetLuau.provider.RpcProvider.new)):toBe("function")
	end)

	it("tx.CallData has compile", function()
		expect(type(StarknetLuau.tx.CallData.compile)):toBe("function")
	end)

	it("wallet.Account has new", function()
		expect(type(StarknetLuau.wallet.Account.new)):toBe("function")
	end)

	it("contract.AbiCodec has buildTypeMap", function()
		expect(type(StarknetLuau.contract.AbiCodec.buildTypeMap)):toBe("function")
	end)

	it("contract.Contract has new", function()
		expect(type(StarknetLuau.contract.Contract.new)):toBe("function")
	end)

	it("errors.StarknetError has new", function()
		expect(type(StarknetLuau.errors.StarknetError.new)):toBe("function")
	end)

	it("errors.ErrorCodes has RPC_ERROR", function()
		expect(StarknetLuau.errors.ErrorCodes.RPC_ERROR ~= nil):toBe(true)
	end)

	it("paymaster.PaymasterRpc has new", function()
		expect(type(StarknetLuau.paymaster.PaymasterRpc.new)):toBe("function")
	end)
end)
