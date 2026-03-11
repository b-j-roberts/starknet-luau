--!strict
-- TransactionBuilder: High-level transaction orchestration for Starknet V3 transactions
-- Coordinates nonce fetching, fee estimation, hash computation, signing, and submission
-- All async operations return Promises for Roblox compatibility

local BigInt = require("../crypto/BigInt")
local CallData = require("./CallData")
local TransactionHash = require("./TransactionHash")
local RpcTypes = require("../provider/RpcTypes")
local Interfaces = require("../shared/interfaces")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type Account = {
	address: string,
	signer: Interfaces.MinimalSigner,
}

export type Call = CallData.Call

export type BaseTransactionOptions = {
	nonce: string?, -- Override automatic nonce fetching
	maxFee: string?, -- Cap overall fee (reduces l1Gas.maxAmount so maxAmount * maxPricePerUnit <= maxFee)
	resourceBounds: TransactionHash.ResourceBounds?, -- Override computed resource bounds
	feeMultiplier: number?, -- Fee buffer multiplier (default 1.5)
	tip: string?, -- Tip for priority (default "0x0")
	paymasterData: { string }?, -- Paymaster data
	nonceDataAvailabilityMode: number?, -- DA mode for nonce (default 0)
	feeDataAvailabilityMode: number?, -- DA mode for fee (default 0)
	dryRun: boolean?, -- Build and sign but don't submit
	skipValidate: boolean?, -- Use SKIP_VALIDATE flag for fee estimation
}

export type ExecuteOptions = BaseTransactionOptions & {
	accountDeploymentData: { string }?, -- Account deployment data
}

export type DeployAccountParams = {
	classHash: string, -- Account implementation class hash
	constructorCalldata: { string }, -- Compiled constructor args
	addressSalt: string, -- Salt for address computation (typically public key)
	contractAddress: string, -- Pre-computed counterfactual address
}

export type DeployAccountOptions = BaseTransactionOptions & {
	waitForConfirmation: boolean?, -- Account-level: wait for receipt after submission (default true)
}

export type WaitOptions = RpcTypes.WaitOptions

export type ExecuteResult = {
	transactionHash: string,
}

