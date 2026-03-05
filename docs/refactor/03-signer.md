## 3. signer/

### StarkSigner.luau
_78 lines. Stark curve signer wrapping ECDSA operations behind a clean interface._

- `[ok]` Clean, minimal wrapper — 78 lines total. Single responsibility: key management + signing delegation.
- `[ok]` Constructor validates private key range `[1, N-1]` with structured `SigningError` errors. Consistent with ECDSA.sign() internal validation.
- `[ok]` Lazy public key derivation: `getPubKey()` caches the expensive EC scalar multiplication on first call. Subsequent calls return the cached `AffinePoint` (same table reference, verified in tests).
- `[ok]` Deterministic signing via ECDSA.sign() — no redundant validation or re-implementation. The signer is a pure facade.
- `[ok]` Proper error codes: `INVALID_PRIVATE_KEY` for zero key, `KEY_OUT_OF_RANGE` for key >= N.

- `[refactor]` **Dual signing on `signTransaction()`.** `signTransaction()` (line 73) calls `ECDSA.sign()` directly instead of delegating to `self:signRaw()`. This means `signTransaction` and `signRaw` are two independent entry points into ECDSA, making it harder to add instrumentation, logging, or rate limiting at a single chokepoint. Should be:
  ```luau
  function StarkSignerClass:signTransaction(txHash: buffer): { string }
      local sig = self:signRaw(txHash)  -- delegate instead of ECDSA.sign()
      return { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }
  end
  ```
  Functionally identical, but channels all signing through one method.

- `[refactor]` **`signRaw` + hex conversion duplicated in Account:signMessage().** `Account:signMessage()` (Account.luau:741-742) does `self.signer:signRaw(hashBuf)` then `{ BigInt.toHex(sig.r), BigInt.toHex(sig.s) }` — this is exactly what `signTransaction()` already does. The Account method reimplements the buffer→hex conversion instead of calling `signTransaction()`. This creates two code paths that produce identical `{ string }` output from a hash buffer:
  1. `StarkSigner:signTransaction(buf)` → used by TransactionBuilder
  2. `Account:signMessage()` → `signer:signRaw(buf)` + manual `BigInt.toHex()` → used by SNIP-12, paymaster, outside execution

  **Fix:** `Account:signMessage()` should call `self.signer:signTransaction(hashBuf)` directly:
  ```luau
  function Account:signMessage(typedData: { [string]: any }): { string }
      local msgHash = self:hashMessage(typedData)
      local hashBuf = BigInt.fromHex(msgHash)
      return self.signer:signTransaction(hashBuf)  -- reuse signTransaction
  end
  ```
  Eliminates the duplicate `BigInt.toHex(sig.r), BigInt.toHex(sig.s)` pattern.

- `[refactor]` **Naming asymmetry: `signTransaction` vs `signRaw`.** The method `signTransaction()` doesn't do anything transaction-specific — it just signs a hash and returns hex strings. A message hash and a transaction hash go through the exact same code path. The name implies it has transaction-specific logic (nonce, calldata, etc.) when it's really just `signToHex()`. Consider renaming to `signToHexArray()` or `signHex()` to clarify it works on any hash, not just transaction hashes. This would also make it more natural for `Account:signMessage()` to call it.

- `[refactor]` **Redundant private key validation between StarkSigner and ECDSA.** `StarkSigner.new()` (lines 27-37) validates `privateKey ∈ [1, N-1]`. `ECDSA.sign()` (lines 218-228) performs the **exact same validation** again on every call. Since the signer stores the validated key and passes it through, the ECDSA-level check is redundant for signer-mediated calls. Two options:
  - **Keep both (current approach):** Defense-in-depth. ECDSA stays safe for direct callers who bypass StarkSigner. Minor perf cost (two BigInt comparisons per sign).
  - **Remove ECDSA validation:** ECDSA becomes a "trusted internal" layer, signer enforces the contract. Saves 2 BigInt comparisons per sign. Risk: direct ECDSA callers lose validation.
  - **Recommendation:** Keep both for now — the perf cost is negligible and the safety is worth it. But document the intentional redundancy so future maintainers don't "optimize" one away without understanding the tradeoff.

- `[api]` **No `Signer` interface type exported.** The signer is consumed duck-typed everywhere:
  - `TransactionBuilder.Account.signer` (TransactionBuilder.luau:18-20) defines its own inline type: `{ signTransaction: (self: any, txHash: buffer) -> { string } }`
  - `Account.new()` (Account.luau:429) accepts `signer: any` — no type constraint at all
  - `AccountFactory._createAccountFromSigner()` (AccountFactory.luau:63) accepts `signer: any`
  - `Account:signMessage()` (Account.luau:741) calls `signer:signRaw()` — a method not in TransactionBuilder's type
  - The dummy signer in `getDeploymentFeeEstimate` (Account.luau:227-233) implements only `signTransaction`

  This means there are **two implicit signer interfaces** in the SDK:
  1. **Minimal (TransactionBuilder):** `{ signTransaction(self, buffer) -> {string} }` — used for tx signing + fee estimation
  2. **Full (Account):** `{ signTransaction, signRaw, getPubKey, getPublicKeyHex }` — used for SNIP-12, address derivation, deploy

  **Recommendation:** Export a formal `Signer` type from `src/signer/StarkSigner.luau` (already there as `StarkSigner` type, line 11-16) and use it in Account.new() and AccountFactory instead of `any`. Define a `MinimalSigner` type for TransactionBuilder's narrower requirement. This makes the contract explicit and helps catch errors at type-check time.

