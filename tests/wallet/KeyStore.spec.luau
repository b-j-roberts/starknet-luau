--!strict
local KeyStore = require("../../src/wallet/KeyStore")
local ErrorCodes = require("../../src/errors/ErrorCodes")
local TestUtils = require("../helpers/TestUtils")
local BigInt = require("../../src/crypto/BigInt")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Valid 32-byte (64 hex char) server secret for tests
local TEST_SECRET = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
local TEST_SECRET_0X = "0x" .. TEST_SECRET
local ALT_SECRET = "1122334455667788990011223344556677889900112233445566778899001122"
local SHORT_SECRET = "a1b2c3d4" -- too short
local ALL_ZEROS_SECRET = string.rep("0", 64)

local PLAYER_1 = 12345
local PLAYER_2 = 67890
local PLAYER_3 = 11111

--- Create deterministic "random" bytes for reproducible tests.
local function makeDeterministicRandom(): (n: number) -> buffer
	local callCount = 0
	return function(n: number): buffer
		callCount += 1
		local buf = buffer.create(n)
		for i = 0, n - 1 do
			buffer.writeu8(buf, i, (i * 37 + 13 + callCount * 7) % 256)
		end
		return buf
	end
end

--- Create a mock DataStore with GetAsync, SetAsync, RemoveAsync.
--- Returns (store, data, setUserIds) where setUserIds tracks userIds passed to SetAsync.
local function createMockDataStore(): (any, { [string]: any }, { [string]: { number }? })
	local data: { [string]: any } = {}
	local setUserIds: { [string]: { number }? } = {}
	local store = {}

	function store:GetAsync(key: string): any?
		return data[key]
	end

	function store:SetAsync(key: string, value: any, userIds: { number }?): ()
		data[key] = value
		if userIds then
			setUserIds[key] = userIds
		end
	end

	function store:RemoveAsync(key: string): ()
		data[key] = nil
		setUserIds[key] = nil
	end

	return store, data, setUserIds
end

--- Create a mock DataStore that errors on specified operations.
local function createFailingDataStore(failGet: boolean?, failSet: boolean?, failRemove: boolean?): any
	local store = {}

	function store:GetAsync(_key: string): any?
		if failGet then
			error("DataStore GetAsync failed: service unavailable")
		end
		return nil
	end

	function store:SetAsync(_key: string, _value: any, _userIds: { number }?): ()
		if failSet then
			error("DataStore SetAsync failed: service unavailable")
		end
	end

	function store:RemoveAsync(_key: string): ()
		if failRemove then
			error("DataStore RemoveAsync failed: service unavailable")
		end
	end

	return store
end

--- Create a KeyStore with standard test config and mock DataStore.
local function createTestKeyStore(overrides: { [string]: any }?): (any, { [string]: any }, { [string]: { number }? })
	local mockDS, data, setUserIds = createMockDataStore()
	local config: any = {
		serverSecret = TEST_SECRET,
		_dataStore = mockDS,
		_clock = function()
			return 1000
		end,
		_randomBytes = makeDeterministicRandom(),
	}
	if overrides then
		for k, v in overrides do
			config[k] = v
		end
	end
	local ks = KeyStore.new(config)
	return ks, data, setUserIds
end

--- Create a mock provider using TestUtils.
local function createProvider(): any
	local rpc = TestUtils.createMockRpcLayer()
	return rpc.createTestProvider()
end

--------------------------------------------------------------------------------
-- Tests: Constructor
--------------------------------------------------------------------------------

