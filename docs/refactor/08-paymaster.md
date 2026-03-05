## 8. paymaster/

### PaymasterRpc.luau
_661 lines. Generic SNIP-29 paymaster JSON-RPC client. Handles HTTP requests, rate limiting, retry logic, error mapping, and Promise-based async for any SNIP-29-compliant paymaster service._

- `[ok]` SNIP-29 error code mapping (lines 152-164) is comprehensive — maps all 8 known paymaster RPC codes (150-163) to SDK error codes, with fallback to generic `PAYMASTER_ERROR`.
- `[ok]` Retry logic (lines 375-412) correctly classifies 8 deterministic paymaster error codes as non-retryable. Only transient errors (network, rate limit, unavailable) are retried.
- `[ok]` `isAvailable()` (lines 440-453) resolves `false` on network failure instead of rejecting — correct for a health check.
- `[ok]` Response normalization handles both snake_case (SNIP-29 spec) and camelCase (SDK convention) — defensive against paymaster implementations.
- `[ok]` Dependency injection (`_httpRequest`, `_sleep`, `_clock`) matches RpcProvider pattern — consistent testability.

- `[refactor]` **CRITICAL — 200+ lines duplicated verbatim from `provider/RpcProvider.luau`.** This is the largest DRY violation in the paymaster module. Already catalogued in [provider/ section](./04-provider.md) and [cross-cutting](./14-cross-cutting.md). Full inventory:

  | Component | PaymasterRpc Lines | RpcProvider Lines | Similarity |
  |-----------|-------------------|-------------------|------------|
  | `Promise<T>` type | 15-19 | 15-19 | 100% |
  | `HttpRequest` / `HttpResponse` | 21-33 | RpcTypes:83-96 | 100% |
  | `RateLimiter` type | 170-175 | 70-75 | 100% |
  | `createRateLimiter()` | 177-184 | 77-84 | 100% |
  | `tryAcquire()` | 186-198 | 86-98 | 100% |
  | `_getPromise()` | 254-264 | 196-206 | 98% |
  | `_doHttpRequest()` | 266-272 | 209-216 | 100% |
  | `_jsonEncode()` | 274-281 | 219-227 | 100% |
  | `_jsonDecode()` | 283-290 | 230-237 | 100% |
  | `_rawRequest()` | 307-371 | 240-306 | 95% |
  | `_requestWithRetry()` | 375-412 | 309-334 | 90% |

  **Fix:** Extract shared `JsonRpcClient` base module (see provider/ Priority Action #1).

- `[refactor]` **DeploymentData camelCase→snake_case formatting duplicated between `buildTypedData()` (lines 510-528) and `executeTransaction()` (lines 604-626).** 17 lines of identical struct construction:
  ```luau
  local deployData: any = {
      class_hash = dd.classHash,
      constructor_calldata = dd.calldata,
      salt = dd.salt,
      unique = if dd.unique ~= nil then dd.unique else false,
      version = dd.version or 1,
  }
  if dd.sigdata then deployData.sigdata = dd.sigdata end
  ```
  Extract to a local helper: `formatDeploymentData(dd: DeploymentData): any`.

- `[refactor]` **Transaction structure construction duplicated.** `buildTypedData()` (lines 498-533) and `executeTransaction()` (lines 593-626) both build the `{type, invoke/deploy_and_invoke}` envelope with near-identical logic. The only difference is that `executeTransaction` includes `typed_data` and `signature` fields. Extract a shared `buildTransactionEnvelope(userAddress, calls?, typedData?, signature?, deploymentData?)`.

- `[refactor]` **Response normalization is manual and repetitive.** `getSupportedTokens()` (lines 461-471) normalizes 3 fields, `buildTypedData()` (lines 556-577) normalizes 8+ fields, `executeTransaction()` (lines 641-646) normalizes 2 fields. Each uses the same `raw.snake_case or raw.camelCase` pattern. Consider a generic `normalizeKeys(raw, fieldMap)` helper:
  ```luau
  local function normalizeKeys(raw: any, map: { { from: string, to: string } }): { [string]: any }
      local result = {}
      for _, entry in map do
          result[entry.to] = raw[entry.from] or raw[entry.to]
      end
      return result
  end
  ```

- `[fix]` **`executeTransaction()` hardcodes `fee_mode.mode = "sponsored"` (lines 629-634).** Unlike `buildTypedData()` which correctly determines mode based on `gasTokenAddress`, `executeTransaction` always sends `mode = "sponsored"` regardless of input. The `gasTokenAddress` parameter is not accepted in `executeTransaction`, so there's no way to execute a "default" (gasless) transaction through this path.
  **Impact:** Low — execute is typically called after buildTypedData, and the paymaster already knows the fee mode from the build step. But this is inconsistent with the build path and could confuse consumers examining the RPC payload.
  **Fix:** Either accept `gasTokenAddress` parameter or pass through the `feeMode` from the preceding `buildTypedData` result.

- `[perf]` **`require("@lune/serde")` called dynamically on every `_jsonEncode()`/`_jsonDecode()` invocation (lines 276, 285).** In test mode (when `_httpRequest` is injected), `serde` is re-required on every JSON operation. Should cache at module level or in the constructor.

- `[api]` **`Call` type (lines 49-53) is a duplicate definition of the same concept in `tx/TransactionBuilder` and `contract/Contract`.** There is no shared `Call` type — each module defines its own. Consumers must manually ensure compatibility.

- `[api]` **Rate-limit timeout is hardcoded to 10 seconds (line 309).** Not configurable via `PaymasterConfig`. Games with very low `maxRequestsPerMinute` settings may hit this too quickly. Add `maxRateLimitWait` to config.

---

### AvnuPaymaster.luau
_321 lines. Pre-configured AVNU convenience wrapper. Auto-selects endpoints, provides known token addresses, caches token lists, and manages API key for sponsored mode._

- `[ok]` Clean composition: wraps `PaymasterRpc` via delegation, doesn't inherit or modify internal behavior.
- `[ok]` Token caching with configurable TTL (default 300s) — avoids redundant `getSupportedTokens` calls.
- `[ok]` Known token addresses per network (mainnet: ETH/STRK/USDC/USDT, sepolia: ETH/STRK) — removes the need for game devs to look up addresses.
- `[ok]` `isSponsored()` is a clean check on API key presence — correct for gasfree vs gasless mode detection.
- `[ok]` All static methods (`getEndpoint`, `getEndpoints`, `getTokensForNetwork`) use `table.clone` — prevents mutation of module constants.
- `[ok]` Custom headers (`x-paymaster-api-key`) injected at construction — correct for AVNU's auth model.

- `[refactor]` **`getSupportedTokens()` cache hit accesses private field `innerAny._PromiseModule` (line 254).** To wrap the cached result in a Promise, the method casts `self._inner` to `any` and reads `_PromiseModule` directly. This breaks encapsulation — if PaymasterRpc renames or restructures the field, this breaks silently.
  **Fix:** Add a `wrapInPromise(value)` or `resolveImmediate(value)` method to `PaymasterRpc` that returns `Promise.resolve(value)`. Or expose `_getPromise()` as a public method.

- `[refactor]` **Known token addresses (ETH, STRK) overlap with `constants.luau:STRK_TOKEN_ADDRESS` and are hardcoded in AvnuPaymaster.** If token addresses change (unlikely but possible on testnets), they must be updated in multiple places. Consider importing from `constants.luau` for ETH/STRK and only keeping AVNU-specific tokens (USDC, USDT) here.

- `[refactor]` **Method selector normalization not applied to `entrypoint` in `allowedMethods`.** AvnuPaymaster delegates `buildTypedData` to PaymasterRpc which converts `call.entrypoint` to `entry_point`. But if a Policy checks `allowedMethods` with the raw entrypoint name and the paymaster returns a selector hash, validation may fail. This is a cross-module gap — see PaymasterPolicy section.

- `[type]` **All delegated methods return `: any` instead of typed Promises.** Lines 241, 247, 269-276, 279-286, etc. all return `any`. The exported `AvnuPaymaster` type (lines 87-117) correctly specifies return types, but the implementation bodies lose type information. Known Luau limitation with setmetatable pattern.

- `[api]` **No way to update API key after construction.** If a game needs to rotate API keys (e.g., on expiry), the entire AvnuPaymaster must be reconstructed. Minor — acceptable for v1.

---

### PaymasterPolicy.luau
_347 lines. Pure validation module for paymaster usage rules. Defines allowed contracts, methods, players, fee limits, and rate limits. No persistence — in-memory tracking only._

- `[ok]` Clean pure validation — no side effects beyond rate-limit timestamp recording.
- `[ok]` Hex normalization (lines 36-46) is correct: lowercase, strip `0x` prefix, strip leading zeros, re-add `0x`.
- `[ok]` Call field aliases (`contractAddress`/`to`, `entrypoint`/`selector` at lines 200, 219) handle both SDK-style and Starknet RPC-style call objects.
- `[ok]` Rate limit configuration validation (lines 144-158) enforces that `timeWindow` is required when `maxTxPerPlayer` is set — prevents misconfiguration.
- `[ok]` `validate()` and `recordUsage()` are separate — game devs can validate without recording, and only record after successful execution.

- `[refactor]` **`normalizeHex()` (lines 36-46) is the third implementation in the SDK.** `tx/CallData.luau:36-38` uses BigInt roundtrip (`BigInt.toHex(BigInt.fromHex(hex))`), `wallet/OutsideExecution.luau:134-136` uses the same BigInt roundtrip, and this module uses manual string manipulation. These can produce different results for edge cases (e.g., the string version strips all leading zeros; the BigInt version may preserve internal representation quirks). See [cross-cutting](./14-cross-cutting.md) for consolidation plan.

- `[refactor]` **Rate-limit timestamps grow unboundedly (line 310).** `recordUsage()` appends timestamps to `record.timestamps` but never cleans up expired entries. Over time, a player with high activity accumulates thousands of timestamps that are iterated on every `validate()` and `getUsageCount()` call (lines 240-244, 339-343).
  **Fix:** Prune expired timestamps during `recordUsage()` or `validate()`:
  ```luau
  -- In recordUsage, after inserting:
  local pruned = {}
  local cutoff = now - self._timeWindow
  for _, ts in record.timestamps do
      if ts > cutoff then table.insert(pruned, ts) end
  end
  record.timestamps = pruned
  ```

- `[refactor]` **Player whitelist check duplicated between `validate()` (line 185-192) and `validateFee()` (lines 267-273).** If both are called for the same transaction (as SponsoredExecutor would do), the player whitelist is checked twice. Not a bug, but wasteful. Consider a `validateAll(playerId, calls, feeAmount)` method that runs both in one pass.

- `[type]` **`calls` parameter typed as `{ any }` (line 183).** Should reference `PaymasterRpc.Call` or a shared `Call` type for type safety. Currently accepts any table shape.

- `[type]` **Constructor return type not exported.** `PaymasterPolicy.new()` returns the result of `setmetatable(...)` which Luau infers as the internal metatable type. Consumers get `any`. Should export a `PaymasterPolicy` type similar to how `PaymasterRpc` exports `PaymasterRpc` type (lines 126-146).

- `[api]` **Method selector matching uses raw string comparison (line 224).** If `allowedMethods` entries use function name strings (e.g., `"transfer"`) but the paymaster returns selector hashes (e.g., `"0x83afd3f4..."`), validation will incorrectly reject. Document that selectors must be in the same format as the calls passed to `validate()`.

---

### PaymasterBudget.luau
_500 lines. Per-player virtual "paymaster tokens" for sponsored transaction budgets. In-memory cache with periodic DataStore flush for persistence. Tokens are game-managed, NOT on-chain._

- `[ok]` Lazy flush design (lines 210-226) avoids excessive DataStore writes — flushes on dirty count threshold or time interval.
- `[ok]` NaN checking on `grantTokens()`/`revokeTokens()` (lines 265, 285) — defensive against corrupted input.
- `[ok]` `revokeTokens()` clamps to zero (line 296) — prevents negative balances.
- `[ok]` DataStore error handling is resilient — logs errors but uses default data (lines 184-191).
- `[ok]` `unloadPlayer()` (lines 466-473) flushes before evicting — prevents data loss on player leave.
- `[ok]` `isValidPlayerData()` (lines 68-74) validates DataStore data shape — prevents crashes on corrupted persistence.

- `[refactor]` **`PlayerData` and `UsageStats` are identical types (lines 32-37 vs 39-44).** Four fields with the same names and types. Remove `UsageStats` and alias it:
  ```luau
  export type UsageStats = PlayerData
  ```
  Or keep `UsageStats` and delete `PlayerData`, using the public-facing name everywhere.

- `[refactor]` **`consumeTransaction()` uses `StarknetError.new()` (line 341) instead of a dedicated subtype.** Error code is `INSUFFICIENT_BUDGET` (7012) which falls in the paymaster range. Should use a hypothetical `StarknetError.paymaster()` factory (see [cross-cutting](./14-cross-cutting.md) for missing PaymasterError subtype). Same issue in SponsoredExecutor lines 298, 327, 477.

- `[refactor]` **`clonePlayerData()` (lines 59-66) manually copies 4 fields.** Luau provides `table.clone()` which handles this in one call. The manual clone is fragile — if a field is added to `PlayerData`, this function must be updated separately.
  **Fix:** `local function clonePlayerData(data: PlayerData): PlayerData return table.clone(data) end` — or inline `table.clone(data)` at all 3 call sites (lines 180, 241, 445).

- `[refactor]` **DataStore loading logic duplicated between `_getPlayerData()` (lines 166-198) and `loadPlayer()` (lines 436-461).** Both:
  1. Build key as `"player_" .. tostring(playerId)`
  2. `pcall(DataStore:GetAsync(key))`
  3. Validate with `isValidPlayerData(result)`
  4. Clone and cache, or fall back to default
  5. Log errors to `_flushErrors`
  ~15 lines of identical logic. `loadPlayer()` could delegate to a shared `_loadFromDataStore(playerId)` helper that `_getPlayerData()` also uses.

- `[refactor]` **`flushPlayer()` (lines 422-431) recounts all dirty entries via table iteration.** After removing one entry from `_dirty`, it loops the entire table to recompute `_dirtyCount`. Should simply decrement:
  ```luau
  function BudgetProto:flushPlayer(playerId: number): ()
      self:_flushPlayer(playerId)
      if self._dirty[playerId] then
          self._dirty[playerId] = nil
          self._dirtyCount = math.max(0, self._dirtyCount - 1)
      end
  end
  ```
  Note: `unloadPlayer()` (line 470) already does this correctly — inconsistency.

- `[refactor]` **Config validation (lines 90-136) has 6 nearly identical blocks.** Each validates: `type ~= "number"` → error, `< 0` → error. Extract a helper:
  ```luau
  local function validateNonNeg(name: string, value: any)
      if value ~= nil then
          if type(value) ~= "number" then error(...) end
          if value < 0 then error(...) end
      end
  end
  ```

- `[api]` **No `destroy()` or lifecycle method.** Budget instances accumulate data indefinitely. In a long-running game server, this could grow unbounded. Consider adding `destroy()` that flushes all dirty data and clears the cache, or document expected lifecycle (create on server start, flush on shutdown).

---

### SponsoredExecutor.luau
_489 lines. End-to-end sponsored transaction orchestrator. Chains: Policy check → Budget check → Paymaster build+sign+execute (with retry) → Budget deduct/refund. Event callbacks, retry logic, and detailed metrics._

- `[ok]` Clean orchestration flow — policy, budget, execution, and metrics are well-separated responsibilities.
- `[ok]` Budget refund on failure is correct and consistent (lines 417-420 for confirmation failure, lines 457-462 for all-attempts failure).
- `[ok]` Retry with exponential backoff (lines 362-367) is correct: `delay * 2^(attempt-2)`.
- `[ok]` Policy usage is only recorded after successful execution (lines 404-406, 435-437) — prevents rate-limit poisoning from failed transactions.
- `[ok]` Constructor validation is thorough — required fields, feeMode validation, gasToken requirement for "default" mode.

- `[fix]` **Line 289: `account._provider:_getPromise()` — double encapsulation breach.** Accesses private `_provider` field on account, then calls private `_getPromise()` method on the provider. If either is renamed or restructured, SponsoredExecutor breaks silently.
  **Fix:** Accept the Promise module at construction time in `SponsoredExecutorConfig`:
  ```luau
  -- SponsoredExecutorConfig
  _Promise: any?, -- Promise module (injected for testing, auto-detected in Roblox)
  ```
  Or have Account expose a `getProvider()` method and provider expose `getPromise()`.

- `[fix]` **Lines 393, 397: `account._provider` accessed directly for `waitForTransaction()`.** Same issue as above — reaches into account internals to get the provider for confirmation wait.
  **Fix:** Use `account._provider` via a public accessor or accept a `provider` in config.

- `[refactor]` **`isTransientError()` (lines 107-130) partially overlaps with PaymasterRpc's non-retry check (lines 388-401).** Both classify paymaster errors as transient vs deterministic, but from opposite perspectives. PaymasterRpc lists 8 codes to NOT retry; SponsoredExecutor lists 4 codes that ARE transient. These are the same classification expressed inversely, but they could diverge if new error codes are added.
  **Fix:** Centralize error classification. Add `isTransient(code: number): boolean` to the error system:
  ```luau
  -- src/errors/ErrorCodes.luau
  ErrorCodes.isTransient = function(code: number): boolean
      return code == ErrorCodes.NETWORK_ERROR.code
          or code == ErrorCodes.PAYMASTER_UNAVAILABLE.code
          or code == ErrorCodes.RATE_LIMIT.code
  end
  ```

- `[refactor]` **`safeCall()` (lines 133-140) swallows callback errors with `warn()`.** Game devs using callbacks for critical logging/analytics won't know their callback is failing unless they check Roblox's output console. No way to opt into strict callback error handling.
  **Fix:** Add optional `onCallbackError` to `ExecutorCallbacks`:
  ```luau
  onCallbackError: ((callbackName: string, error: any) -> ())?,
  ```
  This preserves backward compatibility (defaults to `warn`) but allows strict handling.

- `[refactor]` **Metrics `byContract` and `byMethod` grow unboundedly (lines 159-163).** Every unique contract address and `address:method` pair gets an entry. In a game with many contracts or dynamic addresses, these tables can grow without limit.
  **Fix:** Cap at a configurable limit (e.g., 100) and evict oldest entries, or use `resetMetrics()` periodically.

- `[type]` **Config fields `account`, `paymaster`, `policy`, `budget` are all typed as `any` (lines 70-74).** This defeats type checking entirely — consumers can pass invalid objects and only discover errors at runtime.
  **Fix:** Reference exported types:
  ```luau
  account: Account.Account,  -- from wallet/Account
  paymaster: PaymasterRpc.PaymasterRpc,
  policy: PaymasterPolicy?,
  budget: PaymasterBudget?,
  ```
  This may require forward-declaring types to avoid circular dependencies.

- `[api]` **No getter for inner components.** Consumers can't inspect the account, paymaster, policy, or budget after construction. For debugging and monitoring, add read-only accessors:
  ```luau
  function ExecutorProto:getPolicy(): any? return self._policy end
  function ExecutorProto:getBudget(): any? return self._budget end
  ```

- `[api]` **No way to update feeMode after construction.** If a game wants to switch between sponsored and default mode dynamically (e.g., based on player status), it must reconstruct the executor. Minor — acceptable for v1.

---

### paymaster/init.luau (barrel)
_17 lines. Re-exports all 5 sub-modules._

- `[ok]` Clean barrel, no logic.
- `[ok]` Uses Roblox-style `require(script.Module)` — correct for runtime barrel.
- `[ok]` Flat export structure — all 5 modules are directly accessible.

---

### Account.luau paymaster integration (wallet/)
_~360 lines across 4 methods: `getDeploymentData`, `deployWithPaymaster`, `estimatePaymasterFee`, `executePaymaster`._

- `[ok]` Idempotency check in `deployWithPaymaster()` (lines 826-837) — correctly detects already-deployed accounts via `getNonce()`.
- `[ok]` Security validation in `executePaymaster()` (lines 1063-1084) — verifies returned calls match submitted calls to prevent paymaster tampering.
- `[ok]` Clean separation: `estimatePaymasterFee` for fee estimates, `executePaymaster` for execution, `deployWithPaymaster` for deploy-via-paymaster.

- `[refactor]` **`paymasterDetails` validation duplicated 3× (~30 lines each).** `estimatePaymasterFee` (lines 925-966), `executePaymaster` (lines 987-1036), and `deployWithPaymaster` (lines 771-805) all independently validate:
  1. `paymasterDetails.paymaster` is present
  2. `paymasterDetails.feeMode` is present
  3. `feeMode.mode` is "sponsored" or "default"
  4. `gasToken` is present for "default" mode

  Extract to a shared helper:
  ```luau
  local function validatePaymasterDetails(details: { [string]: any }, methodName: string): (any, FeeMode, string)
      -- Returns (paymaster, feeMode, gasTokenAddress) or throws
  end
  ```
  This also consolidates the gas token address resolution logic (sponsored→"0x0", default→gasToken).

- `[refactor]` **Call validation logic duplicated between `executePaymaster` (lines 1044-1084) and `deployWithPaymaster` (lines 853-880).** ~20 lines of identical code: convert to outside calls → extract returned calls → normalize keys → validate. Extract to a helper:
  ```luau
  local function validateReturnedCalls(submittedCalls, typedData, methodName): boolean
  ```

- `[refactor]` **Uses `StarknetError.new(..., "PaymasterError")` (lines 873, 1077).** Passes `"PaymasterError"` as context string to `StarknetError.new()` — this doesn't create a proper PaymasterError subtype. Related to missing `StarknetError.paymaster()` factory noted in [cross-cutting](./14-cross-cutting.md).

- `[refactor]` **`provider:_getPromise()` called in `deployWithPaymaster` (line 823) and `executePaymaster` (line 1050).** Private method access. See [cross-cutting](./14-cross-cutting.md) for the `_getPromise` discussion.

- `[api]` **No shared `PaymasterDetails` type.** Each method accepts `paymasterDetails: { [string]: any }` — a raw dictionary. Consumers have no type guidance on what fields to provide. Define and export:
  ```luau
  export type PaymasterDetails = {
      paymaster: PaymasterRpc.PaymasterRpc,
      feeMode: { mode: "sponsored" | "default", gasToken: string? },
      deploymentData: PaymasterRpc.DeploymentData?,
  }
  ```

---

### paymaster/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 2,338 (661 + 321 + 347 + 500 + 489 + 17 + 3 Account methods ~360) |
| **Total public methods** | 31 (PaymasterRpc: 7, AvnuPaymaster: 14, Policy: 5, Budget: 14, Executor: 3) |
| **Total tests** | 434 (PaymasterRpc: 87, AvnuPaymaster: 67, Policy: 68, Budget: 110, Executor: 82, Account paymaster: ~20) |
| **Code duplicated from provider/** | ~200 lines (rate limiter, HTTP/JSON helpers, raw request, retry logic, Promise type, HTTP types) |
| **DRY violations within paymaster/** | 5 (DeploymentData formatting, transaction envelope, response normalization, config validation blocks, DataStore loading) |
| **DRY violations cross-module** | 7 (JsonRpcClient infra, normalizeHex, Promise type, HTTP types, Call type, paymasterDetails validation, call validation) |
| **`StarknetError.new()` misuses** | 4 (Budget:341, Executor:298, 327, 477 — should use dedicated subtype) |
| **Private method violations** | 3 (Executor→`account._provider:_getPromise()`, Executor→`account._provider.waitForTransaction`, AvnuPaymaster→`inner._PromiseModule`) |
| **Types using `any`** | 6 (SponsoredExecutorConfig: account, paymaster, policy, budget; Policy calls param; Account paymasterDetails) |

---

### Priority Actions (paymaster/)

1. **HIGH — Extract `JsonRpcClient` base module.** Eliminates ~200 lines of duplication between `PaymasterRpc` and `RpcProvider`. This is the single highest-impact refactor for the paymaster module. See [provider/ Priority Action #1](./04-provider.md) for the extraction plan.

2. **HIGH — Fix SponsoredExecutor private access chain.** Line 289 `account._provider:_getPromise()` is a double encapsulation breach. Either:
   - (a) Accept a `_Promise` module in `SponsoredExecutorConfig` for testing, auto-detect in Roblox
   - (b) Have Account expose `getProvider()` and provider expose `getPromise()`
   - Same fix addresses line 393 (`account._provider.waitForTransaction`)

3. **HIGH — Extract `validatePaymasterDetails()` helper in Account.luau.** ~90 lines of duplicated validation across 3 methods. Extract to a single function that returns `(paymaster, feeMode, gasTokenAddress)` or throws. Also extracts gas token address resolution.

4. **HIGH — Add `PaymasterError` subtype to error system.** 15 error codes in the 7000 range (ErrorCodes.luau:56-71) and 4 `StarknetError.new()` calls in paymaster modules have no dedicated factory. Add `StarknetError.paymaster(message, code, context?)` alongside the existing `rpc()`, `signing()`, `validation()`, `transaction()` factories.

5. **MEDIUM — Extract DeploymentData formatter in PaymasterRpc.** `buildTypedData()` and `executeTransaction()` both format the same `DeploymentData → snake_case` struct (17 lines each). Extract `formatDeploymentData(dd)` helper.

6. **MEDIUM — Extract call validation helper in Account.luau.** `executePaymaster()` and `deployWithPaymaster()` share ~20 lines of identical call normalization and validation logic.

7. **MEDIUM — Fix AvnuPaymaster private field access.** `getSupportedTokens()` cache hit path (line 254) accesses `inner._PromiseModule`. Add a `resolveImmediate(value)` method to PaymasterRpc instead.

8. **MEDIUM — Add timestamp pruning to PaymasterPolicy.** Rate-limit timestamps grow unboundedly. Prune expired timestamps in `recordUsage()` after insertion.

9. **MEDIUM — Consolidate `PlayerData`/`UsageStats` types.** Remove one and alias the other — they are byte-for-byte identical.

10. **MEDIUM — Deduplicate DataStore loading in PaymasterBudget.** `_getPlayerData()` and `loadPlayer()` share ~15 lines of identical DataStore loading logic. Extract to `_loadFromDataStore(playerId)`.

11. **MEDIUM — Centralize transient error classification.** `SponsoredExecutor.isTransientError()` and `PaymasterRpc._requestWithRetry()` both classify paymaster errors as transient vs deterministic from opposite perspectives. Add `ErrorCodes.isTransient(code)` as the single source of truth.

12. **LOW — Replace `clonePlayerData()` with `table.clone()`.** Luau provides `table.clone()` natively. Remove the manual 4-field copy helper.

13. **LOW — Fix `flushPlayer()` dirty count recomputation.** Line 427-430 iterates all dirty entries to recount after removing one. Should simply decrement (as `unloadPlayer()` already does on line 470).

14. **LOW — Define shared `Call` type.** `PaymasterRpc.Call`, `TransactionBuilder` calls, and `Contract.populate()` all use the same `{contractAddress, entrypoint, calldata}` shape but define it independently. Centralize in a shared types module.

15. **LOW — Define shared `PaymasterDetails` type.** Account methods accept `paymasterDetails: { [string]: any }`. Export a proper typed definition for IDE support and validation.

16. **LOW — Add config validation helper to PaymasterBudget.** 6 nearly identical `if cfg.X ~= nil then validate(X)` blocks. Extract `validateNonNeg(name, value)`.

---

### Architectural Flow

```
                    ┌──────────────────────────────────────────┐
                    │            Game Server                    │
                    │                                          │
                    │  ┌─── SponsoredExecutor ───────────────┐ │
                    │  │  1. Policy check (PaymasterPolicy)  │ │
                    │  │  2. Budget check (PaymasterBudget)  │ │
                    │  │  3. Execute with retry               │ │
                    │  │     ↓                                │ │
                    │  │  Account:executePaymaster()          │ │
                    │  │     ↓                                │ │
                    │  │  PaymasterRpc (or AvnuPaymaster)     │ │
                    │  │     • buildTypedData (SNIP-29)       │ │
                    │  │     • sign (Account.signMessage)     │ │
                    │  │     • executeTransaction (SNIP-29)   │ │
                    │  │  4. Budget deduct / refund           │ │
                    │  │  5. Callbacks + Metrics              │ │
                    │  └──────────────────────────────────────┘ │
                    └──────────────────────────────────────────┘
                                       │
                                       ▼
                          ┌─── Paymaster Service ───┐
                          │  AVNU / Cartridge / etc  │
                          │  SNIP-29 JSON-RPC        │
                          └──────────────────────────┘
                                       │
                                       ▼
                          ┌─── Starknet Network ────┐
                          │  Outside Execution (V2)  │
                          │  Account validates sig   │
                          └──────────────────────────┘
```

**Dependency graph (paymaster/ internal):**
```
AvnuPaymaster ──→ PaymasterRpc ──→ errors/StarknetError
                                 ──→ errors/ErrorCodes

PaymasterPolicy ──→ crypto/BigInt
                 ──→ errors/StarknetError
                 ──→ errors/ErrorCodes

PaymasterBudget ──→ errors/StarknetError
                ──→ errors/ErrorCodes

SponsoredExecutor ──→ errors/StarknetError
                  ──→ errors/ErrorCodes
                  ──→ (Account via config.account)
                  ──→ (PaymasterRpc via config.paymaster)
                  ──→ (PaymasterPolicy via config.policy)
                  ──→ (PaymasterBudget via config.budget)
```

**Note:** SponsoredExecutor depends on Account and PaymasterRpc only through config injection (`any` typed), not import-time dependencies. This keeps the module loosely coupled but loses type safety.
