## Cross-Cutting Concerns

_Issues that span multiple modules. Reference specific files where relevant._

### Shared utilities / code duplication

- `[refactor]` **`bufferToHex()` duplicated verbatim** in `crypto/Keccak.luau:359-369` and `crypto/SHA256.luau:292-302`. Identical 10-line function + `HEX_CHARS` constant. Extract to a shared `BufferUtils.luau`.
- `[refactor]` **`concatBuffers()` and `singleByte()`** in `crypto/ECDSA.luau:121-142` are general-purpose buffer utilities trapped in a crypto module. Move to shared utility.
- `[refactor]` **`readBE32()` / `writeBE32()`** in `crypto/SHA256.luau:16-28` are general big-endian I/O. Could move to shared utility if needed elsewhere.
- `[refactor]` **`toBytes32()`** in `crypto/ECDSA.luau:41-55` (fixed-length BigInt serialization) is a pattern needed in transaction hash computation too. Consider `BigInt.toBytes32()` or `BigInt.toBytesFixed(n)`.
- `[refactor]` **StarkField + StarkScalarField: 16 identical functions** (~300 lines total). Biggest DRY violation. See crypto/ section for recommended field factory approach.
- `[refactor]` **Curve order N computed twice**: `StarkScalarField.luau:17` and `StarkCurve.luau:41` both call `BigInt.fromHex()` with the same hex string. StarkCurve should import from StarkScalarField.
- `[refactor]` **Stark prime P computed twice**: `StarkField.luau:16` and `wallet/TypedData.luau:25`. TypedData should import from StarkField.
- `[refactor]` **JSON-RPC client infrastructure duplicated across provider/ and paymaster/.** Rate limiter (`createRateLimiter`, `tryAcquire`), HTTP helpers (`_doHttpRequest`, `_jsonEncode`, `_jsonDecode`), raw request (`_rawRequest`), retry loop (`_requestWithRetry`), and Promise loading (`_getPromise`) are independently implemented in both `RpcProvider.luau` (~200 lines) and `PaymasterRpc.luau` (~200 lines). This is the largest cross-module DRY violation in the SDK. See [provider/ section](./04-provider.md) for the extraction plan (`JsonRpcClient` base module).
- `[refactor]` **`Promise<T>` type defined in 2 places**: `RpcProvider.luau:15-19` and `PaymasterRpc.luau:15-19`. Move to `RpcTypes.luau` as a single source of truth.
- `[refactor]` **`HttpRequest` / `HttpResponse` types defined in 2 places**: `RpcTypes.luau:83-96` and `PaymasterRpc.luau:21-33`. PaymasterRpc should import from RpcTypes.

- `[refactor]` **`normalizeHex()` duplicated 3× with divergent implementations.** `tx/CallData.luau:36-38` and `wallet/OutsideExecution.luau:134-136` use `BigInt.toHex(BigInt.fromHex(hex))` (BigInt roundtrip). `paymaster/PaymasterPolicy.luau:36-45` uses manual string manipulation (lowercase, strip prefix, strip leading zeros). These could produce different results for edge cases. Extract to a single `normalizeHex()` in a shared utility or add `BigInt.normalizeHex()`.
- `[refactor]` **`encodeShortString()` duplicated in `tx/CallData.luau:57-74` and `wallet/TypedData.luau:45-54`.** CallData version validates length (≤31) and ASCII range (≤127); TypedData version does not validate. TypedData should import from CallData to get the validation guards.
- `[refactor]` **`ResourceBounds` type exists in 2 incompatible shapes.** `tx/TransactionHash.luau:18-27` defines camelCase with 3 fields (`l1Gas`, `l2Gas`, `l1DataGas`). `provider/RpcTypes.luau:207-210` defines snake_case with 2 fields (`l1_gas`, `l2_gas`). The `l1DataGas`→`l1_data_gas` mapping is handled by `TransactionBuilder.toRpcResourceBounds()` which silently drops `l1DataGas`. This should be documented or unified.
- `[fix]` **DA modes hardcoded in `TransactionBuilder.buildInvokeTransaction()` and `buildDeployAccountTransaction()`.** Despite accepting `nonceDataAvailabilityMode`/`feeDataAvailabilityMode` parameters, both builder functions output `"0x0"`. This causes a hash/transaction mismatch for non-L1 DA modes. See [tx/ section](./05-tx.md) for details.

