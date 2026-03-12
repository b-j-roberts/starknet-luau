# Contract Interaction Guide

This guide covers how to interact with Starknet smart contracts: reading state, writing transactions, using presets, building custom ABIs, batching operations with multicall, querying events, and using the ABI codec.

## Overview

starknet-luau provides three levels of contract interaction:

1. **ERC-20 / ERC-721 presets** -- Zero-config token interaction
2. **Custom contracts via ABI** -- Define your own ABI and get typed methods
3. **Raw provider calls** -- Direct RPC calls for full control

## ERC-20 Token Interaction

The `ERC20` preset comes with a built-in ABI for standard ERC-20 tokens.

### Reading Token Data (No Account Needed)

```luau
local ERC20 = Starknet.contract.ERC20
local Constants = Starknet.constants

-- Create a read-only ERC-20 instance
local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider)

-- Read metadata
strkToken:name():andThen(function(name)
    print("Token name:", name)  -- "Starknet Token"
end)

strkToken:symbol():andThen(function(symbol)
    print("Symbol:", symbol)    -- "STRK"
end)

strkToken:decimals():andThen(function(decimals)
    print("Decimals:", decimals) -- 18
end)

-- Read a balance (returns u256 as { low: string, high: string })
strkToken:balance_of("0x123..."):andThen(function(balance)
    print("Balance (low 128 bits):", balance.low)
    print("Balance (high 128 bits):", balance.high)
end)

-- Read allowance
strkToken:allowance("0xOwner...", "0xSpender..."):andThen(function(allowance)
    print("Allowance:", allowance.low)
end)

-- Read total supply
strkToken:total_supply():andThen(function(supply)
    print("Total supply:", supply.low)
end)
```

Both snake_case and camelCase method names work: `balance_of` / `balanceOf`, `total_supply` / `totalSupply`, `transfer_from` / `transferFrom`.

### Writing (Account Required)

```luau
-- Create an ERC-20 instance with an account for write access
local strkToken = ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider, account)

-- Transfer tokens
strkToken:transfer("0xRecipient...", "0x38D7EA4C68000")
    :andThen(function(result)
        print("Tx hash:", result.transactionHash)
        return account:waitForReceipt(result.transactionHash)
    end)
    :andThen(function(receipt)
        print("Confirmed:", receipt.finality_status)
    end)
    :catch(function(err)
        warn("Transfer failed:", tostring(err))
    end)

-- Approve a spender
strkToken:approve("0xSpender...", "0xFFFFFFFF")
    :andThen(function(result)
        print("Approval tx:", result.transactionHash)
    end)
```

### Getting the ABI

```luau
local abi = ERC20.getAbi()  -- returns the full Cairo ABI table
```

## ERC-721 NFT Interaction

The `ERC721` preset works the same way for NFT contracts.

### Reading

```luau
local ERC721 = Starknet.contract.ERC721

local nft = ERC721.new("0xNFT_CONTRACT_ADDRESS", provider)

-- Check how many NFTs an address owns
nft:balance_of("0xOwner..."):andThen(function(balance)
    local count = tonumber(balance.low) or 0
    print("NFTs owned:", count)
end)

-- Check who owns a specific token
nft:owner_of("0x1"):andThen(function(owner)  -- token ID as hex
    print("Owner of token #1:", owner)
end)

-- Check approval
nft:get_approved("0x1"):andThen(function(approved)
    print("Approved for token #1:", approved)
end)
```

Both snake_case and camelCase: `owner_of` / `ownerOf`, `get_approved` / `getApproved`, `is_approved_for_all` / `isApprovedForAll`, `transfer_from` / `transferFrom`, `set_approval_for_all` / `setApprovalForAll`.

### Writing

```luau
local nft = ERC721.new("0xNFT_CONTRACT_ADDRESS", provider, account)

-- Transfer an NFT
nft:transfer_from("0xFrom...", "0xTo...", "0x1")
    :andThen(function(result)
        print("Transfer tx:", result.transactionHash)
    end)
```

### Getting the ABI

```luau
local abi = ERC721.getAbi()
```

