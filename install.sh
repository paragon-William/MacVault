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
YELLOW="$(tput setaf 3)"
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
echo "  ${GREEN}${BOLD}MacVault is installed.${RESET}"
echo ""
echo "  ${BOLD}Choose how you want to run it:${RESET}"
echo ""
echo "  ${BOLD}1${RESET} — Run by full path (no changes to your shell)"
echo "     ${CYAN}${DEST}/${NAME}${RESET} <command>"
echo ""
echo "  ${BOLD}2${RESET} — Add to PATH for this session only"
echo "     ${CYAN}export PATH=\"${DEST}:\$PATH\"${RESET}"
echo "     ${CYAN}${NAME}${RESET} <command>"
echo ""
echo "  ${BOLD}3${RESET} — Permanent PATH (adds to ~/.zshrc)"
echo "     ${CYAN}echo 'export PATH=\"${DEST}:\$PATH\"' >> ~/.zshrc${RESET}"
echo "     ${CYAN}source ~/.zshrc${RESET}"
echo "     ${CYAN}${NAME}${RESET} <command>"
echo ""
printf "  ${YELLOW}Enter 1, 2, or 3: ${RESET}"
read -r CHOICE

case "$CHOICE" in
    1)
        echo ""
        echo "  ${GREEN}You chose Mode 1. Run it with the full path:${RESET}"
        echo "    ${CYAN}${DEST}/${NAME}${RESET} init"
        ;;
    2)
        export PATH="${DEST}:$PATH"
        echo ""
        echo "  ${GREEN}PATH updated for this session. You can now run:${RESET}"
        echo "    ${CYAN}${NAME}${RESET} init"
        ;;
    3)
        echo 'export PATH="'"${DEST}"':$PATH"' >> "$HOME/.zshrc"
        echo ""
        echo "  ${GREEN}PATH added to ~/.zshrc. Restart your terminal or run:${RESET}"
        echo "    ${CYAN}source ~/.zshrc${RESET}"
        echo "  Then:"
        echo "    ${CYAN}${NAME}${RESET} init"
        ;;
    *)
        echo ""
        echo "  ${YELLOW}Invalid choice. Defaulting to Mode 1.${RESET}"
        echo "    ${CYAN}${DEST}/${NAME}${RESET} init"
        ;;
esac

echo ""
echo "  ${BOLD}All commands:${RESET}"
echo "    ${CYAN}${NAME}${RESET} init        # create a new store"
echo "    ${CYAN}${NAME}${RESET} open        # unlock and mount"
echo "    ${CYAN}${NAME}${RESET} close       # lock and unmount"
echo "    ${CYAN}${NAME}${RESET} add         # move files into the store"
echo "    ${CYAN}${NAME}${RESET} remove      # restore files from store"
echo "    ${CYAN}${NAME}${RESET} list        # show tracked files"
echo "    ${CYAN}${NAME}${RESET} show        # restore all to origin"
echo "    ${CYAN}${NAME}${RESET} hide        # re-hide all tracked files"
echo "    ${CYAN}${NAME}${RESET} restore     # restore all and clear tracking"
echo "    ${CYAN}${NAME}${RESET} status      # show store location & state"
echo "    ${CYAN}${NAME}${RESET} uninstall   # restore all & remove everything"
echo ""
echo "  ${DIM}Prefix commands with a space to keep them out of history.${RESET}"
echo ""