- `[refactor]` **`computeHashOnElements()` / `hashPedersen()` — same Pedersen chain-hash in 2 modules.** `wallet/Account.luau:77-84` operates on `Felt` buffers, `wallet/TypedData.luau:83-90` operates on hex strings with identical logic. Extract to `Pedersen.hashMany()` or a shared utility. See [wallet/ section](./06-wallet.md).
- `[refactor]` **`u256ToBigInt()` utility trapped in Account.luau.** `wallet/Account.luau:106-114` converts `{low, high}` u256 to single BigInt. This is a general-purpose operation useful in AbiCodec, Contract, and ERC20 modules. Should live in `BigInt.fromU256()` or a shared utility.
- `[refactor]` **`CONTRACT_ADDRESS_PREFIX` duplicated.** `wallet/Account.luau:26` and `constants.luau:37` define the same hex constant. Account should import from constants.
- `[refactor]` **Class hash constants defined in 3 places.** `constants.luau:21-30`, `wallet/Account.luau:44-53`, and `wallet/AccountType.luau:22-25` all define the same OZ/Argent/Braavos class hashes independently. See [wallet/ section](./06-wallet.md) for consolidation plan.
- `[refactor]` **Test mock infrastructure duplicated across 4 wallet test files.** ~450 lines of identical `createMockHttpRequest()`, `createTestProvider()`, `resetHandlers()`, and test constants in Account.spec, AccountFactory.spec, PrefundingHelper.spec, BatchDeploy.spec. Extract to `tests/helpers/MockRpc.luau`.
- `[refactor]` **`Call` type defined independently in 3+ modules.** `PaymasterRpc.Call` (PaymasterRpc.luau:49-53), `TransactionBuilder` call shape, and `Contract.populate()` output all use `{contractAddress, entrypoint, calldata}` but define it independently. Extract to a shared `types.luau` or `RpcTypes.luau`.
- `[refactor]` **`paymasterDetails` validation duplicated 3× in Account.luau.** `estimatePaymasterFee` (lines 925-966), `executePaymaster` (lines 987-1036), and `deployWithPaymaster` (lines 771-805) each validate paymaster, feeMode, gasToken with ~30 lines of identical checks. Extract to `validatePaymasterDetails(details, methodName)`. See [paymaster/ section](./08-paymaster.md).
- `[refactor]` **Call validation after paymaster build duplicated 2× in Account.luau.** `executePaymaster` (lines 1044-1084) and `deployWithPaymaster` (lines 853-880) both normalize returned calls from typed data and validate against submitted calls with ~20 lines of identical logic.
- `[refactor]` **Transient error classification duplicated between SponsoredExecutor and PaymasterRpc.** `SponsoredExecutor.isTransientError()` (lines 107-130) lists 4 codes that ARE transient; `PaymasterRpc._requestWithRetry()` (lines 388-401) lists 8 codes that are NOT retryable. Same classification expressed inversely. Centralize as `ErrorCodes.isTransient(code)`.
- `[api]` **No shared `PaymasterDetails` type.** Account methods (`estimatePaymasterFee`, `executePaymaster`, `deployWithPaymaster`) all accept `paymasterDetails: { [string]: any }`. Consumers have no type guidance. Define and export `PaymasterDetails` type in paymaster module or a shared types file.

### Private method coupling

- `[refactor]` **`_getPromise()` called by 3 external modules despite being private.** Account.luau, NonceManager.luau (×2) call `provider:_getPromise()`. Either make public or inject the Promise module at construction time.
- `[refactor]` **`_requestWithRetry()` called by EventPoller despite being private.** EventPoller.luau lines 68 and 109 bypass the public API. Add a public `fetchSync()` method to RpcProvider.
- `[refactor]` **`_nonceManager` accessed directly by Account.** Account.luau accesses `provider._nonceManager` as a private field. Use `provider:getNonceManager()` (which exists at RpcProvider:636 but is not in the exported type).
- `[refactor]` **`_PromiseModule` accessed inconsistently.** `AccountFactory.luau:287` accesses `provider._PromiseModule` (field), while `Account.luau` uses `provider:_getPromise()` (method). Same private access intent, different patterns. Align on a single public accessor.
- `[refactor]` **SponsoredExecutor double encapsulation breach.** `SponsoredExecutor.luau:289` calls `account._provider:_getPromise()` — accesses private `_provider` field on Account, then calls private `_getPromise()` on the provider. Lines 393, 397 also access `account._provider` directly for `waitForTransaction()`. See [paymaster/ section](./08-paymaster.md).
- `[refactor]` **AvnuPaymaster private field access.** `AvnuPaymaster.luau:254` accesses `innerAny._PromiseModule` on the wrapped PaymasterRpc instance to wrap cached results in a Promise. Should use a public method instead.
- `[refactor]` **`provider: any` used in 8+ constructor signatures.** Account, TransactionBuilder, Contract, ERC20, ERC721, AccountFactory, NonceManager, EventPoller all accept `provider: any`. Define a `ProviderInterface` type or use the `RpcProvider` export type.

