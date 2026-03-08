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
--
-- Batch operations for game onboarding:
--   local accounts = factory:batchCreate(10, { keyGenerator = myKeyGen })
--   local report = factory:batchDeploy(accounts, { onDeployProgress = callback }):expect()

local Account = require("./Account")
local StarkSigner = require("../signer/StarkSigner")
local Interfaces = require("../shared/interfaces")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

local MAX_BATCH_SIZE = 100

--- Build a deploy result entry and update summary counters.
local function buildDeployResult(
	summary: { deployed: number, failed: number, skipped: number, results: { any } },
	index: number,
	address: string,
	ok: boolean,
	deployResult: any
): any
	local resultEntry: any
	if ok then
		if deployResult.alreadyDeployed then
			summary.skipped += 1
			resultEntry = { index = index, address = address, transactionHash = "0x0", status = "skipped" }
		else
			summary.deployed += 1
			resultEntry = {
				index = index,
				address = address,
				transactionHash = deployResult.transactionHash,
				status = "deployed",
			}
		end
	else
		summary.failed += 1
		resultEntry = { index = index, address = address, error = deployResult, status = "failed" }
	end
	table.insert(summary.results, resultEntry)
	return resultEntry
end

local AccountFactory = {}
AccountFactory.__index = AccountFactory

--- Create a new AccountFactory.
--- @param provider — RpcProvider instance for blockchain interaction
--- @param accountType — Account type config (e.g., AccountType.OZ, AccountType.Argent, or AccountType.custom(...))
--- @param signer — StarkSigner instance for signing transactions
function AccountFactory.new(
	provider: Interfaces.ProviderInterface,
	accountType: any,
	signer: Interfaces.SignerInterface
): any
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

--- Internal: create an account entry from a signer instance.
--- Reuses the factory's account type and provider but with the given signer.
function AccountFactory:_createAccountFromSigner(
	signer: any,
	options: {
		classHash: string?,
		salt: string?,
		guardian: string?,
	}?
): {
	account: any,
	address: string,
	signer: any,
	deployTx: (any?) -> any,
}
	local opts = options or {}
	local publicKey = signer:getPublicKeyHex()
	local classHash = opts.classHash or self._accountType.classHash
	local salt = opts.salt or publicKey

	local calldata: { string } = self._accountType(publicKey, opts.guardian)

	local address = Account.computeAddress({
		classHash = classHash,
		publicKey = publicKey,
		salt = salt,
		constructorCalldata = calldata,
	})

	local account = Account.new({
		address = address,
		signer = signer,
		provider = self._provider,
		accountType = self._accountType.type,
		classHash = classHash,
		constructorCalldata = calldata,
	})

	return {
		account = account,
		address = address,
		signer = signer,
		deployTx = function(deployOptions: any?): any
			return account:deployAccount(deployOptions)
		end,
	}
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
	local result = self:_createAccountFromSigner(self._signer, options)
	return {
		account = result.account,
		address = result.address,
		deployTx = result.deployTx,
	}
end

