## 7. contract/

### AbiCodec.luau
_688 lines. Recursive ABI type resolution, encoding, and decoding for Cairo types. Handles felt252, bool, u256, structs, enums, arrays, spans, tuples, Option, Result, ByteArray. Internal module -- not exported through barrel._

- `[ok]` Clean type system. `TypeDef`, `TypeMap`, `EventDef` types are well-defined and cover all Cairo type kinds.
- `[ok]` `buildTypeMap()` correctly clones `BUILTIN_TYPES` to prevent cross-contract contamination. Correctly skips `core::bool`, `core::option::Option`, and `core::result::Result` from ABI enum defs since those are resolved as generics.
- `[ok]` `resolveType()` has proper caching -- writes resolved types back into `typeMap` for O(1) subsequent lookups.
- `[ok]` `parseTupleTypes()` correctly handles nested generics by tracking angle bracket depth -- essential for types like `(Array<felt252>, u256)`.
- `[ok]` `encodeEnum()` cleanly handles three enum conventions: Option (`{Some=val}` / `{None=true}` / `nil`), Result (`{Ok=val}` / `{Err=val}`), and custom enums (`{variant="Name", value=data}`).
- `[ok]` `decodeOutputs()` smart dispatch: single output returns bare value, multiple outputs return keyed table, zero outputs return raw felts.
- `[ok]` Consistent use of `StarknetError.abi()` with `ErrorCodes` throughout -- no raw `error("string")` calls.
- `[ok]` `INTEGER_PATTERNS` covers all Cairo integer types (`u8`..`u128`, `i8`..`i128`) with both short and fully-qualified names.

- `[fix]` **`parseHexNumber` pattern has dead first branch.** Lines 300, 330, 551, 587 all use:
  ```luau
  local n = tonumber(hexStr, 16) or tonumber(string.sub(hexStr, 3), 16) or 0
  ```
  In Luau, `tonumber("0x1a", 16)` returns `nil` because the `0x` prefix is not valid with an explicit base-16 argument. So the first `tonumber()` **always fails** for standard `0x`-prefixed hex strings. The second branch does the real work. This is not a bug (the fallback is correct), but the first call is dead code that misleads readers. Extract to a single helper:
  ```luau
  local function parseHexToNumber(hex: string): number
      local stripped = if string.sub(hex, 1, 2) == "0x" then string.sub(hex, 3) else hex
      return tonumber(stripped, 16) or 0
  end
  ```
  This eliminates 4 instances of duplicated hex-parsing logic.

- `[refactor]` **CRITICAL -- Encode-and-append pattern repeated 10+ times.** Throughout `encode()`, `encodeEnum()`, and `encodeInputs()`, the same 3-line pattern appears:
  ```luau
  local encoded = AbiCodec.encode(someValue, someType, typeMap)
  for _, felt in encoded do
      table.insert(result, felt)
  end
  ```
  Occurrences: lines 375-378, 392-395, 403-406, 432-435, 442-445, 451-454, 460-463, 471-474, 478-481, 494-497, 610-613. That's ~33 lines of identical boilerplate. Extract:
  ```luau
  local function appendAll(target: { string }, source: { string })
      table.move(source, 1, #source, #target + 1, target)
  end
  ```
  Then each call site becomes `appendAll(result, AbiCodec.encode(val, typ, typeMap))` -- one line instead of three.

- `[refactor]` **ByteArray bytes-to-hex conversion duplicated.** Lines 270-274 and 279-284 in `encodeByteArray()` contain identical byte-to-hex loops:
  ```luau
  local hexParts = {}
  for j = 1, #chunk do
      table.insert(hexParts, string.format("%02x", string.byte(chunk, j)))
  end
  table.insert(result, "0x" .. table.concat(hexParts))
  ```
  Same for the reverse (hex-to-bytes) in `decodeByteArray()` lines 315-320 and 338-343. Extract `bytesToHex(str): string` and `hexToBytes(hex, expectedLen): string` helpers. Saves ~20 lines and eliminates 4 near-identical loops.

