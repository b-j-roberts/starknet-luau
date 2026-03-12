# Cryptography & Low-Level Primitives

Reference for developers who need direct access to hash functions, field arithmetic, curve operations, or custom signing flows.

## Prerequisites

- Completed [Guide 3: Accounts & Transactions](accounts-and-transactions.md)
- Familiarity with elliptic curve cryptography concepts (finite fields, scalar multiplication, ECDSA)

## When You Need This Guide

Most game developers never touch these modules directly -- `Account`, `Contract`, and `TransactionBuilder` handle cryptography internally. Reach for the primitives when you need to:

- Build a custom signing protocol or multisig scheme
- Verify signatures from an external system
- Compute Pedersen/Poseidon hashes for Merkle proofs or commitments
- Derive function selectors for raw `provider:call()` invocations
- Debug transaction hash mismatches against starknet.js or another SDK

## BigInt: Arbitrary Precision Arithmetic

All cryptographic values in the SDK -- private keys, field elements, hash outputs, curve coordinates -- are `BigInt` buffers. BigInt provides buffer-based arbitrary precision arithmetic using 11 limbs of 24-bit f64 values (264 bits total).

### Creating BigInts

```luau
--!strict
-- ServerScriptService/BigIntExample.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local BigInt = StarknetLuau.crypto.BigInt

-- From hex (most common -- addresses, keys, and hashes are hex)
local a = BigInt.fromHex("0x1234abcd")

-- From a Luau number (integers up to 2^53 only)
local b = BigInt.fromNumber(42)

-- From raw big-endian bytes (for parsing external data)
local raw = buffer.create(4)
buffer.writeu32(raw, 0, 0x12345678)
local c = BigInt.fromBytes(raw)

-- From a u256 table (two 128-bit felts, as returned by ERC-20 balances)
local d = BigInt.fromU256({ low = "0x1", high = "0x0" })

-- Constants
local zero = BigInt.zero()
local one = BigInt.one()
```

### Converting Back

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt

local val = BigInt.fromHex("0xdeadbeef")

-- To "0x"-prefixed hex string (normalized, no leading zeros)
local hex: string = BigInt.toHex(val) -- "0xdeadbeef"

-- To big-endian byte buffer (minimal length)
local bytes: buffer = BigInt.toBytes(val)

-- To exactly 32 bytes (zero-padded, for ECDSA / hash inputs)
local bytes32: buffer = BigInt.toBytes32(val)

-- To Luau number (ONLY safe for values < 2^53)
local num: number = BigInt.toNumber(val)
```

### Arithmetic and Comparison

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt

local a = BigInt.fromHex("0x10")
local b = BigInt.fromHex("0x3")

-- Basic arithmetic (unbounded -- results can exceed field size)
local sum = BigInt.add(a, b) -- 0x13
local diff = BigInt.sub(a, b) -- 0xd
local prod = BigInt.mul(a, b) -- 0x30

-- Division and modulus
local quot, rem = BigInt.divmod(a, b) -- quot=0x5, rem=0x1
local quotOnly = BigInt.div(a, b)
local remOnly = BigInt.mod(a, b)

-- Comparison: returns -1, 0, or 1
local cmpResult = BigInt.cmp(a, b) -- 1 (a > b)
local isEqual = BigInt.eq(a, b) -- false
local isLess = BigInt.lt(a, b) -- false
local isZero = BigInt.isZero(a) -- false

-- Bit operations
local bits = BigInt.bitLength(a) -- 5
local bit0 = BigInt.getBit(a, 0) -- 0 (least significant)
local shifted = BigInt.shl(a, 4) -- 0x100
local right = BigInt.shr(a, 2) -- 0x4
local anded = BigInt.band(a, b) -- 0x0
local ored = BigInt.bor(a, b) -- 0x13
```

### Modular Arithmetic

For cryptographic operations you almost always want modular arithmetic -- results reduced by a prime modulus:

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt

local a = BigInt.fromHex("0x7")
local b = BigInt.fromHex("0x5")
local m = BigInt.fromHex("0xb") -- modulus 11

-- Modular add/sub/mul
local addMod = BigInt.addmod(a, b, m) -- (7+5) mod 11 = 1
local subMod = BigInt.submod(a, b, m) -- (7-5) mod 11 = 2
local mulMod = BigInt.mulmod(a, b, m) -- (7*5) mod 11 = 2

