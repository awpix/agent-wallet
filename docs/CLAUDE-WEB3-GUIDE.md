# AWP Wallet — Claude Code Integration Guide

> Copy the relevant sections into your web3 project's CLAUDE.md so Claude Code knows how to use the local wallet.

## Add to Your Project's CLAUDE.md

```markdown
## Local Wallet (awp-wallet)

This project uses `awp-wallet` as the local EVM wallet for signing transactions, deploying contracts, and interacting with on-chain protocols.

### Wallet Basics

The wallet is a CLI tool. Every command outputs JSON to stdout. Errors output JSON to stderr with exit code 1.

```bash
# Check if wallet is set up
awp-wallet --version

# Wallet address
awp-wallet receive

# Unlock wallet (required before any write operation)
WALLET_PASSWORD="$WALLET_PASSWORD" awp-wallet unlock --duration 3600
# Returns: { "sessionToken": "wlt_abc123...", "expires": "..." }

# Lock wallet when done
awp-wallet lock
```

### Session Token Workflow

Every write operation requires a session token. The pattern is:

```bash
# 1. Unlock to get token
export WALLET_PASSWORD="your-password"
TOKEN=$(awp-wallet unlock --duration 3600 | jq -r '.sessionToken')

# 2. Use token for operations
awp-wallet balance --token $TOKEN --chain base
awp-wallet send --token $TOKEN --to 0x... --amount 0.1 --chain base

# 3. Lock when done
awp-wallet lock
```

In Node.js scripts:

```javascript
import { execFileSync } from "node:child_process"

function wallet(args, env = {}) {
  const result = execFileSync("awp-wallet", args, {
    encoding: "utf8",
    env: { ...process.env, ...env },
  })
  return JSON.parse(result)
}

// Unlock
const { sessionToken } = wallet(["unlock", "--duration", "3600"], {
  WALLET_PASSWORD: process.env.WALLET_PASSWORD,
})

// Check balance
const bal = wallet(["balance", "--token", sessionToken, "--chain", "base"])
console.log(bal.balances)

// Send
const tx = wallet(
  ["send", "--token", sessionToken, "--to", "0x...", "--amount", "0.1", "--chain", "base"],
  { WALLET_PASSWORD: process.env.WALLET_PASSWORD }
)
console.log(tx.txHash)

// Lock
wallet(["lock"])
```

### Chain Selection

```bash
# By name
--chain ethereum
--chain base
--chain bsc
--chain arbitrum
--chain polygon

# By chain ID
--chain 56
--chain 8453
--chain 42161

# Custom chain (must provide --chain with numeric ID)
--chain 99999 --rpc-url https://custom-rpc.com
```

Default chain (when --chain omitted): `bsc` (configurable in ~/.openclaw-wallet/config.json)

### Token Selection

```bash
# By symbol (preconfigured chains only)
--asset usdc
--asset usdt
--asset weth
--asset wbnb

# By contract address (any chain, auto-detects decimals)
--asset 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
```

IMPORTANT: BSC USDC/USDT have 18 decimals (not 6). The wallet handles this automatically.

### Common Operations

#### Check balance
```bash
awp-wallet balance --token $TOKEN --chain base
awp-wallet balance --token $TOKEN --chain base --asset usdc
awp-wallet balance --token $TOKEN --chain base --asset 0xTokenAddr
```

#### Send native token (ETH/BNB/MATIC)
```bash
WALLET_PASSWORD="$PW" awp-wallet send \
  --token $TOKEN --to 0xRecipient --amount 0.1 --chain base
```

#### Send ERC-20 token
```bash
WALLET_PASSWORD="$PW" awp-wallet send \
  --token $TOKEN --to 0xRecipient --amount 100 --asset usdc --chain base
```

#### Approve token spending (for DEX/protocol interactions)
```bash
WALLET_PASSWORD="$PW" awp-wallet approve \
  --token $TOKEN --asset usdc --spender 0xRouterAddr --amount 1000 --chain base
```

#### Revoke approval
```bash
WALLET_PASSWORD="$PW" awp-wallet revoke \
  --token $TOKEN --asset usdc --spender 0xRouterAddr --chain base
```

#### Estimate gas
```bash
awp-wallet estimate --to 0xRecipient --amount 0.1 --chain base
awp-wallet estimate --to 0xRecipient --amount 100 --asset usdc --chain base
```

#### Sign message (EIP-191)
```bash
WALLET_PASSWORD="$PW" awp-wallet sign-message \
  --token $TOKEN --message "Hello World"
