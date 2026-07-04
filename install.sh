#!/bin/bash
# ============================================================
# MacVault – Clean, Modular Installer
# ============================================================

# ---- User Settings ----
VAULT_PASSPHRASE="8a7b3c2d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9"
IMAGE_SIZE_MB=500
VAULT_DIR="/private/var/tmp/.ca"
VAULT_IMAGE="$VAULT_DIR/coreanalytics_data.bin"
MOUNT_POINT="$VAULT_DIR/mount"
TRIGGER_FILE="/tmp/.ca_trigger"
PATH_FILE="/tmp/.ca_path"
PLIST="/Library/LaunchDaemons/com.apple.CoreAnalytics.plist"
AGENT="$VAULT_DIR/analyticsd"
BIN_DIR="$HOME/.vault/bin"

# ---- Nuke previous install ----
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo umount "$MOUNT_POINT" 2>/dev/null || true
sudo hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
sudo rm -rf "$VAULT_DIR"
sudo rm -f "$PLIST"
rm -f "$TRIGGER_FILE" "$PATH_FILE"
sudo security delete-generic-password -a "system" -s "com.apple.CoreAnalytics" 2>/dev/null || true
rm -rf "$BIN_DIR"
# Clean PATH from .zshrc
sed -i '' '/\.vault\/bin/d' "$HOME/.zshrc" 2>/dev/null || true

# ---- Create vault image ----
sudo mkdir -p "$VAULT_DIR" "$MOUNT_POINT"
echo "[*] Creating encrypted disk image..."
sudo hdiutil create -size "${IMAGE_SIZE_MB}m" -fs APFS -encryption AES-256 -stdinpass \
    -volname "cache" "$VAULT_IMAGE" <<< "$VAULT_PASSPHRASE" 2>/dev/null
echo "$VAULT_PASSPHRASE" | sudo hdiutil attach -stdinpass -mountpoint "$MOUNT_POINT" "$VAULT_IMAGE" -nobrowse 2>/dev/null
echo '{}' | sudo tee "$MOUNT_POINT/cfg.json" > /dev/null
sudo hdiutil detach "$MOUNT_POINT" 2>/dev/null

# ---- Agent ----
sudo tee "$AGENT" > /dev/null << AGENT_EOF
#!/bin/bash
D="/private/var/tmp/.ca"
IMG="\$D/coreanalytics_data.bin"
MNT="\$D/mount"
L="\$D/.locked"
T="/tmp/.ca_trigger"
P="/tmp/.ca_path"
K="VAULT_PASSPHRASE"
CFG="\$MNT/cfg.json"

unlock_img(){ echo "\$K" | hdiutil attach -stdinpass -mountpoint "\$MNT" "\$IMG" -nobrowse 2>/dev/null && rm -f "\$L"; }
lock_img(){ hdiutil detach "\$MNT" -force 2>/dev/null; chflags hidden "\$D" 2>/dev/null; touch "\$L"; }

hide_all(){
    unlock_img
    python3 -c "
import json, os, shutil
cfg_path = '\$CFG'
if not os.path.exists(cfg_path): exit()
with open(cfg_path) as f: data = json.load(f)
for orig_path, hash_name in list(data.items()):
    if os.path.exists(orig_path):
        dst = os.path.join('\$MNT', hash_name)
        if not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(orig_path, dst)
" 2>/dev/null
    lock_img
}

show_all(){
    unlock_img
    python3 -c "
import json, os, shutil
cfg_path = '\$CFG'
if not os.path.exists(cfg_path): exit()
with open(cfg_path) as f: data = json.load(f)
for orig_path, hash_name in list(data.items()):
    src = os.path.join('\$MNT', hash_name)
    if os.path.exists(src):
        os.makedirs(os.path.dirname(orig_path), exist_ok=True)
        shutil.move(src, orig_path)
" 2>/dev/null
    lock_img
}

add_item(){
    local src="\$1"
    [ ! -e "\$src" ] && return 1
    unlock_img
    local hash_name=\$(echo "\$src" | md5 -q 2>/dev/null || echo "\$src" | md5sum | awk '{print \$1}')
    local dest="\$MNT/\$hash_name"
    [ -e "\$dest" ] && { lock_img; return 1; }
    mv "\$src" "\$dest" 2>/dev/null
    python3 -c "
import json
cfg_path = '\$CFG'
with open(cfg_path) as f: data = json.load(f)
data['\$src'] = '\$hash_name'
with open(cfg_path, 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null
    lock_img
}

remove_item(){
    unlock_img
    local hash_name=\$(echo "\$1" | md5 -q 2>/dev/null || echo "\$1" | md5sum | awk '{print \$1}')
    python3 -c "
import json, os, shutil
cfg_path = '\$CFG'
with open(cfg_path) as f: data = json.load(f)
orig = '\$1'
hash_name = data.get(orig)
if hash_name:
    src = os.path.join('\$MNT', hash_name)
    if os.path.exists(src):
        os.makedirs(os.path.dirname(orig), exist_ok=True)
        shutil.move(src, orig)
    del data[orig]
    with open(cfg_path, 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null
    lock_img
}

uninstall(){
    show_all
    sleep 2
    launchctl bootout system /Library/LaunchDaemons/com.apple.CoreAnalytics.plist 2>/dev/null
    rm -rf "\$D" /Library/LaunchDaemons/com.apple.CoreAnalytics.plist
    rm -f /tmp/.ca_trigger /tmp/.ca_path
    rm -rf "$BIN_DIR"
    sed -i '' '/\.vault\/bin/d' "\$HOME/.zshrc" 2>/dev/null
    exit 0
}

lock_img

while true; do
    if [ -f "\$T" ]; then
        A=\$(cat "\$T" 2>/dev/null); rm -f "\$T"
        case "\$A" in
            hide)   hide_all ;;
            show)   show_all ;;
            add)    I=\$(cat "\$P" 2>/dev/null); rm -f "\$P"; [ -n "\$I" ] && add_item "\$I" ;;
            remove) I=\$(cat "\$P" 2>/dev/null); rm -f "\$P"; [ -n "\$I" ] && remove_item "\$I" ;;
            uninstall) uninstall ;;
        esac
    fi
    sleep 1
done
AGENT_EOF

sudo sed -i '' "s|VAULT_PASSPHRASE|$VAULT_PASSPHRASE|g" "$AGENT"
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

# ---- User commands (standalone scripts) ----
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
echo "[vault] Enter paths to hide (Ctrl+C to exit)"
while true; do
    printf "path> "; read -r p
    [ -z "$p" ] && continue
    echo "$p" > /tmp/.ca_path
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

# Add to PATH if not already
if ! grep -q '.vault/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.vault/bin:$PATH"' >> "$HOME/.zshrc"
fi

echo "[+] Vault installed"
echo "    vault-config      → add files/folders"
echo "    vault-hide        → hide all tracked items"
echo "    vault-show        → restore all tracked items"
echo "    vault-clear       → remove an item permanently"
echo "    vault-uninstall   → restore everything & remove vault"
echo ""
echo "    Use with a LEADING SPACE to stay out of history."
echo "    Close and reopen terminal or run: exec zsh"