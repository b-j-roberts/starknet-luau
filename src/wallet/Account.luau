--!strict
-- Account: High-level account management combining signer, provider, and address
-- Provides convenience methods for executing transactions, fetching nonce, and estimating fees
-- Supports address derivation from private key using OpenZeppelin class hash
-- Reference: starknet.js Account class and hash.calculateContractAddressFromHash

local BigInt = require("../crypto/BigInt")
local StarkField = require("../crypto/StarkField")
local Pedersen = require("../crypto/Pedersen")
local StarkSigner = require("../signer/StarkSigner")
local TransactionBuilder = require("../tx/TransactionBuilder")

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

-- OpenZeppelin Account class hash constants (Cairo 1)
Account.OZ_CLASS_HASH = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

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

--- Create an Account from an explicit address, signer, and provider.
function Account.new(config: {
	address: string,
	signer: any,
	provider: any,
}): any
	if not config.address then
		error("Account: address is required")
	end
	if not config.signer then
		error("Account: signer is required")
	end
	if not config.provider then
		error("Account: provider is required")
	end

	local self = setmetatable({
		address = config.address,
		signer = config.signer,
		_provider = config.provider,
		_builder = TransactionBuilder.new(config.provider),
	}, Account)

	return self
end

--- Create an Account from a private key, deriving the address using the given class hash.
--- Defaults to OpenZeppelin account class hash.
function Account.fromPrivateKey(config: {
	privateKey: string,
	provider: any,
	classHash: string?,
}): any
	if not config.privateKey then
		error("Account: privateKey is required")
	end
	if not config.provider then
		error("Account: provider is required")
	end

	local signer = StarkSigner.new(config.privateKey)
	local publicKeyHex = signer:getPublicKeyHex()
	local classHash = config.classHash or Account.OZ_CLASS_HASH

	local address = Account.computeAddress({
		classHash = classHash,
		publicKey = publicKeyHex,
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

return Account