-- Modular exponentiation (square-and-multiply)
local powMod = BigInt.powmod(a, b, m) -- 7^5 mod 11 = 10

-- Modular inverse (extended GCD)
local invMod = BigInt.invmod(a, m) -- 7^(-1) mod 11 = 8 (since 7*8=56≡1 mod 11)

-- Barrett reduction (fast path for repeated operations with the same modulus)
local ctx = BigInt.createBarrettCtx(m)
local fastMul = BigInt.mulmodB(a, b, ctx) -- same result, faster for hot loops
local fastPow = BigInt.powmodB(a, b, ctx) -- same as powmod but uses Barrett
```

Barrett reduction precomputes a reciprocal approximation so that subsequent multiplications avoid expensive division. The SDK uses this internally for all field operations.

## StarkField vs StarkScalarField

Starknet uses two distinct finite fields. Knowing which to use is critical:

| Field | Modulus | Use Case |
|-------|---------|----------|
| **StarkField** (mod P) | `2^251 + 17*2^192 + 1` | Hash outputs, addresses, curve coordinates, storage values |
| **StarkScalarField** (mod N) | Curve order N | Private keys, ECDSA nonces (k), signature components (r, s) |

Both fields share the same API surface, generated by `FieldFactory`:

```luau
--!strict
local StarkField = StarknetLuau.crypto.StarkField
local StarkScalarField = StarknetLuau.crypto.StarkScalarField

-- Create field elements (automatically reduced mod P or mod N)
local felt = StarkField.fromHex("0xdeadbeef")
local scalar = StarkScalarField.fromHex("0xdeadbeef")

-- Arithmetic is mod-reduced automatically
local sum = StarkField.add(felt, StarkField.one()) -- (felt + 1) mod P
local product = StarkScalarField.mul(scalar, StarkScalarField.fromNumber(2)) -- (scalar * 2) mod N

-- Inversion via Fermat's little theorem: a^(P-2) mod P
local inverse = StarkField.inv(felt)

-- Convert back to hex
local hex = StarkField.toHex(sum)

-- Convert to BigInt (un-reduced copy for cross-field operations)
local raw = StarkField.toBigInt(felt)

-- StarkField has sqrt (Tonelli-Shanks) -- StarkScalarField does not
local root = StarkField.sqrt(felt) -- returns nil if not a quadratic residue
```

**Rule of thumb**: if you're working with data that lives on-chain (addresses, storage, hash digests), use `StarkField`. If you're working with signing math (private keys, nonce k, signature r/s), use `StarkScalarField`.

## StarkCurve: Elliptic Curve Operations

The Stark curve is a short Weierstrass curve `y^2 = x^3 + x + beta` over StarkField (alpha=1). The SDK uses Jacobian coordinates internally for speed, converting to affine only at output boundaries.

### Deriving a Public Key

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt
local StarkCurve = StarknetLuau.crypto.StarkCurve

-- Private key must be in [1, N-1]
local privateKey = BigInt.fromHex("0x1234567890abcdef1234567890abcdef")

-- publicKey = privateKey * G (generator point)
local publicKey = StarkCurve.getPublicKey(privateKey)
print("x:", BigInt.toHex(publicKey.x))
print("y:", BigInt.toHex(publicKey.y))

-- Verify the point is on the curve
assert(StarkCurve.isOnCurve(publicKey))
```

### Point Arithmetic

```luau
--!strict
local StarkCurve = StarknetLuau.crypto.StarkCurve
local StarkField = StarknetLuau.crypto.StarkField
local BigInt = StarknetLuau.crypto.BigInt

-- Generator point
local G = StarkCurve.G
print("Gx:", BigInt.toHex(G.x))

-- Scalar multiplication: k * P
local k = BigInt.fromNumber(7)
local result = StarkCurve.scalarMul(G, k) -- 7G

-- Shamir's trick: k1*P1 + k2*P2 in a single pass (used in ECDSA verify)
local k1 = BigInt.fromNumber(3)
local k2 = BigInt.fromNumber(5)
local P2 = StarkCurve.scalarMul(G, BigInt.fromNumber(11))
local combined = StarkCurve.shamirMul(G, k1, P2, k2) -- 3G + 5*(11G)

-- Point negation and comparison
local negG = StarkCurve.affineNeg(G) -- -G (same x, negated y)
assert(not StarkCurve.affineEq(G, negG))

-- Check for point at infinity
local infinity = StarkCurve.INFINITY
assert(StarkCurve.isInfinityAffine(infinity))
```