export type DryRunResult = {
	transactionHash: string,
	transaction: any,
	signature: { string },
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_FEE_MULTIPLIER = 1.5
local ZERO_RESOURCE_BOUND: TransactionHash.ResourceBound = {
	maxAmount = "0x0",
	maxPricePerUnit = "0x0",
}
local ZERO_RESOURCE_BOUNDS: TransactionHash.ResourceBounds = {
	l1Gas = ZERO_RESOURCE_BOUND,
	l2Gas = ZERO_RESOURCE_BOUND,
	l1DataGas = ZERO_RESOURCE_BOUND,
}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Apply a multiplier to a hex string amount, returning a hex string.
--- Used to add a fee buffer to gas estimates.
local function applyMultiplier(hexValue: string, multiplier: number): string
	-- Parse hex to number, multiply, convert back
	-- For very large values we need BigInt arithmetic
	local big = BigInt.fromHex(hexValue)
	if BigInt.isZero(big) then
		return "0x0"
	end

	-- Multiply: convert multiplier to integer numerator/denominator
	-- e.g., 1.5 = 150/100, 2.0 = 200/100
	local scale = 100
	local numerator = math.floor(multiplier * scale + 0.5)
	local bigNumerator = BigInt.fromNumber(numerator)
	local bigDenominator = BigInt.fromNumber(scale)

	local product = BigInt.mul(big, bigNumerator)
	local result = BigInt.div(product, bigDenominator)
	return BigInt.toHex(result)
end

--- Build resource bounds from a fee estimate with a multiplier buffer.
--- Supports both v0.7 field names (gas_consumed, gas_price, data_gas_consumed, data_gas_price)
--- and v0.8+ field names (l1_gas_consumed, l1_gas_price, l2_gas_consumed, l2_gas_price,
--- l1_data_gas_consumed, l1_data_gas_price).
local function resourceBoundsFromEstimate(estimate: any, multiplier: number): TransactionHash.ResourceBounds
	-- L1 gas: v0.8 "l1_gas_*" or v0.7 "gas_*"
	local l1GasConsumed = estimate.l1_gas_consumed or estimate.gas_consumed or "0x0"
	local l1GasPrice = estimate.l1_gas_price or estimate.gas_price or "0x0"

	-- L2 gas: v0.8 only (v0.7 had no L2 gas in estimates)
	local l2GasConsumed = estimate.l2_gas_consumed or "0x0"
	local l2GasPrice = estimate.l2_gas_price or "0x0"

	-- L1 data gas: v0.8 "l1_data_gas_*" or v0.7 "data_gas_*"
	local dataGasConsumed = estimate.l1_data_gas_consumed or estimate.data_gas_consumed or "0x0"
	local dataGasPrice = estimate.l1_data_gas_price or estimate.data_gas_price or "0x0"

	return {
		l1Gas = {
			maxAmount = applyMultiplier(l1GasConsumed, multiplier),
			maxPricePerUnit = applyMultiplier(l1GasPrice, multiplier),
		},
		l2Gas = {
			maxAmount = applyMultiplier(l2GasConsumed, multiplier),
			maxPricePerUnit = applyMultiplier(l2GasPrice, multiplier),
		},
		l1DataGas = {
			maxAmount = applyMultiplier(dataGasConsumed, multiplier),
			maxPricePerUnit = applyMultiplier(dataGasPrice, multiplier),
		},
	}
end

--- Convert numeric DA mode (0=L1, 1=L2) to the RPC string format required by spec v0.7+.
local function toRpcDAMode(mode: number?): string
	if (mode or 0) == 1 then
		return "L2"
	end
	return "L1"
end

--- Convert TransactionHash.ResourceBounds (camelCase, 3 fields) to RPC format (snake_case, 3 fields).
--- TransactionHash uses camelCase keys (l1Gas, l2Gas, l1DataGas) for hash computation,
--- while the Starknet JSON-RPC spec uses snake_case (l1_gas, l2_gas, l1_data_gas).
--- RPC spec v0.8+ requires all three fields in the resource_bounds object.
local function toRpcResourceBounds(bounds: TransactionHash.ResourceBounds): any
	return {
		l1_gas = {
			max_amount = bounds.l1Gas.maxAmount,
			max_price_per_unit = bounds.l1Gas.maxPricePerUnit,
		},
		l2_gas = {
			max_amount = bounds.l2Gas.maxAmount,
			max_price_per_unit = bounds.l2Gas.maxPricePerUnit,
		},
		l1_data_gas = {
			max_amount = bounds.l1DataGas.maxAmount,
			max_price_per_unit = bounds.l1DataGas.maxPricePerUnit,
		},
	}
end

--- Extract the first fee estimate from a result that may be an array or single object.
local function extractFirstEstimate(feeResult: any): any
	if type(feeResult) == "table" and #feeResult > 0 then
		return feeResult[1]
	end
	return feeResult
end

--- Build an unsigned InvokeTransactionV3 object for RPC submission or fee estimation.
local function buildInvokeTransaction(params: {
	senderAddress: string,
	calldata: { string },
	nonce: string,
	resourceBounds: TransactionHash.ResourceBounds,
	signature: { string },
	tip: string?,
	paymasterData: { string }?,
	accountDeploymentData: { string }?,
	nonceDataAvailabilityMode: number?,
	feeDataAvailabilityMode: number?,
}): any
	return {
		type = "INVOKE",
		version = "0x3",
		sender_address = params.senderAddress,
		calldata = params.calldata,
		signature = params.signature,
		nonce = params.nonce,
		resource_bounds = toRpcResourceBounds(params.resourceBounds),
		tip = params.tip or "0x0",
		paymaster_data = params.paymasterData or {},
		nonce_data_availability_mode = toRpcDAMode(params.nonceDataAvailabilityMode),
		fee_data_availability_mode = toRpcDAMode(params.feeDataAvailabilityMode),
		account_deployment_data = params.accountDeploymentData or {},
	}
end

--- Build an unsigned DeployAccountTransactionV3 object for RPC submission or fee estimation.
local function buildDeployAccountTransaction(params: {
	classHash: string,
	constructorCalldata: { string },
	contractAddressSalt: string,
	nonce: string,
	resourceBounds: TransactionHash.ResourceBounds,
	signature: { string },
	tip: string?,
	paymasterData: { string }?,
	nonceDataAvailabilityMode: number?,
	feeDataAvailabilityMode: number?,
}): any
	return {
		type = "DEPLOY_ACCOUNT",
		version = "0x3",
		class_hash = params.classHash,
		constructor_calldata = params.constructorCalldata,
		contract_address_salt = params.contractAddressSalt,
		signature = params.signature,
		nonce = params.nonce,
		resource_bounds = toRpcResourceBounds(params.resourceBounds),
		tip = params.tip or "0x0",
		paymaster_data = params.paymasterData or {},
		nonce_data_availability_mode = toRpcDAMode(params.nonceDataAvailabilityMode),
		fee_data_availability_mode = toRpcDAMode(params.feeDataAvailabilityMode),
	}
end

--- Shared internal fee estimation logic.
--- @param provider -- RpcProvider instance
--- @param resolveNonce -- returns nonce (may throw)
--- @param buildUnsignedTx -- builds unsigned tx with zero bounds + dummy sig for given nonce
local function _estimateInternal(
	provider: Interfaces.ProviderInterface,
	resolveNonce: () -> string,
	buildUnsignedTx: (nonce: string) -> any
): any
	local Promise = provider:getPromise()
	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		local nonceOk, nonce = pcall(resolveNonce)
		if not nonceOk then
			reject(nonce)
			return
		end

		local unsignedTx = buildUnsignedTx(nonce)

		local feeOk, feeResult = pcall(function()
			return provider:estimateFee({ unsignedTx }, { "SKIP_VALIDATE" }):expect()
		end)
		if not feeOk then
			reject(feeResult)
			return
		end

		resolve(extractFirstEstimate(feeResult))
	end)
