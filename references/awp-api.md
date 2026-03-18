# AWP RootNet — Full API Reference

> Read this file when you need detailed request/response formats for the AWP REST API, WebSocket events, or gasless relay signatures.

## Table of Contents

1. [REST API Endpoints](#rest-api)
2. [Gasless Relay — Full Request Format](#gasless-relay)
3. [WebSocket Events](#websocket)
4. [EIP-712 Typed Data Structures](#eip-712-structures)

---

## REST API

Base URL: `https://tapi.awp.sh/api`

### System
- `GET /health` → `{"status":"ok"}`
- `GET /registry` → All 11 contract addresses

### Users
- `GET /users?page=1&limit=20` — Paginated user list
- `GET /users/count` → `{"count": N}`
- `GET /users/{address}` → User details + balance + agents
- `GET /address/{address}/check` → `{"isRegisteredUser": bool, "isRegisteredAgent": bool}`

### Agents
- `GET /agents/by-owner/{owner}` → Agent list
- `GET /agents/lookup/{agent}` → `{"ownerAddress": "0x..."}`
- `POST /agents/batch-info` — Body: `{"agents":["0x..."], "subnetId": N}` (max 100)

### Staking
- `GET /staking/user/{address}/balance` → `{"totalStaked":"...", "totalAllocated":"...", "unallocated":"..."}`
- `GET /staking/user/{address}/positions` → StakeNFT position NFTs
- `GET /staking/user/{address}/allocations?page=1&limit=20`
- `GET /staking/agent/{agent}/subnet/{subnetId}` → `{"amount":"..."}`
- `GET /staking/agent/{agent}/subnets` → All subnets with stakes
- `GET /staking/subnet/{subnetId}/total` → `{"total":"..."}`

### Subnets
- `GET /subnets?status=Active&page=1&limit=20`
- `GET /subnets/{subnetId}` — Single subnet detail
- `GET /subnets/{subnetId}/earnings?page=1&limit=20`
- `GET /subnets/{subnetId}/skills` → `{"subnetId": N, "skillsURI": "..."}`
- `GET /subnets/{subnetId}/agents/{agent}`

### Emission [DRAFT]
- `GET /emission/current` → `{"epoch":"42", "dailyEmission":"...", "totalWeight":"..."}`
- `GET /emission/schedule` → 30/90/365 day projections
- `GET /emission/epochs?page=1&limit=20`

### Tokens
- `GET /tokens/awp` → `{"totalSupply":"...", "maxSupply":"..."}`
- `GET /tokens/alpha/{subnetId}` → Alpha token info
- `GET /tokens/alpha/{subnetId}/price` → `{"priceInAWP":"...", ...}`

### Governance
- `GET /governance/proposals?status=Active&page=1&limit=20`
- `GET /governance/proposals/{proposalId}`
- `GET /governance/treasury` → `{"treasuryAddress":"0x..."}`

### Vanity Address
- `GET /vanity/mining-params` → Factory address + init code hash + vanity rule
- `POST /vanity/upload-salts` — Batch upload mined salts
- `GET /vanity/salts` — List available salts
- `GET /vanity/salts/count` → `{"available": N}`
- `POST /vanity/compute-salt` → Get/mine a vanity salt

All amounts are in **wei** (18 decimals). Pagination: `page` (1-based) + `limit` (max 100).

---

## Gasless Relay

Base URL: `https://tapi.awp.sh/api/relay`

Rate limit: 100 requests per IP per hour (shared across all relay endpoints).

### POST /relay/register

Gasless user registration.

**Request:**
```json
{"user": "0x1234...", "deadline": 1742400000, "signature": "0x...130 hex chars"}
```

**Response:** `{"txHash": "0x..."}`

### POST /relay/bind

Gasless agent binding.

**Request:**
```json
{"agent": "0xAgent...", "principal": "0xPrincipal...", "deadline": 1742400000, "signature": "0x...130 hex chars"}
```

**Response:** `{"txHash": "0x..."}`

### POST /relay/register-subnet

Fully gasless subnet registration. Requires two signatures.

**Request:**
```json
{
  "user": "0x...",
  "name": "My Subnet",
  "symbol": "MSUB",
  "subnetManager": "0x0000000000000000000000000000000000000000",
  "salt": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "minStake": "0",
  "deadline": 1742400000,
  "permitSignature": "0x...130 hex chars (ERC-2612 AWP permit)",
  "registerSignature": "0x...130 hex chars (EIP-712 registerSubnet)"
}
```

**Response:** `{"txHash": "0x..."}`

- `permitSignature`: Authorizes RootNet to spend user's AWP (no prior approve tx needed)
- `registerSignature`: Authorizes subnet registration parameters
- Both are 65-byte signatures (r[32]+s[32]+v[1]), hex-encoded with 0x prefix

### Relay Error Codes

| Code | Error | Meaning |
|------|-------|---------|
| 400 | `invalid user address` | Malformed address |
| 400 | `deadline is missing or expired` | Deadline in the past |
| 400 | `missing/invalid signature` | Bad EIP-712 signature |
| 400 | `user already registered` | Already on-chain |
| 400 | `insufficient AWP balance` | Not enough AWP |
| 400 | `contract is paused` | Emergency pause |
| 429 | `rate limit exceeded` | 100/hour IP limit |

---

## WebSocket

URL: `wss://tapi.awp.sh/ws/live`

```javascript
const ws = new WebSocket('wss://tapi.awp.sh/ws/live');
ws.send(JSON.stringify({ subscribe: ["EpochSettled", "Allocated", "SubnetRegistered"] }));
ws.onmessage = (e) => {
  const { type, data, blockNumber, txHash } = JSON.parse(e.data);
};
```

### Event Types

| Event | Data Fields | Source |
|-------|-------------|--------|
| `UserRegistered` | `{user}` | RootNet |
| `AgentBound` | `{principal, agent}` | RootNet |
| `Deposited` | `{user, tokenId, amount, lockEndTime}` | StakeNFT |
| `Withdrawn` | `{user, tokenId, amount}` | StakeNFT |
| `Allocated` | `{user, agent, subnetId, amount}` | RootNet |
| `Deallocated` | `{user, agent, subnetId, amount}` | RootNet |
| `Reallocated` | `{user, fromAgent, fromSubnet, toAgent, toSubnet, amount}` | RootNet |
| `SubnetRegistered` | `{subnetId, owner, name, symbol, subnetManager, alphaToken}` | RootNet |
| `SubnetActivated` | `{subnetId}` | RootNet |
| `SubnetPaused` | `{subnetId}` | RootNet |
| `SkillsURIUpdated` | `{subnetId, skillsURI}` | SubnetNFT |
| `RecipientAWPDistributed` | `{epoch, recipient, awpAmount}` | AWPEmission |
| `EpochSettled` | `{epoch, totalEmission, recipientCount}` | AWPEmission |

---

## EIP-712 Structures

### Register (for gasless user registration)

```json
{
  "types": {
    "Register": [
      {"name": "user", "type": "address"},
      {"name": "deadline", "type": "uint256"},
      {"name": "nonce", "type": "uint256"}
    ]
  },
  "primaryType": "Register",
  "domain": {
    "name": "AWP-RootNet",
    "version": "1",
    "chainId": 56,
    "verifyingContract": "0x190E0E3128764913D54aD570993b21a38D1411F7"
  },
  "message": {
    "user": "0xYourAddress",
    "deadline": "1742400000",
    "nonce": "0"
  }
}
```

### Bind (for gasless agent binding)

```json
{
  "types": {
    "Bind": [
      {"name": "agent", "type": "address"},
      {"name": "principal", "type": "address"},
      {"name": "deadline", "type": "uint256"},
      {"name": "nonce", "type": "uint256"}
    ]
  },
  "primaryType": "Bind",
  "domain": {
    "name": "AWP-RootNet",
    "version": "1",
    "chainId": 56,
    "verifyingContract": "0x190E0E3128764913D54aD570993b21a38D1411F7"
  },
  "message": {
    "agent": "0xAgentAddress",
    "principal": "0xPrincipalAddress",
    "deadline": "1742400000",
    "nonce": "0"
  }
}
```

Get the current nonce: `curl -s https://tapi.awp.sh/api/address/0xAddr/check` or on-chain `rootNet.nonces(address)`.
