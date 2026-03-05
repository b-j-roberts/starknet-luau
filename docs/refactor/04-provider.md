## 4. provider/

### RpcTypes.luau
_385 lines. Type definitions for Starknet JSON-RPC request/response objects._

- `[ok]` Clean separation of types from implementation. All 30+ type exports are well-documented with field-level comments.
- `[ok]` Configuration types (`RpcProviderConfig`, `RequestQueueConfig`, `CacheConfig`, `NonceManagerConfig`) use optional fields with sensible defaults documented in comments.
- `[ok]` JSON-RPC 2.0 envelope types (`JsonRpcRequest`, `JsonRpcResponse`, `JsonRpcError`) are correctly modeled.
- `[ok]` HTTP abstraction types (`HttpRequest`, `HttpResponse`) mirror Roblox `HttpService:RequestAsync` interface, enabling clean test injection.
- `[ok]` All V3 transaction types (`InvokeTransactionV3`, `DeployAccountTransactionV3`) use snake_case field names matching the Starknet RPC spec.

- `[refactor]` **`Promise<T>` type defined in RpcProvider.luau:15-19 AND PaymasterRpc.luau:15-19.** Identical 5-line type definition duplicated between two files. Should be defined once in RpcTypes.luau (or a shared types module) and imported by both.

- `[refactor]` **`HttpRequest` / `HttpResponse` types duplicated in PaymasterRpc.luau:21-33.** PaymasterRpc defines its own identical `HttpRequest` and `HttpResponse` types (lines 21-33) that are byte-for-byte copies of RpcTypes.luau:83-96. PaymasterRpc should import from RpcTypes instead.

- `[refactor]` **`StarknetError` type (lines 122-128) re-defines what's already in `errors/StarknetError.luau`.** This is a forward-declaration for type annotation purposes, but it creates a maintenance risk — if the real StarknetError interface changes, this shadow type won't track it. Consider using the actual module's type export or removing this declaration if Luau doesn't require it here.

- `[api]` **`RpcTypes.ErrorTypes` (lines 376-382) is dead code.** Defines 5 error type string constants (`RPC_ERROR`, `NETWORK_ERROR`, etc.) that are never referenced anywhere in `src/` or `tests/`. The actual error handling uses `ErrorCodes` from `errors/ErrorCodes.luau`. Remove to reduce confusion.

- `[type]` **`EventPollerConfig.provider` is typed as `any` (line 365).** Should reference `RpcProvider` type from RpcProvider.luau to enable IDE autocomplete and type-checking for EventPoller consumers.

- `[type]` **`BlockId` type (lines 138-142) has optional fields but `formatBlockId()` helper in RpcProvider.luau:105-119 accepts `string?`.** The type and the helper don't agree on the representation. `formatBlockId()` interprets raw strings ("latest", "pending", "0x...") while `BlockId` is a structured object with `block_hash`, `block_number`, `block_tag` fields. These are two different representations of the same concept — the Starknet RPC spec uses the structured form, but our API accepts the string shorthand. Document this explicitly.

---

### RpcProvider.luau
_1104 lines. Core JSON-RPC client with rate limiting, retry, queue, cache, nonce, and event features._

- `[ok]` Dependency injection for all I/O: `_httpRequest`, `_sleep`, `_clock`, `_defer` — enables comprehensive test coverage without network.
- `[ok]` Token bucket rate limiter (lines 77-98) is correct: refills proportional to elapsed time, atomic decrement.
- `[ok]` Selective retry in `_requestWithRetry()` (lines 309-334): deterministic `RPC_ERROR` failures are NOT retried, only transient `NETWORK_ERROR` and `RATE_LIMIT` get exponential backoff.
- `[ok]` 3-layer dispatch (cache → queue → direct) in `fetch()` is clean and transparent to callers.
- `[ok]` Block-based cache invalidation in `getBlockNumber()` (lines 738-753) correctly preserves immutable caches (chainId, classHash, specVersion) while invalidating state-dependent caches (storage, call, block).
- `[ok]` `waitForTransaction()` (lines 1036-1101) correctly handles all terminal states: ACCEPTED_ON_L2/L1 → resolve with receipt, REVERTED → reject with revert_reason, REJECTED → reject with status.
- `[ok]` Batch dispatch (lines 492-633) correctly distributes responses by JSON-RPC `id`, handles partial failures, and rate-limits the batch as a single request.
- `[ok]` `getMetrics()` (lines 648-715) aggregates metrics from all sub-modules (queue, cache, nonce) into a single snapshot.

