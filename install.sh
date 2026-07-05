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

BOLD="$(tput bold)"
DIM="$(tput dim)"
GREEN="$(tput setaf 2)"
CYAN="$(tput setaf 6)"
RESET="$(tput sgr0)"

echo ""
echo "  ${BOLD}${GREEN}MacVault Installer${RESET}"
echo "  ${DIM}https://github.com/paragon-William/MacVault${RESET}"
echo ""

echo "  ${DIM}Cloning repository...${RESET}"
git clone --depth 1 "$REPO" "$TMPDIR" &>/dev/null
echo "  ${GREEN}Done.${RESET}"

cd "$TMPDIR"

if [ ! -f build/mvs ]; then
    echo "  [!] build/mvs not found in repo."
    exit 1
fi

chmod +x build/mvs 2>/dev/null || true

echo "  ${DIM}Verifying source files...${RESET}"
sleep 0.2
echo "  ${GREEN}Done.${RESET}"

echo "  ${DIM}Installing ${NAME} to ${DEST}...${RESET}"
mkdir -p "$DEST"
cp build/mvs "$DEST/$NAME"
chmod +x "$DEST/$NAME"
sleep 0.2
echo "  ${GREEN}Done.${RESET}"

echo "  ${DIM}Finalising...${RESET}"
sleep 0.2
echo "  ${GREEN}Done.${RESET}"

echo ""
echo "  ${GREEN}${BOLD}Congratulations! MacVault is installed.${RESET}"
echo ""
echo "  ${BOLD}Usage:${RESET}"
echo ""
echo "  ${BOLD}Mode 1 — Run by full path (no PATH changes needed):${RESET}"
echo "    ${CYAN}${DEST}/${NAME}${RESET} init"
echo "    ${CYAN}${DEST}/${NAME}${RESET} open"
echo ""
echo "  ${BOLD}Mode 2 — Add to PATH for this session only:${RESET}"
echo "    ${CYAN}export PATH=\"${DEST}:\$PATH\"${RESET}"
echo "    ${CYAN}${NAME}${RESET} init"
echo ""
echo "  ${BOLD}Mode 3 — Permanent PATH (adds to ~/.zshrc):${RESET}"
echo "    ${CYAN}echo 'export PATH=\"${DEST}:\$PATH\"' >> ~/.zshrc${RESET}"
echo "    ${CYAN}source ~/.zshrc${RESET}"
echo "    ${CYAN}${NAME}${RESET} init"
echo ""
echo "  ${BOLD}Quick reference:${RESET}"
echo "    ${CYAN}${NAME}${RESET} init       # create a new encrypted store"
echo "    ${CYAN}${NAME}${RESET} open       # unlock and mount"
echo "    ${CYAN}${NAME}${RESET} add        # move files into the store"
echo "    ${CYAN}${NAME}${RESET} show       # restore files to origin"
echo "    ${CYAN}${NAME}${RESET} hide       # instant re-hide"
echo "    ${CYAN}${NAME}${RESET} close      # lock it all up"
echo ""
echo "  ${DIM}Prefix commands with a space to keep them out of history.${RESET}"
echo ""