# Claude Code Task: Implement OpenClaw Wallet Skill

## Context

You are implementing a self-custodial, chain-agnostic EVM blockchain wallet skill for OpenClaw AI Agents. The complete architecture has been through 12 rounds of audit. Every function has a JavaScript implementation in the spec — your job is to assemble them into working files, wire up the CLI, and verify it runs.

## Input Files

Read these files **in order** before writing any code:

1. **`DEV-SPEC.md`** — The authoritative spec. 1716 lines, 14 modules, 54 function implementations, 30 do-not-do rules. Every code block is copy-paste ready. Start here.

2. **`IMPLEMENTATION-GUIDE.md`** — 16 critical gotchas extracted from 12 audit rounds. Read this AFTER the spec. Each item describes a bug that will occur if you deviate from the spec.

3. **`default-config.json`** — Production config with 10 chains, 7 with Alchemy names, 3 bundler providers. Copy to `assets/default-config.json`.

4. **`SKILL.md`** — OpenClaw skill entry point. Copy to project root.

## Implementation Order

Follow DEV-SPEC §7 strictly — each round is independently testable:

### Round 1: Foundation (zero on-chain interaction)
```
① chains.js         — chain registry, resolveChainId, loadConfig, tokenInfo, getRpcUrl, publicClient
② keystore.js       — ethers encrypt/decrypt, AES-GCM signer cache, unlockAndCache, all CRUD functions
③ session.js        — HMAC session tokens, unlockWallet, validateSession, requireScope, lockWallet
④ tx-logger.js      — hash-chain audit log, logTransaction, getHistory, verifyIntegrity
⑤ tx-validator.js   — address validation, daily limits (parseFloat comparison), batch validation
⑥ signing.js        — signMessage, signTypedData
```

**Test Round 1**: `init` → `unlock` → `lock` → `change-password` → `export` → `verify-log` — all should produce valid JSON output, no network calls needed.

### Round 2: Direct transactions + balance (most critical)
```
⑦ balance.js        — getBalance, getAllowances, getTxStatus, getPortfolio
⑧ direct-tx.js      — sendDirect (EOA walletClient.sendTransaction)
⑨ tx-router.js      — selectMode, sendTransaction (unified entry)
```

**Test Round 2**: `balance --chain bsc` → should return JSON with native + token balances. `estimate --chain base --to 0x0...1 --amount 0.01` → should return gas estimate.

### Round 3: Gasless enhancement
```
⑩ bundler.js        — expandUrl, createClients (separate bundler/paymaster transports)
⑪ paymaster.js      — selectStrategy, isGaslessAvailable, paymasterFor (accepts paymasterClient param)
⑫ gasless-tx.js     — buildClient, sendGasless (strategy loop + inner nonce retry)
```

### Round 4: Optional + integration
```
⑬ eip7702.js        — upgradeVia7702 (optional)
⑭ wallet-cli.js     — commander CLI, all 26 commands, global options, defaultChain resolution
⑮ setup.sh          — npm install, create dirs, copy config, generate .session-secret
```

## Critical Rules

These are the mistakes previous spec versions made. Violating ANY of these creates a silent bug:

1. **`permissionless@^0.3` not `^0.2`**. Use `sendUserOperation({ calls: [...] })` — NOT `sendUserOperation({ callData: encodeCalls([...]) })`.

2. **Config `chains` keyed by name, not chainId**. `config.chains["bsc"]` not `config.chains["56"]`. Each entry has a `chainId` numeric field.

3. **Private key never leaves keystore.js**. `session.js` calls `unlockAndCache(sessionId, expires)` — it does NOT call `loadSigner()` and pass the key around.

4. **AES-GCM encrypted signer cache**, never plaintext. `.signer-cache/*.key` files are `iv(12) + tag(16) + ciphertext`.

5. **`JSON.stringify(obj, null, indent)`** — 2nd arg is replacer, not indent. Previous spec had this wrong.

6. **BSC USDC/USDT are 18 decimals**. Never hardcode `decimals = 6` for stablecoins.