### Low-Level Jacobian Operations

For performance-critical code, you can work in Jacobian coordinates directly to avoid repeated field inversions:

```luau
--!strict
local StarkCurve = StarknetLuau.crypto.StarkCurve

local G = StarkCurve.G
local jG = StarkCurve.jacobianFromAffine(G)

-- Jacobian doubling and addition (no field inversions)
local j2G = StarkCurve.jacobianDouble(jG)
local j3G = StarkCurve.jacobianAdd(j2G, jG)

-- Convert back to affine only when you need the final result
local affine3G = StarkCurve.affineFromJacobian(j3G)
```

## Hash Functions

Starknet uses four hash functions, each for specific purposes:

| Hash | Where Used | Input | Output |
|------|-----------|-------|--------|
| **Poseidon** | V3 transaction hashes, SNIP-12 (active revision) | Field elements | Field element |
| **Pedersen** | Contract addresses, SNIP-12 (legacy revision) | Field elements | Field element |
| **Keccak** | Function selectors, EVM compatibility | Byte buffer | 256-bit buffer / 250-bit felt |
| **SHA-256** | RFC 6979 nonce generation (internal to ECDSA) | Byte buffer | 256-bit buffer |

### Poseidon

The primary hash for V3 transactions. Uses a width-3 Hades permutation with S-box x^3:

```luau
--!strict
local StarkField = StarknetLuau.crypto.StarkField
local Poseidon = StarknetLuau.crypto.Poseidon

-- Hash two field elements
local a = StarkField.fromHex("0x1")
local b = StarkField.fromHex("0x2")
local h = Poseidon.hash(a, b)
print("Poseidon(1, 2):", StarkField.toHex(h))

-- Hash a single element
local h1 = Poseidon.hashSingle(StarkField.fromHex("0xabc"))

-- Hash variable-length input (sponge construction, pads with [1, 0...] to rate boundary)
local elements = {
	StarkField.fromHex("0x1"),
	StarkField.fromHex("0x2"),
	StarkField.fromHex("0x3"),
	StarkField.fromHex("0x4"),
	StarkField.fromHex("0x5"),
}
local hMany = Poseidon.hashMany(elements)
print("Poseidon(1..5):", StarkField.toHex(hMany))
```

### Pedersen

The legacy hash, based on elliptic curve point operations. Slower than Poseidon but still used for address computation:

```luau
--!strict
local StarkField = StarknetLuau.crypto.StarkField
local Pedersen = StarknetLuau.crypto.Pedersen

-- Hash two field elements
local a = StarkField.fromHex("0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb")
local b = StarkField.fromHex("0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a")
local h = Pedersen.hash(a, b)
print("Pedersen(a, b):", StarkField.toHex(h))

-- Chain hash: reduce([e1, e2, ..., en], pedersen, 0) then pedersen(result, n)
-- This is how contract addresses are computed (computeHashOnElements)
local elements = {
	StarkField.fromHex("0x1"),
	StarkField.fromHex("0x2"),
	StarkField.fromHex("0x3"),
}
local hChain = Pedersen.hashChain(elements)
print("hashChain:", StarkField.toHex(hChain))
```

**When to use which**: Poseidon for V3 transaction hashes and SNIP-12 active revision. Pedersen for contract address computation and SNIP-12 legacy revision.

### Keccak

Ethereum-variant Keccak-256 (NOT SHA-3 -- different padding). Used for function selectors:

```luau
--!strict
local StarkField = StarknetLuau.crypto.StarkField
local Keccak = StarknetLuau.crypto.Keccak

-- Raw keccak256 on a byte buffer (returns 32-byte buffer)
local input = buffer.create(5)
buffer.writestring(input, 0, "hello")
local hash = Keccak.keccak256(input) -- 32-byte buffer

-- Starknet keccak: keccak256 masked to 250 bits, returned as a StarkField felt
local snHash = Keccak.snKeccak(input) -- Felt (mod P)
print("sn_keccak:", StarkField.toHex(snHash))

-- Compute a function selector from an entry point name
local selector = Keccak.getSelectorFromName("transfer")
print("transfer selector:", StarkField.toHex(selector))

-- Special entry points return zero
local defaultSel = Keccak.getSelectorFromName("__default__")
assert(StarkField.isZero(defaultSel))
```

