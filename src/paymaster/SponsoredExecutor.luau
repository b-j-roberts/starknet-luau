--!strict
-- SponsoredExecutor: End-to-end sponsored transaction orchestrator
-- Chains: Policy check → Budget check → Paymaster build → Sign → Execute → Budget deduct
-- Includes retry logic on transient errors, event callbacks, and usage metrics.
-- This is the "batteries included" module that ties PaymasterRpc, PaymasterPolicy,
-- and PaymasterBudget together. Each sub-module is independently usable for advanced users.

local Interfaces = require("../shared/interfaces")
local PaymasterRpc = require("./PaymasterRpc")
local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes
local Defaults = require("../shared/TestableDefaults")

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

--- Info passed to the onTransactionSubmitted callback.
export type SubmittedInfo = {
	playerId: number,
	transactionHash: string,
	trackingId: string?,
	calls: { any },
	tokensCost: number,
}

--- Info passed to the onTransactionConfirmed callback.
export type ConfirmedInfo = {
	playerId: number,
	transactionHash: string,
	calls: { any },
}

--- Info passed to the onTransactionFailed callback.
export type FailedInfo = {
	playerId: number,
	calls: { any },
	error: any,
	retryCount: number,
	tokensRefunded: number,
}

--- Event callbacks for transaction lifecycle.
export type ExecutorCallbacks = {
	onTransactionSubmitted: ((info: SubmittedInfo) -> ())?,
	onTransactionConfirmed: ((info: ConfirmedInfo) -> ())?,
	onTransactionFailed: ((info: FailedInfo) -> ())?,
}

--- Per-player metrics.
export type PlayerMetrics = {
	executions: number,
	successful: number,
	failed: number,
	tokensSpent: number,
}

--- Aggregate executor metrics.
export type ExecutorMetrics = {
	totalExecutions: number,
	totalSuccessful: number,
	totalFailed: number,
	totalRetries: number,
	totalTokensConsumed: number,
	totalTokensRefunded: number,
	byPlayer: { [number]: PlayerMetrics },
	byContract: { [string]: number },
	byMethod: { [string]: number },
}

--- Configuration for creating a SponsoredExecutor.
export type SponsoredExecutorConfig = {
	account: Interfaces.AccountInterface,
	paymaster: Interfaces.PaymasterInterface,
	feeMode: PaymasterRpc.FeeMode,
	policy: Interfaces.PolicyInterface?,
	budget: Interfaces.BudgetInterface?,
	callbacks: ExecutorCallbacks?,
	retryAttempts: number?,
	retryDelay: number?,
	deploymentData: PaymasterRpc.DeploymentData?,
	-- Testing injection points
	_sleep: ((seconds: number) -> ())?,
	_clock: (() -> number)?,
}

--- Options for a single execute call.
export type ExecuteOptions = {
	txCost: number?,
	gasUsed: number?,
	deploymentData: any?,
	waitForConfirmation: boolean?,
}

