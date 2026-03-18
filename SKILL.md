---
name: awp-wallet
description: >
  Crypto wallet for AI agents — send tokens, check balances, sign messages,
  and manage approvals on any EVM blockchain. Trigger when the user wants to
  send crypto, check wallet balance, approve a DeFi contract, sign EIP-712
  data, estimate gas, or do anything involving on-chain wallet operations.
  Works on Ethereum, Base, BSC, Arbitrum, Polygon, Avalanche, Optimism,
  Fantom, and any custom EVM chain. Handles gasless transactions automatically.
  Do NOT use for writing Solidity, deploying contracts, or analytics.
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
All commands output JSON. `--token` in commands below refers to the session token returned by `unlock`, not a crypto token.

## Core Workflow

```bash
# 1. Ensure wallet exists
awp-wallet receive 2>/dev/null || WALLET_PASSWORD="$PW" awp-wallet init

# 2. Unlock — this is the only step that needs WALLET_PASSWORD
#    Returns a session token ($T) used by all subsequent commands
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 3600
# => {"sessionToken":"wlt_abc123...","expires":"..."}

# 3. Execute operations using the session token
awp-wallet balance --token $T --chain bsc
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0x... --amount 0.1 --chain bsc

# 4. Lock when done
awp-wallet lock
```

**Password rule:** If `WALLET_PASSWORD` is not stored yet, generate it silently (`openssl rand -base64 36`), store it, and inject per-command. Never ask the user or show a password error.

## Commands — No Token Needed

These work without `unlock`. No session token, no password:

```bash
awp-wallet receive                       # show wallet address
awp-wallet receive --chain base          # show address + smart account
awp-wallet chains                        # list preconfigured chains
awp-wallet chain-info --chain bsc        # chain capabilities
awp-wallet estimate --to 0x... --amount 0.1 --chain bsc   # gas cost
awp-wallet estimate --to 0x... --amount 100 --asset usdc --chain base
awp-wallet tx-status --hash 0x... --chain bsc              # tx status
awp-wallet verify-log                    # audit log integrity
```

## Commands — Read (need session token from `unlock`)

```bash
awp-wallet balance --token $T --chain bsc                  # all balances
awp-wallet balance --token $T --chain bsc --asset awp      # specific token
awp-wallet portfolio --token $T                             # all chains at once
awp-wallet history --token $T --chain bsc                   # transaction log
awp-wallet history --token $T --chain bsc --limit 20       # with limit
awp-wallet allowances --token $T --asset usdc --spender 0xRouter --chain bsc
awp-wallet status --token $T                                # address + session
```

## Commands — Write (need session token + WALLET_PASSWORD)

```bash
# Send native currency (BNB/ETH/MATIC)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 0.1 --chain bsc

# Send ERC-20 token
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 100 --asset usdc --chain base

# Gasless send (no native gas needed, requires PIMLICO_API_KEY)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 50 --asset usdc --chain base --mode gasless

# Approve token spending (for DEX/DeFi protocols)
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset usdc --spender 0xRouter --amount 1000 --chain base

# Revoke approval (sets allowance to 0)
WALLET_PASSWORD="$PW" awp-wallet revoke --token $T --asset usdc --spender 0xRouter --chain base

# Sign message (EIP-191)
WALLET_PASSWORD="$PW" awp-wallet sign-message --token $T --message "Hello World"

# Sign typed data (EIP-712)
WALLET_PASSWORD="$PW" awp-wallet sign-typed-data --token $T --data '{"types":{...},"primaryType":"...","domain":{...},"message":{...}}'

# Batch multiple sends
WALLET_PASSWORD="$PW" awp-wallet batch --token $T --chain base \
  --ops '[{"to":"0xA","amount":"10","asset":"usdc"},{"to":"0xB","amount":"20","asset":"usdc"}]'
```

## Commands — Account Management (WALLET_PASSWORD, no session)

```bash
WALLET_PASSWORD="$PW" awp-wallet init                                      # create new wallet
WALLET_PASSWORD="$PW" awp-wallet import --mnemonic "word1 word2 ... word12" # import existing
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 3600                    # session token (1h)
WALLET_PASSWORD="$PW" awp-wallet unlock --duration 300 --scope read        # read-only session
awp-wallet lock                                                             # revoke all sessions
WALLET_PASSWORD="$PW" awp-wallet export                                    # show seed phrase
WALLET_PASSWORD="$OLD" NEW_WALLET_PASSWORD="$NEW" awp-wallet change-password
```

## Chain & Token

```bash
--chain bsc          # by name (default when omitted)
--chain 56           # by chain ID
--chain ethereum / --chain base / --chain arbitrum / --chain polygon
--chain 99999 --rpc-url https://custom.rpc.com    # any EVM chain

--asset usdc / --asset usdt / --asset awp / --asset weth / --asset wbnb
--asset 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # any token by address
```

## Transaction Modes

- **Direct** (default): Standard EOA transaction. Needs native gas. Cheapest and fastest.
- **Gasless** (`--mode gasless`): ERC-4337 Smart Account, paymaster pays gas. Auto-selected when wallet has no native gas. Requires `PIMLICO_API_KEY` env var.

## Error Recovery

| Error | Fix |
|-------|-----|
| `WALLET_PASSWORD environment variable required` | Generate password, store, inject, retry |
| `No wallet found` | `WALLET_PASSWORD="$PW" awp-wallet init` |
| `Config not found` | `bash scripts/setup.sh` |
| `Invalid or expired session token` | `WALLET_PASSWORD="$PW" awp-wallet unlock` |
| `Insufficient balance for transfer + gas` | Fund wallet or `--mode gasless` |
| `Daily limit exceeded` | Wait 24h or edit `~/.openclaw-wallet/config.json` |
| `Amount must be a positive number` | Check amount is > 0 |
| `Unknown chain` | Use `--chain <name|id>` or `--chain <id> --rpc-url <url>` |

## Output

All JSON to stdout. Errors JSON to stderr with exit code 1. Add `--pretty` for indented output.

```json
{"status":"sent","mode":"direct","txHash":"0x...","chain":"BNB Smart Chain","chainId":56,"to":"0x...","amount":"0.1","asset":"BNB"}
```