end

--- Shared execution pipeline parameterized by transaction-specific behavior.
--- Both execute() and deployAccount() delegate to this function.
local function _executePipeline(
	provider: Interfaces.ProviderInterface,
	account: Account,
	config: {
		resolveNonce: () -> string,
		buildEstimationTx: (nonce: string) -> any,
		computeHash: (string, string, TransactionHash.ResourceBounds, string, { string }, number, number) -> string,
		buildSignedTx: (string, TransactionHash.ResourceBounds, { string }, string, { string }, number, number) -> any,
		submit: (any) -> any,
		formatResult: (any) -> any,
		applyPostEstimate: ((TransactionHash.ResourceBounds) -> TransactionHash.ResourceBounds)?,
	},
	opts: BaseTransactionOptions
): any
	local Promise = provider:getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Resolve nonce
		local nonceOk, nonce = pcall(config.resolveNonce)
		if not nonceOk then
			reject(nonce)
			return
		end

		-- Step 2: Fetch chain ID
		local chainIdOk, chainId = pcall(function()
			return provider:getChainId():expect()
		end)
		if not chainIdOk then
			reject(chainId)
			return
		end

		-- Step 3: Determine resource bounds (estimate or use override)
		local resourceBounds: TransactionHash.ResourceBounds
		if opts.resourceBounds then
			resourceBounds = opts.resourceBounds
		else
			local multiplier = opts.feeMultiplier or DEFAULT_FEE_MULTIPLIER
			local unsignedTx = config.buildEstimationTx(nonce)
			local simFlags = if opts.skipValidate ~= false then { "SKIP_VALIDATE" } else {}

			local feeOk, feeResult = pcall(function()
				return provider:estimateFee({ unsignedTx }, simFlags):expect()
			end)
			if not feeOk then
				reject(feeResult)
				return
			end

			local estimate = extractFirstEstimate(feeResult)
			resourceBounds = resourceBoundsFromEstimate(estimate, multiplier)

			if config.applyPostEstimate then
				resourceBounds = config.applyPostEstimate(resourceBounds)
			end
		end

		-- Step 4: Extract common options
		local tip = opts.tip or "0x0"
		local paymasterData = opts.paymasterData or {}
		local nonceDAMode = opts.nonceDataAvailabilityMode or 0
		local feeDAMode = opts.feeDataAvailabilityMode or 0

		-- Step 5: Compute transaction hash
		local txHash = config.computeHash(chainId, nonce, resourceBounds, tip, paymasterData, nonceDAMode, feeDAMode)

		-- Step 6: Sign the transaction hash
		local txHashBuf = BigInt.fromHex(txHash)
		local signature = account.signer:signHash(txHashBuf)

		-- Step 7: Build the final signed transaction
		local signedTx =
			config.buildSignedTx(nonce, resourceBounds, signature, tip, paymasterData, nonceDAMode, feeDAMode)

		-- Step 8: Handle dryRun
		if opts.dryRun then
			resolve({
				transactionHash = txHash,
				transaction = signedTx,
				signature = signature,
			})
			return
		end

		-- Step 9: Submit
		local submitOk, submitResult = pcall(config.submit, signedTx)
		if not submitOk then
			reject(submitResult)
			return
		end

		resolve(config.formatResult(submitResult))
	end)
end

--------------------------------------------------------------------------------
-- TransactionBuilder class
--------------------------------------------------------------------------------

local TransactionBuilder = {}
TransactionBuilder.__index = TransactionBuilder

--- Create a new TransactionBuilder.
--- @param provider -- RpcProvider instance for network communication
function TransactionBuilder.new(provider: Interfaces.ProviderInterface): any
	if not provider then
		error(StarknetError.validation("TransactionBuilder: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local self = setmetatable({
		_provider = provider,
	}, TransactionBuilder)

	return self
