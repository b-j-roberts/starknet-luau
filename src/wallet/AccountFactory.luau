--!strict
-- AccountFactory: Factory for creating deployable Starknet accounts
-- Encapsulates provider, account type, and signer to produce pre-deployment Account instances.
--
-- Usage:
--   local factory = AccountFactory.new(provider, AccountType.OZ, signer)
--   local result = factory:createAccount()
--   -- result.account: pre-deployment Account instance
--   -- result.address: counterfactual address (hex string)
--   -- result.deployTx(): convenience function to deploy the account
--
-- For Argent accounts with a guardian:
--   local factory = AccountFactory.new(provider, AccountType.Argent, signer)
--   local result = factory:createAccount({ guardian = "0xguardianPubKey" })

local Account = require("./Account")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

local AccountFactory = {}
AccountFactory.__index = AccountFactory

--- Create a new AccountFactory.
--- @param provider — RpcProvider instance for blockchain interaction
--- @param accountType — Account type config (e.g., AccountType.OZ, AccountType.Argent, or AccountType.custom(...))
--- @param signer — StarkSigner instance for signing transactions
function AccountFactory.new(provider: any, accountType: any, signer: any): any
	if not provider then
		error(StarknetError.validation("AccountFactory: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not accountType then
		error(StarknetError.validation("AccountFactory: accountType is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not accountType.type or not accountType.classHash then
		error(
			StarknetError.validation(
				"AccountFactory: accountType must have 'type' and 'classHash' fields",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end
	if not signer then
		error(StarknetError.validation("AccountFactory: signer is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	return setmetatable({
		_provider = provider,
		_accountType = accountType,
		_signer = signer,
	}, AccountFactory)
end

--- Create a pre-deployment Account instance with its counterfactual address.
--- Returns { account, address, deployTx } where:
---   account: Account instance (not yet deployed on-chain)
---   address: hex string of the counterfactual contract address
---   deployTx: function(options?) that deploys the account (calls account:deployAccount)
---
--- Options:
---   classHash: string? — Override the default class hash from the account type
---   salt: string? — Custom address salt (defaults to public key)
---   guardian: string? — Guardian public key for Argent accounts (defaults to no guardian)
function AccountFactory:createAccount(options: {
	classHash: string?,
	salt: string?,
	guardian: string?,
}?): {
	account: any,
	address: string,
	deployTx: (any?) -> any,
}
	local opts = options or {}
	local publicKey = self._signer:getPublicKeyHex()
	local classHash = opts.classHash or self._accountType.classHash
	local salt = opts.salt or publicKey

	-- Build constructor calldata via the account type's __call
	local calldata: { string }
	if self._accountType.type == "argent" then
		calldata = self._accountType(publicKey, opts.guardian)
	else
		calldata = self._accountType(publicKey)
	end

	-- Compute counterfactual address
	local address = Account.computeAddress({
		classHash = classHash,
		publicKey = publicKey,
		salt = salt,
		constructorCalldata = calldata,
	})

	-- Create pre-deployment Account instance
	local account = Account.new({
		address = address,
		signer = self._signer,
		provider = self._provider,
		accountType = self._accountType.type,
		classHash = classHash,
		constructorCalldata = calldata,
	})

	return {
		account = account,
		address = address,
		deployTx = function(deployOptions: any?): any
			return account:deployAccount(deployOptions)
		end,
	}
end

return AccountFactory