- `[api]` **`getPubKey()` returns full `AffinePoint` (x, y) but only `x` is ever used.** Every consumer calls `getPublicKeyHex()` which extracts only `pubKey.x`. The raw `AffinePoint` (including `y`) is never used outside tests. `getPubKey()` exposes internal crypto details that most consumers don't need. Not a bug, but worth documenting that `getPublicKeyHex()` is the intended public API for most use cases.

- `[api]` **Private key is stored as a BigInt buffer (`self._privateKey`) with no accessor.** There's no `getPrivateKeyHex()` method, which is correct from a security perspective — private keys should not be casually extractable. However, there's also no way to serialize/restore a signer for persistence. If account recovery or export is ever needed, this would require a new method. Document the intentional omission.

- `[type]` **Constructor return type is `any` (line 44: `return self :: any`).** The exported `StarkSigner` type (lines 11-16) is well-defined, but the `:: any` cast erases it at the constructor boundary. Callers of `StarkSigner.new()` get `any` instead of `StarkSigner`. This is a Luau limitation with `setmetatable` patterns — the cast is necessary to avoid type errors with the metatable approach. Document this as a known limitation.

- `[test]` 21 tests — **well-structured, low redundancy, excellent coverage given the module's simplicity.**
  - 5 constructor tests (valid keys, zero rejection, N rejection, prefix handling)
  - 4 getPubKey tests (correctness, caching, @scure/starknet vector)
  - 2 getPublicKeyHex tests (format, prefix)
  - 7 signRaw tests (output shape, determinism, ECDSA equivalence, cross-reference vector, verifiability)
  - 8 signTransaction tests (array format, hex prefix, signRaw equivalence, cross-reference vector, verifiability)
  - 2 multi-signer tests (key isolation, signature isolation)
- `[test]` **Missing: error message content assertions.** Tests use `:toThrowType("SigningError")` but don't verify the error code is `INVALID_PRIVATE_KEY` vs `KEY_OUT_OF_RANGE`. If error codes were swapped, tests would still pass.
- `[test]` **Missing: private key near boundary N-1.** Tests validate `key == 0` (rejected) and `key >= N` (rejected) but don't test `key == N-1` (should succeed) or `key == N+1` (should fail). Boundary testing is important for the `[1, N-1]` range.
- `[test]` **Missing: signing with edge-case hashes.** No test for `signRaw(BigInt.zero())` or `signRaw(BigInt.fromHex(N_hex))` — extreme hash values that stress the `bits2intModN` path.

### signer/init.luau (barrel)
_9 lines. Re-exports StarkSigner._

- `[ok]` Clean barrel export, no logic.
- `[ok]` Uses Roblox-style `require(script.StarkSigner)` — correct for runtime barrel.
- `[api]` Returns `{ StarkSigner = StarkSigner }` table. Consistent with other barrel exports.

---

### signer/ Module Summary

| Metric | Value |
|--------|-------|
| **Total lines** | 87 (78 + 9) |
| **Total public functions** | 5 (new, getPubKey, getPublicKeyHex, signRaw, signTransaction) |
| **Total tests** | 21 |
| **Test vectors** | 2 (@scure/starknet cross-reference) |
| **Production callers** | 7 (TransactionBuilder ×2, Account ×5) |
| **Code duplication** | 1 significant (signRaw→hex in Account:signMessage) |
| **Implicit interfaces** | 2 (full StarkSigner, minimal signTransaction-only) |
| **DRY violations** | 2 (signTransaction bypasses signRaw, Account reimplements hex conversion) |

### Priority Actions (signer/)

1. **HIGH — Fix Account:signMessage() to use signTransaction().** Replace `signer:signRaw(buf)` + manual hex conversion with `signer:signTransaction(buf)`. Eliminates the duplicated `BigInt.toHex(sig.r), BigInt.toHex(sig.s)` pattern across two files. One-line fix.
2. **HIGH — Fix signTransaction() to delegate to signRaw().** Change `ECDSA.sign(txHash, self._privateKey)` to `self:signRaw(txHash)`. Channels all signing through one method, making instrumentation easier.
3. **MEDIUM — Export formal Signer interface types.** Define and export `Signer` (full) and `MinimalSigner` (signTransaction-only) types. Use them in Account.new(), AccountFactory, and TransactionBuilder instead of `any`. Makes the implicit contract explicit.
4. **MEDIUM — Add boundary tests.** Test `key == N-1` (valid), `key == N+1` (invalid), `signRaw(zero_hash)`, `signRaw(N_hash)`. Add error code assertions to constructor error tests.
5. **LOW — Consider renaming signTransaction → signHex.** The method has no transaction-specific logic — it signs any hash and returns hex. Current name is misleading and discourages reuse for non-transaction signing (which Account:signMessage() needs). This is a breaking API change, so weigh against stability.
6. **LOW — Document intentional redundant validation.** StarkSigner.new() and ECDSA.sign() both validate the private key range. Add a comment in ECDSA.sign() noting this is defense-in-depth for direct callers.

