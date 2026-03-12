# Account Management Guide

This guide covers key generation, address derivation, account types, nonce handling, message signing, account deployment, and advanced features like KeyStore, OnboardingManager, and Outside Execution.

## Starknet Account Model

Unlike Ethereum (where addresses are derived from public keys), Starknet uses **account abstraction**. Every account is a smart contract deployed at a specific address. The address is determined by:

- **Class hash** -- Which account contract implementation (OpenZeppelin, Argent, Braavos)
- **Constructor calldata** -- The public key (and potentially other parameters like a guardian)
- **Salt** -- Usually the public key
- **Deployer address** -- Usually `0x0` for self-deployment

## Creating an Account from a Private Key

The simplest way to create an account:

```luau
local Account = Starknet.wallet.Account

local account = Account.fromPrivateKey({
    privateKey = "0xYOUR_PRIVATE_KEY_HEX",
    provider = provider,
})

print("Address:", account.address)
print("Public key:", account:getPublicKeyHex())
```

This derives the address using the **OpenZeppelin** class hash by default.

### Specifying an Account Type

Use the `accountType` parameter to get correct constructor calldata and class hash for each account type:

```luau
-- Argent account (constructor calldata: [0, publicKey, guardian])
local argentAccount = Account.fromPrivateKey({
    privateKey = "0x...",
    provider = provider,
    accountType = "argent",
    guardian = "0x0",  -- optional guardian key
})

-- Braavos account (uses base class hash for address computation)
local braavosAccount = Account.fromPrivateKey({
    privateKey = "0x...",
    provider = provider,
    accountType = "braavos",
})

-- Custom class hash (overrides accountType)
local customAccount = Account.fromPrivateKey({
    privateKey = "0x...",
    provider = provider,
    classHash = "0xCUSTOM_CLASS_HASH",
})
```

### Account Type Constants

```luau
Account.ACCOUNT_TYPE_OZ      -- "oz"
Account.ACCOUNT_TYPE_ARGENT  -- "argent"
Account.ACCOUNT_TYPE_BRAAVOS -- "braavos"

Account.OZ_CLASS_HASH              -- OpenZeppelin class hash
Account.ARGENT_CLASS_HASH          -- Argent X class hash
Account.BRAAVOS_CLASS_HASH         -- Braavos implementation class hash
Account.BRAAVOS_BASE_CLASS_HASH    -- Braavos base class hash (used for address computation)
```

### Available Class Hashes

| Account Type | Constant | Constructor Calldata |
|-------------|----------|---------------------|
| OpenZeppelin (default) | `Constants.OZ_ACCOUNT_CLASS_HASH` | `[publicKey]` |
| Argent X | `Constants.ARGENT_ACCOUNT_CLASS_HASH` | `[0, publicKey, guardian]` |
| Braavos | `Constants.BRAAVOS_BASE_ACCOUNT_CLASS_HASH` | `[publicKey]` |

## Creating an Account with a Known Address

If you already know the account address (e.g., from a wallet):

```luau
local StarkSigner = Starknet.signer.StarkSigner

local account = Account.new({
    address = "0xYOUR_ACCOUNT_ADDRESS",
    signer = StarkSigner.new("0xYOUR_PRIVATE_KEY"),
    provider = provider,
    -- Optional:
    accountType = "oz",           -- for deploy convenience
    classHash = "0x...",          -- custom class hash
    constructorCalldata = { },    -- custom constructor calldata
})
```

## Address Derivation

Compute an account address without a provider (offline, synchronous):

```luau
local address = Account.computeAddress({
    classHash = Constants.OZ_ACCOUNT_CLASS_HASH,  -- required
    publicKey = "0xYOUR_PUBLIC_KEY_HEX",
})

print("Computed address:", address)
```

### How Address Derivation Works

The address is computed using `computeHashOnElements` (chained Pedersen hashes with a final length hash):

```
calldataHash = computeHashOnElements(constructorCalldata)
               -- i.e., pedersen(pedersen(pedersen(0, c1), c2), ..., cn), len)

rawHash = computeHashOnElements({
    CONTRACT_ADDRESS_PREFIX,
    deployerAddress,      -- 0x0 for self-deployment
    salt,                 -- usually the public key
    classHash,
    calldataHash,
})

address = rawHash masked to 251 bits
```

