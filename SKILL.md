---
name: AWP Wallet
description: >
  Crypto wallet for AI agents — send tokens, check balances, sign messages,
  and manage approvals on any EVM blockchain. Trigger when the user wants to
  send crypto, check wallet balance, approve a DeFi contract, sign EIP-712
  data, estimate gas, or do anything involving on-chain wallet operations.
  Works on Ethereum, Base, BSC, Arbitrum, Polygon, Avalanche, Optimism,
  Fantom, and any custom EVM chain. Handles gasless transactions automatically.
  Do NOT use for writing Solidity, deploying contracts, or analytics.
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
    homepage: https://github.com/awp-core/awp-wallet
    install:
      - kind: node
        package: awp-wallet
        bins: [awp-wallet]
---

# AWP Wallet

On-chain wallet operations across all EVM blockchains via the `awp-wallet` CLI.

## Core Workflow

Every interaction: **ensure wallet → unlock → execute → lock**.

```bash
awp-wallet receive 2>/dev/null || WALLET_PASSWORD="$PW" awp-wallet init
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 300
# ... execute commands ...
awp-wallet lock
```

If `WALLET_PASSWORD` is not stored yet, generate it silently (`openssl rand -base64 36`), store it, and inject per-command. The user should never see a password error.

## Commands

### Read (session token only, no password)

```bash
awp-wallet balance --token $T --chain bsc               # native + token balances
awp-wallet balance --token $T --chain bsc --asset awp    # specific token
awp-wallet portfolio --token $T                           # all chains
awp-wallet estimate --to 0xAddr --amount 0.1 --chain bsc # gas cost
awp-wallet tx-status --hash 0xHash --chain bsc           # tx status
awp-wallet history --token $T --chain bsc                 # tx history
awp-wallet allowances --token $T --asset usdc --chain bsc # approvals
awp-wallet status --token $T                              # session info
awp-wallet receive --chain bsc                            # wallet address
awp-wallet chains                                         # list chains
awp-wallet chain-info --chain bsc                         # chain details
awp-wallet verify-log                                     # audit log
```

### Write (need WALLET_PASSWORD + session token)

```bash
# Send native (BNB/ETH)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 0.1 --chain bsc

# Send ERC-20
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 100 --asset usdc --chain base

# Gasless send (no native gas needed)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 50 --asset usdc --chain base --mode gasless

# Approve token spending
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset usdc --spender 0xRouter --amount 1000 --chain base

# Revoke approval
WALLET_PASSWORD="$PW" awp-wallet revoke --token $T --asset usdc --spender 0xRouter --chain base

# Sign message (EIP-191)
WALLET_PASSWORD="$PW" awp-wallet sign-message --token $T --message "Hello"

# Sign typed data (EIP-712 / Permit2)
WALLET_PASSWORD="$PW" awp-wallet sign-typed-data --token $T --data '{"domain":...}'

# Batch operations
WALLET_PASSWORD="$PW" awp-wallet batch --token $T --ops '[{"to":"0x...","amount":"10","asset":"usdc"}]' --chain base
```

### Account Management (WALLET_PASSWORD, no session)

```bash
WALLET_PASSWORD="$PW" awp-wallet init                    # create wallet
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 3600  # get session token
awp-wallet lock                                           # revoke sessions
WALLET_PASSWORD="$PW" awp-wallet export                  # seed phrase
WALLET_PASSWORD="$OLD" NEW_WALLET_PASSWORD="$NEW" awp-wallet change-password
```

## Chain & Token Selection

```bash
--chain bsc / --chain 56 / --chain ethereum / --chain base
--chain 99999 --rpc-url https://custom.rpc.com   # custom chain

--asset usdc / --asset awp / --asset weth / --asset wbnb
--asset 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # by address
```

Default chain when omitted: `bsc`. AWP token is preconfigured on BSC as `awp`.

## Transaction Modes

- **Direct** (default): EOA transaction, needs native gas. Cheapest.
- **Gasless**: ERC-4337 Smart Account via paymaster. Auto-selected when no gas. Needs `PIMLICO_API_KEY`.

## Error Recovery

| Error | Fix |
|-------|-----|
| `WALLET_PASSWORD environment variable required` | Generate password, store, retry |
| `No wallet found` | Run `awp-wallet init` |
| `Config not found` | Run `bash scripts/setup.sh` |
| `Invalid or expired session token` | Run `awp-wallet unlock` |
| `Insufficient balance` | Fund wallet or use `--mode gasless` |
| `Daily limit exceeded` | Wait 24h or edit `~/.openclaw-wallet/config.json` |

## Output

All JSON to stdout. Errors JSON to stderr with exit code 1. Use `--pretty` for readable output.
