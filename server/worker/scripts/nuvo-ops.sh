#!/usr/bin/env bash
# Wrapper around nuvo-motion.mjs that pulls NUVO_INTERNAL_KEY out of the
# macOS Keychain instead of taking it as a literal argument or env var typed
# on the command line. The key itself never appears in this file or in any
# command built from it.
#
# One-time setup (run yourself, once):
#   security add-generic-password -a "$USER" -s nuvo-internal-api-key -w '<key>' -U
#
# Usage (same arguments as nuvo-motion.mjs):
#   ./scripts/nuvo-ops.sh activity-visibility jumping_jacks --set hidden
set -euo pipefail

KEY="$(security find-generic-password -a "$USER" -s nuvo-internal-api-key -w 2>/dev/null || true)"
if [ -z "$KEY" ]; then
  echo "No key found in Keychain under service 'nuvo-internal-api-key'." >&2
  echo "Set it once with:" >&2
  echo "  security add-generic-password -a \"\$USER\" -s nuvo-internal-api-key -w '<your key>' -U" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUVO_INTERNAL_KEY="$KEY" node "$SCRIPT_DIR/nuvo-motion.mjs" "$@"
