# Common Patterns Guide

This guide covers practical patterns for integrating Starknet into Roblox games: NFT gating, token rewards, onchain leaderboards, and more.

## NFT Gating

Gate access to game content based on NFT ownership.

### Basic Balance Check

```luau
local ERC721 = Starknet.contract.ERC721

local nftContract = ERC721.new("0xNFT_CONTRACT_ADDRESS", provider)

local function checkNFTAccess(playerAddress: string): any
    return nftContract:balance_of(playerAddress):andThen(function(balance)
        local count = tonumber(balance.low, 16) or 0
        return count > 0
    end)
end

-- Usage in a player join handler
checkNFTAccess("0xPlayerWallet"):andThen(function(hasAccess)
    if hasAccess then
        -- Unlock exclusive area, skin, or feature
        grantAccess(player)
    else
        -- Show "NFT required" UI
        showNFTRequiredMessage(player)
    end
end)
```

### Specific Token ID Check

Verify ownership of a particular token:

```luau
local function ownsSpecificNFT(playerAddress: string, tokenId: string): any
    return nftContract:owner_of(tokenId):andThen(function(owner)
        return string.lower(owner) == string.lower(playerAddress)
    end):catch(function()
        return false  -- token may not exist
    end)
end
```

### Tiered Access (Multiple Collections)

```luau
local collections = {
    { address = "0xGOLD_PASS", tier = "gold" },
    { address = "0xSILVER_PASS", tier = "silver" },
    { address = "0xBRONZE_PASS", tier = "bronze" },
}

local function getPlayerTier(playerAddress: string): any
    -- Check collections from highest to lowest tier
    local function checkNext(index)
        if index > #collections then
            return Promise.resolve("free")  -- no NFTs found
        end

        local col = collections[index]
        local nft = ERC721.new(col.address, provider)

        return nft:balance_of(playerAddress):andThen(function(balance)
            if (tonumber(balance.low, 16) or 0) > 0 then
                return col.tier
            end
            return checkNext(index + 1)
        end)
    end

    return checkNext(1)
end
```

### Caching NFT Checks

NFT ownership doesn't change every second. Cache results to reduce RPC calls:

```luau
local nftCache: { [string]: { hasNFT: boolean, checkedAt: number } } = {}
local CACHE_TTL = 300  -- 5 minutes

local function checkNFTCached(playerAddress: string): any
    local cached = nftCache[playerAddress]
    if cached and (os.clock() - cached.checkedAt) < CACHE_TTL then
        return Promise.resolve(cached.hasNFT)
    end

    return nftContract:balance_of(playerAddress):andThen(function(balance)
        local hasNFT = (tonumber(balance.low, 16) or 0) > 0
        nftCache[playerAddress] = { hasNFT = hasNFT, checkedAt = os.clock() }
        return hasNFT
    end)
end
```

## Token Rewards

Award tokens to players for in-game achievements.

### Server-Side Token Distribution

```luau
local Account = Starknet.wallet.Account
local ERC20 = Starknet.contract.ERC20
local Constants = Starknet.constants

-- Server account that holds and distributes tokens
local serverAccount = Account.fromPrivateKey({
    privateKey = SERVER_PRIVATE_KEY,  -- stored securely (see Roblox guide)
    provider = provider,
})

local rewardToken = ERC20.new("0xTOKEN_ADDRESS", provider, serverAccount)

local function rewardPlayer(playerAddress: string, amount: string)
    rewardToken:transfer(playerAddress, amount)
        :andThen(function(result)
            print("Reward sent:", result.transactionHash)
            return serverAccount:waitForReceipt(result.transactionHash)
        end)
        :andThen(function(receipt)
            if receipt.execution_status == "SUCCEEDED" then
                print("Reward confirmed for", playerAddress)
            else
                warn("Reward reverted:", receipt.revert_reason)
            end
        end)
        :catch(function(err)
            warn("Reward failed:", tostring(err))
        end)
end
```

### Batch Rewards (Multicall)

Distribute rewards to multiple players in one transaction:

