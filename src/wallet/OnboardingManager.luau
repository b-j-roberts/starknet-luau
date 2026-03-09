--!strict
-- OnboardingManager: One-call player onboarding orchestration layer
-- Composes KeyStore + Account deployment into a single onboard(playerId) call.
-- Handles key generation, deployment (direct or paymaster-sponsored), and status tracking.

local StarknetError = require("../errors/StarknetError")
local ErrorCodes = StarknetError.ErrorCodes

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type OnboardingConfig = {
	keyStore: any,
	provider: any,
	paymasterDetails: {
		paymaster: any,
		feeMode: { mode: string, gasToken: string? },
		deploymentData: { classHash: string, calldata: { string }, salt: string, sigdata: { string }? }?,
	}?,
	waitForConfirmation: boolean?,
	dryRun: boolean?,
}

export type OnboardingResult = {
	account: any,
	address: string,
	isNew: boolean,
	wasDeployed: boolean,
	alreadyDeployed: boolean,
	transactionHash: string?,
	trackingId: string?,
}

export type OnboardingStatus = {
	hasAccount: boolean,
	isDeployed: boolean,
	address: string?,
}

--------------------------------------------------------------------------------
-- OnboardingManager class
--------------------------------------------------------------------------------

local OnboardingManager = {}
OnboardingManager.__index = OnboardingManager

--- Create a new OnboardingManager.
function OnboardingManager.new(config: OnboardingConfig): any
	if not config.keyStore then
		error(StarknetError.validation("OnboardingManager: keyStore is required", ErrorCodes.REQUIRED_FIELD.code))
	end
	if not config.provider then
		error(StarknetError.validation("OnboardingManager: provider is required", ErrorCodes.REQUIRED_FIELD.code))
	end

	local self = setmetatable({
		_keyStore = config.keyStore,
		_provider = config.provider,
		_paymasterDetails = config.paymasterDetails,
		_waitForConfirmation = if config.waitForConfirmation ~= nil then config.waitForConfirmation else true,
		_dryRun = config.dryRun or false,
	}, OnboardingManager)

	return self :: any
end

--- Deploy an account if not already deployed.
--- Returns { transactionHash, contractAddress, trackingId?, alreadyDeployed? }.
function OnboardingManager:_deployIfNeeded(account: any): {
	transactionHash: string?,
	contractAddress: string?,
	trackingId: string?,
	alreadyDeployed: boolean?,
}
	local ok, result
	if self._paymasterDetails then
		ok, result = pcall(function()
			return account
				:deployWithPaymaster(self._paymasterDetails, {
					waitForConfirmation = self._waitForConfirmation,
				})
				:expect()
		end)
	else
		ok, result = pcall(function()
			return account
				:deployAccount({
					waitForConfirmation = self._waitForConfirmation,
					dryRun = self._dryRun,
				})
				:expect()
		end)
	end

	if not ok then
		error(
			StarknetError.transaction(
				`OnboardingManager: deployment failed: {tostring(result)}`,
				ErrorCodes.ONBOARDING_ERROR.code
			)
		)
	end

	return result
end

--- Primary onboarding API. Call from PlayerAdded.
--- Creates or loads account key, deploys if needed, marks deployed.
function OnboardingManager:onboard(playerId: number): OnboardingResult
	-- Step 1: Get or create key
	local keyResult = self._keyStore:getOrCreate(playerId, self._provider)
	local account = keyResult.account
	local isNew = keyResult.isNew

	-- Step 2: Check if already deployed in KeyStore
	if self._keyStore:isDeployed(playerId) then
		return {
			account = account,
			address = account.address,
			isNew = isNew,
			wasDeployed = false,
			alreadyDeployed = true,
		}
	end

	-- Step 3: Deploy
	local deployResult = self:_deployIfNeeded(account)

	-- Step 4: Handle chain-level idempotency (account was deployed but KeyStore didn't know)
	if deployResult.alreadyDeployed then
		self._keyStore:markDeployed(playerId)
		return {
			account = account,
			address = account.address,
			isNew = isNew,
			wasDeployed = false,
			alreadyDeployed = true,
			transactionHash = deployResult.transactionHash,
			trackingId = deployResult.trackingId,
		}
	end

	-- Step 5: Mark deployed (skip for dryRun)
	if not self._dryRun then
		self._keyStore:markDeployed(playerId)
	end

	return {
		account = account,
		address = account.address,
		isNew = isNew,
		wasDeployed = true,
		alreadyDeployed = false,
		transactionHash = deployResult.transactionHash,
		trackingId = deployResult.trackingId,
	}
end

--- Get onboarding status for a player without decryption or RPC calls.
function OnboardingManager:getStatus(playerId: number): OnboardingStatus
	local record = self._keyStore:getRecord(playerId)
	if record == nil then
		return {
			hasAccount = false,
			isDeployed = false,
		}
	end

	return {
		hasAccount = true,
		isDeployed = record.deployedAt ~= nil,
		address = record.address,
	}
end

--- Ensure an existing account is deployed. Errors if no account exists.
function OnboardingManager:ensureDeployed(playerId: number): OnboardingResult
	-- Step 1: Check if already deployed
	if self._keyStore:isDeployed(playerId) then
		local account = self._keyStore:loadAccount(playerId, self._provider)
		if not account then
			error(
				StarknetError.transaction(
					`OnboardingManager: account record exists but load failed for player {playerId}`,
					ErrorCodes.ONBOARDING_ERROR.code
				)
			)
		end
		return {
			account = account,
			address = account.address,
			isNew = false,
			wasDeployed = false,
			alreadyDeployed = true,
		}
	end

	-- Step 2: Load account (must exist)
	local account = self._keyStore:loadAccount(playerId, self._provider)
	if not account then
		error(
			StarknetError.transaction(
				`OnboardingManager: no account found for player {playerId}`,
				ErrorCodes.ONBOARDING_ERROR.code
			)
		)
	end

	-- Step 3: Deploy
	local deployResult = self:_deployIfNeeded(account)

	-- Step 4: Handle chain-level idempotency
	if deployResult.alreadyDeployed then
		self._keyStore:markDeployed(playerId)
		return {
			account = account,
			address = account.address,
			isNew = false,
			wasDeployed = false,
			alreadyDeployed = true,
			transactionHash = deployResult.transactionHash,
			trackingId = deployResult.trackingId,
		}
	end

	-- Step 5: Mark deployed (skip for dryRun)
	if not self._dryRun then
		self._keyStore:markDeployed(playerId)
	end

	return {
		account = account,
		address = account.address,
		isNew = false,
		wasDeployed = true,
		alreadyDeployed = false,
		transactionHash = deployResult.transactionHash,
		trackingId = deployResult.trackingId,
	}
end

--- Remove a player's key. Delegates to keyStore:deleteKey().
function OnboardingManager:removePlayer(playerId: number): ()
	self._keyStore:deleteKey(playerId)
end

return OnboardingManager
