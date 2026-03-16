---
name: wallet
description: >
  Self-custodial EVM blockchain wallet for sending tokens, checking balances,
  and managing crypto assets. Supports all EVM chains (Ethereum, Base, BSC,
  Arbitrum, Polygon, Avalanche, etc.). Use when the user wants to send crypto,
  check wallet balance, sign messages, estimate gas fees, or manage token
  approvals. Supports gasless transactions via ERC-4337 when native gas is
  unavailable.
---

# AWP Wallet Skill

A chain-agnostic EVM wallet that lets you manage crypto assets across all EVM-compatible blockchains.

## Installation

```bash
# Install dependencies and register the awp-wallet command
bash scripts/setup.sh

# Verify installation
awp-wallet --version
```

After setup, the `awp-wallet` command is available globally. If `npm link` fails (non-root), use `node scripts/wallet-cli.js` directly instead.

### Requirements

- **Node.js >= 20**
- **npm >= 9**
- 4 dependencies: `viem@^2.46`, `permissionless@^0.3`, `ethers@^6.13`, `commander@^12.0`

### Project Structure

```
awp-wallet/
├── SKILL.md                        # This file — skill metadata + usage guide
├── package.json                    # npm package with "bin": { "awp-wallet": ... }
├── scripts/
│   ├── setup.sh                    # One-click install + directory provisioning
│   ├── wallet-cli.js               # CLI entry point (26 commands)
│   └── lib/
│       ├── chains.js               # Chain registry (400+ built-in + custom)
│       ├── keystore.js             # ethers.js encryption + AES-GCM signer cache
│       ├── session.js              # HMAC-signed session tokens
│       ├── tx-router.js            # Transaction mode routing (direct vs gasless)
│       ├── direct-tx.js            # EOA direct transactions (default path)
│       ├── gasless-tx.js           # ERC-4337 Smart Account transactions
│       ├── balance.js              # Balance queries (no bundler dependency)
│       ├── bundler.js              # Multi-provider fallback transport
│       ├── paymaster.js            # Gas sponsorship strategy detection
│       ├── eip7702.js              # Optional EOA delegation
│       ├── signing.js              # EIP-191/712 message signing
│       ├── tx-validator.js         # Address validation + transaction limits
│       └── tx-logger.js            # Hash-chain audit log
├── assets/
│   └── default-config.json         # Default config (10 chains, 3 bundler providers)
└── tests/
    ├── helpers/setup.js            # Isolated test environment utilities
    ├── integration/                # 8 module-level test files (111 tests)
    └── e2e/                        # 3 end-to-end test files (33 tests)
```

### Runtime Directory

Created by `setup.sh` at `~/.openclaw-wallet/`:

```
~/.openclaw-wallet/                 0o700
├── keystore.enc                    0o600  Encrypted wallet (ethers V3 format)
├── meta.json                       0o600  Wallet address + smart account registry
├── config.json                     0o600  Chain config, limits, bundler providers
├── .session-secret                 0o600  32-byte HMAC key for session tokens
├── .signer-cache/                  0o700  AES-256-GCM encrypted private key cache
│   ├── .salt                       0o600  scrypt salt for cache key derivation
│   └── wlt_<hex>.key               0o600  iv(12) + tag(16) + ciphertext
├── sessions/                       0o700  Session token files
│   └── wlt_<hex>.json                     HMAC-signed session data
└── tx-log.jsonl                    0o600  Append-only transaction audit log
```

## Secret Management (IMPORTANT)

The wallet requires a `WALLET_PASSWORD` to encrypt/decrypt the keystore. OpenClaw **must** store this password securely:

### Requirements for OpenClaw

1. **Generate a strong random password** (minimum 32 characters, cryptographically random) at wallet initialization time. Do NOT let users choose weak passwords.

   ```bash
   # Example: generate a 48-char random password
   WALLET_PASSWORD=$(openssl rand -base64 36)
   ```

2. **Store the password in OpenClaw's encrypted secret store**, never in plaintext config files, environment files, or logs. Treat `WALLET_PASSWORD` with the same security level as a database master key.

3. **Inject as environment variable only at call time**. The password must exist in the process environment only for the duration of the CLI command, never persisted to disk in plaintext.

   ```bash
   # CORRECT: inject per-command, password from secure store
   WALLET_PASSWORD="$STORED_SECRET" awp-wallet unlock

   # WRONG: written to .env file on disk
   echo "WALLET_PASSWORD=xxx" >> .env  # NEVER DO THIS
   ```

