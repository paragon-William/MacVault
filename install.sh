#!/bin/bash
# ============================================================
# MacVault – 5GB, Space‑Safe, Backslash‑Adaptable
# ============================================================

VAULT_PASSPHRASE="8a7b3c2d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9"
IMAGE_SIZE_MB=5120
VAULT_DIR="/private/var/tmp/.ca"
VAULT_IMAGE="$VAULT_DIR/coreanalytics_data.bin"
MOUNT_POINT="$VAULT_DIR/mount"
TRIGGER_FILE="/tmp/.ca_trigger"
PATH_FILE="/tmp/.ca_path"
PLIST="/Library/LaunchDaemons/com.apple.CoreAnalytics.plist"
AGENT="$VAULT_DIR/analyticsd"
BIN_DIR="$HOME/.vault/bin"

# ---- Nuke ----
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo umount "$MOUNT_POINT" 2>/dev/null || true
sudo hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
sudo rm -rf "$VAULT_DIR"
sudo rm -f "$PLIST"
rm -f "$TRIGGER_FILE" "$PATH_FILE"
sudo security delete-generic-password -a "system" -s "com.apple.CoreAnalytics" 2>/dev/null || true
rm -rf "$BIN_DIR"
sed -i '' '/\.vault\/bin/d' "$HOME/.zshrc" 2>/dev/null || true

# ---- Create vault image (5GB) ----
sudo mkdir -p "$VAULT_DIR" "$MOUNT_POINT"
echo "[*] Creating encrypted disk image (5GB)..."
sudo hdiutil create -size "${IMAGE_SIZE_MB}m" -fs APFS -encryption AES-256 -stdinpass \
    -volname "cache" "$VAULT_IMAGE" <<< "$VAULT_PASSPHRASE" 2>/dev/null
echo "$VAULT_PASSPHRASE" | sudo hdiutil attach -stdinpass -mountpoint "$MOUNT_POINT" "$VAULT_IMAGE" -nobrowse 2>/dev/null
echo '{}' | sudo tee "$MOUNT_POINT/cfg.json" > /dev/null
sudo hdiutil detach "$MOUNT_POINT" 2>/dev/null

# ---- Agent ----
sudo tee "$AGENT" > /dev/null << 'AGENT_EOF'
#!/bin/bash
D="/private/var/tmp/.ca"
IMG="$D/coreanalytics_data.bin"
MNT="$D/mount"
L="$D/.locked"
T="/tmp/.ca_trigger"
P="/tmp/.ca_path"
K="8a7b3c2d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9"

unlock_img(){ echo "$K" | hdiutil attach -stdinpass -mountpoint "$MNT" "$IMG" -nobrowse 2>/dev/null && rm -f "$L"; }
lock_img(){ hdiutil detach "$MNT" -force 2>/dev/null; chflags hidden "$D" 2>/dev/null; touch "$L"; }

hide_all(){
    unlock_img
    python3 << 'PYEOF'
import json, os, shutil
cfg_path = '/private/var/tmp/.ca/mount/cfg.json'
if not os.path.exists(cfg_path): exit()
with open(cfg_path) as f: data = json.load(f)
for orig_path, hash_name in list(data.items()):
    if os.path.exists(orig_path):
        dst = os.path.join('/private/var/tmp/.ca/mount', hash_name)
        if not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(orig_path, dst)
PYEOF
    lock_img
}

show_all(){
    unlock_img
    python3 << 'PYEOF'
import json, os, shutil
cfg_path = '/private/var/tmp/.ca/mount/cfg.json'
if not os.path.exists(cfg_path): exit()
with open(cfg_path) as f: data = json.load(f)
for orig_path, hash_name in list(data.items()):
    src = os.path.join('/private/var/tmp/.ca/mount', hash_name)
    if os.path.exists(src):
        os.makedirs(os.path.dirname(orig_path), exist_ok=True)
        shutil.move(src, orig_path)
PYEOF
    lock_img
}

add_item(){
    unlock_img
    python3 << 'PYEOF'
import json, os, shutil, hashlib, sys
with open('/tmp/.ca_path') as pf:
    src = pf.read().strip()
cfg_path = '/private/var/tmp/.ca/mount/cfg.json'
mnt = '/private/var/tmp/.ca/mount'
if not os.path.exists(src):
    sys.exit(1)
hash_name = hashlib.md5(src.encode()).hexdigest()
dst = os.path.join(mnt, hash_name)
if os.path.exists(dst):
    sys.exit(1)
shutil.move(src, dst)
with open(cfg_path) as f: data = json.load(f)
data[src] = hash_name
with open(cfg_path, 'w') as f: json.dump(data, f, indent=2)
PYEOF
    lock_img
}

