## 11. Docs

### SPEC.md

**Wrong/nonexistent file paths in Section 2.3 (Repository Structure):**
- `src/signer/SignerInterface.luau` does not exist -- type is defined inline in `StarkSigner.luau`
- `src/provider/RpcMethods.luau` does not exist -- methods are in `RpcProvider.luau` directly
- `src/tx/CalldataEncoder.luau` does not exist -- actual file is `src/tx/CallData.luau`
- `src/tx/TransactionTypes.luau` does not exist -- types are inline in `TransactionBuilder.luau` and `TransactionHash.luau`
- `src/wallet/AccountTypes.luau` does not exist -- actual file is `src/wallet/AccountType.luau` (singular)
- `src/wallet/NonceManager.luau` does not exist at this path -- actual location is `src/provider/NonceManager.luau`
- `src/contract/AbiParser.luau` does not exist -- ABI parsing is in `Contract.luau` and `AbiCodec.luau`
- `src/contract/AbiTypes.luau` does not exist -- types are inline in `Contract.luau`
- `src/contract/presets/ERC20.luau` and `presets/ERC721.luau` -- `presets/` subdirectory does not exist; files are directly in `src/contract/`
- `tests/tx/CalldataEncoder.spec.luau` does not exist -- actual file is `tests/tx/CallData.spec.luau`
- `tests/contract/AbiParser.spec.luau` does not exist -- actual file is `tests/contract/AbiCodec.spec.luau`
- `tests/fixtures/sample-abis.luau` does not appear to exist
- `examples/sign-transaction.luau` does not exist -- actual file is `send-transaction.luau`

**15+ modules exist in src/ with zero spec coverage:**
- `src/constants.luau`
- `src/errors/StarknetError.luau`, `src/errors/ErrorCodes.luau`, `src/errors/init.luau`
- `src/contract/AbiCodec.luau`
- `src/wallet/TypedData.luau`
- `src/wallet/OutsideExecution.luau`
- `src/wallet/AccountType.luau`
- `src/wallet/AccountFactory.luau`
- `src/provider/EventPoller.luau`
- `src/provider/RequestQueue.luau`
- `src/provider/ResponseCache.luau`
- `src/provider/NonceManager.luau` (spec lists under wallet/ which is wrong)
- Entire `src/paymaster/` directory (PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor, init)

**26+ test files exist but are not listed in the spec** (DeployAccount, TransactionHash, CallData, AbiCodec, ContractEvents, ERC20, ERC721, TypedData, AccountFactory, PrefundingHelper, BatchDeploy, OutsideExecution, StarknetError, EventPoller, RequestQueue, RequestBatcher, ResponseCache, NonceManager, constants, cross-reference, sepolia integration, all 5 paymaster test files).

**Function signature mismatches (Section 3.1.4 StarkCurve):**
- `scalarMul` parameter order is wrong: spec says `(k, p)`, actual code is `(p, k)` -- point first, scalar second
- `pointAdd(p1, p2)` and `pointDouble(p)` do not exist -- actual functions are `jacobianAdd` and `jacobianDouble` on JacobianPoints
- Type name mismatch: spec says `Point`, code exports `AffinePoint`
- `StarkCurve.P` is not exported -- spec lists it but only N, G, ALPHA, BETA are exported
- Missing public functions: `affineEq`, `affineNeg`, `jacobianFromAffine`, `affineFromJacobian`

**ECDSA type mismatches (Section 3.1.9):**
- Spec says return `{ r: Felt, s: Felt }` -- actual type is `Signature = { r: buffer, s: buffer }`. r and s are scalars mod N, not field elements mod P, so "Felt" is semantically incorrect
- `verify` publicKey type: spec says `Point`, actual is `StarkCurve.AffinePoint`

**Signer mismatches (Section 3.2):**
- `SignerInterface.luau` does not exist as a separate file
- `signTransaction` parameter: spec says `Felt`, actual is `buffer`
- `signRaw` return type: spec says `{ r: Felt, s: Felt }`, actual returns `ECDSA.Signature = { r: buffer, s: buffer }`

