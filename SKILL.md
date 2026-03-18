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

EVM wallet for agents. Every command outputs JSON. Follow these steps in order.

## Step 0: First-Time Setup

Run once. Skip if `awp-wallet --version` works.

```bash
# If awp-wallet is not installed
git clone https://github.com/awp-core/awp-wallet.git /tmp/awp-wallet
cd /tmp/awp-wallet && bash scripts/setup.sh
```

## Step 1: Ensure Wallet Exists

```bash
awp-wallet receive 2>/dev/null
```

If this fails, create a wallet. Generate a password if you don't have one — never ask the user:

```bash
# Generate and store password (do this once, remember it for all future commands)
WALLET_PASSWORD=$(openssl rand -base64 36)

# Create wallet
WALLET_PASSWORD="<password>" awp-wallet init
# => {"status":"created","address":"0x..."}
```

## Step 2: Unlock

Every session starts with unlock. This returns a session token used by all subsequent commands.

```bash
WALLET_PASSWORD="<password>" awp-wallet unlock --duration 3600
# => {"sessionToken":"wlt_abc123...","expires":"..."}
```

Save the `sessionToken` value — you'll pass it as `--token` to every command below.

## Step 3: Do What the User Asked

### "Check my balance" / "How much do I have"

```bash
awp-wallet balance --token <session> --chain bsc
awp-wallet balance --token <session> --chain bsc --asset usdc
awp-wallet portfolio --token <session>   # all chains at once
```

### "Send X to 0x..."

```bash
# Native currency (BNB/ETH)
WALLET_PASSWORD="<password>" awp-wallet send --token <session> --to 0xRecipient --amount 0.1 --chain bsc

# ERC-20 token
WALLET_PASSWORD="<password>" awp-wallet send --token <session> --to 0xRecipient --amount 100 --asset usdc --chain base

# No gas? Use gasless mode
WALLET_PASSWORD="<password>" awp-wallet send --token <session> --to 0xRecipient --amount 50 --asset usdc --chain base --mode gasless
```

### "Approve token" / "Revoke approval"

```bash
WALLET_PASSWORD="<password>" awp-wallet approve --token <session> --asset usdc --spender 0xContract --amount 1000 --chain base
WALLET_PASSWORD="<password>" awp-wallet revoke --token <session> --asset usdc --spender 0xContract --chain base
```

### "Sign this message"

```bash
# EIP-191
WALLET_PASSWORD="<password>" awp-wallet sign-message --token <session> --message "Hello World"

# EIP-712 typed data
WALLET_PASSWORD="<password>" awp-wallet sign-typed-data --token <session> --data '{"types":{...},"primaryType":"...","domain":{...},"message":{...}}'
```

### "What's my address"

```bash
awp-wallet receive
# => {"eoaAddress":"0x...","smartAccountAddress":null}
```

### "Estimate gas"

```bash
awp-wallet estimate --to 0xRecipient --amount 0.1 --chain bsc
awp-wallet estimate --to 0xRecipient --amount 100 --asset usdc --chain base
```

### "Check transaction status"

```bash
awp-wallet tx-status --hash 0xTxHash --chain bsc
# => {"status":"confirmed","blockNumber":12345,"gasUsed":"21000"}
```

### "Show transaction history"

```bash
awp-wallet history --token <session> --chain bsc --limit 20
```

### "Check allowances"

```bash
awp-wallet allowances --token <session> --asset usdc --spender 0xContract --chain bsc
```

## Step 4: Lock

Always lock when done to revoke the session:

```bash
awp-wallet lock
# => {"status":"locked"}
```

## Chain & Token

`--chain` accepts name or ID. Default: `bsc`.

Names: `ethereum`, `base`, `bsc`, `arbitrum`, `optimism`, `polygon`, `avalanche`, `fantom`, `sepolia`, `base-sepolia`

Custom chain: `--chain 99999 --rpc-url https://custom.rpc.com`

`--asset` accepts symbol or contract address: `usdc`, `usdt`, `awp`, `weth`, `wbnb`, or `0x...`

## Gasless Mode

When the wallet has no native gas (BNB/ETH), it auto-switches to gasless mode (ERC-4337). This requires `PIMLICO_API_KEY` in the environment. Force with `--mode gasless`.

## Error Handling

If a command fails, check the JSON error message and fix:

| Error | What to do |
|-------|------------|
| `WALLET_PASSWORD environment variable required` | You forgot to pass the password. Generate one if needed. |
| `No wallet found` | Run `awp-wallet init` with password. |
| `Config not found` | Run `bash scripts/setup.sh`. |
| `Invalid or expired session token` | Run `awp-wallet unlock` again. |
| `Insufficient balance for transfer + gas` | User needs to fund the wallet, or use `--mode gasless`. |
| `Daily limit exceeded` | Limits are in `~/.openclaw-wallet/config.json`. Default: 500/day per asset. |