4. **Never log the password**. Ensure OpenClaw's logging framework redacts `WALLET_PASSWORD` from command logs, audit trails, and error reports.

5. **Rotate on compromise**. If the secret store is breached, immediately run `change-password`:
   ```bash
   WALLET_PASSWORD="$OLD" NEW_WALLET_PASSWORD="$NEW" awp-wallet change-password
   ```

### Environment Variables

| Variable | Storage | Required | Used By |
|----------|---------|----------|---------|
| `WALLET_PASSWORD` | **Encrypted secret store** | For write ops | keystore, session |
| `NEW_WALLET_PASSWORD` | **Encrypted secret store** | change-password only | keystore |
| `PIMLICO_API_KEY` | Secret store or config | Optional (gasless) | bundler |
| `ALCHEMY_API_KEY` | Secret store or config | Optional (RPC/bundler) | chains, bundler |
| `BSC_RPC_URL` | Config | Optional (BSC RPC) | chains |

## Quick Start

```bash
# 1. Create a new wallet
WALLET_PASSWORD="$SECRET" awp-wallet init
# Returns: { "status": "created", "address": "0x..." }

# 2. Unlock (creates a session token for subsequent commands)
WALLET_PASSWORD="$SECRET" awp-wallet unlock --duration 3600
# Returns: { "sessionToken": "wlt_abc123...", "expires": "..." }

# 3. Check balance (no password needed — session token only)
awp-wallet balance --token wlt_abc123 --chain bsc
awp-wallet balance --token wlt_abc123 --chain base

# 4. Send tokens (password needed for signing)
WALLET_PASSWORD="$SECRET" awp-wallet send \
  --token wlt_abc123 --to 0xRecipient --amount 50 --asset usdc --chain base

# 5. Lock when done (no password needed)
awp-wallet lock
```

### Output Format

All commands output JSON to stdout. Errors output JSON to stderr with exit code 1:

```json
// Success
{ "status": "created", "address": "0x..." }

// Error
{ "error": "Wrong password — decryption failed." }
```

Use `--pretty` for indented output: `awp-wallet balance --token T --chain bsc --pretty`

## How It Works

### Two Transaction Modes

1. **Direct mode** (default when you have native gas): Standard EOA transaction via viem. 21k gas for ETH, ~65k for ERC-20. No external dependencies — works even when bundler services are down.

2. **Gasless mode** (automatic when no native gas, or `--mode gasless`): ERC-4337 Smart Account via Bundler + Paymaster. Gas is paid by the Paymaster (free or in USDC). Requires PIMLICO_API_KEY.

The wallet automatically picks the best mode based on your native gas balance. Override with `--mode direct` or `--mode gasless`.

### Chain Support

Works on **all EVM chains**. Use chain name or ID:
- `--chain ethereum`, `--chain base`, `--chain bsc`, `--chain arbitrum`
- `--chain 56`, `--chain 43114`, `--chain 250`
- Custom chains: `--chain 99999 --rpc-url https://your-rpc.com`

When `--chain` is omitted, the default chain from `config.json` is used (default: `"bsc"`).

### Token Support

Use symbol (preconfigured chains) or contract address (any chain):
- `--asset usdc`, `--asset weth`
- `--asset 0x55d398326f99059fF775485246999027B3197955` (auto-detects decimals on-chain)

### Preconfigured Chains (10)

| Chain | ID | Tokens | Gasless |
|-------|----|--------|---------|
| Ethereum | 1 | USDC, USDT, DAI, WETH, WBTC | Yes (ERC-20 paymaster) |
| Base | 8453 | USDC, USDT, DAI, WETH | Yes (verifying paymaster) |
| BSC | 56 | USDC (18dec), USDT (18dec), WBNB | Yes (ERC-20 paymaster) |
| Arbitrum | 42161 | USDC, USDT, WETH, WBTC | Yes (ERC-20 paymaster) |
| Optimism | 10 | USDC, USDT, WETH | Yes (verifying paymaster) |
| Polygon | 137 | USDC, USDT, WETH | Yes (ERC-20 paymaster) |
| Avalanche | 43114 | USDC, USDT, WAVAX | Yes (ERC-20 paymaster) |
| Fantom | 250 | USDC, WFTM | Yes (ERC-20 paymaster) |
| Base Sepolia | 84532 | USDC | Yes (verifying paymaster) |
| Sepolia | 11155111 | USDC | Yes (verifying paymaster) |