- `[refactor]` **CRITICAL — Rate limiter code duplicated verbatim in PaymasterRpc.luau.** `createRateLimiter()` (lines 77-84) and `tryAcquire()` (lines 86-98) are byte-for-byte identical to PaymasterRpc.luau:177-198. Extract to a shared `src/provider/RateLimiter.luau`:
  ```luau
  -- src/provider/RateLimiter.luau
  export type RateLimiter = {
      tokens: number,
      maxTokens: number,
      refillRate: number,
      lastRefill: number,
  }
  local RateLimiter = {}
  function RateLimiter.create(maxPerMinute: number, clockFn: () -> number): RateLimiter ...
  function RateLimiter.tryAcquire(limiter: RateLimiter, clockFn: () -> number): boolean ...
  return RateLimiter
  ```

- `[refactor]` **CRITICAL — `_doHttpRequest()`, `_jsonEncode()`, `_jsonDecode()` duplicated verbatim in PaymasterRpc.luau.** Lines 209-237 in RpcProvider are identical to PaymasterRpc:266-290. All three methods use the same pattern: `if self._httpRequest then (use injected/Lune) else (use Roblox HttpService)`. Extract to a shared `src/provider/JsonRpcClient.luau` base module that both RpcProvider and PaymasterRpc can delegate to.

- `[refactor]` **CRITICAL — `_rawRequest()` duplicated with 95% overlap.** RpcProvider:240-306 and PaymasterRpc:307-371 are nearly identical: rate-limit spin wait → build JSON-RPC envelope → HTTP POST → decode response → check error. The only difference is the error mapping on the JSON-RPC error branch (RpcProvider throws `StarknetError.rpc()` directly; PaymasterRpc routes through `mapPaymasterError()` for SNIP-29 code mapping). Extract the shared logic and accept an optional error mapper callback:
  ```luau
  function JsonRpcClient:_rawRequest(method, params, errorMapper?): any
      -- ... shared rate-limit + HTTP + decode ...
      if decoded.error then
          if errorMapper then
              errorMapper(decoded.error.code, decoded.error.message, decoded.error.data)
          else
              error(StarknetError.rpc(decoded.error.message, ErrorCodes.RPC_ERROR.code, ...))
          end
      end
      return decoded.result
  end
  ```

- `[refactor]` **CRITICAL — `_requestWithRetry()` duplicated with 90% overlap.** RpcProvider:309-334 and PaymasterRpc:375-412 share the same retry loop with exponential backoff. The difference is the "don't retry" condition: RpcProvider checks `result.code == ErrorCodes.RPC_ERROR.code`, PaymasterRpc checks 8 individual paymaster error codes. Extract the shared retry loop and accept a `shouldRetry(err) -> boolean` predicate.

- `[refactor]` **`_getPromise()` is private but called from 3 external modules.** `_getPromise()` (lines 196-206) is prefixed with `_` (private convention) but is called by:
  - `NonceManager.luau:78` — `self._provider:_getPromise()`
  - `NonceManager.luau:190` — `self._provider:_getPromise()`
  - `Account.luau:224+` — `config.provider:_getPromise()`
  - `TransactionBuilder.luau` — via provider reference
  This breaks encapsulation. Either:
  (a) Rename to `getPromise()` (make it public API), or
  (b) Pass the Promise module to NonceManager/Account at construction time so they don't reach into provider internals.

- `[refactor]` **`getAllEvents()` pagination duplicates EventPoller pagination.** Lines 982-1032 (`getAllEvents`) and EventPoller:92-125 both implement:
  1. Loop with safety limit (1000 / 100 pages)
  2. Call `_requestWithRetry("starknet_getEvents", {filter})` with continuation token
  3. Collect events, advance token, break on empty token
  The EventPoller version is ~30 lines of identical logic. Extract to a shared helper:
  ```luau
  function RpcProviderClass:_paginateEvents(filter, maxPages): { EmittedEvent }
  ```

