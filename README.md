# AWP Wallet

[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Self-custodial, chain-agnostic EVM blockchain wallet for AI agents. Direct EOA transactions by default, with on-demand ERC-4337 gasless support.

Works with OpenClaw · Claude Code · Cursor · Codex · Gemini CLI · Windsurf — and any agent that can invoke CLI commands.

## Install as Agent Skill

### OpenClaw

```bash
npx clawhub@latest install awp-wallet
```

Or paste the repo URL directly in your OpenClaw conversation:

```
https://github.com/awp-core/awp-wallet
```

### Other Skill Registries

**Via [skills CLI](https://github.com/vercel-labs/skills):**

```bash
npx skills add awp-core/awp-wallet
```

### How Agents Use the Wallet

Once installed, agents invoke wallet commands as subprocess calls. All output is JSON:

```
Agent
  │
  │  User: "Send 50 USDC to 0xBob on Base"
  │
  ├─ 1. WALLET_PASSWORD="$SECRET" awp-wallet unlock --duration 300
  │     → { "sessionToken": "wlt_abc..." }
  │
  ├─ 2. WALLET_PASSWORD="$SECRET" awp-wallet send \
  │       --token wlt_abc --to 0xBob --amount 50 --asset usdc --chain base
  │     → { "status": "sent", "txHash": "0x...", "mode": "direct", ... }
  │
  └─ 3. awp-wallet lock
        → { "status": "locked" }
```

Each command is an independent process. The agent only sees JSON output and session tokens — **never** private keys. Password is auto-generated on first use.

## Features

- **All EVM chains** — 400+ built-in via viem, plus custom chain support
- **Dual-mode transactions** — Direct EOA (default, cheapest) or gasless ERC-4337 (auto when no gas)
- **Self-custodial** — Private keys never leave the wallet process; agents only hold session tokens
- **10 preconfigured chains** — Ethereum, Base, BSC, Arbitrum, Optimism, Polygon, Avalanche, Fantom, + testnets
- **26 CLI commands** — Send, balance, approve, revoke, sign, estimate, batch, and more
- **144 tests** — Integration + E2E, 0 failures

## Quick Start (Standalone)

```bash
# Install
bash scripts/setup.sh

# Create wallet
WALLET_PASSWORD="your-password" awp-wallet init

# Unlock (get session token)
WALLET_PASSWORD="your-password" awp-wallet unlock --duration 3600
# => { "sessionToken": "wlt_abc123...", "expires": "..." }

# Check balance
awp-wallet balance --token wlt_abc123 --chain bsc

# Send tokens
WALLET_PASSWORD="your-password" awp-wallet send \
  --token wlt_abc123 --to 0xRecipient --amount 50 --asset usdc --chain base

# Lock
awp-wallet lock
```

## Commands

| Command | What It Does |
|---------|-------------|
| `init` | Create a new wallet |
| `import --mnemonic "..."` | Import from seed phrase |
| `unlock [--duration N] [--scope S]` | Get a session token |
| `lock` | Revoke all sessions |
| `balance --token T [--chain C]` | Check balances |
| `portfolio --token T` | Balances across all chains |
| `send --token T --to A --amount N` | Send tokens |
| `batch --token T --ops JSON` | Batch operations |
| `approve / revoke` | Token approvals |
| `estimate --to A --amount N` | Gas estimation |
| `sign-message / sign-typed-data` | Message signing (EIP-191/712) |
| `history / tx-status / verify-log` | Transaction tracking |
| `chain-info / chains / receive` | Chain & address info |
| `change-password / export` | Account management |
| `upgrade-7702 / deploy-4337` | Smart account ops |

See [SKILL.md](SKILL.md) for full command reference with all options.

## Architecture

```
Agent
  │
  ├── awp-wallet balance --token T --chain bsc     → JSON stdout
  ├── awp-wallet send --token T --to 0x... ...     → JSON stdout
  └── awp-wallet lock                              → JSON stdout

Each command = independent Node.js process
  ├── Reads encrypted keystore (scrypt N=262144)
  ├── Decrypts signer from AES-GCM cache (scrypt N=16384, ~50ms)
  ├── Executes on-chain operation via viem
  ├── Returns JSON result
  └── Process exits — all secrets destroyed
```

### Transaction Routing

```
User intent
     │
     ▼
 tx-router: select path
     │
     ├── Has native gas OR --mode direct ──→ direct-tx.js
     │     viem walletClient.sendTransaction()
     │     21k gas (ETH) / ~65k gas (ERC-20)
     │
     └── No gas OR --mode gasless ──→ gasless-tx.js
           Smart Account → Bundler → Paymaster → EntryPoint
           ERC-4337, gas paid by paymaster
```

## Security Model

| Layer | Protection |
|-------|-----------|
| Keystore | scrypt (N=262144) — ~1 attempt/sec brute-force |
| Signer cache | scrypt (N=16384) — ~2000 attempts/sec |
| Session tokens | HMAC-SHA256, time-limited, tamper-proof |
| Path traversal | Regex validation on all token IDs |
| File permissions | 0o600/0o700 (owner-only) |
| Process isolation | Keys destroyed on process exit |
| Transaction limits | Per-tx and 24h rolling caps |
| Audit log | SHA-256 hash-chain for tamper detection |

**Private keys never enter the agent's context.** The agent only receives time-limited session tokens.

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `WALLET_PASSWORD` | For write ops | Keystore encryption password (auto-generated if not set) |
| `NEW_WALLET_PASSWORD` | change-password only | New password for `change-password` command |
| `PIMLICO_API_KEY` | For gasless | ERC-4337 bundler/paymaster |
| `ALCHEMY_API_KEY` | Optional | RPC + bundler fallback |
| `BSC_RPC_URL` | Optional | Custom BSC RPC endpoint |

## Platform Integration

### Claude Code

Add the wallet guide to your web3 project's CLAUDE.md:

```bash
cp awp-wallet/docs/CLAUDE-WEB3-GUIDE.md your-project/
cat awp-wallet/docs/CLAUDE-WEB3-GUIDE.md >> your-project/CLAUDE.md
```

See [docs/CLAUDE-WEB3-GUIDE.md](docs/CLAUDE-WEB3-GUIDE.md) for the full guide.

### Other Agents

AWP Wallet works with any agent that can run CLI commands and parse JSON output. Copy `SKILL.md` to your agent's skills directory, or point your agent platform to this repo.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| CLI | commander |
| Keystore | ethers v6 (scrypt + AES-128-CTR) |
| Transactions | viem (direct EOA) |
| Smart Accounts | permissionless 0.3 (Kernel v3, ERC-4337) |
| Bundler | viem/account-abstraction (fallback transport) |
| Chain Registry | viem/chains (400+ built-in) |

4 runtime dependencies. Node.js >= 20.

---

## Development

### Build from Source

```bash
git clone https://github.com/awp-core/awp-wallet.git
cd awp-wallet
bash scripts/setup.sh
```

### One-Click Deploy

```bash
bash install.sh
```

Or with options:

```bash
bash install.sh \
  --dir ~/awp-wallet \
  --bsc-rpc "https://your-bsc-rpc.com" \
  --pimlico "pm_your_api_key"
```

| Flag | Default | Description |
|------|---------|-------------|
| `--dir <path>` | `~/awp-wallet` | Installation directory |
| `--password <pwd>` | Auto-generated | Wallet password (48-char random if omitted) |
| `--pimlico <key>` | None | Enable gasless transactions |
| `--bsc-rpc <url>` | Config template | Custom BSC RPC endpoint |
| `--no-init` | Init enabled | Skip wallet creation (setup only) |

### Testing

```bash
# All tests
node --test tests/integration/*.test.js tests/e2e/*.test.js

# With network access (enables balance/estimate tests)
BSC_RPC_URL="https://..." node --test tests/integration/*.test.js tests/e2e/*.test.js
```

144 tests across 11 files: 8 integration suites + 3 E2E suites.

### Publish to ClawHub

```bash
clawhub login
bash publish.sh          # patch bump
bash publish.sh minor    # minor bump
bash publish.sh 2.0.0    # explicit version
```

### Updating

```bash
cd awp-wallet
git pull
npm install
```

No migration needed — the runtime directory and keystore are preserved across updates.

## License

[MIT](LICENSE)
