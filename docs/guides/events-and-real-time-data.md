# Events & Real-Time Data

Monitor on-chain events continuously and react to blockchain state changes in your game -- live leaderboards, trade notifications, NFT minting alerts, and more.

## Prerequisites

- Completed [Guide 2: Reading Blockchain Data](reading-blockchain-data.md) -- you have a working `RpcProvider` and can read contract state
- HttpService enabled in Game Settings
- DataStoreService enabled (for checkpoint persistence across server restarts)

## How Starknet Events Work

When a Cairo contract emits an event, it produces a record containing:

- **`from_address`** -- the contract that emitted the event
- **`keys`** -- an array of hex strings. `keys[1]` is the event selector (a keccak hash of the event name). Remaining keys hold indexed parameters (marked `kind = "key"` in the ABI).
- **`data`** -- an array of hex strings containing non-indexed parameters (marked `kind = "data"` in the ABI).
- **`block_number`**, **`block_hash`**, **`transaction_hash`** -- context about when and where the event occurred.

For example, an ERC-20 `Transfer` event has `from` and `to` as keys, and `value` (a u256 split into low/high) as data:

```
keys[1] = 0x99cd8b...  (keccak of "Transfer")
keys[2] = 0xABC...     (from address)
keys[3] = 0xDEF...     (to address)
data[1] = 0x1000       (amount low)
data[2] = 0x0          (amount high)
```

## One-Shot Event Queries

### `provider:getEvents()` -- Single Page

Fetch a page of events matching a filter. Returns a Promise resolving to `{ events, continuation_token }`.

```luau
--!strict
-- ServerScriptService/QueryEvents.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- Compute the Transfer event selector
local transferSelector = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))

provider
	:getEvents({
		from_block = { block_number = 100000 },
		to_block = "latest",
		address = Constants.STRK_TOKEN_ADDRESS,
		keys = { { transferSelector } },
		chunk_size = 50,
	})
	:andThen(function(result)
		print("Found", #result.events, "events")

		for _, event in result.events do
			print("Block:", event.block_number, "Tx:", event.transaction_hash)
		end

		-- If there are more events, result.continuation_token is non-nil
		if result.continuation_token then
			print("More events available -- pass continuation_token for next page")
		end
	end)
	:catch(function(err)
		warn("Failed to query events:", tostring(err))
	end)
```

### Event Filter Reference

| Field | Type | Description |
|-------|------|-------------|
| `from_block` | `{block_number = N}`, `{block_hash = "0x..."}`, `"latest"`, `"pending"` | Start of range (inclusive) |
| `to_block` | same as above | End of range (inclusive) |
| `address` | `string?` | Filter to events from this contract |
| `keys` | `{{string}}?` | Array of key arrays. `keys[1]` filters on selector. |
| `chunk_size` | `number?` | Max events per RPC response (default 100) |
| `continuation_token` | `string?` | Pagination cursor from previous response |

The `keys` filter is an array of arrays. Each position filters the corresponding `keys[N]` of the event. Use an empty inner array `{}` to match any value at that position:

```luau
-- Match Transfer events FROM a specific address
keys = {
	{ transferSelector },     -- keys[1] must be Transfer
	{ "0xABC_FROM_ADDRESS" }, -- keys[2] must be this sender
}

-- Match Transfer events TO a specific address (any sender)
keys = {
	{ transferSelector },     -- keys[1] must be Transfer
	{},                       -- keys[2] can be anything
	{ "0xDEF_TO_ADDRESS" },   -- keys[3] must be this recipient
}
```

### `provider:getAllEvents()` -- Auto-Paginated

When you want every matching event without manual pagination, use `getAllEvents()`. It handles continuation tokens internally and returns a flat array of all events:

```luau
provider
	:getAllEvents({
		from_block = { block_number = 100000 },
		to_block = { block_number = 100500 },
		address = Constants.STRK_TOKEN_ADDRESS,
		keys = { { transferSelector } },
	})
	:andThen(function(events)
		print("Total events found:", #events)
		for _, event in events do
			print("  Block:", event.block_number, "From:", event.keys[2])
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

Use `getAllEvents` for bounded historical queries where you know the block range. For open-ended monitoring, use `EventPoller` (next section).

## Continuous Polling with EventPoller

`EventPoller` runs a background loop that calls `starknet_getEvents` at a configurable interval, delivering new events to your callback. It tracks the last processed block number so each poll only fetches new events.

### Basic Setup

```luau
--!strict
-- ServerScriptService/EventListener.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local EventPoller = StarknetLuau.provider.EventPoller
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local transferSelector = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))

