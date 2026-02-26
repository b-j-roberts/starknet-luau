--!strict
-- TransactionBuilder: High-level transaction orchestration for Starknet V3 INVOKE transactions
-- Coordinates nonce fetching, fee estimation, hash computation, signing, and submission
-- All async operations return Promises for Roblox compatibility

local BigInt = require("../crypto/BigInt")
local CallData = require("./CallData")
local TransactionHash = require("./TransactionHash")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type Account = {
	address: string,
	signer: {
		signTransaction: (self: any, txHash: buffer) -> { string },
	},
}

export type Call = CallData.Call

export type ExecuteOptions = {
	nonce: string?, -- Override automatic nonce fetching
	maxFee: string?, -- Override fee estimation with explicit max fee
	resourceBounds: TransactionHash.ResourceBounds?, -- Override computed resource bounds
	feeMultiplier: number?, -- Fee buffer multiplier (default 1.5)
	tip: string?, -- Tip for priority (default "0x0")
	paymasterData: { string }?, -- Paymaster data
	accountDeploymentData: { string }?, -- Account deployment data
	nonceDataAvailabilityMode: number?, -- DA mode for nonce (default 0)
	feeDataAvailabilityMode: number?, -- DA mode for fee (default 0)
	dryRun: boolean?, -- Build and sign but don't submit
	skipValidate: boolean?, -- Use SKIP_VALIDATE flag for fee estimation
}

export type WaitOptions = {
	retryInterval: number?, -- Seconds between polls (default 5)
	maxAttempts: number?, -- Max poll attempts (default 30)
}

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
local function resourceBoundsFromEstimate(estimate: any, multiplier: number): TransactionHash.ResourceBounds
	local gasConsumed = estimate.gas_consumed or "0x0"
	local gasPrice = estimate.gas_price or "0x0"
	local dataGasConsumed = estimate.data_gas_consumed or "0x0"
	local dataGasPrice = estimate.data_gas_price or "0x0"

	return {
		l1Gas = {
			maxAmount = applyMultiplier(gasConsumed, multiplier),
			maxPricePerUnit = applyMultiplier(gasPrice, multiplier),
		},
		l2Gas = ZERO_RESOURCE_BOUND,
		l1DataGas = {
			maxAmount = applyMultiplier(dataGasConsumed, multiplier),
			maxPricePerUnit = applyMultiplier(dataGasPrice, multiplier),
		},
	}
end

--- Convert TransactionHash.ResourceBounds (camelCase) to RPC format (snake_case).
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
	}
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
		nonce_data_availability_mode = "0x0",
		fee_data_availability_mode = "0x0",
		account_deployment_data = params.accountDeploymentData or {},
	}
end

--------------------------------------------------------------------------------
-- TransactionBuilder class
--------------------------------------------------------------------------------

local TransactionBuilder = {}
TransactionBuilder.__index = TransactionBuilder

--- Create a new TransactionBuilder.
--- @param provider -- RpcProvider instance for network communication
function TransactionBuilder.new(provider: any): any
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
	local Promise = provider:_getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Fetch nonce and chain ID in sequence (synchronous in test, async in Roblox)
		local nonceOk, nonce = pcall(function()
			return provider:getNonce(account.address):expect()
		end)
		if not nonceOk then
			reject(nonce)
			return
		end

		-- Step 2: Encode calldata
		local calldata = CallData.encodeMulticall(calls)

		-- Step 3: Build unsigned transaction with zero resource bounds and dummy signature
		local unsignedTx = buildInvokeTransaction({
			senderAddress = account.address,
			calldata = calldata,
			nonce = nonce,
			resourceBounds = {
				l1Gas = ZERO_RESOURCE_BOUND,
				l2Gas = ZERO_RESOURCE_BOUND,
				l1DataGas = ZERO_RESOURCE_BOUND,
			},
			signature = { "0x0", "0x0" }, -- Dummy signature for estimation
		})

		-- Step 4: Call estimateFee with SKIP_VALIDATE
		local feeOk, feeResult = pcall(function()
			return provider:estimateFee({ unsignedTx }, { "SKIP_VALIDATE" }):expect()
		end)
		if not feeOk then
			reject(feeResult)
			return
		end

		-- Return the first estimate (single transaction)
		if type(feeResult) == "table" and #feeResult > 0 then
			resolve(feeResult[1])
		else
			resolve(feeResult)
		end
	end)
