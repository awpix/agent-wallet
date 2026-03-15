# AWP Wallet

Self-custodial, chain-agnostic EVM blockchain wallet for AI agents. Direct EOA transactions by default, with on-demand ERC-4337 gasless support.

## Features

- **All EVM chains** — 400+ built-in via viem, plus custom chain support
- **Dual-mode transactions** — Direct EOA (default, cheapest) or gasless ERC-4337 (auto when no gas)
- **Self-custodial** — Private keys never leave the wallet process; agents only hold session tokens
- **10 preconfigured chains** — Ethereum, Base, BSC, Arbitrum, Optimism, Polygon, Avalanche, Fantom, + testnets
- **27 CLI commands** — Send, balance, approve, revoke, sign, estimate, batch, and more
- **144 tests** — Integration + E2E, 0 failures

## Install as OpenClaw Skill

### Prerequisites

- Node.js >= 20
- npm >= 9
- Git

### Step 1: Clone and install

```bash
git clone https://github.com/awpix/agent-wallet.git
cd agent-wallet
bash scripts/setup.sh
```

This will:
- Install 4 npm dependencies (viem, permissionless, ethers, commander)
- Register the `awp-wallet` command globally via `npm link`
- Create the runtime directory `~/.openclaw-wallet/` with strict permissions (0o700)
- Copy the default chain config (10 chains, 3 bundler providers)
- Generate a 32-byte HMAC session secret

### Step 2: Configure secrets in OpenClaw

OpenClaw must store these secrets in its **encrypted secret store** (never plaintext):

```bash
# Generate a strong random wallet password (do this once per agent)
WALLET_PASSWORD=$(openssl rand -base64 36)

# Store in OpenClaw's secret manager:
openclaw secrets set WALLET_PASSWORD "$WALLET_PASSWORD"

# Optional: enable gasless transactions
openclaw secrets set PIMLICO_API_KEY "pm_xxx"

# Optional: custom BSC RPC (faster than public)
openclaw secrets set BSC_RPC_URL "https://your-bsc-rpc.com"
```

### Step 3: Initialize wallet

```bash
# OpenClaw injects WALLET_PASSWORD from its secret store
WALLET_PASSWORD="$SECRET" awp-wallet init
# => { "status": "created", "address": "0x..." }
```

### Step 4: Register skill in OpenClaw

Point OpenClaw to the `SKILL.md` file so the agent knows when and how to use the wallet:

```bash
openclaw skills add ./agent-wallet/SKILL.md
```

OpenClaw reads the YAML frontmatter in `SKILL.md` to understand the skill's name, description, and trigger conditions.

### Step 5: Verify

```bash
# Test the full lifecycle
WALLET_PASSWORD="$SECRET" awp-wallet unlock --duration 60
# => { "sessionToken": "wlt_...", "expires": "..." }

awp-wallet balance --token wlt_... --chain bsc
# => { "chain": "BNB Smart Chain", "chainId": 56, "balances": { "BNB": "0", ... } }

awp-wallet lock
# => { "status": "locked" }
```

### How OpenClaw Calls the Skill

Once installed, the agent invokes wallet commands as subprocess calls:

```
OpenClaw Agent
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

Each command is an independent process. The agent only sees JSON output and session tokens — **never** private keys.

### Updating

```bash
cd agent-wallet
git pull
npm install
```

No migration needed — the runtime directory (`~/.openclaw-wallet/`) and keystore are preserved across updates.

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

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `WALLET_PASSWORD` | For write ops | Keystore encryption password |
| `PIMLICO_API_KEY` | For gasless | ERC-4337 bundler/paymaster |
| `ALCHEMY_API_KEY` | Optional | RPC + bundler fallback |
| `BSC_RPC_URL` | Optional | Custom BSC RPC endpoint |

## Testing

```bash
# All tests
node --test tests/integration/*.test.js tests/e2e/*.test.js

# With network access (enables balance/estimate tests)
BSC_RPC_URL="https://..." node --test tests/integration/*.test.js tests/e2e/*.test.js
```

144 tests across 11 files: 8 integration suites + 3 E2E suites.

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

## License

MIT