end

--- Estimate the fee for a set of calls without submitting.
--- Returns a Promise resolving to the fee estimate.
function TransactionBuilder:estimateFee(account: Account, calls: { Call }): any
	local provider = self._provider
	local calldata = CallData.encodeMulticall(calls)

	return _estimateInternal(provider, function(): string
		return provider:getNonce(account.address):expect()
	end, function(nonce: string): any
		return buildInvokeTransaction({
			senderAddress = account.address,
			calldata = calldata,
			nonce = nonce,
			resourceBounds = ZERO_RESOURCE_BOUNDS,
			signature = { "0x0", "0x0" },
		})
	end)
end

--- Execute a full transaction flow: fetch nonce, estimate fees, hash, sign, submit.
--- Returns a Promise resolving to the transaction hash (or DryRunResult if dryRun=true).
function TransactionBuilder:execute(account: Account, calls: { Call }, options: ExecuteOptions?): any
	local provider = self._provider
	local opts = options or {} :: ExecuteOptions
	local calldata = CallData.encodeMulticall(calls)
	local accountDeploymentData = opts.accountDeploymentData or {}

	return _executePipeline(provider, account, {
		resolveNonce = function(): string
			if opts.nonce then
				return opts.nonce :: string
			end
			return provider:getNonce(account.address):expect()
		end,
		buildEstimationTx = function(nonce: string): any
			return buildInvokeTransaction({
				senderAddress = account.address,
				calldata = calldata,
				nonce = nonce,
				resourceBounds = ZERO_RESOURCE_BOUNDS,
				signature = { "0x0", "0x0" },
				nonceDataAvailabilityMode = opts.nonceDataAvailabilityMode,
				feeDataAvailabilityMode = opts.feeDataAvailabilityMode,
			})
		end,
		computeHash = function(
			chainId: string,
			nonce: string,
			resourceBounds: TransactionHash.ResourceBounds,
			tip: string,
			paymasterData: { string },
			nonceDAMode: number,
			feeDAMode: number
		): string
			return TransactionHash.calculateInvokeTransactionHash({
				senderAddress = account.address,
				compiledCalldata = calldata,
				chainId = chainId,
				nonce = nonce,
				resourceBounds = resourceBounds,
				tip = tip,
				paymasterData = paymasterData,
				accountDeploymentData = accountDeploymentData,
				nonceDataAvailabilityMode = nonceDAMode,
				feeDataAvailabilityMode = feeDAMode,
			})
		end,
		buildSignedTx = function(
			nonce: string,
			resourceBounds: TransactionHash.ResourceBounds,
			signature: { string },
			tip: string,
			paymasterData: { string },
			nonceDAMode: number,
			feeDAMode: number
		): any
			return buildInvokeTransaction({
				senderAddress = account.address,
				calldata = calldata,
				nonce = nonce,
				resourceBounds = resourceBounds,
				signature = signature,
				tip = tip,
				paymasterData = paymasterData,
				accountDeploymentData = accountDeploymentData,
				nonceDataAvailabilityMode = nonceDAMode,
				feeDataAvailabilityMode = feeDAMode,
			})
		end,
		submit = function(signedTx: any): any
			return provider:addInvokeTransaction(signedTx):expect()
		end,
		formatResult = function(submitResult: any): any
			return { transactionHash = submitResult.transaction_hash }
		end,
		applyPostEstimate = if opts.maxFee
			then function(resourceBounds: TransactionHash.ResourceBounds): TransactionHash.ResourceBounds
				local maxFeeBig = BigInt.fromHex(opts.maxFee :: string)
				local priceBig = BigInt.fromHex(resourceBounds.l1Gas.maxPricePerUnit)
				if not BigInt.isZero(priceBig) then
					local cappedMaxAmount = BigInt.div(maxFeeBig, priceBig)
					local currentMaxAmount = BigInt.fromHex(resourceBounds.l1Gas.maxAmount)
					if BigInt.cmp(currentMaxAmount, cappedMaxAmount) > 0 then
						return {
							l1Gas = {
								maxAmount = BigInt.toHex(cappedMaxAmount),
								maxPricePerUnit = resourceBounds.l1Gas.maxPricePerUnit,
							},
							l2Gas = resourceBounds.l2Gas,
							l1DataGas = resourceBounds.l1DataGas,
						}
					end
				end
				return resourceBounds
			end
			else nil,
	}, opts)
end