## PresetFactory

Create your own presets from any ABI:

```luau
local PresetFactory = Starknet.contract.PresetFactory

local MyToken = PresetFactory.create(MY_TOKEN_ABI, { "name", "symbol" })
-- The second argument lists methods whose return values should be decoded as short strings

local token = MyToken.new("0xCONTRACT_ADDRESS", provider, account)
token:name():andThen(function(name) print(name) end)

local abi = MyToken.getAbi()
```

## Custom Contracts

For contracts beyond ERC-20/721, define a custom ABI:

### Defining an ABI

The ABI is a Luau table matching Cairo's ABI JSON format:

```luau
local GAME_ABI = {
    -- View function (read-only, no gas cost)
    {
        type = "function",
        name = "get_player_score",
        inputs = {
            { name = "player", type = "core::starknet::contract_address::ContractAddress" },
        },
        outputs = {
            { name = "score", type = "core::integer::u128" },
        },
        state_mutability = "view",
    },
    -- External function (writes state, costs gas)
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
    -- Event definition (for parsing transaction receipts)
    {
        type = "event",
        name = "ScoreSubmitted",
        kind = "struct",
        members = {
            { name = "player", type = "core::starknet::contract_address::ContractAddress", kind = "key" },
            { name = "score", type = "core::integer::u128", kind = "data" },
        },
    },
}
```

### Creating a Contract Instance

```luau
local Contract = Starknet.contract.Contract

-- Read-only (no account)
local gameReader = Contract.new({
    abi = GAME_ABI,
    address = "0xGAME_CONTRACT_ADDRESS",
    provider = provider,
})

-- Read + write (with account)
local gameWriter = Contract.new({
    abi = GAME_ABI,
    address = "0xGAME_CONTRACT_ADDRESS",
    provider = provider,
    account = account,
})
```

### Dynamic Dispatch

The contract automatically generates methods from the ABI:

```luau
-- View functions → call() (no gas, returns data)
gameReader:get_player_score("0xPlayer..."):andThen(function(score)
    print("Score:", score)
end)

-- External functions → invoke() (costs gas, returns tx hash)
gameWriter:submit_score("0xPlayer...", "0x2A"):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

### Explicit call/invoke

You can also call methods explicitly:

```luau
-- Explicit call (view), with optional blockId
gameReader:call("get_player_score", { "0xPlayer..." }, "latest")
    :andThen(function(result)
        print("Raw result:", result)
    end)

-- Explicit invoke (external)
gameWriter:invoke("submit_score", { "0xPlayer...", "0x2A" })
    :andThen(function(result)
        print("Tx:", result.transactionHash)
    end)
```

### Contract Introspection

```luau
-- List all functions in the ABI
local functions = contract:getFunctions()  -- { "get_player_score", "submit_score" }

-- Get metadata for a specific function
local fn = contract:getFunction("get_player_score")
-- { name, inputs, outputs, stateMutability }

-- Check if a function exists
if contract:hasFunction("submit_score") then
    -- ...
end

-- List all events
local events = contract:getEvents()  -- { "ScoreSubmitted" }

-- Check if an event exists
if contract:hasEvent("ScoreSubmitted") then
    -- ...
end
```

## Cairo Type Mapping

The ABI codec automatically handles type encoding/decoding:

| Cairo Type | Luau Input | Luau Output | Felt Count |
|------------|-----------|-------------|------------|
| `felt252` | hex string `"0x123"` | hex string | 1 |
| `ContractAddress` | hex string | hex string | 1 |
| `bool` | `true` / `false` | `true` / `false` | 1 |
| `u8` through `u128` | hex string | hex string | 1 |
| `u256` | hex string | `{ low, high }` | 2 |
| `Array<T>` / `Span<T>` | `{ item1, item2, ... }` | `{ item1, item2, ... }` | 1 + n*T |
| `ByteArray` | Luau string | Luau string | varies |
| `struct` | `{ field1 = val, ... }` | `{ field1 = val, ... }` | sum(fields) |
| `Option<T>` | `{ Some = val }` / `{ None = true }` / `nil` | `{ variant, value }` | varies |
| `Result<T, E>` | `{ Ok = val }` / `{ Err = val }` | `{ variant, value }` | varies |
| `enum` | `{ variant = "Name", value = data }` | `{ variant, value }` | varies |
| `()` (unit) | n/a | n/a | 0 |

### u256 Values

u256 is encoded as two felts (low 128 bits, high 128 bits):

```luau
-- Input: pass a hex string, the codec splits it automatically
contract:transfer("0xRecipient", "0xDE0B6B3A7640000") -- 1e18