```luau
local function batchReward(rewards: { { address: string, amount: string } })
    local calls = {}
    for _, reward in rewards do
        table.insert(calls, rewardToken:populate("transfer", {
            reward.address,
            reward.amount,
        }))
    end

    serverAccount:execute(calls)
        :andThen(function(result)
            print("Batch reward tx:", result.transactionHash)
            return serverAccount:waitForReceipt(result.transactionHash)
        end)
        :andThen(function(receipt)
            print("All rewards confirmed in block:", receipt.block_number)
        end)
        :catch(function(err)
            warn("Batch reward failed:", tostring(err))
        end)
end

-- Award tokens to top 3 players at round end
batchReward({
    { address = "0xPlayer1", amount = "0xDE0B6B3A7640000" },  -- 1 token
    { address = "0xPlayer2", amount = "0x6F05B59D3B20000" },  -- 0.5 tokens
    { address = "0xPlayer3", amount = "0x2386F26FC10000" },   -- 0.01 tokens
})
```

### Queued Reward System

For high-traffic games, queue rewards and submit them periodically:

```luau
local pendingRewards: { { address: string, amount: string } } = {}
local BATCH_INTERVAL = 60  -- submit every 60 seconds

local function queueReward(playerAddress: string, amount: string)
    table.insert(pendingRewards, { address = playerAddress, amount = amount })
end

-- Periodically flush the reward queue
task.spawn(function()
    while true do
        task.wait(BATCH_INTERVAL)
        if #pendingRewards > 0 then
            local batch = pendingRewards
            pendingRewards = {}  -- reset immediately to avoid double-sending
            batchReward(batch)
        end
    end
end)

-- In your game logic:
queueReward("0xPlayerWallet", "0x1000")
```

## Onchain Leaderboard

Store game scores onchain for transparency and cross-game interoperability.

### Reading Scores

```luau
local Contract = Starknet.contract.Contract

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

local leaderboard = Contract.new({
    abi = LEADERBOARD_ABI,
    address = "0xLEADERBOARD_ADDRESS",
    provider = provider,
})

-- Read a player's score
leaderboard:get_score("0xPlayer"):andThen(function(score)
    local numericScore = tonumber(score, 16) or 0
    print("Score:", numericScore)
end)
```

### Submitting Scores

```luau
local leaderboardWriter = Contract.new({
    abi = LEADERBOARD_ABI,
    address = "0xLEADERBOARD_ADDRESS",
    provider = provider,
    account = serverAccount,
})

local function submitScore(playerAddress: string, score: number)
    local scoreHex = string.format("0x%x", score)

    leaderboardWriter:submit_score(playerAddress, scoreHex)
        :andThen(function(result)
            print("Score submitted:", result.transactionHash)
        end)
        :catch(function(err)
            warn("Score submission failed:", tostring(err))
        end)
end
```

### Batch Score Submission

```luau
local function submitScoresBatch(entries: { { address: string, score: number } })
    local calls = {}
    for _, entry in entries do
        local scoreHex = string.format("0x%x", entry.score)
        table.insert(calls, leaderboardWriter:populate("submit_score", {
            entry.address,
            scoreHex,
        }))
    end

    serverAccount:execute(calls)
        :andThen(function(result)
            print("Batch scores submitted:", result.transactionHash)
        end)
end
```

## Onchain Game State

Store verifiable game state on Starknet.

### Reading Game State

```luau
local GAME_ABI = {
    {
        type = "function",
        name = "get_player_data",
        inputs = {
            { name = "player", type = "core::starknet::contract_address::ContractAddress" },
        },
        outputs = {
            { name = "level", type = "core::integer::u32" },
            { name = "experience", type = "core::integer::u64" },
            { name = "guild_id", type = "core::felt252" },
        },
        state_mutability = "view",
    },
}

local gameState = Contract.new({
    abi = GAME_ABI,
    address = "0xGAME_STATE_CONTRACT",
    provider = provider,
})

-- Multiple outputs are returned as a table keyed by parameter name
gameState:get_player_data("0xPlayer"):andThen(function(data)
    print("Level:", data.level)
    print("Experience:", data.experience)
    print("Guild:", data.guild_id)
end)
```

