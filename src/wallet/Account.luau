--!strict
-- Account: High-level account management combining signer, provider, and address
-- Provides convenience methods for executing transactions, fetching nonce, and estimating fees
-- Supports address derivation from private key for OpenZeppelin, Argent X, and Braavos accounts
-- Reference: starknet.js Account class and hash.calculateContractAddressFromHash

local BigInt = require("../crypto/BigInt")
local StarkField = require("../crypto/StarkField")
local Pedersen = require("../crypto/Pedersen")
local StarkSigner = require("../signer/StarkSigner")
local TransactionBuilder = require("../tx/TransactionBuilder")
local TypedData = require("./TypedData")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

type Felt = StarkField.Felt

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- "STARKNET_CONTRACT_ADDRESS" as felt (ASCII encoding)
local CONTRACT_ADDRESS_PREFIX = "0x535441524b4e45545f434f4e54524143545f41444452455353"

-- 2^251 - 1 mask for address computation
local MASK_251 = BigInt.sub(BigInt.shl(BigInt.one(), 251), BigInt.one())

--------------------------------------------------------------------------------
-- Account class
--------------------------------------------------------------------------------

local Account = {}
Account.__index = Account

-- Account type constants
Account.ACCOUNT_TYPE_OZ = "oz"
Account.ACCOUNT_TYPE_ARGENT = "argent"
Account.ACCOUNT_TYPE_BRAAVOS = "braavos"

-- OpenZeppelin Account class hash (Cairo 1)
Account.OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

-- Argent X Account class hash (Cairo 1, v0.4.0)
Account.ARGENT_CLASS_HASH = "0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"

-- Braavos Account implementation class hash (v1.2.0)
Account.BRAAVOS_CLASS_HASH = "0x03957f9f5a1cbfe918cedc2015c85200ca51a5f7506ecb6de98a5207b759bf8a"

-- Braavos Base Account class hash (used for address computation, v1.2.0)
Account.BRAAVOS_BASE_CLASS_HASH = "0x03d16c7a9a60b0593bd202f660a28c5d76e0403601d9ccc7e4fa253b6a70c201"