**RpcProvider mismatches (Section 3.3):**
- Config missing many real fields: `enableQueue`, `queueConfig`, `enableCache`, `cacheConfig`, `enableNonceManager`, `nonceManagerConfig`, test injection fields
- 12+ methods exist in code but not in spec: `addDeployAccountTransaction`, `getBlockWithTxs`, `getBlockWithReceipts`, `getTransactionByHash`, `getClass`, `getClassAt`, `estimateMessageFee`, `getSyncingStats`, `getAllEvents`, `getNodeUrl`, `getMetrics`, `flushCache`
- `fetch()` has a third optional argument `options: FetchOptions?` not shown in spec
- Many RpcTypes are undocumented (BlockId, Block, BlockWithTxs, BlockWithReceipts, Transaction, DeployAccountTransactionV3, DeployAccountResult, ProviderMetrics, etc.)

**CalldataEncoder mismatches (Section 3.4.1):**
- Wrong module name throughout: spec says `CalldataEncoder`, actual is `CallData`
- `encodeFelt` only accepts string, not `string | number` as spec says
- Missing functions: `encodeShortString`, `encodeStruct`, `numberToHex`, `concat`

**TransactionHash mismatches (Section 3.4.2):**
- Wrong function name: spec says `computeInvokeV3Hash`, actual is `calculateInvokeTransactionHash`
- Wrong parameter name: spec says `calldata`, actual is `compiledCalldata`
- `l1DataGas` is required in code but marked optional in spec
- Missing: `encodeResourceBound`, `hashFeeField`, `hashDAMode`, `calculateDeployAccountTransactionHash`

**TransactionBuilder mismatches (Section 3.4.3):**
- `buildInvoke()` and `submitTransaction()` do not exist as public methods
- Missing: `deployAccount()`, `estimateDeployAccountFee()`
- `ExecuteOptions` type missing many real fields: `maxFee`, `feeMultiplier`, `paymasterData`, `dryRun`, `skipValidate`, etc.
- `execute` returns `Promise<ExecuteResult>` (table with transactionHash), not `Promise<string>`

**Account mismatches (Section 3.5.1):**
- `Account.new` config missing optional fields: `accountType?`, `classHash?`, `constructorCalldata?`
- `Account.fromPrivateKey` missing `accountType` and `guardian` fields
- `Account.computeAddress` wrongly marks `classHash` as optional -- it's required
- `account.publicKey` property does not exist -- must call `account:getPublicKeyHex()`
- `account.provider` property does not exist -- stored as `account._provider` (private)
- `account:getBalance()` method does not exist anywhere in the code
- Missing methods: `hashMessage`, `signMessage`, `getPublicKeyHex`, `waitForReceipt`, `deployAccount`, `estimateDeployAccountFee`, `getDeploymentData`, `deployWithPaymaster`, `estimatePaymasterFee`, `executePaymaster`
- Missing static methods: `detectAccountType`, `getConstructorCalldata`, `getDeploymentFeeEstimate`, `checkDeploymentBalance`, `getDeploymentFundingInfo`

**AccountTypes mismatches (Section 3.5.2):**
- Wrong file name: spec says `AccountTypes.luau`, actual is `AccountType.luau` (singular)
- API completely different: spec shows `AccountTypes.OZ_LATEST`, `AccountTypes.BRAAVOS` -- actual code uses `AccountType.OZ` (callable table), `AccountType.Argent`, `AccountType.custom()`
- Braavos not supported in AccountType -- only OZ and Argent

**NonceManager mismatches (Section 3.5.3):**
- Wrong location: spec says `src/wallet/`, actual is `src/provider/`
- API completely different: spec shows `getNonce`/`incrementNonce`/`invalidate` -- actual is `reserve`/`confirm`/`reject`/`resync`/`getMetrics`