```

#### Sign typed data (EIP-712, for Permit2/protocols)
```bash
WALLET_PASSWORD="$PW" awp-wallet sign-typed-data \
  --token $TOKEN --data '{"domain":{...},"types":{...},"message":{...}}'
```

#### Get wallet address
```bash
awp-wallet receive --chain base
# Returns: { "eoaAddress": "0x...", "smartAccountAddress": "0x..." | null }
```

#### Check transaction status
```bash
awp-wallet tx-status --hash 0xTxHash --chain base
# Returns: { "status": "confirmed" | "pending" | "reverted", "blockNumber": ..., "gasUsed": ... }
```

#### Transaction history
```bash
awp-wallet history --token $TOKEN --chain base --limit 20
```

### Smart Contract Deployment

The wallet doesn't have a dedicated `deploy` command. For contract deployment, use the wallet's signing capability with your deployment framework:

#### With viem (recommended)

```javascript
import { createWalletClient, http } from "viem"
import { privateKeyToAccount } from "viem/accounts"
import { base } from "viem/chains"

// DON'T use privateKey directly — use the wallet's session-based approach instead.
// For deployment scripts that need a walletClient, use this pattern:

// Option 1: Use awp-wallet for sending, parse the tx hash
const deployTx = wallet(
  ["send", "--token", TOKEN, "--to", "0x0000000000000000000000000000000000000000",
   "--amount", "0", "--chain", "base"],
  { WALLET_PASSWORD: PW }
)

// Option 2: For complex deployment, export the private key temporarily
// WARNING: Only do this in a secure local environment
const exported = wallet(["export"], { WALLET_PASSWORD: PW })
// Use exported.mnemonic with your deployment tool (hardhat, forge, etc.)
```

#### With Hardhat

```javascript
// hardhat.config.js
// Get the mnemonic from awp-wallet
const { execFileSync } = require("child_process")
const { mnemonic } = JSON.parse(
  execFileSync("awp-wallet", ["export"], {
    encoding: "utf8",
    env: { ...process.env, WALLET_PASSWORD: process.env.WALLET_PASSWORD },
  })
)

module.exports = {
  networks: {
    base: {
      url: "https://mainnet.base.org",
      accounts: { mnemonic },
    },
  },
}
```

### Transaction Limits

The wallet enforces safety limits (configurable in ~/.openclaw-wallet/config.json):

```
Per-transaction: USDC 500, USDT 500, ETH 0.25, default 250
Daily (24h):     USDC 1000, USDT 1000, ETH 0.5, BNB 1.0, default 500
```

To modify limits for development/testing, edit `~/.openclaw-wallet/config.json`.

### Error Handling

Always check exit code and parse error JSON:

```javascript
function wallet(args, env = {}) {
  try {
    const result = execFileSync("awp-wallet", args, {
      encoding: "utf8",
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"],
    })
    return { ok: true, data: JSON.parse(result) }
  } catch (e) {
    const errJson = (e.stderr || e.stdout || "").trim()
    try {
      return { ok: false, error: JSON.parse(errJson).error }
    } catch {
      return { ok: false, error: e.message }
    }
  }
}
```

Common errors:
- `"WALLET_PASSWORD environment variable required."` — forgot to pass password
- `"Wrong password — decryption failed."` — wrong password
- `"Invalid or expired session token."` — token expired or wallet locked
- `"Insufficient balance for transfer + gas."` — not enough native token
- `"Daily limit exceeded for USDC."` — hit 24h rolling limit
- `"Amount must be a positive number."` — invalid amount

### Environment Variables

```bash
# Required for write operations
export WALLET_PASSWORD="your-password"

# Optional: enable gasless transactions (ERC-4337)
export PIMLICO_API_KEY="pm_xxx"

# Optional: custom RPC endpoints
export BSC_RPC_URL="https://your-bsc-rpc.com"
export ALCHEMY_API_KEY="your-alchemy-key"
```

### Gasless Transactions

When native gas balance is insufficient, the wallet automatically switches to gasless mode (requires PIMLICO_API_KEY):

```bash
# Force gasless mode
WALLET_PASSWORD="$PW" awp-wallet send \
  --token $TOKEN --to 0x... --amount 100 --asset usdc --chain base --mode gasless

