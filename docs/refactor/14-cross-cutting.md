## Cross-Cutting Concerns

_Issues that span multiple modules. Only items affecting 2+ module directories belong here.
Single-module concerns live in their respective docs (01-13). Last validated: 2026-03-05._

---

### 1. Dependency graph & layer violations

The intended layering is: `errors/constants` → `crypto` → `signer` → `provider` → `tx` → `wallet` → `contract` → `paymaster`.

45 source files. **No circular `require()` dependencies.** One layer violation:

- `[refactor]` **wallet/Account.luau imports contract/ERC20.luau** — the only hard `require()` that points from a lower layer to a higher one. Used in two static methods: `Account.checkDeploymentBalance()` and `Account.getDeploymentFundingInfo()`, which create an ERC20 instance to read STRK balance. **Fix:** accept a balance-checking callback, or move balance-query logic to a provider-layer utility.

- `[info]` **Near-circular semantic dependency (wallet ↔ contract).** Account imports ERC20 at compile time; Contract accepts `account: any` at runtime (duck-typed) and calls `account:execute()`. No actual module loader deadlock since the contract→account direction is duck-typed, but it creates a bidirectional coupling that complicates future refactoring.

- `[refactor]` **3 paymaster modules import `ErrorCodes` separately from `StarknetError`.** `PaymasterPolicy.luau`, `PaymasterBudget.luau`, `SponsoredExecutor.luau` use `require("../errors/ErrorCodes")` instead of accessing `StarknetError.ErrorCodes` like the other 23 modules. Functionally equivalent but inconsistent. Align to the single-import pattern.

---

### 2. Shared utilities / code duplication (source)

#### 2A. Highest-ROI extractions (multi-module, >50 lines eliminable)

- `[refactor]` **JSON-RPC client infrastructure duplicated across provider/ and paymaster/ (~400 lines).** Rate limiter (`createRateLimiter`/`tryAcquire`, 29 lines each), HTTP helpers (`_doHttpRequest`, `_jsonEncode`, `_jsonDecode`), raw request (`_rawRequest`), retry loop (`_requestWithRetry`), and Promise loading (`_getPromise`, 10 lines each) are independently implemented in both `RpcProvider.luau` and `PaymasterRpc.luau`. This is the **largest cross-module DRY violation** in the SDK. See [provider/ section](./04-provider.md) for the `JsonRpcClient` extraction plan.

- `[refactor]` **`encodeByteArray()` duplicated with divergent implementations (~50 lines).** `wallet/TypedData.luau:139-191` and `contract/AbiCodec.luau:256-293` both implement Cairo ByteArray encoding (31-byte chunks, pending word, pending length) but with different chunking strategies. TypedData delegates to its local `encodeShortString()`; AbiCodec inline-encodes with a hex loop. Extract to a shared `ByteArray.encode()` utility.

- `[refactor]` **`normalizeHex()` duplicated 3× with divergent implementations.** `tx/CallData.luau:36-38` and `wallet/OutsideExecution.luau:134-136` use `BigInt.toHex(BigInt.fromHex(hex))` (BigInt roundtrip). `paymaster/PaymasterPolicy.luau:36-45` uses manual string manipulation (lowercase, strip prefix, strip leading zeros). These could produce different results for edge cases (e.g., leading zeros). Additionally, `wallet/TypedData.luau` uses the BigInt roundtrip inline at lines 68, 76, 469, 692 without a helper. Extract to a single `normalizeHex()` in a shared utility or add `BigInt.normalizeHex()`.

- `[refactor]` **`encodeShortString()` duplicated in `tx/CallData.luau:57-74` and `wallet/TypedData.luau:45-54`.** CallData version validates length (≤31) and ASCII range (≤127); TypedData version does not validate. TypedData should import from CallData to get the validation guards.

- `[refactor]` **`computeHashOnElements()` / `hashPedersen()` — same Pedersen chain-hash in 2 modules.** `wallet/Account.luau:77-84` operates on `Felt` buffers, `wallet/TypedData.luau:83-90` operates on hex strings with identical logic. Extract to `Pedersen.hashMany()` or a shared utility. See [wallet/ section](./06-wallet.md).

