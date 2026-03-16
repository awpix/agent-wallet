#!/usr/bin/env bash
# ==============================================================================
# AWP Wallet — Publish to ClawHub
#
# Usage:
#   bash publish.sh                    # patch bump (1.0.0 -> 1.0.1)
#   bash publish.sh minor              # minor bump (1.0.1 -> 1.1.0)
#   bash publish.sh major              # major bump (1.1.0 -> 2.0.0)
#   bash publish.sh 2.0.0              # explicit version
#   bash publish.sh --dry-run          # preview only
# ==============================================================================
set -euo pipefail

SLUG="awp-wallet"
NAME="AWP Wallet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[publish]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[publish]${NC} $*" >&2; }
err()  { echo -e "${RED}[publish]${NC} $*" >&2; exit 1; }

# ---------- Pre-flight ----------
command -v clawhub &>/dev/null || err "clawhub CLI not found. Install: npm i -g clawhub"
command -v node &>/dev/null || err "node not found"
command -v jq &>/dev/null || JQ_AVAILABLE=false || JQ_AVAILABLE=true

# ---------- Parse args ----------
DRY_RUN=false
BUMP="patch"
EXPLICIT_VERSION=""
CHANGELOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --changelog) CHANGELOG="$2"; shift 2 ;;
    patch|minor|major) BUMP="$1"; shift ;;
    [0-9]*)      EXPLICIT_VERSION="$1"; shift ;;
    --help|-h)
      head -12 "$0" | tail -8
      exit 0 ;;
    *) err "Unknown arg: $1. Use --help." ;;
  esac
done

# ---------- Read current version from package.json ----------
cd "$SCRIPT_DIR"
CURRENT_VERSION=$(node -e "console.log(require('./package.json').version)")
log "Current version: $CURRENT_VERSION"

# ---------- Calculate next version ----------
if [[ -n "$EXPLICIT_VERSION" ]]; then
  NEXT_VERSION="$EXPLICIT_VERSION"
else
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  case "$BUMP" in
    major) NEXT_VERSION="$((MAJOR + 1)).0.0" ;;
    minor) NEXT_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
    patch) NEXT_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  esac
fi
log "Next version: $NEXT_VERSION"

# ---------- Generate changelog from git if not provided ----------
if [[ -z "$CHANGELOG" ]]; then
  # Find the last publish tag, or use first commit
  LAST_TAG=$(git tag -l "v*" --sort=-v:refname | head -1)
  if [[ -n "$LAST_TAG" ]]; then
    CHANGELOG=$(git log "${LAST_TAG}..HEAD" --oneline --no-merges | head -10 | sed 's/^[a-f0-9]* /- /')
  else
    CHANGELOG=$(git log --oneline --no-merges -10 | sed 's/^[a-f0-9]* /- /')
  fi
  if [[ -z "$CHANGELOG" ]]; then
    CHANGELOG="Release v${NEXT_VERSION}"
  fi
fi

# ---------- Update version in package.json and SKILL.md ----------
log "Updating version in package.json and SKILL.md..."
node -e "
  const fs = require('fs');
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  pkg.version = '${NEXT_VERSION}';
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
sed -i "s/^version: .*/version: ${NEXT_VERSION}/" SKILL.md

# ---------- Run tests ----------
log "Running tests..."
TEST_OUTPUT=$(node --test tests/integration/*.test.js tests/e2e/*.test.js 2>&1)
PASS=$(echo "$TEST_OUTPUT" | grep "^# pass" | awk '{print $3}')
FAIL=$(echo "$TEST_OUTPUT" | grep "^# fail" | awk '{print $3}')
if [[ "$FAIL" -gt 0 ]]; then
  err "Tests failed ($FAIL failures). Fix before publishing."
fi
log "Tests passed: $PASS"

# ---------- Preview ----------
echo "" >&2
echo -e "${CYAN}============================================================${NC}" >&2
echo -e "${CYAN}  Publish Preview${NC}" >&2
echo -e "${CYAN}============================================================${NC}" >&2
echo -e "  ${GREEN}Slug:${NC}      $SLUG" >&2
echo -e "  ${GREEN}Name:${NC}      $NAME" >&2
echo -e "  ${GREEN}Version:${NC}   $NEXT_VERSION" >&2
echo -e "  ${GREEN}Changelog:${NC}" >&2
echo "$CHANGELOG" | sed 's/^/    /' >&2
echo "" >&2

if [[ "$DRY_RUN" == true ]]; then
  warn "Dry run — skipping publish."
  # Revert version changes
  git checkout -- package.json SKILL.md 2>/dev/null || true
  exit 0
fi

# ---------- Git tag ----------
log "Committing version bump..."
git add package.json SKILL.md
git commit -m "chore: bump version to v${NEXT_VERSION}" 2>/dev/null || true
git tag "v${NEXT_VERSION}"
git push && git push --tags

# ---------- Publish to ClawHub ----------
log "Publishing to ClawHub..."
clawhub publish . \
  --slug "$SLUG" \
  --name "$NAME" \
  --version "$NEXT_VERSION" \
  --tags latest \
  --changelog "$CHANGELOG"

echo "" >&2
echo -e "${GREEN}Published ${SLUG}@${NEXT_VERSION} to ClawHub!${NC}" >&2
echo -e "  ${CYAN}https://clawhub.ai/skills/${SLUG}${NC}" >&2
echo "" >&2
echo -e "  Users can install with: ${CYAN}clawhub install ${SLUG}${NC}" >&2