--- Estimate the fee for a deploy account transaction without submitting.
--- Returns a Promise resolving to the fee estimate.
function TransactionBuilder:estimateDeployAccountFee(_account: Account, params: DeployAccountParams): any
	local provider = self._provider

	return _estimateInternal(provider, function(): string
		return "0x0"
	end, function(nonce: string): any
		return buildDeployAccountTransaction({
			classHash = params.classHash,
			constructorCalldata = params.constructorCalldata,
			contractAddressSalt = params.addressSalt,
			nonce = nonce,
			resourceBounds = ZERO_RESOURCE_BOUNDS,
			signature = { "0x0", "0x0" },
		})
	end)
end

--- Execute a full deploy account transaction flow: fetch chain ID, estimate fees, hash, sign, submit.
--- Returns a Promise resolving to the transaction hash (or DryRunResult if dryRun=true).
function TransactionBuilder:deployAccount(
	account: Account,
	params: DeployAccountParams,
	options: DeployAccountOptions?
): any
	local provider = self._provider
	local opts = options or {} :: DeployAccountOptions

	return _executePipeline(provider, account, {
		resolveNonce = function(): string
			return opts.nonce or "0x0"
		end,
		buildEstimationTx = function(nonce: string): any
			return buildDeployAccountTransaction({
				classHash = params.classHash,
				constructorCalldata = params.constructorCalldata,
				contractAddressSalt = params.addressSalt,
				nonce = nonce,
				resourceBounds = ZERO_RESOURCE_BOUNDS,
				signature = { "0x0", "0x0" },
				nonceDataAvailabilityMode = opts.nonceDataAvailabilityMode,
				feeDataAvailabilityMode = opts.feeDataAvailabilityMode,
			})
		end,
		computeHash = function(
			chainId: string,
			nonce: string,
			resourceBounds: TransactionHash.ResourceBounds,
			tip: string,
			paymasterData: { string },
			nonceDAMode: number,
			feeDAMode: number
		): string
			return TransactionHash.calculateDeployAccountTransactionHash({
				classHash = params.classHash,
				constructorCalldata = params.constructorCalldata,
				contractAddress = params.contractAddress,
				salt = params.addressSalt,
				chainId = chainId,
				nonce = nonce,
				resourceBounds = resourceBounds,
				tip = tip,
				paymasterData = paymasterData,
				nonceDataAvailabilityMode = nonceDAMode,
				feeDataAvailabilityMode = feeDAMode,
			})
		end,
		buildSignedTx = function(
			nonce: string,
			resourceBounds: TransactionHash.ResourceBounds,
			signature: { string },
			tip: string,
			paymasterData: { string },
			nonceDAMode: number,
			feeDAMode: number
		): any
			return buildDeployAccountTransaction({
				classHash = params.classHash,
				constructorCalldata = params.constructorCalldata,
				contractAddressSalt = params.addressSalt,
				nonce = nonce,
				resourceBounds = resourceBounds,
				signature = signature,
				tip = tip,
				paymasterData = paymasterData,
				nonceDataAvailabilityMode = nonceDAMode,
				feeDataAvailabilityMode = feeDAMode,
			})
		end,
		submit = function(signedTx: any): any
			return provider:addDeployAccountTransaction(signedTx):expect()
		end,
		formatResult = function(submitResult: any): any
			return {
				transactionHash = submitResult.transaction_hash,
				contractAddress = submitResult.contract_address,
			}
		end,
		applyPostEstimate = if opts.maxFee
			then function(resourceBounds: TransactionHash.ResourceBounds): TransactionHash.ResourceBounds
				local maxFeeBig = BigInt.fromHex(opts.maxFee :: string)
				local priceBig = BigInt.fromHex(resourceBounds.l1Gas.maxPricePerUnit)
				if not BigInt.isZero(priceBig) then
					local cappedMaxAmount = BigInt.div(maxFeeBig, priceBig)
					local currentMaxAmount = BigInt.fromHex(resourceBounds.l1Gas.maxAmount)
					if BigInt.cmp(currentMaxAmount, cappedMaxAmount) > 0 then
						return {
							l1Gas = {
								maxAmount = BigInt.toHex(cappedMaxAmount),
								maxPricePerUnit = resourceBounds.l1Gas.maxPricePerUnit,
							},
							l2Gas = resourceBounds.l2Gas,
							l1DataGas = resourceBounds.l1DataGas,
						}
					end
				end
				return resourceBounds
			end
			else nil,
	}, opts)
end

--- Wait for a transaction receipt by polling the provider.
--- Returns a Promise resolving to the transaction receipt.
function TransactionBuilder:waitForReceipt(txHash: string, options: WaitOptions?): any
	return self._provider:waitForTransaction(txHash, options)
end

return TransactionBuilder