Function selectors are how Starknet identifies which contract method to call. When you use `contract:call("transfer", ...)`, the SDK computes `getSelectorFromName("transfer")` internally.

### SHA-256

FIPS 180-4 compliant hash, used internally by ECDSA for RFC 6979 nonce generation. You rarely need this directly:

```luau
--!strict
local SHA256 = StarknetLuau.crypto.SHA256

-- Hash a byte buffer
local data = buffer.create(11)
buffer.writestring(data, 0, "hello world")
local hash = SHA256.hash(data) -- 32-byte buffer

-- HMAC-SHA-256 (keyed hash)
local key = buffer.create(3)
buffer.writestring(key, 0, "key")
local mac = SHA256.hmac(key, data) -- 32-byte buffer
```

## ECDSA: Signing and Verification

The `ECDSA` module implements Stark ECDSA with RFC 6979 deterministic nonce generation. This is the raw signing primitive -- most developers should use `StarkSigner` or `Account:signMessage()` instead.

### Signing a Hash

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt
local ECDSA = StarknetLuau.crypto.ECDSA
local StarkCurve = StarknetLuau.crypto.StarkCurve

local privateKey = BigInt.fromHex("0x1234567890abcdef1234567890abcdef")
local messageHash = BigInt.fromHex("0xdeadbeefdeadbeefdeadbeefdeadbeef")

-- Sign: returns { r: buffer, s: buffer }
local sig = ECDSA.sign(messageHash, privateKey)
print("r:", BigInt.toHex(sig.r))
print("s:", BigInt.toHex(sig.s))

-- Verify against the public key
local publicKey = StarkCurve.getPublicKey(privateKey)
local valid = ECDSA.verify(messageHash, publicKey, sig)
assert(valid, "Signature should be valid")

-- Verify with wrong hash fails
local wrongHash = BigInt.fromHex("0x1111111111111111")
assert(not ECDSA.verify(wrongHash, publicKey, sig))
```

### Generating a Deterministic Nonce

RFC 6979 generates a deterministic nonce `k` from the message hash and private key, ensuring the same inputs always produce the same signature without needing a random number generator:

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt
local ECDSA = StarknetLuau.crypto.ECDSA

local messageHash = BigInt.fromHex("0xabcdef")
local privateKey = BigInt.fromHex("0x1234567890abcdef1234567890abcdef")

-- Exposed for testing/debugging; normally called internally by sign()
local k = ECDSA.generateK(messageHash, privateKey)
print("nonce k:", BigInt.toHex(k))
```

## StarkSigner: High-Level Signing Interface

`StarkSigner` wraps ECDSA behind a clean interface that `Account` uses internally. Use it when you need signing without a full Account:

```luau
--!strict
local BigInt = StarknetLuau.crypto.BigInt
local StarkSigner = StarknetLuau.signer.StarkSigner

-- Create from a hex private key
local signer = StarkSigner.new("0x1234567890abcdef1234567890abcdef")

-- Get the derived public key
local pubKey = signer:getPubKey() -- { x: buffer, y: buffer }
local pubKeyHex = signer:getPublicKeyHex() -- "0x..." (x-coordinate)

-- Sign a transaction hash (input MUST be a BigInt buffer, not a hex string)
local txHash = BigInt.fromHex("0xdeadbeefdeadbeefdeadbeefdeadbeef")
local signature = signer:signHash(txHash) -- { "0x<r>", "0x<s>" }
print("r:", signature[1])
print("s:", signature[2])

-- Raw signature (returns { r: buffer, s: buffer } instead of hex strings)
local rawSig = signer:signRaw(txHash)
```

## TypedData: SNIP-12 Structured Message Hashing

SNIP-12 defines how to hash structured data for off-chain signatures (similar to EIP-712 on Ethereum). The SDK supports both revisions:

| Revision | Domain Name | Hash Function |
|----------|-------------|---------------|
| 0 (LEGACY) | `"StarkNetDomain"` | Pedersen |
| 1 (ACTIVE) | `"StarknetDomain"` | Poseidon |

### Computing a Message Hash

