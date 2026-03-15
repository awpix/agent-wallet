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

Required environment variables:
- `WALLET_PASSWORD` — encryption password for the keystore (required for init/unlock/send)
- `PIMLICO_API_KEY` — (optional) enables gasless transactions via ERC-4337

## Quick Start

```bash
# Create a new wallet
WALLET_PASSWORD="your-password" node scripts/wallet-cli.js init

# Unlock (creates a session token for subsequent commands)
WALLET_PASSWORD="your-password" node scripts/wallet-cli.js unlock --duration 3600
# Returns: { "sessionToken": "wlt_abc123...", "expires": "..." }

# Check balance on any chain
node scripts/wallet-cli.js balance --token wlt_abc123 --chain base
node scripts/wallet-cli.js balance --token wlt_abc123 --chain bsc
node scripts/wallet-cli.js balance --token wlt_abc123 --chain 43114

# Send tokens (automatically chooses direct or gasless mode)
WALLET_PASSWORD="your-password" node scripts/wallet-cli.js send \
  --token wlt_abc123 --to 0xRecipient --amount 50 --asset usdc --chain base

# Force direct mode (uses EOA, pays gas in native currency)
WALLET_PASSWORD="your-password" node scripts/wallet-cli.js send \
  --token wlt_abc123 --to 0xRecipient --amount 0.1 --chain base --mode direct

# Force gasless mode (uses Smart Account + Paymaster, zero gas cost)
WALLET_PASSWORD="your-password" node scripts/wallet-cli.js send \
  --token wlt_abc123 --to 0xRecipient --amount 50 --asset usdc --chain base --mode gasless

# Lock when done
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

| Command | What It Does |
|---------|-------------|
| `init` | Create a new wallet |
| `import --mnemonic "..."` | Import from seed phrase |
| `unlock [--duration N] [--scope S]` | Get a session token |
| `lock` | Revoke all sessions |
| `balance --token T [--chain C] [--asset A]` | Check balances |
| `portfolio --token T` | Check balances across all configured chains |
| `send --token T --to A --amount N [--asset A] [--chain C] [--mode M]` | Send tokens |
| `batch --token T --ops JSON [--chain C]` | Send multiple operations |
| `approve --token T --asset A --spender A --amount N [--chain C]` | Approve token spending |
| `estimate --to A --amount N [--asset A] [--chain C]` | Estimate gas cost |
| `tx-status --hash H --chain C` | Check transaction status |
| `status --token T` | Show wallet status (address, session info) |
| `history --token T [--chain C]` | Show transaction history |
| `sign-message --token T --message M` | Sign a message (EIP-191) |
| `receive [--chain C]` | Show receive addresses |
| `allowances --token T [--chain C] [--asset A]` | Check token approvals |
| `revoke --token T --asset A --spender A [--chain C]` | Revoke approval |
| `chain-info --chain C` | Show chain capabilities |
| `chains` | List all supported chains |
| `change-password` | Change wallet password |
| `export` | Export seed phrase |
| `verify-log` | Verify transaction log integrity |
| `upgrade-7702 --token T [--chain C]` | Upgrade EOA via EIP-7702 (needs gas) |
| `deploy-4337 --token T [--chain C]` | Deploy Smart Account (gasless) |
| `revoke-7702 --token T [--chain C]` | Revoke EIP-7702 delegation |

## Security

- Private keys are **never** exposed to the agent. The agent only receives session tokens.
- Keystore uses scrypt (N=262144) encryption — same as MetaMask/geth.
- Session tokens are HMAC-signed to prevent tampering.
- Transaction limits are enforced per-transaction and per-24h rolling window.
- All file permissions are 0o600/0o700 (owner-only).