- `[refactor]` **Rate-limit spin wait duplicated in `_rawRequest()` and `_dispatchBatch()`.** Lines 241-254 (`_rawRequest`) and lines 496-513 (`_dispatchBatch`) both do:
  ```luau
  local maxWait = 10
  while not tryAcquire(self._rateLimiter, self._clock) do ...
  ```
  Extract to a helper: `self:_acquireRateLimitToken()`.

- `[refactor]` **Header construction duplicated in `_rawRequest()` and `_dispatchBatch()`.** Lines 266-271 and 531-536 both build the same headers table with `Content-Type` + custom headers merge. Extract to `self:_buildHeaders()`.

- `[refactor]` **`getMetrics()` returns two different literal tables (lines 675-715).** The queue-enabled and queue-disabled paths return nearly identical tables with the only difference being queue metrics defaulting to 0. Consolidate to a single return with conditional queue metrics.

- `[api]` **Exported `RpcProvider` type (lines 21-64) is missing `getNonceManager()` (line 636).** The `getNonceManager()` method exists in the implementation but is not in the exported type. Consumers can call it but don't get type checking.

- `[api]` **No public synchronous fetch method.** EventPoller (line 68, 109) and `waitForTransaction` (line 1045) call `self:_requestWithRetry()` directly because they need synchronous results inside `pcall`/loops. But `_requestWithRetry` is private. Add a public `fetchSync(method, params)` that delegates to `_requestWithRetry()`, and update EventPoller/waitForTransaction to use it.

- `[api]` **`addInvokeTransaction()` manually copies all 11 fields from `InvokeTransactionV3` (lines 801-814).** This is fragile — if a new field is added to the type, this method must be manually updated. Same for `addDeployAccountTransaction()` (lines 828-841). Consider passing the object directly:
  ```luau
  return self:fetch("starknet_addInvokeTransaction", { invokeTx })
  ```
  The only reason for the manual copy is that `InvokeTransactionV3` fields might have SDK-internal fields that shouldn't be sent to the RPC. If all fields are RPC-spec-compatible, the copy is unnecessary.

- `[type]` **All public methods return `any` instead of `Promise<T>`.** Every method like `getChainId()`, `getNonce()`, `call()` is declared as `: any` in the implementation (e.g., line 723). The exported type on lines 21-64 correctly declares `Promise<string>` etc., but the implementation bodies lose this information. This is a known Luau limitation with the metatable+setmetatable pattern.

- `[perf]` **Cache key computed via `self:_jsonEncode(params)` on every `fetch()` call (line 349).** JSON serialization for cache key generation has overhead. For high-frequency calls (e.g., `getNonce` in a loop), this could be noticeable. Not critical — the serialization is fast for typical RPC param sizes — but worth noting.

- `[perf]` **`table.remove(queue._high, 1)` in RequestQueue.dequeue() is O(n).** Array shift on every dequeue. For typical queue depths (< 100 items), this is negligible. If queue depth scales significantly, consider a ring buffer.

---

### RequestQueue.luau
_216 lines. 3-bucket priority queue with backpressure and batch classification._

- `[ok]` Clean, minimal implementation. Single responsibility: priority classification + FIFO ordering.
- `[ok]` Backpressure via `maxQueueDepth` with clear `QUEUE_FULL` error (line 118).
- `[ok]` Priority classification is static and correct: `addInvokeTransaction`/`estimateFee` = HIGH, `getEvents` = LOW, everything else = NORMAL.
- `[ok]` Batchable method classification (lines 56-74) correctly includes all read-only methods and excludes mutating methods.
- `[ok]` Metrics tracking is comprehensive and lightweight.
- `[ok]` `getPriority()` and `isBatchable()` are static methods — correct since they don't depend on instance state.

- `[refactor]` **`addDeployAccountTransaction` missing from priority classification.** `METHOD_PRIORITY` (lines 49-54) classifies `addInvokeTransaction` and `estimateFee` as HIGH, but `addDeployAccountTransaction` is not listed. Deploy account submissions are equally latency-sensitive. Should be HIGH priority.

- `[refactor]` **`addDeployAccountTransaction` missing from non-batchable list.** `BATCHABLE_METHODS` (lines 56-74) is a whitelist — unlisted methods default to non-batchable. This is correct behavior, but the intent should be documented: `addDeployAccountTransaction` is implicitly non-batchable by omission. Consider adding an explicit `NON_BATCHABLE` table or a comment listing the expected non-batchable methods for clarity.

