# OpenClaw Wallet Skill — Development Specification

> **This document is the single authoritative source for implementing this skill.**
> After reading it, you should be able to implement the entire skill from scratch without additional research.

---

## 0. Overview

### 0.1 What This Is

A self-custodial, chain-agnostic EVM blockchain wallet skill for OpenClaw AI Agents. Uses direct EOA transactions by default (most efficient), with on-demand ERC-4337 gasless transactions (zero gas fees).

### 0.2 Hard Constraints

| # | Constraint | Why |
|---|-----------|-----|
| 1 | Private keys never enter agent context | Agent only holds time-limited session tokens |
| 2 | Direct EOA transaction is the default path | Fastest, cheapest, zero external dependencies |
| 3 | Gasless is an enhancement, activated on-demand | Only when no native gas or explicitly requested |
| 4 | No custom cryptography | Keystore uses audited ethers.js implementation |
| 5 | ethers.js is confined to keystore module only | Everything else uses viem + permissionless |
| 6 | Password only via environment variable | Never in CLI arguments (visible via `ps aux`) |
| 7 | Support all EVM chains | No hardcoded chain list; viem has 400+ built-in |
| 8 | All output is JSON | CLI serves agents, not human terminal users |

### 0.3 Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| CLI | commander | Argument parsing (no chalk — pure JSON needs no color) |
| Keystore | ethers v6 | scrypt + AES-128-CTR + keccak MAC (Ethereum V3 standard) |
| Bridge | viem/accounts `privateKeyToAccount` | ethers.Wallet → viem LocalAccount |
| Direct Tx | viem `createWalletClient` | Standard EOA transactions (default path) |
| Smart Account | permissionless `toEcdsaKernelSmartAccount` | Kernel v3 ERC-4337 + ERC-7579 modular (gasless path) |
| Module Extension | permissionless `erc7579Actions()` | ERC-7579 module install/uninstall (future: session keys, automation) |
| Bundler | viem/account-abstraction + `fallback` transport | Multi-provider automatic failover |
| Paymaster | viem/account-abstraction `createPaymasterClient` | Gas sponsorship (runtime detection) |
| EIP-7702 | viem/experimental `eip7702Actions` | EOA delegation (optional, requires native gas) |
| Chain Registry | `import * as viemChains from "viem/chains"` | 400+ chains built-in + defineChain for dynamic extension |

### 0.4 Dual-Mode Transaction Engine (Core Architecture)

```
User intent
     │
     ▼
 tx-router: select path
     │
     ├── Has native gas OR --mode direct ──→ direct-tx.js
     │     viem walletClient.sendTransaction()
     │     21k gas (ETH) / ~65k gas (ERC-20)
     │     Only needs RPC node, zero external dependencies
     │     Unaffected by bundler outages
     │
     └── No gas OR --mode gasless ──→ gasless-tx.js
           Smart Account → Bundler → Paymaster → EntryPoint
           ~80k gas (Paymaster pays)
           Requires bundler infrastructure
```

**Why not route everything through ERC-4337**: Each UserOperation has ~42k gas fixed overhead. A 21k gas ETH transfer becomes ~80k gas through 4337 (3.8x). On L2s where gas is already cheap, the 4337 pipeline is actually more expensive. Direct transactions are the most frequent wallet operation and must be the most efficient path.

### 0.5 Three-Tier Chain Support Model

| Tier | Capability | Configuration Required | Coverage |
|------|-----------|----------------------|----------|
| 1 | Direct transactions (EOA) | chainId + RPC URL | **All EVM chains** (400+ built-in, defineChain for custom) |
| 2 | + Token name resolution, balance display | config.json with token `{ address, decimals }` | 10+ preconfigured chains |
| 3 | + Gasless (ERC-4337) | Tier 2 + Bundler API key | 30+ chains supported by Pimlico |

**Key principle**: Direct transaction mode is always available on all EVM chains. Gasless is an enhancement — when unavailable, the wallet works normally.

---

## 1. Dependencies

### 1.1 npm Packages (4 total)

```bash
npm install viem@^2.46 permissionless@^0.3 ethers@^6.13 commander@^12.0
```

**Critical**: `permissionless@^0.3` not `^0.2`. Under semver 0.x, `^0.2` means `>=0.2.0 <0.3.0` — it cannot install 0.3.x. The 0.3 API uses `sendUserOperation({ calls: [...] })` instead of the 0.2 `sendUserOperation({ callData: encodeCalls([...]) })`.

### 1.2 Node.js Built-in Modules

| Module | Used For |
|--------|---------|
| `node:crypto` | randomBytes, createHash, createHmac, createCipheriv/Decipheriv (AES-GCM signer cache) |
| `node:fs` | File I/O |
| `node:path` | Path manipulation |

### 1.3 package.json

```json
{ "type": "module", "engines": { "node": ">=20" } }
```

All modules use ESM `import`/`export`.

---

## 2. File Structure

```
wallet-skill/
├── SKILL.md                        ← OpenClaw trigger description + usage guide
├── scripts/
│   ├── setup.sh                    ← One-click install
│   ├── wallet-cli.js               ← CLI entry point (~280 lines)
│   └── lib/
│       ├── chains.js               ← Chain-agnostic registry (~120 lines)
│       ├── keystore.js             ← ethers.js encryption + AES-GCM signer cache (~150 lines)
│       ├── session.js              ← HMAC-signed session tokens (~100 lines)
│       ├── tx-router.js            ← Transaction routing logic (~80 lines)
│       ├── direct-tx.js            ← EOA direct transactions (~80 lines) ★ most frequent path
│       ├── gasless-tx.js           ← ERC-4337 gasless transactions (~200 lines)
│       ├── balance.js              ← Balance queries (~100 lines) ★ no Bundler dependency
│       ├── bundler.js              ← Fallback transport bundler client (~80 lines)
│       ├── paymaster.js            ← Runtime strategy detection (~120 lines)
│       ├── eip7702.js              ← Optional EOA delegation (~130 lines)
│       ├── signing.js              ← EIP-191/712 message signing (~40 lines)
│       ├── tx-validator.js         ← Pre-transaction safety checks (~120 lines)
│       └── tx-logger.js            ← Hash-chain audit log (~70 lines)
├── assets/
│   └── default-config.json         ← Default config (10+ chains preconfigured)
└── references/                     ← Reference documentation
```

### 2.1 Runtime Directory

```
~/.openclaw-wallet/                 0o700
├── keystore.enc                    0o600  ethers V3 JSON (MetaMask-importable)
├── meta.json                       0o600  { address, smartAccounts: { chainId: addr }, ... }
├── config.json                     0o600  Chain config + limits + bundler providers
├── .session-secret                 0o600  32-byte HMAC key
├── .signer-cache/                  0o700  AES-256-GCM encrypted privateKey cache
│   └── wlt_<hex>.key               0o600  iv(12) + tag(16) + ciphertext — same TTL as session
├── sessions/                       0o700  Session token files (HMAC-signed)
│   └── wlt_<hex>.json
└── tx-log.jsonl                    0o600  Append-only transaction log
```

**Signer cache**: Each CLI command runs as an independent Node.js process — in-process memory is not shared. On `unlock`, the privateKey is AES-256-GCM encrypted (key derived from SHA-256 of password, < 0.1ms) and written to `.signer-cache/`. Subsequent commands read and decrypt (< 0.1ms), skipping scrypt (1.5s). `lock` deletes all cache files. Security: cache files are encrypted — an attacker who obtains the file still needs the password, equivalent to keystore.enc.

---

## 3. Module Specifications

Ordered by dependency topology. Each module specifies: exact imports, exported function signatures, pseudocode-level implementation.

---

### 3.1 chains.js — Chain-Agnostic Registry

**Imports**:

```javascript
import * as viemChains from "viem/chains"       // imports 400+ chains
import { createPublicClient, http, defineChain, erc20Abi } from "viem"
import { readFileSync, existsSync } from "node:fs"
import { join } from "node:path"
```

**Core design: three-level chain lookup**