-- Output: returned as { low: string, high: string }
contract:balance_of("0x..."):andThen(function(balance)
    print(balance.low)   -- "0xde0b6b3a7640000"
    print(balance.high)  -- "0x0"
end)
```

### ByteArray (Strings)

Cairo's `ByteArray` type is automatically encoded/decoded:

```luau
-- Input: pass a regular Luau string
contract:set_name("My Game Token")

-- Output: returned as a Luau string
contract:name():andThen(function(name)
    print(name) -- "My Game Token"
end)
```

## Multicall (Batching)

Multicall combines multiple contract calls into a single transaction. This saves gas and ensures atomicity (all calls succeed or all revert).

### Building Calls with populate()

Use `populate()` to build Call objects without executing:

```luau
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)

-- Build calls without executing
local call1 = ethToken:populate("transfer", { "0xRecipient1", "0x1000" })
local call2 = ethToken:populate("transfer", { "0xRecipient2", "0x2000" })
local call3 = ethToken:populate("approve",  { "0xSpender",    "0xFFFF" })

-- Execute all atomically in one transaction
account:execute({ call1, call2, call3 })
    :andThen(function(result)
        print("Batch tx:", result.transactionHash)
    end)
```

### Cross-Contract Multicall

You can batch calls across different contracts:

```luau
local ethToken = ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)
local gameContract = Contract.new({
    abi = GAME_ABI,
    address = "0xGAME...",
    provider = provider,
    account = account,
})

-- Approve + interact in one transaction
local approveCall = ethToken:populate("approve", { "0xGAME...", "0x1000" })
local actionCall = gameContract:populate("enter_game", { "0x1000" })

account:execute({ approveCall, actionCall })
    :andThen(function(result)
        print("Approve + enter in one tx:", result.transactionHash)
    end)
```

### Fee Estimation

Estimate fees before executing:

```luau
local calls = { call1, call2, call3 }

account:estimateFee(calls):andThen(function(estimate)
    print("Gas consumed:", estimate.gas_consumed)
    print("Overall fee:", estimate.overall_fee)
    print("Unit:", estimate.unit)
end)
```

## Event Parsing

Parse events from transaction receipts using the contract's ABI:

```luau
-- After a transaction is confirmed
account:execute(calls)
    :andThen(function(result)
        return account:waitForReceipt(result.transactionHash)
    end)
    :andThen(function(receipt)
        local parsed = contract:parseEvents(receipt)
        for _, event in parsed.events do
            print("Event:", event)
        end
        -- In strict mode, errors are surfaced:
        -- local parsed = contract:parseEvents(receipt, { strict = true })
        -- parsed.errors contains { { event, error } } for events that failed to decode
    end)
```

### Querying Events from the Chain

```luau
-- Query events matching the contract's ABI
contract:queryEvents({
    from_block = { block_number = 100000 },
    to_block = { block_tag = "latest" },
    chunk_size = 100,
}):andThen(function(events)
    for _, event in events do
        print("Event:", event)
    end
end)
```

## Event Polling

Use `EventPoller` for continuous event monitoring:

```luau
local EventPoller = Starknet.provider.EventPoller
local Keccak = Starknet.crypto.Keccak
local StarkField = Starknet.crypto.StarkField

local selectorHex = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))

local poller = EventPoller.new({
    provider = provider,
    filter = {
        address = "0xCONTRACT",
        keys = { { selectorHex } },
    },
    interval = 10,  -- poll every 10 seconds
    onEvents = function(events)
        for _, event in events do
            handleGameEvent(event)
        end
    end,
    onError = function(err)
        warn("Poller error:", tostring(err))
    end,
})