- `[type]` **`priority` field in `QueueItem` is typed as `string` (line 16).** Should be `"high" | "normal" | "low"` (a union/literal type) for type safety, matching `RequestPriority` from RpcTypes.luau:8.

- `[test]` 82 tests — comprehensive coverage of enqueue/dequeue ordering, backpressure, metrics, priority classification, and batch classification.

---

### ResponseCache.luau
_311 lines. LRU cache with per-method TTL for JSON-RPC responses._

- `[ok]` Textbook LRU implementation: doubly-linked list + hash map, O(1) get/set/evict.
- `[ok]` TTL is per-method with sensible defaults: immutable data (chainId, classHash) = indefinite, block-sensitive data (storage, call) = 30s.
- `[ok]` Lazy expiration on `get()` — no background cleanup thread needed.
- `[ok]` Uncacheable methods correctly exclude all mutating/non-deterministic operations.
- `[ok]` `invalidateByPrefix()` enables block-based bulk invalidation from RpcProvider.getBlockNumber().
- `[ok]` Config-driven TTL overrides allow fine-tuning per deployment.

- `[refactor]` **`invalidateByPrefix()` is O(n) full-map scan (lines 260-270).** Iterates all cache entries to find prefix matches, then deletes. For typical cache sizes (256 max), this is fine. For larger caches, consider maintaining a reverse index by method name. Not actionable now, but worth noting for future scaling.

- `[refactor]` **`getTTLForMethod()` returns `nil` for unknown methods (line 292).** Any new RPC method not explicitly listed in `METHOD_TTL_CONFIG_KEY` will be uncacheable by default. This is a safe fallback, but it means new methods require explicit addition to the config map. Document this as intentional behavior.

- `[api]` **Constructor `config` parameter is typed as `{ [string]: any }?` (line 90).** Should use the `CacheConfig` type from RpcTypes.luau:24-34 for type safety.

- `[test]` 89 tests — excellent coverage of LRU eviction, TTL expiration, prefix invalidation, per-method TTL, and metrics.

---

### NonceManager.luau
_276 lines. Per-address nonce tracking with parallel reservation and auto-resync._

- `[ok]` Reserve/confirm/reject lifecycle correctly models optimistic nonce management for parallel transactions.
- `[ok]` Backpressure via `maxPendingNonces` prevents runaway transaction queueing.
- `[ok]` Auto-resync on error (dirty flag) recovers gracefully from nonce gaps.
- `[ok]` Hex nonce parsing with decimal fallback (lines 98-102, 152-155, 171-174) is robust.
- `[ok]` `peekNextNonce()` enables inspection without reservation — useful for debugging.
- `[ok]` `reset()` with optional address parameter enables both per-address and global cleanup.

- `[refactor]` **Calls `self._provider:_getPromise()` (private method) twice (lines 78, 190).** NonceManager reaches into provider's private API to get the Promise module. Instead, accept the Promise module at construction time:
  ```luau
  function NonceManager.new(provider, config, PromiseModule?): any
  ```
  Or have the provider expose it publicly (see RpcProvider section).

- `[refactor]` **Hex nonce parsing duplicated 3 times.** Lines 98-102 (`reserve`), 152-155 (`confirm`), 171-174 (`reject`) all do the same pattern:
  ```luau
  local nonce = tonumber(result, 16)
  if not nonce then
      nonce = tonumber(result) or 0
  end
  ```
  Extract to a local helper: `local function parseNonceHex(hex: string): number`.

- `[refactor]` **`countPending()` is O(n) table iteration (lines 58-64).** Called on every `reserve()` to check backpressure. For typical `maxPendingNonces` = 10, this is negligible. But the count could be tracked incrementally:
  ```luau
  state.pendingCount += 1  -- on reserve
  state.pendingCount -= 1  -- on confirm/reject
  ```
  Eliminates the iteration entirely. Minor optimization.

- `[api]` **Provider parameter typed as `any` (line 38).** Should reference the provider type for IDE support.

- `[test]` 64 tests — good coverage of reserve/confirm/reject, resync, backpressure, multi-address, and dirty flag.

---