### Require patterns (Roblox vs Lune)

- `[ok]` Source modules (`src/`) use `require("./Module")` for sibling imports — works in both Lune and modern Roblox.
- `[ok]` Barrel exports (`init.luau`) use `require(script.Module)` — Roblox-only, which is correct since barrels are only used at runtime.
- `[ok]` Test files use relative paths from test location: `require("../../src/crypto/BigInt")` — Lune-compatible.
- `[doc]` This dual-pattern is documented in MEMORY.md but not in the codebase itself. Consider a comment in `init.luau` files explaining the pattern for new contributors.

### Error handling consistency

- `[ok]` All crypto modules use `StarknetError` structured errors with `ErrorCodes` constants.
- `[ok]` Error messages include module prefix (e.g., "ECDSA.sign:", "StarkField:", "StarkCurve:").
- `[ok]` Validation errors use `StarknetError.validation()`, crypto errors use `StarknetError.signing()`.
- `[ok]` No raw `error("string")` calls remain in any source module — all 130+ migrated to structured errors.
- `[ok]` No raw `reject("string")` calls remain — all 55+ use `StarknetError` objects.
- `[ok]` No string-based error matching (`string.find`, `string.match`) in any `pcall` or `:catch()` handler.
- `[refactor]` **7 `StarknetError.new()` misuses** where specific subtypes should be used. See [errors/ section](./02-errors.md) for full table.
- `[refactor]` **`MATH_ERROR` code used with inconsistent subtypes** — `validation()` in BigInt/StarkField vs `new()` (base) in Pedersen. Consumer catching math errors cannot rely on `:is("ValidationError")` consistently.
- `[refactor]` **`:is()` method and `isStarknetError()` are never used in production** — only in tests. The 2 production error-type checks use raw `._type == "RpcError"`. Either dogfood the hierarchy API internally or acknowledge it's consumer-facing only.
- `[api]` **Missing `PaymasterError` subtype.** 15 error codes across 4+ files have no dedicated factory or hierarchy entry. Paymaster errors are thrown as untyped `StarknetError.new()`, `rpc()`, or `validation()` — inconsistent and hard to discriminate programmatically.
- `[refactor]` **Error code numeric ranges don't always match error subtypes.** `TRANSACTION_REVERTED` (2004) and `TRANSACTION_REJECTED` (2005) are in the 2000 RPC range but used with `StarknetError.transaction()`. `MATH_ERROR` (3010) is in the 3000 signing range but used with both `validation()` and `new()`. No enforcement that code ranges and `_type` subtypes are aligned.
- `[refactor]` **Account.luau uses `StarknetError.new(..., "PaymasterError")` for paymaster errors** (lines 874, 1077) instead of a dedicated `StarknetError.paymaster()` factory. Related to the missing PaymasterError subtype noted above. See [wallet/ section](./06-wallet.md).

### API naming consistency

- `[ok]` Constructors: `zero()`, `one()`, `fromNumber(n)`, `fromHex(hex)` — consistent across BigInt, StarkField, StarkScalarField.
- `[ok]` Arithmetic: `add(a,b)`, `sub(a,b)`, `mul(a,b)`, `square(a)`, `neg(a)`, `inv(a)` — consistent across fields.
- `[ok]` Conversions: `toHex(a)`, `toBigInt(a)`, `eq(a,b)`, `isZero(a)` — consistent.
- `[ok]` Hash functions: `hash(a,b)` for Poseidon/Pedersen, `keccak256(input)` / `hash(data)` for Keccak/SHA256 — different names are appropriate since they serve different roles.
- `[api]` `bufferToHex()` is exposed on both `Keccak` and `SHA256` as a public method "for testing/debugging". Crypto modules shouldn't be the canonical source of hex conversion utilities. Move to BufferUtils and remove from crypto public APIs.

### Type exports

- `[ok]` `BigInt.BigInt = buffer` — exported, used by StarkField/StarkScalarField.
- `[ok]` `StarkField.Felt = buffer` — exported, used by StarkCurve, Poseidon, Pedersen.
- `[ok]` `StarkScalarField.Scalar = buffer` — exported, used by ECDSA.
- `[ok]` `StarkCurve.AffinePoint`, `StarkCurve.JacobianPoint` — exported, used by Pedersen, ECDSA.
- `[ok]` `ECDSA.Signature = { r: buffer, s: buffer }` — exported.
- `[ok]` `BigInt.BarrettCtx` — exported, used by field modules.
- `[type]` All buffer-based types (`BigInt`, `Felt`, `Scalar`) are aliases for `buffer`. Luau's type system cannot distinguish them structurally, so a `Felt` can be passed where a `Scalar` is expected without type errors. This is a known Luau limitation, not actionable.
