# Crypto Module Deep Dive

The `crypto` module is the foundation of starknet-luau. It implements all cryptographic primitives needed for Starknet interaction -- entirely in pure Luau with no native FFI.

## Architecture Overview

```
ECDSA (signing)
  |
  +-- StarkCurve (elliptic curve operations)
  |     |
  |     +-- StarkField (arithmetic mod prime P)
  |     |     |
  |     |     +-- BigInt (arbitrary precision integers)
  |     |
  |     +-- StarkScalarField (arithmetic mod curve order N)
  |           |
  |           +-- BigInt
  |
  +-- SHA256 / HMAC (RFC 6979 nonce generation)

Poseidon (hash)  -- uses StarkField
Pedersen (hash)  -- uses StarkCurve + StarkField
Keccak (hash)    -- standalone (buffer-based)
SHA256 (hash)    -- standalone (buffer-based)
```

## BigInt -- Arbitrary Precision Integers

BigInt is the lowest-level primitive. It provides arbitrary-precision integer arithmetic using buffer-backed f64 limb arrays.

### Design

- **Representation**: 11 limbs of 24 bits each (264 bits total), stored in a Luau `buffer`
- **Limb size**: 24 bits per limb keeps products under 2^53 (f64 precision limit)
- **Carry propagation**: Uses the IEEE 754 rounding trick for fast carries
- **Performance**: Uses `--!native` and `--!optimize 2` pragmas for JIT compilation

### Creating BigInts

```luau
local BigInt = Starknet.crypto.BigInt

-- From hex string (most common for Starknet values)
local a = BigInt.fromHex("0x1a2b3c")

-- From number (only safe for values < 2^53)
local b = BigInt.fromNumber(42)

-- From raw bytes
local c = BigInt.fromBytes(someBuffer)

-- Constants
local zero = BigInt.zero()
local one = BigInt.one()
```

### Arithmetic

```luau
local sum = BigInt.add(a, b)
local diff = BigInt.sub(a, b)
local product = BigInt.mul(a, b)
local quotient = BigInt.div(a, b)
local remainder = BigInt.mod(a, b)
local q, r = BigInt.divmod(a, b)
```

### Modular Arithmetic

For field operations, BigInt provides modular variants:

```luau
local m = BigInt.fromHex("0x800000000000011000000000000000000000000000000000000000000000001")

local result = BigInt.addmod(a, b, m)   -- (a + b) mod m
local result = BigInt.mulmod(a, b, m)   -- (a * b) mod m
local result = BigInt.powmod(a, e, m)   -- a^e mod m
local result = BigInt.invmod(a, m)      -- a^(-1) mod m (modular inverse)
```

### Bitwise Operations

```luau
local shifted = BigInt.shl(a, 4)        -- left shift by 4 bits
local shifted = BigInt.shr(a, 4)        -- right shift by 4 bits
local result = BigInt.band(a, b)        -- bitwise AND
local result = BigInt.bor(a, b)         -- bitwise OR
local bits = BigInt.bitLength(a)        -- number of significant bits
local bit = BigInt.getBit(a, 3)         -- get bit at index 3 (0 or 1)
```

### Conversions

```luau
local hex = BigInt.toHex(a)             -- "0x1a2b3c"
local bytes = BigInt.toBytes(a)         -- 32-byte big-endian buffer
local num = BigInt.toNumber(a)          -- Lua number (only safe for small values)
```

## StarkField -- Prime Field Arithmetic

StarkField wraps BigInt with automatic modular reduction over the Stark prime:

```
P = 2^251 + 17 * 2^192 + 1
P = 0x800000000000011000000000000000000000000000000000000000000000001
```

Every StarkField value (called a "felt" -- field element) is automatically reduced to `[0, P-1]`.

### Creating Field Elements

```luau
local StarkField = Starknet.crypto.StarkField

local a = StarkField.fromHex("0x1234")
local b = StarkField.fromNumber(42)
local zero = StarkField.zero()
local one = StarkField.one()
```

### Field Arithmetic

All operations automatically reduce mod P:

```luau
local sum = StarkField.add(a, b)        -- (a + b) mod P
local diff = StarkField.sub(a, b)       -- (a - b) mod P
local product = StarkField.mul(a, b)    -- (a * b) mod P
local squared = StarkField.square(a)    -- a^2 mod P
local negated = StarkField.neg(a)       -- (-a) mod P = P - a
local inverse = StarkField.inv(a)       -- a^(P-2) mod P (Fermat's little theorem)
local root = StarkField.sqrt(a)         -- square root via Tonelli-Shanks (or nil)
```

### When to Use StarkField vs BigInt

- **StarkField**: For values that represent Starknet addresses, storage values, hash inputs/outputs, and calldata felts. These are always in `[0, P-1]`.
- **BigInt**: For raw arithmetic where you need full control (e.g., scalar multiplication by the curve order, u256 values that exceed the field prime).

## StarkScalarField -- Curve Order Arithmetic

StarkScalarField is analogous to StarkField but works modulo the curve order N:

```
N = 0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f
```

This is used internally for ECDSA scalar operations (private keys, nonces, signatures). You rarely need to use it directly.

```luau
local StarkScalarField = Starknet.crypto.StarkScalarField

local k = StarkScalarField.fromHex("0xabc123")
local product = StarkScalarField.mul(k, s)  -- (k * s) mod N
```

## StarkCurve -- Elliptic Curve Operations

StarkCurve implements the Stark elliptic curve:

```
y^2 = x^3 + x + beta    (short Weierstrass form, alpha = 1)
```

### Points