- `[refactor]` **ASCII-to-hex byte encoding loop duplicated 5× across 3 files.** The pattern `for i = 1, #str do table.insert(hexParts, string.format("%02x", string.byte(str, i))) end` followed by `"0x" .. table.concat(hexParts)` appears in `TypedData.luau:51,171`, `CallData.luau:71`, and `AbiCodec.luau:272,282`. Extract to a shared `asciiToHex(str): string` utility.

#### 2B. Constant duplication

- `[refactor]` **Class hash constants defined in 3 places.** `constants.luau:21-30`, `wallet/Account.luau:44-53`, and `wallet/AccountType.luau:22-25` all define the same OZ/Argent/Braavos class hashes independently. Additionally, `Account.luau` has a `CLASS_HASH_TO_TYPE` lookup table (lines 57-69) with historical versions (OZ v0.14, Argent v0.3.1) not in `constants.luau`. See [wallet/ section](./06-wallet.md) for consolidation plan.

- `[refactor]` **`CONTRACT_ADDRESS_PREFIX` duplicated.** `wallet/Account.luau:26` and `constants.luau:37` define the same hex constant. Account should import from constants.

- `[refactor]` **Stark prime P computed twice**: `StarkField.luau:16` and `wallet/TypedData.luau:25`. TypedData should import from StarkField.

- `[refactor]` **Chain ID constants (`SN_MAIN`, `SN_SEPOLIA`) duplicated.** `constants.luau:11,14` and `tx/TransactionHash.luau:48-49` both define the same values. TransactionHash should import from constants.

- `[refactor]` **ETH/STRK token addresses hardcoded in AvnuPaymaster.** `paymaster/AvnuPaymaster.luau` has 4 inline occurrences (lines 36, 41, 58, 63) of the same addresses defined in `constants.luau:44,47`. Should import from constants.

#### 2C. Type duplication

- `[refactor]` **`Promise<T>` type defined in 2 places**: `RpcProvider.luau:15-19` and `PaymasterRpc.luau:15-19`. Move to `RpcTypes.luau` as a single source of truth.

- `[refactor]` **`HttpRequest` / `HttpResponse` types defined in 2 places**: `RpcTypes.luau:83-96` and `PaymasterRpc.luau:21-33`. PaymasterRpc should import from RpcTypes.

- `[refactor]` **`ResourceBounds` type exists in 2 incompatible shapes.** `tx/TransactionHash.luau:18-27` defines camelCase with 3 fields (`l1Gas`, `l2Gas`, `l1DataGas`). `provider/RpcTypes.luau:207-210` defines snake_case with 2 fields (`l1_gas`, `l2_gas`). The `l1DataGas`→`l1_data_gas` mapping is handled by `TransactionBuilder.toRpcResourceBounds()` which silently drops `l1DataGas`. Should be documented or unified.

- `[refactor]` **`Call` type defined independently in 3+ modules.** `PaymasterRpc.Call` (PaymasterRpc.luau:49-53), `TransactionBuilder` call shape, and `Contract.populate()` output all use `{contractAddress, entrypoint, calldata}` but define it independently. Extract to a shared `types.luau` or `RpcTypes.luau`.

- `[refactor]` **`WaitOptions` type defined identically in 2 places.** `tx/TransactionBuilder.luau:60-63` and `provider/RpcTypes.luau:351-354` both define `{ retryInterval: number?, maxAttempts: number? }`. TransactionBuilder should import from RpcTypes.

- `[api]` **No shared `PaymasterDetails` type.** Account methods (`estimatePaymasterFee`, `executePaymaster`, `deployWithPaymaster`) all accept `paymasterDetails: { [string]: any }`. Consumers have no type guidance. Define and export `PaymasterDetails` type in paymaster module or a shared types file.

#### 2D. Micro-duplication patterns

- `[refactor]` **Hex prefix check pattern repeated 6× across 4 files.** `string.sub(s, 1, 2) == "0x" or ... == "0X"` appears in `TypedData.luau` (×3), `OutsideExecution.luau` (×1), `RpcProvider.luau` (×1), `BigInt.luau` (×1). Consider a shared `hasHexPrefix(s)` utility if extracting other hex utilities anyway.