### EventPoller.luau
_176 lines. Polling-based event subscription for Roblox (no WebSocket support)._

- `[ok]` Clean polling loop with configurable interval and safety limits.
- `[ok]` Automatic `from_block` advancement past highest seen block prevents re-fetching.
- `[ok]` Callback errors caught and forwarded to `onError` without stopping the poll loop — resilient.
- `[ok]` Stop mechanism is clean: `_running = false` exits on next iteration.

- `[refactor]` **Calls `self._provider:_requestWithRetry()` directly (lines 68, 109) — breaks encapsulation.** `_requestWithRetry` is a private method on RpcProvider (underscore prefix, not in exported type). EventPoller bypasses the Promise layer, queue, and cache to get synchronous results. This tight coupling means:
  - If `_requestWithRetry` is renamed/refactored, EventPoller breaks silently
  - EventPoller cannot benefit from request queue batching
  - EventPoller bypasses cache (intentional for events, but implicit)

  **Fix:** Add a public `fetchSync(method, params)` to RpcProvider and update EventPoller to use it:
  ```luau
  -- EventPoller.luau line 68
  return self._provider:fetchSync("starknet_blockNumber", {})

  -- EventPoller.luau line 109
  local chunk = self._provider:fetchSync("starknet_getEvents", { { filter = pageFilter } })
  ```

- `[refactor]` **Event pagination loop (lines 92-125) duplicates `getAllEvents()` in RpcProvider.luau:982-1032.** Both implement the same continuation-token iteration with safety limits. ~30 lines of identical logic. Extract to a shared helper on RpcProvider:
  ```luau
  function RpcProviderClass:_paginateEventsSync(filter, maxPages): { EmittedEvent }
      -- shared continuation-token loop
  end
  ```
  Then `getAllEvents()` wraps it in a Promise, and EventPoller calls it directly.

- `[refactor]` **Filter reconstruction duplicated on every poll cycle (lines 84-90 and 146-152).** The same filter fields are copied into a new table each iteration. Could maintain a mutable `_currentFilter` field and only update `from_block` on block advancement.

- `[api]` **No way to get the last polled block number.** `_lastBlockNumber` is tracked internally but not exposed. Consumers may want to know the poller's progress. Add `getLastBlockNumber(): number?`.

- `[test]` 47 tests (EventPoller + getAllEvents) — good coverage of polling lifecycle, pagination, error recovery, and block advancement.

---

### provider/init.luau (barrel)
_19 lines. Re-exports all provider sub-modules._

- `[ok]` Clean barrel, no logic.
- `[ok]` Uses Roblox-style `require(script.Module)` — correct for runtime barrel.
- `[ok]` Exports all 6 sub-modules: RpcProvider, RpcTypes, EventPoller, RequestQueue, ResponseCache, NonceManager.

---

### provider/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 2,167 (385 + 1104 + 216 + 311 + 276 + 176 + 19) |
| **Total public methods** | 36 (RpcProvider: 26, RequestQueue: 8, ResponseCache: 8, NonceManager: 10, EventPoller: 3) |
| **Total tests** | 382 (59 + 82 + 89 + 64 + 47 + 39 + misc) |
| **Code duplicated in PaymasterRpc** | ~200 lines (rate limiter, HTTP helpers, JSON encode/decode, raw request, retry logic, Promise type, HTTP types) |
| **Private method violations** | 5 (`_getPromise` ×3, `_requestWithRetry` ×2 from EventPoller) |
| **DRY violations** | 6 significant (rate limiter, HTTP helpers, JSON helpers, raw request, retry logic, pagination loop) |
| **Dead code** | 1 (`RpcTypes.ErrorTypes` — never used) |

---

### Priority Actions (provider/)

1. **HIGH — Extract shared `JsonRpcClient` base module.** Create `src/provider/JsonRpcClient.luau` containing: rate limiter (`createRateLimiter`, `tryAcquire`), HTTP helpers (`_doHttpRequest`, `_jsonEncode`, `_jsonDecode`), `_rawRequest()` (with error mapper callback), `_requestWithRetry()` (with shouldRetry predicate), Promise loading (`_getPromise`), and constructor boilerplate. Both `RpcProvider` and `PaymasterRpc` delegate to this shared infrastructure. Eliminates ~200 lines of duplication across the two files.

