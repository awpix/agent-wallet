#!/usr/bin/env bash
# ==============================================================================
# AWP Wallet — One-click deployment script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/awp-core/awp-wallet/main/install.sh | bash
#   # or
#   bash install.sh [OPTIONS]
#
# Options:
#   --dir <path>        Installation directory (default: ~/awp-wallet)
#   --password <pwd>    Wallet password (default: auto-generated 48-char random)
#   --no-init           Skip wallet initialization (setup only)
#   --pimlico <key>     Set PIMLICO_API_KEY for gasless transactions
#   --bsc-rpc <url>     Set BSC_RPC_URL for BSC chain
#   --help              Show this help message
# ==============================================================================
set -euo pipefail

# ---------- Defaults ----------
INSTALL_DIR="$HOME/awp-wallet"
WALLET_PASSWORD=""
AUTO_INIT=true
PIMLICO_API_KEY=""
BSC_RPC_URL=""
REPO_URL="https://github.com/awp-core/awp-wallet.git"

# ---------- Colors (stderr only, no interference with JSON) ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[awp-wallet]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[awp-wallet]${NC} $*" >&2; }
err()  { echo -e "${RED}[awp-wallet]${NC} $*" >&2; exit 1; }

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        INSTALL_DIR="$2"; shift 2 ;;
    --password)   WALLET_PASSWORD="$2"; shift 2 ;;
    --no-init)    AUTO_INIT=false; shift ;;
    --pimlico)    PIMLICO_API_KEY="$2"; shift 2 ;;
    --bsc-rpc)    BSC_RPC_URL="$2"; shift 2 ;;
    --help|-h)
      head -17 "$0" | tail -12
      exit 0 ;;
    *) err "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ---------- Pre-flight checks ----------
log "Checking prerequisites..."

# Node.js
if ! command -v node &>/dev/null; then
  err "Node.js not found. Install Node.js >= 20: https://nodejs.org/"
fi
NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 20 ]]; then
  err "Node.js >= 20 required (found: $(node -v)). Update: https://nodejs.org/"
fi

# npm
if ! command -v npm &>/dev/null; then
  err "npm not found. It should come with Node.js."
fi

# git
if ! command -v git &>/dev/null; then
  err "git not found. Install: sudo apt install git"
fi

# openssl (for password generation and session secret)
if ! command -v openssl &>/dev/null; then
  err "openssl not found. Install: sudo apt install openssl"
fi

log "Node.js $(node -v), npm $(npm -v), git $(git --version | cut -d' ' -f3)"

# ---------- Step 1: Clone, update, or use local ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "Updating existing installation at $INSTALL_DIR..."
  cd "$INSTALL_DIR"
  git pull --ff-only 2>/dev/null || warn "git pull failed (offline?), using existing code"
elif [[ -f "$SCRIPT_DIR/package.json" ]] && grep -q "awp-wallet" "$SCRIPT_DIR/package.json" 2>/dev/null; then
  # Running from the repo directory — use it directly
  if [[ "$INSTALL_DIR" != "$SCRIPT_DIR" ]]; then
    log "Copying local repo to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    cp -r "$SCRIPT_DIR/." "$INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/node_modules" "$INSTALL_DIR/.git"
  fi
  cd "$INSTALL_DIR"
else
  log "Cloning repository to $INSTALL_DIR..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# ---------- Step 2: Install dependencies ----------
log "Installing npm dependencies..."
npm install --no-audit --no-fund 2>&1 | tail -1

# ---------- Step 3: Register CLI command ----------
log "Registering awp-wallet command..."
if npm link 2>/dev/null; then
  log "Registered: $(which awp-wallet)"
elif sudo npm link 2>/dev/null; then
  log "Registered (sudo): $(which awp-wallet)"
else
  warn "npm link failed. Use 'node $INSTALL_DIR/scripts/wallet-cli.js' instead."
  warn "Or fix with: sudo npm link (from $INSTALL_DIR)"
fi

# ---------- Step 4: Create runtime directories ----------
WALLET_DIR="$HOME/.openclaw-wallet"
log "Setting up runtime directory at $WALLET_DIR..."
mkdir -p "$WALLET_DIR" && chmod 0700 "$WALLET_DIR"
mkdir -p "$WALLET_DIR/sessions" && chmod 0700 "$WALLET_DIR/sessions"
mkdir -p "$WALLET_DIR/.signer-cache" && chmod 0700 "$WALLET_DIR/.signer-cache"

# Copy default config (don't overwrite existing)
if [[ ! -f "$WALLET_DIR/config.json" ]]; then
  cp "$INSTALL_DIR/assets/default-config.json" "$WALLET_DIR/config.json"
  chmod 0600 "$WALLET_DIR/config.json"
  log "Default config copied (10 chains, 3 bundler providers)"
else
  log "Config already exists, preserved"
fi