**Contract mismatches (Section 3.6.1):**
- `contract:attach(newAddress)` does not exist
- Missing methods: `getFunctions`, `getFunction`, `hasFunction`, `parseEvents`, `queryEvents`, `getEvents`, `hasEvent`

**AbiParser (Section 3.6.2):**
- `AbiParser.luau` does not exist -- ABI parsing is in `Contract.luau` and `AbiCodec.luau`
- `ParsedABI` type does not exist as a named export

**Presets (Section 3.6.3):**
- Access path wrong: spec says `Starknet.contract.presets.ERC20`, actual is `Starknet.contract.ERC20` (no `presets` sub-table)
- Missing: `ERC20.getAbi()` and `ERC721.getAbi()` static methods
- Spec only documents camelCase method names; ABI uses snake_case (`balance_of`, `total_supply`, `owner_of`, etc.) with camelCase aliases

**Error handling (Section 5):**
- Error field name wrong: spec says `type`, actual is `_type` (underscore prefix)
- Error categories are completely different from spec's 8 string constants -- actual code has a typed hierarchy with ~40+ error codes across 7 numeric categories (1000s-7000s)

**Constants/Networks (Section 8):**
- `Starknet.networks` does not exist
- Constant names differ: spec says `INVOKE_TX_PREFIX`/`TRANSACTION_VERSION_3`, actual is `INVOKE_TX_V3`/`DEPLOY_ACCOUNT_TX_V3`/`DECLARE_TX_V3`
- Missing from spec: class hash constants, chain ID constants (`SN_MAIN`, `SN_SEPOLIA`), `CONTRACT_ADDRESS_PREFIX`, `ANY_CALLER`

**Examples (Section 9):**
- Examples 9.1, 9.2, 9.4 all use `Starknet.contract.presets.ERC20` -- should be `Starknet.contract.ERC20`

### ROADMAP.md

**Structural issues:**
- Phase 1 is completely absent -- all crypto, signer, provider, tx, wallet, contract, and error modules are implemented but have no record in the roadmap
- Phase numbering is incoherent: Phase 4 subsections use `3.4.x` prefix instead of `4.x`; gaps at 2.10, 2.12, 2.13, 3.1, 3.2, etc.
- Missing sections for many completed modules: CallData, TransactionHash, AbiCodec, TypedData, StarknetError/ErrorCodes, EventPoller, RequestQueue, ResponseCache, NonceManager, Expanded RPC, Documentation/Guides

**10 sections have all checkboxes incorrectly marked `[ ]` when work is 100% complete:**
- 3.3.1 SNIP-9 Outside Execution (82 tests, fully implemented)
- 3.3.3 AVNU Paymaster Helpers (61 tests, fully implemented)
- 3.3.4 Account Paymaster Integration (implemented in Account.luau)
- 3.3.5 Paymaster Policy Config (66 tests, fully implemented)
- 3.4.1 DEPLOY_ACCOUNT V3 Transaction Hash (51 tests in TransactionHash.spec)
- 3.4.2 Deploy Account Transaction Builder (58 tests in DeployAccount.spec)
- 3.4.3 RPC addDeployAccountTransaction (implemented in RpcProvider.luau)
- 3.4.4 Account.deployAccount() Method (full orchestration in Account.luau)
- 3.4.7 Batch Deploy for Game Onboarding (53 tests in BatchDeploy.spec)
- 3.4.8 Bridge: Paymaster-Sponsored Deployment (implemented in Account.luau)

**API naming mismatches between roadmap and code:**
- Roadmap says `paymaster_execute(userAddress, typedData, signature)` -- actual method is `executeTransaction()`
- Roadmap omits `trackingIdToLatestHash()` method (part of SNIP-29 spec)
- Roadmap says `_computeDeployAccountHash()` in TransactionBuilder -- actual is `TransactionHash.calculateDeployAccountTransactionHash()` (separate module)
- Roadmap says `TransactionBuilder:buildDeployAccountTransaction(params)` -- actual public methods are `:deployAccount()` and `:estimateDeployAccountFee()`

