---
name: AWP Wallet
description: >
  Use this skill to execute crypto wallet operations on any EVM blockchain,
  and interact with the AWP RootNet protocol on BSC. Trigger whenever the
  user wants to: send ETH/BNB/tokens/USDC/USDT/AWP to an address, check
  their crypto wallet balance, view token holdings across multiple chains,
  approve or revoke a DeFi protocol's spending allowance, sign a message or
  EIP-712 typed data, estimate gas fees for a transfer, create a new crypto
  wallet, check a transaction's status, register as an AWP user, bind an
  agent, register a subnet, deposit/stake AWP, allocate stake, or query
  AWP protocol state (subnets, emissions, staking). Works on Ethereum, Base,
  BSC, Arbitrum, Polygon, Avalanche, Optimism, Fantom, and any EVM chain by
  ID. Handles gasless/zero-gas transactions automatically. Also supports
  gasless AWP registration and subnet registration via relay API.
  IMPORTANT: Always use this skill when the user mentions sending crypto,
  transferring tokens, checking wallet balance, token approvals, signing,
  AWP staking, subnet operations, or agent registration — even if they
  don't explicitly say "wallet". Do NOT use for writing Solidity, deploying
  contracts, price charts, or blockchain analytics.
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

Execute on-chain wallet operations across all EVM blockchains via the `awp-wallet` CLI, with native support for the AWP RootNet protocol on BSC.

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

# Send ERC-20 token (including AWP token)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 100 --asset usdc --chain base

# Send AWP tokens on BSC
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 1000 \
  --asset 0x0000969dDC625E1c084ECE9079055Fbc50F400a1 --chain bsc

# Force gasless (when no native gas available)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xRecipient --amount 50 --asset usdc --chain base --mode gasless

# Approve token spending (for DEX/DeFi/AWP RootNet)
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset usdc --spender 0xRouter --amount 1000 --chain base

# Approve AWP for RootNet (required before registerSubnet, deposit, registerAndStake)
WALLET_PASSWORD="$PW" awp-wallet approve --token $T \
  --asset 0x0000969dDC625E1c084ECE9079055Fbc50F400a1 \
  --spender 0x190E0E3128764913D54aD570993b21a38D1411F7 \
  --amount 1000000 --chain bsc

# Revoke token approval
WALLET_PASSWORD="$PW" awp-wallet revoke --token $T --asset usdc --spender 0xRouter --chain base

# Sign message (EIP-191)
WALLET_PASSWORD="$PW" awp-wallet sign-message --token $T --message "Hello"

# Sign typed data (EIP-712 / Permit2 / AWP gasless relay)
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

## AWP RootNet Protocol Integration

The wallet operates on BSC (Chain ID 56) where the AWP RootNet protocol is deployed.

### Key Contract Addresses (BSC Mainnet)

| Contract | Address |
|----------|---------|
| RootNet | `0x190E0E3128764913D54aD570993b21a38D1411F7` |
| AWPToken | `0x0000969dDC625E1c084ECE9079055Fbc50F400a1` |
| StakeNFT | `0x3678463cd5EbA407b20CD1c296B6ECc58491C170` |
| SubnetNFT | `0xbdfd26f499bd7972242bb765d8C3262d6d89fE63` |
| StakingVault | `0xbEe164bdE7F690E7bb73a0D84c1a87D1073545eE` |
| AWPEmission | `0xcc4fA866c0c49FE4763977C5302a6052C3f0d742` |
| AWPDAO | `0xe21097cB128b41611557356de7f55BCd25062579` |

### REST API (read-only, no wallet needed)

Base URL: `https://tapi.awp.sh/api`

```bash
# Query subnet info
curl -s https://tapi.awp.sh/api/subnets/1

# List active subnets
curl -s 'https://tapi.awp.sh/api/subnets?status=Active&page=1&limit=20'

# Get user staking balance
curl -s https://tapi.awp.sh/api/staking/user/0xAddress/balance

# Get user positions (StakeNFT)
curl -s https://tapi.awp.sh/api/staking/user/0xAddress/positions

# Get emission info
curl -s https://tapi.awp.sh/api/emission/current

# Get AWP token info
curl -s https://tapi.awp.sh/api/tokens/awp

# Get subnet skills URI
curl -s https://tapi.awp.sh/api/subnets/1/skills

# Check if address is registered
curl -s https://tapi.awp.sh/api/address/0xAddress/check
```

