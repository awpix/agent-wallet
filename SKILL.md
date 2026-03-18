---
name: AWP Wallet
description: >
  Use this skill to execute crypto wallet operations on any EVM blockchain.
  Trigger whenever the user wants to: send ETH/BNB/tokens/USDC/USDT to an
  address, check their crypto wallet balance, view token holdings across
  multiple chains, approve or revoke a DeFi protocol's spending allowance,
  sign a message or EIP-712 typed data, estimate gas fees for a transfer,
  create a new crypto wallet, or check a transaction's status. Works on
  Ethereum, Base, BSC, Arbitrum, Polygon, Avalanche, Optimism, Fantom, and
  any EVM chain by ID. Handles gasless/zero-gas transactions automatically.
  IMPORTANT: Always use this skill when the user mentions sending crypto,
  transferring tokens, checking wallet balance, token approvals, or signing
  — even if they don't explicitly say "wallet". Do NOT use for writing
  Solidity, deploying contracts, price charts, or blockchain analytics.
version: 1.0.0
metadata:
  openclaw:
    requires:
      env:
        - WALLET_PASSWORD
      bins:
        - node
        - openssl
      anyBins:
        - npm
    primaryEnv: WALLET_PASSWORD
    emoji: "\U0001F4B0"
    homepage: https://github.com/awpix/agent-wallet
    install:
      - kind: node
        package: awp-wallet
        bins: [awp-wallet]
---

# AWP Wallet

Execute on-chain wallet operations across all EVM blockchains via the `awp-wallet` CLI.

## Core Workflow

Every wallet interaction follows this pattern: **ensure wallet exists → unlock → execute → lock**.

```bash
# Step 1: Ensure wallet exists (only needed once, idempotent check)
awp-wallet receive 2>/dev/null || WALLET_PASSWORD="$PW" awp-wallet init

# Step 2: Unlock (get session token, needed before any operation)
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 300

# Step 3: Execute the operation
awp-wallet balance --token $TOKEN --chain bsc
# or: WALLET_PASSWORD="$PW" awp-wallet send --token $TOKEN --to 0x... --amount 1 --chain base

# Step 4: Lock when done
awp-wallet lock
```

## Password Handling

If `WALLET_PASSWORD` is not already stored, **generate it automatically** — never ask the user or show an error:

```bash
WALLET_PASSWORD=$(openssl rand -base64 36)   # 48-char random
# Store securely, then inject per-command
```

The user should never see "WALLET_PASSWORD environment variable required." Handle the password lifecycle transparently.

## Command Reference

### Read Operations (no password needed, session token only)

```bash
awp-wallet balance --token $T --chain bsc                    # native + token balances
awp-wallet balance --token $T --chain base --asset usdc      # specific token
awp-wallet portfolio --token $T                               # all chains at once
awp-wallet estimate --to 0xAddr --amount 0.1 --chain base    # gas cost estimate
awp-wallet tx-status --hash 0xTxHash --chain base            # confirmed/pending/reverted
awp-wallet history --token $T --chain bsc                     # recent transactions
awp-wallet allowances --token $T --asset usdc --chain base   # token approvals
awp-wallet status --token $T                                  # wallet address + session info
awp-wallet receive --chain base                               # show wallet addresses
awp-wallet chain-info --chain bsc                             # chain capabilities
awp-wallet chains                                             # list all configured chains
awp-wallet verify-log                                         # audit log integrity
```

### Write Operations (need WALLET_PASSWORD + session token)

```bash
# Send native currency (ETH/BNB/MATIC)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 0.1 --chain base

# Send ERC-20 token
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 100 --asset usdc --chain base

# Force gasless (when no native gas available)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 50 --asset usdc --chain base --mode gasless

# Approve token spending (for DEX/DeFi)
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset usdc --spender 0xRouter --amount 1000 --chain base

# Revoke token approval
WALLET_PASSWORD="$PW" awp-wallet revoke --token $T --asset usdc --spender 0xRouter --chain base

# Sign message (EIP-191)
WALLET_PASSWORD="$PW" awp-wallet sign-message --token $T --message "Hello"

# Sign typed data (EIP-712 / Permit2)
WALLET_PASSWORD="$PW" awp-wallet sign-typed-data --token $T --data '{"domain":...}'

# Batch multiple operations
WALLET_PASSWORD="$PW" awp-wallet batch --token $T --ops '[{"to":"0x...","amount":"10","asset":"usdc"}]' --chain base
```

### Account Management (need WALLET_PASSWORD, no session token)

```bash
WALLET_PASSWORD="$PW" awp-wallet init                         # create new wallet
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 3600       # get session token
awp-wallet lock                                                # revoke all sessions
WALLET_PASSWORD="$PW" awp-wallet export                       # show seed phrase
WALLET_PASSWORD="$OLD" NEW_WALLET_PASSWORD="$NEW" awp-wallet change-password
```

## Chain & Token Selection

```bash
--chain bsc          # by name (default if omitted: bsc)
--chain 56           # by chain ID
--chain 99999 --rpc-url https://custom.rpc.com   # custom chain

--asset usdc         # by symbol (preconfigured)
--asset 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # by address (any chain)
```

Preconfigured: Ethereum (1), Base (8453), BSC (56), Arbitrum (42161), Optimism (10), Polygon (137), Avalanche (43114), Fantom (250), Base Sepolia (84532), Sepolia (11155111).

## Output Format

All commands return JSON to stdout. Errors return JSON to stderr with exit code 1:

```json
{"status":"sent","mode":"direct","txHash":"0x...","chain":"Base","to":"0x...","amount":"0.1","asset":"ETH"}
{"error":"Insufficient balance for transfer + gas."}
```

## Transaction Modes

The wallet auto-selects the best mode:
- **Direct** (default): EOA transaction, needs native gas. Cheapest and fastest.
- **Gasless**: ERC-4337 Smart Account, gas paid by paymaster. Used when no native gas or `--mode gasless`. Requires `PIMLICO_API_KEY`.

## Error Recovery

| Error | Action |
|-------|--------|
| `WALLET_PASSWORD environment variable required` | Generate password, store, retry |
| `No wallet found. Run 'init' first.` | Run `awp-wallet init` with password |
| `Config not found. Run 'bash scripts/setup.sh' first.` | Run `bash scripts/setup.sh` |
| `Invalid or expired session token.` | Run `awp-wallet unlock` to get fresh token |
| `Insufficient balance for transfer + gas.` | Check balance, fund wallet, or use `--mode gasless` |
| `Daily limit exceeded` | Wait 24h or modify limits in `~/.openclaw-wallet/config.json` |

## Limits

Per-transaction: USDC 500, ETH 0.25, default 250. Daily: USDC 1000, ETH 0.5, BNB 1.0, default 500. All in human units (not wei). Configurable in `~/.openclaw-wallet/config.json`.