Where `CONTRACT_ADDRESS_PREFIX = 0x535441524b4e45545f434f4e54524143545f41444452455353` (ASCII "STARKNET_CONTRACT_ADDRESS").

### Custom Constructor Calldata

For non-standard accounts:

```luau
local address = Account.computeAddress({
    classHash = "0xCUSTOM_CLASS_HASH",
    publicKey = "0xPUBKEY",
    constructorCalldata = { "0xPUBKEY", "0xGUARDIAN" },
    salt = "0xCUSTOM_SALT",
    deployer = "0x0",
})
```

### Detect Account Type from Class Hash

```luau
local accountType = Account.detectAccountType("0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f")
-- Returns "oz", "argent", "braavos", or nil for unknown

local calldata = Account.getConstructorCalldata("argent", "0xPUBKEY", "0xGUARDIAN")
-- Returns { "0x0", "0xPUBKEY", "0xGUARDIAN" }
```

## AccountType Module

The `AccountType` module provides callable account type objects for configurable account creation:

```luau
local AccountType = Starknet.wallet.AccountType

-- Pre-defined types
local ozType = AccountType.OZ           -- { type = "oz", classHash = ... }
local argentType = AccountType.Argent   -- { type = "argent", classHash = ... }
local braavosType = AccountType.Braavos -- { type = "braavos", classHash = ... }

-- Callable: generate constructor calldata
local calldata = AccountType.OZ("0xPUBKEY")                    -- { "0xPUBKEY" }
local calldata = AccountType.Argent("0xPUBKEY", "0xGUARDIAN")  -- { "0x0", "0xPUBKEY", "0xGUARDIAN" }

-- Look up by name
local acctType = AccountType.get("argent")  -- returns AccountType.Argent or nil

-- Custom account type
local myType = AccountType.custom({
    type = "my_custom",
    classHash = "0xCUSTOM_CLASS_HASH",
    buildCalldata = function(pubKey)
        return { pubKey, "0xSOME_PARAM" }
    end,
})
```

## AccountFactory Module

`AccountFactory` simplifies batch creation and deployment of accounts:

```luau
local AccountFactory = Starknet.wallet.AccountFactory
local AccountType = Starknet.wallet.AccountType

local factory = AccountFactory.new(provider, AccountType.OZ, signer)

-- Create a single account
local result = factory:createAccount()
print("Address:", result.address)
print("Account:", result.account)
-- result.deployTx() to deploy later

-- Batch create multiple accounts
local accounts = factory:batchCreate(10, {
    -- Optional: provide specific private keys
    privateKeys = { "0xKEY1", "0xKEY2", ... },
    -- Or: generate keys with a custom function
    keyGenerator = function() return generateRandomKey() end,
})

-- Batch deploy all accounts
factory:batchDeploy(accounts, {
    maxConcurrency = 3,                           -- deploy 3 at a time
    waitForConfirmation = true,                   -- wait for each to confirm
    onDeployProgress = function(index, total, result)
        print(string.format("Deployed %d/%d", index, total))
    end,
}):andThen(function(summary)
    print("Deployed:", summary.deployed)
    print("Failed:", summary.failed)
    print("Skipped:", summary.skipped)
end)
```

## Key Generation

### From a Private Key

```luau
local StarkSigner = Starknet.signer.StarkSigner

local signer = StarkSigner.new("0xPRIVATE_KEY_HEX")

-- Get the public key
local pubKeyHex = signer:getPublicKeyHex()   -- hex string
local pubKeyPoint = signer:getPubKey()         -- { x: Felt, y: Felt }
```

### Using the Crypto Module Directly

```luau
local BigInt = Starknet.crypto.BigInt
local StarkCurve = Starknet.crypto.StarkCurve
local StarkField = Starknet.crypto.StarkField

-- Private key as BigInt
local privateKey = BigInt.fromHex("0xABC123")

-- Derive public key (point on the curve)
local publicKey = StarkCurve.getPublicKey(privateKey)
print("Public key X:", StarkField.toHex(publicKey.x))
```

### Key Security

Private keys must satisfy: `0 < privateKey < N` (curve order). The SDK validates this at construction time.