- `[refactor]` **`resolveType()` silently falls back to `felt` for unknown types.** Lines 243-246:
  ```luau
  -- Fallback: treat as felt (backward compat)
  local def: TypeDef = { kind = "felt" }
  typeMap[typeName] = def
  return def
  ```
  Any typo in a type name (e.g., `core::flelt252`) silently encodes/decodes as a felt, producing corrupt data with no error. The "backward compat" comment lacks context on what it's backward-compatible with. At minimum, add a `warn()` call here. Better: accept a `strict: boolean?` option in `buildTypeMap()` that errors on unknown types, defaulting to lenient for backward compat.

- `[refactor]` **Unreachable fallback in `encode()` and `decode()`.** Lines 411-412 and 573-574:
  ```luau
  -- Fallback: treat as felt
  return CallData.encodeFelt(tostring(value))
  ```
  After the `if/elseif` chain covers all 9 type kinds (felt, bool, u256, unit, bytearray, struct, enum, array, tuple), and `resolveType()` always returns one of those kinds (its own fallback returns `kind = "felt"`), these fallback lines are unreachable dead code. Remove them or convert to `error("unreachable")` assertions for defensive coding.

- `[fix]` **`decode()` does not validate array bounds.** Lines 522-574: reads `results[offset]` without checking `offset <= #results`. If the RPC returns fewer felts than expected (malformed response), this silently produces `nil` values instead of a clear error. For example, decoding a `u256` reads `results[offset]` and `results[offset + 1]` (lines 527-528) but never validates both indices exist. Add bounds checks:
  ```luau
  if offset > #results then
      error(StarknetError.abi(
          `AbiCodec: decode out of bounds at offset {offset}, results has {#results} felts`,
          ErrorCodes.DECODE_ERROR.code
      ))
  end
  ```

- `[refactor]` **`decodeEvent()` silently skips members when keys/data arrays are short.** Lines 667-683: if `keyOffset > #keys` or `dataOffset > #data`, members are simply omitted from the result. The caller has no way to tell whether a field is absent because it wasn't emitted or because data was truncated. Consider adding a `_partial: boolean` flag to the returned table, or erroring when data is shorter than the event definition expects.

- `[type]` **`AbiEntry.items` typed as `{ any }?`.** Line 33. This is the interface-nested-items field. Since items are known to be `AbiFunction` entries, it should be `{ AbiFunction }?` for better type safety.

- `[perf]` **Eager selector computation in `parseAbi()` outside this file.** Although this is triggered by `Contract.new()` (not AbiCodec), `buildTypeMap()` is called from there, and the related `parseAbi()` computes Keccak selectors for every ABI function at construction time. For large ABIs (100+ functions), this is non-trivial. Lazy selector computation would defer cost until first use.

- `[test]` 109 tests -- excellent coverage.
- `[test]` **No test for `decode()` with insufficient results array.** Missing test: decode a `u256` from a 1-element array (should error or handle gracefully, currently returns `nil` for `high`).
- `[test]` **No test for `resolveType()` fallback with unknown type names.** Missing test: verify behavior when an unrecognized type name falls through all patterns.
- `[test]` **No test for deeply nested recursive types.** Missing: `Array<Array<struct with u256>>` or `Option<Option<felt252>>` stress tests for the recursive codec.

---

### Contract.luau
_482 lines. ABI-driven contract interaction via dynamic method dispatch (__index metamethod). Supports call (views), invoke (externals), populate (multicall), and event parsing._

- `[ok]` Clean separation: `parseAbi()` handles functions, `parseAbiEvents()` handles events, `AbiCodec.buildTypeMap()` handles type definitions. Each parser is focused.
- `[ok]` Dynamic dispatch via `__index` is well-implemented. View functions return Promise-based `call()`, external functions return `invoke()` with trailing-options detection.
- `[ok]` `invoke()` correctly delegates to `populate()` then `account:execute()` -- avoids duplicating calldata encoding.
- `[ok]` `parseAbiEvents()` correctly handles both modern Cairo events (`kind="struct"` with key/data members) and legacy events (`inputs` array).
- `[ok]` `queryEvents()` correctly pre-fills contract address filter before delegating to `provider:getEvents()`.
- `[ok]` Consistent `StarknetError.validation()` and `StarknetError.abi()` usage throughout.
- `[ok]` Event selector extraction from fully-qualified names (`pkg::module::Transfer` → `Transfer`) is correct.

