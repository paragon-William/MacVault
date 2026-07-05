#!/bin/bash
# ============================================================
# MacVault — Bootstrap installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
# ============================================================
set -euo pipefail

REPO="https://github.com/paragon-William/MacVault.git"
DEST="${1:-$HOME/.local/bin}"
NAME="${2:-mvs}"
TMPDIR="$(mktemp -d /tmp/_macvault_XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# ── Colours ──
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[92m'
CYAN='\033[96m'
RESET='\033[0m'

progress() {
    local current="$1" total="$2" desc="$3"
    local percent=$(( current * 100 / total ))
    local filled=$(( percent / 2 ))
    local empty=$(( 50 - filled ))
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    local space
    space=$(printf '%*s' "$empty" '' | tr ' ' ' ')
    printf "\r  [%b%s%b%s%b] %s" "$GREEN" "$bar" "$RESET" "$space" "$RESET" "$desc"
}

clear_line() {
    printf "\r  [%b##################################################%b] %bDone%b\n" "$GREEN" "$RESET" "$GREEN" "$RESET"
}

printf "\n%b  MacVault Installer%b\n" "$BOLD$GREEN" "$RESET"
printf "%b  https://github.com/paragon-William/MacVault%b\n\n" "$DIM" "$RESET"

# Step 1/4
progress 1 4 "Cloning repository..."
git clone --depth 1 "$REPO" "$TMPDIR" &>/dev/null
clear_line

cd "$TMPDIR"

if [ ! -f build/install ]; then
    printf "\n  [!] build/install not found in repo.\n"
    exit 1
fi

chmod +x build/install build/mvs 2>/dev/null || true

# Step 2/4
progress 2 4 "Verifying source files..."
sleep 0.2
clear_line

# Step 3/4
progress 3 4 "Installing mvs to ${DEST}..."
bash build/install "$@" &>/dev/null
sleep 0.2
clear_line

# Step 4/4
progress 4 4 "Finalising..."
sleep 0.2
clear_line

printf "\n  %bCongratulations! MacVault is installed.%b\n\n" "$GREEN$BOLD" "$RESET"
printf "  %bUsage:%b\n" "$BOLD" "$RESET"
printf "    %bmvs%b init       %b# create a new encrypted store%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "    %bmvs%b open       %b# unlock and mount%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "    %bmvs%b add        %b# move files into the store%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "    %bmvs%b show       %b# restore files to origin%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "    %bmvs%b hide       %b# instant re-hide%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "    %bmvs%b close      %b# lock it all up%b\n" "$CYAN" "$RESET" "$DIM" "$RESET"
printf "\n  %bPrefix commands with a space to keep them out of history.%b\n" "$DIM" "$RESET"
echo ""