- `[refactor]` **`_sleep`/`_clock` injection boilerplate in 7 modules, no shared type.** `RpcProvider`, `PaymasterRpc`, `SponsoredExecutor`, `PaymasterPolicy`, `PaymasterBudget`, `AvnuPaymaster`, `EventPoller` all independently declare `_sleep: ((seconds: number) -> ())?` and `_clock: (() -> number)?` in config types, default them identically (`config._sleep or function(s) task.wait(s) end`, `config._clock or os.clock`), and store them identically. Extract a shared `TestableConfig` type or `applyDefaults()` helper (~35 lines eliminable).

- `[refactor]` **`buildConstructorCalldata()` in Account.luau duplicates AccountType `__call` logic.** `Account.luau:90-101` reimplements the same OZ/Argent calldata construction that `AccountType.OZ.__call` (line 38) and `AccountType.Argent.__call` (lines 57-62) provide. The Argent branch is character-for-character identical. Account should call `AccountType.OZ(publicKey)` / `AccountType.Argent(ownerKey, guardianKey)` instead.

#### 2E. Other cross-module duplication

- `[refactor]` **`bufferToHex()` duplicated verbatim** in `crypto/Keccak.luau:359-369` and `crypto/SHA256.luau:292-302`. Identical 10-line function + `HEX_CHARS` constant. Extract to a shared `BufferUtils.luau`.

- `[refactor]` **`toBytes32()`** in `crypto/ECDSA.luau:41-55` (fixed-length BigInt serialization) is a pattern needed in transaction hash computation too. Consider `BigInt.toBytes32()` or `BigInt.toBytesFixed(n)`.

- `[refactor]` **`u256ToBigInt()` utility trapped in Account.luau.** `wallet/Account.luau:106-114` converts `{low, high}` u256 to single BigInt. This is a general-purpose operation useful in AbiCodec, Contract, and ERC20 modules. Should live in `BigInt.fromU256()` or a shared utility.

- `[refactor]` **Transient error classification duplicated between SponsoredExecutor and PaymasterRpc.** `SponsoredExecutor.isTransientError()` (lines 107-130) lists 4 codes that ARE transient; `PaymasterRpc._requestWithRetry()` (lines 388-401) lists 8 codes that are NOT retryable. Same classification expressed inversely. Centralize as `ErrorCodes.isTransient(code)`.

- `[fix]` **DA modes hardcoded in `TransactionBuilder.buildInvokeTransaction()` and `buildDeployAccountTransaction()`.** Despite accepting `nonceDataAvailabilityMode`/`feeDataAvailabilityMode` parameters, both builder functions output `"0x0"`. This causes a hash/transaction mismatch for non-L1 DA modes. See [tx/ section](./05-tx.md) for details.

---

### 3. Interface boundaries & duck typing

#### 3A. provider: any

**8+ constructor signatures accept `provider: any`**: Account, TransactionBuilder, Contract, ERC20, ERC721, AccountFactory, NonceManager, EventPoller. Each calls a different subset of provider methods:

| Consumer | Methods called on provider |
|----------|--------------------------|
| TransactionBuilder | `_getPromise()`, `getNonce()`, `getChainId()`, `estimateFee()`, `addInvokeTransaction()`, `addDeployAccountTransaction()`, `waitForTransaction()` |
| Account | `_getPromise()`, `getNonce()`, `waitForTransaction()`, `._nonceManager` (field) |
| Contract | `call()`, `getEvents()` |
| ERC20/ERC721 | (delegates to Contract) |
| EventPoller | `_requestWithRetry()` (private — see coupling section) |
| NonceManager | `_getPromise()`, `getNonce()` |
| AccountFactory | `._PromiseModule` (field) |
| SponsoredExecutor | `account._provider:_getPromise()`, `account._provider:waitForTransaction()` |

- `[api]` **Define a `ProviderInterface` type** based on the union of all public methods actually called. Minimum: `getNonce`, `getChainId`, `estimateFee`, `call`, `getEvents`, `addInvokeTransaction`, `addDeployAccountTransaction`, `waitForTransaction`, plus a public `getPromise()` accessor.

