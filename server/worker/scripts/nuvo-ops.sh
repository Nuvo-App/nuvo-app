#!/usr/bin/env bash
# Wrapper around nuvo-motion.mjs that reads NUVO_INTERNAL_KEY from a credential
# store instead of taking it as a literal argument or an env var typed on the
# command line. The key itself never appears in this file or in any command
# built from it.
#
# Looked up in this order:
#   1. macOS Keychain       security add-generic-password -a "$USER" -s nuvo-internal-api-key -w '<key>' -U
#   2. libsecret (Linux)    secret-tool store --label=nuvo-internal-api-key service nuvo-internal-api-key
#   3. a private key file   ~/.config/nuvo/internal-api-key   (chmod 600, never in git)
#
# Headless servers usually only have option 3. Create it once, yourself, without
# putting the key on a command line:
#   mkdir -p ~/.config/nuvo && chmod 700 ~/.config/nuvo
#   ( umask 077; cat > ~/.config/nuvo/internal-api-key )   # paste the key, Enter, Ctrl-D
#
# Usage (same arguments as nuvo-motion.mjs):
#   ./scripts/nuvo-ops.sh activity-visibility jumping_jacks --set hidden
set -euo pipefail

KEY_FILE="${NUVO_KEY_FILE:-$HOME/.config/nuvo/internal-api-key}"
KEY=""

if command -v security >/dev/null 2>&1; then
  KEY="$(security find-generic-password -a "$USER" -s nuvo-internal-api-key -w 2>/dev/null || true)"
fi
if [ -z "$KEY" ] && command -v secret-tool >/dev/null 2>&1; then
  KEY="$(secret-tool lookup service nuvo-internal-api-key 2>/dev/null || true)"
fi
if [ -z "$KEY" ] && [ -f "$KEY_FILE" ]; then
  # Refuse a key file other users can read.
  mode="$(stat -c '%a' "$KEY_FILE" 2>/dev/null || stat -f '%Lp' "$KEY_FILE")"
  if [ "${mode: -2}" != "00" ]; then
    echo "Refusing to read $KEY_FILE: permissions are $mode. Run: chmod 600 $KEY_FILE" >&2
    exit 1
  fi
  KEY="$(tr -d '\r\n' < "$KEY_FILE")"
fi

if [ -z "$KEY" ]; then
  echo "No internal API key found (Keychain, libsecret, or $KEY_FILE)." >&2
  echo "On a headless Linux box, create the key file once (see the header of this script)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUVO_INTERNAL_KEY="$KEY" node "$SCRIPT_DIR/nuvo-motion.mjs" "$@"
