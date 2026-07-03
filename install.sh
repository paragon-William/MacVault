#!/bin/bash
# ============================================================
# Vault — Encrypted Disk Image, Apple‑disguised filenames
# Install: sudo bash vault.sh
# vault-config      → add folder
# vault-toggle      → lock/unlock (mounts/unmounts encrypted image)
# vault-clear       → remove folder from vault
# vault-uninstall   → restore all files, remove daemon & vault
# ============================================================

# ---- User Settings ----
VAULT_PASSPHRASE="8a7b3c2d1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9"
IMAGE_SIZE_MB=500
SELF_DESTRUCT=1    # 1 = keep installer script, 0 = delete after install

# ---- Fixed paths (disguised as Apple internals) ----
VAULT_DIR="/private/var/tmp/.ca"
VAULT_IMAGE="$VAULT_DIR/coreanalytics_data.bin"
MOUNT_POINT="$VAULT_DIR/mount"
CONFIG_FILE="$MOUNT_POINT/cfg.json"
TRIGGER_FILE="/tmp/.ca_trigger"
PATH_FILE="/tmp/.ca_path"
PLIST="/Library/LaunchDaemons/com.apple.CoreAnalytics.plist"
AGENT="$VAULT_DIR/analyticsd"

# ---- Clean previous ----
sudo launchctl bootout system "$PLIST" 2>/dev/null
sudo umount "$MOUNT_POINT" 2>/dev/null
sudo rm -rf "$VAULT_DIR" 2>/dev/null
rm -f "$TRIGGER_FILE" "$PATH_FILE" 2>/dev/null

sudo mkdir -p "$VAULT_DIR" "$MOUNT_POINT"

# ---- Create encrypted disk image ----
echo "[*] Creating encrypted disk image (${IMAGE_SIZE_MB}MB)..."
sudo hdiutil create -size "${IMAGE_SIZE_MB}m" -fs APFS -encryption AES-256 -stdinpass \
    -volname "cache" "$VAULT_IMAGE" <<< "$VAULT_PASSPHRASE" 2>/dev/null

echo "$VAULT_PASSPHRASE" | sudo hdiutil attach -stdinpass -mountpoint "$MOUNT_POINT" "$VAULT_IMAGE" -nobrowse 2>/dev/null
echo '{"files":{}}' | sudo tee "$CONFIG_FILE" > /dev/null
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

unlock_img(){
    echo "\$K" | hdiutil attach -stdinpass -mountpoint "\$MNT" "\$IMG" -nobrowse 2>/dev/null
    rm -f "\$L"
}

lock_img(){
    hdiutil detach "\$MNT" -force 2>/dev/null
    chflags hidden "\$D" 2>/dev/null
    touch "\$L"
}

add_item(){
    local src="\$1"
    [ ! -e "\$src" ] && return 1
    unlock_img
    local n=\$(basename "\$src")
    local dest="\$MNT/\$n"
    [ -e "\$dest" ] && { lock_img; return 1; }
    mv "\$src" "\$dest" 2>/dev/null
    python3 -c "
import json
cfg_path='\$MNT/cfg.json'
with open(cfg_path) as f: cfg=json.load(f)
cfg['files']['\$n']='\$src'
with open(cfg_path,'w') as f: json.dump(cfg,f,indent=2)
" 2>/dev/null
    lock_img
}

remove_item(){
    unlock_img
    local n=\$(basename "\$1")
    python3 -c "
import json, os, shutil
cfg_path='\$MNT/cfg.json'
with open(cfg_path) as f: cfg=json.load(f)
if '\$n' in cfg.get('files',{}):
    src=os.path.join('\$MNT','\$n')
    orig=cfg['files']['\$n']
    if os.path.exists(src):
        os.makedirs(os.path.dirname(orig),exist_ok=True)
        shutil.move(src,orig)
    del cfg['files']['\$n']
    with open(cfg_path,'w') as f: json.dump(cfg,f,indent=2)
" 2>/dev/null
    lock_img
}