#### 3B. account: any

Two implicit account interfaces exist:

| Consumer | Methods/fields used |
|----------|-------------------|
| TransactionBuilder | `account.address`, `account.signer:signTransaction(txHash)` |
| Contract | `account:execute({call}, options)` |
| SponsoredExecutor | `account:executePaymaster()`, `account._provider` (private field) |

- `[api]` **Define an `AccountInterface` type** or at minimum document the structural contract that `account: any` must satisfy.

#### 3C. Signer interface

Two implicit signer interfaces exist in the SDK:

| Context | Interface |
|---------|-----------|
| TransactionBuilder (minimal) | `{ signTransaction(txHash: buffer): Signature }` |
| Account (full) | `{ signTransaction(txHash: buffer): Signature, signRaw(msgHash: buffer): Signature, getPubKey(): buffer, getPublicKeyHex(): string }` |

- `[api]` **Export a `SignerInterface` type** from `signer/` that all consumers can import. The minimal interface (signTransaction only) should be sufficient for TransactionBuilder; the full interface lives on StarkSigner.

#### 3D. Return value inconsistencies at API boundaries

- `[api]` **`RpcProvider:addInvokeTransaction()` returns a bare `string`** (the transaction hash), while **`addDeployAccountTransaction()` returns `{ transaction_hash, contract_address }`** (a snake_case table). TransactionBuilder handles this correctly but the internal API is asymmetric. Both should return consistent shapes.

- `[api]` **`Account:executePaymaster()` passes through the paymaster's raw return value** (line 1104: `resolve(execResult)`) without normalizing to a consistent SDK shape, unlike every other `Account` method which constructs `{ transactionHash, ... }`. The return shape depends entirely on the paymaster implementation.

- `[fix]` **`maxFee` support inconsistency.** `TransactionBuilder:deployAccount()` implements `maxFee` cap logic, but `TransactionBuilder:execute()` silently ignores `maxFee` despite `ExecuteOptions` having the field in its type (line 27). See [tx/ section](./05-tx.md).

---

### 4. Private method coupling

- `[refactor]` **`_getPromise()` called 21 times across 6 files despite being private.** Account.luau (7×), TransactionBuilder.luau (4×), NonceManager.luau (2×), SponsoredExecutor.luau (1× via `account._provider`), RpcProvider.luau (4× internal), PaymasterRpc.luau (2× internal). Either make public `getPromise()` or inject the Promise module at construction time.

- `[refactor]` **`_requestWithRetry()` called by EventPoller despite being private.** EventPoller.luau lines 68 and 109 bypass the public API. Add a public `fetchSync()` method or `rawRequest()` to RpcProvider.

- `[refactor]` **`_nonceManager` accessed directly by Account.** Account.luau accesses `provider._nonceManager` as a private field. Use `provider:getNonceManager()` (which exists at RpcProvider:636 but is not in the exported type).

- `[refactor]` **`_PromiseModule` accessed inconsistently.** `AccountFactory.luau:287` accesses `provider._PromiseModule` (field), while `Account.luau` uses `provider:_getPromise()` (method). Same private access intent, different patterns. Align on a single public accessor.

- `[refactor]` **SponsoredExecutor double encapsulation breach.** `SponsoredExecutor.luau:289` calls `account._provider:_getPromise()` — accesses private `_provider` field on Account, then calls private `_getPromise()` on the provider. Lines 393, 397 also access `account._provider` directly for `waitForTransaction()`. See [paymaster/ section](./08-paymaster.md).

- `[refactor]` **AvnuPaymaster private field access.** `AvnuPaymaster.luau:254` accesses `innerAny._PromiseModule` on the wrapped PaymasterRpc instance to wrap cached results in a Promise. Should use a public method instead.

---

### 5. Error handling consistency