- `[fix]` **Address comparison in `parseEvents()` vulnerable to hex normalization mismatch.** Lines 400-411:
  ```luau
  local contractAddress: string = string.lower(self_.address)
  local fromAddr: string = string.lower(event.from_address or "")
  if fromAddr == contractAddress then
  ```
  `string.lower()` handles case normalization but **not** hex normalization. If `self_.address` is `"0x049d..."` (leading zero) and the RPC returns `"0x49d..."` (without), the comparison fails despite being the same address. Starknet RPC responses can strip leading zeros. Fix: normalize both addresses through BigInt before comparison:
  ```luau
  local BigInt = require("../crypto/BigInt")
  local contractAddress = BigInt.toHex(BigInt.fromHex(self_.address))
  -- and for each event:
  local fromAddr = BigInt.toHex(BigInt.fromHex(event.from_address or "0x0"))
  ```
  Or, since this is called per-event in a loop, pre-compute the normalized address once in `Contract.new()` and store it as `_normalizedAddress`.

- `[refactor]` **CRITICAL -- Duplicated validation+encoding in `call()` and `populate()`.** Lines 267-288 (`call`) and 310-331 (`populate`) contain 22 identical lines:
  ```luau
  local functions = self_._functions
  local fn = functions[method]
  if not fn then error(...) end
  local callArgs = args or {}
  local inputs = fn.inputs
  local typeMap = self_._typeMap
  if #callArgs ~= #inputs then error(...) end
  local calldata = AbiCodec.encodeInputs(callArgs, inputs, typeMap)
  ```
  `invoke()` (line 358) already delegates to `populate()`, proving the pattern works. `call()` should also delegate to a shared helper. Extract:
  ```luau
  local function resolveAndEncode(self_: any, method: string, args: { any }?): (ParsedFunction, { string })
      local fn = self_._functions[method]
      if not fn then error(StarknetError.abi(...)) end
      local callArgs = args or {}
      if #callArgs ~= #fn.inputs then error(StarknetError.abi(...)) end
      local calldata = AbiCodec.encodeInputs(callArgs, fn.inputs, self_._typeMap)
      return fn, calldata
  end
  ```
  Then `call()` uses `local fn, calldata = resolveAndEncode(self_, method, args)` and `populate()` does the same. Saves ~18 lines.

- `[refactor]` **`self_: any = self` cast repeated 11 times.** Lines 188, 267, 310, 347, 364, 376, 383, 397, 438, 456, 472. This is a necessary workaround for Luau strict mode not understanding the `__index` metamethod pattern, but it should be documented with a single comment at the class level explaining why it's necessary, rather than appearing silently in every method.

- `[refactor]` **`parseEvents()` silently swallows decode errors.** Lines 418-425:
  ```luau
  local ok, fields = pcall(AbiCodec.decodeEvent, keys, event.data or {}, eventDef, typeMap)
  if ok then
      table.insert(parsed, { name = eventDef.name, fields = fields, raw = event })
  end
  ```
  When `pcall` catches an error, the event is silently skipped with no logging or callback. This makes production debugging very difficult when events are unexpectedly missing from parsed output. Consider: (a) accept an `onError` callback in options, (b) return failed events in a separate `errors` array alongside `parsed`, or (c) at minimum store a `_lastParseErrors` field on the contract instance.

- `[refactor]` **`hasEvent()` is O(n) linear scan vs O(1) `hasFunction()`.** Lines 471-480: `_events` is keyed by selector hex (not by name), so `hasEvent()` must scan all entries. `hasFunction()` (line 382) does O(1) lookup because `_functions` is keyed by name. Fix: maintain a parallel `_eventsByName` lookup table built in `parseAbiEvents()`, or add name-keyed entries alongside selector-keyed entries. This also benefits `getEvents()` (lines 459-462) which already needs a `seen` set to deduplicate names.

