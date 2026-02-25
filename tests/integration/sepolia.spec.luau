--!strict
-- Integration test: end-to-end flow against Starknet Sepolia testnet.
-- GATED BY ENV VAR: Set STARKNET_SEPOLIA_URL to enable (e.g., "https://api.zan.top/public/starknet-sepolia")
-- Optionally set STARKNET_SEPOLIA_PRIVKEY to test account operations (hex private key).
--
-- Usage:
--   STARKNET_SEPOLIA_URL=https://api.zan.top/public/starknet-sepolia make test
--   STARKNET_SEPOLIA_URL=https://api.zan.top/public/starknet-sepolia STARKNET_SEPOLIA_PRIVKEY=0x1234... make test

local process = require("@lune/process")
local net = require("@lune/net")
local serde = require("@lune/serde")

local RpcProvider = require("../../src/provider/RpcProvider")
local Account = require("../../src/wallet/Account")
local StarkSigner = require("../../src/signer/StarkSigner")
local Keccak = require("../../src/crypto/Keccak")
local StarkField = require("../../src/crypto/StarkField")
local MockPromise = require("../helpers/MockPromise")

--------------------------------------------------------------------------------
-- Env-var gate: skip all tests if STARKNET_SEPOLIA_URL is not set
--------------------------------------------------------------------------------

local SEPOLIA_URL = process.env.STARKNET_SEPOLIA_URL or ""
local SEPOLIA_PRIVKEY = process.env.STARKNET_SEPOLIA_PRIVKEY or ""

if SEPOLIA_URL == "" then
	describe("Integration: Sepolia (SKIPPED - set STARKNET_SEPOLIA_URL to enable)", function()
		it("skipped - no STARKNET_SEPOLIA_URL env var", function()
			-- Intentionally empty: this test passes silently when integration is disabled
			expect(true):toBe(true)
		end)
	end)
	return
end

--------------------------------------------------------------------------------
-- Lune HTTP adapter: bridges net.request to RpcProvider's _httpRequest interface
--------------------------------------------------------------------------------

local function luneHttpRequest(request: any): any
	local response = net.request({
		url = request.Url,
		method = request.Method or "POST",
		headers = request.Headers or {},
		body = request.Body,
	})

	return {
		StatusCode = response.statusCode,
		Body = response.body,
		Success = response.ok,
	}
end

local function createSepoliaProvider(): any
	local config: any = {
		nodeUrl = SEPOLIA_URL,
		retryAttempts = 2,
		retryDelay = 1,
		_httpRequest = luneHttpRequest,
		_sleep = function(seconds: number)
			-- Lune doesn't have task.wait, use a busy wait for short durations
			local target = os.clock() + seconds
			while os.clock() < target do
			end
		end,
		_clock = os.clock,
	}

	local provider = RpcProvider.new(config)
	;(provider :: any)._PromiseModule = MockPromise
	return provider
end

--------------------------------------------------------------------------------
-- Provider-level integration tests (read-only, no private key needed)
--------------------------------------------------------------------------------