**Stale content:**
- Phase 3 and 4 headers read as if prerequisites are pending -- all prerequisites and all work items are complete
- Section 3.4.8 still says "Depends on Phase 3 Paymaster Integration -- implement after both phases are complete" -- both are done
- The entire roadmap reads as mostly pending when in reality only 2.9 (Performance Optimization), 2.11 (Multi-Version RPC), and Phase 5 (Future) are genuinely pending

**Test count discrepancies (MEMORY.md vs actual):**

| Module | MEMORY.md | Actual |
|--------|-----------|--------|
| BigInt | 94 | 89 |
| StarkField | 51 | 56 |
| RpcProvider | 59 | 139 |
| Account | 35+80 | 137 |
| TransactionBuilder | 36 | 40 |
| RequestQueue | 82 | 60 (+10 batcher=70) |
| ResponseCache | 89 | 60 |
| StarknetError | 42 | 41 |
| TransactionHash | 23 | 51 |

- MEMORY.md total claim of 1926 is stale -- actual count is ~2098

### CHANGELOG.md

**Total test count is massively outdated:**
- Changelog claims "1,429 tests" -- actual count is ~2,075 across 41 spec files (646 tests missing)

**Incorrect per-module test counts:**

| Module | Changelog | Actual |
|--------|-----------|--------|
| BigInt | 94 | 89 |
| StarkField | 51 | 56 |
| RpcProvider | 59 | 139 |
| RequestQueue | 82 | 60 |
| ResponseCache | 89 | 60 |
| TransactionBuilder | 36 | 40 |
| Account | 80 | 137 |
| StarknetError | 42 | 41 |

**"Known Limitations" are factually wrong:**
- Claims "V3 INVOKE transactions only (no DECLARE or DEPLOY_ACCOUNT)" -- FALSE: DEPLOY_ACCOUNT V3 is fully implemented (TransactionHash, TransactionBuilder, Account, RpcProvider, 58 dedicated tests)
- Claims "No session key or paymaster (SNIP-29) support yet" -- FALSE: Comprehensive SNIP-29 paymaster support with 5 modules and 377+ tests, plus SNIP-9 outside execution with 82 tests

**Entirely missing from the changelog (implemented but not mentioned):**
- Entire `paymaster/` module (PaymasterRpc, AvnuPaymaster, PaymasterPolicy, PaymasterBudget, SponsoredExecutor -- 377 tests across 5 test files)
- Account paymaster integration methods (estimatePaymasterFee, executePaymaster, deployWithPaymaster, getDeploymentData)
- All DEPLOY_ACCOUNT support (TransactionHash, TransactionBuilder, Account orchestration, RPC method -- tests in DeployAccount.spec, TransactionHash.spec)
- AccountType.luau (callable account type constructors)
- AccountFactory.luau (batchCreate, batchDeploy -- 52 tests)
- BatchDeploy tests (53 tests)
- Prefunding helpers (getDeploymentFeeEstimate, checkDeploymentBalance, getDeploymentFundingInfo -- 44 tests)
- OutsideExecution.luau (SNIP-9 meta-transactions -- 82 tests)
- ContractEvents tests (23 tests)
- getAllEvents tests (8 tests)
- RequestBatcher tests (10 tests)
- CallData tests (41 tests, no count given)
- TransactionHash tests (51 tests, no count given)
- constants tests (10 tests)
- integration/sepolia tests (10 tests)
- cross-reference tests (7 tests)

**Expanded RPC methods list is incomplete:**
- Missing: `getBlockWithTxHashes`, `estimateMessageFee`, `getSyncingStats`, `getEvents`, `getAllEvents`, `addDeployAccountTransaction`, `getClass`

**Braavos partially misleading:**
- Changelog says Account supports "OpenZeppelin, Argent X, and Braavos account types" -- Braavos works via older Account interface but is NOT available in the newer AccountType/AccountFactory system

### docs/guides/getting-started.md