local poller = EventPoller.new({
	provider = provider,

	filter = {
		address = Constants.STRK_TOKEN_ADDRESS,
		keys = { { transferSelector } },
		chunk_size = 100,
	},

	onEvents = function(events)
		for _, event in events do
			print("Transfer detected in block", event.block_number)
			print("  From:", event.keys[2])
			print("  To:", event.keys[3])
			print("  Amount (low):", event.data[1])
		end
	end,

	onError = function(err)
		warn("Poll error:", tostring(err))
	end,

	interval = 15, -- seconds between polls (default 10)
})

-- start() blocks until stop() is called -- run in a background thread
task.spawn(function()
	poller:start()
end)

-- Stop gracefully on server shutdown
game:BindToClose(function()
	poller:stop()
end)
```

On the first call to `start()`, if no `from_block` is set in the filter, the poller fetches the current block number from the provider and begins polling from there. Each subsequent poll starts from the block after the last event it processed.

### EventPoller Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | RpcProvider | **required** | The RPC provider to use |
| `filter` | EventFilter | **required** | Which events to fetch |
| `onEvents` | `(events) -> ()` | **required** | Callback with new events |
| `onError` | `(err) -> ()` | no-op | Called on poll errors |
| `onCheckpoint` | `(blockNumber) -> ()` | nil | Called after advancing block |
| `interval` | number | 10 | Seconds between polls |
| `_dataStore` | DataStore | nil | For automatic checkpoint restore |
| `checkpointKey` | string | `"EventPoller_checkpoint"` | DataStore key name |

### EventPoller Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `start()` | void | Blocking poll loop -- run in `task.spawn` |
| `stop()` | void | Signals the loop to exit after current poll |
| `isRunning()` | boolean | Whether the poller is actively polling |
| `getLastBlockNumber()` | number? | Last successfully polled block (nil if none) |
| `setLastBlockNumber(n)` | void | Manually set resume point before calling `start()` |
| `getCheckpointKey()` | string? | Configured DataStore key (nil if no DataStore) |

## Surviving Server Restarts with Checkpoints

Without persistence, a server restart means the poller starts from the current block and any events emitted during downtime are missed. Checkpoints solve this.

### DataStore Persistence

Pass a DataStore and checkpoint key to the poller. It will automatically restore the last block number on `start()` and save progress via the `onCheckpoint` callback:

```luau
--!strict
-- ServerScriptService/PersistentPoller.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local EventPoller = StarknetLuau.provider.EventPoller
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField
local Constants = StarknetLuau.constants

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local transferSelector = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))
local checkpointStore = DataStoreService:GetDataStore("EventPollerCheckpoints")

local poller = EventPoller.new({
	provider = provider,

	filter = {
		address = Constants.STRK_TOKEN_ADDRESS,
		keys = { { transferSelector } },
		chunk_size = 100,
	},

	onEvents = function(events)
		for _, event in events do
			-- Process each event (update game state, notify players, etc.)
			print("Transfer:", event.keys[2], "->", event.keys[3])
		end
	end,

	onError = function(err)
		warn("Poll error:", tostring(err))
	end,

	-- Called after each poll cycle that advances the block number.
	-- Persist to DataStore so we resume from here after restart.
	onCheckpoint = function(blockNumber: number)
		local ok, storeErr = pcall(function()
			checkpointStore:SetAsync("strk_transfers_block", blockNumber)
		end)
		if not ok then
			warn("Failed to save checkpoint:", tostring(storeErr))
		end
	end,

	interval = 15,

	-- Auto-restore: on start(), reads this key from the DataStore
	-- and resumes from the stored block number
	_dataStore = checkpointStore,
	checkpointKey = "strk_transfers_block",
})

task.spawn(function()
	local lastBlock = poller:getLastBlockNumber()
	if lastBlock then
		print("Resuming from block", lastBlock)
	else
		print("Starting from latest block (no checkpoint)")
	end

	poller:start()
end)

game:BindToClose(function()
	poller:stop()
end)
```

The checkpoint lifecycle:

1. **First start (no checkpoint):** Poller fetches current block number from the provider and begins there.
2. **Events arrive:** After processing, `onCheckpoint` fires with the highest block number seen. You save it to DataStore.
3. **Server restarts:** On `start()`, the poller reads the DataStore via `_dataStore:GetAsync(checkpointKey)` and resumes from that block.
4. **Manual recovery:** Call `poller:setLastBlockNumber(n)` before `start()` to override the resume point.

## Decoding Events with Contract ABI

Raw events give you hex strings in `keys` and `data`. If you have the contract's ABI, the `Contract` class can decode events into named fields automatically.

### Parsing Events from a Transaction Receipt

After submitting a transaction, parse its receipt to extract typed event data:

```luau
--!strict
-- ServerScriptService/ParseReceipt.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Contract = StarknetLuau.contract.Contract
local Account = StarknetLuau.wallet.Account

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