```javascript
// Build chainId → Chain mapping from viem built-ins
const BUILTIN = new Map()
for (const c of Object.values(viemChains)) {
  if (c?.id) BUILTIN.set(c.id, c)
}

// Auto-build name aliases
const NAME_TO_ID = new Map()
for (const c of BUILTIN.values()) {
  NAME_TO_ID.set(c.name.toLowerCase(), c.id)
  if (c.network) NAME_TO_ID.set(c.network.toLowerCase(), c.id)
}
NAME_TO_ID.set("bsc", 56)
NAME_TO_ID.set("avax", 43114)
NAME_TO_ID.set("ftm", 250)

const CUSTOM = new Map()

// --- Config loading with graceful error handling ---
let _configCache = null
const CONFIG_PATH = join(process.env.HOME, ".openclaw-wallet", "config.json")

export function loadConfig() {
  if (_configCache) return _configCache
  try {
    _configCache = JSON.parse(readFileSync(CONFIG_PATH, "utf8"))
    return _configCache
  } catch (err) {
    if (err.code === "ENOENT")
      throw new Error("Config not found. Run 'bash scripts/setup.sh' first.")
    if (err instanceof SyntaxError)
      throw new Error("Config file corrupted. Delete and re-run setup.sh.")
    throw err
  }
}

// --- Chain ID resolution ---
export function resolveChainId(nameOrId) {
  if (typeof nameOrId === "number") return nameOrId
  const s = String(nameOrId).toLowerCase()
  // Direct numeric string: "56" → 56
  const num = Number(s)
  if (!isNaN(num) && num > 0) return num
  // Name lookup
  if (NAME_TO_ID.has(s)) return NAME_TO_ID.get(s)
  // Config lookup: "base-sepolia" → config.chains["base-sepolia"].chainId
  try {
    const cfg = loadConfig()
    if (cfg.chains?.[s]?.chainId) return cfg.chains[s].chainId
  } catch { /* config not available yet */ }
  throw new Error(`Unknown chain: "${nameOrId}". Use --chain <name|id> or --rpc-url.`)
}

export function viemChain(chainId, rpcUrl, nativeCurrency) {
  chainId = Number(chainId)
  if (CUSTOM.has(chainId)) return CUSTOM.get(chainId)
  if (BUILTIN.has(chainId)) return BUILTIN.get(chainId)
  if (!rpcUrl) throw new Error(`Chain ${chainId} unknown. Provide --rpc-url or add to config.`)
  const c = defineChain({
    id: chainId, name: `Chain ${chainId}`,
    nativeCurrency: nativeCurrency || { name: "ETH", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  })
  CUSTOM.set(chainId, c)
  return c
}
```

**Load customChains from config.json at module initialization**:

```javascript
function loadCustomChains() {
  try {
    const cfg = loadConfig()
    for (const cc of cfg.customChains || []) {
      if (!cc.chainId || !cc.rpcUrl) continue
      const c = defineChain({
        id: cc.chainId,
        name: cc.name || `Chain ${cc.chainId}`,
        nativeCurrency: cc.nativeCurrency || { name: "ETH", symbol: "ETH", decimals: 18 },
        rpcUrls: { default: { http: [cc.rpcUrl] } },
      })
      CUSTOM.set(cc.chainId, c)
      if (cc.name) NAME_TO_ID.set(cc.name.toLowerCase(), cc.chainId)
    }
  } catch { /* config doesn't exist yet (before init) — skip */ }
}
loadCustomChains()
```

**Exports**:

| Function | Description |
|----------|------------|
| `resolveChainId(nameOrId)` | "bsc" → 56, "43114" → 43114, "base" → 8453 |
| `viemChain(chainId, rpcUrl?, nativeCurrency?)` | Returns viem Chain object (builtin → custom → defineChain) |
| `chainConfig(nameOrId)` | Chain config from config.json keyed by chain name (e.g. `cfg.chains["bsc"]`). Accepts name or chainId. Returns null for Tier 1 chains with no config |
| `loadConfig()` | Reads config.json with in-memory cache. Throws friendly error on ENOENT/SyntaxError |
| `tokenInfo(chain, symbolOrAddress)` | Symbol → config lookup; 0x address → **on-chain decimals()/symbol() query** |
| `publicClient(chain)` | Creates and caches viem PublicClient. Uses rpcOverrides first |
| `getRpcUrl(chainNameOrId)` | rpcOverrides (name-keyed) → reverse lookup for numeric chainId → viem built-in RPC fallback |

**chainConfig — name-based lookup with chainId fallback**:

config.json `chains` is keyed by chain name (e.g. `"bsc"`, `"base"`), each entry has a `chainId` field. This function accepts either name or numeric chainId:

```javascript
export function chainConfig(nameOrId) {
  const cfg = loadConfig()
  // Direct name match (most common path: "bsc" → cfg.chains["bsc"])
  const name = String(nameOrId).toLowerCase()
  if (cfg.chains?.[name]) return cfg.chains[name]
  // Numeric chainId fallback: find entry where entry.chainId matches
  const id = Number(nameOrId)
  if (!isNaN(id)) {
    for (const [, entry] of Object.entries(cfg.chains || {})) {
      if (entry.chainId === id) return entry
    }
  }
  return null  // Tier 1 chain with no config — direct-tx still works
}
```

**getRpcUrl — production RPC resolution**:

Public RPCs are rate-limited (10-25 req/s) and unreliable. config.json `rpcOverrides` is keyed by chain name:

```javascript
// Reverse lookup: numeric chainId → config chain name
function chainIdToName(chainId) {
  const cfg = loadConfig()
  for (const [name, entry] of Object.entries(cfg.chains || {})) {
    if (entry.chainId === chainId) return name
  }
  return null
}

export function getRpcUrl(chainNameOrId) {
  const cfg = loadConfig()
  const name = String(chainNameOrId).toLowerCase()
  // Direct name match (fast path: "bsc" → cfg.rpcOverrides["bsc"])
  let override = cfg.rpcOverrides?.[name]
  // Numeric chainId → reverse lookup to name, then check rpcOverrides
  if (!override) {
    const id = Number(chainNameOrId)
    if (!isNaN(id)) {
      const resolved = chainIdToName(id)
      if (resolved) override = cfg.rpcOverrides?.[resolved]
    }
  }
  if (override) {
    return override.replace(/\{(\w+)\}/g, (_, k) => process.env[k] || k)
  }
  return viemChain(resolveChainId(chainNameOrId)).rpcUrls.default.http[0]
}

const _clientCache = new Map()

export function publicClient(chainNameOrId) {
  const chainId = resolveChainId(chainNameOrId)
  if (!_clientCache.has(chainId)) {
    _clientCache.set(chainId, createPublicClient({
      chain: viemChain(chainId),
      transport: http(getRpcUrl(chainNameOrId)),  // passes name through for rpcOverrides lookup
    }))
  }
  return _clientCache.get(chainId)
}
```

**tokenInfo — dual-mode token resolution**:

```javascript
export async function tokenInfo(chain, symbolOrAddress) {
  const chainId = resolveChainId(chain)
  // Symbol (e.g. "USDC") → lookup from config.json (keyed by chain name)
  if (!/^0x/i.test(symbolOrAddress)) {
    const cfg = chainConfig(chain)  // accepts name ("bsc") or chainId (56)
    const entry = cfg?.tokens?.[symbolOrAddress.toUpperCase()]
    if (entry) return { symbol: symbolOrAddress.toUpperCase(), ...entry }
    throw new Error(`Token "${symbolOrAddress}" not configured for chain "${chain}". Use contract address: --asset 0x...`)
  }
  // Contract address → on-chain query (supports any token on any chain)
  const client = publicClient(chainId)
  const decimals = Number(await client.readContract({
    address: symbolOrAddress, abi: erc20Abi, functionName: "decimals"
  }))
  const symbol = await client.readContract({
    address: symbolOrAddress, abi: erc20Abi, functionName: "symbol"
  }).catch(() => "UNKNOWN")
  return { symbol, address: symbolOrAddress, decimals }
}
```

---

### 3.2 keystore.js — ethers.js Encryption + AES-GCM Signer Cache

**Imports**:

```javascript
import { Wallet } from "ethers"
import { privateKeyToAccount } from "viem/accounts"
import { createHash, createCipheriv, createDecipheriv, randomBytes } from "node:crypto"
import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync, readdirSync, unlinkSync } from "node:fs"
import { join } from "node:path"
```

**Do not import** ethers encryption functions. scrypt/keystore is handled by ethers internally. Signer cache encryption uses node:crypto.

**Constants**:

```javascript
const WALLET_DIR = join(process.env.HOME, ".openclaw-wallet")
const KS_PATH = join(WALLET_DIR, "keystore.enc")
const META_PATH = join(WALLET_DIR, "meta.json")
```

**Password retrieval**: Always from `process.env.WALLET_PASSWORD`.

```javascript
function getPassword() {
  const pw = process.env.WALLET_PASSWORD
  if (!pw) throw new Error("WALLET_PASSWORD environment variable required.")
  return pw
}
```

**AES-256-GCM encrypted signer cache**:

```javascript
const CACHE_DIR = join(WALLET_DIR, ".signer-cache")

// AES key derived from password via SHA-256 (not scrypt — scrypt's slowness is what we're avoiding)
// Purpose: protect against "attacker has disk backup but no password" scenario
function deriveAesKey(password) {
  return createHash("sha256").update(password).digest()  // 32 bytes = AES-256
}

// Write encrypted cache (called by unlockAndCache)
function writeSignerCache(sessionId, privateKey, expiresISO) {
  const key = deriveAesKey(getPassword())
  const iv = randomBytes(12)  // GCM standard 96-bit IV
  const cipher = createCipheriv("aes-256-gcm", key, iv)
  const plaintext = JSON.stringify({ privateKey, expires: expiresISO })
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()])
  const tag = cipher.getAuthTag()
  const blob = Buffer.concat([iv, tag, encrypted])  // File format: iv(12) + tag(16) + ciphertext
  if (!existsSync(CACHE_DIR)) mkdirSync(CACHE_DIR, { mode: 0o700 })
  writeFileSync(join(CACHE_DIR, sessionId + ".key"), blob, { mode: 0o600 })
}

// Read encrypted cache. Returns viem LocalAccount or null.
// Decryption failure (password changed/file corrupted) → silently delete, fall through to scrypt.
function readSignerCache() {
  if (!existsSync(CACHE_DIR)) return null
  const password = process.env.WALLET_PASSWORD
  if (!password) return null

  const key = deriveAesKey(password)
  const files = readdirSync(CACHE_DIR).filter(f => f.endsWith(".key"))
  for (const f of files) {
    try {
      const blob = readFileSync(join(CACHE_DIR, f))
      const iv = blob.subarray(0, 12)
      const tag = blob.subarray(12, 28)
      const ciphertext = blob.subarray(28)
      const decipher = createDecipheriv("aes-256-gcm", key, iv)
      decipher.setAuthTag(tag)
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()])
      const data = JSON.parse(plaintext.toString("utf8"))
      if (new Date(data.expires) > new Date()) {
        return privateKeyToAccount(data.privateKey)
      }
      unlinkSync(join(CACHE_DIR, f))  // expired
    } catch {
      unlinkSync(join(CACHE_DIR, f))  // decryption failed
    }
  }
  return null
}

export function loadSigner() {
  // 1. Try encrypted file cache (< 0.1ms, skip scrypt)
  const cached = readSignerCache()
  if (cached) return { account: cached, cleanup: () => {} }

  // 2. Cache miss → scrypt decrypt (~1.5s)
  const json = readFileSync(KS_PATH, "utf8")
  let w
  try { w = Wallet.fromEncryptedJsonSync(json, getPassword()) }
  catch (e) {
    if ((e.message || "").toLowerCase().match(/password|decrypt/))
      throw new Error("Wrong password — decryption failed.")
    throw e
  }
  const account = privateKeyToAccount(w.privateKey)
  // Do NOT write cache here — cache is written by unlockAndCache (bound to session TTL)
  return { account, cleanup: () => {} }
}

// Decrypt + write encrypted cache. Called ONLY by session.js unlockWallet.
// privateKey never leaves this function — decrypted, cached, and bridged within the same scope.
export function unlockAndCache(sessionId, expiresISO) {
  const json = readFileSync(KS_PATH, "utf8")
  const w = Wallet.fromEncryptedJsonSync(json, getPassword())
  writeSignerCache(sessionId, w.privateKey, expiresISO)
  return { account: privateKeyToAccount(w.privateKey) }
}

export function clearSignerCache() {
  if (!existsSync(CACHE_DIR)) return
  for (const f of readdirSync(CACHE_DIR).filter(f => f.endsWith(".key"))) unlinkSync(join(CACHE_DIR, f))
}
```

**Performance profile**:
```
node wallet-cli.js unlock       # scrypt 1.5s → write session + write .signer-cache (AES encrypted)
node wallet-cli.js send ...     # read .signer-cache → AES decrypt < 0.1ms → send
node wallet-cli.js send ...     # read .signer-cache → AES decrypt < 0.1ms → send
node wallet-cli.js lock         # delete sessions/ + delete .signer-cache/
```

**Other exports — full implementations**:

```javascript
export async function initWallet() {
  if (existsSync(KS_PATH)) throw new Error("Wallet already exists.")
  const w = Wallet.createRandom()
  const json = await w.encrypt(getPassword(), { scrypt: { N: 262144 } })
  if (!existsSync(WALLET_DIR)) mkdirSync(WALLET_DIR, { mode: 0o700 })
  writeFileSync(KS_PATH, json, { mode: 0o600 })
  writeFileSync(META_PATH, JSON.stringify({ address: w.address, smartAccounts: {} }), { mode: 0o600 })
  return { status: "created", address: w.address }
}

export async function importWallet(mnemonic) {
  if (existsSync(KS_PATH)) throw new Error("Wallet already exists.")
  const w = Wallet.fromPhrase(mnemonic.trim())
  const json = await w.encrypt(getPassword(), { scrypt: { N: 262144 } })
  if (!existsSync(WALLET_DIR)) mkdirSync(WALLET_DIR, { mode: 0o700 })
  writeFileSync(KS_PATH, json, { mode: 0o600 })
  writeFileSync(META_PATH, JSON.stringify({ address: w.address, smartAccounts: {} }), { mode: 0o600 })
  return { status: "imported", address: w.address }
}

export async function changePassword() {
  const newPw = process.env.NEW_WALLET_PASSWORD
  if (!newPw) throw new Error("NEW_WALLET_PASSWORD environment variable required.")
  const json = readFileSync(KS_PATH, "utf8")
  const w = Wallet.fromEncryptedJsonSync(json, getPassword())
  const newJson = await w.encrypt(newPw, { scrypt: { N: 262144 } })
  writeFileSync(KS_PATH, newJson, { mode: 0o600 })
  clearSignerCache()
  return { status: "password_changed" }
}

export function exportMnemonic() {
  const json = readFileSync(KS_PATH, "utf8")
  const w = Wallet.fromEncryptedJsonSync(json, getPassword())
  if (!w.mnemonic) throw new Error("Wallet has no mnemonic (imported from private key).")
  return {
    mnemonic: w.mnemonic.phrase,
    warning: "Store this offline. Anyone with these words has full access to your funds."
  }
}

export function getAddress(type = "eoa", chainId) {
  try {
    const meta = JSON.parse(readFileSync(META_PATH, "utf8"))
    if (type === "smart") return meta.smartAccounts?.[String(chainId)] || null
    return meta.address
  } catch (err) {
    if (err.code === "ENOENT") throw new Error("No wallet found. Run 'init' first.")
    if (err instanceof SyntaxError) throw new Error("Wallet metadata corrupted. Re-import with 'import --mnemonic'.")
    throw err
  }
}

export function saveSmartAccountAddress(chainId, addr) {
  const meta = JSON.parse(readFileSync(META_PATH, "utf8"))
  if (meta.smartAccounts?.[String(chainId)] === addr) return  // dedup
  if (!meta.smartAccounts) meta.smartAccounts = {}
  meta.smartAccounts[String(chainId)] = addr
  writeFileSync(META_PATH, JSON.stringify(meta), { mode: 0o600 })
}

export function getReceiveInfo(chainId) {
  return {
    eoaAddress: getAddress("eoa"),
    smartAccountAddress: chainId ? getAddress("smart", chainId) : null,
    note: "Send to EOA address for direct transactions. Smart Account address is for gasless operations (if deployed)."
  }
}
```

**Disk format**: keystore.enc = raw output of ethers `wallet.encrypt()` (Ethereum V3 JSON). No wrapping. Directly importable by MetaMask / geth.

---

### 3.3 session.js — HMAC-Signed Session Tokens

**Imports**:

```javascript
import { randomBytes, createHmac, timingSafeEqual } from "node:crypto"
import { readFileSync, writeFileSync, readdirSync, unlinkSync, existsSync, mkdirSync } from "node:fs"
import { join } from "node:path"
import { unlockAndCache, clearSignerCache } from "./keystore.js"
```

**HMAC tamper-proofing**: `.session-secret` file stores a 32-byte random key (created by setup.sh). Each session file includes an `_hmac` field. Validation uses `timingSafeEqual`.

**Constants and helpers**:

```javascript
const WALLET_DIR = join(process.env.HOME, ".openclaw-wallet")
const SESSIONS_DIR = join(WALLET_DIR, "sessions")
const SECRET_PATH = join(WALLET_DIR, ".session-secret")

function getSessionSecret() {
  return Buffer.from(readFileSync(SECRET_PATH, "utf8").trim(), "hex")
}

function signSession(data) {
  return createHmac("sha256", getSessionSecret())
    .update(JSON.stringify(data)).digest("hex")
}
```

**Exports**:

| Function | Description |
|----------|------------|
| `unlockWallet(duration, scope)` | unlockAndCache() decrypt+cache → randomBytes → write session file + HMAC |
| `validateSession(tokenId)` | Read file → HMAC verify → expiry check |
| `requireScope(tokenId, needed)` | validateSession + scope hierarchy (read < transfer < full) |
| `lockWallet()` | Delete all session files + clearSignerCache() |

**unlockWallet implementation** (privateKey never passes through session.js):

```javascript
export function unlockWallet(durationSec = 3600, scope = "full") {
  const id = "wlt_" + randomBytes(16).toString("hex")
  const expires = new Date(Date.now() + durationSec * 1000).toISOString()

  // Decrypt + write encrypted cache (privateKey stays inside keystore.js)
  unlockAndCache(id, expires)

  // Ensure sessions directory exists (in case setup.sh wasn't run or dir was deleted)
  if (!existsSync(SESSIONS_DIR)) mkdirSync(SESSIONS_DIR, { mode: 0o700, recursive: true })

  // Write session token + HMAC
  const data = { id, scope, created: new Date().toISOString(), expires }
  const hmac = signSession(data)
  writeFileSync(join(SESSIONS_DIR, id + ".json"),
    JSON.stringify({ ...data, _hmac: hmac }), { mode: 0o600 })

  return { sessionToken: id, expires }
}

export function validateSession(tokenId) {
  const filePath = join(SESSIONS_DIR, tokenId + ".json")
  if (!existsSync(filePath)) throw new Error("Invalid or expired session token.")
  const raw = JSON.parse(readFileSync(filePath, "utf8"))
  const { _hmac, ...data } = raw
  // HMAC verification (timing-safe)
  const expected = Buffer.from(signSession(data), "hex")
  const actual = Buffer.from(_hmac, "hex")
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    throw new Error("Session token integrity check failed.")
  }
  if (new Date(data.expires) <= new Date()) {
    unlinkSync(filePath)  // clean up expired session
    throw new Error("Invalid or expired session token.")
  }
  return data  // { id, scope, created, expires }
}

const SCOPE_LEVELS = { read: 1, transfer: 2, full: 3 }

export function requireScope(tokenId, needed) {
  const session = validateSession(tokenId)
  if ((SCOPE_LEVELS[session.scope] || 0) < (SCOPE_LEVELS[needed] || 0)) {
    throw new Error(`Scope '${session.scope}' insufficient; '${needed}' required.`)
  }
  return session
}

export function lockWallet() {
  // Delete all session files
  if (existsSync(SESSIONS_DIR)) {
    for (const f of readdirSync(SESSIONS_DIR)) unlinkSync(join(SESSIONS_DIR, f))
  }
  // Delete signer cache
  clearSignerCache()
  return { status: "locked" }
}
```