poller:start()
-- Later: poller:stop()
```

### DataStore Persistence

For production, persist the last processed block number so you don't re-process events after a server restart:

```luau
local poller = EventPoller.new({
    provider = provider,
    filter = { address = "0xCONTRACT", keys = { { selectorHex } } },
    interval = 10,
    onEvents = function(events) processEvents(events) end,
    -- DataStore persistence
    _dataStore = DataStoreService:GetDataStore("EventPollerState"),
    checkpointKey = "MyGame_TransferEvents",  -- unique key per poller
    onCheckpoint = function(blockNumber)
        print("Checkpointed at block:", blockNumber)
    end,
})

-- The poller restores its last block number from DataStore on start
poller:start()

-- Manual control
poller:setLastBlockNumber(150000)  -- override starting block
local lastBlock = poller:getLastBlockNumber()
local key = poller:getCheckpointKey()
```

## AbiCodec (Public API)

The `AbiCodec` is exported publicly for advanced use cases like manual encoding/decoding:

```luau
local AbiCodec = Starknet.contract.AbiCodec

-- Build a type map from an ABI
local typeMap = AbiCodec.buildTypeMap(myAbi)

-- Resolve a type definition
local typeDef = AbiCodec.resolveType("core::integer::u256", typeMap)
-- { kind = "u256" }

-- Encode a value
local felts = AbiCodec.encode("0x1000", "core::integer::u128", typeMap)
-- { "0x1000" }

-- Decode from calldata
local value, consumed = AbiCodec.decode({ "0x1000", "0x0" }, 1, "core::integer::u256", typeMap)
-- value = { low = "0x1000", high = "0x0" }, consumed = 2

-- Encode function inputs
local calldata = AbiCodec.encodeInputs(args, functionDef.inputs, typeMap)

-- Decode function outputs
local result = AbiCodec.decodeOutputs(resultFelts, functionDef.outputs, typeMap)

-- Decode an event
local eventData = AbiCodec.decodeEvent(keys, data, eventDef, typeMap)

-- ByteArray helpers (re-exported)
local felts = AbiCodec.encodeByteArray("Hello, World!")
local str, consumed = AbiCodec.decodeByteArray(felts, 1)
```

## Interface-Based ABIs

Cairo contracts often use interfaces. The ABI codec handles nested interface items:

```luau
local ABI = {
    {
        type = "interface",
        name = "IMyContract",
        items = {
            {
                type = "function",
                name = "get_value",
                inputs = {},
                outputs = { { name = "value", type = "core::felt252" } },
                state_mutability = "view",
            },
            {
                type = "function",
                name = "set_value",
                inputs = { { name = "value", type = "core::felt252" } },
                outputs = {},
                state_mutability = "external",
            },
        },
    },
}

-- Functions inside interfaces are extracted and available at the top level
local contract = Contract.new({ abi = ABI, address = "0x...", provider = provider })
contract:get_value():andThen(function(value)
    print(value)
end)
```

## Error Handling

Contract calls can fail for several reasons:

```luau
contract:some_function("0xArg")
    :andThen(function(result)
        -- Success
    end)
    :catch(function(err)
        local StarknetError = Starknet.errors.StarknetError

        if StarknetError.isStarknetError(err) then
            if err:is("AbiError") then
                -- ABI encoding/decoding issue
                warn("ABI error:", err.message)
            elseif err:is("RpcError") then
                -- RPC node returned an error
                warn("RPC error:", err.message, "code:", err.code)
            elseif err:is("TransactionError") then
                -- Transaction was reverted
                warn("Reverted:", err.revertReason)
            end
        else
            warn("Unknown error:", tostring(err))
        end
    end)
```

## Next Steps

- [Account Management](accounts.md) -- Setting up accounts for write operations
- [Common Patterns](patterns.md) -- NFT gating, leaderboards, token rewards
- [API Reference](api-reference.md) -- Complete Contract, ERC20, ERC721, AbiCodec, PresetFactory, EventPoller API
