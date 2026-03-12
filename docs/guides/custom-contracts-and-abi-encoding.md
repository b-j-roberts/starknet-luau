# Custom Contracts & ABI Encoding

Interact with any Cairo contract using its ABI -- encode inputs, decode outputs, and handle complex types like structs, enums, arrays, Option, Result, and ByteArray.

## Prerequisites

- Completed [Guide 3: Accounts & Transactions](accounts-and-transactions.md) -- you know how to create accounts, execute transactions, and use `populate()` for multicall
- Your contract's ABI (exported from Scarb or copied from a block explorer)
- HttpService enabled in Game Settings

## Defining a Contract ABI

A Cairo ABI is a Luau table describing your contract's functions, structs, and enums. You only need to define the entries you actually use -- you don't need the full ABI.

### Function Entries

Every function has a `type`, `name`, `inputs`, `outputs`, and `state_mutability`:

```luau
{
	type = "function",
	name = "get_score",
	inputs = {
		{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
	},
	outputs = {
		{ name = "score", type = "core::integer::u128" },
	},
	state_mutability = "view", -- "view" for reads, "external" for writes
}
```

- `view` functions are read-only -- they go through `provider:call()` and don't require an account.
- `external` functions modify state -- they go through `account:execute()` and require a funded account.

### Interface Entries

Cairo ABIs often wrap functions inside `interface` entries. The SDK extracts nested functions automatically:

```luau
{
	type = "interface",
	name = "my_game::ILeaderboard",
	items = {
		{
			type = "function",
			name = "get_score",
			inputs = { { name = "player", type = "ContractAddress" } },
			outputs = { { name = "score", type = "core::integer::u128" } },
			state_mutability = "view",
		},
		{
			type = "function",
			name = "submit_score",
			inputs = {
				{ name = "player", type = "ContractAddress" },
				{ name = "score", type = "core::integer::u128" },
			},
			outputs = {},
			state_mutability = "external",
		},
	},
}
```

### Struct and Enum Entries

Define struct and enum entries so the codec knows how to encode and decode your custom types:

```luau
-- Struct
{
	type = "struct",
	name = "my_game::PlayerStats",
	members = {
		{ name = "wins", type = "core::integer::u32" },
		{ name = "losses", type = "core::integer::u32" },
		{ name = "rating", type = "core::felt252" },
	},
},

-- Enum
{
	type = "enum",
	name = "my_game::GameResult",
	variants = {
		{ name = "Win", type = "()" },
		{ name = "Loss", type = "()" },
		{ name = "Draw", type = "()" },
	},
}
```

## Creating a Contract Instance