end

--- Execute a full transaction flow: fetch nonce, estimate fees, hash, sign, submit.
--- Returns a Promise resolving to the transaction hash (or DryRunResult if dryRun=true).
function TransactionBuilder:execute(account: Account, calls: { Call }, options: ExecuteOptions?): any
	local provider = self._provider
	local Promise = provider:_getPromise()
	local opts = options or {} :: ExecuteOptions

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Fetch nonce (or use override)
		local nonce: string
		if opts.nonce then
			nonce = opts.nonce
		else
			local nonceOk, nonceResult = pcall(function()
				return provider:getNonce(account.address):expect()
			end)
			if not nonceOk then
				reject(nonceResult)
				return
			end
			nonce = nonceResult
		end

		-- Step 2: Fetch chain ID
		local chainIdOk, chainId = pcall(function()
			return provider:getChainId():expect()
		end)
		if not chainIdOk then
			reject(chainId)
			return
		end

		-- Step 3: Encode calldata (multicall format)
		local calldata = CallData.encodeMulticall(calls)

		-- Step 4: Determine resource bounds (estimate or use override)
		local resourceBounds: TransactionHash.ResourceBounds
		if opts.resourceBounds then
			resourceBounds = opts.resourceBounds
		else
			local multiplier = opts.feeMultiplier or DEFAULT_FEE_MULTIPLIER

			-- Build unsigned tx for fee estimation
			local unsignedTx = buildInvokeTransaction({
				senderAddress = account.address,
				calldata = calldata,
				nonce = nonce,
				resourceBounds = {
					l1Gas = ZERO_RESOURCE_BOUND,
					l2Gas = ZERO_RESOURCE_BOUND,
					l1DataGas = ZERO_RESOURCE_BOUND,
				},
				signature = { "0x0", "0x0" },
			})

			local simFlags = if opts.skipValidate ~= false then { "SKIP_VALIDATE" } else {}

			local feeOk, feeResult = pcall(function()
				return provider:estimateFee({ unsignedTx }, simFlags):expect()
			end)
			if not feeOk then
				reject(feeResult)
				return
			end

			local estimate = if type(feeResult) == "table" and #feeResult > 0 then feeResult[1] else feeResult
			resourceBounds = resourceBoundsFromEstimate(estimate, multiplier)
		end

		-- Step 5: Compute transaction hash (Poseidon)
		local tip = opts.tip or "0x0"
		local paymasterData = opts.paymasterData or {}
		local accountDeploymentData = opts.accountDeploymentData or {}
		local nonceDAMode = opts.nonceDataAvailabilityMode or 0
		local feeDAMode = opts.feeDataAvailabilityMode or 0

		local txHash = TransactionHash.calculateInvokeTransactionHash({
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

		-- Step 6: Sign the transaction hash
		local txHashBuf = BigInt.fromHex(txHash)
		local signature = account.signer:signTransaction(txHashBuf)

		-- Step 7: Build the final signed transaction
		local signedTx = buildInvokeTransaction({
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

		-- Step 7b: If dryRun, return without submitting
		if opts.dryRun then
			resolve({
				transactionHash = txHash,
				transaction = signedTx,
				signature = signature,
			})
			return
		end

		-- Step 8: Submit the transaction
		local submitOk, submitResult = pcall(function()
			return provider:addInvokeTransaction(signedTx):expect()
		end)
		if not submitOk then
			reject(submitResult)
			return
		end

		resolve({
			transactionHash = submitResult,
		})
	end)
end

--- Wait for a transaction receipt by polling the provider.
--- Returns a Promise resolving to the transaction receipt.
function TransactionBuilder:waitForReceipt(txHash: string, options: WaitOptions?): any
	return self._provider:waitForTransaction(txHash, options)
end

return TransactionBuilder
