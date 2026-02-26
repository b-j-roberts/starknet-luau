# Changelog

All notable changes to starknet-luau will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-02-26

Initial release of starknet-luau -- a pure Luau SDK for Starknet blockchain interaction from Roblox games.

### Added

#### Cryptographic Primitives (`crypto`)
- **BigInt**: Buffer-based arbitrary precision integers with 24-bit f64 limbs, Barrett reduction, full modular arithmetic (94 tests)
- **StarkField**: Field arithmetic over the Stark prime P = 2^251 + 17 * 2^192 + 1 (51 tests)
- **StarkScalarField**: Scalar arithmetic over the curve order N (54 tests)
- **StarkCurve**: Elliptic curve point operations on the Stark curve (y^2 = x^3 + x + beta) with Jacobian coordinates (53 tests)
- **Poseidon**: Poseidon hash with Hades permutation (width=3, 91 rounds) for V3 transaction hashing (22 tests)
- **Pedersen**: Pedersen hash using EC point operations for legacy address computation (17 tests)
- **Keccak**: Keccak-256 (Ethereum variant) for function selector computation (24 tests)
- **SHA256**: FIPS 180-4 SHA-256 + HMAC-SHA-256 for RFC 6979 nonce generation (31 tests)
- **ECDSA**: Stark ECDSA signing with RFC 6979 deterministic nonces, cross-referenced against @scure/starknet (37 tests)

#### Signing (`signer`)
- **StarkSigner**: Key derivation, transaction signing, public key caching (21 tests)

#### RPC Provider (`provider`)
- **RpcProvider**: JSON-RPC 2.0 client with Promise-based async, token bucket rate limiting, exponential backoff retry (59 tests)
- **RpcTypes**: Complete type definitions for all Starknet JSON-RPC request/response types
- **EventPoller**: Configurable polling for contract events with start/stop lifecycle
- **RequestQueue**: 3-bucket priority queue with JSON-RPC batching for read-only methods (82 tests)
- **ResponseCache**: LRU cache with per-method TTL and block-based invalidation (89 tests)
- **NonceManager**: Per-address local nonce tracking with parallel reservation and auto-resync (64 tests)
- Expanded RPC methods: `getBlockWithTxs`, `getBlockWithReceipts`, `getTransactionByHash`, `getStorageAt`, `getClassHashAt`, `getClassAt`, `getSpecVersion` (39 tests)

#### Transaction Building (`tx`)
- **TransactionBuilder**: Orchestrates nonce fetch, fee estimation, V3 INVOKE hash computation, signing, and submission (36 tests)
- **TransactionHash**: V3 INVOKE transaction hash computation using Poseidon
- **CallData**: Multicall calldata encoding for `__execute__`

#### Account Management (`wallet`)
- **Account**: Address derivation, transaction execution, fee estimation for OpenZeppelin, Argent X, and Braavos account types (80 tests)
- **TypedData**: SNIP-12 typed data signing with both LEGACY (Pedersen) and ACTIVE (Poseidon) revisions, Merkle tree support, preset types (43 tests)

#### Contract Interaction (`contract`)
- **Contract**: ABI-driven dynamic dispatch -- view functions via `call()`, external functions via `invoke()`, with `populate()` for multicall batching (60 tests)
- **AbiCodec**: Recursive encoder/decoder for all Cairo types -- felt, bool, u256, structs, enums, Option, Result, Array, Span, ByteArray, tuples (109 tests)
- **ERC20**: Pre-built ERC-20 token interface with standard read/write methods (35 tests)
- **ERC721**: Pre-built ERC-721 NFT interface with ownership and approval methods (41 tests)

#### Error Handling (`errors`)
- **StarknetError**: Typed error hierarchy (RpcError, SigningError, AbiError, ValidationError, TransactionError) with structured codes, `pcall`-safe identity preservation, and `:is()` type checking (42 tests)
- **ErrorCodes**: Categorized error code constants (validation=1000s, RPC=2000s, signing=3000s, ABI=4000s, transaction=5000s)

#### Infrastructure
- **Constants**: Chain IDs, class hashes (OZ, Argent, Braavos), well-known token addresses, transaction versions
- **Main entry point**: Single `require()` barrel export for the entire SDK
- Dual package manager support: Wally (`b-j-roberts/starknet-luau`) and Pesde (`magic/starknet_luau`)
- CI pipeline: build, test (1,429 tests), lint (Selene), format check (StyLua)
- Automated release workflow: GitHub Release + Wally publish + Pesde publish on version tags
- 5 example scripts: read-contract, send-transaction, nft-gate, multicall, leaderboard
- 7 documentation guides: getting-started, contracts, accounts, patterns, roblox, crypto, api-reference

### Known Limitations
- V3 INVOKE transactions only (no DECLARE or DEPLOY_ACCOUNT)
- Polling-based event monitoring (no WebSocket/SSE support in Roblox)
- No session key or paymaster (SNIP-29) support yet
- Performance optimizations (windowed scalar multiplication, precomputed tables) not yet applied
- Tested against Sepolia testnet; mainnet usage should be validated independently

[0.1.0]: https://github.com/b-j-roberts/starknet-luau/releases/tag/v0.1.0
