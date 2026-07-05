#!/bin/bash
# ============================================================
# MacVault — Bootstrap installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
#
# Clones the repo and runs build/install
# ============================================================
set -euo pipefail

REPO="https://github.com/paragon-William/MacVault.git"
TMPDIR="$(mktemp -d /tmp/_macvault_XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "[*] Cloning MacVault..."
git clone --depth 1 "$REPO" "$TMPDIR" 2>/dev/null

cd "$TMPDIR"
chmod +x build/install