**Note**: BSC USDC/USDT use **18 decimals** (not 6). The wallet reads decimals from config, never hardcodes.

## All Commands

| Command | Password | What It Does |
|---------|----------|-------------|
| `init` | Yes | Create a new wallet |
| `import --mnemonic "..."` | Yes | Import from seed phrase |
| `unlock [--duration N] [--scope S]` | Yes | Get a session token (default: 1h, scope: full) |
| `lock` | No | Revoke all sessions + clear signer cache |
| `balance --token T [--chain C] [--asset A]` | No | Check balances (native + configured tokens) |
| `portfolio --token T` | No | Check balances across all configured chains |
| `send --token T --to A --amount N [--asset A] [--chain C] [--mode M]` | Yes | Send tokens |
| `batch --token T --ops JSON [--chain C] [--mode M]` | Yes | Send multiple operations atomically |
| `approve --token T --asset A --spender A --amount N [--chain C]` | Yes | Approve token spending |
| `revoke --token T --asset A --spender A [--chain C]` | Yes | Revoke token approval (sets allowance to 0) |
| `estimate --to A --amount N [--asset A] [--chain C]` | No | Estimate gas cost (direct + gasless) |
| `tx-status --hash H --chain C` | No | Check transaction status (confirmed/pending/reverted) |
| `status --token T` | No | Show wallet address, session info, smart accounts |
| `history --token T [--chain C] [--limit N]` | No | Show transaction history (default: last 50) |
| `sign-message --token T --message M` | Yes | Sign a message (EIP-191) |
| `sign-typed-data --token T --data JSON` | Yes | Sign typed data (EIP-712, for Permit2 etc.) |
| `receive [--chain C]` | No | Show receive addresses (EOA + smart account) |
| `allowances --token T --asset A [--chain C] [--spender A]` | No | Check token approval allowances |
| `chain-info --chain C` | No | Show chain capabilities + gasless availability |
| `chains` | No | List all preconfigured chains |
| `change-password` | Yes+New | Change wallet password (requires NEW_WALLET_PASSWORD) |
| `export` | Yes | Export seed phrase (12 words) |
| `verify-log` | No | Verify transaction log hash-chain integrity |
| `upgrade-7702 --token T [--chain C]` | Yes | Upgrade EOA via EIP-7702 (requires native gas) |
| `deploy-4337 --token T [--chain C]` | Yes | Deploy Smart Account (gasless, auto on first tx) |
| `revoke-7702 --token T [--chain C]` | Yes | Revoke EIP-7702 delegation |

### Global Options

| Option | Description |
|--------|-------------|
| `--chain <name\|id>` | Chain name (`bsc`) or numeric ID (`56`). Default from config. |
| `--pretty` | Pretty-print JSON output with 2-space indent |
| `--rpc-url <url>` | Custom RPC URL (requires `--chain`) |
| `--native-symbol <sym>` | Native currency symbol for custom chains (default: ETH) |

### Session Scopes

| Scope | Permissions |
|-------|-------------|
| `read` | balance, portfolio, history, status, allowances |
| `transfer` | All of `read` + send, batch, approve, revoke, sign-message, sign-typed-data |
| `full` | All of `transfer` + upgrade-7702, deploy-4337, revoke-7702 |

### Transaction Limits

Configured in `config.json`. Enforced per-transaction and per-24h rolling window:

```json
{
  "dailyLimits": { "USDC": "1000", "USDT": "1000", "ETH": "0.5", "BNB": "1.0", "default": "500" },
  "perTransactionMax": { "USDC": "500", "USDT": "500", "ETH": "0.25", "default": "250" }
}
```

- Limits are in **human-readable units** (not wei/raw units)
- Daily limits track by asset symbol and chainId
- Approve/revoke operations do **not** count toward daily transfer limits
- Batch operations enforce cumulative limits within the batch
- `confirmationThreshold` in config is reserved for future use (large-amount confirmation prompts)

## Security Model

### Trust Boundary