remove_item(){
    unlock_img
    python3 << 'PYEOF'
import json, os, shutil, hashlib, sys
with open('/tmp/.ca_path') as pf:
    src = pf.read().strip()
cfg_path = '/private/var/tmp/.ca/mount/cfg.json'
mnt = '/private/var/tmp/.ca/mount'
with open(cfg_path) as f: data = json.load(f)
hash_name = data.get(src)
if not hash_name:
    sys.exit(1)
vaulted = os.path.join(mnt, hash_name)
if os.path.exists(vaulted):
    os.makedirs(os.path.dirname(src), exist_ok=True)
    shutil.move(vaulted, src)
del data[src]
with open(cfg_path, 'w') as f: json.dump(data, f, indent=2)
PYEOF
    lock_img
}

uninstall(){
    show_all
    sleep 2
    launchctl bootout system /Library/LaunchDaemons/com.apple.CoreAnalytics.plist 2>/dev/null
    rm -rf "$D" /Library/LaunchDaemons/com.apple.CoreAnalytics.plist
    rm -f /tmp/.ca_trigger /tmp/.ca_path
    rm -rf "$HOME/.vault"
    sed -i '' '/\.vault\/bin/d' "$HOME/.zshrc" 2>/dev/null
    exit 0
}

lock_img

while true; do
    if [ -f "$T" ]; then
        A=$(cat "$T" 2>/dev/null); rm -f "$T"
        case "$A" in
            hide)   hide_all ;;
            show)   show_all ;;
            add)    [ -f "$P" ] && add_item ;;
            remove) [ -f "$P" ] && remove_item ;;
            uninstall) uninstall ;;
        esac
    fi
    sleep 1
done
AGENT_EOF

sudo chmod +x "$AGENT"
sudo chflags hidden "$VAULT_DIR" 2>/dev/null

# ---- LaunchDaemon ----
sudo tee "$PLIST" > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.apple.CoreAnalytics</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$AGENT</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>UserName</key><string>root</string>
    <key>GroupName</key><string>wheel</string>
    <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST
sudo chmod 644 "$PLIST"
sudo launchctl bootstrap system "$PLIST" 2>/dev/null

# ---- User commands with backslash-stripping path resolver ----
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/vault-hide" << 'EOF'
#!/bin/bash
echo "hide" > /tmp/.ca_trigger
EOF
chmod +x "$BIN_DIR/vault-hide"

cat > "$BIN_DIR/vault-show" << 'EOF'
#!/bin/bash
echo "show" > /tmp/.ca_trigger
EOF
chmod +x "$BIN_DIR/vault-show"

cat > "$BIN_DIR/vault-config" << 'EOF'
#!/bin/bash
resolve_path() {
    local input="$1"
    # Strip backslashes (from drag-and-drop escaping)
    input="${input//\\/}"
    # Expand tilde
    input="${input/#\~/$HOME}"
    # Remove trailing slash
    input="${input%/}"
    # If path exists as-is, return it
    if [ -e "$input" ]; then
        echo "$input"
        return
    fi
    # Try adding .app
    if [ -e "${input}.app" ]; then
        echo "${input}.app"
        return
    fi
    # Give up, return original
    echo "$input"
}

echo "[vault] Enter paths to hide (Ctrl+C to exit)"
while true; do
    printf "path> "; read -r p
    [ -z "$p" ] && continue
    resolved=$(resolve_path "$p")
    if [ ! -e "$resolved" ]; then
        echo "  [!] Not found: $resolved"
        continue
    fi
    echo "  -> $resolved"
    echo "$resolved" > /tmp/.ca_path
    echo "add" > /tmp/.ca_trigger
    sleep 0.5
done
EOF
chmod +x "$BIN_DIR/vault-config"

cat > "$BIN_DIR/vault-clear" << 'EOF'
#!/bin/bash
echo "[vault] Enter paths to permanently remove from vault (Ctrl+C to exit)"
while true; do
    printf "path> "; read -r p
    [ -z "$p" ] && continue
    p="${p//\\/}"
    echo "$p" > /tmp/.ca_path
    echo "remove" > /tmp/.ca_trigger
    sleep 0.5
done
EOF
chmod +x "$BIN_DIR/vault-clear"

cat > "$BIN_DIR/vault-uninstall" << 'EOF'
#!/bin/bash
echo "uninstall" > /tmp/.ca_trigger
sleep 3
rm -rf "$HOME/.vault"
sed -i '' '/\.vault\/bin/d' "$HOME/.zshrc" 2>/dev/null
echo "[vault] Uninstalled."
EOF
chmod +x "$BIN_DIR/vault-uninstall"

if ! grep -q '.vault/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.vault/bin:$PATH"' >> "$HOME/.zshrc"
fi

echo "[+] Vault installed (5GB, handles backslashes & spaces)"
echo "    vault-config      → add files/folders"
echo "    vault-hide        → hide everything"
echo "    vault-show        → restore everything"
echo "    vault-clear       → remove an item permanently"
echo "    vault-uninstall   → restore all & remove vault"
echo ""
echo "    Use with a LEADING SPACE. Reopen terminal or run: exec zsh"