### Writing Game State

```luau
local gameWriter = Contract.new({
    abi = GAME_ABI,
    address = "0xGAME_STATE_CONTRACT",
    provider = provider,
    account = serverAccount,
})

-- Update player progress
gameWriter:update_player("0xPlayer", "0xA", "0x1000", "0x1")
    :andThen(function(result)
        print("State updated:", result.transactionHash)
    end)
```

## Event Querying

Listen for onchain events to sync game state:

```luau
-- Query transfer events from an ERC-20 contract
provider:getEvents({
    from_block = { block_number = 100000 },
    to_block = "latest",
    address = Constants.STRK_TOKEN_ADDRESS,
    keys = { { Keccak.getSelectorFromName("Transfer") } },
    chunk_size = 100,
}):andThen(function(result)
    for _, event in result.events do
        print("Transfer event:")
        print("  From:", event.data[1])
        print("  To:", event.data[2])
        print("  Amount:", event.data[3])
    end

    -- Check for more events
    if result.continuation_token then
        -- Fetch next page using continuation_token
    end
end)
```

### Event Polling

Use EventPoller for continuous monitoring:

```luau
local EventPoller = Starknet.provider.EventPoller

local poller = EventPoller.new({
    provider = provider,
    filter = {
        address = "0xCONTRACT",
        keys = { { selectorHex } },
    },
    interval = 10,  -- poll every 10 seconds
    onEvents = function(events)
        for _, event in events do
            -- Process each new event
            handleGameEvent(event)
        end
    end,
})

poller:start()
-- Later: poller:stop()
```

## Wallet Linking

Link a player's Roblox account to their Starknet wallet.

### Server-Side Verification Flow

```luau
-- 1. Generate a challenge for the player
local challenges: { [number]: string } = {}

local function generateChallenge(player: Player): string
    local challenge = string.format("0x%x", math.random(1, 2^48))
    challenges[player.UserId] = challenge
    return challenge
end

-- 2. Player signs the challenge with their wallet (off-game, e.g., via web)
-- 3. Server verifies the signature
local ECDSA = Starknet.crypto.ECDSA
local StarkField = Starknet.crypto.StarkField

local function verifyWalletLink(
    player: Player,
    walletAddress: string,
    publicKeyHex: string,
    signatureR: string,
    signatureS: string
): boolean
    local challenge = challenges[player.UserId]
    if not challenge then
        return false
    end

    local messageHash = StarkField.fromHex(challenge)
    local publicKey = {
        x = StarkField.fromHex(publicKeyHex),
        y = StarkField.fromHex("0x0"),  -- need full point
    }
    local sig = {
        r = StarkField.fromHex(signatureR),
        s = StarkField.fromHex(signatureS),
    }

    local valid = ECDSA.verify(messageHash, publicKey, sig)
    challenges[player.UserId] = nil  -- consume the challenge

    return valid
end
```

## Best Practices Summary

1. **Cache aggressively** -- NFT ownership and token balances don't change every frame. Cache for 1-5 minutes.
2. **Batch operations** -- Use multicall to combine multiple contract calls into one transaction.
3. **Queue writes** -- For high-throughput reward distribution, queue and batch-submit periodically.
4. **Server-side only** -- All Starknet operations must run on the server (HttpService limitation).
5. **Handle failures gracefully** -- Network calls can fail. Always use `:catch()` and show appropriate UI.
6. **Fee estimation** -- Use `estimateFee` before large transactions to avoid overpaying.
7. **Use the right account type** -- Match the class hash to whatever wallet the player uses.

## Next Steps

- [Roblox Considerations](roblox.md) -- Rate limits, security, performance
- [Contract Interaction](contracts.md) -- Deep dive into contract APIs
- [Getting Started](getting-started.md) -- Basic setup if you haven't started yet
