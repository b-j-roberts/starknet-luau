--!strict
-- event-listener.luau
-- Poll for on-chain events using EventPoller with DataStore persistence.
--
-- This example shows how to:
--   1. Configure an EventPoller with a Transfer event filter
--   2. Use onCheckpoint callback for DataStore persistence
--   3. Handle incoming events in a callback
--   4. Resume from the last checkpoint after a server restart
--   5. Stop the poller gracefully on shutdown
--
-- EventPoller continuously queries starknet_getEvents and delivers new events
-- to your callback. Checkpoint persistence ensures no events are missed across
-- server restarts.
--
-- Roblox-only: This script requires HttpService and DataStoreService enabled.
-- Runs in ServerScriptService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local EventPoller = StarknetLuau.provider.EventPoller
local Constants = StarknetLuau.constants
local StarknetError = StarknetLuau.errors.StarknetError

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local SEPOLIA_RPC = "https://api.zan.top/public/starknet-sepolia"

-- Contract to monitor for events (ETH token in this example)
local MONITORED_CONTRACT = Constants.ETH_TOKEN_ADDRESS

-- Transfer event key (keccak hash of "Transfer")
-- You can compute this with: StarknetLuau.crypto.Keccak.starknetKeccak("Transfer")
local TRANSFER_EVENT_KEY = "0x99cd8bde557814842a3121e8ddfd433a539b8c9f14bf31ebf108d12e6196e9"

-- Polling interval in seconds
local POLL_INTERVAL = 15

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local provider = RpcProvider.new({
	nodeUrl = SEPOLIA_RPC,
})

-- DataStore for persisting the last processed block number.
-- On server restart, the poller resumes from this checkpoint instead of
-- re-processing all historical events.
local checkpointStore = DataStoreService:GetDataStore("EventPollerCheckpoints")

--------------------------------------------------------------------------------
-- Event handler callback
--------------------------------------------------------------------------------

--- Called whenever the poller finds new events matching the filter.
--- Events arrive in chronological order within each poll batch.
local function handleTransferEvents(events: { any })
	for _, event in events do
		-- Each event has: block_number, transaction_hash, keys, data
		print("[Events] Transfer detected:")
		print(`  Block: {event.block_number}`)
		print(`  Tx: {event.transaction_hash}`)

		-- For a Transfer event, keys typically contain:
		--   keys[1] = event selector (Transfer)
		--   keys[2] = from address
		--   keys[3] = to address
		-- And data contains:
		--   data[1] = amount low (u256)
		--   data[2] = amount high (u256)
		if event.keys and #event.keys >= 3 then
			print(`  From: {event.keys[2]}`)
			print(`  To: {event.keys[3]}`)
		end
		if event.data and #event.data >= 1 then
			print(`  Amount (low): {event.data[1]}`)
		end
	end

	print(`[Events] Processed {#events} transfer(s)`)
end

--------------------------------------------------------------------------------
-- Create and start the EventPoller
--------------------------------------------------------------------------------

local poller = EventPoller.new({
	provider = provider,

	-- Filter: which events to fetch
	filter = {
		address = MONITORED_CONTRACT,
		keys = { { TRANSFER_EVENT_KEY } }, -- match Transfer events
		chunk_size = 100, -- max events per RPC call
	},

	-- Callback: invoked with each batch of new events
	onEvents = handleTransferEvents,

	-- Error callback: handle polling errors without crashing the loop
	onError = function(err)
		if StarknetError.isStarknetError(err) then
			warn("[Events] RPC error during poll:", tostring(err))
		else
			warn("[Events] Poll error:", tostring(err))
		end
	end,

	-- Checkpoint callback: called after each successful poll with the latest
	-- block number. Use this to persist progress to DataStore.
	onCheckpoint = function(blockNumber: number)
		local ok, storeErr = pcall(function()
			checkpointStore:SetAsync("transfer_poller_block", blockNumber)
		end)
		if not ok then
			warn("[Events] Failed to save checkpoint:", tostring(storeErr))
		end
	end,

	-- Polling interval (seconds between each getEvents call)
	interval = POLL_INTERVAL,

	-- DataStore integration: automatically restores checkpoint on start()
	_dataStore = checkpointStore,
	checkpointKey = "transfer_poller_block",
})

-- Start the poller in a background thread.
-- start() is a blocking call that loops until stop() is called.
-- It automatically restores the last checkpoint from DataStore.
task.spawn(function()
	print("[Events] Starting event poller...")
	print(`[Events] Monitoring: {MONITORED_CONTRACT}`)
	print(`[Events] Poll interval: {POLL_INTERVAL}s`)

	local lastBlock = poller:getLastBlockNumber()
	if lastBlock then
		print(`[Events] Resuming from block: {lastBlock}`)
	else
		print("[Events] Starting from latest block (no checkpoint)")
	end

	-- This blocks until poller:stop() is called
	poller:start()
	print("[Events] Poller stopped")
end)

--------------------------------------------------------------------------------
-- Graceful shutdown
--------------------------------------------------------------------------------

-- Stop the poller when the game server shuts down
game:BindToClose(function()
	print("[Events] Server shutting down — stopping poller...")
	poller:stop()
end)

print("[Events] Event listener system initialized")

return {
	poller = poller,
}