---

### 3.4 tx-logger.js — Hash-Chain Audit Log

**Imports**:

```javascript
import { createHash } from "node:crypto"
import { readFileSync, appendFileSync, existsSync } from "node:fs"
import { join } from "node:path"
```

**Constants**:

```javascript
const LOG_PATH = join(process.env.HOME, ".openclaw-wallet", "tx-log.jsonl")
```

**Exports**: `logTransaction(data)`, `getHistory(chain, limit)`, `verifyIntegrity()`

Each record: `{ timestamp, ...data, _prevHash, _hash: SHA256(prevHash + JSON(data)) }`

Provides tamper detection (not prevention — documented limitation).

**Critical**: `getHistory` and `verifyIntegrity` must return empty results (not throw) when `tx-log.jsonl` does not exist. This is the normal state before the first transaction. If `getHistory` throws ENOENT, then `tx-validator`'s daily limit check will fail, blocking the very first transaction.

```javascript
export function logTransaction(data) {
  // Read last hash for chain continuity
  let prevHash = "0"
  if (existsSync(LOG_PATH)) {
    const lines = readFileSync(LOG_PATH, "utf8").trim().split("\n").filter(Boolean)
    if (lines.length > 0) {
      const last = JSON.parse(lines[lines.length - 1])
      prevHash = last._hash
    }
  }
  // Build content (timestamp + data), then hash it.
  // verifyIntegrity reconstructs the same content via { ...entry, _prevHash: undefined, _hash: undefined }
  const content = { timestamp: new Date().toISOString(), ...data }
  const hashInput = prevHash + JSON.stringify(content)
  const _hash = createHash("sha256").update(hashInput).digest("hex")
  const entry = { ...content, _prevHash: prevHash, _hash }
  appendFileSync(LOG_PATH, JSON.stringify(entry) + "\n", { mode: 0o600 })
  return entry
}

export function getHistory(chain, limit = 50) {
  if (!existsSync(LOG_PATH)) return []  // no log yet — normal for new wallets
  const lines = readFileSync(LOG_PATH, "utf8").trim().split("\n").filter(Boolean)
  let entries = lines.map(l => JSON.parse(l))
  if (chain) entries = entries.filter(e => e.chain === chain || e.chainId === chain)
  return entries.slice(-limit)
}

export function verifyIntegrity() {
  if (!existsSync(LOG_PATH)) return { valid: true, entries: 0 }
  const lines = readFileSync(LOG_PATH, "utf8").trim().split("\n").filter(Boolean)
  let prevHash = "0"
  for (const line of lines) {
    const entry = JSON.parse(line)
    const expected = createHash("sha256")
      .update(prevHash + JSON.stringify({ ...entry, _prevHash: undefined, _hash: undefined }))
      .digest("hex")
    if (entry._hash !== expected) return { valid: false, brokenAt: entry.timestamp }
    prevHash = entry._hash
  }
  return { valid: true, entries: lines.length }
}
```

---

### 3.5 tx-validator.js — Pre-Transaction Safety Checks

**Imports**:

```javascript
import { isAddress, getAddress as checksumAddr } from "viem"
import { getAddress as walletGetAddress } from "./keystore.js"
import { getHistory } from "./tx-logger.js"
import { loadConfig, resolveChainId, viemChain } from "./chains.js"
```

**validateTransaction({ to, amount, asset, chain })**:

1. **Address validation**: isAddress → getAddress checksum → reject zero address → reject self-send (check both EOA and Smart Account addresses)
2. **Allowlist**: if config.allowlistMode is true, check allowlistedRecipients
3. **Daily limit**: read tx-log.jsonl past 24h cumulative, verify total + current ≤ dailyLimits
4. **Per-tx limit**: verify amount ≤ perTransactionMax

**Amount comparison**: Config limits (`dailyLimits`, `perTransactionMax`) are strings in **human-readable units** (e.g. `"1000"` = 1000 USDC, `"0.5"` = 0.5 ETH). CLI `amount` is also a human-readable string. Compare via `parseFloat`:

```javascript
function checkLimit(amount, limitStr, label) {
  if (!limitStr) return  // no limit configured
  if (parseFloat(amount) > parseFloat(limitStr)) {
    throw new Error(`${label} exceeded: ${amount} > ${limitStr}`)
  }
}

function checkDailyLimit(amount, asset, chain) {
  const cfg = loadConfig()
  // Resolve null asset (native transfer) to chain's native currency symbol
  // This matches how sendDirect logs it: asset || chainObj.nativeCurrency.symbol
  const resolvedAsset = asset || (() => {
    try { return viemChain(resolveChainId(chain)).nativeCurrency.symbol }
    catch { return "native" }
  })()
  const limitStr = cfg.dailyLimits?.[resolvedAsset.toUpperCase()] || cfg.dailyLimits?.default
  if (!limitStr) return
  const history = getHistory(chain)
  const since = Date.now() - 24 * 60 * 60 * 1000
  const spent = history
    .filter(e => new Date(e.timestamp).getTime() > since && e.asset === resolvedAsset)
    .reduce((sum, e) => sum + parseFloat(e.amount), 0)
  if (spent + parseFloat(amount) > parseFloat(limitStr)) {
    throw new Error(`Daily limit exceeded for ${resolvedAsset}.`)
  }
}
```

**validateBatchOps(operations, chain)**: Each op in batch goes through validation. **Raw call type is forbidden** — only transfer and approve allowed.

---

### 3.6 bundler.js — Fallback Transport

**Imports**:

```javascript
import { http, fallback } from "viem"
import { createBundlerClient, createPaymasterClient } from "viem/account-abstraction"
import { viemChain, resolveChainId, loadConfig } from "./chains.js"
```

Uses viem's built-in `fallback()` transport for automatic failover:

```javascript
function expandUrl(template, chainId, apiKey) {
  // Resolve chain name for {chainName} placeholder
  // Alchemy requires specific names like "base-mainnet", "arb-mainnet"
  let chainName
  try {
    const cfg = loadConfig()
    for (const [name, entry] of Object.entries(cfg.chains || {})) {
      if (entry.chainId === chainId) {
        chainName = entry.alchemyName || name  // prefer Alchemy-specific name
        break
      }
    }
  } catch { /* ignore */ }
  if (!chainName) {
    const chain = viemChain(chainId)
    chainName = (chain.name || `chain-${chainId}`).toLowerCase().replace(/\s+/g, "-")
  }
  return template
    .replace("{chainId}", String(chainId))
    .replace("{chainName}", chainName)
    .replace("{key}", apiKey)
}

export function createClients(chainNameOrId) {
  const chainId = resolveChainId(chainNameOrId)
  const chain = viemChain(chainId)
  const cfg = loadConfig()

  const providers = cfg.bundlerProviders
    .filter(p => process.env[p.envKey])
    .sort((a, b) => a.priority - b.priority)

  if (providers.length === 0)
    throw new Error("No bundler API key set. Export PIMLICO_API_KEY, ALCHEMY_API_KEY, or STACKUP_API_KEY.")

  // Separate transports for bundler and paymaster (URLs differ for Alchemy/Stackup)
  const bundlerTransports = providers.map(p =>
    http(expandUrl(p.bundlerUrlTemplate, chainId, process.env[p.envKey]), { timeout: p.timeout })
  )
  const paymasterTransports = providers.map(p =>
    http(expandUrl(p.paymasterUrlTemplate || p.bundlerUrlTemplate, chainId, process.env[p.envKey]), { timeout: p.timeout })
  )

  return {
    bundlerClient: createBundlerClient({ chain, transport: fallback(bundlerTransports) }),
    paymasterClient: createPaymasterClient({ chain, transport: fallback(paymasterTransports) }),
  }
}
```

**URL expansion**: Pimlico uses `{chainId}` (universal). Alchemy uses `{chainName}` which requires Alchemy-specific names (e.g. `"base-mainnet"`, `"arb-mainnet"`). These don't match our config chain names (`"base"`, `"arbitrum"`). Each chain config entry can include an optional `alchemyName` field:

```json
"base": { "chainId": 8453, "alchemyName": "base-mainnet", ... }
```