-- Lookup table: normalized class hash -> account type (includes historical versions)
-- Keys are normalized (no leading zeros after 0x) to match BigInt.toHex output
local CLASS_HASH_TO_TYPE: { [string]: string } = {
	-- OpenZeppelin
	["0x61dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"] = "oz",
	["0x1a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003"] = "oz", -- OZ v0.14

	-- Argent X
	["0x36078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f"] = "argent", -- v0.4.0
	["0x29927c8af6bccf3f6fda035981e765a7bdbf18a2dc0d630494f8758aa908e2b"] = "argent", -- v0.3.1

	-- Braavos
	["0x3d16c7a9a60b0593bd202f660a28c5d76e0403601d9ccc7e4fa253b6a70c201"] = "braavos", -- Base v1.2.0
	["0x3957f9f5a1cbfe918cedc2015c85200ca51a5f7506ecb6de98a5207b759bf8a"] = "braavos", -- Impl v1.2.0
}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Compute Pedersen hash of elements (equivalent to starknet.js computeHashOnElements).
--- Reduces [e1, e2, ..., en] as: pedersen(pedersen(...pedersen(pedersen(0, e1), e2)..., en), n)
local function computeHashOnElements(elements: { Felt }): Felt
	local result = StarkField.zero()
	for _, element in elements do
		result = Pedersen.hash(result, element)
	end
	result = Pedersen.hash(result, StarkField.fromNumber(#elements))
	return result
end

--- Build constructor calldata for a given account type.
--- OZ/Braavos: [publicKey]
--- Argent (v0.4.0+): [0, publicKey, 0] without guardian, [0, publicKey, 1, 0, guardianKey] with guardian
--- The format uses Cairo enum serialization: Signer::Starknet(pubkey) = [0, pubkey], Option::None = [0], Option::Some(signer) = [1, 0, guardianKey]
local function buildConstructorCalldata(accountType: string, publicKey: string, guardian: string?): { string }
	if accountType == "argent" then
		if guardian then
			-- [Signer::Starknet variant=0, publicKey, Option::Some variant=1, Signer::Starknet variant=0, guardianKey]
			return { "0x0", publicKey, "0x1", "0x0", guardian }
		else
			-- [Signer::Starknet variant=0, publicKey, Option::None variant=0]
			return { "0x0", publicKey, "0x0" }
		end
	end
	-- OZ and Braavos both use [publicKey]
	return { publicKey }
end

--- Get the default class hash for an account type.
--- Braavos uses the base class hash for address computation.
local function getDefaultClassHash(accountType: string): string
	if accountType == "argent" then
		return Account.ARGENT_CLASS_HASH
	elseif accountType == "braavos" then
		return Account.BRAAVOS_BASE_CLASS_HASH
	end
	return Account.OZ_CLASS_HASH
end

--------------------------------------------------------------------------------
-- Static methods
--------------------------------------------------------------------------------

--- Compute a contract address from deployment parameters.
--- Formula: pedersen(["STARKNET_CONTRACT_ADDRESS", deployer, salt, classHash,
---          pedersen(constructorCalldata)]) mod 2^251
--- For OZ accounts: constructorCalldata = [publicKey], salt = publicKey, deployer = 0
function Account.computeAddress(config: {
	classHash: string,
	publicKey: string,
	deployer: string?,
	salt: string?,
	constructorCalldata: { string }?,
}): string
	local publicKeyFelt = StarkField.fromHex(config.publicKey)
	local classHashFelt = StarkField.fromHex(config.classHash)
	local deployerFelt = if config.deployer then StarkField.fromHex(config.deployer) else StarkField.zero()
	local saltFelt = if config.salt then StarkField.fromHex(config.salt) else publicKeyFelt

	-- Constructor calldata: defaults to [publicKey] for OZ accounts
	local calldataFelts: { Felt }
	if config.constructorCalldata then
		calldataFelts = {}
		for _, hex in config.constructorCalldata do
			table.insert(calldataFelts, StarkField.fromHex(hex))
		end
	else
		calldataFelts = { publicKeyFelt }
	end

	local calldataHash = computeHashOnElements(calldataFelts)

	local addressHash = computeHashOnElements({
		StarkField.fromHex(CONTRACT_ADDRESS_PREFIX),
		deployerFelt,
		saltFelt,
		classHashFelt,
		calldataHash,
	})

	-- Mask to 251 bits
	local addressBigInt = BigInt.band(StarkField.toBigInt(addressHash), MASK_251)
	return BigInt.toHex(addressBigInt)
end

--- Detect account type from a class hash.
--- Returns "oz", "argent", "braavos", or nil if the class hash is not recognized.
function Account.detectAccountType(classHash: string): string?
	-- Normalize the class hash (strip leading zeros after 0x prefix for consistent lookup)
	local normalized = BigInt.toHex(BigInt.fromHex(classHash))
	return CLASS_HASH_TO_TYPE[normalized]
end

--- Build constructor calldata for an account type (exposed for advanced use).
function Account.getConstructorCalldata(accountType: string, publicKey: string, guardian: string?): { string }
	return buildConstructorCalldata(accountType, publicKey, guardian)
end

--- Create an Account from an explicit address, signer, and provider.
function Account.new(config: {
	address: string,
	signer: any,
	provider: any,
}): any
	if not config.address then
		error(StarknetError.validation("Account: address is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.signer then
		error(StarknetError.validation("Account: signer is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.provider then
		error(StarknetError.validation("Account: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local self = setmetatable({
		address = config.address,
		signer = config.signer,
		_provider = config.provider,
		_builder = TransactionBuilder.new(config.provider),
	}, Account)

	return self
end

--- Create an Account from a private key, deriving the address.
--- Supports "oz" (default), "argent", and "braavos" account types.
--- For Argent, an optional guardian public key can be provided.
function Account.fromPrivateKey(config: {
	privateKey: string,
	provider: any,
	accountType: string?,
	classHash: string?,
	guardian: string?,
}): any
	if not config.privateKey then
		error(StarknetError.validation("Account: privateKey is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.provider then
		error(StarknetError.validation("Account: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local accountType = config.accountType or "oz"
	if accountType ~= "oz" and accountType ~= "argent" and accountType ~= "braavos" then
		error(
			StarknetError.validation(
				`Account: unsupported accountType "{accountType}", expected "oz", "argent", or "braavos"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	if config.guardian and accountType ~= "argent" then
		error(
			StarknetError.validation(
				"Account: guardian is only supported for Argent accounts",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local signer = StarkSigner.new(config.privateKey)
	local publicKeyHex = signer:getPublicKeyHex()
	local classHash = config.classHash or getDefaultClassHash(accountType)
	local constructorCalldata = buildConstructorCalldata(accountType, publicKeyHex, config.guardian)

	local address = Account.computeAddress({
		classHash = classHash,
		publicKey = publicKeyHex,
		constructorCalldata = constructorCalldata,
	})

	return Account.new({
		address = address,
		signer = signer,
		provider = config.provider,
	})
end

--------------------------------------------------------------------------------
-- Instance methods
--------------------------------------------------------------------------------

--- Execute calls via the internal TransactionBuilder.
--- Returns a Promise resolving to { transactionHash: string }.
function Account:execute(calls: { TransactionBuilder.Call }, options: TransactionBuilder.ExecuteOptions?): any
	return self._builder:execute({
		address = self.address,
		signer = self.signer,
	}, calls, options)
end

--- Fetch the current nonce from the provider.
--- Returns a Promise resolving to a hex string.
function Account:getNonce(): any
	return self._provider:getNonce(self.address)
end

--- Estimate the fee for a set of calls.
--- Returns a Promise resolving to the fee estimate.
function Account:estimateFee(calls: { TransactionBuilder.Call }): any
	return self._builder:estimateFee({
		address = self.address,
		signer = self.signer,
	}, calls)
end

--- Wait for a transaction receipt by polling the provider.
--- Returns a Promise resolving to the transaction receipt.
function Account:waitForReceipt(txHash: string, options: TransactionBuilder.WaitOptions?): any
	return self._builder:waitForReceipt(txHash, options)
end

--- Get the public key hex of the signer.
function Account:getPublicKeyHex(): string
	return self.signer:getPublicKeyHex()
end

--- Compute the SNIP-12 message hash for a typed data object.
--- Returns the hex string hash that would be signed.
function Account:hashMessage(typedData: { [string]: any }): string
	return TypedData.getMessageHash(typedData, self.address)
end

--- Sign a SNIP-12 typed data message.
--- Returns { r_hex, s_hex } signature array.
function Account:signMessage(typedData: { [string]: any }): { string }
	local msgHash = self:hashMessage(typedData)
	local hashBuf = BigInt.fromHex(msgHash)
	local sig = self.signer:signRaw(hashBuf)
	return { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }
end

return Account