```luau
--!strict
local TypedData = StarknetLuau.wallet.TypedData

-- SNIP-12 typed data object (active revision)
local typedData = {
	types = {
		StarknetDomain = {
			{ name = "name", type = "shortstring" },
			{ name = "version", type = "shortstring" },
			{ name = "chainId", type = "shortstring" },
			{ name = "revision", type = "shortstring" },
		},
		Transfer = {
			{ name = "to", type = "ContractAddress" },
			{ name = "amount", type = "u128" },
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
		to = "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
		amount = "0x100",
	},
}

-- Identify which revision the data uses
local revision = TypedData.identifyRevision(typedData) -- "1" (ACTIVE)

-- Compute the full message hash (includes domain separator + account address)
local accountAddress = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
local messageHash = TypedData.getMessageHash(typedData, accountAddress)
print("Message hash:", messageHash)

-- Or use Account directly (recommended)
-- local hash = account:hashMessage(typedData)
-- local sig = account:signMessage(typedData) -- { "0x<r>", "0x<s>" }
```

### Type Hashing

For debugging or building custom typed data:

```luau
--!strict
local TypedData = StarknetLuau.wallet.TypedData

local types = {
	Transfer = {
		{ name = "to", type = "ContractAddress" },
		{ name = "amount", type = "u128" },
	},
}

-- Get the canonical type encoding string
local encoded = TypedData.encodeType(types, "Transfer", "1")
print("Encoded type:", encoded) -- "Transfer(to:ContractAddress,amount:u128)"

-- Get the type hash (snKeccak or Pedersen depending on revision)
local typeHash = TypedData.getTypeHash(types, "Transfer", "1")
print("Type hash:", typeHash)
```

## TransactionHash: Pure Hash Computation

`TransactionHash` computes V3 transaction hashes using Poseidon. These are the hashes that get signed.

### Computing an Invoke Transaction Hash

```luau
--!strict
local TransactionHash = StarknetLuau.tx.TransactionHash

local txHash = TransactionHash.calculateInvokeTransactionHash({
	senderAddress = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	compiledCalldata = { "0x1", "0x2", "0x3" },
	chainId = "0x534e5f5345504f4c4941", -- "SN_SEPOLIA"
	nonce = "0x0",
	resourceBounds = {
		l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
		l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
	},
})
print("Invoke tx hash:", txHash)
```

### Computing a Deploy Account Transaction Hash

```luau
--!strict
local TransactionHash = StarknetLuau.tx.TransactionHash

local deployHash = TransactionHash.calculateDeployAccountTransactionHash({
	classHash = "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f",
	constructorCalldata = { "0xabc123" }, -- public key
	contractAddress = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	salt = "0xabc123",
	chainId = "0x534e5f5345504f4c4941",
	nonce = "0x0",
	resourceBounds = {
		l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
		l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
		l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
	},
})
print("Deploy tx hash:", deployHash)
```

### Helper Functions

```luau
--!strict
local TransactionHash = StarknetLuau.tx.TransactionHash

-- Hash the fee field (tip + resource bounds → Poseidon digest)
local feeHash = TransactionHash.hashFeeField("0x0", {
	l1Gas = { maxAmount = "0x186a0", maxPricePerUnit = "0x5af3107a4000" },
	l2Gas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
	l1DataGas = { maxAmount = "0x0", maxPricePerUnit = "0x0" },
})

-- Encode DA mode
local daMode = TransactionHash.hashDAMode(0, 0) -- L1 data availability
```

## Practical Example: Custom Signature Verification

Here's a complete example that verifies a signature produced by an external system (e.g., a backend service or another SDK):

```luau
--!strict
-- ServerScriptService/VerifyExternalSignature.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local BigInt = StarknetLuau.crypto.BigInt
local StarkField = StarknetLuau.crypto.StarkField
local StarkCurve = StarknetLuau.crypto.StarkCurve
local ECDSA = StarknetLuau.crypto.ECDSA
local Poseidon = StarknetLuau.crypto.Poseidon

-- Suppose a backend signed a message with a known public key
local pubKeyX = BigInt.fromHex("0x077da0e0de29be5c1ccc0a88cdd25c83c0e2e0c02e783e859da6274c0fa3c576")
local pubKeyY = BigInt.fromHex("0x052a68dce18b7540d3a07308e5f1682fdba78a4d022e8f5a88e2b1198f94c195")
local publicKey: StarkCurve.AffinePoint = { x = pubKeyX, y = pubKeyY }

-- Verify the public key is on the curve
if not StarkCurve.isOnCurve(publicKey) then
	warn("Invalid public key: not on curve")
	return
end

-- Hash the data we expect was signed (e.g., a game action)
local actionFelt = StarkField.fromHex("0x1") -- "claim reward"
local playerFelt = StarkField.fromHex("0x123")
local msgHash = Poseidon.hash(actionFelt, playerFelt)

-- Verify the signature
local sig: ECDSA.Signature = {
	r = BigInt.fromHex("0x<r_from_external_system>"),
	s = BigInt.fromHex("0x<s_from_external_system>"),
}

if ECDSA.verify(msgHash, publicKey, sig) then
	print("Signature verified -- action is authentic")
else
	warn("Invalid signature -- rejecting action")
end
```