expandUrl resolves `{chainName}` by checking `alchemyName` first, then falling back to config chain name:

---

### 3.7 paymaster.js — Runtime Strategy Detection

**Imports**:

```javascript
import { erc20Abi } from "viem"
import { resolveChainId, chainConfig, publicClient, tokenInfo } from "./chains.js"
import { getAddress } from "./keystore.js"
import { createClients } from "./bundler.js"  // used by isGaslessAvailable only
```

No hardcoded SPONSORED_CHAINS. `selectStrategy` returns a **strategy queue** (priority-ordered), tried sequentially by the caller:

```javascript
async function userHasStablecoin(chainId) {
  try {
    const addr = getAddress("eoa")
    const { address: usdcAddr } = await tokenInfo(chainId, "USDC")
    const client = publicClient(chainId)
    const bal = await client.readContract({
      address: usdcAddr, abi: erc20Abi,
      functionName: "balanceOf", args: [addr]
    })
    return BigInt(bal) >= 10_000n  // ≥ 0.01 USDC (6 decimals) or ≥ 0.00000000000001 (18 decimals)
  } catch { return false }
}

export async function selectStrategy(chain) {
  const chainId = resolveChainId(chain)
  const strategies = []
  const cfg = chainConfig(chain)  // may be null (Tier 1 chain)

  if (cfg?.gasStrategy === "verifying_paymaster") strategies.push("verifying_paymaster")
  if (await userHasStablecoin(chainId)) strategies.push("erc20_paymaster")
  strategies.push("smart_account")  // fallback

  return strategies
}
```

**isGaslessAvailable(chainId)** — runtime probe for chain-info command:

```javascript
export async function isGaslessAvailable(chainNameOrId) {
  try {
    const { bundlerClient } = createClients(chainNameOrId)
    const entryPoints = await bundlerClient.request({
      method: "eth_supportedEntryPoints", params: []
    })
    return { available: true, entryPoints }
  } catch (err) {
    return { available: false, reason: err.message }
  }
}
```

**paymasterFor(chainNameOrId, strategy, paymasterClient)** — wraps the given paymasterClient with strategy-specific context:

```javascript
export function paymasterFor(chainNameOrId, strategy, paymasterClient) {
  const chainId = resolveChainId(chainNameOrId)

  if (strategy === "verifying_paymaster") {
    return paymasterClient  // standard viem PaymasterClient, no extra context
  }

  if (strategy === "erc20_paymaster") {
    // Wrap paymasterClient to inject token context on every request
    const cfg = chainConfig(chainId)
    const usdcAddr = cfg?.tokens?.USDC?.address
    return {
      async getPaymasterData(params) {
        return paymasterClient.getPaymasterData({
          ...params, context: { token: usdcAddr }
        })
      },
      async getPaymasterStubData(params) {
        return paymasterClient.getPaymasterStubData({
          ...params, context: { token: usdcAddr }
        })
      },
    }
  }

  return paymasterClient  // fallback: smart_account strategy uses standard paymaster
}
```

---

### 3.8 tx-router.js — Transaction Routing ★

Unified entry point for all write operations (send, batch, approve).

**Imports**:

```javascript
import { resolveChainId, publicClient, viemChain, loadConfig } from "./chains.js"
import { getAddress } from "./keystore.js"
import { sendDirect } from "./direct-tx.js"
import { sendGasless } from "./gasless-tx.js"
import { requireScope } from "./session.js"
import { validateTransaction, validateBatchOps } from "./tx-validator.js"
import { logTransaction } from "./tx-logger.js"
```

**selectMode — automatic routing**:

```javascript
async function selectMode(chain, asset) {
  const chainId = resolveChainId(chain)
  const client = publicClient(chainId)
  const eoaAddr = getAddress("eoa")
  const balance = await client.getBalance({ address: eoaAddr })
  const gasPrice = await client.getGasPrice()
  const estimatedGas = asset ? 65_000n : 21_000n
  const needed = gasPrice * estimatedGas * 2n  // 2x buffer

  if (balance >= needed) return "direct"

  // Want gasless — check bundler key exists
  const cfg = loadConfig()
  const hasKey = cfg.bundlerProviders.some(p => process.env[p.envKey])
  if (hasKey) return "gasless"

  // Neither path available
  throw new Error(
    `Insufficient native gas for direct transaction (have: ${balance}, need: ~${needed}), ` +
    `and no bundler API key configured for gasless mode. ` +
    `Either: (1) fund the EOA with native gas, or (2) set PIMLICO_API_KEY for gasless transactions.`
  )
}

export async function sendTransaction({ sessionToken, to, amount, asset, chain, mode }) {
  requireScope(sessionToken, "transfer")
  await validateTransaction({ to, amount, asset, chain })

  const selectedMode = mode || await selectMode(chain, asset)

  const result = selectedMode === "direct"
    ? await sendDirect({ to, amount, asset, chain })
    : await sendGasless({ to, amount, asset, chain })

  await logTransaction(result)
  return result
}

// batchTransaction, approveToken follow identical routing logic:
// requireScope → validateBatchOps/validateTransaction → selectMode → sendDirect or sendGasless variant → logTransaction
// Implement by following the sendTransaction pattern above.
```

---

### 3.9 direct-tx.js — EOA Direct Transactions (Default, Most Frequent)

**The simplest and most important module.**

```javascript
import { createWalletClient, http, encodeFunctionData, parseUnits, erc20Abi, getAddress as checksumAddr } from "viem"
import { loadSigner } from "./keystore.js"
import { viemChain, publicClient, tokenInfo, resolveChainId, getRpcUrl } from "./chains.js"

export async function sendDirect({ to, amount, asset, chain }) {
  const chainId = resolveChainId(chain)
  const chainObj = viemChain(chainId)
  const { account: signer } = loadSigner()  // hits encrypted cache → < 0.1ms

  const walletClient = createWalletClient({
    account: signer, chain: chainObj,
    transport: http(getRpcUrl(chainId)),     // uses rpcOverrides if configured
  })

  let hash
  if (asset) {
    const { address: tokenAddr, decimals } = await tokenInfo(chainId, asset)
    hash = await walletClient.sendTransaction({
      to: tokenAddr,
      data: encodeFunctionData({
        abi: erc20Abi, functionName: "transfer",
        args: [checksumAddr(to), parseUnits(amount, decimals)]
      }),
    })
  } else {
    const client = publicClient(chainId)
    const balance = await client.getBalance({ address: signer.address })
    const value = parseUnits(amount, chainObj.nativeCurrency.decimals)
    const gasPrice = await client.getGasPrice()
    if (balance < value + gasPrice * 21_000n)
      throw new Error("Insufficient balance for transfer + gas.")

    hash = await walletClient.sendTransaction({ to: checksumAddr(to), value })
  }

  const receipt = await publicClient(chainId).waitForTransactionReceipt({
    hash,
    timeout: 120_000,          // 2-minute timeout prevents agent from hanging on stuck tx
    confirmations: 1,
  })
  return {
    status: "sent", mode: "direct", txHash: hash,
    chain: chainObj.name, to, amount,
    asset: asset || chainObj.nativeCurrency.symbol,
    gasUsed: receipt.gasUsed.toString(),
    blockNumber: Number(receipt.blockNumber),
  }
}
```

**Properties**: Zero external dependencies (no Bundler/Paymaster), 21k gas, ~1s latency. Wallet remains functional even if all bundlers are down.

---

### 3.10 balance.js — Balance Queries (Independent of Bundler)

**Why independent**: Balance queries are pure `publicClient.readContract` operations. Users without PIMLICO_API_KEY should still be able to check balances.

**Imports**:

```javascript
import { erc20Abi, formatUnits } from "viem"
import { requireScope } from "./session.js"
import { getAddress } from "./keystore.js"
import { resolveChainId, publicClient, viemChain, chainConfig, tokenInfo, loadConfig } from "./chains.js"
```

**getBalance — parallel queries + dual address**:

```javascript
export async function getBalance(sessionToken, chain, asset) {
  requireScope(sessionToken, "read")
  const chainId = resolveChainId(chain)
  const client = publicClient(chainId)
  const eoaAddr = getAddress("eoa")
  const smartAddr = getAddress("smart", chainId)
  const addrs = [eoaAddr, smartAddr].filter(Boolean)
  const chainObj = viemChain(chainId)
  const cfg = chainConfig(chainId)

  const queries = []
  // Custom token info fetched OUTSIDE the loop (one RPC call shared by both addresses)
  let customTokenInfo = null
  if (asset && /^0x/i.test(asset)) {
    customTokenInfo = await tokenInfo(chainId, asset)
  }

  for (const addr of addrs) {
    // Native balance
    queries.push(
      client.getBalance({ address: addr })
        .then(b => ({ addr, sym: chainObj.nativeCurrency.symbol, bal: b, dec: chainObj.nativeCurrency.decimals }))
        .catch(() => null)
    )
    // Preconfigured tokens
    for (const [sym, info] of Object.entries(cfg?.tokens || {})) {
      if (asset && sym !== asset.toUpperCase()) continue
      queries.push(
        client.readContract({ address: info.address, abi: erc20Abi, functionName: "balanceOf", args: [addr] })
          .then(b => ({ addr, sym, bal: b, dec: info.decimals }))
          .catch(() => null)
      )
    }
    // Custom token by contract address
    if (customTokenInfo) {
      queries.push(
        client.readContract({ address: customTokenInfo.address, abi: erc20Abi, functionName: "balanceOf", args: [addr] })
          .then(b => ({ addr, sym: customTokenInfo.symbol, bal: b, dec: customTokenInfo.decimals }))
          .catch(() => null)
      )
    }
  }

  const results = (await Promise.allSettled(queries))
    .filter(r => r.status === "fulfilled" && r.value).map(r => r.value)

  const balances = {}
  for (const { addr, sym, bal, dec } of results) {
    const label = addrs.length > 1 ? `${sym}(${addr === eoaAddr ? "EOA" : "Smart"})` : sym
    balances[label] = formatUnits(BigInt(bal), dec)
  }

  return { chain: chainObj.name, chainId, eoaAddress: eoaAddr, smartAccountAddress: smartAddr || null, balances }
}
```

