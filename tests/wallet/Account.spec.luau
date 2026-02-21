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

-- Expected addresses (computed by starknet.js calculateContractAddressFromHash)
local EXPECTED_ADDR_1_OZ = "0x76d427e4760e8a0947f747c98263827154aca2c999b288a2087cd9655e2008d"
local EXPECTED_ADDR_2_OZ = "0x568f41175d86b1ea857a8daba89430ebe5b5da27c6848fa8234392151ea8b39"
local EXPECTED_ADDR_3_OZ = "0x2b5cea709ab25612f9d014a3312f1c6dbd988add3bf396c1866db1b03b09194"

local EXPECTED_ADDR_1_OZ2 = "0x38de74aab5907ad06a25dd88fafe0296a2ca303fedb8b37926edf15363aee67"
local EXPECTED_ADDR_2_OZ2 = "0x365ff7fefa7c4a5e0c41e2c27aa55d35b6439fa891ad5b85da1cdffeb736f08"
local EXPECTED_ADDR_3_OZ2 = "0x4235a538f2315ca101e7260ff94997456428a1a7138b71ab335a423602400d8"

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
-- computeAddress
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
		-- Should match the standard OZ address (deployer=0)
		local addr = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
		})
		expect(addr):toBe(EXPECTED_ADDR_3_OZ)
	end)

	it("defaults salt to publicKey", function()
		-- Explicit salt = publicKey should match default
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
		-- With different calldata, address should differ from OZ default
		local addrDefault = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
		})
		local addrCustom = Account.computeAddress({
			classHash = OZ_CLASS_HASH,
			publicKey = PUBKEY_3,
			constructorCalldata = { PUBKEY_3, "0x0" }, -- e.g., [publicKey, guardian=0] for Argent
		})
		-- Must be different addresses
		expect(addrCustom ~= addrDefault):toBe(true)
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
		end):toThrow()
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
		end):toThrow()
	end)

	it("errors when provider is missing", function()
		local signer = StarkSigner.new(PRIVKEY_1)

		expect(function()
			Account.new({
				address = EXPECTED_ADDR_1_OZ,
				signer = signer,
				provider = nil :: any,
			})
		end):toThrow()
	end)
end)

--------------------------------------------------------------------------------
-- Account.fromPrivateKey
--------------------------------------------------------------------------------

describe("Account.fromPrivateKey", function()
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

	it("errors when privateKey is missing", function()
		resetHandlers()
		local provider = createTestProvider()

		expect(function()
			Account.fromPrivateKey({
				privateKey = nil :: any,
				provider = provider,
			})
		end):toThrow()
	end)

	it("errors when provider is missing", function()
		expect(function()
			Account.fromPrivateKey({
				privateKey = PRIVKEY_1,
				provider = nil :: any,
			})
		end):toThrow()
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

		-- Find the getNonce call in the request log
		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_getNonce" then
				found = true
				-- params is [blockId, contractAddress]
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

		-- The addInvokeTransaction call should include the derived address
		local found = false
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				found = true
				-- params is [{type, version, sender_address, ...}]
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(EXPECTED_ADDR_1_OZ)
			end
		end
		expect(found):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account class hash constants
--------------------------------------------------------------------------------

describe("Account constants", function()
	it("exposes OZ_CLASS_HASH", function()
		expect(Account.OZ_CLASS_HASH):toBe(OZ_CLASS_HASH)
	end)

	it("OZ_CLASS_HASH is a valid hex string", function()
		expect(string.sub(Account.OZ_CLASS_HASH, 1, 2)):toBe("0x")
		expect(#Account.OZ_CLASS_HASH > 2):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account with Account.new (explicit address)
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

		-- Verify the custom address was used
		for _, entry in requestLog do
			if entry.method == "starknet_addInvokeTransaction" then
				-- params is [{type, version, sender_address, ...}]
				local tx = entry.params[1]
				expect(tx.sender_address):toBe(customAddress)
			end
		end
	end)
end)