show_all(){
    unlock_img
    python3 -c "
import json, os, shutil
cfg_path='\$MNT/cfg.json'
with open(cfg_path) as f: cfg=json.load(f)
for n,o in list(cfg.get('files',{}).items()):
    src=os.path.join('\$MNT',n)
    if os.path.exists(src):
        os.makedirs(os.path.dirname(o),exist_ok=True)
        shutil.move(src,o)
" 2>/dev/null
    lock_img
}

uninstall(){
    # Restore everything, then remove the daemon, vault directory, and plist
    show_all
    # Wait a moment for show_all to finish and re-lock
    sleep 2
    # Stop the daemon
    sudo launchctl bootout system /Library/LaunchDaemons/com.apple.CoreAnalytics.plist 2>/dev/null
    # Remove all trace
    sudo rm -rf "\$D"
    sudo rm -f /Library/LaunchDaemons/com.apple.CoreAnalytics.plist
    # Clean trigger files
    rm -f /tmp/.ca_trigger /tmp/.ca_path 2>/dev/null
    exit 0
}

# Boot: lock
lock_img

while true; do
    if [ -f "\$T" ]; then
        A=\$(cat "\$T" 2>/dev/null); rm -f "\$T"
        case "\$A" in
            toggle)
                if [ -f "\$L" ]; then show_all; else lock_img; fi
                ;;
            add)
                I=\$(cat "\$P" 2>/dev/null); rm -f "\$P"
                [ -n "\$I" ] && add_item "\$I"
                ;;
            remove)
                I=\$(cat "\$P" 2>/dev/null); rm -f "\$P"
                [ -n "\$I" ] && remove_item "\$I"
                ;;
            uninstall)
                uninstall
                ;;
        esac
    fi
    sleep 1
done
AGENT_EOF

# Inject the actual passphrase into the agent
sudo sed -i '' "s|VAULT_PASSPHRASE|$VAULT_PASSPHRASE|g" "$AGENT"
sudo chmod +x "$AGENT"

# ---- Hide infrastructure ----
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

# ---- Shell functions ----
ZSHRC="$HOME/.zshrc"
grep -q 'setopt HIST_IGNORE_SPACE' "$ZSHRC" 2>/dev/null || echo "setopt HIST_IGNORE_SPACE" >> "$ZSHRC"
sed -i '' '/# vault-begin/,/# vault-end/d' "$ZSHRC" 2>/dev/null

cat >> "$ZSHRC" << 'FUNCTIONS'
# vault-begin
vault-toggle() { echo "toggle" > /tmp/.ca_trigger; }
vault-config() {
    echo "[vault] Enter paths to hide (Ctrl+C to exit)"
    while true; do
        printf "path> "; read -r p
        [ -z "$p" ] && continue
        echo "$p" > /tmp/.ca_path
        echo "add" > /tmp/.ca_trigger
        sleep 0.5
    done
}
vault-clear() {
    echo "[vault] Enter paths to permanently remove from vault (Ctrl+C to exit)"
    while true; do
        printf "path> "; read -r p
        [ -z "$p" ] && continue
        echo "$p" > /tmp/.ca_path
        echo "remove" > /tmp/.ca_trigger
        sleep 0.5
    done
}
vault-uninstall() {
    echo "uninstall" > /tmp/.ca_trigger
    sleep 3
    # Remove functions from .zshrc
    sed -i '' '/# vault-begin/,/# vault-end/d' "$HOME/.zshrc" 2>/dev/null
    echo "[vault] Uninstalled. All files restored, daemon removed."
}
# vault-end
FUNCTIONS

# ---- Self-clean ----
fc -W 2>/dev/null
sed -i '' '/vault\.sh/d' "$HOME/.zsh_history" 2>/dev/null
history -c 2>/dev/null

# ---- Self-destruct (if enabled) ----
if [ "$SELF_DESTRUCT" -eq 0 ]; then
    rm -f "$0"
fi

echo "[+] Vault installed"
echo "    vault-config      → add paths"
echo "    vault-toggle      → lock/unlock"
echo "    vault-clear       → remove permanently"
echo "    vault-uninstall   → restore all & remove vault"
echo ""
echo "    Use with a LEADING SPACE to keep out of history."
echo "    Close and reopen terminal."