```
OpenClaw (trusted zone)
  ├── Secret store: WALLET_PASSWORD (encrypted at rest)
  ├── Injects password as env var per CLI call
  └── Receives session tokens + JSON results only

AWP Wallet (isolated process per command)
  ├── Decrypts keystore with password
  ├── Signs transactions
  ├── Returns JSON (never returns private keys)
  └── Process exits — all in-memory secrets destroyed
```

### Defense Layers

| Layer | Protection | Against |
|-------|-----------|---------|
| Keystore (scrypt N=262144) | ~1 attempt/sec brute-force | Disk theft without password |
| Signer cache (scrypt N=16384) | ~2000 attempts/sec brute-force | Cache file theft without password |
| Session tokens (HMAC-SHA256) | Tamper-proof, time-limited | Agent impersonation |
| Path traversal prevention | Regex validation on tokenId | Malicious session token input |
| File permissions (0o600/0o700) | Owner-only access | Other OS users |
| Process isolation | Keys destroyed on exit | Memory dump attacks |
| Transaction limits | Per-tx + 24h rolling caps | Compromised session abuse |
| Strong random password | Infeasible brute-force | All password-based attacks |
| Hash-chain audit log | Tamper detection via SHA-256 chain | Log manipulation |

### What OpenClaw Must NOT Do

- **Never** store `WALLET_PASSWORD` in plaintext files (`.env`, config, logs)
- **Never** pass the password as a CLI argument (`--password xxx` is visible in `ps aux`)
- **Never** log CLI commands that include `WALLET_PASSWORD` in the environment
- **Never** expose the password to the agent's LLM context
- **Never** reuse the same password across different wallet instances

## Testing

```bash
# Run all tests (144 total)
node --test tests/integration/*.test.js tests/e2e/*.test.js

# Run with BSC RPC for network tests
BSC_RPC_URL="https://..." node --test tests/integration/*.test.js tests/e2e/*.test.js

# Run a specific test file
node --test tests/e2e/security.test.js
```

| Suite | Tests | Covers |
|-------|-------|--------|
| integration/chains | 20 | Chain resolution, config, RPC URLs, token info |
| integration/keystore | 19 | Encryption, AES-GCM cache, password ops, addresses |
| integration/session | 14 | HMAC tokens, scope, lock, tamper detection |
| integration/tx-logger | 15 | Hash-chain log, history, integrity verification |
| integration/tx-validator | 13 | Address validation, limits, batch, allowlist |
| integration/signing | 9 | EIP-191 message signing, scope control |
| integration/balance | 10 | Balance queries, portfolio, tx status |
| integration/bundler-paymaster | 11 | Bundler URLs, strategy selection, paymaster wrapping |
| e2e/lifecycle | 7 | Full lifecycle: init → unlock → lock → import → export |
| e2e/security | 12 | Wrong password, expiry, HMAC tamper, permissions, limits |
| e2e/chain-operations | 14 | Chains, chain-info, balance, estimate, receive, history |
| **Total** | **144** | **0 failures, 1 skip (needs PIMLICO_API_KEY)** |

## Error Messages

All errors are returned as `{ "error": "..." }` JSON on stderr. Known error conditions:

| Condition | Message |
|-----------|---------|
| No password | `WALLET_PASSWORD environment variable required.` |
| Wrong password | `Wrong password — decryption failed.` |
| Wallet exists | `Wallet already exists.` |
| No wallet | `No wallet found. Run 'init' first.` |
| Config missing | `Config not found. Run 'bash scripts/setup.sh' first.` |
| Invalid token | `Invalid or expired session token.` |
| HMAC mismatch | `Session token integrity check failed.` |
| Insufficient scope | `Scope 'read' insufficient; 'transfer' required.` |
| Invalid address | `Invalid Ethereum address: 0x...` |
| Daily limit | `Daily limit exceeded for USDC.` |
| Per-tx limit | `Per-transaction limit exceeded: 600 > 500` |
| No gas + no key | `Insufficient native gas ... Either: (1) fund EOA, or (2) set PIMLICO_API_KEY` |
| Unknown chain | `Unknown chain: "xxx". Use --chain <name\|id> or --rpc-url.` |
| Missing env var | `Environment variable "BSC_RPC_URL" required for RPC URL is not set.` |
| No bundler key | `No bundler API key set. Export PIMLICO_API_KEY, ALCHEMY_API_KEY, or STACKUP_API_KEY.` |
| Amount invalid | `Amount must be a positive number.` |