7. **`waitForTransactionReceipt({ hash, timeout: 120_000 })`** — always set timeout or stuck tx hangs the agent forever.

8. **`buildClient` outside the nonce retry loop**. Build once per strategy, retry only `sendUserOperation`.

9. **`paymasterFor(chainId, strategy, paymasterClient)`** — receives paymasterClient as param, does NOT call `createClients` internally.

10. **`checkDailyLimit` resolves null asset to `viemChain(chainId).nativeCurrency.symbol`** — otherwise native transfers bypass limits.

11. **CLI pre-hook skips `loadConfig()` for `init`, `import`, `lock`, `verify-log`, `export`, `change-password`** — config doesn't exist before setup.

12. **`getHistory` returns `[]` when `tx-log.jsonl` doesn't exist** — otherwise the first transaction ever fails validation.

13. **Alchemy bundler URLs need `alchemyName`** (e.g. `"base-mainnet"`). Config has this field; `expandUrl` checks it.

## Project Structure

```
wallet-skill/
├── SKILL.md
├── package.json                    { "type": "module", "engines": { "node": ">=20" } }
├── scripts/
│   ├── setup.sh
│   ├── wallet-cli.js
│   └── lib/
│       ├── chains.js
│       ├── keystore.js
│       ├── session.js
│       ├── tx-router.js
│       ├── direct-tx.js
│       ├── gasless-tx.js
│       ├── balance.js
│       ├── bundler.js
│       ├── paymaster.js
│       ├── eip7702.js
│       ├── signing.js
│       ├── tx-validator.js
│       └── tx-logger.js
└── assets/
    └── default-config.json
```

## Dependencies

```bash
npm install viem@^2.46 permissionless@^0.3 ethers@^6.13 commander@^12.0
```

No other dependencies. No chalk, no dotenv, no extra packages.

## Runtime Directory

```
~/.openclaw-wallet/                 0o700
├── keystore.enc                    0o600
├── meta.json                       0o600
├── config.json                     0o600
├── .session-secret                 0o600
├── .signer-cache/                  0o700
│   └── wlt_<hex>.key               0o600
├── sessions/                       0o700
│   └── wlt_<hex>.json
└── tx-log.jsonl                    0o600
```

## Verification Checklist

After implementation, run the acceptance test from DEV-SPEC §6:

```bash
export WALLET_PASSWORD="test-pwd-123"

# Must all produce valid JSON:
bash scripts/setup.sh
node scripts/wallet-cli.js init
TOKEN=$(node scripts/wallet-cli.js unlock | python3 -c "import sys,json;print(json.load(sys.stdin)['sessionToken'])")
node scripts/wallet-cli.js balance --token $TOKEN --chain bsc
node scripts/wallet-cli.js chain-info --chain bsc
node scripts/wallet-cli.js estimate --to 0x0000000000000000000000000000000000000001 --amount 0.01 --chain bsc
WALLET_PASSWORD=wrong node scripts/wallet-cli.js unlock  # must return error JSON
node scripts/wallet-cli.js verify-log
node scripts/wallet-cli.js lock
node scripts/wallet-cli.js balance --token $TOKEN --chain bsc  # must return "Invalid or expired session token"
```

## How to Use the Spec

The DEV-SPEC contains complete JavaScript for every function. For each module:

1. Read the **Imports** section → copy the exact import lines
2. Read the **Constants** section (if any) → copy
3. Read each **function body** code block → copy into the file
4. Wire up exports

Do NOT invent alternative implementations. The spec's code has been audited for:
- Correct viem/permissionless 0.3 API usage
- Hash chain consistency between logTransaction and verifyIntegrity
- HMAC timing-safe comparison
- AES-GCM IV/tag/ciphertext format
- Cross-module parameter passing (especially paymasterFor's 3rd param)

If something seems missing, check IMPLEMENTATION-GUIDE.md — it likely addresses your concern.

## Start

Begin with Round 1. Create `package.json`, then implement `chains.js` → `keystore.js` → `session.js` → `tx-logger.js` → `tx-validator.js` → `signing.js`. After each file, verify it has no syntax errors with `node -c scripts/lib/<file>.js`.