### Gasless Relay (no BNB gas needed)

The relay API at `https://tapi.awp.sh/api/relay` enables gasless operations. The user signs EIP-712 typed data, the relayer submits the transaction.

#### Gasless User Registration

```bash
# 1. Get wallet address
ADDRESS=$(awp-wallet receive | jq -r '.eoaAddress')

# 2. Sign EIP-712 registration message
DEADLINE=$(($(date +%s) + 3600))
TYPED_DATA='{"types":{"Register":[{"name":"user","type":"address"},{"name":"deadline","type":"uint256"},{"name":"nonce","type":"uint256"}]},"primaryType":"Register","domain":{"name":"AWP-RootNet","version":"1","chainId":56,"verifyingContract":"0x190E0E3128764913D54aD570993b21a38D1411F7"},"message":{"user":"'$ADDRESS'","deadline":"'$DEADLINE'","nonce":"0"}}'

WALLET_PASSWORD="$PW" awp-wallet sign-typed-data --token $T --data "$TYPED_DATA"
# => { "signature": "0x...", "signer": "0x..." }

# 3. Submit to relay
curl -X POST https://tapi.awp.sh/api/relay/register \
  -H 'Content-Type: application/json' \
  -d '{"user":"'$ADDRESS'","deadline":'$DEADLINE',"signature":"0x..."}'
# => { "txHash": "0x..." }
```

#### Gasless Subnet Registration

Requires two signatures: ERC-2612 permit (AWP spend) + EIP-712 registerSubnet.

```bash
curl -X POST https://tapi.awp.sh/api/relay/register-subnet \
  -H 'Content-Type: application/json' \
  -d '{
    "user": "0x...",
    "name": "My Subnet",
    "symbol": "MSUB",
    "subnetManager": "0x0000000000000000000000000000000000000000",
    "salt": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "minStake": "0",
    "deadline": 1742400000,
    "permitSignature": "0x...65 bytes (ERC-2612 AWP permit)",
    "registerSignature": "0x...65 bytes (EIP-712 registerSubnet)"
  }'
```

#### Gasless Agent Binding

```bash
curl -X POST https://tapi.awp.sh/api/relay/bind \
  -H 'Content-Type: application/json' \
  -d '{"agent":"0xAgent","principal":"0xPrincipal","deadline":1742400000,"signature":"0x..."}'
```

### Subnet Skill Discovery

Subnets publish a `skillsURI` pointing to a SKILL.md file. To discover and install subnet skills:

```bash
# List subnets with skills
curl -s 'https://tapi.awp.sh/api/subnets?status=Active' | \
  jq '.[] | select(.skills_uri != null) | {id: .subnet_id, name: .name, skills: .skills_uri}'

# Fetch and install a subnet's skill
SKILLS_URI=$(curl -s https://tapi.awp.sh/api/subnets/1/skills | jq -r '.skillsURI')
mkdir -p ~/.openclaw/skills/awp-subnet-1
curl -o ~/.openclaw/skills/awp-subnet-1/SKILL.md "$SKILLS_URI"
```

## Chain & Token Selection

```bash
--chain bsc          # by name (default if omitted: bsc)
--chain 56           # by chain ID
--chain 99999 --rpc-url https://custom.rpc.com   # custom chain

--asset usdc         # by symbol (preconfigured)
--asset 0x0000969dDC625E1c084ECE9079055Fbc50F400a1  # AWP token by address
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

For AWP-specific gasless operations (registration, binding, subnet registration), use the relay API instead of ERC-4337.

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

## WebSocket Events

Subscribe to real-time AWP protocol events:

```javascript
const ws = new WebSocket('wss://tapi.awp.sh/ws/live');
ws.send(JSON.stringify({
  subscribe: ["Allocated", "Deallocated", "SubnetRegistered", "EpochSettled", "RecipientAWPDistributed"]
}));
```
