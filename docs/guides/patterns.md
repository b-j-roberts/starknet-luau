# Common Patterns Guide

This guide covers practical patterns for integrating Starknet into Roblox games: NFT gating, token rewards, onchain leaderboards, sponsored transactions, account deployment, error handling, and more.

## NFT Gating

Gate access to game content based on NFT ownership.

### Basic Balance Check

```luau
local ERC721 = Starknet.contract.ERC721
local BigInt = Starknet.crypto.BigInt

local nftContract = ERC721.new("0xNFT_CONTRACT_ADDRESS", provider)

local function checkNFTAccess(playerAddress: string): any
    return nftContract:balance_of(playerAddress):andThen(function(balance)
        local count = tonumber(balance.low) or 0
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
        -- Normalize addresses through BigInt for consistent comparison
        return BigInt.toHex(BigInt.fromHex(owner)) == BigInt.toHex(BigInt.fromHex(playerAddress))
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
            if (tonumber(balance.low) or 0) > 0 then
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
        local hasNFT = (tonumber(balance.low) or 0) > 0
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
    local numericScore = tonumber(score) or 0
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

## Event Querying

Listen for onchain events to sync game state:

```luau
local Keccak = Starknet.crypto.Keccak
local StarkField = Starknet.crypto.StarkField

-- Compute the selector and convert buffer→hex
local selectorHex = StarkField.toHex(Keccak.getSelectorFromName("Transfer"))