- `[ok]` All crypto modules use `StarknetError` structured errors with `ErrorCodes` constants.
- `[ok]` Error messages include module prefix (e.g., "ECDSA.sign:", "StarkField:", "StarkCurve:").
- `[ok]` Validation errors use `StarknetError.validation()`, crypto errors use `StarknetError.signing()`.
- `[ok]` **No raw `error("string")` calls remain** in any source module — all 130+ migrated to structured errors.
- `[ok]` **No raw `reject("string")` calls remain** — all 55+ use `StarknetError` objects.
- `[ok]` No string-based error matching (`string.find`, `string.match`) in any `pcall` or `:catch()` handler.
- `[ok]` Validation codes (1xxx) used across all modules — appropriate since input validation can occur at any layer.
- `[ok]` Signing codes (3xxx) confined to crypto/ and signer/ — clean boundary.
- `[ok]` RPC codes (2xxx) confined to provider/ — clean boundary except one minor case noted below.
- `[refactor]` **7 `StarknetError.new()` misuses** where specific subtypes should be used. See [errors/ section](./02-errors.md) for full table.
- `[refactor]` **`MATH_ERROR` code used with inconsistent subtypes** — `validation()` in BigInt/StarkField vs `new()` (base) in Pedersen. Consumer catching math errors cannot rely on `:is("ValidationError")` consistently.
- `[refactor]` **`:is()` method and `isStarknetError()` are never used in production** — only in tests. The 2 production error-type checks use raw `._type == "RpcError"` (RpcProvider.luau:322, PaymasterRpc.luau:388). The 5 production `.code ==` checks are in RpcProvider, PaymasterRpc, and SponsoredExecutor. `SponsoredExecutor.isTransientError()` uses `type(err) ~= "table"` instead of `isStarknetError()`. Either dogfood the hierarchy API internally or acknowledge it's consumer-facing only.
- `[refactor]` **`NONCE_EXHAUSTED` (2014) type/code domain mismatch.** `NonceManager.luau:121` uses `StarknetError.transaction()` with a 2xxx-range code. The error's `._type` is `"TransactionError"` but its numeric code places it in the RPC domain.
- `[api]` **Missing `PaymasterError` subtype.** 15 error codes across 4+ files have no dedicated factory or hierarchy entry. Paymaster errors are thrown as untyped `StarknetError.new()`, `rpc()`, or `validation()` — inconsistent and hard to discriminate programmatically. `Account.luau` lines 874, 1077 use `StarknetError.new(..., "PaymasterError")` instead of a dedicated factory.
- `[refactor]` **Error code numeric ranges don't always match error subtypes.** `TRANSACTION_REVERTED` (2004) and `TRANSACTION_REJECTED` (2005) are in the 2000 RPC range but used with `StarknetError.transaction()`. `MATH_ERROR` (3010) is in the 3000 signing range but used with both `validation()` and `new()`. No enforcement that code ranges and `_type` subtypes are aligned.

---

### 6. API naming & consistency

#### 6A. Confirmed consistent

- `[ok]` Constructors: `zero()`, `one()`, `fromNumber(n)`, `fromHex(hex)` — consistent across BigInt, StarkField, StarkScalarField.
- `[ok]` Arithmetic: `add(a,b)`, `sub(a,b)`, `mul(a,b)`, `square(a)`, `neg(a)`, `inv(a)` — consistent across fields.
- `[ok]` Conversions: `toHex(a)`, `toBigInt(a)`, `eq(a,b)`, `isZero(a)` — consistent.
- `[ok]` Hash functions: `hash(a,b)` for Poseidon/Pedersen, `keccak256(input)` / `hash(data)` for Keccak/SHA256 — different names are appropriate since they serve different roles.
- `[ok]` Options pattern: every module uses `local opts = options or {}` uniformly. No modules use explicit nil checks as an alternative.
- `[ok]` camelCase (SDK) / snake_case (RPC) naming split is intentional and consistently applied at translation boundaries.
- `[ok]` `calldata` vs `compiledCalldata` distinction is intentional — per-call vs flattened multicall format.
- `[ok]` `entrypoint` (human name) vs `selector` (hash) vs `entry_point_selector` (RPC wire) distinction is intentional.

#### 6B. Issues

- `[api]` `bufferToHex()` is exposed on both `Keccak` and `SHA256` as a public method "for testing/debugging". Crypto modules shouldn't be the canonical source of hex conversion utilities. Move to BufferUtils and remove from crypto public APIs.