A point on the curve has `{x, y}` coordinates (both field elements):

```luau
local StarkCurve = Starknet.crypto.StarkCurve

-- The generator point
local G = StarkCurve.G   -- { x: Felt, y: Felt }

-- Point operations
local sum = StarkCurve.pointAdd(p1, p2)
local doubled = StarkCurve.pointDouble(p)
local result = StarkCurve.scalarMul(k, p)  -- k * P

-- Verification
local valid = StarkCurve.isOnCurve(point)
local isInf = StarkCurve.isInfinity(point)
```

### Key Derivation

```luau
-- Public key = privateKey * G (generator point)
local publicKey = StarkCurve.getPublicKey(privateKeyBigInt)
-- publicKey = { x: Felt, y: Felt }
```

### Internal Representation

Internally, StarkCurve uses **Jacobian coordinates** `(X, Y, Z)` to avoid expensive field inversions during point addition and doubling. Conversion to affine `(x, y)` only happens when needed (e.g., returning the final result).

## Hash Functions

### Poseidon

Poseidon is Starknet's primary hash function, used for transaction hashes and most modern operations.

```luau
local Poseidon = Starknet.crypto.Poseidon

-- Hash two field elements
local h = Poseidon.hash(a, b)

-- Hash a single element
local h = Poseidon.hashSingle(x)

-- Hash a variable number of elements (sponge construction)
local h = Poseidon.hashMany({ a, b, c, d })
```

**Properties:**
- State width = 3, rate = 2, capacity = 1
- 91 rounds: 4 full + 83 partial + 4 full (Hades permutation)
- Used in V3 transaction hashes, SNIP-12 typed data (active revision)

### Pedersen

Pedersen hash is an older hash function based on elliptic curve point operations. It's still used for address computation and some legacy operations.

```luau
local Pedersen = Starknet.crypto.Pedersen

-- Hash two field elements
local h = Pedersen.hash(a, b)
```

**Properties:**
- Uses 4 pre-computed constant base points
- Processes 248-bit + 4-bit chunks
- Used in contract address derivation, legacy SNIP-12 typed data

### Keccak

Keccak-256 is the Ethereum variant (NOT SHA-3). It's used for function selectors and some cross-chain operations.

```luau
local Keccak = Starknet.crypto.Keccak

-- Raw Keccak-256 hash
local hash = Keccak.keccak256(dataBuffer)   -- returns buffer

-- Starknet keccak (result masked to 250 bits)
local felt = Keccak.snKeccak(dataBuffer)     -- returns Felt

-- Compute a function selector from its name
local selector = Keccak.getSelectorFromName("transfer")
```

**Properties:**
- Full Keccak-f[1600] permutation (24 rounds)
- 64-bit lanes emulated via `{hi, lo}` 32-bit pairs
- Domain separation byte: `0x01` (not SHA-3's `0x06`)
- `snKeccak` masks the result to 250 bits (Starknet convention)

### SHA-256

SHA-256 and HMAC-SHA-256, used internally for RFC 6979 deterministic nonce generation.

```luau
local SHA256 = Starknet.crypto.SHA256

-- SHA-256 hash
local hash = SHA256.hash(dataBuffer)         -- returns 32-byte buffer

-- HMAC-SHA-256
local mac = SHA256.hmac(keyBuffer, msgBuffer) -- returns 32-byte buffer
```

## ECDSA -- Stark Signing

ECDSA implements Starknet-flavored ECDSA signing with RFC 6979 deterministic nonce generation.

```luau
local ECDSA = Starknet.crypto.ECDSA

-- Sign a message hash with a private key
local sig = ECDSA.sign(messageHash, privateKey)
-- sig = { r: Felt, s: Felt }

-- Verify a signature
local valid = ECDSA.verify(messageHash, publicKey, sig)
-- valid = true | false
```

### Starknet-Specific Behavior

Starknet's ECDSA has custom `bits2int` and `bits2int_modN` functions that differ from standard RFC 6979:

- **`bits2int`**: Strips leading zero bytes before computing the delta shift
- **`bits2int_modN`**: When the hex representation is 63 characters, appends a trailing `'0'` to cancel a 4-bit right-shift

This ensures Starknet field elements (249-252 bits) are used directly without truncation in the signing equation.

## Performance Notes

All crypto modules use these Luau pragmas for maximum performance:

```luau
--!native
--!optimize 2
```

- `--!native` enables the Luau JIT compiler for the module
- `--!optimize 2` enables aggressive optimizations

The buffer-based arithmetic avoids table allocations and uses direct memory access, which is significantly faster than table-based implementations in Luau.

## How the Crypto Stack Fits Together

Here's how a typical transaction signing uses the crypto stack:

1. **Calldata encoding** -- BigInt converts hex values to field elements
2. **Selector computation** -- Keccak computes `sn_keccak("transfer")` to get the entry point selector
3. **Transaction hash** -- Poseidon hashes the transaction fields (sender, calldata, fees, nonce, chain ID)
4. **Signature generation** -- ECDSA signs the transaction hash using the private key:
   - SHA256/HMAC generates the deterministic nonce k (RFC 6979)
   - StarkCurve performs scalar multiplication: `R = k * G`
   - StarkScalarField computes `s = k^(-1) * (hash + r * privateKey) mod N`
5. **Address derivation** -- Pedersen computes `hash(hash(hash(0, prefix), deployer), salt, classHash)` to derive the contract address

## Further Reading

- [API Reference](api-reference.md) -- Complete function signatures for all crypto modules
- [Account Management](accounts.md) -- How keys and addresses work in practice