-- ABI with event definitions
local TOKEN_ABI = {
	{
		type = "function",
		name = "transfer",
		inputs = {
			{ name = "recipient", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "amount", type = "core::integer::u256" },
		},
		outputs = { { name = "success", type = "core::bool" } },
		state_mutability = "external",
	},
	{
		type = "event",
		name = "Transfer",
		kind = "struct",
		members = {
			{ name = "from", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "to", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
			{ name = "value", type = "core::integer::u256", kind = "data" },
		},
	},
}

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local token = Contract.new({
	abi = TOKEN_ABI,
	address = "0x_TOKEN_CONTRACT_ADDRESS",
	provider = provider,
	account = account,
})

-- Execute a transfer and parse the receipt events
token
	:transfer("0x_RECIPIENT", "0x1000")
	:andThen(function(result)
		-- Wait for the receipt
		return provider:getTransactionReceipt(result.transaction_hash)
	end)
	:andThen(function(receipt)
		-- parseEvents decodes all events from this contract in the receipt
		local parsed = token:parseEvents(receipt)

		for _, event in parsed.events do
			print("Event:", event.name) -- "Transfer"
			print("  from:", event.fields.from)
			print("  to:", event.fields.to)
			print("  value:", event.fields.value.low, event.fields.value.high)
		end

		-- Any events that failed to decode are in parsed.errors
		for _, parseErr in parsed.errors do
			warn("Failed to decode event:", parseErr.error)
		end
	end)
	:catch(function(err)
		warn("Transaction failed:", tostring(err))
	end)
```

`parseEvents` returns `{ events, errors }`:

- **`events`** -- array of `{ name: string, fields: {[string]: any}, raw: Event }`. Fields are decoded according to the ABI types (u256 becomes `{ low, high }`, addresses are hex strings, etc.).
- **`errors`** -- array of `{ event: Event, error: string }` for events that matched the contract address but failed to decode. Empty unless decoding went wrong.

Pass `{ strict = true }` to throw on the first decode error instead of collecting them:

```luau
-- Throws immediately if any event fails to decode
local parsed = token:parseEvents(receipt, { strict = true })
```

### Querying Historical Events from a Contract

`queryEvents` combines `provider:getEvents()` with the contract's address:

```luau
token
	:queryEvents({
		from_block = { block_number = 100000 },
		to_block = "latest",
		chunk_size = 50,
	})
	:andThen(function(result)
		-- result.events are raw EmittedEvent objects (not ABI-decoded)
		print("Found", #result.events, "events from this contract")
	end)
	:catch(function(err)
		warn("Query failed:", tostring(err))
	end)
```

Note: `queryEvents` returns raw events (hex keys/data), not ABI-decoded ones. To decode them, you'd parse them manually or combine with `parseEvents` on a receipt.

### Contract Event Introspection

```luau
-- List all events defined in the ABI
local eventNames = token:getEvents()
print("Events:", table.concat(eventNames, ", ")) -- "Approval, Transfer"

-- Check if a specific event is defined
if token:hasEvent("Transfer") then
	print("Contract has Transfer event")
end
```

## Computing Event Selectors

Event selectors are the keccak hash of the event name, masked to 250 bits (a Starknet felt). Use `Keccak.getSelectorFromName()`:

```luau
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField

-- Compute selector and convert to hex for use in filters
local selector = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))
-- selector = "0x99cd8bde557814842a3121e8ddfd433a539b8c9f14bf31ebf108d12e6196e9"
```

`getSelectorFromName` returns a `Felt` (StarkField element). Convert to hex with `StarkField.toHex()` for use in event filters or comparisons.

## Practical Pattern: Live NFT Minting Feed

React to NFT mints in real time -- when a new token is minted on-chain, spawn the corresponding item in your game:

```luau
--!strict
-- ServerScriptService/NFTMintFeed.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local EventPoller = StarknetLuau.provider.EventPoller
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local NFT_CONTRACT = "0x_YOUR_NFT_CONTRACT"
local transferSelector = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))
local ZERO_ADDRESS = "0x0"

-- Track player Starknet addresses (set during onboarding)
local playerAddresses: { [string]: Player } = {} -- starknet address -> Player

local checkpointStore = DataStoreService:GetDataStore("NFTMintCheckpoints")