-- Query transfer events from an ERC-20 contract
provider:getEvents({
    from_block = { block_number = 100000 },
    to_block = { block_tag = "latest" },
    address = Constants.STRK_TOKEN_ADDRESS,
    keys = { { selectorHex } },
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

## Sponsored Transactions (Paymaster)

Use a paymaster to let players transact without paying gas fees:

### Using SponsoredExecutor

```luau
local SponsoredExecutor = Starknet.paymaster.SponsoredExecutor
local AvnuPaymaster = Starknet.paymaster.AvnuPaymaster
local PaymasterPolicy = Starknet.paymaster.PaymasterPolicy
local PaymasterBudget = Starknet.paymaster.PaymasterBudget

-- Set up the paymaster client
local paymaster = AvnuPaymaster.new({
    network = "sepolia",
    apiKey = "YOUR_AVNU_API_KEY",
})

-- Optional: policy to restrict sponsorship
local policy = PaymasterPolicy.new({
    allowedContracts = { { address = "0xGAME_CONTRACT" } },
    maxTxPerPlayer = 100,
    timeWindow = 3600,  -- per hour
})

-- Optional: budget to track per-player token allowance
local budget = PaymasterBudget.new({
    defaultTokenBalance = 100,
    costPerTransaction = 1,
})

-- Create the executor
local executor = SponsoredExecutor.new({
    account = serverAccount,
    paymaster = paymaster,
    feeMode = { mode = "sponsored" },
    policy = policy,
    budget = budget,
    callbacks = {
        onTransactionSubmitted = function(info)
            print("Tx submitted for player", info.playerId, ":", info.transactionHash)
        end,
        onTransactionFailed = function(info)
            warn("Tx failed for player", info.playerId, ":", tostring(info.error))
        end,
    },
})

-- Execute a sponsored transaction for a player
executor:execute(player.UserId, {
    { contractAddress = "0xGAME", entrypoint = "claim_reward", calldata = { "0x100" } },
}):andThen(function(result)
    print("Sponsored tx:", result.transactionHash)
    print("Tokens cost:", result.tokensCost)
end)
```

### Direct Account Paymaster Methods

For simpler cases without policy/budget:

```luau
-- Estimate paymaster fees
account:estimatePaymasterFee(calls, {
    paymaster = paymaster,
    feeMode = { mode = "sponsored" },
}):andThen(function(result)
    print("Fee estimate:", result.feeEstimate)
end)

-- Execute with paymaster
account:executePaymaster(calls, {
    paymaster = paymaster,
    feeMode = { mode = "sponsored" },
}):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

## Account Deployment & Onboarding

### Using KeyStore + OnboardingManager

The recommended pattern for Roblox games -- generates, encrypts, and deploys player wallets automatically:

```luau
local KeyStore = Starknet.wallet.KeyStore
local OnboardingManager = Starknet.wallet.OnboardingManager

-- Set up encrypted key storage
local keyStore = KeyStore.new({
    serverSecret = "your-32-char-server-secret-here!",
})

-- Set up onboarding with optional paymaster for gasless deployment
local manager = OnboardingManager.new({
    keyStore = keyStore,
    provider = provider,
    paymasterDetails = {
        paymaster = paymaster,
        feeMode = { mode = "sponsored" },
    },
})

-- Player join handler
Players.PlayerAdded:Connect(function(player)
    local result = manager:onboard(player.UserId)
    print("Player wallet:", result.address)
    if result.isNew then
        print("New wallet created and deployed")
    end
end)

-- Player leave handler
Players.PlayerRemoving:Connect(function(player)
    -- Optional: clean up in-memory state
end)
```

### Manual Deployment with Pre-funding

For more control over the deployment process:

```luau
local Account = Starknet.wallet.Account

-- 1. Get funding info
local info = Account.getDeploymentFundingInfo({
    publicKey = publicKeyHex,
    provider = provider,
}):expect()

-- 2. Fund the address (your backend sends STRK)
-- ...

-- 3. Check balance
local check = Account.checkDeploymentBalance({
    address = info.address,
    classHash = info.classHash,
    constructorCalldata = info.constructorCalldata,
    salt = info.salt,
    provider = provider,
}):expect()

-- 4. Deploy
if check.hasSufficientBalance then
    account:deployAccount():andThen(function(result)
        print("Deployed:", result.transactionHash)
    end)
end
```

## Structured Error Handling

Use the structured error system for clear error recovery:

```luau
local StarknetError = Starknet.errors.StarknetError
local ErrorCodes = Starknet.errors.ErrorCodes

account:execute(calls)
    :catch(function(err)
        if not StarknetError.isStarknetError(err) then
            warn("Unknown error:", tostring(err))
            return
        end

        if err:is("RpcError") then
            -- Network/RPC issue
            if ErrorCodes.isTransient(err.code) then
                -- Safe to retry: NETWORK_ERROR, RATE_LIMIT, PAYMASTER_UNAVAILABLE
                warn("Transient error, will retry:", err.message)
            else
                warn("Permanent RPC error:", err.message, "code:", err.code)
            end
        elseif err:is("TransactionError") then
            warn("Transaction failed:", err.revertReason)
        elseif err:is("ValidationError") then
            warn("Bad input:", err.message, "hint:", err.hint)
        elseif err:is("AbiError") then
            warn("ABI encoding issue:", err.message)
        elseif err:is("SigningError") then
            warn("Signing failed:", err.message)
        end
    end)
```

## NonceManager for Parallel Transactions

When sending many transactions in parallel, enable the NonceManager to avoid nonce conflicts:

```luau
local provider = RpcProvider.new({
    nodeUrl = "https://api.zan.top/public/starknet-sepolia",
    enableNonceManager = true,
})

-- Parallel transactions automatically get sequential nonces
local results = {}
for i = 1, 10 do
    results[i] = account:execute({
        { contractAddress = "0xGAME", entrypoint = "action", calldata = { string.format("0x%x", i) } },
    })
end

-- All 10 transactions are submitted with nonces 0-9 without waiting for each other
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
local StarkCurve = Starknet.crypto.StarkCurve
local BigInt = Starknet.crypto.BigInt

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

    local messageHash = BigInt.fromHex(challenge)
    -- Public key must be the full AffinePoint (both x and y coordinates)
    local publicKey = StarkCurve.getPublicKey(BigInt.fromHex(publicKeyHex))
    -- If you only have the x-coordinate, you need point decompression
    -- (compute y from the curve equation y^2 = x^3 + x + beta)

    local sig = {
        r = BigInt.fromHex(signatureR),
        s = BigInt.fromHex(signatureS),
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
5. **Handle failures gracefully** -- Use `StarknetError.isStarknetError()` and `err:is()` for structured error handling.
6. **Fee estimation** -- Use `estimateFee` before large transactions to avoid overpaying.
7. **Use the right account type** -- Use `accountType` parameter (not just `classHash`) for correct constructor calldata.
8. **Use NonceManager** -- Enable it on the provider for parallel transaction scenarios.
9. **Use paymaster for players** -- SponsoredExecutor + PaymasterPolicy + PaymasterBudget for gasless player transactions.
10. **Normalize addresses** -- Use `BigInt.toHex(BigInt.fromHex(addr))` for consistent address comparison.

## Next Steps

- [Roblox Considerations](roblox.md) -- Rate limits, security, performance
- [Contract Interaction](contracts.md) -- Deep dive into contract APIs
- [Getting Started](getting-started.md) -- Basic setup if you haven't started yet