2. **HIGH — Make `_getPromise()` public or inject Promise at construction.** Three external modules call `provider:_getPromise()`. Either rename to `getPromise()` and add to the exported `RpcProvider` type, or pass the Promise module to NonceManager/Account at construction time. The current approach breaks the private convention.

3. **HIGH — Add public `fetchSync()` method and update EventPoller.** EventPoller calls private `_requestWithRetry()` directly. Expose a public `fetchSync(method, params)` that wraps `_requestWithRetry()`. Update EventPoller lines 68 and 109 to use it. This preserves encapsulation and makes the contract explicit.

4. **HIGH — Add `addDeployAccountTransaction` to HIGH priority in RequestQueue.** Lines 49-54 of RequestQueue.luau classify `addInvokeTransaction` and `estimateFee` as HIGH but omit `addDeployAccountTransaction`. Deploy account submissions are equally latency-sensitive.

5. **MEDIUM — Extract event pagination helper.** `getAllEvents()` (RpcProvider:982-1032) and EventPoller:92-125 share ~30 lines of identical continuation-token iteration. Extract to `_paginateEventsSync(filter, maxPages)` on RpcProvider, used by both.

6. **MEDIUM — Extract rate-limit acquisition helper.** Rate-limit spin wait (lines 241-254 and 496-513) is duplicated in `_rawRequest()` and `_dispatchBatch()`. Extract to `_acquireRateLimitToken()`.

7. **MEDIUM — Extract header construction helper.** Header building (lines 266-271 and 531-536) is duplicated. Extract to `_buildHeaders()`.

8. **MEDIUM — DRY the nonce hex parsing.** NonceManager has the same `tonumber(hex, 16)` pattern at lines 98, 152, and 171. Extract to `parseNonceHex()` local helper.

9. **MEDIUM — Remove `RpcTypes.ErrorTypes` dead code.** Lines 376-382 define 5 error type constants never used anywhere. Remove entirely — `ErrorCodes` from `errors/ErrorCodes.luau` is the canonical source.

10. **LOW — Use proper types for config parameters.** ResponseCache constructor accepts `{ [string]: any }?` instead of `CacheConfig`. NonceManager and EventPoller accept `provider: any` instead of typed provider. Add proper type annotations where possible.

11. **LOW — Consolidate `getMetrics()` return paths.** Lines 675-715 have two nearly identical return tables for queue-enabled vs disabled. Merge into a single return with conditional queue metric injection.

---

### Provider Cross-Cutting Audit — PaymasterRpc Duplication

_Complete inventory of code duplicated between `src/provider/RpcProvider.luau` and `src/paymaster/PaymasterRpc.luau`._

**Why this matters:** PaymasterRpc is a parallel JSON-RPC client that re-implements the entire HTTP/rate-limit/retry/JSON stack from RpcProvider. Bug fixes, performance improvements, or behavioral changes must be applied in both files. The two implementations can silently diverge.

| Component | RpcProvider Lines | PaymasterRpc Lines | Similarity | Notes |
|-----------|------------------|--------------------|------------|-------|
| `Promise<T>` type | 15-19 | 15-19 | 100% identical | Move to RpcTypes |
| `HttpRequest` type | (RpcTypes:83-88) | 21-26 | 100% identical | Import from RpcTypes |
| `HttpResponse` type | (RpcTypes:91-96) | 28-33 | 100% identical | Import from RpcTypes |
| `RateLimiter` type | 70-75 | 170-175 | 100% identical | Extract to RateLimiter.luau |
| `createRateLimiter()` | 77-84 | 177-184 | 100% identical | Extract to RateLimiter.luau |
| `tryAcquire()` | 86-98 | 186-198 | 100% identical | Extract to RateLimiter.luau |
| Constructor boilerplate | 130-188 | 209-243 | 85% identical | Shared base fields, differs in queue/cache/nonce setup |
| `_getPromise()` | 196-206 | 254-264 | 98% identical | Differs only in error message text |
| `_doHttpRequest()` | 209-216 | 266-272 | 100% identical | Extract to shared module |
| `_jsonEncode()` | 219-227 | 274-281 | 100% identical | Extract to shared module |
| `_jsonDecode()` | 230-237 | 283-290 | 100% identical | Extract to shared module |
| `_rawRequest()` | 240-306 | 307-371 | 95% identical | Differs only in error mapping branch |
| `_requestWithRetry()` | 309-334 | 375-412 | 90% identical | Differs in "don't retry" condition |
| `fetch()` | 340-366 | 419-432 | 70% similar | RpcProvider has cache layer; PaymasterRpc is direct |