- `[api]` **Dynamic dispatch options heuristic is fragile.** Lines 213-221:
  ```luau
  if type(lastArg) == "table" and #args > #fn.inputs then
      options = lastArg :: any
  ```
  If a function's last ABI input is a table type (struct, array) and the user passes exactly one extra argument, this heuristic incorrectly steals the last real argument as "options." Example: `foo(myStruct, {dryRun = true})` works, but if `myStruct` happens to have a `dryRun` field, the behavior becomes ambiguous. This edge case should be documented with a comment warning, or the options detection should check for known option keys (`nonce`, `maxFee`, `feeMultiplier`, `dryRun`).

- `[type]` **`ContractConfig.provider` and `ContractConfig.account` typed as `any`.** Lines 39-40. The type checker provides zero help for provider/account API misuse. Define minimal interface types:
  ```luau
  type ProviderLike = { call: (any, any, string?) -> any, getEvents: (any, any) -> any }
  type AccountLike = { execute: (any, { any }, any?) -> any }
  ```
  This gives autocomplete and catches method-name typos without requiring the full circular import.

- `[type]` **`Contract.new()` return type is `any`.** Line 234. Also `call()`, `invoke()`, `queryEvents()` all return `any`. Consumers get zero autocomplete or type checking on Contract instances.

- `[doc]` **No class-level doc comment.** The module header (lines 2-4) describes the file but doesn't document the public API surface (`new`, `call`, `invoke`, `populate`, `parseEvents`, `queryEvents`, `getFunctions`, `getFunction`, `hasFunction`, `getEvents`, `hasEvent`). A brief API summary comment would help consumers.

- `[test]` 60 tests -- solid coverage of core paths.
- `[test]` **No test for `parseEvents` with hex normalization mismatch** (leading-zero stripping). `ContractEvents.spec.luau` tests case-insensitive matching but not `0x049d...` vs `0x49d...`.
- `[test]` **No test for dynamic dispatch with trailing options table conflicting with struct input** (the fragile heuristic edge case).

---

### ERC20.luau
_167 lines. Pre-built ERC-20 contract interface with baked-in OpenZeppelin Cairo ABI. Provides both snake_case and camelCase method names._

- `[ok]` Clean, focused module. The ABI definition is accurate for standard OZ Cairo ERC-20.
- `[ok]` Both snake_case (`balance_of`, `total_supply`, `transfer_from`) and camelCase (`balanceOf`, `totalSupply`, `transferFrom`) are defined -- correct for OZ dual compatibility.
- `[ok]` Uses `StarknetError.validation()` with `ErrorCodes.REQUIRED_FIELD` consistently.

- `[refactor]` **Redundant validation in `ERC20.new()`.** Lines 147-152: validates `address` and `provider` before passing to `Contract.new()`, which performs identical validation (Contract.luau lines 238-243). The ERC20 version provides a slightly better error message prefix ("ERC20:" vs "Contract:"), but this is duplication. Either remove it (relying on Contract.new) or make it the **only** validation by passing through a flag that tells Contract.new to skip its own checks.

- `[feat]` **Missing standard ERC-20 functions.** The baked-in ABI is missing common OZ functions:
  - `increase_allowance(spender, added_value)` / `increaseAllowance()` -- very commonly used
  - `decrease_allowance(spender, subtracted_value)` / `decreaseAllowance()` -- paired with above
  These are part of the standard OZ ERC-20 component and expected by most developers.