**getAllowances**:

```javascript
export async function getAllowances(sessionToken, chain, asset, spender) {
  requireScope(sessionToken, "read")
  const chainId = resolveChainId(chain)
  const chainObj = viemChain(chainId)
  const client = publicClient(chainId)
  const eoaAddr = getAddress("eoa")
  const { address: tokenAddr, symbol, decimals } = await tokenInfo(chainId, asset)

  const spenders = spender
    ? [{ name: "specified", address: spender }]
    : []

  const results = []
  for (const s of spenders) {
    const allowance = await client.readContract({
      address: tokenAddr, abi: erc20Abi,
      functionName: "allowance", args: [eoaAddr, s.address]
    })
    results.push({ spender: s.address, name: s.name, allowance: formatUnits(allowance, decimals) })
  }
  return { token: symbol, chain: chainObj.name, allowances: results }
}
```

**getTxStatus**:

```javascript
export async function getTxStatus(txHash, chain) {
  const client = publicClient(resolveChainId(chain))
  try {
    const receipt = await client.getTransactionReceipt({ hash: txHash })
    return {
      status: receipt.status === "success" ? "confirmed" : "reverted",
      blockNumber: Number(receipt.blockNumber),
      gasUsed: receipt.gasUsed.toString(),
    }
  } catch {
    return { status: "pending" }
  }
}
```

**getPortfolio** — balance across all configured chains:

```javascript
export async function getPortfolio(sessionToken) {
  requireScope(sessionToken, "read")
  const cfg = loadConfig()
  const chainNames = Object.keys(cfg.chains || {})

  const results = await Promise.allSettled(
    chainNames.map(name => getBalance(sessionToken, name, null))
  )

  const chains = chainNames.map((name, i) => {
    const r = results[i]
    if (r.status === "fulfilled") return r.value
    return { chain: name, chainId: cfg.chains[name]?.chainId, error: r.reason?.message }
  })

  return { chains }
}
```

---

### 3.11 gasless-tx.js — ERC-4337 Gasless Transactions

**Imports**:

```javascript
import { encodeFunctionData, parseUnits, erc20Abi, getAddress as checksumAddr } from "viem"
import { entryPoint07Address } from "viem/account-abstraction"
import { createSmartAccountClient } from "permissionless"
import { toEcdsaKernelSmartAccount } from "permissionless/accounts"
import { loadSigner, getAddress, saveSmartAccountAddress } from "./keystore.js"
import { viemChain, publicClient, tokenInfo, resolveChainId, chainConfig } from "./chains.js"
import { createClients } from "./bundler.js"
import { selectStrategy, paymasterFor } from "./paymaster.js"
```

**buildClient(chain, strategy)** — creates SmartAccountClient for a given strategy:

```javascript
async function buildClient(chain, strategy) {
  const chainId = resolveChainId(chain)
  const chainObj = viemChain(chainId)
  const client = publicClient(chainId)
  const { account: signer } = loadSigner()

  const smartAccount = await toEcdsaKernelSmartAccount({
    client,
    owners: [signer],
    entryPoint: { address: entryPoint07Address, version: "0.7" },
  })

  // Dedup: only write to meta.json if not already recorded
  try {
    if (getAddress("smart", chainId) !== smartAccount.address) {
      saveSmartAccountAddress(chainId, smartAccount.address)
    }
  } catch {
    saveSmartAccountAddress(chainId, smartAccount.address)
  }

  const { bundlerClient, paymasterClient } = createClients(chainId)
  const paymaster = paymasterFor(chainId, strategy, paymasterClient)

  const smartAccountClient = createSmartAccountClient({
    account: smartAccount,
    chain: chainObj,
    bundlerTransport: bundlerClient.transport,
    paymaster,
  })

  return { smartAccountClient, smartAccount, bundlerClient }
}
```

**sendGasless — strategy queue + waitForReceipt**:

```javascript
export async function sendGasless({ to, amount, asset, chain }) {
  const chainId = resolveChainId(chain)
  const strategies = await selectStrategy(chain)

  let lastError
  for (const strategy of strategies) {
    // Build client ONCE per strategy — reuse across nonce retries
    let smartAccountClient, smartAccount, bundlerClient
    try {
      ({ smartAccountClient, smartAccount, bundlerClient } = await buildClient(chain, strategy))
    } catch (err) {
      lastError = err
      continue  // strategy setup failed → next strategy
    }

    let callData
    if (asset) {
      const { address: tokenAddr, decimals } = await tokenInfo(chainId, asset)
      callData = { to: tokenAddr, value: 0n, data: encodeFunctionData({
        abi: erc20Abi, functionName: "transfer",
        args: [checksumAddr(to), parseUnits(amount, decimals)]
      })}
    } else {
      callData = { to: checksumAddr(to), value: parseUnits(amount, viemChain(chainId).nativeCurrency.decimals), data: "0x" }
    }

    const MAX_NONCE_RETRIES = 3
    for (let attempt = 0; attempt <= MAX_NONCE_RETRIES; attempt++) {
      try {
        // permissionless 0.3 API: pass calls array directly, no manual encodeCalls
        const userOpHash = await smartAccountClient.sendUserOperation({
          calls: [callData]
        })
        const receipt = await bundlerClient.waitForUserOperationReceipt({
          hash: userOpHash, timeout: 60_000,
        })

        return {
          status: "sent", mode: "gasless",
          txHash: receipt.receipt.transactionHash,  // real on-chain hash
          userOpHash,
          chain: viemChain(chainId).name, to, amount,
          asset: asset || viemChain(chainId).nativeCurrency.symbol,
          gasStrategy: strategy,
          smartAccount: smartAccount.address,
          blockNumber: Number(receipt.receipt.blockNumber),
        }
      } catch (err) {
        lastError = err
        // Nonce conflict → retry SAME strategy (inner loop)
        if ((err.message?.includes("AA25") || err.message?.includes("nonce")) && attempt < MAX_NONCE_RETRIES) {
          await new Promise(r => setTimeout(r, 2000))
          continue
        }
        // Paymaster rejected → break inner loop, try next strategy
        if (err.message?.match(/paymaster|AA3/i)) break
        throw err
      }
    }
  }
  throw new Error(`All gas strategies failed. Last error: ${lastError?.message}`)
}
```

**ERC-7579 extension point**: Kernel v3 natively supports ERC-7579. Via `createSmartAccountClient({...}).extend(erc7579Actions())`, modules (session key validator, automation executor, social recovery, etc.) can be installed. Not implemented in v1, but buildClient's smartAccountClient is already compatible.

---

### 3.12 eip7702.js — Optional EOA Delegation

**Imports**:

```javascript
import { createWalletClient, http } from "viem"
import { eip7702Actions } from "viem/experimental"
import { requireScope } from "./session.js"
import { loadSigner, getAddress } from "./keystore.js"
import { viemChain, publicClient, resolveChainId, getRpcUrl } from "./chains.js"
```

```javascript
export async function upgradeVia7702(sessionToken, chain, target = "kernel") {
  requireScope(sessionToken, "full")
  const chainId = resolveChainId(chain)
  const balance = await publicClient(chainId).getBalance({ address: getAddress("eoa") })
  if (balance === 0n) throw new Error(
    "EIP-7702 requires native gas in EOA. Use 'deploy-4337' for gasless setup instead."
  )
  // ... signAuthorization + sendTransaction({ authorizationList }) ...
}
```

---

### 3.13 signing.js — Message Signing

```javascript
import { loadSigner } from "./keystore.js"

export async function signMessage(message) {
  const { account } = loadSigner()
  return { signature: await account.signMessage({ message }), signer: account.address }
}
export async function signTypedData(typedData) {
  const { account } = loadSigner()
  return { signature: await account.signTypedData(typedData), signer: account.address }
}
```

---

### 3.14 wallet-cli.js — CLI Entry Point

**Password**: Always via environment variables. CLI has zero `--password` arguments.

**Command table**:

| Command | Password Source | Scope | Module |
|---------|----------------|-------|--------|
| `init` | WALLET_PASSWORD | none | keystore |
| `import --mnemonic "..."` | WALLET_PASSWORD | none | keystore |
| `unlock [--duration N] [--scope S]` | WALLET_PASSWORD | none | session |
| `lock` | none | none | session |
| `change-password` | WALLET_PASSWORD + NEW_WALLET_PASSWORD | none | keystore |
| `export` | WALLET_PASSWORD | none | keystore |
| `status --token T` | none | read | keystore |
| `balance --token T [--chain C] [--asset A]` | none | read | balance |
| `portfolio --token T` | none | read | balance |
| `history --token T [--chain C]` | none | read | tx-logger |
| `send --token T --to A --amount N [--asset A] [--chain C] [--mode M]` | WALLET_PASSWORD | transfer | tx-router |
| `batch --token T --ops JSON [--chain C] [--mode M]` | WALLET_PASSWORD | transfer | tx-router |
| `approve --token T --asset A --spender A --amount N [--chain C]` | WALLET_PASSWORD | transfer | tx-router |
| `estimate --to A --amount N [--asset A] [--chain C]` | none | none | tx-router |
| `tx-status --hash H --chain C` | none | none | balance |
| `sign-message --token T --message M` | WALLET_PASSWORD | transfer | signing |
| `receive [--chain C]` | none | none | keystore |
| `allowances --token T [--chain C] [--asset A] [--spender A]` | none | read | balance |
| `revoke --token T --asset A --spender A [--chain C]` | WALLET_PASSWORD | transfer | tx-router |
| `upgrade-7702 --token T [--chain C]` | WALLET_PASSWORD | full | eip7702 |
| `deploy-4337 --token T [--chain C]` | WALLET_PASSWORD | full | gasless-tx |
| `revoke-7702 --token T [--chain C]` | WALLET_PASSWORD | full | eip7702 |
| `chain-info --chain C` | none | none | chains + paymaster |
| `verify-log` | none | none | tx-logger |
| `chains` | none | none | chains |

**Additional command specs**:

**estimate** (exported from tx-router.js): Uses `getAddress("eoa")` for the sender address and `client.estimateGas()` RPC for accurate gas estimation. No session token required — estimate only reads public chain data. Fallback to hardcoded 65k/21k if RPC fails. Returns `{ direct: { estimatedGas, gasPrice, estimatedCost }, gasless: { available, cost } }`. Note: selectMode's internal routing still uses hardcoded constants (speed over precision).

**portfolio** (exported from balance.js): Iterates all chains in `loadConfig().chains`, calls `getBalance(sessionToken, chainName, null)` for each in parallel via `Promise.allSettled`. Returns `{ chains: [{ chain, chainId, balances }, ...] }`. Chains with RPC errors are included with `{ chain, error }` rather than omitted.

**chain-info**: Combines viemChain() + chainConfig() + isGaslessAvailable(). Returns `{ chainId, name, nativeCurrency, source, directTx: true, gasless: { available, provider }, configuredTokens }`.

**revoke**: Routes through selectMode to direct or gasless path. callData = `encodeFunctionData(erc20Abi, "approve", [spender, 0n])`.

**status** (routed to keystore.js): Returns wallet address, session validity (if `--token` provided), and Smart Account addresses per chain. `{ address, sessionValid, sessionExpires, smartAccounts: { "56": "0x...", ... } }`.

**history** (routed to tx-logger.js): Calls `getHistory(chain, limit)`. Returns last N transaction log entries as JSON array. Default limit 50, filterable by `--chain`.

**Global options**: `--pretty` (indented JSON), `--rpc-url URL` (custom RPC), `--native-symbol SYM` (native currency symbol for custom chains, default ETH)

**--chain default**: When `--chain` is omitted, read `loadConfig().defaultChain` (e.g. `"bsc"`). If config is unavailable, throw `"No --chain specified and no defaultChain in config."`.

**--rpc-url flow**: When the user passes `--rpc-url`, wallet-cli.js must call `viemChain(chainId, rpcUrl, nativeCurrency)` before any other operation. This registers the custom chain in the CUSTOM map so that subsequent calls to `publicClient`, `getRpcUrl`, etc. find it. Example:

```javascript
// In wallet-cli.js, before dispatching to any command:
const opts = cli.opts()

// Commands that don't need chain context — skip config/rpcUrl processing
const NO_CHAIN_COMMANDS = ["init", "import", "lock", "verify-log", "export", "change-password"]
const currentCmd = cli.args[0]

if (!NO_CHAIN_COMMANDS.includes(currentCmd)) {
  if (opts.rpcUrl) {
    const chainId = resolveChainId(opts.chain || "0")
    const nativeCurrency = opts.nativeSymbol
      ? { name: opts.nativeSymbol, symbol: opts.nativeSymbol, decimals: 18 }
      : undefined
    viemChain(chainId, opts.rpcUrl, nativeCurrency)  // registers in CUSTOM map
  }
}
// Resolve chain: explicit --chain > config defaultChain > undefined (commands that don't need it)
const chain = opts.chain || (NO_CHAIN_COMMANDS.includes(currentCmd) ? undefined : loadConfig().defaultChain)
```

**--chain** accepts name or ID: `--chain bsc`, `--chain 56`, `--chain avalanche`

**--asset** accepts symbol or contract address: `--asset usdc`, `--asset 0x55d398...`

**--mode**: `direct` (force EOA), `gasless` (force 4337), omit for automatic

**Output format**:

```javascript
function json(obj) { console.log(JSON.stringify(obj, null, cli.opts().pretty ? 2 : undefined)) }
function fail(msg) { console.error(JSON.stringify({ error: msg })); process.exit(1) }
```

**Version**: Read from package.json.

---

## 4. Configuration — default-config.json

```json
{
  "defaultChain": "bsc",
  "rpcOverrides": {
    "ethereum": "https://eth-mainnet.g.alchemy.com/v2/{ALCHEMY_API_KEY}",
    "base": "https://base-mainnet.g.alchemy.com/v2/{ALCHEMY_API_KEY}",
    "bsc": "https://bsc-dataseed1.binance.org"
  },
  "dailyLimits": { "USDC": "1000", "USDT": "1000", "ETH": "0.5", "BNB": "1.0", "default": "500" },
  "perTransactionMax": { "USDC": "500", "ETH": "0.25", "default": "250" },
  "confirmationThreshold": { "USDC": "200", "default": "100" },
  "allowlistMode": false,
  "allowlistedRecipients": [],
  "bundlerProviders": [
    { "name": "pimlico", "priority": 1, "timeout": 5000, "envKey": "PIMLICO_API_KEY",
      "bundlerUrlTemplate": "https://api.pimlico.io/v2/{chainId}/rpc?apikey={key}",
      "paymasterUrlTemplate": "https://api.pimlico.io/v2/{chainId}/rpc?apikey={key}" },
    { "name": "alchemy", "priority": 2, "timeout": 5000, "envKey": "ALCHEMY_API_KEY",
      "bundlerUrlTemplate": "https://{chainName}-bundler.g.alchemy.com/v2/{key}",
      "paymasterUrlTemplate": "https://{chainName}-paymaster.g.alchemy.com/v2/{key}" },
    { "name": "stackup", "priority": 3, "timeout": 8000, "envKey": "STACKUP_API_KEY",
      "bundlerUrlTemplate": "https://api.stackup.sh/v1/node/{key}",
      "paymasterUrlTemplate": "https://api.stackup.sh/v1/paymaster/{key}" }
  ],
  "chains": {
    "ethereum":     { "chainId": 1,        "alchemyName": "eth-mainnet", "gasStrategy": "erc20_paymaster", ... },
    "base":         { "chainId": 8453,     "alchemyName": "base-mainnet", "gasStrategy": "verifying_paymaster", ... },
    "bsc":          { "chainId": 56,       "gasStrategy": "erc20_paymaster", "tokens": { "USDC": { "decimals": 18 }, "USDT": { "decimals": 18 }, ... }},
    "arbitrum":     { "chainId": 42161,    "alchemyName": "arb-mainnet", ... },
    "optimism":     { "chainId": 10,       ... },
    "polygon":      { "chainId": 137,      ... },
    "avalanche":    { "chainId": 43114,    ... },
    "fantom":       { "chainId": 250,      ... },
    "base-sepolia": { "chainId": 84532,    ... },
    "sepolia":      { "chainId": 11155111, ... }
  },
  "customChains": []
}
```

**Config key convention**: `chains` is keyed by **chain name** (not chainId). Each entry contains a `chainId` numeric field. This matches the CLI `--chain bsc` interface — the same string used in CLI is the config key.

See `assets/default-config.json` for the full config with all token addresses.

---

## 5. Error Handling