--- Result from a successful sponsored execution.
export type SponsoredExecuteResult = {
	transactionHash: string,
	trackingId: string?,
	tokensCost: number,
	retryCount: number,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Check if an error is transient and worth retrying.
--- Transient: HTTP 502/503/504, network errors, rate limits, paymaster unavailable.
--- Deterministic paymaster errors (invalid signature, etc.) are NOT transient.
local function isTransientError(err: any): boolean
	if type(err) ~= "table" then
		return true -- raw string errors from network are treated as transient
	end
	-- HTTP gateway errors (502/503/504)
	local rpcCode = err.rpcCode
	if rpcCode == 502 or rpcCode == 503 or rpcCode == 504 then
		return true
	end
	return ErrorCodes.isTransient(err.code or 0)
end

--- Safely call a callback, catching and warning on errors.
local function safeCall(callback: ((...any) -> ())?, ...: any)
	if callback then
		local ok, err = pcall(callback, ...)
		if not ok then
			warn("SponsoredExecutor callback error: " .. tostring(err))
		end
	end
end

--- Get or create per-player metrics entry.
local function getOrCreatePlayerMetrics(metrics: ExecutorMetrics, playerId: number): PlayerMetrics
	if not metrics.byPlayer[playerId] then
		metrics.byPlayer[playerId] = {
			executions = 0,
			successful = 0,
			failed = 0,
			tokensSpent = 0,
		}
	end
	return metrics.byPlayer[playerId]
end

--- Record per-contract and per-method metrics for calls.
local function recordCallMetrics(metrics: ExecutorMetrics, calls: { any })
	for _, call in calls do
		local addr = call.contractAddress or ""
		metrics.byContract[addr] = (metrics.byContract[addr] or 0) + 1
		local method = call.entrypoint or ""
		local key = addr .. ":" .. method
		metrics.byMethod[key] = (metrics.byMethod[key] or 0) + 1
	end
end

--- Create a fresh metrics table.
local function createMetrics(): ExecutorMetrics
	return {
		totalExecutions = 0,
		totalSuccessful = 0,
		totalFailed = 0,
		totalRetries = 0,
		totalTokensConsumed = 0,
		totalTokensRefunded = 0,
		byPlayer = {},
		byContract = {},
		byMethod = {},
	}
end

--------------------------------------------------------------------------------
-- SponsoredExecutor
--------------------------------------------------------------------------------

local SponsoredExecutor = {}
local ExecutorProto = {}
ExecutorProto.__index = ExecutorProto

--- Create a new SponsoredExecutor.
--- @param config SponsoredExecutorConfig — required fields: account, paymaster, feeMode
function SponsoredExecutor.new(config: SponsoredExecutorConfig)
	if not config then
		error(StarknetError.validation("SponsoredExecutor: config is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.account then
		error(StarknetError.validation("SponsoredExecutor: account is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.paymaster then
		error(StarknetError.validation("SponsoredExecutor: paymaster is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.feeMode then
		error(StarknetError.validation("SponsoredExecutor: feeMode is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if config.feeMode.mode ~= "sponsored" and config.feeMode.mode ~= "default" then
		error(
			StarknetError.validation(
				`SponsoredExecutor: invalid feeMode.mode "{config.feeMode.mode}", expected "sponsored" or "default"`,
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end
	if config.feeMode.mode == "default" and not config.feeMode.gasToken then
		error(
			StarknetError.validation(
				"SponsoredExecutor: gasToken is required for 'default' feeMode",
				ErrorCodes.REQUIRED_FIELD.code
			)
		)
	end

	local self = setmetatable({
		_account = config.account,
		_paymaster = config.paymaster,
		_feeMode = config.feeMode,
		_policy = config.policy,
		_budget = config.budget,
		_callbacks = config.callbacks or {},
		_retryAttempts = config.retryAttempts or 3,
		_retryDelay = config.retryDelay or 1,
		_deploymentData = config.deploymentData,
		_sleep = config._sleep or Defaults.sleep,
		_clock = config._clock or Defaults.clock,
		_metrics = createMetrics(),
	}, ExecutorProto)

	return self
end

--- Get the current execution metrics.
function ExecutorProto:getMetrics(): ExecutorMetrics
	return self._metrics
end

--- Reset all metrics to zero.
function ExecutorProto:resetMetrics()
	self._metrics = createMetrics()
end

--- Execute sponsored calls for a player.
--- Flow: Policy check → Budget check → Paymaster build+sign+execute (with retry) → Budget deduct/refund.
--- Returns a Promise resolving to SponsoredExecuteResult.
function ExecutorProto:execute(playerId: number, calls: { any }, options: ExecuteOptions?): any
	if type(playerId) ~= "number" then
		error(
			StarknetError.validation("SponsoredExecutor: playerId must be a number", ErrorCodes.INVALID_ARGUMENT.code)
		)
	end
	if not calls or #calls == 0 then
		error(
			StarknetError.validation(
				"SponsoredExecutor: at least one call is required",
				ErrorCodes.INVALID_ARGUMENT.code
			)
		)
	end

	local opts: ExecuteOptions = (options or {}) :: ExecuteOptions
	local account = self._account
	local feeMode = self._feeMode
	local policy = self._policy
	local budget = self._budget
	local callbacks = self._callbacks
	local retryAttempts = self._retryAttempts
	local retryDelay = self._retryDelay
	local sleepFn = self._sleep
	local metrics = self._metrics
	local deploymentData = opts.deploymentData or self._deploymentData
	local waitForConfirmation = opts.waitForConfirmation or false

	-- Track execution start
	metrics.totalExecutions += 1
	local playerMetrics = getOrCreatePlayerMetrics(metrics, playerId)
	playerMetrics.executions += 1
	recordCallMetrics(metrics, calls)

	-- Get Promise from the account's provider
	local Promise = account:getProvider():getPromise()

	return Promise.new(function(resolve: (any) -> (), reject: (any) -> ())
		-- Step 1: Policy check (synchronous)
		if policy then
			local policyResult = policy:validate(playerId, calls)
			if not policyResult.allowed then
				metrics.totalFailed += 1
				playerMetrics.failed += 1
				local err = StarknetError.new(
					"SponsoredExecutor: policy rejected — " .. (policyResult.reason or "unknown"),
					ErrorCodes.PAYMASTER_POLICY_REJECTED.code,
					{ reason = policyResult.reason }
				)
				safeCall(callbacks.onTransactionFailed, {
					playerId = playerId,
					calls = calls,
					error = err,
					retryCount = 0,
					tokensRefunded = 0,
				})
				reject(err)
				return
			end
		end

		-- Step 2: Budget pre-check and consume (synchronous)
		local tokensCost = 0
		if budget then
			local cost: number
			if opts.txCost ~= nil then
				cost = opts.txCost
			else
				cost = budget:calculateCost(opts.gasUsed)
			end
			if not budget:canAfford(playerId, cost) then
				metrics.totalFailed += 1
				playerMetrics.failed += 1
				local err = StarknetError.new(
					"SponsoredExecutor: insufficient budget",
					ErrorCodes.INSUFFICIENT_BUDGET.code,
					{ playerId = playerId, required = cost, balance = budget:getBalance(playerId) }
				)
				safeCall(callbacks.onTransactionFailed, {
					playerId = playerId,
					calls = calls,
					error = err,
					retryCount = 0,
					tokensRefunded = 0,
				})
				reject(err)
				return
			end
			budget:consumeTransaction(playerId, cost)
			tokensCost = cost
			metrics.totalTokensConsumed += cost
		end

		-- Step 3: Execute with retry on transient errors
		local paymasterDetails: { [string]: any } = {
			paymaster = self._paymaster,
			feeMode = feeMode,
		}
		if deploymentData then
			paymasterDetails.deploymentData = deploymentData
		end

		local lastErr: any = nil
		local attempts = 0

		for attempt = 1, retryAttempts do
			attempts = attempt

			-- Exponential backoff before retry (not first attempt)
			if attempt > 1 then
				metrics.totalRetries += 1
				local delay = retryDelay * math.pow(2, attempt - 2)
				sleepFn(delay)
			end

			local ok, result = pcall(function()
				return account:executePaymaster(calls, paymasterDetails):expect()
			end)

			if ok then
				-- Paymaster accepted and submitted the transaction
				local retryCount = attempt - 1
				local txResult: SponsoredExecuteResult = {
					transactionHash = result.transactionHash,
					trackingId = result.trackingId,
					tokensCost = tokensCost,
					retryCount = retryCount,
				}

				-- Fire onTransactionSubmitted
				safeCall(callbacks.onTransactionSubmitted, {
					playerId = playerId,
					transactionHash = result.transactionHash,
					trackingId = result.trackingId,
					calls = calls,
					tokensCost = tokensCost,
				})

				-- Handle confirmation tracking
				local provider = account:getProvider()
				local hasWaitFn = provider and type(provider.waitForTransaction) == "function"

				if waitForConfirmation and hasWaitFn then
					local confirmOk, confirmErr = pcall(function()
						return provider:waitForTransaction(result.transactionHash):expect()
					end)
					if confirmOk then
						-- Transaction confirmed on-chain
						metrics.totalSuccessful += 1
						playerMetrics.successful += 1
						playerMetrics.tokensSpent += tokensCost
						if policy then
							policy:recordUsage(playerId)
						end
						safeCall(callbacks.onTransactionConfirmed, {
							playerId = playerId,
							transactionHash = result.transactionHash,
							calls = calls,
						})
						resolve(txResult)
					else
						-- Transaction reverted or timed out — refund budget
						metrics.totalFailed += 1
						playerMetrics.failed += 1
						if budget and tokensCost > 0 then
							budget:refundTransaction(playerId, tokensCost)
							metrics.totalTokensRefunded += tokensCost
						end
						safeCall(callbacks.onTransactionFailed, {
							playerId = playerId,
							calls = calls,
							error = confirmErr,
							retryCount = retryCount,
							tokensRefunded = tokensCost,
						})
						reject(confirmErr)
					end
				else
					-- No confirmation wait: optimistic success
					metrics.totalSuccessful += 1
					playerMetrics.successful += 1
					playerMetrics.tokensSpent += tokensCost
					if policy then
						policy:recordUsage(playerId)
					end
					resolve(txResult)
				end
				return
			end

			-- Execution failed
			lastErr = result

			-- Don't retry deterministic errors
			if not isTransientError(result) then
				break
			end
		end

		-- All attempts failed or deterministic error
		local retryCount = attempts - 1
		metrics.totalFailed += 1
		playerMetrics.failed += 1

		-- Refund budget tokens
		local tokensRefunded = 0
		if budget and tokensCost > 0 then
			budget:refundTransaction(playerId, tokensCost)
			metrics.totalTokensRefunded += tokensCost
			tokensRefunded = tokensCost
		end

		-- Fire onTransactionFailed callback
		safeCall(callbacks.onTransactionFailed, {
			playerId = playerId,
			calls = calls,
			error = lastErr,
			retryCount = retryCount,
			tokensRefunded = tokensRefunded,
		})

		-- Wrap with retry context if retries were attempted
		if retryCount > 0 and isTransientError(lastErr) then
			reject(
				StarknetError.new(
					`SponsoredExecutor: all {attempts} attempts failed — {tostring(lastErr)}`,
					ErrorCodes.SPONSORED_EXECUTION_FAILED.code,
					{ lastError = lastErr, attempts = attempts }
				)
			)
		else
			reject(lastErr)
		end
	end)
end

return SponsoredExecutor
