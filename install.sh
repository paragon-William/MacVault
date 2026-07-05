#!/bin/bash
# ============================================================
# MacVault — Bootstrap installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
# ============================================================
set -euo pipefail

# ── Colours ──
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[91m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_BLUE='\033[94m'
C_CYAN='\033[96m'

REPO="https://github.com/paragon-William/MacVault.git"
DEST="${1:-$HOME/.local/bin}"
NAME="${2:-mvs}"
TMPDIR="$(mktemp -d /tmp/_macvault_XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# ── Progress bar ──
progress() {
    local current="$1"
    local total="$2"
    local desc="$3"
    local percent=$(( current * 100 / total ))
    local filled=$(( percent / 2 ))
    local empty=$(( 50 - filled ))
    printf "\r  ${C_CYAN}[%s]${C_RESET} ${C_BOLD}%s${C_RESET}" \
        "$(printf '#%.0s' $(seq 1 $filled))$(printf ' %.0s' $(seq 1 $empty))" \
        "$desc"
}

echo ""
echo -e "${C_BOLD}${C_GREEN}  MacVault Installer${C_RESET}"
echo -e "${C_DIM}  https://github.com/paragon-William/MacVault${C_RESET}"
echo ""

# Step 1/4: Clone
progress 1 4 "Cloning repository..."
git clone --depth 1 "$REPO" "$TMPDIR" &>/dev/null
echo -e "\r  ${C_GREEN}[##################################################]${C_RESET} ${C_GREEN}Done${C_RESET}"

cd "$TMPDIR"

if [ ! -f build/install ]; then
    echo ""
    echo -e "  ${C_RED}[!] build/install not found in repo.${C_RESET}"
    exit 1
fi

chmod +x build/install build/mvs 2>/dev/null || true

# Step 2/4: Verify
progress 2 4 "Verifying source files..."
sleep 0.3
echo -e "\r  ${C_GREEN}[##################################################]${C_RESET} ${C_GREEN}Done${C_RESET}"

# Step 3/4: Install
progress 3 4 "Installing ${C_BOLD}${NAME}${C_RESET} to ${C_DIM}${DEST}${C_RESET}..."
bash build/install "$@" &>/dev/null
sleep 0.3
echo -e "\r  ${C_GREEN}[##################################################]${C_RESET} ${C_GREEN}Done${C_RESET}"

# Step 4/4: Finalise
progress 4 4 "Finalising..."
sleep 0.3
echo -e "\r  ${C_GREEN}[##################################################]${C_RESET} ${C_GREEN}Done${C_RESET}"

echo ""
echo -e "  ${C_GREEN}${C_BOLD}Congratulations! MacVault is installed.${C_RESET}"
echo ""
echo -e "  ${C_BOLD}Usage:${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} init       ${C_DIM}# create a new encrypted store${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} open       ${C_DIM}# unlock and mount${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} add        ${C_DIM}# move files into the store${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} show       ${C_DIM}# restore files to origin${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} hide       ${C_DIM}# instant re-hide${C_RESET}"
echo -e "    ${C_CYAN}${NAME}${C_RESET} close      ${C_DIM}# lock it all up${C_RESET}"
echo ""
echo -e "  ${C_DIM}Prefix commands with a space to keep them out of history.${C_RESET}"
echo ""