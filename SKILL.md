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

# Wallet Skill

A chain-agnostic EVM wallet that lets you manage crypto assets across all EVM-compatible blockchains.

## Setup

```bash
bash scripts/setup.sh
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
   WALLET_PASSWORD="$STORED_SECRET" node scripts/wallet-cli.js unlock

   # WRONG: written to .env file on disk
   echo "WALLET_PASSWORD=xxx" >> .env  # NEVER DO THIS
   ```

4. **Never log the password**. Ensure OpenClaw's logging framework redacts `WALLET_PASSWORD` from command logs, audit trails, and error reports.

5. **Rotate on compromise**. If the secret store is breached, immediately run `change-password`:
   ```bash
   WALLET_PASSWORD="$OLD" NEW_WALLET_PASSWORD="$NEW" node scripts/wallet-cli.js change-password
   ```

### Why This Matters

The wallet keystore is encrypted with scrypt (N=262144), which makes brute-force attacks against the keystore file extremely expensive (~1 attempt/second). However, this protection is only as strong as the password. A weak or leaked password renders keystore encryption useless.

The signer cache (`.signer-cache/`) uses scrypt (N=16384, ~50ms) for key derivation — still computationally expensive for brute-force, but weaker than the main keystore. A strong random password ensures both layers remain secure.

### Environment Variables

| Variable | Storage | Required | Used By |
|----------|---------|----------|---------|
| `WALLET_PASSWORD` | **Encrypted secret store** | For write ops | keystore, session |
| `NEW_WALLET_PASSWORD` | **Encrypted secret store** | change-password only | keystore |
| `PIMLICO_API_KEY` | Secret store or config | Optional (gasless) | bundler |
| `ALCHEMY_API_KEY` | Secret store or config | Optional (RPC/bundler) | chains, bundler |
| `ETH_RPC_URL` | Config | Optional (custom RPC) | chains |

## Quick Start

```bash
# Create a new wallet (password from OpenClaw secret store)
WALLET_PASSWORD="$SECRET" node scripts/wallet-cli.js init

# Unlock (creates a session token for subsequent commands)
WALLET_PASSWORD="$SECRET" node scripts/wallet-cli.js unlock --duration 3600
# Returns: { "sessionToken": "wlt_abc123...", "expires": "..." }

# Check balance (no password needed — session token only)
node scripts/wallet-cli.js balance --token wlt_abc123 --chain base
node scripts/wallet-cli.js balance --token wlt_abc123 --chain bsc

# Send tokens (password needed for signing)
WALLET_PASSWORD="$SECRET" node scripts/wallet-cli.js send \
  --token wlt_abc123 --to 0xRecipient --amount 50 --asset usdc --chain base

# Lock when done (no password needed)
node scripts/wallet-cli.js lock
```

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

### Token Support

Use symbol (preconfigured chains) or contract address (any chain):
- `--asset usdc`, `--asset weth`
- `--asset 0x55d398326f99059fF775485246999027B3197955` (auto-detects decimals)

## All Commands

| Command | Password | What It Does |
|---------|----------|-------------|
| `init` | Yes | Create a new wallet |
| `import --mnemonic "..."` | Yes | Import from seed phrase |
| `unlock [--duration N] [--scope S]` | Yes | Get a session token |
| `lock` | No | Revoke all sessions |
| `balance --token T [--chain C] [--asset A]` | No | Check balances |
| `portfolio --token T` | No | Check balances across all configured chains |
| `send --token T --to A --amount N [--asset A] [--chain C] [--mode M]` | Yes | Send tokens |
| `batch --token T --ops JSON [--chain C]` | Yes | Send multiple operations |
| `approve --token T --asset A --spender A --amount N [--chain C]` | Yes | Approve token spending |
| `estimate --to A --amount N [--asset A] [--chain C]` | No | Estimate gas cost |
| `tx-status --hash H --chain C` | No | Check transaction status |
| `status --token T` | No | Show wallet status |
| `history --token T [--chain C]` | No | Show transaction history |
| `sign-message --token T --message M` | Yes | Sign a message (EIP-191) |
| `receive [--chain C]` | No | Show receive addresses |
| `allowances --token T [--chain C] [--asset A]` | No | Check token approvals |
| `revoke --token T --asset A --spender A [--chain C]` | Yes | Revoke approval |
| `chain-info --chain C` | No | Show chain capabilities |
| `chains` | No | List all supported chains |
| `change-password` | Yes+New | Change wallet password |
| `export` | Yes | Export seed phrase |
| `verify-log` | No | Verify transaction log integrity |
| `upgrade-7702 --token T [--chain C]` | Yes | Upgrade EOA via EIP-7702 |
| `deploy-4337 --token T [--chain C]` | Yes | Deploy Smart Account |
| `revoke-7702 --token T [--chain C]` | Yes | Revoke EIP-7702 delegation |

## Security Model

### Trust Boundary

```
OpenClaw (trusted zone)
  ├── Secret store: WALLET_PASSWORD (encrypted at rest)
  ├── Injects password as env var per CLI call
  └── Receives session tokens + JSON results only

Wallet Skill (isolated process)
  ├── Decrypts keystore with password
  ├── Signs transactions
  ├── Returns JSON (never returns private keys)
  └── Process exits — all in-memory secrets destroyed
```

### Defense Layers

| Layer | Protection | Against |
|-------|-----------|---------|
| Keystore (scrypt N=262144) | ~1 attempt/sec brute-force | Disk theft without password |
| Signer cache (scrypt N=16384) | ~2000 attempts/sec | Cache file theft without password |
| Session tokens (HMAC-SHA256) | Tamper-proof, time-limited | Agent impersonation |
| File permissions (0o600/0o700) | Owner-only access | Other OS users |
| Process isolation | Keys destroyed on exit | Memory dump attacks |
| Transaction limits | Per-tx and 24h rolling caps | Compromised session abuse |
| Strong random password | Infeasible brute-force | All password-based attacks |

### What OpenClaw Must NOT Do

- **Never** store `WALLET_PASSWORD` in plaintext files (`.env`, config, logs)
- **Never** pass the password as a CLI argument (`--password xxx` is visible in `ps aux`)
- **Never** log CLI commands that include `WALLET_PASSWORD` in the environment
- **Never** expose the password to the agent's LLM context
- **Never** reuse the same password across different wallet instances