---

### Signer Cross-Cutting Audit — All Signing Flows

_Complete audit of every signing operation across the SDK, tracing from user-facing API to ECDSA._

**Flow 1: Transaction Execution (INVOKE V3)**
```
Account:execute(calls, options)
  → TransactionBuilder:execute(account, calls, options)
    → TransactionHash.calculateInvokeTransactionHash(...) → hex string
    → BigInt.fromHex(txHash) → buffer
    → account.signer:signTransaction(buffer) → { "0x...", "0x..." }
      → ECDSA.sign(txHash, privateKey) → { r: buffer, s: buffer }
    → RPC: addInvokeTransaction({ signature = [...] })
```

**Flow 2: Account Deployment (DEPLOY_ACCOUNT V3)**
```
Account:deployAccount(options)
  → TransactionBuilder:deployAccount(account, params, options)
    → TransactionHash.calculateDeployAccountTransactionHash(...) → hex string
    → BigInt.fromHex(txHash) → buffer
    → account.signer:signTransaction(buffer) → { "0x...", "0x..." }
      → ECDSA.sign(txHash, privateKey) → { r: buffer, s: buffer }
    → RPC: addDeployAccountTransaction({ signature = [...] })
```

**Flow 3: SNIP-12 Message Signing**
```
Account:signMessage(typedData)
  → TypedData.getMessageHash(typedData, address) → hex string
  → BigInt.fromHex(msgHash) → buffer
  → self.signer:signRaw(buffer) → { r: buffer, s: buffer }     ← DIFFERENT PATH
  → { BigInt.toHex(sig.r), BigInt.toHex(sig.s) }               ← MANUAL HEX CONVERSION
```
**Issue:** This flow bypasses `signTransaction()` and reimplements the hex conversion. Should use `signTransaction()` for consistency.

**Flow 4: Paymaster-Sponsored Execution**
```
Account:executeWithPaymaster(paymaster, calls, options)
  → AvnuPaymaster:buildTypedData(...) → TypedData
  → Account:signMessage(typedData) → { "0x...", "0x..." }     (uses Flow 3)
  → AvnuPaymaster:executeTransaction(address, typedData, signature)
```

**Flow 5: Paymaster-Sponsored Deployment**
```
Account:deployWithPaymaster(paymaster, options)
  → AvnuPaymaster:buildTypedData(...) → TypedData
  → Account:signMessage(typedData) → { "0x...", "0x..." }     (uses Flow 3)
  → AvnuPaymaster:executeTransaction(address, typedData, signature, { deploymentData })
```

**Flow 6: Fee Estimation (Dummy Signer)**
```
Account.getDeploymentFeeEstimate(config)
  → dummyAccount.signer.signTransaction(_self, _hash) → { "0x0", "0x0" }
  → TransactionBuilder:estimateDeployAccountFee(dummyAccount, params)
  → RPC: estimateFee({ ..., signature = ["0x0", "0x0"], SKIP_VALIDATE })
```

**Flow 7: OutsideExecution Tests (Direct ECDSA)**
```
tests/wallet/OutsideExecution.spec.luau:
  → TypedData.getMessageHash(td, address) → hex string
  → BigInt.fromHex(msgHash) → buffer
  → signer:signRaw(buffer) → { r: buffer, s: buffer }
  → ECDSA.verify(hashBuf, pubKeyPoint, sig)
```
**Note:** Tests use `signRaw()` directly for verification roundtrip. This is appropriate for unit tests.

**Summary of signing entry points:**

| Entry Point | Method Used | Output Format | Callers |
|-------------|-------------|---------------|---------|
| Transaction signing | `signTransaction(buffer)` | `{ string }` (hex array) | TransactionBuilder.execute, TransactionBuilder.deployAccount |
| Message signing | `signRaw(buffer)` + manual hex | `{ string }` (hex array) | Account.signMessage |
| Verification prep | `signRaw(buffer)` | `{ r: buffer, s: buffer }` | OutsideExecution tests |
| Fee estimation | dummy `signTransaction` | `{ "0x0", "0x0" }` | Account.getDeploymentFeeEstimate |

**Key Finding:** All four entry points ultimately produce the same final format (`{ string }`) but through two different code paths. Unifying Flow 3 to use `signTransaction()` would reduce this to one production path.