local poller = EventPoller.new({
	provider = provider,

	filter = {
		address = NFT_CONTRACT,
		keys = {
			{ transferSelector }, -- Transfer events only
			{ ZERO_ADDRESS },     -- from = 0x0 means mint (not a regular transfer)
		},
		chunk_size = 100,
	},

	onEvents = function(events)
		for _, event in events do
			local toAddress = event.keys[3]
			local tokenIdLow = event.data[1]

			-- Check if the mint recipient is a connected player
			local player = playerAddresses[toAddress]
			if player then
				print(player.Name, "minted NFT #" .. tokenIdLow)
				-- Fire a client event to spawn the item in-game
				local spawnEvent = ReplicatedStorage:FindFirstChild("NFTMinted")
				if spawnEvent and spawnEvent:IsA("RemoteEvent") then
					spawnEvent:FireClient(player, tokenIdLow)
				end
			end
		end
	end,

	onError = function(err)
		warn("NFT poller error:", tostring(err))
	end,

	onCheckpoint = function(blockNumber: number)
		pcall(function()
			checkpointStore:SetAsync("nft_mint_block", blockNumber)
		end)
	end,

	interval = 10,
	_dataStore = checkpointStore,
	checkpointKey = "nft_mint_block",
})

task.spawn(function()
	poller:start()
end)

game:BindToClose(function()
	poller:stop()
end)
```

This pattern:
1. Filters Transfer events where `from = 0x0` (mints only, not regular transfers)
2. Looks up the recipient in a map of connected players
3. Fires a RemoteEvent to the player's client to spawn the item
4. Persists checkpoints so no mints are missed across restarts

## Practical Pattern: On-Chain Leaderboard Sync

Poll for score update events and maintain a server-side leaderboard that stays synchronized with the blockchain:

```luau
--!strict
-- ServerScriptService/LeaderboardSync.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local EventPoller = StarknetLuau.provider.EventPoller
local Keccak = StarknetLuau.crypto.Keccak
local StarkField = StarknetLuau.crypto.StarkField

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local GAME_CONTRACT = "0x_YOUR_GAME_CONTRACT"
local scoreSelector = StarkField.toHex(Keccak.getSelectorFromName("ScoreUpdated"))

-- In-memory leaderboard
local scores: { [string]: number } = {} -- address -> score

local checkpointStore = DataStoreService:GetDataStore("LeaderboardCheckpoints")

local poller = EventPoller.new({
	provider = provider,

	filter = {
		address = GAME_CONTRACT,
		keys = { { scoreSelector } },
		chunk_size = 100,
	},

	onEvents = function(events)
		for _, event in events do
			-- Assuming ScoreUpdated has: keys[2]=player, data[1]=newScore
			local player = event.keys[2]
			local newScore = tonumber(event.data[1]) or 0
			scores[player] = newScore
		end

		-- Update a Roblox leaderboard UI, fire RemoteEvents, etc.
		print("Leaderboard updated, tracking", 0, "players") -- replace 0 with table size logic
	end,

	onError = function(err)
		warn("Leaderboard poll error:", tostring(err))
	end,

	onCheckpoint = function(blockNumber: number)
		pcall(function()
			checkpointStore:SetAsync("leaderboard_block", blockNumber)
		end)
	end,

	interval = 10,
	_dataStore = checkpointStore,
	checkpointKey = "leaderboard_block",
})

task.spawn(function()
	poller:start()
end)

game:BindToClose(function()
	poller:stop()
end)
```

## Common Mistakes

**No WebSockets in Roblox.** Roblox only supports outbound HTTP requests via HttpService. There is no WebSocket or server-sent events support. `EventPoller` uses HTTP polling, so your minimum latency equals your `interval` setting. For most game features, 10-15 seconds is a good balance between responsiveness and RPC rate limits.

**`start()` blocks the thread.** `EventPoller:start()` runs a loop that doesn't return until `stop()` is called. Always wrap it in `task.spawn()` or it will freeze your script:

```luau
-- WRONG: blocks the entire script
poller:start()
print("This never runs")

-- CORRECT: runs in background
task.spawn(function()
	poller:start()
end)
print("This runs immediately")
```

**DataStore requires a published place.** The `_dataStore` checkpoint persistence only works in published Roblox experiences. In Studio testing without publishing, DataStore calls will fail silently (the poller handles this gracefully and continues polling, but checkpoints won't persist).

**Events from other contracts are silently skipped.** `parseEvents` only decodes events where `from_address` matches the contract instance's address. Events from other contracts in the same transaction receipt are ignored -- they won't appear in either `events` or `errors`.

**Event selectors are case-sensitive.** `getSelectorFromName("Transfer")` and `getSelectorFromName("transfer")` produce different selectors. Event names in Cairo are typically PascalCase (`Transfer`, `Approval`), while function names are snake_case (`balance_of`). Match the exact name from the ABI.

**`getAllEvents` is for bounded queries.** It accumulates every matching event into memory. For open-ended monitoring (no fixed `to_block`), use `EventPoller` instead. Calling `getAllEvents` with `to_block = "latest"` over a large block range can return thousands of events and consume significant memory.

## What's Next

You now have the tools to build reactive game features driven by on-chain data. For production deployments, [Guide 8: Production Configuration](production-configuration.md) covers rate limiting, caching, and error handling to keep your event polling reliable under load.
