import { Wallet, encryptKeystoreJson } from "ethers"
import { privateKeyToAccount } from "viem/accounts"
import { createHash, createCipheriv, createDecipheriv, randomBytes } from "node:crypto"
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, unlinkSync } from "node:fs"
import { join } from "node:path"

const WALLET_DIR = join(process.env.HOME, ".openclaw-wallet")
const KS_PATH = join(WALLET_DIR, "keystore.enc")
const META_PATH = join(WALLET_DIR, "meta.json")

function getPassword() {
  const pw = process.env.WALLET_PASSWORD
  if (!pw) throw new Error("WALLET_PASSWORD environment variable required.")
  return pw
}

// --- AES-256-GCM encrypted signer cache ---
const CACHE_DIR = join(WALLET_DIR, ".signer-cache")

// Derive AES key from password via SHA-256 (not scrypt — scrypt's slowness is what we want to avoid)
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

// Read encrypted cache. Returns a viem LocalAccount or null.
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
      try { unlinkSync(join(CACHE_DIR, f)) } catch { /* already deleted by concurrent process */ }  // expired
    } catch {
      try { unlinkSync(join(CACHE_DIR, f)) } catch { /* already deleted by concurrent process */ }  // decryption failed
    }
  }
  return null
}

export function loadSigner() {
  // 1. Try encrypted file cache (< 0.1ms, skips scrypt)
  const cached = readSignerCache()
  if (cached) return { account: cached, cleanup: () => {} }

  // 2. Cache miss -> scrypt decryption (~1.5s)
  const json = readFileSync(KS_PATH, "utf8")
  let w
  try { w = Wallet.fromEncryptedJsonSync(json, getPassword()) }
  catch (e) {
    if ((e.message || "").toLowerCase().match(/password|decrypt|incorrect/))
      throw new Error("Wrong password — decryption failed.")
    throw e
  }
  const account = privateKeyToAccount(w.privateKey)
  // Don't write cache here — cache is written by unlockAndCache (bound to session TTL)
  return { account, cleanup: () => {} }
}

// Decrypt + write encrypted cache. Only called by session.js unlockWallet.
export function unlockAndCache(sessionId, expiresISO) {
  const json = readFileSync(KS_PATH, "utf8")
  let w
  try { w = Wallet.fromEncryptedJsonSync(json, getPassword()) }
  catch (e) {
    if ((e.message || "").toLowerCase().match(/password|decrypt|incorrect/))
      throw new Error("Wrong password — decryption failed.")
    throw e
  }
  writeSignerCache(sessionId, w.privateKey, expiresISO)
  return { account: privateKeyToAccount(w.privateKey) }
}

export function clearSignerCache() {
  if (!existsSync(CACHE_DIR)) return
  for (const f of readdirSync(CACHE_DIR).filter(f => f.endsWith(".key"))) unlinkSync(join(CACHE_DIR, f))
}

export async function initWallet() {
  if (existsSync(KS_PATH)) throw new Error("Wallet already exists.")
  const w = Wallet.createRandom()
  const json = await encryptKeystoreJson(w, getPassword(), { scrypt: { N: 262144 } })
  if (!existsSync(WALLET_DIR)) mkdirSync(WALLET_DIR, { mode: 0o700 })
  writeFileSync(KS_PATH, json, { mode: 0o600 })
  writeFileSync(META_PATH, JSON.stringify({ address: w.address, smartAccounts: {} }), { mode: 0o600 })
  return { status: "created", address: w.address }
}

export async function importWallet(mnemonic) {
  if (existsSync(KS_PATH)) throw new Error("Wallet already exists.")
  const w = Wallet.fromPhrase(mnemonic.trim())
  const json = await encryptKeystoreJson(w, getPassword(), { scrypt: { N: 262144 } })
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
  const newJson = await encryptKeystoreJson(w, newPw, { scrypt: { N: 262144 } })
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
  if (meta.smartAccounts?.[String(chainId)] === addr) return  // deduplicate
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
