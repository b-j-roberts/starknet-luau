## 10. Examples

### leaderboard.luau

**Status: Mostly correct, minor bugs**

**API Surface Accuracy:**
- `Contract.new({abi, address, provider, account})` — Correct config table shape matches `ContractConfig`
- `Account.fromPrivateKey({privateKey, provider})` — Correct
- `RpcProvider.new({nodeUrl})` — Correct
- Dynamic dispatch (`:get_score()`, `:submit_score()`) — Correct; view → `call()`, external → `invoke()`
- `Contract:populate("submit_score", {args})` — Correct; builds Call object `{contractAddress, entrypoint, calldata}`
- `account:execute(calls)` — Correct
- `account:waitForReceipt(txHash)` — Correct; delegates to `TransactionBuilder:waitForReceipt()`

**Issues:**

1. **`tonumber(score, 16)` bug (lines 133, 157)** — `score` is a `0x`-prefixed hex string from AbiCodec. In Luau, `tonumber("0x1234", 16)` returns `nil` because `0x` is not valid with an explicit base-16 argument. The `or 0` fallback silently masks the error, making the displayed score always 0. Fix: use `tonumber(score)` which auto-detects `0x` prefix.

2. **Dual contract instances** — The example creates separate `leaderboardReader` (no account) and `leaderboardWriter` (with account). This is pedagogically clear but unnecessary — a single contract instance with an account can do both view calls and external calls. Should note this to avoid confusing users into thinking two instances are required.

3. **`score` argument as u128** — The ABI defines `score` as `core::integer::u128`, which AbiCodec resolves as a felt (single hex string). The `string.format("0x%x", score)` conversion at line 172 works for Lua numbers but will silently overflow for scores > 2^53. For a game leaderboard this is fine in practice, but worth noting.

4. **Good practices demonstrated:**
   - Custom ABI definition with proper Cairo type paths
   - Separate read-only vs writable instances (good for least-privilege)
   - `populate()` + `account:execute()` multicall pattern — idiomatic
   - Private key security warning
   - Module return table for composability

**Rating: Good example, fix tonumber bug**

---

### multicall.luau

**Status: Correct, cleanest example**

**API Surface Accuracy:**
- `ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)` — Correct positional params (address, provider, account?)
- `Constants.ETH_TOKEN_ADDRESS` — Exists in `src/constants.luau`
- `ethToken:populate("transfer", {recipient, amount})` — Correct; encodes u256 via AbiCodec
- `account:execute(calls, {feeMultiplier})` — Correct; calls array + optional ExecuteOptions
- `account:waitForReceipt(txHash)` — Correct

**Issues:**

1. **`feeMultiplier = 1.5` is the default** — Specifying it is redundant but acceptable as documentation of the option. Could note "(default)" in the comment.

2. **No error handling on individual calls** — If one transfer has an invalid address, the entire multicall reverts atomically. The example correctly explains this in the header comment ("either all calls succeed or all revert"). Good.

3. **Good practices demonstrated:**
   - ERC20 preset instead of hand-building ABI — idiomatic
   - `populate()` loop → `execute()` — canonical multicall pattern
   - Clear step numbering in comments
   - Promise chain with `:catch()` — proper error handling
   - Explains gas efficiency of batching

**Rating: Excellent, no changes needed beyond the feeMultiplier annotation**

---

### nft-gate.luau

**Status: Correct, realistic game pattern**

**API Surface Accuracy:**
- `ERC721.new(NFT_CONTRACT_ADDRESS, provider)` — Correct positional params (no account needed for read-only)
- `nftContract:balance_of(address)` — Returns u256 `{low: string, high: string}` — `balance.low` access is correct
- `nftContract:owner_of(tokenId)` — Returns single ContractAddress (hex string) — correct
- `:expect()` on Promise — Valid evaera/promise API; yields current thread

**Issues:**

1. **`tonumber(balance.low, 16)` bug (line 58)** — Same `0x` prefix issue as leaderboard. `tonumber(balance.low, 16)` returns nil when balance.low is `"0x..."`. Fix: `tonumber(balance.low)`.

2. **Identity transform no-op (lines 103-105):**
   ```lua
   :andThen(function(result: boolean)
       return result
   end)
   ```
   This wraps `checkNFTOwnership` in an unnecessary identity function. The `:catch()` already chains directly on the promise. Remove.

3. **`:expect()` blocks the thread** — Used inside `RemoteFunction.OnServerInvoke`, which supports yielding in Roblox. This is technically correct but should carry a comment: "expect() yields the current thread — safe inside RemoteFunction callbacks but avoid in RenderStepped/Heartbeat".

4. **Hardcoded NFT contract address** — The example uses a real-looking address (`0x07606a...`). This is fine for an example but could mislead users. Consider using `"0x_YOUR_NFT_COLLECTION_ADDRESS"` for consistency with other examples.