- `[fix]` **Address comparison in `Contract.luau:400,410` uses `string.lower()` instead of `normalizeHex()`.** This is a different normalization strategy — `string.lower()` preserves leading zeros while `BigInt.toHex(BigInt.fromHex(...))` strips them. If a provider returns `0x00abc` and the contract address is stored as `0xabc`, event filtering via `string.lower` comparison would fail while `normalizeHex` would succeed. **Bug risk.**

- `[api]` **No address normalization on construction.** `Account.new()` and `Contract.new()` store addresses as-given without normalization. If a user passes `0x00ABC` to Contract and `0xabc` to Account, internal comparisons could silently fail.

- `[api]` **`PaymasterPolicy.allowedMethods` semantic mismatch.** The config field name `selector` implies a pre-hashed value, but `validate()` at line 219 accesses `call.entrypoint or call.selector` and does a plain string match. If `allowedMethods` stores selectors but calls provide human-readable names, comparison fails silently.

- `[refactor]` **Account:signMessage() bypasses signTransaction().** `Account.luau` calls `signer:signRaw(hashBuf)` then manually converts `{ BigInt.toHex(sig.r), BigInt.toHex(sig.s) }` — duplicating the hex conversion that `signTransaction()` already does. See [signer/ section](./03-signer.md).

---

### 7. Type exports & shared types

- `[ok]` `BigInt.BigInt = buffer` — exported, used by StarkField/StarkScalarField.
- `[ok]` `StarkField.Felt = buffer` — exported, used by StarkCurve, Poseidon, Pedersen.
- `[ok]` `StarkScalarField.Scalar = buffer` — exported, used by ECDSA.
- `[ok]` `StarkCurve.AffinePoint`, `StarkCurve.JacobianPoint` — exported, used by Pedersen, ECDSA.
- `[ok]` `ECDSA.Signature = { r: buffer, s: buffer }` — exported.
- `[ok]` `BigInt.BarrettCtx` — exported, used by field modules.
- `[type]` All buffer-based types (`BigInt`, `Felt`, `Scalar`) are aliases for `buffer`. Luau's type system cannot distinguish them structurally, so a `Felt` can be passed where a `Scalar` is expected without type errors. This is a known Luau limitation, not actionable.

- `[api]` **Missing shared types file.** The SDK would benefit from a `src/types.luau` that centralizes: `Call`, `ProviderInterface`, `AccountInterface`, `SignerInterface`, `PaymasterDetails`, `WaitOptions`. Currently each consumer defines these independently.

---

### 8. Require patterns (Roblox vs Lune)

- `[ok]` Source modules (`src/`) use `require("./Module")` for sibling imports — works in both Lune and modern Roblox.
- `[ok]` Barrel exports (`init.luau`) use `require(script.Module)` — Roblox-only, which is correct since barrels are only used at runtime.
- `[ok]` Test files use relative paths from test location: `require("../../src/crypto/BigInt")` — Lune-compatible.
- `[doc]` This dual-pattern is documented in MEMORY.md but not in the codebase itself. Consider a comment in `init.luau` files explaining the pattern for new contributors.

---

### 9. Test infrastructure duplication

#### 9A. Mock HTTP handlers (~832 eliminable lines)

**16 test files** define their own `createMockHttpRequest()` — a near-identical ~52-line function that decodes JSON-RPC, dispatches to `mockHandlers`, and returns a response:

| Directory | Files |
|-----------|-------|
| provider/ | RpcProvider, NonceManager, EventPoller, getAllEvents |
| tx/ | TransactionBuilder, DeployAccount |
| wallet/ | Account, AccountFactory, PrefundingHelper, BatchDeploy |
| contract/ | Contract, ERC20, ERC721, ContractEvents |
| paymaster/ | PaymasterRpc, AvnuPaymaster |

Additionally, `RequestBatcher.spec.luau` has a specialized `createBatchMockHttp` (~100 lines).

#### 9B. Mock provider factory (~224 eliminable lines)

The same **16 files** each define `createTestProvider()` (~14 lines), creating an RpcProvider with mock HTTP, no-op sleep, `os.clock`, `retryAttempts=1`, and MockPromise injected.