# Generate HMAC session secret (don't overwrite existing)
if [[ ! -f "$WALLET_DIR/.session-secret" ]]; then
  openssl rand -hex 32 > "$WALLET_DIR/.session-secret"
  chmod 0600 "$WALLET_DIR/.session-secret"
fi

# ---------- Step 5: Update BSC RPC if provided ----------
if [[ -n "$BSC_RPC_URL" ]]; then
  # Update config.json rpcOverrides.bsc (use env vars to prevent shell injection)
  WALLET_DIR="$WALLET_DIR" BSC_RPC_URL="$BSC_RPC_URL" node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync(process.env.WALLET_DIR + '/config.json', 'utf8'));
    cfg.rpcOverrides.bsc = process.env.BSC_RPC_URL;
    fs.writeFileSync(process.env.WALLET_DIR + '/config.json', JSON.stringify(cfg, null, 2));
  "
  log "BSC RPC configured"
fi

# ---------- Step 6: Generate password if not provided ----------
if [[ -z "$WALLET_PASSWORD" ]]; then
  WALLET_PASSWORD=$(openssl rand -base64 36)
  log "Generated wallet password (48 chars, cryptographically random)"
fi

# ---------- Step 7: Initialize wallet ----------
if [[ "$AUTO_INIT" == true ]]; then
  if [[ -f "$WALLET_DIR/keystore.enc" ]]; then
    log "Wallet already exists, skipping init"
  else
    log "Initializing wallet..."
    INIT_RESULT=$(WALLET_PASSWORD="$WALLET_PASSWORD" node "$INSTALL_DIR/scripts/wallet-cli.js" init 2>&1)
    ADDRESS=$(echo "$INIT_RESULT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).address)")
    log "Wallet created: $ADDRESS"
  fi
fi

# ---------- Step 8: Verify installation ----------
log "Verifying installation..."
VERIFY_RESULT=$(WALLET_PASSWORD="$WALLET_PASSWORD" node "$INSTALL_DIR/scripts/wallet-cli.js" unlock --duration 10 2>&1)
TOKEN=$(echo "$VERIFY_RESULT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).sessionToken)")
node "$INSTALL_DIR/scripts/wallet-cli.js" lock >/dev/null 2>&1
log "Verification passed (unlock/lock cycle OK)"

# ---------- Done ----------
echo "" >&2
echo -e "${CYAN}============================================================${NC}" >&2
echo -e "${CYAN}  AWP Wallet installed successfully!${NC}" >&2
echo -e "${CYAN}============================================================${NC}" >&2
echo "" >&2
echo -e "  ${GREEN}Install dir:${NC}  $INSTALL_DIR" >&2
echo -e "  ${GREEN}Runtime dir:${NC}  $WALLET_DIR" >&2
echo -e "  ${GREEN}Command:${NC}      awp-wallet --version" >&2
echo "" >&2

if [[ "$AUTO_INIT" == true ]]; then
  echo -e "  ${GREEN}Wallet address:${NC}  $ADDRESS" >&2
fi

echo "" >&2
echo -e "  ${YELLOW}IMPORTANT — Save this password securely:${NC}" >&2
echo "" >&2
echo -e "  ${RED}WALLET_PASSWORD=${NC}${WALLET_PASSWORD}" >&2
echo "" >&2
echo -e "  Store it in your secret manager. You need it for:" >&2
echo -e "  unlock, send, approve, sign-message, change-password, export" >&2
echo "" >&2

if [[ -n "$PIMLICO_API_KEY" ]]; then
  echo -e "  ${GREEN}Gasless TX:${NC}  Enabled (PIMLICO_API_KEY set)" >&2
else
  echo -e "  ${YELLOW}Gasless TX:${NC}  Disabled (set PIMLICO_API_KEY to enable)" >&2
fi

echo "" >&2
echo -e "  Quick test:" >&2
echo -e "  ${CYAN}WALLET_PASSWORD=\"...\" awp-wallet unlock${NC}" >&2
echo -e "  ${CYAN}awp-wallet balance --token wlt_... --chain bsc${NC}" >&2
echo -e "  ${CYAN}awp-wallet lock${NC}" >&2
echo "" >&2

# Output machine-readable JSON to stdout (for OpenClaw to parse)
# NOTE: walletPassword is included for initial setup only — OpenClaw must store it
# in its encrypted secret store immediately and never log this output.
cat <<ENDJSON
{
  "status": "installed",
  "installDir": "$INSTALL_DIR",
  "walletDir": "$WALLET_DIR",
  "walletPassword": "$WALLET_PASSWORD",
  "address": "${ADDRESS:-null}",
  "command": "awp-wallet",
  "pimlicoEnabled": $([ -n "$PIMLICO_API_KEY" ] && echo true || echo false),
  "bscRpcConfigured": $([ -n "$BSC_RPC_URL" ] && echo true || echo false),
  "_warning": "Store walletPassword in your secret manager immediately. Do NOT log this output."
}
ENDJSON
