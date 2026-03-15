#!/usr/bin/env bash
set -euo pipefail

WALLET_DIR="$HOME/.openclaw-wallet"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Install npm dependencies and register CLI command
cd "$SCRIPT_DIR/.."
npm install
if ! npm link 2>/dev/null; then
  echo '{"warning":"npm link failed. Run with sudo or use: node scripts/wallet-cli.js"}' >&2
fi

# 2. Create runtime directories (strict permissions)
mkdir -p "$WALLET_DIR" && chmod 0700 "$WALLET_DIR"
mkdir -p "$WALLET_DIR/sessions" && chmod 0700 "$WALLET_DIR/sessions"
mkdir -p "$WALLET_DIR/.signer-cache" && chmod 0700 "$WALLET_DIR/.signer-cache"

# 3. Copy default config (do not overwrite user config)
if [ ! -f "$WALLET_DIR/config.json" ]; then
  cp "$SCRIPT_DIR/../assets/default-config.json" "$WALLET_DIR/config.json"
  chmod 0600 "$WALLET_DIR/config.json"
fi

# 4. Generate HMAC session secret (if not exists)
if [ ! -f "$WALLET_DIR/.session-secret" ]; then
  openssl rand -hex 32 > "$WALLET_DIR/.session-secret"
  chmod 0600 "$WALLET_DIR/.session-secret"
fi

echo '{"status":"setup_complete","walletDir":"'"$WALLET_DIR"'"}'