#### 9C. Common handler presets (~360 eliminable lines)

**12 files** independently define identical `resetHandlers()` blocks with the same 4 core handlers: `starknet_chainId` → SN_SEPOLIA, `starknet_getNonce` → "0x5", `starknet_estimateFee` → standard fee response, `starknet_addInvokeTransaction` → `{ transaction_hash = "0xabc123" }`.

#### 9D. Test constant duplication (~43 one-liners)

| Constant | Files defining it | Canonical source |
|----------|------------------|-----------------|
| `SN_SEPOLIA` chain ID | 11 spec files | `tests/fixtures/test-vectors.luau:471` (unused) |
| Primary test private key | 15 spec files (6 different variable names) | — |
| ETH token address | 14 spec files | — |
| OZ class hash | 3 spec files | — |

#### 9E. Hand-rolled test framework in 3 paymaster specs (~210 eliminable lines)

`PaymasterPolicy.spec`, `PaymasterBudget.spec`, and `SponsoredExecutor.spec` each reimplement ~70 lines of `test()`, `describe()`, `expect()`, and a summary printer instead of using the global runner from `run.luau`. This makes them invisible to the test runner's aggregate reporting.

#### 9F. Total eliminable test duplication

| Category | Copies | Lines/copy | Total |
|----------|--------|-----------|-------|
| `createMockHttpRequest()` | 16 | ~52 | ~832 |
| `createTestProvider()` | 16 | ~14 | ~224 |
| `mockHandlers` + `requestLog` decls | 16 | ~3 | ~48 |
| `resetHandlers()` common subset | 12 | ~30 | ~360 |
| Test constants | 43 | 1 | ~43 |
| Mini test framework (paymaster) | 3 | ~70 | ~210 |
| **Total** | | | **~1,717** |

#### 9G. Recommended extraction: `tests/helpers/TestUtils.luau`

```
TestUtils.SN_SEPOLIA              -- shared constant
TestUtils.TEST_PRIVATE_KEY        -- shared constant
TestUtils.ETH_TOKEN_ADDRESS       -- shared constant
TestUtils.OZ_CLASS_HASH           -- shared constant
TestUtils.MockPromise             -- re-export

TestUtils.createMockRpcLayer()    -- returns { mockHandlers, requestLog, createMockHttpRequest, resetLog }
TestUtils.createTestProvider(mockLayer, overrides?)
TestUtils.defaultHandlers.chainId(id?)
TestUtils.defaultHandlers.getNonce(nonce?)
TestUtils.defaultHandlers.estimateFee(response?)
TestUtils.defaultHandlers.addInvoke(txHash?)
TestUtils.applyDefaultHandlers(mockHandlers, options?)
```

Factory-based (not global state) so tests remain isolated. Each test file would drop from ~120 lines of boilerplate to ~10 lines.

---

### 10. Cross-module issues from per-module docs

Items discovered in individual module reviews (01-13) that span 2+ modules. Consolidated here as the authoritative location; the per-module docs should reference this section instead of maintaining their own copy.

- `[refactor]` **TransactionBuilder `Account` type vs wallet `Account` class.** `tx/TransactionBuilder.luau:16-21` defines a minimal `Account = { address: string, signer: { signTransaction: ... } }` interface. `wallet/Account.luau` structurally conforms but doesn't import or reference it. Fragile duck-typing contract — if TransactionBuilder changes the expected shape, wallet/Account would break silently. From [tx/ section](./05-tx.md).

- `[refactor]` **`ExecuteOptions` and `DeployAccountOptions` share 8 identical fields** in `tx/TransactionBuilder.luau`. Both types duplicate `nonce?`, `maxFee?`, `resourceBounds?`, `feeMultiplier?`, `dryRun?`, `waitForConfirmation?`, `nonceDataAvailabilityMode?`, `feeDataAvailabilityMode?`. Extract a shared `BaseTxOptions` type. From [tx/ section](./05-tx.md).

