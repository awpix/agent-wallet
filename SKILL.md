---
name: AWP Wallet
description: >
  Crypto wallet for AI agents — send tokens, check balances, sign messages,
  manage approvals, and interact with AWP RootNet on BSC. Trigger when the
  user wants to send crypto, check wallet balance, approve a DeFi contract,
  sign EIP-712 data, estimate gas, register on AWP, stake AWP, manage
  subnets, or do anything involving on-chain wallet operations on any EVM
  chain. Do NOT use for writing Solidity, deploying contracts, or analytics.
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

On-chain wallet operations across all EVM blockchains via the `awp-wallet` CLI. Native support for AWP RootNet protocol on BSC.

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
awp-wallet balance --token $T --chain bsc --asset awp    # AWP balance
awp-wallet portfolio --token $T                           # all chains
awp-wallet estimate --to 0xAddr --amount 0.1 --chain bsc # gas cost
awp-wallet tx-status --hash 0xHash --chain bsc           # tx status
awp-wallet history --token $T --chain bsc                 # tx history
awp-wallet allowances --token $T --asset awp --chain bsc # approvals
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

# Send AWP
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 1000 --asset awp --chain bsc

# Gasless send (no native gas needed)
WALLET_PASSWORD="$PW" awp-wallet send --token $T --to 0xAddr --amount 50 --asset usdc --chain base --mode gasless

# Approve token spending
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset usdc --spender 0xRouter --amount 1000 --chain base

# Approve AWP for RootNet (staking, subnet registration)
WALLET_PASSWORD="$PW" awp-wallet approve --token $T --asset awp --spender 0x190E0E3128764913D54aD570993b21a38D1411F7 --amount 1000000 --chain bsc

# Revoke approval
WALLET_PASSWORD="$PW" awp-wallet revoke --token $T --asset usdc --spender 0xRouter --chain base

# Sign message (EIP-191)
WALLET_PASSWORD="$PW" awp-wallet sign-message --token $T --message "Hello"

# Sign typed data (EIP-712 / Permit2 / AWP relay)
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
--asset 0x0000969dDC625E1c084ECE9079055Fbc50F400a1  # by address
```

Default chain when omitted: `bsc`. AWP token is preconfigured on BSC as `awp`.

## AWP RootNet Protocol

The AWP protocol is deployed on BSC. The wallet handles token transfers and approvals; for protocol-specific operations (registration, staking, subnets), use the REST API and gasless relay.

### Contract Addresses (BSC)

| Contract | Address |
|----------|---------|
| RootNet | `0x190E0E3128764913D54aD570993b21a38D1411F7` |
| AWPToken | `0x0000969dDC625E1c084ECE9079055Fbc50F400a1` |
| StakeNFT | `0x3678463cd5EbA407b20CD1c296B6ECc58491C170` |
| SubnetNFT | `0xbdfd26f499bd7972242bb765d8C3262d6d89fE63` |
| StakingVault | `0xbEe164bdE7F690E7bb73a0D84c1a87D1073545eE` |
| AWPEmission | `0xcc4fA866c0c49FE4763977C5302a6052C3f0d742` |
| AWPDAO | `0xe21097cB128b41611557356de7f55BCd25062579` |

### REST API (`https://tapi.awp.sh/api`)

No wallet needed — pure reads:

```bash
curl -s https://tapi.awp.sh/api/subnets/1                              # subnet info
curl -s 'https://tapi.awp.sh/api/subnets?status=Active&limit=20'       # list subnets
curl -s https://tapi.awp.sh/api/staking/user/0xAddr/balance            # staking balance
curl -s https://tapi.awp.sh/api/staking/user/0xAddr/positions          # NFT positions
curl -s https://tapi.awp.sh/api/emission/current                       # epoch + emission
curl -s https://tapi.awp.sh/api/tokens/awp                             # AWP supply info
curl -s https://tapi.awp.sh/api/subnets/1/skills                       # subnet skills URI
curl -s https://tapi.awp.sh/api/address/0xAddr/check                   # registration check
```

> For full API reference (all endpoints, WebSocket events, relay signatures), read `references/awp-api.md`.

### Gasless Relay (`https://tapi.awp.sh/api/relay`)

Three gasless operations — user signs EIP-712, relayer pays gas:

| Endpoint | Purpose | Signatures |
|----------|---------|------------|
| `POST /relay/register` | Register user | 1× EIP-712 |
| `POST /relay/bind` | Bind agent to principal | 1× EIP-712 |
| `POST /relay/register-subnet` | Register subnet | 2× (ERC-2612 permit + EIP-712) |

Use `awp-wallet sign-typed-data` to produce signatures, then `curl` to submit.

> For full relay request/response format and EIP-712 typed data structure, read `references/awp-api.md`.

### Subnet Skill Discovery

Subnets publish a `skillsURI` → SKILL.md that teaches agents how to use that subnet:

```bash
# Find subnets with skills
curl -s 'https://tapi.awp.sh/api/subnets?status=Active' | \
  jq '.[] | select(.skills_uri != null) | {id: .subnet_id, name, skills: .skills_uri}'

# Install a subnet's skill
SKILLS_URI=$(curl -s https://tapi.awp.sh/api/subnets/1/skills | jq -r '.skillsURI')
mkdir -p ~/.openclaw/skills/awp-subnet-1
curl -o ~/.openclaw/skills/awp-subnet-1/SKILL.md "$SKILLS_URI"
```

## Transaction Modes

- **Direct** (default): EOA transaction, needs native gas. Cheapest.
- **Gasless**: ERC-4337 Smart Account via paymaster. Auto-selected when no gas. Needs `PIMLICO_API_KEY`.
- **AWP Relay**: For AWP-specific operations (register, bind, subnet). Uses `sign-typed-data` + relay API.

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