--- Create multiple pre-deployment Account instances, each with a unique key pair.
--- Returns an array of { account, address, signer, deployTx } entries.
---
--- Options:
---   privateKeys: {string}? — Explicit hex private keys (must match count)
---   keyGenerator: (() -> string)? — Callable that returns a hex private key (called count times)
---   classHash: string? — Override the default class hash from the account type
---   guardian: string? — Guardian public key for Argent accounts
---
--- One of privateKeys or keyGenerator must be provided.
function AccountFactory:batchCreate(
	count: number,
	options: {
		privateKeys: { string }?,
		keyGenerator: (() -> string)?,
		classHash: string?,
		guardian: string?,
	}?
): {
	{
		account: any,
		address: string,
		signer: any,
		deployTx: (any?) -> any,
	}
}
	local opts = options or {}

	-- Validate count
	if type(count) ~= "number" or count < 1 then
		error(
			StarknetError.validation("batchCreate: count must be a positive integer", ErrorCodes.INVALID_ARGUMENT.code)
		)
	end
	if count ~= math.floor(count) then
		error(
			StarknetError.validation("batchCreate: count must be a positive integer", ErrorCodes.INVALID_ARGUMENT.code)
		)
	end
	if count > MAX_BATCH_SIZE then
		error(
			StarknetError.validation(
				`batchCreate: count ({count}) exceeds maximum batch size ({MAX_BATCH_SIZE})`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	-- Validate key source
	local privateKeys = opts.privateKeys
	local keyGenerator = opts.keyGenerator

	if not privateKeys and not keyGenerator then
		error(
			StarknetError.validation(
				"batchCreate: one of privateKeys or keyGenerator must be provided",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	if privateKeys and keyGenerator then
		error(
			StarknetError.validation(
				"batchCreate: provide either privateKeys or keyGenerator, not both",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	if privateKeys then
		if #privateKeys ~= count then
			error(
				StarknetError.validation(
					`batchCreate: privateKeys length ({#privateKeys}) must match count ({count})`,
					ErrorCodes.INVALID_ARGUMENT.code
				)
			)
		end
	end

	-- Create accounts
	local results = {}
	for i = 1, count do
		local key: string
		if privateKeys then
			key = privateKeys[i]
		else
			key = (keyGenerator :: () -> string)()
		end

		local signer = StarkSigner.new(key)
		local entry = self:_createAccountFromSigner(signer, {
			classHash = opts.classHash,
			guardian = opts.guardian,
		})
		table.insert(results, entry)
	end

	return results
end

--- Deploy multiple accounts with rate limit integration, progress callbacks, and error tolerance.
--- Returns a Promise resolving to a summary report.
---
--- Options:
---   maxConcurrency: number? — Max parallel deploys (default 1 = sequential)
---   onDeployProgress: ((index, total, result) -> ())? — Called after each deploy attempt
---   waitForConfirmation: boolean? — Wait for on-chain confirmation (default true)
---   dryRun: boolean? — Build + sign without submitting (default false)
---   maxFee: string? — Maximum fee cap per deployment
---   feeMultiplier: number? — Fee estimation multiplier
function AccountFactory:batchDeploy(
	accounts: {
		{
			account: any,
			address: string,
		}
	},
	options: {
		maxConcurrency: number?,
		onDeployProgress: ((index: number, total: number, result: any) -> ())?,
		waitForConfirmation: boolean?,
		dryRun: boolean?,
		maxFee: string?,
		feeMultiplier: number?,
	}?
): any
	local opts = options or {}
	local maxConcurrency = opts.maxConcurrency or 1

	-- Validate inputs
	if not accounts or #accounts == 0 then
		error(StarknetError.validation("batchDeploy: accounts array must not be empty", ErrorCodes.REQUIRED_FIELD.code))
	end

	if type(maxConcurrency) ~= "number" or maxConcurrency < 1 then
		error(
			StarknetError.validation(
				"batchDeploy: maxConcurrency must be a positive integer",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end
	maxConcurrency = math.floor(maxConcurrency)

	-- Get Promise module from provider
	local Promise = self._provider:getPromise()

	local total = #accounts
	local progressCallback = opts.onDeployProgress
	local deployOpts = {
		waitForConfirmation = if opts.waitForConfirmation ~= nil then opts.waitForConfirmation else true,
		dryRun = opts.dryRun,
		maxFee = opts.maxFee,
		feeMultiplier = opts.feeMultiplier,
	}

	return Promise.new(function(resolve, _reject)
		local summary = {
			deployed = 0,
			failed = 0,
			skipped = 0,
			results = {} :: { any },
		}

		--- Deploy a single account and return its result entry.
		local function deployOne(index: number): any
			local entry = accounts[index]
			local ok, deployResult = pcall(function()
				return entry.account:deployAccount(deployOpts):expect()
			end)
			local resultEntry = buildDeployResult(summary, index, entry.address, ok, deployResult)
			if progressCallback then
				progressCallback(index, total, resultEntry)
			end
			return resultEntry
		end

		if maxConcurrency <= 1 then
			-- Sequential: deploy one at a time
			for i = 1, total do
				deployOne(i)
			end
		else
			-- Parallel: process in batches of maxConcurrency
			for batchStart = 1, total, maxConcurrency do
				local batchEnd = math.min(batchStart + maxConcurrency - 1, total)
				local batchPromises = {}

				for i = batchStart, batchEnd do
					local entryRef = accounts[i]
					local idx = i
					local p = entryRef.account
						:deployAccount(deployOpts)
						:andThen(function(depResult: any)
							local resultEntry = buildDeployResult(summary, idx, entryRef.address, true, depResult)
							if progressCallback then
								progressCallback(idx, total, resultEntry)
							end
							return resultEntry
						end)
						:catch(function(err: any)
							local resultEntry = buildDeployResult(summary, idx, entryRef.address, false, err)
							if progressCallback then
								progressCallback(idx, total, resultEntry)
							end
							-- Resolve (not reject) so Promise.all doesn't abort the batch
							return resultEntry
						end)
					table.insert(batchPromises, p)
				end

				-- Wait for this batch to complete before starting the next
				Promise.all(batchPromises):expect()
			end
		end

		resolve(summary)
	end)
end

return AccountFactory