- **Missing `paymaster` module from the module listing** (lines 77-84): `src/init.luau` exports `Starknet.paymaster` but the guide's module table omits it entirely
- All other code examples, import paths, and function signatures are correct (Account.fromPrivateKey, ERC20.new, RpcProvider.new, waitForReceipt, etc.)

### docs/guides/crypto.md

**StarkCurve section has nonexistent API:**
- `StarkCurve.pointAdd(p1, p2)` and `StarkCurve.pointDouble(p)` do not exist -- actual functions are `jacobianAdd` and `jacobianDouble` operating on JacobianPoints, not AffinePoints
- `StarkCurve.scalarMul` argument order is reversed: guide shows `scalarMul(k, p)`, actual signature is `scalarMul(p, k)` (point first, scalar second)
- `StarkCurve.isInfinity` takes a `JacobianPoint`, not an AffinePoint as implied -- passing an AffinePoint would fail (no `z` field)

**ECDSA section type issues:**
- `sign` return described as `{ r: Felt, s: Felt }` but r/s are scalars mod N, not field elements mod P -- semantically incorrect
- `verify` publicKey type not mentioned -- it requires `AffinePoint` ({x, y} table), not a hex string or buffer

**Address derivation description is incomplete (line 326):**
- Missing the `computeHashOnElements` behavior: chain Pedersen over elements then hash result with length
- Missing the 251-bit masking step

**Undocumented BigInt functions:** `submod`, `isZero`, `eq`, `cmp`, `lt`, `lte`, `clone`, `mulmodB`, `createBarrettCtx`

**Undocumented StarkField functions:** `toHex`, `toBigInt`, `eq`, `isZero`, plus `P` constant

**Undocumented StarkScalarField functions:** Almost entire API missing -- only `fromHex` and `mul` documented; missing `add`, `sub`, `square`, `neg`, `inv`, `zero`, `one`, `fromNumber`, `toHex`, `toBigInt`, `eq`, `isZero`, plus `N` constant

**Undocumented StarkCurve functions:** `jacobianFromAffine`, `affineFromJacobian`, `affineEq`, `affineNeg`, plus constants `ALPHA`, `BETA`, `N`

### docs/guides/accounts.md

**Code example inaccuracies:**
- Uses `classHash` to select account types instead of `accountType` -- will compute wrong addresses for Argent/Braavos since it defaults to OZ constructor calldata `[publicKey]` instead of Argent `[0, pubKey, 0]`
- Braavos example passes `Constants.BRAAVOS_ACCOUNT_CLASS_HASH` (implementation hash) without `accountType = "braavos"` -- wrong hash used for address computation (should use base class hash)

**Function signature issues:**
- `Account.computeAddress` shows `classHash` as optional ("defaults to OZ") -- in code it's a required field
- `account.provider` documented as public property -- actual is `account._provider` (private, underscore prefix)
- `Account:signMessage` return shown as `{ r_hex = ..., s_hex = ... }` (named keys) -- actual returns a plain array `{ hexR, hexS }`, accessed as `[1]` and `[2]`

**Address derivation formula is incomplete:**
- Missing `computeHashOnElements` behavior (chains Pedersen then hashes with count)
- Missing separate `calldataHash` computation step
- Missing 251-bit masking

**Missing documentation for entire modules:**
- `AccountType` module (`Starknet.wallet.AccountType`) -- OZ, Argent, custom() callable tables
- `AccountFactory` module (`Starknet.wallet.AccountFactory`) -- new(), createAccount(), batchCreate(), batchDeploy()
- `OutsideExecution` module (`Starknet.wallet.OutsideExecution`) -- SNIP-9 meta-transactions

**Missing Account methods:**
- `Account:estimateDeployAccountFee()` instance method
- `Account:getDeploymentData()` -- returns SNIP-29 deployment data
- `Account:deployWithPaymaster()` -- paymaster-sponsored deployment
- `Account:estimatePaymasterFee()` -- paymaster fee estimation
- `Account:executePaymaster()` -- gasless/sponsored execution
- `Account.detectAccountType()` static method
- `Account.getConstructorCalldata()` static method
- Account type constants (`ACCOUNT_TYPE_OZ`, `ACCOUNT_TYPE_ARGENT`, `ACCOUNT_TYPE_BRAAVOS`)
- Account class hash constants (`OZ_CLASS_HASH`, `ARGENT_CLASS_HASH`, `BRAAVOS_CLASS_HASH`, `BRAAVOS_BASE_CLASS_HASH`)