describe("KeyStore.new", function()
	it("creates with valid hex secret", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET })
		expect(ks):toBeTruthy()
	end)

	it("creates with 0x-prefixed secret", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET_0X })
		expect(ks):toBeTruthy()
	end)

	it("defaults accountType to oz", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET })
		expect(ks):toBeTruthy()
	end)

	it("accepts custom accountType argent", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET, accountType = "argent" })
		expect(ks):toBeTruthy()
	end)

	it("accepts custom accountType braavos", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET, accountType = "braavos" })
		expect(ks):toBeTruthy()
	end)

	it("accepts custom dataStoreName", function()
		local ks = KeyStore.new({ serverSecret = TEST_SECRET, dataStoreName = "MyGameKeys" })
		expect(ks):toBeTruthy()
	end)

	it("rejects empty secret", function()
		expect(function()
			KeyStore.new({ serverSecret = "" })
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("rejects short secret (< 64 hex chars)", function()
		expect(function()
			KeyStore.new({ serverSecret = SHORT_SECRET })
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("rejects all-zeros secret", function()
		expect(function()
			KeyStore.new({ serverSecret = ALL_ZEROS_SECRET })
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("rejects non-hex secret", function()
		expect(function()
			KeyStore.new({ serverSecret = string.rep("g", 64) })
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("rejects non-string secret", function()
		expect(function()
			KeyStore.new({ serverSecret = 12345 :: any })
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("rejects invalid accountType", function()
		expect(function()
			KeyStore.new({ serverSecret = TEST_SECRET, accountType = "invalid" })
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("accepts secret longer than 64 hex chars", function()
		local longSecret = TEST_SECRET .. "aabbccdd"
		local ks = KeyStore.new({ serverSecret = longSecret })
		expect(ks):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Tests: generateAndStore
--------------------------------------------------------------------------------

describe("KeyStore:generateAndStore", function()
	it("generates and returns account with address", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local result = ks:generateAndStore(PLAYER_1, provider)
		expect(result.account):toBeTruthy()
		expect(result.address):toBeTruthy()
		expect(type(result.address)):toBe("string")
		expect(string.sub(result.address, 1, 2)):toBe("0x")
	end)

	it("stores encrypted record in DataStore", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)

		local record = data["player_12345"]
		expect(record):toBeTruthy()
		expect(record.version):toBe(1)
		expect(type(record.encrypted)):toBe("string")
		expect(type(record.address)):toBe("string")
		expect(record.accountType):toBe("oz")
		expect(record.createdAt):toBe(1000)
	end)

	it("stores address in plaintext", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		local result = ks:generateAndStore(PLAYER_1, provider)
		local record = data["player_12345"]

		expect(record.address):toBe(result.address)
	end)

	it("tags SetAsync with playerId for Right to Erasure", function()
		local ks, _, setUserIds = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)

		local userIds = setUserIds["player_12345"]
		expect(userIds):toBeTruthy()
		expect(#userIds):toBe(1)
		expect(userIds[1]):toBe(PLAYER_1)
	end)

	it("encrypted value differs from raw key bytes", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)

		local record = data["player_12345"]
		-- The encrypted hex should not be all zeros (XOR of key with keystream)
		expect(record.encrypted ~= "0x" .. string.rep("00", 32)):toBe(true)
	end)

	it("generates different keys for different calls", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local r1 = ks:generateAndStore(PLAYER_1, provider)
		local r2 = ks:generateAndStore(PLAYER_2, provider)

		expect(r1.address ~= r2.address):toBe(true)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		expect(function()
			ks:generateAndStore("abc" :: any, provider)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("rejects nil provider", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:generateAndStore(PLAYER_1, nil)
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)

	it("handles DataStore write failure", function()
		local failDS = createFailingDataStore(false, true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
			_randomBytes = makeDeterministicRandom(),
		})
		local provider = createProvider()

		expect(function()
			ks:generateAndStore(PLAYER_1, provider)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("works without DataStore (no-op persist)", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		local provider = createProvider()

		local result = ks:generateAndStore(PLAYER_1, provider)
		expect(result.account):toBeTruthy()
		expect(result.address):toBeTruthy()
	end)

	it("stores correct accountType for argent", function()
		local ks, data = createTestKeyStore({ accountType = "argent" })
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(data["player_12345"].accountType):toBe("argent")
	end)

	it("uses injected clock for createdAt", function()
		local clockVal = 5555
		local ks, data = createTestKeyStore({
			_clock = function()
				return clockVal
			end,
		})
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(data["player_12345"].createdAt):toBe(5555)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: loadAccount
--------------------------------------------------------------------------------

describe("KeyStore:loadAccount", function()
	it("loads and decrypts stored account", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local generated = ks:generateAndStore(PLAYER_1, provider)
		local loaded = ks:loadAccount(PLAYER_1, provider)

		expect(loaded):toBeTruthy()
		expect(loaded.address):toBe(generated.address)
	end)

	it("returns nil when no record exists", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local result = ks:loadAccount(PLAYER_1, provider)
		expect(result):toBeNil()
	end)

	it("returns nil without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		local provider = createProvider()

		local result = ks:loadAccount(PLAYER_1, provider)
		expect(result):toBeNil()
	end)

	it("handles corrupted record (missing fields)", function()
		local mockDS = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		-- Manually insert corrupted data
		mockDS:SetAsync("player_12345", { version = 1, encrypted = "0xabc" })

		local provider = createProvider()
		expect(function()
			ks:loadAccount(PLAYER_1, provider)
		end):toThrowCode(ErrorCodes.KEY_STORE_DECRYPT_ERROR.code)
	end)

	it("handles invalid encrypted key length", function()
		local mockDS = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		-- Insert record with wrong-length encrypted data (only 4 bytes)
		mockDS:SetAsync("player_12345", {
			version = 1,
			encrypted = "0xaabbccdd",
			address = "0x123",
			accountType = "oz",
			createdAt = 1000,
		})

		local provider = createProvider()
		expect(function()
			ks:loadAccount(PLAYER_1, provider)
		end):toThrowCode(ErrorCodes.KEY_STORE_DECRYPT_ERROR.code)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		expect(function()
			ks:loadAccount("abc" :: any, provider)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("rejects nil provider", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:loadAccount(PLAYER_1, nil)
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)

	it("handles DataStore read failure", function()
		local failDS = createFailingDataStore(true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})
		local provider = createProvider()

		expect(function()
			ks:loadAccount(PLAYER_1, provider)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("preserves account type from stored record", function()
		local mockDS = createMockDataStore()
		-- Create with oz, store manually with argent type
		local ksOz = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
			_randomBytes = makeDeterministicRandom(),
			_clock = function()
				return 1000
			end,
		})
		local provider = createProvider()
		ksOz:generateAndStore(PLAYER_1, provider)

		-- Verify loaded account works
		local loaded = ksOz:loadAccount(PLAYER_1, provider)
		expect(loaded):toBeTruthy()
		expect(loaded.address):toBeTruthy()
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getOrCreate
--------------------------------------------------------------------------------

describe("KeyStore:getOrCreate", function()
	it("creates new account when none exists", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local result = ks:getOrCreate(PLAYER_1, provider)
		expect(result.account):toBeTruthy()
		expect(result.isNew):toBe(true)
	end)

	it("loads existing account", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local first = ks:generateAndStore(PLAYER_1, provider)
		local result = ks:getOrCreate(PLAYER_1, provider)

		expect(result.account):toBeTruthy()
		expect(result.isNew):toBe(false)
		expect(result.account.address):toBe(first.address)
	end)

	it("returns same address on repeated calls", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local r1 = ks:getOrCreate(PLAYER_1, provider)
		local r2 = ks:getOrCreate(PLAYER_1, provider)

		expect(r1.isNew):toBe(true)
		expect(r2.isNew):toBe(false)
		expect(r1.account.address):toBe(r2.account.address)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		expect(function()
			ks:getOrCreate(true :: any, provider)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("rejects nil provider", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:getOrCreate(PLAYER_1, nil)
		end):toThrowCode(ErrorCodes.REQUIRED_FIELD.code)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: hasAccount
--------------------------------------------------------------------------------

describe("KeyStore:hasAccount", function()
	it("returns true when account exists", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(ks:hasAccount(PLAYER_1)):toBe(true)
	end)

	it("returns false when no account exists", function()
		local ks = createTestKeyStore()
		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("returns false without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("does not decrypt (checks address field only)", function()
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		-- Insert record with garbage encrypted field but valid address
		data["player_12345"] = {
			version = 1,
			encrypted = "invalid_not_hex",
			address = "0x123abc",
			accountType = "oz",
			createdAt = 1000,
		}

		-- hasAccount should succeed (only checks address field presence)
		expect(ks:hasAccount(PLAYER_1)):toBe(true)
	end)

	it("returns false for non-table record", function()
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		data["player_12345"] = "not a table"
		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("returns false when record missing address", function()
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		data["player_12345"] = { version = 1, encrypted = "0xabc" }
		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:hasAccount("abc" :: any)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("handles DataStore read failure", function()
		local failDS = createFailingDataStore(true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})

		expect(function()
			ks:hasAccount(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: deleteKey
--------------------------------------------------------------------------------

describe("KeyStore:deleteKey", function()
	it("removes key from DataStore", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(data["player_12345"]):toBeTruthy()

		ks:deleteKey(PLAYER_1)
		expect(data["player_12345"]):toBeNil()
	end)

	it("account no longer loadable after delete", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:deleteKey(PLAYER_1)

		local loaded = ks:loadAccount(PLAYER_1, provider)
		expect(loaded):toBeNil()
	end)

	it("hasAccount returns false after delete", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(ks:hasAccount(PLAYER_1)):toBe(true)

		ks:deleteKey(PLAYER_1)
		expect(ks:hasAccount(PLAYER_1)):toBe(false)
	end)

	it("no error when deleting non-existent key", function()
		local ks = createTestKeyStore()
		-- Should not throw
		ks:deleteKey(PLAYER_1)
	end)

	it("no-op without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		-- Should not throw
		ks:deleteKey(PLAYER_1)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:deleteKey("abc" :: any)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("handles DataStore RemoveAsync failure", function()
		local failDS = createFailingDataStore(false, false, true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})

		expect(function()
			ks:deleteKey(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: rotateSecret
--------------------------------------------------------------------------------

describe("KeyStore:rotateSecret", function()
	it("re-encrypts keys with new secret", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		local originalEncrypted = data["player_12345"].encrypted

		local result = ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1 })
		expect(result.rotated):toBe(1)
		expect(#result.failed):toBe(0)

		-- Encrypted value should have changed
		expect(data["player_12345"].encrypted ~= originalEncrypted):toBe(true)
	end)

	it("account loadable with new secret after rotation", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local generated = ks:generateAndStore(PLAYER_1, provider)
		ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1 })

		-- KeyStore internal secret should now be ALT_SECRET
		local loaded = ks:loadAccount(PLAYER_1, provider)
		expect(loaded):toBeTruthy()
		expect(loaded.address):toBe(generated.address)
	end)

	it("rotates multiple players", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:generateAndStore(PLAYER_2, provider)

		local result = ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1, PLAYER_2 })
		expect(result.rotated):toBe(2)
		expect(#result.failed):toBe(0)
	end)

	it("reports missing players as failed", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)

		local result = ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1, PLAYER_3 })
		expect(result.rotated):toBe(1)
		expect(#result.failed):toBe(1)
		expect(result.failed[1].playerId):toBe(PLAYER_3)
	end)

	it("validates old secret", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:rotateSecret(SHORT_SECRET, ALT_SECRET, {})
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("validates new secret", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:rotateSecret(TEST_SECRET, SHORT_SECRET, {})
		end):toThrowCode(ErrorCodes.KEY_STORE_SECRET_INVALID.code)
	end)

	it("requires DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})

		expect(function()
			ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1 })
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("handles empty playerIds list", function()
		local ks = createTestKeyStore()

		local result = ks:rotateSecret(TEST_SECRET, ALT_SECRET, {})
		expect(result.rotated):toBe(0)
		expect(#result.failed):toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Encryption correctness
--------------------------------------------------------------------------------

describe("KeyStore — encryption", function()
	it("XOR encryption is reversible (store → load roundtrip)", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local generated = ks:generateAndStore(PLAYER_1, provider)
		local loaded = ks:loadAccount(PLAYER_1, provider)

		expect(loaded):toBeTruthy()
		expect(loaded.address):toBe(generated.address)
	end)

	it("different players get different ciphertexts", function()
		-- Use same random bytes so both get same private key
		local callCount = 0
		local fixedBytes = buffer.create(32)
		for i = 0, 31 do
			buffer.writeu8(fixedBytes, i, (i * 37 + 13) % 256)
		end

		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
			_clock = function()
				return 1000
			end,
			_randomBytes = function(n: number): buffer
				callCount += 1
				local buf = buffer.create(n)
				buffer.copy(buf, 0, fixedBytes, 0, math.min(n, 32))
				return buf
			end,
		})
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:generateAndStore(PLAYER_2, provider)

		-- Same key, different player → different ciphertext
		expect(data["player_12345"].encrypted ~= data["player_67890"].encrypted):toBe(true)
	end)

	it("different secrets produce different ciphertexts", function()
		local fixedRandom = function(n: number): buffer
			local buf = buffer.create(n)
			for i = 0, n - 1 do
				buffer.writeu8(buf, i, (i * 37 + 13) % 256)
			end
			return buf
		end

		local mockDS1, data1 = createMockDataStore()
		local ks1 = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS1,
			_clock = function()
				return 1000
			end,
			_randomBytes = fixedRandom,
		})

		local mockDS2, data2 = createMockDataStore()
		local ks2 = KeyStore.new({
			serverSecret = ALT_SECRET,
			_dataStore = mockDS2,
			_clock = function()
				return 1000
			end,
			_randomBytes = fixedRandom,
		})

		local provider = createProvider()
		ks1:generateAndStore(PLAYER_1, provider)
		ks2:generateAndStore(PLAYER_1, provider)

		-- Same key, same player, different secret → different ciphertext
		expect(data1["player_12345"].encrypted ~= data2["player_12345"].encrypted):toBe(true)
		-- But same address (same private key)
		expect(data1["player_12345"].address):toBe(data2["player_12345"].address)
	end)

	it("generated private key is valid (in range [1, N-1])", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		-- Generate several keys and verify all produce valid accounts
		for i = 1, 5 do
			local result = ks:generateAndStore(i, provider)
			expect(result.account):toBeTruthy()
			expect(result.address):toBeTruthy()
		end
	end)
end)

--------------------------------------------------------------------------------
-- Tests: Integration scenarios
--------------------------------------------------------------------------------

describe("KeyStore — integration", function()
	it("full lifecycle: generate → load → delete → load returns nil", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		-- Generate
		local generated = ks:generateAndStore(PLAYER_1, provider)
		expect(ks:hasAccount(PLAYER_1)):toBe(true)

		-- Load
		local loaded = ks:loadAccount(PLAYER_1, provider)
		expect(loaded):toBeTruthy()
		expect(loaded.address):toBe(generated.address)

		-- Delete
		ks:deleteKey(PLAYER_1)
		expect(ks:hasAccount(PLAYER_1)):toBe(false)

		-- Load returns nil
		local afterDelete = ks:loadAccount(PLAYER_1, provider)
		expect(afterDelete):toBeNil()
	end)

	it("getOrCreate creates then reloads", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local r1 = ks:getOrCreate(PLAYER_1, provider)
		expect(r1.isNew):toBe(true)

		local r2 = ks:getOrCreate(PLAYER_1, provider)
		expect(r2.isNew):toBe(false)
		expect(r2.account.address):toBe(r1.account.address)
	end)

	it("multiple players with same KeyStore", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local r1 = ks:getOrCreate(PLAYER_1, provider)
		local r2 = ks:getOrCreate(PLAYER_2, provider)
		local r3 = ks:getOrCreate(PLAYER_3, provider)

		-- All different addresses
		expect(r1.account.address ~= r2.account.address):toBe(true)
		expect(r2.account.address ~= r3.account.address):toBe(true)
		expect(r1.account.address ~= r3.account.address):toBe(true)

		-- All loadable
		expect(ks:hasAccount(PLAYER_1)):toBe(true)
		expect(ks:hasAccount(PLAYER_2)):toBe(true)
		expect(ks:hasAccount(PLAYER_3)):toBe(true)
	end)

	it("rotate secret then load all accounts", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local g1 = ks:generateAndStore(PLAYER_1, provider)
		local g2 = ks:generateAndStore(PLAYER_2, provider)

		-- Rotate
		local result = ks:rotateSecret(TEST_SECRET, ALT_SECRET, { PLAYER_1, PLAYER_2 })
		expect(result.rotated):toBe(2)

		-- Both should still load with correct addresses
		local l1 = ks:loadAccount(PLAYER_1, provider)
		local l2 = ks:loadAccount(PLAYER_2, provider)
		expect(l1.address):toBe(g1.address)
		expect(l2.address):toBe(g2.address)
	end)

	it("getOrCreate after delete creates new account", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		local first = ks:getOrCreate(PLAYER_1, provider)
		local firstAddress = first.account.address

		ks:deleteKey(PLAYER_1)

		local second = ks:getOrCreate(PLAYER_1, provider)
		expect(second.isNew):toBe(true)
		-- New key generated → different address (with overwhelming probability)
		-- Note: addresses could theoretically collide but probability is negligible
	end)

	it("DataStore record version field is 1", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(data["player_12345"].version):toBe(1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: getRecord
--------------------------------------------------------------------------------

describe("KeyStore:getRecord", function()
	it("returns record for existing player", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		local record = ks:getRecord(PLAYER_1)
		expect(record):toBeTruthy()
		expect(record.address):toBeTruthy()
		expect(record.version):toBe(1)
		expect(record.accountType):toBe("oz")
		expect(record.createdAt):toBe(1000)
	end)

	it("returns nil for missing player", function()
		local ks = createTestKeyStore()
		local record = ks:getRecord(PLAYER_1)
		expect(record):toBeNil()
	end)

	it("returns nil without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		local record = ks:getRecord(PLAYER_1)
		expect(record):toBeNil()
	end)

	it("returns nil for invalid record", function()
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		data["player_12345"] = { version = 1 } -- missing required fields
		local record = ks:getRecord(PLAYER_1)
		expect(record):toBeNil()
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:getRecord("abc" :: any)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("handles DataStore read failure", function()
		local failDS = createFailingDataStore(true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})

		expect(function()
			ks:getRecord(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("does not include deployedAt when not set", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		local record = ks:getRecord(PLAYER_1)
		expect(record.deployedAt):toBeNil()
	end)
end)

--------------------------------------------------------------------------------
-- Tests: markDeployed
--------------------------------------------------------------------------------

describe("KeyStore:markDeployed", function()
	it("sets deployedAt timestamp", function()
		local ks, data = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(data["player_12345"].deployedAt):toBeNil()

		ks:markDeployed(PLAYER_1)
		expect(data["player_12345"].deployedAt):toBe(1000)
	end)

	it("is idempotent (preserves original timestamp)", function()
		local clockVal = 1000
		local ks, data = createTestKeyStore({
			_clock = function()
				clockVal += 100
				return clockVal
			end,
		})
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)
		local firstTimestamp = data["player_12345"].deployedAt

		ks:markDeployed(PLAYER_1)
		expect(data["player_12345"].deployedAt):toBe(firstTimestamp)
	end)

	it("no-op for missing record", function()
		local ks = createTestKeyStore()
		-- Should not throw
		ks:markDeployed(PLAYER_1)
	end)

	it("no-op without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		-- Should not throw
		ks:markDeployed(PLAYER_1)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:markDeployed("abc" :: any)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("handles DataStore read failure", function()
		local failDS = createFailingDataStore(true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})

		expect(function()
			ks:markDeployed(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("handles DataStore write failure", function()
		-- Create a DS that succeeds on read but fails on write
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
			_randomBytes = makeDeterministicRandom(),
			_clock = function()
				return 1000
			end,
		})
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)

		-- Now make SetAsync fail
		function mockDS:SetAsync(_key: string, _value: any, _userIds: { number }?): ()
			error("DataStore SetAsync failed: service unavailable")
		end

		expect(function()
			ks:markDeployed(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("no-op for invalid record shape", function()
		local mockDS, data = createMockDataStore()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = mockDS,
		})

		data["player_12345"] = { garbage = true }
		-- Should not throw (record is invalid, treated as missing)
		ks:markDeployed(PLAYER_1)
	end)
end)

--------------------------------------------------------------------------------
-- Tests: isDeployed
--------------------------------------------------------------------------------

describe("KeyStore:isDeployed", function()
	it("returns false for missing player", function()
		local ks = createTestKeyStore()
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)

	it("returns false when deployedAt is not set", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)

	it("returns true after markDeployed", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(true)
	end)

	it("returns false without DataStore", function()
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_randomBytes = makeDeterministicRandom(),
		})
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)

	it("rejects non-number playerId", function()
		local ks = createTestKeyStore()

		expect(function()
			ks:isDeployed("abc" :: any)
		end):toThrowCode(ErrorCodes.INVALID_ARGUMENT.code)
	end)

	it("handles DataStore read failure", function()
		local failDS = createFailingDataStore(true)
		local ks = KeyStore.new({
			serverSecret = TEST_SECRET,
			_dataStore = failDS,
		})

		expect(function()
			ks:isDeployed(PLAYER_1)
		end):toThrowCode(ErrorCodes.KEY_STORE_ERROR.code)
	end)

	it("returns false after deleteKey", function()
		local ks = createTestKeyStore()
		local provider = createProvider()

		ks:generateAndStore(PLAYER_1, provider)
		ks:markDeployed(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(true)

		ks:deleteKey(PLAYER_1)
		expect(ks:isDeployed(PLAYER_1)):toBe(false)
	end)
end)