**Total duplicated code:** ~200 lines across 14 functions/types.

**Recommendation:** Extract a `JsonRpcClient` base that encapsulates:
- Rate limiter creation + token acquisition
- HTTP request execution (Roblox vs Lune environment detection)
- JSON serialization (same environment detection)
- JSON-RPC envelope construction
- Raw request (rate limit → build envelope → HTTP POST → decode → error check)
- Retry loop (configurable shouldRetry predicate)
- Promise module loading

RpcProvider extends this base with: queue, cache, nonce manager, block invalidation, 26 typed RPC methods.
PaymasterRpc extends this base with: SNIP-29 error mapping, 5 typed paymaster methods.

```
Before:
  RpcProvider (1104 lines, self-contained)
  PaymasterRpc (661 lines, ~200 lines duplicated from RpcProvider)

After:
  JsonRpcClient (~200 lines, shared base)
  RpcProvider (~900 lines, extends JsonRpcClient)
  PaymasterRpc (~460 lines, extends JsonRpcClient)
```

---

### Provider Cross-Cutting Audit — External Module Usage

_How every module outside `provider/` interacts with the provider._

**Account.luau (wallet/):**
```
Calls provider:_getPromise()          ← private method access [fix]
Calls provider:getNonce()             ← public API [ok]
Calls provider:getChainId()           ← public API [ok]
Accesses provider._nonceManager       ← private field access [fix]
  → nm:reserve(address)
  → nm:confirm(address, nonce)
  → nm:reject(address, nonce)
```
**Fix:** Use `provider:getNonceManager()` (line 636, already exists but not in exported type) instead of `provider._nonceManager`.

**TransactionBuilder.luau (tx/):**
```
Stores provider reference              ← constructor param [ok]
Calls provider:getNonce()              ← public API [ok]
Calls provider:getChainId()            ← public API [ok]
Calls provider:estimateFee()           ← public API [ok]
Calls provider:addInvokeTransaction()  ← public API [ok]
Calls provider:addDeployAccountTransaction() ← public API [ok]
Calls provider:waitForTransaction()    ← public API [ok]
```
**Status:** Clean — uses only public API.

**Contract.luau (contract/):**
```
Calls provider:call()                  ← public API [ok]
Calls provider:getEvents()             ← public API [ok]
```
**Status:** Clean.

**ERC20.luau / ERC721.luau (contract/):**
```
Passes provider to Contract.new()      ← constructor forwarding [ok]
```
**Status:** Clean.

**NonceManager.luau (provider/):**
```
Calls provider:_getPromise()           ← private method access [fix]
Calls provider:getNonce()              ← public API [ok]
```
**Fix:** Inject Promise module at construction (see NonceManager section).

**EventPoller.luau (provider/):**
```
Calls provider:_requestWithRetry()     ← private method access [fix]
```
**Fix:** Use proposed `fetchSync()` public method.

**AccountFactory.luau (wallet/):**
```
Passes provider to Account.new()       ← constructor forwarding [ok]
```
**Status:** Clean.

**PaymasterRpc.luau (paymaster/):**
```
No interaction with RpcProvider         ← parallel implementation [refactor]
```
**Status:** Completely independent — duplicates infrastructure instead of reusing it.

**AvnuPaymaster.luau (paymaster/):**
```
Delegates to PaymasterRpc              ← clean abstraction [ok]
```
**Status:** Clean.

**SponsoredExecutor.luau (paymaster/):**
```
Stores provider reference              ← used for Account construction [ok]
```
**Status:** Clean.

**Summary of private API violations:**

| Caller | Private Access | Fix |
|--------|---------------|-----|
| Account.luau | `provider:_getPromise()` | Make public or inject |
| Account.luau | `provider._nonceManager` | Use `provider:getNonceManager()` + add to type |
| NonceManager.luau | `provider:_getPromise()` | Inject at construction |
| EventPoller.luau | `provider:_requestWithRetry()` | Use public `fetchSync()` |