- `[refactor]` **ERC20/ERC721 preset structural duplication.** `contract/ERC20.luau` and `contract/ERC721.luau` are structurally identical — same factory, same validation, same pattern — differing only in ABI content. Both do redundant validation vs `Contract.new()`. Consider a `PresetFactory` or just inline the ABIs. From [contract/ section](./07-contract.md).

- `[fix]` **Missing event definitions in ERC20/ERC721 preset ABIs.** Neither preset's hardcoded ABI includes Transfer, Approval, or ApprovalForAll event definitions, making `parseEvents()`, `hasEvent()`, and `getEvents()` non-functional on preset instances. From [contract/ section](./07-contract.md).

- `[fix]` **`tonumber(hexString, 16)` bug pattern.** `tonumber("0xFF", 16)` returns nil in Luau when the string has a `0x` prefix. This affects 3/5 examples (from [examples/ section](./10-examples.md)), multiple doc code snippets (from [docs/ section](./11-docs.md)), and `AbiCodec.luau`'s `parseHexNumber` function has a dead first branch due to this (from [contract/ section](./07-contract.md)).

- `[refactor]` **Test framework inconsistency.** 38 spec files use the `run.luau` runner framework; 3 paymaster specs use an incompatible hand-rolled harness. From [tests/ section](./12-tests.md).

---

### 11. Contradictions between refactor docs

| Issue | Doc A | Doc B | Resolution |
|-------|-------|-------|------------|
| Test count | 12-tests.md says 1926 | 11-docs.md says ~2098 | Re-count with `make test` and update both |
| AbiCodec public status | 07-contract.md says "intentionally not exported" | 11-docs.md says api-reference.md documents it as public | Code is authoritative — not exported. Update api-reference.md |

No other inter-doc contradictions found.

---

### 12. Prioritized extraction plan

Ranked by **eliminable lines × risk reduction**, highest ROI first:

| Priority | Extraction | Lines saved | Risk | Modules affected |
|----------|-----------|-------------|------|-----------------|
| **P0** | `tests/helpers/TestUtils.luau` — shared mock infra + constants | ~1,650 | Low (test-only) | 16 test files |
| **P0** | Migrate 3 paymaster specs to `run.luau` framework | ~210 | Low (test-only) | 3 test files |
| **P1** | `src/provider/JsonRpcClient.luau` — rate limiter, HTTP, retry, Promise | ~400 | Medium | RpcProvider, PaymasterRpc |
| **P1** | Centralize constants — class hashes, chain IDs, token addresses, PREFIX | ~30 | Low | constants, Account, AccountType, TransactionHash, AvnuPaymaster |
| **P2** | `src/shared/HexUtils.luau` — normalizeHex, asciiToHex, hasHexPrefix, bufferToHex | ~80 | Low | 8 modules |
| **P2** | `src/shared/types.luau` — Call, ProviderInterface, AccountInterface, SignerInterface, PaymasterDetails, WaitOptions | ~30 types | Low | 10+ modules |
| **P2** | `src/shared/ByteArray.luau` — encodeByteArray, encodeShortString | ~60 | Low | TypedData, AbiCodec, CallData |
| **P2** | `Pedersen.hashMany()` — Pedersen chain-hash utility | ~15 | Low | Account, TypedData |
| **P3** | Make `_getPromise()` public or inject Promise at construction | ~0 (coupling fix) | Medium | 6 modules, 21 call sites |
| **P3** | Fix address normalization on construction + Contract event filtering | ~5 | Medium (behavioral) | Account, Contract |
| **P3** | Fix DA mode passthrough in TransactionBuilder | ~4 | Medium (correctness) | TransactionBuilder |
| **P3** | Add `PaymasterError` subtype to error hierarchy | ~20 | Low | StarknetError, 4 paymaster modules |
| **P3** | Break wallet→contract dependency (Account→ERC20) | ~10 | Medium | Account |
| **P3** | Add event definitions to ERC20/ERC721 preset ABIs | ~20 | Low | ERC20, ERC721 |

**Total source lines eliminable through deduplication: ~650+**
**Total test lines eliminable through deduplication: ~1,860**
**Grand total: ~2,500 lines** (from ~14,000 source + ~12,000 test ≈ 9.6% reduction)
