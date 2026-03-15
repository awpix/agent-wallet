# Implementation Guide — Critical Gotchas

> Read DEV-SPEC.md first. This guide highlights the non-obvious decisions that 8 rounds of architecture audit uncovered. Each item here caused a bug, security issue, or implementation blocker in earlier spec versions.

---

## Critical Gotchas That Will Break Your Implementation

### 0. Config `chains` is keyed by chain NAME, not chainId

```javascript
// ❌ WRONG — chainId as key
config.chains["56"].tokens.USDC

// ✅ CORRECT — chain name as key, chainId is a field inside
config.chains["bsc"].tokens.USDC   // → { address: "0x8AC7...", decimals: 18 }
config.chains["bsc"].chainId       // → 56
```

`rpcOverrides` also uses chain name keys. The `chainConfig()` function accepts both name and chainId (with chainId doing a scan), but name is the fast path.

### 1. permissionless 0.3 API — `calls`, not `callData`

```javascript
// ❌ WRONG (0.2 API — will silently send empty UserOp)
const hash = await smartAccountClient.sendUserOperation({
  callData: await smartAccount.encodeCalls([{ to, value, data }])
})

// ✅ CORRECT (0.3 API — internal encoding)
const hash = await smartAccountClient.sendUserOperation({
  calls: [{ to, value, data }]
})
```

Do NOT use `encodeCalls` at all. permissionless 0.3 handles encoding internally.

### 2. BSC tokens are 18 decimals, not 6

```
BSC USDC: 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d → 18 decimals
BSC USDT: 0x55d398326f99059fF775485246999027B3197955 → 18 decimals
```

If you hardcode `decimals = 6` for stablecoins, a "100 USDT" transfer on BSC will send 0.0000000001 USDT. **Always read decimals from config.json or on-chain.**

### 3. AES-GCM signer cache — never write plaintext privateKey to disk

The `.signer-cache/*.key` files must be AES-256-GCM encrypted (key from SHA-256 of password). Writing plaintext privateKey to disk creates a critical security regression — anyone with a disk backup gets full wallet access.

### 4. `unlockAndCache()` keeps privateKey inside keystore.js

The `session.js → unlockWallet()` function must call `keystore.js → unlockAndCache(sessionId, expires)`. Do NOT have session.js call `loadSigner()` and then separately write the cache — that would require privateKey to pass through session.js, violating the "ethers.js boundary stays in keystore.js" constraint.

### 5. Each CLI command is an independent Node.js process

```bash
node wallet-cli.js unlock    # Process A starts, runs, exits
node wallet-cli.js send ...  # Process B starts — NO shared memory with A
```

This means:
- In-memory variables (`let cache = ...`) reset to null every command
- Signer cache MUST use files (AES-encrypted), not in-process variables
- Config cache per-process is fine (each process lives < 5s)

### 6. `sendUserOperation` returns a UserOp hash, NOT a tx hash

```javascript
const userOpHash = await smartAccountClient.sendUserOperation({ calls: [...] })
// userOpHash is a bundler-internal identifier — NOT visible on Etherscan

const receipt = await bundlerClient.waitForUserOperationReceipt({ hash: userOpHash })
const txHash = receipt.receipt.transactionHash  // ← THIS is the on-chain hash
```

Always wait for receipt and return `transactionHash`, not `userOpHash`.

### 6b. Bundler URL ≠ Paymaster URL

For Pimlico, both happen to be the same endpoint. But for Alchemy and Stackup, they are different:
- Alchemy bundler: `{chainName}-bundler.g.alchemy.com` vs paymaster: `{chainName}-paymaster.g.alchemy.com`
- Stackup bundler: `api.stackup.sh/v1/node/` vs paymaster: `api.stackup.sh/v1/paymaster/`

`createClients()` must build **separate** transport arrays using `bundlerUrlTemplate` and `paymasterUrlTemplate` respectively. Using the same transport for both will silently send paymaster requests to the bundler endpoint.

### 6c. Nonce retry must retry the SAME strategy

```javascript
// ❌ WRONG — `continue` in outer for-of loop skips to NEXT strategy
for (const strategy of strategies) {
  try { ... }
  catch (err) {
    if (err.message?.includes("nonce")) continue  // jumps to next strategy!
  }
}

// ✅ CORRECT — inner retry loop stays on same strategy
for (const strategy of strategies) {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try { ... }
    catch (err) {
      if (err.message?.includes("nonce") && attempt < MAX_RETRIES) continue  // retries same strategy
      if (err.message?.includes("paymaster")) break  // exits inner loop → next strategy
    }
  }
}
```

### 7. Public RPCs will fail for production transactions

viem built-in chains use public RPC endpoints (Cloudflare, Ankr, etc.) that rate-limit at 10-25 req/s. Direct transactions WILL fail intermittently. Always check `config.json → rpcOverrides` first (keyed by chain name):

```javascript
const rpc = config.rpcOverrides?.["bsc"] || chain.rpcUrls.default.http[0]
```