| Source | Condition | Message |
|--------|-----------|---------|
| env | WALLET_PASSWORD not set | `"WALLET_PASSWORD environment variable required."` |
| keystore | Wrong password | `"Wrong password — decryption failed."` |
| keystore | Wallet exists | `"Wallet already exists."` |
| keystore | No wallet | `"No wallet found. Run 'init' first."` |
| config | config.json missing | `"Config not found. Run 'bash scripts/setup.sh' first."` |
| config | config.json corrupted | `"Config file corrupted. Delete and re-run setup.sh."` |
| meta | meta.json corrupted | `"Wallet metadata corrupted. Re-import with 'import --mnemonic'."` |
| session | Invalid token | `"Invalid or expired session token."` |
| session | HMAC mismatch | `"Session token integrity check failed."` |
| session | Insufficient scope | `"Scope 'read' insufficient; 'transfer' required."` |
| tx-validator | Invalid address | `"Invalid Ethereum address: 0x..."` |
| tx-validator | Daily limit | `"Daily limit exceeded for USDC."` |
| tx-validator | Batch raw call | `"Raw call type not allowed in batch."` |
| direct-tx | Insufficient balance | `"Insufficient balance for transfer + gas."` |
| tx-router | No gas + no key | `"Insufficient native gas and no bundler API key. Either fund EOA or set PIMLICO_API_KEY."` |
| chains | Unknown chain no RPC | `"Chain 99999 unknown. Provide --rpc-url."` |
| chains | Token not configured | `"Token 'USDC' not configured for chain 'bsc'. Use contract address: --asset 0x..."` |
| bundler | No API key | `"No bundler API key set. Export PIMLICO_API_KEY, ALCHEMY_API_KEY, or STACKUP_API_KEY."` |
| gasless | All strategies failed | `"All gas strategies failed. Last error: ..."` |
| eip7702 | EOA balance 0 | `"EIP-7702 requires native gas. Use 'deploy-4337' instead."` |
| keystore | change-password no new pw | `"NEW_WALLET_PASSWORD environment variable required."` |
| keystore | No mnemonic (pk import) | `"Wallet has no mnemonic (imported from private key)."` |

---

## 6. Acceptance Criteria

```bash
export PIMLICO_API_KEY="pm_xxx"
export WALLET_PASSWORD="test-pwd-123"

# 1. Install
bash scripts/setup.sh

# 2. Create wallet
node scripts/wallet-cli.js init
# → { "status": "created", "address": "0x..." }

# 3. Unlock + capture token
TOKEN=$(node scripts/wallet-cli.js unlock | python3 -c "import sys,json;print(json.load(sys.stdin)['sessionToken'])")
echo "Session: $TOKEN"

# 4. Multi-chain balance
node scripts/wallet-cli.js balance --token $TOKEN --chain base
node scripts/wallet-cli.js balance --token $TOKEN --chain bsc
node scripts/wallet-cli.js balance --token $TOKEN --chain 43114

# 5. Chain info
node scripts/wallet-cli.js chain-info --chain bsc
# → { "chainId": 56, "name": "BNB Smart Chain", "directTx": true, "gasless": { ... } }

# 6. Gas estimate
node scripts/wallet-cli.js estimate --to 0x0000000000000000000000000000000000000001 --amount 0.01 --chain base

# 7. Wrong password
WALLET_PASSWORD=wrong node scripts/wallet-cli.js unlock
# → { "error": "Wrong password — decryption failed." }

# 8. Change password
NEW_WALLET_PASSWORD="new-pwd" node scripts/wallet-cli.js change-password
export WALLET_PASSWORD="new-pwd"

# 9. Export mnemonic
node scripts/wallet-cli.js export
# → { "mnemonic": "...", "warning": "..." }

# 10. Log integrity
node scripts/wallet-cli.js verify-log

# 11. Custom chain (before lock — token still valid)
node scripts/wallet-cli.js balance --token $TOKEN --chain 99999 --rpc-url https://some-rpc.com

# 12. Contract address as asset (BSC USDT, before lock)
node scripts/wallet-cli.js balance --token $TOKEN --chain bsc --asset 0x55d398326f99059fF775485246999027B3197955

# 13. Lock
node scripts/wallet-cli.js lock

# 14. Expired token rejected (after lock)
node scripts/wallet-cli.js balance --token $TOKEN --chain bsc
# → { "error": "Invalid or expired session token." }
```

---

## 7. Implementation Order

```
Round 1 (Foundation — zero on-chain interaction):
  ① chains.js         → import * as viemChains, resolveChainId, tokenInfo, loadCustomChains
  ② keystore.js       → ethers encrypt/decrypt + AES-GCM signer file cache + unlockAndCache
  ③ session.js        → HMAC session tokens + calls unlockAndCache
  ④ tx-logger.js      → Hash-chain log
  ⑤ tx-validator.js   → Address validation + limits + batch validation
  ⑥ signing.js        → signMessage / signTypedData

Round 2 (Direct transactions + balance — most important):
  ⑦ balance.js        → getBalance, getAllowances, getTxStatus (no Bundler dependency)
  ⑧ direct-tx.js      → walletClient.sendTransaction (core path)
  ⑨ tx-router.js      → selectMode + unified send entry point

Round 3 (Gasless enhancement):
  ⑩ bundler.js        → fallback transport
  ⑪ paymaster.js      → Strategy queue + runtime detection
  ⑫ gasless-tx.js     → buildClient + sendGasless

Round 4 (Optional features + integration):
  ⑬ eip7702.js        → Optional EOA delegation
  ⑭ wallet-cli.js     → All commands (including estimate, chain-info, receive, revoke)
  ⑮ setup.sh + default-config.json
```

**setup.sh specification**:

```bash
#!/usr/bin/env bash
set -euo pipefail

WALLET_DIR="$HOME/.openclaw-wallet"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Install npm dependencies
cd "$SCRIPT_DIR/.."
npm install

# 2. Create runtime directory with strict permissions
mkdir -p "$WALLET_DIR" && chmod 0700 "$WALLET_DIR"
mkdir -p "$WALLET_DIR/sessions" && chmod 0700 "$WALLET_DIR/sessions"

# 3. Copy default config if not present (never overwrite user config)
if [ ! -f "$WALLET_DIR/config.json" ]; then
  cp "$SCRIPT_DIR/../assets/default-config.json" "$WALLET_DIR/config.json"
  chmod 0600 "$WALLET_DIR/config.json"
fi

# 4. Generate HMAC session secret if not present
if [ ! -f "$WALLET_DIR/.session-secret" ]; then
  openssl rand -hex 32 > "$WALLET_DIR/.session-secret"
  chmod 0600 "$WALLET_DIR/.session-secret"
fi

echo '{"status":"setup_complete","walletDir":"'"$WALLET_DIR"'"}'
```

**Each round is independently testable. After Round 2, the wallet can query balances and send transactions on all EVM chains.**

---

## 8. Do-Not-Do List

| # | ❌ Do NOT | ✅ Do Instead |
|---|----------|--------------|
| 1 | Pass password in CLI arguments | WALLET_PASSWORD env var |
| 2 | Hardcode chain list | `import * as viemChains` + defineChain |
| 3 | Hardcode token decimals | config.json `{ address, decimals }` or on-chain query |
| 4 | Route all transactions through ERC-4337 | Default to direct EOA, gasless on-demand |
| 5 | Hardcode SPONSORED_CHAINS | Strategy queue + runtime try/fallback |
| 6 | Manual retry logic | viem `fallback()` transport |
| 7 | Run scrypt on every transaction | AES-GCM encrypted signer file cache |
| 8 | Return userOpHash as txHash | `waitForUserOperationReceipt` for real on-chain hash |
| 9 | EIP-7702 as required gasless path | Optional optimization, requires native gas |
| 10 | Trust unsigned session files | HMAC signature verification |
| 11 | Skip batch validation | Every op through tx-validator, raw calls forbidden |
| 12 | Assume EOA = asset address | Query both EOA and Smart Account balances |
| 13 | Call scryptSync directly | Let ethers.js handle internally |
| 14 | Import ethers outside keystore.js | Strict boundary enforcement |
| 15 | Query balances serially | Promise.allSettled for parallelism |
| 16 | Silently fall back to native gas on Paymaster failure | Explicit error or degrade to next strategy |
| 17 | Use in-process variables for cross-command cache | AES-GCM encrypted file cache in .signer-cache/ |
| 18 | Put getBalance in gasless module | Independent balance.js, no Bundler dependency |
| 19 | Report only "no key" when both paths fail | Dual-path error message: fund EOA or set API key |
| 20 | Use permissionless@^0.2 | Use ^0.3 — semver 0.x caret only allows patch upgrades |
| 21 | Write plaintext privateKey to disk | AES-256-GCM encrypted cache, key derived from password |
| 22 | Pass privateKey outside keystore.js | unlockAndCache handles everything internally |
| 23 | Use public RPCs for transactions | config.json rpcOverrides with custom nodes |
| 24 | waitForReceipt without timeout | timeout: 120_000 to prevent agent from hanging |
| 25 | Use 0.2 sendUserOperation({ callData }) | 0.3 API: sendUserOperation({ calls: [...] }) |
| 26 | Hardcoded gas constants for user-facing estimate | client.estimateGas() RPC for accurate values |
| 27 | Share one transport for both bundler and paymaster | Separate transport arrays: bundlerUrlTemplate vs paymasterUrlTemplate |
| 28 | Nonce retry via `continue` in outer strategy loop | Inner retry loop (max 3) stays on same strategy; `break` for next strategy |
| 29 | Hardcode `dec: 18` for native balance | Use `chainObj.nativeCurrency.decimals` |
| 30 | `JSON.stringify(obj, indent)` — 2nd arg is replacer | `JSON.stringify(obj, null, indent)` — null replacer, 3rd arg is indent |
