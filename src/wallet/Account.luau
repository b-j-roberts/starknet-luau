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
local AccountType = require("./AccountType")
local TypedData = require("./TypedData")
local OutsideExecution = require("./OutsideExecution")
local ERC20 = require("../contract/ERC20")
local Constants = require("../constants")
local Interfaces = require("../shared/interfaces")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

type Felt = StarkField.Felt

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

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

--- Alias for Pedersen.hashChain (computeHashOnElements).
local computeHashOnElements = Pedersen.hashChain

--- Get the default class hash for an account type via AccountType registry.
local function getDefaultClassHash(accountType: string): string
	local typeObj = AccountType.get(accountType)
	if typeObj then
		return typeObj.classHash
	end
	return AccountType.OZ.classHash
end

--- Build constructor calldata for a given account type via AccountType registry.
local function buildConstructorCalldata(accountType: string, publicKey: string, guardian: string?): { string }
	local typeObj = AccountType.get(accountType)
	if typeObj then
		return typeObj(publicKey, guardian)
	end
	return AccountType.OZ(publicKey)
end

--- Validate paymaster details and resolve gas token address.
--- Returns { paymaster, gasTokenAddress, feeMode } or throws a ValidationError.
local function validatePaymasterDetails(
	methodName: string,
	paymasterDetails: Interfaces.PaymasterDetails
): {
	paymaster: Interfaces.PaymasterInterface,
	gasTokenAddress: string,
	feeMode: { mode: string, gasToken: string? },
}
	if not paymasterDetails or not paymasterDetails.paymaster then
		error(
			StarknetError.validation(
				`{methodName}: paymaster is required in paymasterDetails`,
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end
	if not paymasterDetails.feeMode then
		error(
			StarknetError.validation(
				`{methodName}: feeMode is required in paymasterDetails`,
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	local feeMode = paymasterDetails.feeMode
	if feeMode.mode ~= "sponsored" and feeMode.mode ~= "default" then
		error(
			StarknetError.validation(
				`{methodName}: invalid feeMode.mode "{feeMode.mode}", expected "sponsored" or "default"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end
	if feeMode.mode == "default" and not feeMode.gasToken then
		error(
			StarknetError.validation(
				`{methodName}: gasToken is required for 'default' feeMode`,
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	local gasTokenAddress = if feeMode.mode == "sponsored" then "0x0" else feeMode.gasToken

	return {
		paymaster = paymasterDetails.paymaster,
		gasTokenAddress = gasTokenAddress,
		feeMode = feeMode,
	}
end

--- Validate that returned calls from a paymaster match the submitted calls.
--- Throws a PaymasterError if validation fails.
local function validatePaymasterCalls(submittedCalls: { any }, typedData: { [string]: any }): ()
	local submittedOutsideCalls: { { [string]: any } } = {}
	for _, call in submittedCalls do
		table.insert(submittedOutsideCalls, OutsideExecution.getOutsideCall(call))
	end

	local rawReturnedCalls = typedData.message.Calls or typedData.message.calls or {}
	local returnedCalls: { { [string]: any } } = {}
	for _, rc in rawReturnedCalls do
		table.insert(returnedCalls, {
			to = rc.To or rc.to or rc.contractAddress,
			selector = rc.Selector or rc.selector,
			calldata = rc.Calldata or rc.calldata or {},
		})
	end

	local valid = OutsideExecution.validateCalls(submittedOutsideCalls, returnedCalls)
	if not valid then
		error(
			StarknetError.new(
				"returned calls from paymaster do not match submitted calls",
				ErrorCodes.PAYMASTER_CALL_VALIDATION_FAILED.code,
				"PaymasterError"
			)
		)
	end
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
		StarkField.fromHex(Constants.CONTRACT_ADDRESS_PREFIX),
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

--- Estimate the fee required to deploy a new account.
--- This is a static method (no signer needed) — uses a dummy signer internally.
--- Returns a Promise resolving to { estimatedFee, gasConsumed, gasPrice, rawEstimate }.
function Account.getDeploymentFeeEstimate(config: {
	classHash: string,
	constructorCalldata: { string },
	salt: string,
	contractAddress: string,
	provider: Interfaces.ProviderInterface,
	feeMultiplier: number?,
}): any
	if not config.provider then
		error(
			StarknetError.validation("getDeploymentFeeEstimate: provider is required", ErrorCodes.REQUIRED_FIELD.code)
		)
	end
	if not config.classHash then
		error(
			StarknetError.validation("getDeploymentFeeEstimate: classHash is required", ErrorCodes.REQUIRED_FIELD.code)
		)
	end
	if not config.contractAddress then
		error(
			StarknetError.validation(
				"getDeploymentFeeEstimate: contractAddress is required",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	local builder = TransactionBuilder.new(config.provider)
	local params: TransactionBuilder.DeployAccountParams = {
		classHash = config.classHash,
		constructorCalldata = config.constructorCalldata or {},
		addressSalt = config.salt or "0x0",
		contractAddress = config.contractAddress,
	}

	local Promise = config.provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Use dummy account (estimateDeployAccountFee doesn't need a real signer)
		local dummyAccount = {
			address = config.contractAddress,
			signer = {
				signHash = function(_self: any, _hash: buffer): { string }
					return { "0x0", "0x0" }
				end,
			},
		}

		local ok, estimate = pcall(function()
			return builder:estimateDeployAccountFee(dummyAccount, params):expect()
		end)
		if not ok then
			reject(estimate)
			return
		end

		-- Apply fee multiplier to overall_fee
		local multiplier = config.feeMultiplier or 1.5
		local overallFee = estimate.overall_fee or "0x0"
		local feeBig = BigInt.fromHex(overallFee)
		local scale = 100
		local numerator = math.floor(multiplier * scale + 0.5)
		local estimated = BigInt.div(BigInt.mul(feeBig, BigInt.fromNumber(numerator)), BigInt.fromNumber(scale))

		resolve({
			estimatedFee = BigInt.toHex(estimated),
			gasConsumed = estimate.gas_consumed or "0x0",
			gasPrice = estimate.gas_price or "0x0",
			rawEstimate = estimate,
		})
	end)
end

--- Check whether a counterfactual address has sufficient balance for deployment.
--- Returns a Promise resolving to { hasSufficientBalance, balance, estimatedFee, token, deficit? }.
function Account.checkDeploymentBalance(config: {
	address: string,
	classHash: string,
	constructorCalldata: { string },
	salt: string,
	provider: Interfaces.ProviderInterface,
	feeMultiplier: number?,
	token: string?,
}): any
	if not config.provider then
		error(StarknetError.validation("checkDeploymentBalance: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.address then
		error(StarknetError.validation("checkDeploymentBalance: address is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.classHash then
		error(StarknetError.validation("checkDeploymentBalance: classHash is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local token = config.token or "STRK"
	local tokenAddress: string
	if token == "STRK" then
		tokenAddress = Constants.STRK_TOKEN_ADDRESS
	elseif token == "ETH" then
		tokenAddress = Constants.ETH_TOKEN_ADDRESS
	else
		error(
			StarknetError.validation(
				`checkDeploymentBalance: unsupported token "{token}", expected "STRK" or "ETH"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local Promise = config.provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Fetch balance via ERC20
		local erc20 = ERC20.new(tokenAddress, config.provider)
		local balOk, balResult = pcall(function()
			return erc20:balance_of(config.address):expect()
		end)
		if not balOk then
			reject(balResult)
			return
		end

		-- Convert u256 balance to BigInt
		local balanceBigInt: buffer
		if type(balResult) == "table" and balResult.low ~= nil then
			balanceBigInt = BigInt.fromU256(balResult)
		else
			-- Fallback: single felt result
			balanceBigInt = BigInt.fromHex(tostring(balResult))
		end

		-- Estimate deployment fee
		local feeOk, feeResult = pcall(function()
			return Account.getDeploymentFeeEstimate({
				classHash = config.classHash,
				constructorCalldata = config.constructorCalldata or {},
				salt = config.salt or "0x0",
				contractAddress = config.address,
				provider = config.provider,
				feeMultiplier = config.feeMultiplier,
			}):expect()
		end)
		if not feeOk then
			reject(feeResult)
			return
		end

		local estimatedFeeBigInt = BigInt.fromHex(feeResult.estimatedFee)
		local hasSufficient = BigInt.cmp(balanceBigInt, estimatedFeeBigInt) >= 0

		local result: { [string]: any } = {
			hasSufficientBalance = hasSufficient,
			balance = BigInt.toHex(balanceBigInt),
			estimatedFee = feeResult.estimatedFee,
			token = token,
		}

		if not hasSufficient then
			local deficit = BigInt.sub(estimatedFeeBigInt, balanceBigInt)
			result.deficit = BigInt.toHex(deficit)
		end

		resolve(result)
	end)
end

--- Get all deployment funding info for a new account (the "give this to your backend" method).
--- Computes the counterfactual address, estimates deployment cost, and returns all info needed to fund.
--- Returns a Promise resolving to { address, estimatedFee, token, tokenAddress, classHash, constructorCalldata, salt }.
function Account.getDeploymentFundingInfo(config: {
	publicKey: string,
	provider: Interfaces.ProviderInterface,
	classHash: string?,
	accountType: string?,
	guardian: string?,
	salt: string?,
	feeMultiplier: number?,
}): any
	if not config.provider then
		error(
			StarknetError.validation("getDeploymentFundingInfo: provider is required", ErrorCodes.REQUIRED_FIELD.code)
		)
	end
	if not config.publicKey then
		error(
			StarknetError.validation("getDeploymentFundingInfo: publicKey is required", ErrorCodes.REQUIRED_FIELD.code)
		)
	end

	local accountType = config.accountType or "oz"
	if accountType ~= "oz" and accountType ~= "argent" and accountType ~= "braavos" then
		error(
			StarknetError.validation(
				`getDeploymentFundingInfo: unsupported accountType "{accountType}", expected "oz", "argent", or "braavos"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local classHash = config.classHash or getDefaultClassHash(accountType)
	local constructorCalldata = buildConstructorCalldata(accountType, config.publicKey, config.guardian)
	local salt = config.salt or config.publicKey

	local address = Account.computeAddress({
		classHash = classHash,
		publicKey = config.publicKey,
		constructorCalldata = constructorCalldata,
		salt = salt,
	})

	local Promise = config.provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local feeOk, feeResult = pcall(function()
			return Account.getDeploymentFeeEstimate({
				classHash = classHash,
				constructorCalldata = constructorCalldata,
				salt = salt,
				contractAddress = address,
				provider = config.provider,
				feeMultiplier = config.feeMultiplier,
			}):expect()
		end)
		if not feeOk then
			reject(feeResult)
			return
		end

		resolve({
			address = address,
			estimatedFee = feeResult.estimatedFee,
			token = "STRK",
			tokenAddress = Constants.STRK_TOKEN_ADDRESS,
			classHash = classHash,
			constructorCalldata = constructorCalldata,
			salt = salt,
		})
	end)
end

--- Create an Account from an explicit address, signer, and provider.
function Account.new(config: {
	address: string,
	signer: Interfaces.SignerInterface,
	provider: Interfaces.ProviderInterface,
	accountType: string?,
	classHash: string?,
	constructorCalldata: { string }?,
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
		_accountType = config.accountType,
		_classHash = config.classHash,
		_constructorCalldata = config.constructorCalldata,
	}, Account)

	return self
end

--- Create an Account from a private key, deriving the address.
--- Supports "oz" (default), "argent", and "braavos" account types.
--- For Argent, an optional guardian public key can be provided.
function Account.fromPrivateKey(config: {
	privateKey: string,
	provider: Interfaces.ProviderInterface,
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
		accountType = accountType,
		classHash = classHash,
		constructorCalldata = constructorCalldata,
	})
end

--------------------------------------------------------------------------------
-- Internal instance helpers
--------------------------------------------------------------------------------

--- Build DeployAccountParams from stored account config.
--- Shared by deployAccount, estimateDeployAccountFee, getDeploymentData.
function Account:_buildDeployParams(): TransactionBuilder.DeployAccountParams
	local accountType = self._accountType or "oz"
	local publicKeyHex = self.signer:getPublicKeyHex()
	local classHash = self._classHash or getDefaultClassHash(accountType)
	local constructorCalldata = self._constructorCalldata or buildConstructorCalldata(accountType, publicKeyHex)

	return {
		classHash = classHash,
		constructorCalldata = constructorCalldata,
		addressSalt = publicKeyHex,
		contractAddress = self.address,
	}
end

--- Check if this account is already deployed (idempotency guard).
--- Returns a Promise resolving to the early-return result table, or nil if not deployed.
function Account:_checkAlreadyDeployed(): any
	local Promise = self._provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), _reject: (any) -> ())
		local nonceOk, _ = pcall(function()
			return self._provider:getNonce(self.address):expect()
		end)

		if nonceOk then
			resolve({
				transactionHash = "0x0",
				contractAddress = self.address,
				alreadyDeployed = true,
			})
		else
			resolve(nil)
		end
	end)
end

--- Execute a function with NonceManager reserve/confirm/reject lifecycle.
--- If NonceManager is unavailable or an explicit nonce is provided, calls fn(opts) directly.
--- Otherwise: reserve → fn(optsWithNonce) → confirm on success / reject on failure.
function Account:_withNonceManager(options: any?, fn: (opts: any) -> any): any
	local nm = self._provider:getNonceManager()
	local hasExplicitNonce = options and (options :: any).nonce

	if not nm or hasExplicitNonce then
		return fn(options)
	end

	local Promise = self._provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local reserveOk, reservedNonce = pcall(function()
			return nm:reserve(self.address):expect()
		end)
		if not reserveOk then
			reject(reservedNonce)
			return
		end

		local opts: any
		if options then
			opts = table.clone(options :: any)
		else
			opts = {}
		end
		opts.nonce = reservedNonce

		local execOk, execResult = pcall(function()
			return fn(opts):expect()
		end)

		if execOk then
			nm:confirm(self.address, reservedNonce)
			resolve(execResult)
		else
			nm:reject(self.address, reservedNonce)
			reject(execResult)
		end
	end)
end

--------------------------------------------------------------------------------
-- Instance methods
--------------------------------------------------------------------------------

--- Execute calls via the internal TransactionBuilder.
--- Returns a Promise resolving to { transactionHash: string }.
--- When the provider has a NonceManager enabled and no explicit nonce is provided,
--- automatically reserves a nonce, confirms on success, and rejects on failure.
function Account:execute(calls: { TransactionBuilder.Call }, options: TransactionBuilder.ExecuteOptions?): any
	return self:_withNonceManager(options, function(opts: any)
		return self._builder:execute({
			address = self.address,
			signer = self.signer,
		}, calls, opts)
	end)
end

--- Deploy this account on-chain.
--- The account must be pre-funded at its counterfactual address before calling this.
--- Full orchestration: idempotency check, fee estimation, signing, submission, and optional confirmation.
--- Returns a Promise resolving to { transactionHash: string, contractAddress: string }.
--- If the account is already deployed, returns early with alreadyDeployed = true.
function Account:deployAccount(options: TransactionBuilder.DeployAccountOptions?): any
	local opts = options or {} :: TransactionBuilder.DeployAccountOptions
	local Promise = self._provider:getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Idempotency check
		local alreadyDeployed = self:_checkAlreadyDeployed():expect()
		if alreadyDeployed then
			resolve(alreadyDeployed)
			return
		end

		-- Step 2: Build deploy params from stored account config
		local params = self:_buildDeployParams()

		-- Step 3: Execute deploy via builder (with NonceManager if available)
		local deployOk, deployResult = pcall(function()
			return self:_withNonceManager(opts, function(nmOpts: any)
				return self._builder:deployAccount({
					address = self.address,
					signer = self.signer,
				}, params, nmOpts)
			end):expect()
		end)
		if not deployOk then
			reject(deployResult)
			return
		end

		-- Step 4: Wait for confirmation (default true, skip for dryRun)
		local waitForConfirmation = if opts.waitForConfirmation ~= nil then opts.waitForConfirmation else true
		if waitForConfirmation and not opts.dryRun and deployResult.transactionHash then
			local waitOk, waitResult = pcall(function()
				return self._provider:waitForTransaction(deployResult.transactionHash):expect()
			end)
			if not waitOk then
				reject(waitResult)
				return
			end
		end

		-- Step 5: Return result (preserve all fields from builder, ensure contractAddress)
		deployResult.contractAddress = deployResult.contractAddress or self.address
		resolve(deployResult)
	end)
end

--- Estimate the fee for deploying this account.
--- Returns a Promise resolving to the fee estimate.
function Account:estimateDeployAccountFee(): any
	local params = self:_buildDeployParams()
	return self._builder:estimateDeployAccountFee({
		address = self.address,
		signer = self.signer,
	}, params)
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

--- Get the provider instance.
function Account:getProvider(): any
	return self._provider
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
	return self.signer:signHash(hashBuf)
end

--- Get the SNIP-29 DeploymentData for this account.
--- Useful for passing to SponsoredExecutor or building paymaster requests manually.
--- Returns a table matching the PaymasterRpc.DeploymentData shape.
function Account:getDeploymentData(): { [string]: any }
	local params = self:_buildDeployParams()
	return {
		classHash = params.classHash,
		calldata = params.constructorCalldata,
		salt = params.addressSalt,
		unique = false,
		version = 1,
	}
end

--- Deploy the account via paymaster (SNIP-29 DEPLOY_AND_INVOKE) with zero prefunding.
--- Combines account deployment and optional initial calls in a single atomic paymaster transaction.
--- Flow: idempotency check → build deploymentData → paymaster buildTypedData → sign → executeTransaction.
--- Returns a Promise resolving to { transactionHash, contractAddress, trackingId?, alreadyDeployed? }.
function Account:deployWithPaymaster(
	paymasterDetails: Interfaces.PaymasterDetails,
	options: { calls: { any }?, waitForConfirmation: boolean? }?
): any
	local validated = validatePaymasterDetails("deployWithPaymaster", paymasterDetails)

	local opts = options or {}
	local calls = opts.calls or {}
	local waitForConfirmation = if opts.waitForConfirmation ~= nil then opts.waitForConfirmation else false

	local deploymentData = self:getDeploymentData()

	local Promise = self._provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Idempotency check
		local alreadyDeployed = self:_checkAlreadyDeployed():expect()
		if alreadyDeployed then
			resolve(alreadyDeployed)
			return
		end

		-- Step 2: Build typed data via paymaster (DEPLOY_AND_INVOKE)
		local buildOk, buildResult = pcall(function()
			return validated.paymaster
				:buildTypedData(self.address, calls, validated.gasTokenAddress, { deploymentData = deploymentData })
				:expect()
		end)
		if not buildOk then
			reject(buildResult)
			return
		end

		local typedData = buildResult.typedData

		-- Step 3: Validate returned calls match submitted calls (if any)
		if #calls > 0 then
			local valOk, valErr = pcall(function()
				validatePaymasterCalls(calls, typedData)
			end)
			if not valOk then
				reject(valErr)
				return
			end
		end

		-- Step 4: Sign the typed data
		local signOk, signature = pcall(function()
			return self:signMessage(typedData)
		end)
		if not signOk then
			reject(signature)
			return
		end

		-- Step 5: Execute via paymaster
		local execOk, execResult = pcall(function()
			return validated.paymaster
				:executeTransaction(self.address, typedData, signature, { deploymentData = deploymentData })
				:expect()
		end)
		if not execOk then
			reject(execResult)
			return
		end

		-- Step 6: Wait for confirmation (if requested)
		if waitForConfirmation and execResult.transactionHash then
			local waitOk, waitResult = pcall(function()
				return self._provider:waitForTransaction(execResult.transactionHash):expect()
			end)
			if not waitOk then
				reject(waitResult)
				return
			end
		end

		resolve({
			transactionHash = execResult.transactionHash,
			contractAddress = self.address,
			trackingId = execResult.trackingId,
		})
	end)
end

--- Estimate the fee for executing calls through a paymaster (SNIP-29).
--- Returns a Promise resolving to { feeEstimate, typedData } from the paymaster's buildTypedData response.
--- Does NOT interact with the NonceManager — paymaster uses SNIP-9 outside execution nonces.
function Account:estimatePaymasterFee(calls: { any }, paymasterDetails: Interfaces.PaymasterDetails): any
	local validated = validatePaymasterDetails("estimatePaymasterFee", paymasterDetails)

	local options: { [string]: any } = {}
	if paymasterDetails.deploymentData then
		options.deploymentData = paymasterDetails.deploymentData
	end

	return validated.paymaster
		:buildTypedData(self.address, calls, validated.gasTokenAddress, options)
		:andThen(function(buildResult: any)
			return {
				feeEstimate = buildResult.feeEstimate,
				typedData = buildResult.typedData,
			}
		end)
end

--- Execute calls through a paymaster (SNIP-29) for gasless/sponsored transactions.
--- Full flow: buildTypedData → validate returned calls → sign → executeTransaction.
--- Returns a Promise resolving to { transactionHash, trackingId }.
--- Does NOT interact with the NonceManager — paymaster uses SNIP-9 outside execution nonces.
function Account:executePaymaster(calls: { any }, paymasterDetails: Interfaces.PaymasterDetails): any
	local validated = validatePaymasterDetails("executePaymaster", paymasterDetails)

	if not calls or #calls == 0 then
		error(
			StarknetError.validation(
				"executePaymaster: at least one call is required",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local options: { [string]: any } = {}
	if paymasterDetails.deploymentData then
		options.deploymentData = paymasterDetails.deploymentData
	end

	local Promise = self._provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Build typed data via paymaster
		local buildOk, buildResult = pcall(function()
			return validated.paymaster:buildTypedData(self.address, calls, validated.gasTokenAddress, options):expect()
		end)
		if not buildOk then
			reject(buildResult)
			return
		end

		local typedData = buildResult.typedData

		-- Step 2: Security validation — ensure returned calls match submitted calls
		local valOk, valErr = pcall(function()
			validatePaymasterCalls(calls, typedData)
		end)
		if not valOk then
			reject(valErr)
			return
		end

		-- Step 3: Sign the typed data
		local signOk, signature = pcall(function()
			return self:signMessage(typedData)
		end)
		if not signOk then
			reject(signature)
			return
		end

		-- Step 4: Execute via paymaster
		local execOk, execResult = pcall(function()
			return validated.paymaster:executeTransaction(self.address, typedData, signature, options):expect()
		end)
		if not execOk then
			reject(execResult)
			return
		end

		-- Normalize return shape to match execute(): { transactionHash, trackingId? }
		resolve({
			transactionHash = execResult.transactionHash or execResult.transaction_hash,
			trackingId = execResult.trackingId,
		})
	end)
end

return Account