Pass your ABI, the on-chain address, a provider, and optionally an account to `Contract.new()`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local GAME_ABI = {
	{
		type = "function",
		name = "get_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "submit_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "score", type = "core::integer::u128" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

local gameContract = Contract.new({
	abi = GAME_ABI,
	address = "0x_YOUR_CONTRACT_ADDRESS",
	provider = provider,
	account = account, -- omit for read-only usage
})
```

## Calling View Functions

View functions are callable directly on the contract instance via dynamic dispatch. The SDK matches method names against the ABI and routes `view` functions through `provider:call()`:

```luau
-- Dynamic dispatch: calls get_score as a view function
gameContract
	:get_score("0x_PLAYER_ADDRESS")
	:andThen(function(score)
		local numericScore = tonumber(score) or 0
		print("Player score:", numericScore)
	end)
	:catch(function(err)
		warn("Failed to read score:", tostring(err))
	end)
```

You can also call view functions explicitly with `contract:call()`:

```luau
gameContract
	:call("get_score", { "0x_PLAYER_ADDRESS" })
	:andThen(function(score)
		print("Score:", score)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

### Multiple Return Values

When a function has multiple outputs, the SDK returns a table keyed by the output parameter names:

```luau
-- ABI with multiple outputs:
-- outputs = {
--   { name = "wins", type = "core::integer::u32" },
--   { name = "losses", type = "core::integer::u32" },
-- }

gameContract
	:get_stats("0x_PLAYER_ADDRESS")
	:andThen(function(result)
		-- result is a table: { wins = "0x5", losses = "0x2" }
		print("Wins:", tonumber(result.wins))
		print("Losses:", tonumber(result.losses))
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

A single output is returned directly (not wrapped in a table).

## Invoking External Functions

External functions are also dispatched dynamically. With an `account` attached, the SDK routes `external` functions through `account:execute()`:

```luau
-- Dynamic dispatch: calls submit_score as an external function
gameContract
	:submit_score("0x_PLAYER_ADDRESS", "0x2A")
	:andThen(function(result)
		print("Tx submitted:", result.transactionHash)
		return account:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("Confirmed in block:", receipt.block_number)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

You can pass an options table as the last argument to control fees:

```luau
gameContract
	:submit_score("0x_PLAYER_ADDRESS", "0x2A", {
		feeMultiplier = 2.0,
	})
	:andThen(function(result)
		print("Tx:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

You can also invoke explicitly with `contract:invoke()`:

```luau
gameContract
	:invoke("submit_score", { "0x_PLAYER_ADDRESS", "0x2A" }, { feeMultiplier = 2.0 })
	:andThen(function(result)
		print("Tx:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

## Building Calls for Multicall

Use `contract:populate()` to build Call objects without executing them, then pass the array to `account:execute()` for atomic batching:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local GAME_ABI = {
	{
		type = "function",
		name = "submit_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "score", type = "core::integer::u128" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

local gameContract = Contract.new({
	abi = GAME_ABI,
	address = "0x_YOUR_CONTRACT_ADDRESS",
	provider = provider,
	account = account,
})

-- Build Call objects without executing
local calls = {}
local scores = {
	{ player = "0x_PLAYER_1", score = "0x3A98" }, -- 15000
	{ player = "0x_PLAYER_2", score = "0x6F54" }, -- 28500
	{ player = "0x_PLAYER_3", score = "0xA410" }, -- 42000
}

for _, entry in scores do
	-- populate() returns { contractAddress, entrypoint, calldata }
	local call = gameContract:populate("submit_score", { entry.player, entry.score })
	table.insert(calls, call)
end

-- Execute all calls atomically in one transaction
account
	:execute(calls, {
		feeMultiplier = 2.0,
	})
	:andThen(function(result)
		print("Batch submitted:", result.transactionHash)
		return account:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("Confirmed in block:", receipt.block_number)
	end)
	:catch(function(err)
		warn("Batch failed:", tostring(err))
	end)
```

You can mix calls to different contracts in the same batch -- just `populate()` from each contract and combine the results into one array.

## ABI Type System

The `AbiCodec` handles encoding and decoding for all Cairo types. Here's how each type maps between Luau and calldata.

### Primitive Types

| Cairo Type | Luau Input | Encoded As | Decoded As |
|-----------|-----------|-----------|-----------|
| `felt252` | hex string `"0x1a"` | 1 felt | hex string |
| `ContractAddress` | hex string | 1 felt | hex string |
| `ClassHash` | hex string | 1 felt | hex string |
| `bool` | `true` / `false` | 1 felt (`"0x1"` / `"0x0"`) | `boolean` |
| `u8` through `u128` | hex string `"0x2A"` | 1 felt | hex string |
| `u256` | hex string `"0xFFFF..."` | 2 felts (low, high) | `{ low = "0x...", high = "0x..." }` |
| `()` (unit) | `nil` | 0 felts | `nil` |

Integer types `u8`, `u16`, `u32`, `u64`, `u128`, `i8`, `i16`, etc. are all encoded as a single felt. Pass values as hex strings.

### u256

u256 values are automatically split into two 128-bit felts (low and high). Pass a single hex string and the SDK handles the split:

```luau
-- Input: a single hex string
-- Encoded as: two felts { low_128_bits, high_128_bits }
gameContract:submit_amount("0xDE0B6B3A7640000") -- 1e18
```

When decoded, u256 comes back as a table:

```luau
-- result = { low = "0xde0b6b3a7640000", high = "0x0" }
local raw = tonumber(result.low) or 0
```

### Structs

Structs are encoded as their members flattened in order. Pass a Luau table with keys matching the member names:

```luau
-- ABI struct:
-- {
--   type = "struct",
--   name = "my_game::PlayerStats",
--   members = {
--     { name = "wins", type = "core::integer::u32" },
--     { name = "losses", type = "core::integer::u32" },
--     { name = "rating", type = "core::felt252" },
--   },
-- }

-- Encode: pass a table with matching keys
gameContract:update_stats({
	wins = "0x5",
	losses = "0x2",
	rating = "0x3E8",
})

-- Decoded: returns the same table shape
-- result = { wins = "0x5", losses = "0x2", rating = "0x3e8" }
```

### Arrays and Spans

Both `Array<T>` and `Span<T>` are encoded the same way: a length prefix followed by each element. Pass a Luau array:

```luau
-- ABI input type: "core::array::Array::<core::felt252>"
-- Pass a Luau array
gameContract:set_scores({ "0x1", "0x2", "0x3" })
-- Encoded as: "0x3", "0x1", "0x2", "0x3" (length + elements)

-- Decoded: returns a Luau array
-- result = { "0x1", "0x2", "0x3" }
```

Arrays of structs work the same way -- each element is a table:

```luau
-- Array of PlayerStats structs
gameContract:set_all_stats({
	{ wins = "0x5", losses = "0x2", rating = "0x3E8" },
	{ wins = "0xA", losses = "0x1", rating = "0x7D0" },
})
```

### Option

`Option<T>` accepts flexible input formats but always decodes to a consistent shape:

```luau
-- Encoding: three accepted input formats
gameContract:set_nickname({ Some = "0x48656C6C6F" }) -- Some("Hello")
gameContract:set_nickname({ None = true })            -- None
gameContract:set_nickname(nil)                         -- None (nil → None)

-- Decoding: always returns { variant = "Some"/"None", value = ... }
gameContract
	:get_nickname("0x_PLAYER")
	:andThen(function(result)
		if result.variant == "Some" then
			print("Nickname:", result.value)
		else
			print("No nickname set")
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

### Result

`Result<T, E>` works like Option but with `Ok` and `Err` keys:

```luau
-- Encoding
gameContract:process({ Ok = "0x1" })
gameContract:process({ Err = "0x2" })

-- Decoding: { variant = "Ok"/"Err", value = ... }
gameContract
	:get_result()
	:andThen(function(result)
		if result.variant == "Ok" then
			print("Success:", result.value)
		else
			print("Error:", result.value)
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

### Custom Enums

Custom enums use a `{ variant = "Name", value = data }` format:

```luau
-- ABI enum:
-- {
--   type = "enum",
--   name = "my_game::GameResult",
--   variants = {
--     { name = "Win", type = "()" },
--     { name = "Loss", type = "()" },
--     { name = "Draw", type = "()" },
--   },
-- }

-- Encoding: specify the variant name and its data
gameContract:record_result({ variant = "Win", value = nil })
gameContract:record_result({ variant = "Loss", value = nil })

-- Decoding
gameContract
	:get_last_result()
	:andThen(function(result)
		-- result = { variant = "Win", value = nil }
		print("Last result:", result.variant)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

For enums with data in their variants:

```luau
-- ABI enum:
-- variants = {
--   { name = "Attack", type = "core::integer::u32" },       -- damage amount
--   { name = "Heal", type = "core::integer::u32" },         -- heal amount
--   { name = "Defend", type = "()" },                        -- no data
-- }

gameContract:perform_action({ variant = "Attack", value = "0x32" })  -- Attack(50)
gameContract:perform_action({ variant = "Defend", value = nil })     -- Defend
```

### Tuples

Tuples are encoded as their elements in order. Pass a Luau array:

```luau
-- ABI type: "(core::felt252, core::integer::u32)"
-- Pass as an array
gameContract:set_pair({ "0xABC", "0x5" })

-- Decoded as an array: { "0xabc", "0x5" }
```

### ByteArray

Cairo `ByteArray` handles strings longer than 31 bytes. The SDK encodes them as 31-byte chunks with a pending remainder. Pass a regular Luau string:

```luau
-- ABI input type: "core::byte_array::ByteArray"
-- Pass a plain Luau string -- the SDK chunks it automatically
gameContract:set_description("This is a long description that exceeds 31 bytes easily")

-- Decoded: returns the reconstructed Luau string
gameContract
	:get_description()
	:andThen(function(desc)
		print("Description:", desc) -- the original string
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

## Contract Introspection

Query the contract's ABI at runtime:

```luau
-- List all function names
local functions = gameContract:getFunctions()
print("Functions:", table.concat(functions, ", "))

-- Check if a function exists
if gameContract:hasFunction("submit_score") then
	print("submit_score is available")
end

-- Get parsed function metadata
local fn = gameContract:getFunction("submit_score")
if fn then
	print("Name:", fn.name)
	print("Mutability:", fn.stateMutability) -- "view" or "external"
	print("Selector:", fn.selector) -- hex string of sn_keccak(name)
	print("Inputs:", #fn.inputs)
	print("Outputs:", #fn.outputs)
end

-- List event names
local events = gameContract:getEvents()
print("Events:", table.concat(events, ", "))

-- Check if an event exists
if gameContract:hasEvent("Transfer") then
	print("Contract has Transfer event")
end
```

## Decoding Events

### From a Transaction Receipt

After submitting a transaction, decode events from the receipt using `contract:parseEvents()`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

local GAME_ABI = {
	{
		type = "function",
		name = "submit_score",
		inputs = {
			{ name = "player", type = "ContractAddress" },
			{ name = "score", type = "core::integer::u128" },
		},
		outputs = {},
		state_mutability = "external",
	},
	-- Event definition (modern Cairo format with key/data members)
	{
		type = "event",
		name = "my_game::ScoreSubmitted",
		kind = "struct",
		members = {
			{ name = "player", type = "ContractAddress", kind = "key" },
			{ name = "score", type = "core::integer::u128", kind = "data" },
		},
	},
}

local gameContract = Contract.new({
	abi = GAME_ABI,
	address = "0x_YOUR_CONTRACT_ADDRESS",
	provider = provider,
	account = account,
})

gameContract
	:submit_score("0x_PLAYER_ADDRESS", "0x2A")
	:andThen(function(result)
		return account:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		-- Decode events emitted by this contract
		local parsed = gameContract:parseEvents(receipt)

		for _, event in parsed.events do
			print("Event:", event.name) -- "ScoreSubmitted"
			print("Player:", event.fields.player)
			print("Score:", event.fields.score)
		end

		-- Check for decode errors (events that couldn't be parsed)
		for _, err in parsed.errors do
			warn("Failed to decode event:", err.error)
		end
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)
```

`parseEvents()` filters events by the contract's address, matches them by selector, and decodes key/data members. It returns `{ events = {...}, errors = {...} }` -- successfully decoded events and any that failed.

Pass `{ strict = true }` to re-throw decode errors instead of collecting them:

```luau
local parsed = gameContract:parseEvents(receipt, { strict = true })
-- Throws immediately if any event fails to decode
```

### Querying Historical Events

Use `contract:queryEvents()` to fetch events directly from the chain for a block range:

```luau
gameContract
	:queryEvents({
		from_block = { block_number = 100000 },
		to_block = { block_number = 100100 },
		chunk_size = 50, -- max events per RPC response (default 100)
	})
	:andThen(function(eventsChunk)
		-- eventsChunk.events is an array of raw events
		-- Decode them using parseEvents by wrapping in a receipt-like table
		local parsed = gameContract:parseEvents({ events = eventsChunk.events })
		for _, event in parsed.events do
			print(event.name, event.fields)
		end
	end)
	:catch(function(err)
		warn("Query failed:", tostring(err))
	end)
```

## Building Reusable Contract Presets

If you find yourself creating the same contract type repeatedly (e.g., a game token used across multiple scripts), use `PresetFactory` to build a reusable module like the built-in `ERC20` and `ERC721`:

```luau
--!strict
-- ReplicatedStorage/GameToken.luau
-- A reusable preset for your game's custom token contract.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local PresetFactory = StarknetLuau.contract.PresetFactory

local GAME_TOKEN_ABI = {
	{
		type = "function",
		name = "name",
		inputs = {},
		outputs = { { name = "name", type = "core::felt252" } },
		state_mutability = "view",
	},
	{
		type = "function",
		name = "balance_of",
		inputs = {
			{ name = "account", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "balance", type = "core::integer::u256" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "claim_reward",
		inputs = {},
		outputs = {},
		state_mutability = "external",
	},
}

-- Create the preset. The second argument lists view methods whose felt252 results
-- should be auto-decoded from hex to UTF-8 strings.
local GameToken = PresetFactory.create(GAME_TOKEN_ABI, { "name" })

return GameToken
```

Then use it from any server script:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))
local GameToken = require(ReplicatedStorage:WaitForChild("GameToken"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local account = Account.fromPrivateKey({
	privateKey = "0x_YOUR_PRIVATE_KEY",
	provider = provider,
})

-- PresetFactory.create() returns a module with .new(address, provider, account?)
local token = GameToken.new("0x_YOUR_TOKEN_ADDRESS", provider, account)

-- View call -- "name" is auto-decoded to a string by the shortStringMethods option
token
	:name()
	:andThen(function(name)
		print("Token name:", name) -- "Gold Coins" (string, not hex)
	end)
	:catch(function(err)
		warn("Failed:", tostring(err))
	end)

-- Write call
token
	:claim_reward()
	:andThen(function(result)
		print("Claimed! Tx:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Claim failed:", tostring(err))
	end)
```

`PresetFactory.create(abi, shortStringMethods?)` returns a table with:
- `.new(address, provider, account?)` -- creates a Contract instance
- `.getAbi()` -- returns the ABI table

## Complete Example: Game Leaderboard

A full working pattern combining reads, writes, multicall, and events for a game leaderboard contract:

```luau
--!strict
-- ServerScriptService/Leaderboard.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local RpcProvider = StarknetLuau.provider.RpcProvider
local Account = StarknetLuau.wallet.Account
local Contract = StarknetLuau.contract.Contract
local StarknetError = StarknetLuau.errors.StarknetError
local ErrorCodes = StarknetLuau.errors.ErrorCodes

local provider = RpcProvider.new({
	nodeUrl = "https://api.zan.top/public/starknet-sepolia",
})

local serverAccount = Account.fromPrivateKey({
	privateKey = "0x_YOUR_SERVER_PRIVATE_KEY",
	provider = provider,
})

local LEADERBOARD_ABI = {
	{
		type = "function",
		name = "get_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		outputs = {
			{ name = "score", type = "core::integer::u128" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "get_top_player",
		inputs = {},
		outputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
		},
		state_mutability = "view",
	},
	{
		type = "function",
		name = "submit_score",
		inputs = {
			{ name = "player", type = "core::starknet::contract_address::ContractAddress" },
			{ name = "score", type = "core::integer::u128" },
		},
		outputs = {},
		state_mutability = "external",
	},
}

local LEADERBOARD_ADDRESS = "0x_YOUR_LEADERBOARD_CONTRACT_ADDRESS"

-- One contract instance handles both reads and writes when an account is attached
local leaderboard = Contract.new({
	abi = LEADERBOARD_ABI,
	address = LEADERBOARD_ADDRESS,
	provider = provider,
	account = serverAccount,
})

-- Read: dynamic dispatch routes get_score through provider:call()
leaderboard
	:get_score("0x_PLAYER_ADDRESS")
	:andThen(function(score)
		print("Score:", tonumber(score) or 0)
	end)
	:catch(function(err)
		warn("Read failed:", tostring(err))
	end)

-- Write: dynamic dispatch routes submit_score through account:execute()
leaderboard
	:submit_score("0x_PLAYER_ADDRESS", string.format("0x%x", 42000))
	:andThen(function(result)
		print("Submitted:", result.transactionHash)
		return serverAccount:waitForReceipt(result.transactionHash)
	end)
	:andThen(function(receipt)
		print("Confirmed in block:", receipt.block_number)
	end)
	:catch(function(err)
		if StarknetError.isStarknetError(err) and err.code == ErrorCodes.TRANSACTION_REVERTED.code then
			warn("Reverted:", err.revertReason or err.message)
		else
			warn("Failed:", tostring(err))
		end
	end)

-- Batch: submit multiple scores in one atomic transaction
local calls = {}
local entries = {
	{ player = "0x_PLAYER_1", score = 15000 },
	{ player = "0x_PLAYER_2", score = 28500 },
	{ player = "0x_PLAYER_3", score = 42000 },
}

for _, entry in entries do
	local call = leaderboard:populate("submit_score", {
		entry.player,
		string.format("0x%x", entry.score),
	})
	table.insert(calls, call)
end

serverAccount
	:execute(calls)
	:andThen(function(result)
		print("Batch submitted:", result.transactionHash)
	end)
	:catch(function(err)
		warn("Batch failed:", tostring(err))
	end)
```

## Common Mistakes

**Option input is flexible, output is not.** You can pass `nil`, `{ Some = val }`, or `{ None = true }` when encoding. But decoded Option values always come back as `{ variant = "Some", value = ... }` or `{ variant = "None", value = nil }`. Don't check for `result == nil` -- check `result.variant`.

**Enum variant names are case-sensitive.** `{ variant = "win" }` won't match an ABI variant named `"Win"`. The SDK throws `UNKNOWN_ENUM_VARIANT` (error code 4004) if the name doesn't match exactly.

**All values must be hex strings.** When passing numbers as felt arguments, convert to hex first: `string.format("0x%x", 42000)` gives `"0xa410"`. Passing a raw Lua number directly won't work for ABI-typed inputs.

**u256 is two felts, not one.** See the [u256 section in Guide 2](reading-blockchain-data.md) for details on working with the `{ low, high }` format.

**`invoke()` requires an account.** If you create a contract without an account and call an `external` function, you'll get `REQUIRED_FIELD` (error code 1001). Either pass `account` in the `Contract.new()` config or use `populate()` + `account:execute()` instead.

**ABI must include struct/enum definitions.** If your function takes or returns a custom struct or enum, include the struct/enum ABI entry alongside the function entries. Without it, the codec falls back to encoding as a single felt, which corrupts the calldata.

## What's Next

For secure player wallet management and on-chain account deployment, see [Guide 5: Player Onboarding](player-onboarding.md). For gasless transactions where players don't need gas tokens, see [Guide 6: Sponsored Transactions](sponsored-transactions.md).