- `[feat]` **No event definitions in `ERC20_ABI`.** Lines 14-133 define only functions. Missing `Transfer` and `Approval` event definitions. This means:
  - `contract:parseEvents(receipt)` returns empty array for ERC20 instances
  - `contract:hasEvent("Transfer")` returns `false`
  - `contract:getEvents()` returns empty array
  This is a significant functional gap. The standard Transfer event:
  ```luau
  {
      type = "event", kind = "struct", name = "Transfer",
      members = {
          { name = "from", kind = "key", type = "core::starknet::contract_address::ContractAddress" },
          { name = "to", kind = "key", type = "core::starknet::contract_address::ContractAddress" },
          { name = "value", kind = "data", type = "core::integer::u256" },
      },
  },
  ```

- `[refactor]` **ERC20/ERC721 share identical module structure.** See cross-cutting section below.

- `[test]` 35 tests -- covers all defined methods.
- `[test]` **No event parsing tests** since the preset ABI lacks event definitions.

---

### ERC721.luau
_205 lines. Pre-built ERC-721 NFT contract interface with baked-in OpenZeppelin Cairo ABI. Provides both snake_case and camelCase method names._

- `[ok]` Clean, focused module. ABI definitions are accurate for standard OZ Cairo ERC-721.
- `[ok]` Both snake_case and camelCase aliases are defined correctly.
- `[ok]` Uses `StarknetError.validation()` with `ErrorCodes.REQUIRED_FIELD` consistently.

- `[refactor]` **Same redundant validation as ERC20.** Lines 185-190. Identical issue to ERC20 issue above.

- `[feat]` **Missing standard ERC-721 functions.** The baked-in ABI is missing:
  - `safe_transfer_from(from, to, token_id, data)` / `safeTransferFrom()` -- the safe transfer variant, required by the standard
  - `token_uri(token_id)` / `tokenURI()` -- metadata URI, arguably the most commonly called view function after `owner_of` for NFT game integrations
  - `supports_interface(interface_id)` / `supportsInterface()` -- ERC-165 introspection
  For a Roblox gaming SDK, `token_uri` is particularly important for fetching NFT metadata.

- `[feat]` **No event definitions in `ERC721_ABI`.** Same issue as ERC20. Missing `Transfer`, `Approval`, and `ApprovalForAll` event definitions. The standard Transfer event:
  ```luau
  {
      type = "event", kind = "struct", name = "Transfer",
      members = {
          { name = "from", kind = "key", type = "core::starknet::contract_address::ContractAddress" },
          { name = "to", kind = "key", type = "core::starknet::contract_address::ContractAddress" },
          { name = "token_id", kind = "key", type = "core::integer::u256" },
      },
  },
  ```

- `[refactor]` **ERC20/ERC721 share identical module structure.** See cross-cutting section below.

- `[test]` 41 tests -- covers all defined methods.
- `[test]` **No event parsing tests** since the preset ABI lacks event definitions.
- `[test]` **No tests for missing functions** (`safe_transfer_from`, `token_uri`).

---

### contract/init.luau (barrel)
_8 lines. Re-exports Contract, ERC20, ERC721._

- `[ok]` Clean barrel, no logic. Uses Roblox-style `require(script.X)` correctly.
- `[api]` **AbiCodec intentionally not exported.** Comment in AbiCodec.luau line 4 confirms it's internal. However, consumers who want to do custom calldata encoding outside of Contract (e.g., building raw multicall data) have no access to the recursive type-aware codec. Consider exporting it or providing a thin public `Contract.encodeCalldata(abi, functionName, args)` static method.

---

### contract/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 1,550 (688 + 482 + 167 + 205 + 8) |
| **Total public functions** | 21 (AbiCodec: 10, Contract: 11, ERC20: 2, ERC721: 2) |
| **Total tests** | 245 (AbiCodec: 109, Contract: 60, ERC20: 35, ERC721: 41) |
| **DRY violations** | 6 significant (see below) |
| **Production bugs** | 2 (address comparison, dead hex parse branch) |
| **Missing features** | 4 (ERC20 events, ERC721 events, ERC721 token_uri/safe_transfer, ERC20 increase/decrease_allowance) |
| **Type gaps** | 3 (provider/account as `any`, Contract.new returns `any`, AbiEntry.items as `{any}`) |
| **Dead code** | 2 (unreachable fallbacks in encode/decode) |

