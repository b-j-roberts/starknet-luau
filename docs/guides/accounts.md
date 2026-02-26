# Account Management Guide

This guide covers key generation, address derivation, account types, nonce handling, and message signing in starknet-luau.

## Starknet Account Model

Unlike Ethereum (where addresses are derived from public keys), Starknet uses **account abstraction**. Every account is a smart contract deployed at a specific address. The address is determined by:

- **Class hash** -- Which account contract implementation (OpenZeppelin, Argent, Braavos)
- **Constructor calldata** -- The public key (and potentially other parameters)
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

To use a different account implementation:

```luau
local Constants = Starknet.constants

-- Argent account
local argentAccount = Account.fromPrivateKey({
    privateKey = "0x...",
    provider = provider,
    classHash = Constants.ARGENT_ACCOUNT_CLASS_HASH,
})

-- Braavos account
local braavosAccount = Account.fromPrivateKey({
    privateKey = "0x...",
    provider = provider,
    classHash = Constants.BRAAVOS_ACCOUNT_CLASS_HASH,
})
```

### Available Class Hashes

| Account Type | Constant |
|-------------|----------|
| OpenZeppelin (default) | `Constants.OZ_ACCOUNT_CLASS_HASH` |
| Argent X | `Constants.ARGENT_ACCOUNT_CLASS_HASH` |
| Braavos | `Constants.BRAAVOS_ACCOUNT_CLASS_HASH` |

## Creating an Account with a Known Address

If you already know the account address (e.g., from a wallet):

```luau
local StarkSigner = Starknet.signer.StarkSigner

local account = Account.new({
    address = "0xYOUR_ACCOUNT_ADDRESS",
    signer = StarkSigner.new("0xYOUR_PRIVATE_KEY"),
    provider = provider,
})
```

## Address Derivation

You can compute an account address without a provider (offline, synchronous):

```luau
local address = Account.computeAddress({
    publicKey = "0xYOUR_PUBLIC_KEY_HEX",
    classHash = Constants.OZ_ACCOUNT_CLASS_HASH,  -- optional, defaults to OZ
})

print("Computed address:", address)
```

### How Address Derivation Works

The address is computed as:

```
address = pedersen(
    pedersen(
        pedersen(
            pedersen(0, CONTRACT_ADDRESS_PREFIX),
            deployerAddress   -- 0x0 for self-deployment
        ),
        salt                  -- usually the public key
    ),
    classHash
) masked to 251 bits
```

Where `CONTRACT_ADDRESS_PREFIX = 0x535441524b4e45545f434f4e54524143545f41444452455353` (ASCII "STARKNET_CONTRACT_ADDRESS").

### Custom Constructor Calldata

For non-standard accounts:

```luau
local address = Account.computeAddress({
    publicKey = "0xPUBKEY",
    classHash = "0xCUSTOM_CLASS_HASH",
    constructorCalldata = { "0xPUBKEY", "0xGUARDIAN" },
    salt = "0xCUSTOM_SALT",
})
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

> **Important:** Never hardcode private keys in Roblox scripts. See the [Roblox Considerations](roblox.md) guide for secure key management strategies.

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

-- Sign the message
local signature = account:signMessage(typedData)
print("r:", signature.r_hex)
print("s:", signature.s_hex)
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
account.provider             -- The RpcProvider instance
account:getPublicKeyHex()    -- Public key as hex string
account:getNonce()           -- Promise<string> (hex nonce from chain)
```

## Next Steps

- [Contract Interaction](contracts.md) -- Using accounts with contracts
- [Roblox Considerations](roblox.md) -- Secure key management in Roblox
- [Common Patterns](patterns.md) -- Game integration patterns
- [API Reference](api-reference.md) -- Complete Account and StarkSigner API