> **Important:** Never hardcode private keys in Roblox scripts. See the [Roblox Considerations](roblox.md) guide for secure key management strategies, or use the [KeyStore](#encrypted-key-store-keystore) for encrypted persistence.

## Nonce Management

Every Starknet transaction includes a nonce (sequential counter) to prevent replay attacks.

### Automatic Nonce Management

By default, `account:execute()` fetches the nonce from the network before each transaction:

```luau
-- Nonce is fetched automatically
account:execute(calls):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

### Manual Nonce Override

You can provide a specific nonce:

```luau
account:execute(calls, {
    nonce = "0x5",  -- force nonce to 5
}):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

### NonceManager (Optimized Parallel Transactions)

For high-throughput scenarios, enable the NonceManager on the provider to avoid re-fetching nonces:

```luau
local provider = RpcProvider.new({
    nodeUrl = "https://api.zan.top/public/starknet-sepolia",
    enableNonceManager = true,
})
```

The NonceManager:
- Caches the latest nonce locally
- Reserves sequential nonces for parallel transactions
- Confirms/rejects nonces as transactions succeed/fail
- Auto-resyncs from the chain on errors

```luau
-- With NonceManager, parallel transactions get sequential nonces automatically
local tx1 = account:execute(calls1)
local tx2 = account:execute(calls2)
local tx3 = account:execute(calls3)
-- tx1 gets nonce 0, tx2 gets nonce 1, tx3 gets nonce 2 (no RPC calls needed)
```

See [API Reference](api-reference.md#noncemanager) for the full NonceManager API.

## Executing Transactions

### Single Call

```luau
account:execute({
    {
        contractAddress = "0xCONTRACT",
        entrypoint = "transfer",
        calldata = { "0xRECIPIENT", "0x1000", "0x0" },
    },
}):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

### Multicall (Batch)

```luau
account:execute({
    { contractAddress = "0xA", entrypoint = "approve", calldata = { "0xB", "0x1000", "0x0" } },
    { contractAddress = "0xB", entrypoint = "deposit", calldata = { "0x1000", "0x0" } },
}):andThen(function(result)
    print("Batch tx:", result.transactionHash)
end)
```

### Fee Estimation

```luau
account:estimateFee(calls):andThen(function(estimate)
    print("Gas:", estimate.gas_consumed)
    print("Fee:", estimate.overall_fee, estimate.unit)
end)
```

### Custom Fee Bounds

```luau
account:execute(calls, {
    feeMultiplier = 2.0,  -- 2x the estimated fee (default: 1.5x)
}):andThen(function(result)
    print("Tx:", result.transactionHash)
end)
```

### Dry Run (Build + Sign Without Submitting)

```luau
account:execute(calls, {
    dryRun = true,
}):andThen(function(result)
    print("Would have submitted tx:", result.transactionHash)
    print("Signed transaction:", result)
    -- Transaction was built and signed but NOT submitted to the network
end)
```

## Waiting for Receipts

After submitting a transaction, wait for it to be included in a block:

```luau
account:execute(calls)
    :andThen(function(result)
        return account:waitForReceipt(result.transactionHash, {
            retryInterval = 5,  -- poll every 5 seconds (default)
            maxAttempts = 30,   -- max 30 polls (default)
        })
    end)
    :andThen(function(receipt)
        if receipt.execution_status == "SUCCEEDED" then
            print("Success! Block:", receipt.block_number)
        else
            warn("Reverted:", receipt.revert_reason)
        end
    end)
```

## Signing Typed Data (SNIP-12)

Sign structured data following the SNIP-12 standard (similar to EIP-712):

```luau
local typedData = {
    types = {
        StarknetDomain = {
            { name = "name", type = "shortstring" },
            { name = "version", type = "shortstring" },
            { name = "chainId", type = "shortstring" },
            { name = "revision", type = "shortstring" },
        },
        Transfer = {
            { name = "recipient", type = "ContractAddress" },
            { name = "amount", type = "u256" },
        },
    },
    primaryType = "Transfer",
    domain = {
        name = "MyGame",
        version = "1",
        chainId = "SN_SEPOLIA",
        revision = "1",
    },
    message = {
        recipient = "0x123...",
        amount = { low = "0x1000", high = "0x0" },
    },
}

-- Hash the message (synchronous)
local messageHash = account:hashMessage(typedData)

-- Sign the message (returns array: { r_hex, s_hex })
local signature = account:signMessage(typedData)
print("r:", signature[1])
print("s:", signature[2])
```

### Revision Support

SNIP-12 has two revisions:

| Revision | Domain Type | Hash Function |
|----------|------------|---------------|
| `"0"` (Legacy) | `StarkNetDomain` | Pedersen |
| `"1"` (Active) | `StarknetDomain` | Poseidon |

The revision is detected from the `domain.revision` field. Use revision `"1"` for new applications.

## Account Properties

```luau
account.address              -- The onchain address (hex string)
account.signer               -- The StarkSigner instance
account:getPublicKeyHex()    -- Public key as hex string
account:getNonce()           -- Promise<string> (hex nonce from chain)
account:getProvider()        -- The RpcProvider instance
```

## Account Deployment & Prefunding

Before deploying a new account, the counterfactual address must be pre-funded with STRK tokens (V3 transactions use STRK for gas). The SDK provides three static utility methods to streamline this process.

### Step 1: Get Funding Info

Use `getDeploymentFundingInfo` to compute the counterfactual address and estimate the deployment cost. Pass this info to your game backend so it can send funds.

```luau
local info = Account.getDeploymentFundingInfo({
    publicKey = "0xYOUR_PUBLIC_KEY",
    provider = provider,
    -- Optional: accountType = "argent", classHash = "0x...", salt = "0x..."
}):expect()

print("Send STRK to:", info.address)
print("Estimated fee:", info.estimatedFee)
print("Token:", info.token)               -- "STRK"
print("Token address:", info.tokenAddress) -- STRK contract address
print("Class hash:", info.classHash)
print("Salt:", info.salt)
```

### Step 2: Check Balance

After your backend sends funds, verify the address has enough balance:

```luau
local check = Account.checkDeploymentBalance({
    address = info.address,
    classHash = info.classHash,
    constructorCalldata = info.constructorCalldata,
    salt = info.salt,
    provider = provider,
    -- Optional: token = "ETH", feeMultiplier = 2.0
}):expect()

if check.hasSufficientBalance then
    print("Ready to deploy! Balance:", check.balance)
else
    print("Need more funds. Deficit:", check.deficit)
end
```

### Step 3: Estimate Fee (Advanced)

For fee estimation without a balance check:

```luau
local estimate = Account.getDeploymentFeeEstimate({
    classHash = Constants.OZ_ACCOUNT_CLASS_HASH,
    constructorCalldata = { publicKey },
    salt = publicKey,
    contractAddress = computedAddress,
    provider = provider,
    feeMultiplier = 1.5,  -- default, 1.5x buffer on top of estimated fee
}):expect()

print("Estimated fee:", estimate.estimatedFee)
print("Gas consumed:", estimate.gasConsumed)
print("Gas price:", estimate.gasPrice)
```

### Step 4: Deploy

```luau
local account = Account.fromPrivateKey({
    privateKey = privateKey,
    provider = provider,
})

account:deployAccount():andThen(function(result)
    if result.alreadyDeployed then
        print("Account already deployed at:", result.contractAddress)
    else
        print("Deployed! Tx:", result.transactionHash)
    end
end)
```

`deployAccount()` is idempotent -- it calls `getNonce()` first; if it succeeds, the account is already deployed and returns `{ alreadyDeployed = true }`. Options include `maxFee`, `feeMultiplier`, `dryRun`, and `waitForConfirmation` (default `true`).

### Paymaster-Sponsored Deployment

Deploy without pre-funding using a paymaster:

```luau
account:deployWithPaymaster({
    paymaster = paymasterClient,
    feeMode = { mode = "sponsored" },
}):andThen(function(result)
    print("Deployed with paymaster! Tx:", result.transactionHash)
end)
```

See [API Reference](api-reference.md#account) for all deployment-related methods.

### Paymaster-Sponsored Transactions

Execute transactions without the player paying gas:

```luau
account:executePaymaster(calls, {
    paymaster = paymasterClient,
    feeMode = { mode = "sponsored" },
}):andThen(function(result)
    print("Sponsored tx:", result.transactionHash)
    print("Tracking ID:", result.trackingId)
end)

-- Estimate paymaster fees before executing
account:estimatePaymasterFee(calls, {
    paymaster = paymasterClient,
    feeMode = { mode = "sponsored" },
}):andThen(function(result)
    print("Fee estimate:", result.feeEstimate)
end)
```

## Outside Execution (SNIP-9)

Outside Execution allows a third party to execute transactions on behalf of a user, with the user's pre-signed authorization. This is useful for session keys, meta-transactions, and delegated execution.

```luau
local OutsideExecution = Starknet.wallet.OutsideExecution

-- Build the typed data for signing
local typedData = OutsideExecution.getTypedData({
    chainId = "SN_SEPOLIA",
    caller = OutsideExecution.ANY_CALLER,  -- or a specific address
    execute_after = 0,
    execute_before = 9999999999,
    nonce = 1,
    calls = {
        { contractAddress = "0xTOKEN", entrypoint = "transfer", calldata = { "0xTO", "0x100", "0x0" } },
    },
    version = OutsideExecution.VERSION_V2,
})

-- User signs the typed data
local signature = account:signMessage(typedData)

-- Anyone can now submit this execution
local outsideCall = OutsideExecution.buildExecuteFromOutsideCall(
    account.address,
    typedData.message,   -- the outside execution data
    signature,
    OutsideExecution.VERSION_V2
)

-- Submit via any account (even a different one)
relayerAccount:execute({ outsideCall })
```

### Version Support

| Version | Entrypoint | Interface ID |
|---------|-----------|-------------|
| V1 | `execute_from_outside` | `0x68cfd18b...` |
| V2 | `execute_from_outside_v2` | `0x1d1144bb...` |
| V3-RC | `execute_from_outside_v3` | -- |

## Encrypted Key Store (KeyStore)

`KeyStore` provides encrypted persistence of private keys using Roblox DataStore, suitable for server-side player wallet management:

```luau
local KeyStore = Starknet.wallet.KeyStore

local keyStore = KeyStore.new({
    serverSecret = "your-32-char-server-secret-here!",  -- encryption key
    dataStoreName = "PlayerKeys",                        -- DataStore name (default)
    accountType = "oz",                                  -- default account type
})

-- Generate and store a new key for a player
local result = keyStore:generateAndStore(player.UserId, provider)
print("New account address:", result.address)

-- Load an existing account
local account = keyStore:loadAccount(player.UserId, provider)

-- Get or create (idempotent)
local result = keyStore:getOrCreate(player.UserId, provider)
if result.isNew then
    print("Created new account:", result.account.address)
else
    print("Loaded existing account:", result.account.address)
end

-- Check existence
if keyStore:hasAccount(player.UserId) then
    print("Player has a wallet")
end

-- Delete a key
keyStore:deleteKey(player.UserId)

-- Rotate encryption secret (re-encrypts all specified player keys)
local result = keyStore:rotateSecret("old-secret", "new-secret", { 12345, 67890 })
print("Rotated:", result.rotated, "Failed:", #result.failed)

-- Track deployment status
keyStore:markDeployed(player.UserId)
local deployed = keyStore:isDeployed(player.UserId)
```

## Onboarding Manager

`OnboardingManager` orchestrates the full player onboarding flow: key generation, account creation, and deployment in one call:

```luau
local OnboardingManager = Starknet.wallet.OnboardingManager

local manager = OnboardingManager.new({
    keyStore = keyStore,
    provider = provider,
    -- Optional: use a paymaster for gasless deployment
    paymasterDetails = {
        paymaster = paymasterClient,
        feeMode = { mode = "sponsored" },
    },
    waitForConfirmation = true,
})

-- Full onboarding: generate key + create account + deploy (if paymaster configured)
local result = manager:onboard(player.UserId)
print("Address:", result.address)
print("Is new?", result.isNew)
print("Was deployed?", result.wasDeployed)
print("Already deployed?", result.alreadyDeployed)

-- Check status without modifying anything
local status = manager:getStatus(player.UserId)
print("Has account?", status.hasAccount)
print("Is deployed?", status.isDeployed)
print("Address:", status.address)

-- Ensure an existing account is deployed
local result = manager:ensureDeployed(player.UserId)

-- Remove a player's wallet data
manager:removePlayer(player.UserId)
```

## Next Steps

- [Contract Interaction](contracts.md) -- Using accounts with contracts
- [Roblox Considerations](roblox.md) -- Secure key management in Roblox
- [Common Patterns](patterns.md) -- Game integration patterns
- [API Reference](api-reference.md) -- Complete Account, AccountType, AccountFactory, KeyStore, OnboardingManager API