### docs/guides/contracts.md

**`Contract:attach()` method does not exist:**
- The guide shows `token1:attach("0xTOKEN_B")` but there is no `attach` method anywhere in Contract.luau, ERC20.luau, or ERC721.luau -- completely fictional

**Missing Contract methods:**
- `parseEvents(receipt)` -- decodes events from transaction receipt
- `queryEvents(filter?)` -- queries events from provider
- `getEvents()` -- returns list of event names in ABI
- `hasEvent(name)` -- checks if event exists
- `getFunctions()` -- returns list of function names
- `getFunction(name)` -- returns parsed function metadata
- `hasFunction(name)` -- checks if function exists

**Missing preset methods:**
- `ERC20.getAbi()` and `ERC721.getAbi()` static methods
- `ERC20:transfer_from()` not shown
- `set_approval_for_all` / `is_approved_for_all` for ERC-721 not shown

**Missing documentation:**
- EventPoller module (`Starknet.provider.EventPoller`) -- not documented in contracts guide or anywhere
- No mention of camelCase aliases for ERC-20/ERC-721 (users don't know `balanceOf` and `balance_of` both work)
- No mention of `Contract.InvokeOptions` type for dynamic dispatch options
- No event ABI entry examples (only function entries shown)

**AbiCodec correctly not exposed as public API** (confirmed: `src/contract/init.luau` only exports Contract, ERC20, ERC721)

### docs/guides/patterns.md

**Broken code examples:**
- `tonumber(balance.low, 16)` fails with `"0x"` prefix: Luau's `tonumber(str, 16)` does NOT accept the `0x` prefix, so this always returns `nil` and falls through to `or 0`. Fix: `tonumber(balance.low)` (auto-detects 0x) or `tonumber(string.sub(balance.low, 3), 16)`
- `Keccak.getSelectorFromName()` returns a buffer (Felt), not a hex string -- passing it directly into `keys = { { selector } }` (which expects `{ { string } }`) silently breaks. Must convert with `StarkField.toHex()`
- `getEvents` filter uses `to_block = "latest"` (raw string) but `EventFilter.to_block` expects a BlockId table `{ block_tag = "latest" }`. Same issue with `from_block`
- ECDSA verify wallet linking example constructs `publicKey = { x = ..., y = StarkField.fromHex("0x0") }` -- the point (x, 0) is not on the Stark curve for arbitrary x, so `verify` will always return false. Example needs either full y-coordinate or point decompression
- Address comparison `string.lower(owner) == string.lower(playerAddress)` fails on different zero-padding (e.g., `"0x1"` vs `"0x0000...0001"`). Should normalize through `BigInt.toHex(BigInt.fromHex(...))`
- Missing `Keccak` import in Event Querying section -- uses `Keccak.getSelectorFromName()` without showing how to obtain the reference

**Missing patterns for major features:**
- No error handling using `StarknetError` system -- all catch handlers use `tostring(err)` instead of `isStarknetError()` / `err:is("RpcError")`
- No paymaster/sponsored transaction patterns (critical for Roblox game developers wanting gasless player transactions)
- No account deployment/onboarding patterns (deployAccount, getDeploymentFeeEstimate, checkDeploymentBalance, AccountFactory.batchCreate/batchDeploy)
- No NonceManager pattern for parallel transactions
- No SNIP-12 TypedData pattern (signMessage/hashMessage for off-chain signatures)
- No SNIP-9 Outside Execution pattern (meta-transactions)
- No `Account.detectAccountType` pattern for unknown player wallets

### docs/guides/roblox.md

**Wrong config nesting:**
- `maxQueueDepth` shown as top-level provider config key -- actual location is inside `queueConfig`: `queueConfig = { maxQueueDepth = 100 }`
- `maxCacheEntries` shown as top-level provider config key -- actual location is inside `cacheConfig` and the field name is `maxEntries` (not `maxCacheEntries`): `cacheConfig = { maxEntries = 256 }`

**Cache TTL table incomplete/inaccurate:**
- Missing: `starknet_getClass`/`getClassAt` (indefinite), `getBlockWithTxs`/`getBlockWithReceipts` (10s), `getTransactionByHash` (never cached), `getEvents` (never cached), `syncing` (never cached), `estimateMessageFee` (never cached), `getTransactionReceipt`/`getTransactionStatus` (never cached)

**Same `tonumber(balance.low, 16)` bug** as patterns.md (lines 55, 311, 329)

**`signer:signRaw(messageHash)` shown without context:**
- `signRaw` takes a `buffer` (BigInt), not a hex string -- guide doesn't show conversion or how to obtain the signer

**`--!native` terminology:**
- Guide says "JIT compilation" but Roblox's `--!native` is native code generation, not JIT

**Missing Roblox-specific guidance:**
- No guidance on `enableNonceManager` for concurrent server requests (nonce conflicts are a real risk)
- No paymaster integration patterns for gasless player transactions
- No Account deployment/onboarding patterns for player wallet setup
- No guidance on what happens when HttpService is disabled (error behavior)
- No guidance on `flushCache()` usage (when to force fresh reads)

### docs/guides/api-reference.md

**8 entire modules missing from the API reference (publicly exported but undocumented):**
- `src/wallet/AccountType.luau` -- OZ, Argent callable tables, custom()
- `src/wallet/AccountFactory.luau` -- new(), createAccount(), batchCreate(), batchDeploy()
- `src/wallet/OutsideExecution.luau` -- SNIP-9 V1/V2/V3 meta-transactions
- `src/paymaster/PaymasterRpc.luau` -- SNIP-29 JSON-RPC client
- `src/paymaster/AvnuPaymaster.luau` -- AVNU paymaster helpers
- `src/paymaster/PaymasterPolicy.luau` -- policy engine for sponsorship
- `src/paymaster/PaymasterBudget.luau` -- per-player budget tracking
- `src/paymaster/SponsoredExecutor.luau` -- sponsored execution orchestrator
- `src/provider/RpcTypes.luau` -- no dedicated section (~25 export types)

**TypedData section is severely inaccurate:**
- `TypedData.hash(typedData)` -- wrong name, actual is `TypedData.getMessageHash(typedData, accountAddress)` (requires accountAddress parameter)
- `TypedData.hashLegacy(typedData)` -- does not exist in code
- `TypedData.hashActive(typedData)` -- does not exist in code
- `TypedData.encodeValue(value, type, types)` -- does not exist in code
- `TypedData.encodeType(primaryType, types)` -- parameter order is reversed; actual is `encodeType(types, typeName, revision?)`

**TransactionHash section has wrong identifiers:**
- Function name: says `computeInvokeV3Hash`, actual is `calculateInvokeTransactionHash`
- Parameter: says `calldata`, actual is `compiledCalldata`
- Missing `version: string?` parameter
- `l1DataGas` shown as optional but is required in code
- Missing functions: `calculateDeployAccountTransactionHash`, `encodeResourceBound`, `hashFeeField`, `hashDAMode`
- Missing constants: `TransactionHash.SN_MAIN`, `TransactionHash.SN_SEPOLIA`

**Documented functions/methods that do not exist:**
- `Contract:attach(newAddress)` -- no such method
- `account:waitForTransaction(...)` -- actual method is `waitForReceipt`
- `account.provider` (public property) -- actual is `_provider` (private)
- `FetchOptions.priority: string?` field -- does not exist in RpcTypes.FetchOptions

**Account section missing 9+ methods:**
- `getDeploymentFeeEstimate`, `checkDeploymentBalance`, `getDeploymentFundingInfo` (static)
- `deployAccount`, `estimateDeployAccountFee`, `getDeploymentData` (instance)
- `deployWithPaymaster`, `estimatePaymasterFee`, `executePaymaster` (paymaster integration)

**Account.new config missing fields:**
- `accountType: string?`, `classHash: string?`, `constructorCalldata: { string }?` not shown

**Contract section missing 7 methods:**
- `getFunctions`, `getFunction`, `hasFunction`, `parseEvents`, `queryEvents`, `getEvents`, `hasEvent`
- `call()` missing `blockId?` third parameter

**CallData section missing 4 functions:**
- `encodeShortString`, `encodeStruct`, `numberToHex`, `concat`
- `encodeFelt` signature wrong: says `string | number`, actual is string-only

**TransactionBuilder missing 2 methods:**
- `estimateDeployAccountFee(account, params)`
- `deployAccount(account, params, options)`

**AbiCodec missing 7 functions:**
- `encodeByteArray`, `decodeByteArray`, `encodeEnum`, `decodeEnum`, `encodeInputs`, `decodeOutputs`, `decodeEvent`
- Note: AbiCodec is NOT exported through the barrel init.luau (intentionally internal), yet the API reference documents it -- contradictory

**ErrorCodes missing 18 codes:**
- Transaction: `INSUFFICIENT_BALANCE` (5002), `BATCH_DEPLOY_ERROR` (5003)
- Outside Execution (6000s): entire category missing (6000-6004, 5 codes)
- Paymaster (7000s): entire category missing (7000-7020, 16 codes)

**Constants missing:** `ANY_CALLER`

**ERC20/ERC721 missing:** `getAbi()` static methods

**RequestQueue missing 6 methods:** `dequeue`, `peekPriority`, `recordCompleted`, `recordFailed`, `recordBatched`, `recordBatchSent`

**NonceManager missing 5 methods:** `reset`, `getPendingCount`, `isInitialized`, `isDirty`, `peekNextNonce`

**Cross-guide contradiction:** API reference documents `contract.AbiCodec` as publicly accessible, but `src/contract/init.luau` does NOT export AbiCodec (only Contract, ERC20, ERC721). AbiCodec is intentionally internal per its source file comment.

---

Re-review after refactor prompt:

Can you do a deep review of all documentation files (docs/SPEC.md, docs/ROADMAP.md, docs/CHANGELOG.md, and every file in docs/guides/), cross-referenced against the actual codebase, and fill out the docs/refactor/11-docs.md doc based on your deep review.

For SPEC.md: Does it accurately describe the current implementation? Are there modules, types, or behaviors documented in the spec that don't match the code (or vice versa)? Are there implemented features not covered by the spec? Are code examples correct and runnable? Do any constants, function signatures, or type definitions in the spec contradict what's actually in src/?

For ROADMAP.md: Is the completion status accurate? Are items marked "done" that aren't actually implemented, or items marked "todo" that are already complete? Are there phases or tasks that are stale, duplicated, or no longer relevant given the current codebase? Does the roadmap reflect the actual module structure?

For CHANGELOG.md: Does it cover all implemented phases? Are test counts accurate against the current test suite? Are there modules or features that shipped but aren't mentioned?

For each guide in docs/guides/ (getting-started, crypto, accounts, contracts, patterns, roblox, api-reference): Are code examples correct against the current API? Do import paths and function signatures match the actual source? Are there modules, methods, or features that exist in the code but aren't documented? Are there documented APIs that don't exist or have changed? Is the api-reference.md complete — does every public module and every exported function/type appear? Are there contradictions between guides (e.g., one guide shows one pattern, another guide shows a different pattern for the same thing)?

Also check for: documentation that references the AbiCodec public/private contradiction found in the 09-root review, any docs that reference constants or values that are now flagged as duplicated in the codebase, stale references to old module names or removed features, and whether the documentation is appropriate for the target audience (Roblox game developers, not blockchain engineers).