5. **Good practices demonstrated:**
   - Realistic Roblox game architecture (RemoteFunction, PlayerRemoving cleanup)
   - Read-only ERC721 instance (no account — proper least-privilege)
   - Both balance-based and specific-token-ID verification
   - `verifiedPlayers` cache pattern for avoiding repeated RPC calls
   - Module return table with utility function
   - Input validation on address parameter

**Rating: Good, fix tonumber and remove identity transform**

---

### read-contract.luau

**Status: Mostly correct, minor issues**

**API Surface Accuracy:**
- `ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider)` — Correct
- `ERC20.new(Constants.STRK_TOKEN_ADDRESS, provider)` — Correct
- `:name()`, `:symbol()`, `:decimals()` — All exist in ERC20 ABI, return felt252/u8
- `:balance_of(address)` — Returns u256 `{low, high}` — correct access pattern
- `:total_supply()` — Returns u256 `{low, high}` — correct

**Issues:**

1. **Misleading TARGET_ADDRESS** — Line 29 sets `TARGET_ADDRESS` to `0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7` — this is the ETH token contract itself (same as `Constants.ETH_TOKEN_ADDRESS`). Checking the balance of a token contract for itself is confusing. Should use a placeholder like `"0x_YOUR_WALLET_ADDRESS"` or a real known wallet.

2. **No `:catch()` on metadata calls (lines 49-59)** — `name()`, `symbol()`, `decimals()` have no error handling. If the RPC call fails, the error propagates as an unhandled Promise rejection. In Roblox, evaera/promise logs a warning for unhandled rejections. Should either add `:catch()` or explain the omission.

3. **No module return** — Unlike leaderboard.luau and nft-gate.luau, this example doesn't return anything. Inconsistent.

4. **`balance.low` / `balance.high` access is correct** — AbiCodec decodes u256 as `{low: string, high: string}` where both are hex strings. The example correctly accesses `.low` and `.high`.

5. **Missing: human-readable balance formatting** — The example prints raw hex values like `"0x..."`. A good teaching example should show how to convert to human-readable amounts (divide by 10^18 for ETH). Even a comment acknowledging this would help.

6. **Good practices demonstrated:**
   - Using ERC20 preset instead of raw Contract + ABI
   - Using Constants module for known token addresses
   - Reading multiple tokens (ETH and STRK)
   - Minimal setup (read-only, no account needed)

**Rating: Adequate, fix TARGET_ADDRESS and add catch handlers**

---

### send-transaction.luau

**Status: Correct, comprehensive lifecycle**

**API Surface Accuracy:**
- `Account.fromPrivateKey({privateKey, provider})` — Correct
- `account:getPublicKeyHex()` — Method exists, delegates to signer
- `ERC20.new(Constants.ETH_TOKEN_ADDRESS, provider, account)` — Correct
- `ethToken:balance_of(account.address)` — Correct
- `ethToken:transfer(RECIPIENT, TRANSFER_AMOUNT)` — Correct; dynamic dispatch to `invoke()` which wraps `account:execute()`
- `account:waitForReceipt(txHash, {retryInterval = 5})` — Correct; `WaitOptions.retryInterval` exists (default is 5s anyway)

**Issues:**

1. **`tonumber(balance.low, 16)` bug (line 74)** — Same `0x` prefix issue. `tonumber("0x...", 16)` returns nil. The `or 0` fallback means `balanceNum = 0`. Then `tonumber(TRANSFER_AMOUNT, 16)` also returns nil → `transferNum = 0`. The check `0 < 0` never triggers, so the insufficient-balance guard is broken silently. Fix: use `tonumber(balance.low)` and `tonumber(TRANSFER_AMOUNT)`.

2. **`retryInterval = 5` is the default** — Specifying it is redundant. Consider changing to a non-default value (e.g., 3) to demonstrate the option, or add a "(default)" comment.

3. **Lua number overflow for large balances** — `tonumber()` uses f64, which loses precision above 2^53. ETH balances in wei commonly exceed this. The balance check is illustrative but technically unreliable for production. A comment acknowledging this would help.

4. **Good practices demonstrated:**
   - Full transaction lifecycle: setup → check balance → transfer → confirm → verify
   - Comments explaining each underlying step (nonce, fee estimation, hash, sign, submit)
   - Promise chain with single `:catch()` at the end — proper error propagation
   - Uses `account.address` as public property — correct
   - Transfer amount as hex constant with decimal comment

**Rating: Good, fix tonumber bug**

---

### Cross-Cutting Issues

#### 1. `tonumber(hexString, 16)` bug — affects 3/5 examples
Present in: `leaderboard.luau`, `nft-gate.luau`, `send-transaction.luau`

In Luau, `tonumber("0xFF", 16)` returns `nil` because the `0x` prefix is not a valid hex digit when an explicit base is specified. All RPC results and AbiCodec outputs use `0x`-prefixed hex strings. The `or 0` fallback silently masks the bug.

