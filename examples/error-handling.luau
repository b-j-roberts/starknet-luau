--!strict
-- error-handling.luau
-- Demonstrate StarknetError types, :is() checks, and recovery patterns.
--
-- This example shows how to:
--   1. Catch and inspect structured StarknetError instances
--   2. Use :is() to check error type hierarchy (RpcError, ValidationError, etc.)
--   3. Use ErrorCodes constants for precise error matching
--   4. Implement recovery patterns for RPC errors, reverts, and validation failures
--   5. Distinguish transient vs permanent errors for retry logic
--
-- The SDK throws structured errors instead of plain strings. Every error has:
--   - message: human-readable description
--   - code: numeric error code (from ErrorCodes)
--   - _type: error category (RpcError, SigningError, AbiError, etc.)
--   - :is(type): check if error belongs to a category (walks parent hierarchy)
--
-- Roblox-only: This script requires HttpService enabled and runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local ERC20 = StarknetLuau.contract.ERC20
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- WARNING: Never hardcode private keys in production code.
local PRIVATE_KEY = "0x_YOUR_PRIVATE_KEY_HERE"

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

local account = Account.fromPrivateKey({
	privateKey = PRIVATE_KEY,
	provider = provider,
})

local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

--------------------------------------------------------------------------------
-- Pattern 1: Basic error inspection with :is()
--------------------------------------------------------------------------------

--- Demonstrates catching and classifying errors by type.
local function demonstrateErrorTypes()
	print("[Errors] --- Pattern 1: Error type inspection ---")

	-- Attempt a call that might fail
	ethToken
		:balance_of("0x_INVALID_ADDRESS")
		:andThen(function(balance)
			print("[Errors] Balance:", balance.low)
		end)
		:catch(function(err)
			-- Check if it's a structured StarknetError
			if not StarknetError.isStarknetError(err) then
				warn("[Errors] Non-SDK error:", tostring(err))
				return
			end

			-- Use :is() to check the error type hierarchy
			-- :is() walks up the parent chain: RpcError → StarknetError
			if err:is("RpcError") then
				print("[Errors] RPC error:", err.message)
				print("[Errors] Error code:", err.code)
			elseif err:is("ValidationError") then
				print("[Errors] Validation error:", err.message)
				if err.hint then
					print("[Errors] Hint:", err.hint)
				end
			elseif err:is("AbiError") then
				print("[Errors] ABI encoding error:", err.message)
			else
				print("[Errors] Other StarknetError:", tostring(err))
			end
		end)
end

--------------------------------------------------------------------------------
-- Pattern 2: ErrorCodes for precise matching
--------------------------------------------------------------------------------

--- Demonstrates matching specific error codes for targeted recovery.
local function demonstrateErrorCodes()
	print("[Errors] --- Pattern 2: ErrorCodes matching ---")

	account
		:execute({
			ethToken:populate("transfer", {
				"0x_RECIPIENT",
				"0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF", -- absurdly large amount
			}),
		})
		:catch(function(err)
			if not StarknetError.isStarknetError(err) then
				warn("[Errors] Unknown error:", tostring(err))
				return
			end

			-- Match specific error codes for targeted handling
			if err.code == ErrorCodes.TRANSACTION_REVERTED.code then
				-- Transaction executed but reverted on-chain (e.g., insufficient balance)
				print("[Errors] Transaction reverted!")
				if err.revertReason then
					print("[Errors] Revert reason:", err.revertReason)
				end
			elseif err.code == ErrorCodes.TRANSACTION_REJECTED.code then
				-- Node rejected the transaction before execution (bad nonce, fee too low)
				print("[Errors] Transaction rejected by node:", err.message)
			elseif err.code == ErrorCodes.FEE_ESTIMATION_FAILED.code then
				-- Fee estimation failed (usually means the call would revert)
				print("[Errors] Fee estimation failed — call would likely revert")
			elseif err.code == ErrorCodes.NETWORK_ERROR.code then
				-- Network connectivity issue
				print("[Errors] Network error — check RPC connectivity")
			elseif err.code == ErrorCodes.RATE_LIMIT.code then
				-- Rate limited by RPC provider
				print("[Errors] Rate limited — slow down requests")
			else
				print(`[Errors] Error code {err.code}: {err.message}`)
			end
		end)
end

--------------------------------------------------------------------------------
-- Pattern 3: Transient vs permanent error classification
--------------------------------------------------------------------------------