### 8. `waitForTransactionReceipt` needs a timeout

Without timeout, a stuck transaction (gas too low) will hang the agent process forever:

```javascript
// ❌ No timeout — hangs on stuck tx
await client.waitForTransactionReceipt({ hash })

// ✅ With timeout
await client.waitForTransactionReceipt({ hash, timeout: 120_000, confirmations: 1 })
```

### 9. EOA address ≠ Smart Account address

They are two completely different addresses. When querying balance:
- Check BOTH `meta.json → address` (EOA) and `meta.json → smartAccounts[chainId]` (Smart Account)
- User's funds may be in either address depending on which mode they used
- Note: `meta.json → smartAccounts` is keyed by **numeric chainId** (e.g. `"56"`), unlike config.json chains which are keyed by name (e.g. `"bsc"`). This is because Smart Account addresses are per chain ID, not per config entry.

### 10. EIP-7702 upgrade itself needs gas — it's a chicken-and-egg problem

`walletClient.sendTransaction({ authorizationList })` is a regular Ethereum transaction that requires native gas. If the EOA has no ETH, the 7702 upgrade will fail. Check balance first and throw a helpful error pointing to `deploy-4337` as the gasless alternative.

### 11. `paymasterFor` takes a `paymasterClient` parameter — don't create clients inside it

`buildClient` calls `createClients(chainId)` once, getting both `bundlerClient` and `paymasterClient`. It passes `paymasterClient` to `paymasterFor(chainId, strategy, paymasterClient)`. Do NOT have `paymasterFor` call `createClients` internally — that creates duplicate HTTP connections to the bundler for every single gasless transaction.

### 12. Native transfers bypass daily limits if `asset` is null

When the user sends native ETH/BNB without `--asset`, the CLI passes `asset: undefined` to `validateTransaction`. But `sendDirect` logs it as `asset: "ETH"`. If `checkDailyLimit` compares `e.asset === undefined`, it matches nothing — native transfers bypass all limits. The fix: `checkDailyLimit` resolves null asset to `viemChain(chainId).nativeCurrency.symbol` before comparing.

### 13. `init` and `import` must not call `loadConfig()`

The CLI pre-hook reads `loadConfig().defaultChain` to resolve `--chain`. But `init` runs before any config exists. The pre-hook must skip config loading for commands that don't need chain context: `init`, `import`, `lock`, `verify-log`, `export`, `change-password`.

---

## Module Dependency Graph

```
wallet-cli.js
  ├── tx-router.js (unified write entry)
  │     ├── direct-tx.js (DEFAULT path)
  │     │     ├── keystore.js → loadSigner (AES cache → scrypt fallback)
  │     │     └── chains.js → getRpcUrl, publicClient, tokenInfo
  │     │
  │     └── gasless-tx.js (GASLESS path)
  │           ├── keystore.js
  │           ├── bundler.js → fallback transport
  │           ├── paymaster.js → strategy queue
  │           └── chains.js
  │
  ├── balance.js (read-only, NO bundler dependency)
  │     ├── keystore.js → getAddress (EOA + Smart Account)
  │     └── chains.js → publicClient, tokenInfo
  │
  ├── signing.js → keystore.js → loadSigner
  ├── session.js → keystore.js → unlockAndCache
  ├── tx-validator.js → keystore.js + tx-logger.js + chains.js
  └── eip7702.js (optional)
```

**Key insight**: `balance.js`, `signing.js`, and `direct-tx.js` have ZERO dependency on `bundler.js` or `paymaster.js`. A wallet without any Pimlico API key can still do everything except gasless transactions.

---

## Environment Variables

| Variable | Required | Used By |
|----------|----------|---------|
| `WALLET_PASSWORD` | For write ops | keystore.js, session.js |
| `NEW_WALLET_PASSWORD` | change-password only | keystore.js |
| `PIMLICO_API_KEY` | For gasless | bundler.js |
| `ALCHEMY_API_KEY` | Optional fallback | bundler.js, chains.js (rpcOverrides) |
| `STACKUP_API_KEY` | Optional fallback | bundler.js |

---

## Testing Strategy

**Round 1 tests** (no network needed):
- `init` → verify keystore.enc is valid V3 JSON
- `unlock` → verify session file has HMAC
- `lock` → verify sessions/ and .signer-cache/ are empty
- `change-password` → verify old password fails, new works
- Wrong password → verify friendly error message

**Round 2 tests** (needs RPC):
- `balance --chain base` → verify returns JSON with balances
- `balance --chain bsc` → verify BSC works (different chain)
- `balance --asset 0x...` → verify on-chain decimals query

**Round 3 tests** (needs PIMLICO_API_KEY + testnet):
- `send --mode gasless --chain base-sepolia` → verify gasless flow
- All strategies fail → verify error message

**Round 4 tests** (integration):
- `estimate` → verify gas numbers are reasonable
- `chain-info --chain bsc` → verify gasless availability detection
