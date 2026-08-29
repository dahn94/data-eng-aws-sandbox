#!/usr/bin/env bash
# Liga e desliga o GitHub Actions deste repositório.
#
#   ./scripts/ci-toggle.sh on|off|status
set -euo pipefail

ACTION="${1:-status}"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
API="repos/${REPO}/actions/permissions"

case "$ACTION" in
  on)     gh api -X PUT "$API" -F enabled=true -f allowed_actions=all >/dev/null ;;
  off)    gh api -X PUT "$API" -F enabled=false >/dev/null ;;
  status) ;;
  *)      echo "uso: $0 [on|off|status]" >&2; exit 1 ;;
esac

echo "$REPO — Actions: $(gh api "$API" --jq 'if .enabled then "ligado" else "desligado" end')"
