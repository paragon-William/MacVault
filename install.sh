#!/bin/bash
# ============================================================
# MacVault — Bootstrap installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
# ============================================================
set -euo pipefail

REPO="https://github.com/paragon-William/MacVault.git"
TMPDIR="$(mktemp -d /tmp/_macvault_XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "[*] Cloning MacVault..."
git clone --depth 1 "$REPO" "$TMPDIR"

cd "$TMPDIR"

if [ ! -f build/install ]; then
    echo "[!] build/install not found in repo."
    ls -la "$TMPDIR" 2>/dev/null
    ls -la "$TMPDIR/build" 2>/dev/null || echo "    (no build/ directory)"
    exit 1
fi

chmod +x build/install build/mvs 2>/dev/null || true
bash build/install "$@"