### DRY Violations Summary

| # | Violation | Lines Wasted | Location |
|---|-----------|--------------|----------|
| 1 | `call()` / `populate()` duplicated validation+encoding | ~18 | Contract.luau:267-288 + 310-331 |
| 2 | Encode-and-append 3-line pattern repeated 10+ times | ~33 | AbiCodec.luau: 10+ sites (see list above) |
| 3 | `parseHexNumber` pattern duplicated 4 times | ~8 | AbiCodec.luau:300, 330, 551, 587 |
| 4 | ByteArray bytes-to-hex / hex-to-bytes duplicated 2x each | ~20 | AbiCodec.luau:270-274+279-284 (encode), 315-320+338-343 (decode) |
| 5 | ERC20.new() / ERC721.new() identical factory+validation | ~30 | ERC20.luau:146-160 + ERC721.luau:184-198 |
| 6 | Redundant validation in presets vs Contract.new() | ~12 | ERC20.luau:147-152 + ERC721.luau:185-190 (duplicates Contract.luau:235-243) |

### Cross-Cutting: ERC20/ERC721 Preset Duplication

ERC20.luau and ERC721.luau are structurally identical -- they differ only in the ABI content. Both:
1. Import `Contract` and `StarknetError`
2. Define a static ABI table
3. Have a `new(address, provider, account?)` factory with identical validation
4. Have a `getAbi()` accessor
5. Call `Contract.new()` identically

This is a textbook case for a shared factory. Extract to `contract/PresetFactory.luau`:

```luau
local function createPreset(name: string, abi: Contract.Abi)
    local Preset = {}

    function Preset.new(address: string, provider: any, account: any?): any
        if not address then
            error(StarknetError.validation(`{name}: address is required`, ErrorCodes.REQUIRED_FIELD.code))
        end
        if not provider then
            error(StarknetError.validation(`{name}: provider is required`, ErrorCodes.REQUIRED_FIELD.code))
        end
        return Contract.new({ abi = abi, address = address, provider = provider, account = account })
    end

    function Preset.getAbi(): Contract.Abi
        return abi
    end

    return Preset
end
```

Then ERC20.luau becomes:
```luau
local createPreset = require("./PresetFactory")
local ERC20_ABI = { ... }  -- ABI definition only
return createPreset("ERC20", ERC20_ABI)
```

This eliminates ~30 lines of duplicated boilerplate per preset and makes adding future presets (ERC1155, ERC4626, etc.) trivial -- just define the ABI.

### Contract ↔ Provider Event Architecture

```
EventPoller (provider/) ----polls----> RpcProvider._requestWithRetry("starknet_getEvents")
                                       (raw events, no decoding)

RpcProvider:getEvents()  -----------> single-page raw event query
RpcProvider:getAllEvents() ---------> multi-page raw event query (pagination)

Contract:queryEvents()   -----------> delegates to RpcProvider:getEvents()
                                      (adds contract address filter)

Contract:parseEvents(receipt) ------> AbiCodec.decodeEvent(keys, data, eventDef, typeMap)
                                      (filters by address, matches by selector, decodes fields)
```

EventPoller and Contract are independent. EventPoller returns raw events; Contract:parseEvents() decodes them. There is no integrated "poll + decode" flow. Consumers must manually bridge the two:
1. Use EventPoller to get raw events
2. Wrap them in a receipt-like structure
3. Pass to Contract:parseEvents()

This is a potential API improvement -- a `Contract:pollEvents()` method that combines polling with decoding.

### Cross-Module DRY Violations (contract/ ↔ other modules)