## Practical Example: Building a Merkle Proof

Compute a Poseidon Merkle root over a list of values (e.g., for an allowlist):

```luau
--!strict
-- ServerScriptService/MerkleRoot.server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarknetLuau = require(ReplicatedStorage:WaitForChild("StarknetLuau"))

local BigInt = StarknetLuau.crypto.BigInt
local StarkField = StarknetLuau.crypto.StarkField
local Poseidon = StarknetLuau.crypto.Poseidon

-- Allowlisted addresses (leaves)
local leaves = {
	StarkField.fromHex("0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"),
	StarkField.fromHex("0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"),
	StarkField.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
	StarkField.fromHex("0x0fedcba9876543210fedcba9876543210fedcba9876543210fedcba987654321"),
}

-- Build the tree bottom-up, sorting pairs before hashing (Starknet convention)
local function merkleRoot(nodes: { buffer }): buffer
	if #nodes == 1 then
		return nodes[1]
	end

	-- Pad with zero if odd number of leaves
	local padded = table.clone(nodes)
	if #padded % 2 ~= 0 then
		table.insert(padded, StarkField.zero())
	end

	-- Hash pairs (sort each pair ascending before hashing)
	local parents: { buffer } = {}
	for i = 1, #padded, 2 do
		local left = padded[i]
		local right = padded[i + 1]
		-- Sort pair ascending (Starknet Merkle convention)
		if BigInt.cmp(left, right) > 0 then
			left, right = right, left
		end
		table.insert(parents, Poseidon.hash(left, right))
	end

	return merkleRoot(parents)
end

local root = merkleRoot(leaves)
print("Merkle root:", StarkField.toHex(root))
```

## Common Mistakes

**BigInt is a buffer alias.** Luau's type system cannot distinguish BigInt from a raw buffer. Passing an arbitrary buffer to a BigInt function will silently produce garbage. Always create values through `BigInt.fromHex()`, `BigInt.fromNumber()`, or `BigInt.fromBytes()`.

**StarkSigner:signHash() expects a buffer, not a hex string.** This is the most common error when building custom signing flows:

```luau
-- WRONG: passing a hex string
local sig = signer:signHash("0xdeadbeef") -- will error or produce invalid signature

-- CORRECT: convert to BigInt buffer first
local sig = signer:signHash(BigInt.fromHex("0xdeadbeef"))
```

**StarkField vs raw BigInt for negative values.** `StarkField.fromHex()` reduces modulo P, so `StarkField.fromHex(P)` gives zero. When you need the raw prime value (e.g., for i128 negatives in TypedData), use `BigInt.fromHex()` instead.

**Starknet-specific bits2int differs from standard RFC 6979.** The SDK's ECDSA implementation strips leading zero bytes and handles 63-char hex values specially to match @scure/starknet behavior. If you're cross-referencing signatures with other Starknet libraries, this is why the intermediate values may look different from a textbook RFC 6979 implementation.

**Pedersen for addresses, Poseidon for transactions.** Contract address computation uses Pedersen hash chain (`computeHashOnElements`), even though V3 transactions use Poseidon. Do not mix them.

**"StarkNetDomain" vs "StarknetDomain" in SNIP-12.** The capital "N" in "StarkNet" selects legacy revision 0 (Pedersen hashing). Lowercase "n" in "Starknet" selects active revision 1 (Poseidon hashing). Getting this wrong produces valid but incorrect hashes.

**Private key range is [1, N-1].** Zero is invalid. Values >= N are invalid. N-1 is valid (it generates -G). The SDK throws `KEY_OUT_OF_RANGE` (error code 3003) for out-of-bounds keys.

## What's Next

For a complete method-by-method reference of every public function in the SDK (including all the crypto modules covered here), see [Guide 10: API Reference](api-reference.md).