# Force direct mode (fails if insufficient gas)
WALLET_PASSWORD="$PW" awp-wallet send \
  --token $TOKEN --to 0x... --amount 0.1 --chain base --mode direct
```

### Multi-Chain Development

```bash
# Same wallet works on all chains — just change --chain
awp-wallet balance --token $TOKEN --chain ethereum
awp-wallet balance --token $TOKEN --chain base
awp-wallet balance --token $TOKEN --chain bsc
awp-wallet balance --token $TOKEN --chain arbitrum

# Portfolio (all chains at once)
awp-wallet portfolio --token $TOKEN

# Chain info (check capabilities)
awp-wallet chain-info --chain base
```
```

## Wallet Helper Script

For complex web3 projects, create a `scripts/wallet.js` helper:

```javascript
// scripts/wallet.js — AWP Wallet helper for web3 projects
import { execFileSync } from "node:child_process"

const PW = process.env.WALLET_PASSWORD
if (!PW) throw new Error("Set WALLET_PASSWORD environment variable")

export function wallet(args, opts = {}) {
  const env = { ...process.env, ...opts.env }
  if (opts.password !== false) env.WALLET_PASSWORD = PW
  try {
    const stdout = execFileSync("awp-wallet", args, {
      encoding: "utf8",
      env,
      stdio: ["pipe", "pipe", "pipe"],
      timeout: opts.timeout || 120_000,
    })
    return JSON.parse(stdout.trim())
  } catch (e) {
    const msg = (e.stderr || e.stdout || "").trim()
    try { throw new Error(JSON.parse(msg).error) }
    catch (inner) {
      if (inner.message !== msg) throw inner
      throw new Error(msg || e.message)
    }
  }
}

let _token = null

export function unlock(duration = 3600) {
  const { sessionToken } = wallet(["unlock", "--duration", String(duration)])
  _token = sessionToken
  return sessionToken
}

export function lock() {
  _token = null
  return wallet(["lock"], { password: false })
}

export function token() {
  if (!_token) throw new Error("Wallet not unlocked. Call unlock() first.")
  return _token
}

export function balance(chain, asset) {
  const args = ["balance", "--token", token(), "--chain", chain]
  if (asset) args.push("--asset", asset)
  return wallet(args, { password: false })
}

export function send({ to, amount, chain, asset, mode }) {
  const args = ["send", "--token", token(), "--to", to, "--amount", String(amount), "--chain", chain]
  if (asset) args.push("--asset", asset)
  if (mode) args.push("--mode", mode)
  return wallet(args)
}

export function approve({ asset, spender, amount, chain }) {
  return wallet(["approve", "--token", token(), "--asset", asset,
    "--spender", spender, "--amount", String(amount), "--chain", chain])
}

export function revoke({ asset, spender, chain }) {
  return wallet(["revoke", "--token", token(), "--asset", asset,
    "--spender", spender, "--chain", chain])
}

export function signMessage(message) {
  return wallet(["sign-message", "--token", token(), "--message", message])
}

export function signTypedData(data) {
  return wallet(["sign-typed-data", "--token", token(), "--data", JSON.stringify(data)])
}

export function address(chain) {
  const args = ["receive"]
  if (chain) args.push("--chain", chain)
  return wallet(args, { password: false })
}

export function estimate({ to, amount, chain, asset }) {
  const args = ["estimate", "--to", to, "--amount", String(amount), "--chain", chain]
  if (asset) args.push("--asset", asset)
  return wallet(args, { password: false })
}

export function txStatus(hash, chain) {
  return wallet(["tx-status", "--hash", hash, "--chain", chain], { password: false })
}
```

Usage in your web3 scripts:

```javascript
import { unlock, balance, send, approve, lock, address } from "./scripts/wallet.js"

// Get wallet address
const { eoaAddress } = address("base")
console.log("Wallet:", eoaAddress)

// Unlock
unlock(3600)

// Check balance
const bal = balance("base", "usdc")
console.log("USDC:", bal.balances.USDC)

// Approve USDC spending for a DEX router
approve({ asset: "usdc", spender: "0xRouterAddr", amount: "1000", chain: "base" })

// Send USDC
const tx = send({ to: "0xRecipient", amount: "50", chain: "base", asset: "usdc" })
console.log("TX:", tx.txHash)

// Lock
lock()
```