| # | Violation | Files Affected |
|---|-----------|----------------|
| 1 | Address normalization missing everywhere (contract uses `string.lower`, should use BigInt roundtrip) | `contract/Contract.luau:400-411` -- see also `normalizeHex()` duplication in [tx/ section](./05-tx.md) |
| 2 | `CallData.encodeArray()` and `CallData.encodeStruct()` overlap with AbiCodec's recursive encoder | `tx/CallData.luau:91-107` ↔ `contract/AbiCodec.luau:370-397` (AbiCodec is type-aware superset) |
| 3 | Selector computation (`Keccak.getSelectorFromName`) used in 4 modules | `contract/Contract.luau:76,117` + `tx/CallData.luau:123` + `wallet/TypedData.luau:431,471` + `wallet/OutsideExecution.luau:164` -- not duplication (different domains), but selector computation could be centralized |

---

### Priority Actions (contract/)

1. **HIGH -- Fix address comparison in `parseEvents()` to handle hex normalization.** Lines 400-411 in Contract.luau use `string.lower()` which doesn't normalize leading zeros. RPC responses can return `0x49d...` while the contract was created with `0x049d...`. Pre-compute a normalized address in `Contract.new()` via BigInt roundtrip. 4-line fix, prevents silent event loss in production.

2. **HIGH -- Add event definitions to ERC20 and ERC721 preset ABIs.** Transfer, Approval (both), and ApprovalForAll (ERC721) events are missing. Without them, `parseEvents()`, `hasEvent()`, and `getEvents()` are non-functional on preset instances. This is a data-only change (adding ABI entries) with zero logic changes needed.

3. **HIGH -- Extract `parseHexToNumber()` helper in AbiCodec.** Eliminate 4 duplicated instances of the broken two-branch hex parsing pattern. The first `tonumber(hex, 16)` branch is dead code for `0x`-prefixed strings.

4. **MEDIUM -- Extract `resolveAndEncode()` helper in Contract.luau.** Deduplicate the 22 identical validation+encoding lines shared between `call()` and `populate()`. Both methods need the same `(fn, calldata)` result; only the downstream action differs.

5. **MEDIUM -- Extract `appendAll()` helper in AbiCodec.** Replace 10+ instances of the 3-line encode-and-append pattern with a single `table.move`-based helper. Saves ~33 lines and improves readability of the recursive encoder.

6. **MEDIUM -- Create `PresetFactory.luau` for ERC20/ERC721.** Eliminate ~30 lines of identical factory boilerplate per preset. Makes future presets (ERC1155, custom game token) trivial to add.

7. **MEDIUM -- Add missing ERC-721 functions: `safe_transfer_from`, `token_uri`, `supports_interface`.** For a Roblox gaming SDK, `token_uri` is essential for fetching NFT metadata. `safe_transfer_from` is part of the ERC-721 standard.

8. **MEDIUM -- Add missing ERC-20 functions: `increase_allowance`, `decrease_allowance`.** Common in OZ ERC-20 implementations and frequently used by dApps.

9. **MEDIUM -- Add bounds checking in `AbiCodec.decode()`.** Validate `offset <= #results` before reading. Currently produces `nil` values for malformed/truncated RPC responses, which propagates as silent data corruption.

10. **MEDIUM -- Build `_eventsByName` lookup in `parseAbiEvents()`.** Makes `hasEvent()` O(1) consistent with `hasFunction()`, and simplifies `getEvents()` by removing the `seen` dedup set.

11. **LOW -- Extract ByteArray `bytesToHex()` / `hexToBytes()` helpers in AbiCodec.** Consolidates 4 near-identical byte conversion loops into 2 reusable functions.

12. **LOW -- Remove unreachable fallbacks in `encode()` and `decode()`.** Lines 411-412 and 573-574 are dead code. Replace with `error("unreachable")` assertions or remove entirely.

13. **LOW -- Document the `self_: any = self` pattern at class level.** Add a single comment explaining why this cast is necessary (Luau strict mode + __index metamethod limitation), rather than having it silently appear in every method.

14. **LOW -- Consider exporting AbiCodec or adding `Contract.encodeCalldata()` static method.** Consumers who build raw multicall data outside Contract currently have no access to the recursive type-aware codec.

15. **LOW -- Add a comment or option for the dynamic dispatch options heuristic.** Document the edge case where the last ABI input is a table type and exactly one extra argument is passed, which could be misinterpreted as options.