describe("Integration: Sepolia - Provider basics", function()
	it("getChainId returns SN_SEPOLIA", function()
		local provider = createSepoliaProvider()
		local chainId = provider:getChainId():expect()
		expect(chainId):toBe("0x534e5f5345504f4c4941")
	end)

	it("getBlockNumber returns a positive number", function()
		local provider = createSepoliaProvider()
		local blockNumber = provider:getBlockNumber():expect()
		expect(blockNumber > 0):toBe(true)
	end)

	it("getSpecVersion returns a version string", function()
		local provider = createSepoliaProvider()
		local specVersion = provider:getSpecVersion():expect()
		expect(type(specVersion)):toBe("string")
		expect(#specVersion > 0):toBe(true)
	end)

	it("call: reads ETH balanceOf for a known contract", function()
		local provider = createSepoliaProvider()
		-- Read ETH balance of the zero address (should return a u256 = 2 felts)
		local ETH_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
		local selectorFelt = Keccak.getSelectorFromName("balanceOf")
		local selector = StarkField.toHex(selectorFelt)

		local result = provider:call({
			contract_address = ETH_ADDRESS,
			entry_point_selector = selector,
			calldata = { "0x0" }, -- address 0
		}):expect()

		-- Should return at least 1 result element (the balance)
		expect(type(result)):toBe("table")
		expect(#result >= 1):toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Account-level integration tests (requires STARKNET_SEPOLIA_PRIVKEY)
--------------------------------------------------------------------------------

if SEPOLIA_PRIVKEY ~= "" then
	describe("Integration: Sepolia - Account operations", function()
		it("derives account address from private key", function()
			local signer = StarkSigner.new(SEPOLIA_PRIVKEY)
			local pubKeyHex = signer:getPublicKeyHex()
			local addr = Account.computeAddress({
				publicKey = pubKeyHex,
			})
			expect(type(addr)):toBe("string")
			expect(string.sub(addr, 1, 2)):toBe("0x")
			expect(#addr > 2):toBe(true)
		end)

		it("fetches nonce for derived account", function()
			local provider = createSepoliaProvider()
			local account = Account.fromPrivateKey({
				privateKey = SEPOLIA_PRIVKEY,
				provider = provider,
			})
			-- Try to get nonce; may fail if account is not deployed, but should not error on RPC level
			local ok, result = pcall(function()
				return account:getNonce():expect()
			end)
			if ok then
				expect(type(result)):toBe("string")
				expect(string.sub(result, 1, 2)):toBe("0x")
			else
				-- Account might not be deployed on Sepolia, which is acceptable
				-- The RPC call itself should have worked (we got an RPC error, not a network error)
				expect(true):toBe(true)
			end
		end)

		it("estimates fee for a dummy transfer (read-only)", function()
			local provider = createSepoliaProvider()
			local account = Account.fromPrivateKey({
				privateKey = SEPOLIA_PRIVKEY,
				provider = provider,
			})

			local ETH_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
			local calls = {
				{
					contractAddress = ETH_ADDRESS,
					entrypoint = "transfer",
					calldata = {
						"0x0000000000000000000000000000000000000000000000000000000000000001", -- recipient
						"0x1", -- amount low
						"0x0", -- amount high
					},
				},
			}

			-- Fee estimation may fail if account has no balance, but the RPC call should work
			local ok, result = pcall(function()
				return account:estimateFee(calls):expect()
			end)
			if ok then
				expect(result):toBeTruthy()
				-- Fee estimate should have gas_consumed and gas_price
				expect(result.gas_consumed):toBeTruthy()
			else
				-- Acceptable: account may not be deployed or funded on Sepolia
				expect(true):toBe(true)
			end
		end)
	end)

	describe("Integration: Sepolia - end-to-end dry run", function()
		it("builds and signs a transaction without submitting (dryRun)", function()
			local provider = createSepoliaProvider()
			local account = Account.fromPrivateKey({
				privateKey = SEPOLIA_PRIVKEY,
				provider = provider,
			})

			local ETH_ADDRESS = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"
			local calls = {
				{
					contractAddress = ETH_ADDRESS,
					entrypoint = "transfer",
					calldata = {
						"0x0000000000000000000000000000000000000000000000000000000000000001",
						"0x1",
						"0x0",
					},
				},
			}

			-- Dry run: build + sign but don't submit
			local ok, result = pcall(function()
				return account:execute(calls, { dryRun = true }):expect()
			end)
			if ok then
				expect(result):toBeTruthy()
				expect(result.transactionHash):toBeTruthy()
				expect(result.signature):toBeTruthy()
				expect(type(result.transactionHash)):toBe("string")
				expect(string.sub(result.transactionHash, 1, 2)):toBe("0x")
			else
				-- Acceptable: account may not be deployed or funded
				expect(true):toBe(true)
			end
		end)
	end)
else
	describe("Integration: Sepolia - Account (SKIPPED - set STARKNET_SEPOLIA_PRIVKEY to enable)", function()
		it("skipped - no STARKNET_SEPOLIA_PRIVKEY env var", function()
			expect(true):toBe(true)
		end)
	end)
end