--- Demonstrates using ErrorCodes.isTransient() for retry decisions.
local function demonstrateRetryLogic()
	print("[Errors] --- Pattern 3: Retry logic ---")

	local MAX_RETRIES = 3

	local function executeWithRetry(calls, attempt)
		attempt = attempt or 1

		return account:execute(calls):catch(function(err)
			if not StarknetError.isStarknetError(err) then
				error(err) -- re-throw non-SDK errors
			end

			-- isTransient returns true for: NETWORK_ERROR, RATE_LIMIT, PAYMASTER_UNAVAILABLE
			-- These are worth retrying. Permanent errors (TRANSACTION_REVERTED, etc.) are not.
			if ErrorCodes.isTransient(err.code) and attempt < MAX_RETRIES then
				local delay = 2 ^ attempt -- exponential backoff: 2, 4, 8 seconds
				print(`[Errors] Transient error (attempt {attempt}/{MAX_RETRIES}), retrying in {delay}s...`)
				task.wait(delay)
				return executeWithRetry(calls, attempt + 1)
			end

			-- Permanent error or max retries exhausted
			if attempt >= MAX_RETRIES then
				warn(`[Errors] Max retries exhausted after {MAX_RETRIES} attempts`)
			end
			error(err) -- re-throw
		end)
	end

	-- Usage: wrap any execute call with retry logic
	local transferCall = ethToken:populate("transfer", { "0x_RECIPIENT", "0x38D7EA4C68000" })

	executeWithRetry({ transferCall })
		:andThen(function(result)
			print("[Errors] Transaction succeeded:", result.transactionHash)
		end)
		:catch(function(err)
			warn("[Errors] Final failure:", tostring(err))
		end)
end

--------------------------------------------------------------------------------
-- Pattern 4: Transaction receipt error handling
--------------------------------------------------------------------------------

--- Demonstrates handling errors from waitForTransaction.
local function demonstrateReceiptErrors()
	print("[Errors] --- Pattern 4: Receipt error handling ---")

	local SOME_TX_HASH = "0x_SOME_TRANSACTION_HASH"

	provider
		:waitForTransaction(SOME_TX_HASH, {
			retryInterval = 5,
			maxAttempts = 20,
		})
		:andThen(function(receipt)
			-- Check the execution status in the receipt
			if receipt.execution_status == "REVERTED" then
				warn("[Errors] Transaction reverted on-chain!")
				if receipt.revert_reason then
					warn("[Errors] Reason:", receipt.revert_reason)
				end
				-- Handle revert: refund player, show error UI, etc.
				return
			end

			print("[Errors] Transaction succeeded!")
			print("[Errors] Block:", receipt.block_number)
			print("[Errors] Status:", receipt.finality_status)
		end)
		:catch(function(err)
			if StarknetError.isStarknetError(err) then
				if err.code == ErrorCodes.TIMEOUT.code then
					warn("[Errors] Transaction timed out — it may still be pending")
				elseif err.code == ErrorCodes.TRANSACTION_REJECTED.code then
					warn("[Errors] Transaction was rejected:", err.message)
				else
					warn("[Errors] Receipt error:", tostring(err))
				end
			else
				warn("[Errors] Unknown error:", tostring(err))
			end
		end)
end

--------------------------------------------------------------------------------
-- Pattern 5: pcall-style error handling (synchronous context)
--------------------------------------------------------------------------------

--- Demonstrates using pcall to catch errors in synchronous code paths.
local function demonstratePcallPattern()
	print("[Errors] --- Pattern 5: pcall pattern ---")

	-- Some SDK methods throw synchronously (e.g., validation errors).
	-- Use pcall to catch them without a Promise.
	local ok, err = pcall(function()
		-- This will throw a ValidationError if the private key is invalid
		Account.fromPrivateKey({
			privateKey = "not_a_valid_key",
			provider = provider,
		})
	end)

	if not ok then
		if StarknetError.isStarknetError(err) then
			print("[Errors] Caught validation error:", err.message)
			print("[Errors] Error code:", err.code)
			print("[Errors] Is ValidationError:", err:is("ValidationError"))
			print("[Errors] Is StarknetError:", err:is("StarknetError"))
		else
			warn("[Errors] Unexpected error:", tostring(err))
		end
	end
end

--------------------------------------------------------------------------------
-- Run all demonstrations
--------------------------------------------------------------------------------

demonstrateErrorTypes()
demonstrateErrorCodes()
demonstrateRetryLogic()
demonstrateReceiptErrors()
demonstratePcallPattern()

return {}
