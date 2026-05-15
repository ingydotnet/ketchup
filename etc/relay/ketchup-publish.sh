#!/usr/bin/env bash
set -euo pipefail
: "${KETCHUP_REPO:?Set KETCHUP_REPO=owner/repo}"
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec gh secret set CLAUDE_CREDENTIALS -R "$KETCHUP_REPO" \
    < "$HOME/.ketchup/creds.json"