**Fix:** Use `tonumber(hexString)` which auto-detects the `0x` prefix. Or strip the prefix: `tonumber(string.sub(hexString, 3), 16)`.

#### 2. Inconsistent module return pattern
- leaderboard.luau and nft-gate.luau return utility function tables
- multicall.luau, read-contract.luau, and send-transaction.luau return nothing

**Recommendation:** Either all examples return a module table (for use as a ModuleScript) or none do (Script-style). Since these are game scripts (ServerScriptService), returning nothing is more idiomatic for Roblox Scripts. The leaderboard/nft-gate returns make sense because their utilities could be consumed by other scripts. Standardize by documenting the intent.

#### 3. No structured error handling
None of the examples use the SDK's `StarknetError` system (`:is()`, error codes, etc.). All error handling is `tostring(err)` in `:catch()` blocks.

**Recommendation:** At least one example should demonstrate:
```lua
:catch(function(err)
    if StarknetError.isStarknetError(err) and err:is("RpcError") then
        warn("RPC Error:", err.code, err.message)
    else
        warn("Unknown error:", tostring(err))
    end
end)
```

#### 4. No hardcoded-value centralization
All examples hardcode `"https://api.zan.top/public/starknet-sepolia"` for the RPC URL. This is fine for examples but could use `Constants.SN_SEPOLIA` for chain ID references. The RPC URL itself is provider-specific and can't be a constant, so this is acceptable.

#### 5. Roblox-only runtime
All examples use `game:GetService("ReplicatedStorage")` and `require(ReplicatedStorage:WaitForChild("StarknetLuau"))` — they are Roblox Studio-only. This is correct for the target audience. They would not run under Lune. This is fine but should be stated explicitly in a top-level examples README or in the SDK docs.

---

### Feature Coverage Gaps

The current 5 examples cover: read contract, send transaction, multicall, NFT gating, custom ABI. The SDK has significant features with **no example coverage:**

| Missing Example | SDK Module | Priority | Rationale |
|---|---|---|---|
| **Paymaster / sponsored tx** | `paymaster/SponsoredExecutor`, `paymaster/AvnuPaymaster` | **High** | Core differentiator for game UX — gasless transactions are critical for onboarding |
| **Deploy account** | `wallet/Account:deployAccount()` | **High** | Required for new player onboarding flow |
| **Event polling** | `provider/EventPoller` | **Medium** | Essential for reactive game logic (listening for on-chain events) |
| **Error handling** | `errors/StarknetError` | **Medium** | No example demonstrates structured error handling |
| **Batch account creation** | `wallet/AccountFactory:batchCreate/batchDeploy` | **Medium** | Key for game server bootstrapping multiple player accounts |
| **TypedData signing (SNIP-12)** | `wallet/TypedData` | **Low** | Advanced pattern, relevant for signed messages / meta-transactions |
| **Outside execution (SNIP-9)** | `wallet/OutsideExecution` | **Low** | Advanced pattern for delegated execution |
| **Provider features** | `provider/RequestQueue`, `ResponseCache`, `NonceManager` | **Low** | Opt-in performance features; could be shown in a "production config" example |

**Suggested new examples (by priority):**
1. `sponsored-transaction.luau` — Gasless game action using SponsoredExecutor + AvnuPaymaster
2. `deploy-account.luau` — Create and deploy a new player account on-chain
3. `event-listener.luau` — Poll for on-chain events and react in-game
4. `error-handling.luau` — Demonstrate StarknetError types, `:is()` checks, and recovery patterns

---

### Summary Table

| Example | API Correct? | Idiomatic? | Bugs | Error Handling | Teaching Quality |
|---|---|---|---|---|---|
| leaderboard.luau | ✅ Yes | ✅ Good (populate + execute) | ⚠️ tonumber | ✅ catch blocks | Good — custom ABI + multicall |
| multicall.luau | ✅ Yes | ✅ Excellent | None | ✅ catch block | Excellent — clean, focused |
| nft-gate.luau | ✅ Yes | ✅ Good | ⚠️ tonumber, identity no-op | ✅ catch + expect | Good — realistic Roblox pattern |
| read-contract.luau | ✅ Yes | ⚠️ Misleading target address | None | ⚠️ Missing on metadata | Adequate — needs cleanup |
| send-transaction.luau | ✅ Yes | ✅ Good | ⚠️ tonumber (breaks balance check) | ✅ catch block | Good — full lifecycle |

**Overall:** The examples are structurally sound and use the SDK API correctly. The primary bug (`tonumber` with `0x` prefix) is pervasive but easy to fix. The biggest gap is feature coverage — paymaster, deploy-account, and event polling are production-critical features with no example representation. multicall.luau is the gold standard; others should match its quality.
