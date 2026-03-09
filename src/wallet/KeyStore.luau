--!strict
-- KeyStore: Encrypted key persistence via DataStoreService for player-linked accounts
-- Keys are encrypted at rest using XOR with HMAC-SHA256 derived keystream.
-- This is a custodial model — the game developer is the custodian.
-- For non-custodial alternatives, see relay server mode or wallet linking.

local BigInt = require("../crypto/BigInt")
local SHA256 = require("../crypto/SHA256")
local StarkCurve = require("../crypto/StarkCurve")
local Account = require("./Account")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type DataStoreLike = {
	GetAsync: (self: DataStoreLike, key: string) -> any?,
	SetAsync: (self: DataStoreLike, key: string, value: any, userIds: { number }?, options: any?) -> (),
	RemoveAsync: (self: DataStoreLike, key: string) -> (),
}

export type KeyStoreConfig = {
	serverSecret: string,
	dataStoreName: string?,
	accountType: string?,
	_dataStore: DataStoreLike?,
	_clock: (() -> number)?,
	_randomBytes: ((n: number) -> buffer)?,
}

export type KeyStoreRecord = {
	version: number,
	encrypted: string,
	address: string,
	accountType: string,
	createdAt: number,
	deployedAt: number?,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local ALL_ZEROS_64 = string.rep("0", 64)

--- Convert a hex string to a buffer of raw bytes.
local function hexToBuffer(hex: string): buffer
	local h = hex
	if string.sub(h, 1, 2) == "0x" or string.sub(h, 1, 2) == "0X" then
		h = string.sub(h, 3)
	end
	if #h % 2 ~= 0 then
		h = "0" .. h
	end
	local len = #h / 2
	local buf = buffer.create(len)
	for i = 0, len - 1 do
		local byte = tonumber(string.sub(h, i * 2 + 1, i * 2 + 2), 16)
		if byte == nil then
			error(StarknetError.validation("Invalid hex character in string", ErrorCodes.INVALID_FORMAT.code))
		end
		buffer.writeu8(buf, i, byte)
	end
	return buf
end

--- Convert a buffer of raw bytes to a "0x..." hex string.
local function bufferToHex(buf: buffer): string
	local len = buffer.len(buf)
	local parts = table.create(len)
	for i = 0, len - 1 do
		parts[i + 1] = string.format("%02x", buffer.readu8(buf, i))
	end
	return "0x" .. table.concat(parts)
end

--- XOR two equal-length buffers, returning a new buffer.
local function xorBuffers(a: buffer, b: buffer): buffer
	local len = buffer.len(a)
	local result = buffer.create(len)
	for i = 0, len - 1 do
		buffer.writeu8(result, i, bit32.bxor(buffer.readu8(a, i), buffer.readu8(b, i)))
	end
	return result
end

--- Generate a deterministic keystream for a player using HMAC-SHA256.
local function deriveKeystream(secretBuf: buffer, playerId: number): buffer
	local playerIdStr = tostring(playerId)
	local msgBuf = buffer.create(#playerIdStr)
	for i = 1, #playerIdStr do
		buffer.writeu8(msgBuf, i - 1, string.byte(playerIdStr, i))
	end
	return SHA256.hmac(secretBuf, msgBuf)
end

--- Encrypt a 32-byte private key buffer using the player keystream.
local function encryptKey(privKeyBuf: buffer, secretBuf: buffer, playerId: number): buffer
	local keystream = deriveKeystream(secretBuf, playerId)
	return xorBuffers(privKeyBuf, keystream)
end

--- Decrypt an encrypted key buffer back to private key buffer.
local function decryptKey(encryptedBuf: buffer, secretBuf: buffer, playerId: number): buffer
	local keystream = deriveKeystream(secretBuf, playerId)
	return xorBuffers(encryptedBuf, keystream)
end

--- Strip "0x"/"0X" prefix from a hex string.
local function stripHexPrefix(hex: string): string
	if string.sub(hex, 1, 2) == "0x" or string.sub(hex, 1, 2) == "0X" then
		return string.sub(hex, 3)
	end
	return hex
end

--- Validate server secret: must be at least 64 hex chars (32 bytes), not all zeros.
local function validateServerSecret(secret: string): ()
	if type(secret) ~= "string" or #secret == 0 then
		error(StarknetError.signing("KeyStore: serverSecret is required", ErrorCodes.KEY_STORE_SECRET_INVALID.code))
	end

	local hex = stripHexPrefix(secret)

	if not string.match(hex, "^[0-9a-fA-F]+$") then
		error(
			StarknetError.signing(
				"KeyStore: serverSecret must be a valid hex string",
				ErrorCodes.KEY_STORE_SECRET_INVALID.code
			)
		)
	end

	if #hex < 64 then
		error(
			StarknetError.signing(
				"KeyStore: serverSecret must be at least 32 bytes (64 hex characters)",
				ErrorCodes.KEY_STORE_SECRET_INVALID.code
			)
		)
	end

	if string.sub(hex, 1, 64) == ALL_ZEROS_64 then
		error(
			StarknetError.signing(
				"KeyStore: serverSecret must not be all zeros",
				ErrorCodes.KEY_STORE_SECRET_INVALID.code
			)
		)
	end
end

--- Generate random bytes using math.random (or injected function).
local function defaultRandomBytes(n: number): buffer
	local buf = buffer.create(n)
	for i = 0, n - 1 do
		buffer.writeu8(buf, i, math.random(0, 255))
	end
	return buf
end

--- Generate a valid Stark private key from random bytes.
--- Returns a hex string (0x-prefixed) in the range [1, N-1].
local function generatePrivateKey(randomBytes: (n: number) -> buffer): string
	local rawBytes = randomBytes(32)
	local rawBigInt = BigInt.fromBytes(rawBytes)

	-- Reduce mod (N-1) then add 1 to get range [1, N-1]
	local nMinusOne = BigInt.sub(StarkCurve.N, BigInt.one())
	local reduced = BigInt.mod(rawBigInt, nMinusOne)
	local privKey = BigInt.add(reduced, BigInt.one())

	return BigInt.toHex(privKey)
end

--- Validate a DataStore record has the expected shape.
local function isValidRecord(data: any): boolean
	return type(data) == "table"
		and type(data.version) == "number"
		and type(data.encrypted) == "string"
		and type(data.address) == "string"
		and type(data.accountType) == "string"
		and type(data.createdAt) == "number"
end

--- Build the DataStore key for a player.
local function playerKey(playerId: number): string
	return "player_" .. tostring(playerId)
end

--------------------------------------------------------------------------------
-- KeyStore class
--------------------------------------------------------------------------------

local KeyStore = {}
KeyStore.__index = KeyStore

--- Create a new KeyStore with encrypted key persistence.
function KeyStore.new(config: KeyStoreConfig): any
	validateServerSecret(config.serverSecret)

	local accountType = config.accountType or "oz"
	if accountType ~= "oz" and accountType ~= "argent" and accountType ~= "braavos" then
		error(
			StarknetError.validation(
				`KeyStore: unsupported accountType "{accountType}", expected "oz", "argent", or "braavos"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local self = setmetatable({
		_secretBuf = hexToBuffer(config.serverSecret),
		_accountType = accountType,
		_dataStore = config._dataStore,
		_clock = config._clock or os.time,
		_randomBytes = config._randomBytes or defaultRandomBytes,
		_dataStoreName = config.dataStoreName or "StarknetKeyStore",
	}, KeyStore)

	return self :: any
end

--- Generate a new keypair, encrypt and store it, return hydrated Account.
function KeyStore:generateAndStore(playerId: number, provider: any): { account: any, address: string }
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end
	if not provider then
		error(StarknetError.validation("KeyStore: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local privateKeyHex = generatePrivateKey(self._randomBytes)

	local account = Account.fromPrivateKey({
		privateKey = privateKeyHex,
		provider = provider,
		accountType = self._accountType,
	})

	local address = account.address

	-- Encrypt private key
	local privKeyBuf = BigInt.toBytes32(BigInt.fromHex(privateKeyHex))
	local encryptedBuf = encryptKey(privKeyBuf, self._secretBuf, playerId)
	local encryptedHex = bufferToHex(encryptedBuf)

	local record: KeyStoreRecord = {
		version = 1,
		encrypted = encryptedHex,
		address = address,
		accountType = self._accountType,
		createdAt = self._clock(),
	}

	if self._dataStore then
		local ok, err = pcall(function()
			self._dataStore:SetAsync(playerKey(playerId), record, { playerId })
		end)
		if not ok then
			error(
				StarknetError.signing(
					`KeyStore: failed to persist key for player {playerId}`,
					ErrorCodes.KEY_STORE_ERROR.code,
					{ cause = tostring(err) }
				)
			)
		end
	end

	return { account = account, address = address }
end

--- Load an existing account from encrypted DataStore key.
--- Returns nil if no key exists for this player.
function KeyStore:loadAccount(playerId: number, provider: any): any?
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end
	if not provider then
		error(StarknetError.validation("KeyStore: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	if not self._dataStore then
		return nil
	end

	local record
	local ok, err = pcall(function()
		record = self._dataStore:GetAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to load key for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end

	if record == nil then
		return nil
	end

	if not isValidRecord(record) then
		error(
			StarknetError.signing(
				`KeyStore: corrupted record for player {playerId}`,
				ErrorCodes.KEY_STORE_DECRYPT_ERROR.code
			)
		)
	end

	-- Decrypt private key
	local encryptedBuf = hexToBuffer(record.encrypted)
	if buffer.len(encryptedBuf) ~= 32 then
		error(
			StarknetError.signing(
				`KeyStore: encrypted key has invalid length for player {playerId}`,
				ErrorCodes.KEY_STORE_DECRYPT_ERROR.code
			)
		)
	end

	local privKeyBuf = decryptKey(encryptedBuf, self._secretBuf, playerId)
	local privKeyHex = BigInt.toHex(BigInt.fromBytes(privKeyBuf))

	-- Validate decrypted key is in valid range [1, N-1]
	local privKeyBigInt = BigInt.fromHex(privKeyHex)
	if BigInt.isZero(privKeyBigInt) or BigInt.cmp(privKeyBigInt, StarkCurve.N) >= 0 then
		error(
			StarknetError.signing(
				`KeyStore: decrypted key is out of range for player {playerId}`,
				ErrorCodes.KEY_STORE_DECRYPT_ERROR.code
			)
		)
	end

	local accountType = record.accountType or self._accountType
	return Account.fromPrivateKey({
		privateKey = privKeyHex,
		provider = provider,
		accountType = accountType,
	})
end

--- Load existing account or generate + store a new one.
--- Primary onboarding API for PlayerAdded.
function KeyStore:getOrCreate(playerId: number, provider: any): { account: any, isNew: boolean }
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end
	if not provider then
		error(StarknetError.validation("KeyStore: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local account = self:loadAccount(playerId, provider)
	if account then
		return { account = account, isNew = false }
	end

	local result = self:generateAndStore(playerId, provider)
	return { account = result.account, isNew = true }
end

--- Check if a player has a stored account (reads address field only, no decryption).
function KeyStore:hasAccount(playerId: number): boolean
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end

	if not self._dataStore then
		return false
	end

	local record
	local ok, err = pcall(function()
		record = self._dataStore:GetAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to check account for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end

	return record ~= nil and type(record) == "table" and type(record.address) == "string"
end

--- Delete a player's key from DataStore (GDPR Right to Erasure).
--- Uses RemoveAsync for full removal.
function KeyStore:deleteKey(playerId: number): ()
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end

	if not self._dataStore then
		return
	end

	local ok, err = pcall(function()
		self._dataStore:RemoveAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to delete key for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end
end

--- Re-encrypt specified player keys with a new server secret.
--- Returns summary of rotated and failed keys.
function KeyStore:rotateSecret(
	oldSecret: string,
	newSecret: string,
	playerIds: { number }
): { rotated: number, failed: { { playerId: number, error: string } } }
	validateServerSecret(oldSecret)
	validateServerSecret(newSecret)

	if not self._dataStore then
		error(StarknetError.signing("KeyStore: rotateSecret requires a DataStore", ErrorCodes.KEY_STORE_ERROR.code))
	end

	local oldSecretBuf = hexToBuffer(oldSecret)
	local newSecretBuf = hexToBuffer(newSecret)

	local rotated = 0
	local failed: { { playerId: number, error: string } } = {}

	for _, playerId in playerIds do
		local ok, err = pcall(function()
			local record = self._dataStore:GetAsync(playerKey(playerId))
			if record == nil then
				error("no key found")
			end
			if not isValidRecord(record) then
				error("corrupted record")
			end

			-- Decrypt with old secret
			local encryptedBuf = hexToBuffer(record.encrypted)
			local privKeyBuf = decryptKey(encryptedBuf, oldSecretBuf, playerId)

			-- Re-encrypt with new secret
			local newEncryptedBuf = encryptKey(privKeyBuf, newSecretBuf, playerId)
			record.encrypted = bufferToHex(newEncryptedBuf)

			self._dataStore:SetAsync(playerKey(playerId), record, { playerId })
		end)

		if ok then
			rotated += 1
		else
			table.insert(failed, { playerId = playerId, error = tostring(err) })
		end
	end

	-- Update internal secret buffer to new secret
	self._secretBuf = newSecretBuf

	return { rotated = rotated, failed = failed }
end

--- Read a player's record metadata without decryption.
--- Returns nil if no record exists.
function KeyStore:getRecord(playerId: number): KeyStoreRecord?
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end

	if not self._dataStore then
		return nil
	end

	local record
	local ok, err = pcall(function()
		record = self._dataStore:GetAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to read record for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end

	if record == nil or not isValidRecord(record) then
		return nil
	end

	return record :: KeyStoreRecord
end

--- Mark a player's account as deployed by setting the deployedAt timestamp.
--- Idempotent: no-op if already marked or no record exists.
function KeyStore:markDeployed(playerId: number): ()
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end

	if not self._dataStore then
		return
	end

	local record
	local ok, err = pcall(function()
		record = self._dataStore:GetAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to read record for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end

	if record == nil or not isValidRecord(record) then
		return
	end

	-- Idempotent: skip if already marked
	if record.deployedAt ~= nil then
		return
	end

	record.deployedAt = self._clock()

	local setOk, setErr = pcall(function()
		self._dataStore:SetAsync(playerKey(playerId), record, { playerId })
	end)
	if not setOk then
		error(
			StarknetError.signing(
				`KeyStore: failed to mark deployed for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(setErr) }
			)
		)
	end
end

--- Check if a player's account has been marked as deployed.
--- No decryption, no network. Returns false if no record or unset.
function KeyStore:isDeployed(playerId: number): boolean
	if type(playerId) ~= "number" then
		error(StarknetError.validation("KeyStore: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code))
	end

	if not self._dataStore then
		return false
	end

	local record
	local ok, err = pcall(function()
		record = self._dataStore:GetAsync(playerKey(playerId))
	end)
	if not ok then
		error(
			StarknetError.signing(
				`KeyStore: failed to check deployment for player {playerId}`,
				ErrorCodes.KEY_STORE_ERROR.code,
				{ cause = tostring(err) }
			)
		)
	end

	if record == nil or type(record) ~= "table" then
		return false
	end

	return record.deployedAt ~= nil
end

return KeyStore
