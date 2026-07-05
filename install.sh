#!/bin/bash
# ============================================================
# MacVault — One-liner installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
# ============================================================
set -euo pipefail

DEST="${1:-$HOME/.local/bin}"

echo "[*] Installing macvault to $DEST ..."

command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required."; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "[!] openssl required."; exit 1; }

mkdir -p "$DEST"

python3 - "$DEST/macvault" << 'PYEOF'
import sys, os, stat

script = r'''#!/usr/bin/env python3
"""
macvault — Encrypted file vault for macOS.
AES-256 at every layer. Zero trace when locked.

  macvault init              Create vault at ~/.macvault/<random>.sparsebundle
  macvault init <path>       Create vault at custom path
  macvault open              Open default vault
  macvault open <path>       Open vault at custom path
  macvault close             Lock & unmount
  macvault add <path>        Move a file into the vault
  macvault remove <path>     Restore a file from the vault
  macvault list              Show tracked files
  macvault status            Show vault location & state
  macvault uninstall         Restore all, delete vault, remove self
"""

import argparse, hashlib, json, os, secrets, shutil, subprocess, sys, tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve()
VAULT_HOME = Path.home() / ".macvault"
CONFIG_FILE = VAULT_HOME / "config.json"
STATE_FILE = Path(f"/tmp/.mv_state_{os.getuid()}")
VAULT_SIZE_MB = int(os.environ.get("MACVAULT_SIZE", "5120"))

def load_config():
    if CONFIG_FILE.exists(): return json.loads(CONFIG_FILE.read_text())
    return {}

def save_config(cfg):
    VAULT_HOME.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))

def get_default_vault(): return load_config().get("vault")

def set_default_vault(path):
    cfg = load_config()
    cfg["vault"] = str(Path(path).resolve())
    save_config(cfg)

def die(msg): print(f"[!] {msg}", file=sys.stderr); sys.exit(1)
def ok(msg):  print(f"[+] {msg}")
def info(msg): print(f"[*] {msg}")

def getpass_verify(prompt="Passphrase: "):
    import getpass
    p1 = getpass.getpass(prompt)
    p2 = getpass.getpass("Confirm:   ")
    if p1 != p2: die("Passphrases do not match.")
    if len(p1) < 8: die("Passphrase must be at least 8 characters.")
    return p1

def read_state():
    if STATE_FILE.exists(): return json.loads(STATE_FILE.read_text())
    return None

def write_state(data):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(data))

def clear_state(): STATE_FILE.unlink(missing_ok=True)

def require_open():
    st = read_state()
    if not st: die("Vault is not open. Run 'macvault open' first.")
    if not Path(st["mount"]).ismount():
        clear_state()
        die("Mount point gone. Run 'macvault open' again.")
    return st

def manifest_path(mount): return os.path.join(mount, ".manifest.enc")

def read_manifest(mount, passphrase):
    mp = manifest_path(mount)
    if not os.path.exists(mp): return {}
    try:
        out = subprocess.run(
            ["openssl", "enc", "-aes-256-cbc", "-d", "-pbkdf2", "-iter", "100000",
             "-pass", f"pass:{passphrase}", "-in", mp],
            capture_output=True, text=True, check=True)
        return json.loads(out.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        die("Failed to decrypt manifest. Wrong passphrase or corrupted data.")

def write_manifest(mount, passphrase, data):
    mp = manifest_path(mount)
    plain = json.dumps(data, indent=2)
    subprocess.run(
        ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "100000",
         "-pass", f"pass:{passphrase}", "-in", "/dev/stdin", "-out", mp],
        input=plain, text=True, check=True)

def file_hash(path): return hashlib.sha256(str(path).encode()).hexdigest()[:16]
def random_basename(): return f"{secrets.token_hex(10)}.sparsebundle"

def cmd_init(args):
    if args.vault:
        vault = Path(args.vault).resolve()
    else:
        VAULT_HOME.mkdir(parents=True, exist_ok=True)
        vault = VAULT_HOME / random_basename()
    if vault.exists(): die(f"Already exists: {vault}")
    info(f"Creating vault: {vault}")
    passphrase = getpass_verify("Set vault passphrase: ")
    subprocess.run(
        ["hdiutil", "create", "-size", f"{VAULT_SIZE_MB}m", "-fs", "APFS",
         "-encryption", "AES-256", "-stdinpass", "-type", "SPARSEBUNDLE",
         "-volname", "vault", str(vault)],
        input=passphrase.encode(), check=True)
    mount = tempfile.mkdtemp(prefix=".mv_", dir="/tmp")
    subprocess.run(
        ["hdiutil", "attach", "-stdinpass", "-mountpoint", mount,
         "-nobrowse", str(vault)],
        input=passphrase.encode(), check=True)
    write_manifest(mount, passphrase, {})
    subprocess.run(["hdiutil", "detach", mount], check=True)
    os.rmdir(mount)
    set_default_vault(str(vault))
    ok(f"Vault ready: {vault}")
    info(f"Size: {VAULT_SIZE_MB} MB  |  Passphrase: only you know it. No recovery.")

def cmd_open(args):
    if args.vault:
        vault_path = str(Path(args.vault).resolve())
    else:
        vault_path = get_default_vault()
        if not vault_path: die("No vault found. Run 'macvault init' first.")
    vault = Path(vault_path)
    if not vault.exists(): die(f"Vault not found: {vault}")
    if read_state(): die("A vault is already open. Run 'macvault close' first.")
    passphrase = getpass_verify("Vault passphrase: ")
    mount = tempfile.mkdtemp(prefix=".mv_", dir="/tmp")
    try:
        subprocess.run(
            ["hdiutil", "attach", "-stdinpass", "-mountpoint", mount,
             "-nobrowse", str(vault)],
            input=passphrase.encode(), check=True, capture_output=True)
    except subprocess.CalledProcessError:
        os.rmdir(mount)
        die("Wrong passphrase or corrupted vault.")
    manifest = read_manifest(mount, passphrase)
    write_state({"vault": str(vault), "mount": mount, "passphrase": passphrase})
    ok(f"Vault open -- {len(manifest)} file(s) tracked.")

def cmd_close(args):
    st = require_open()
    mount, passphrase = st["mount"], st["passphrase"]
    mp = manifest_path(mount)
    manifest = read_manifest(mount, passphrase) if os.path.exists(mp) else {}
    write_manifest(mount, passphrase, manifest)
    subprocess.run(["hdiutil", "detach", mount, "-force"], check=True)
    os.rmdir(mount)
    clear_state()
    ok(f"Vault locked -- {len(manifest)} file(s) secured.")

def cmd_add(args):
    st = require_open()
    src = Path(args.file).resolve()
    if not src.exists(): die(f"File not found: {src}")
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    key = str(src)
    if key in manifest: die(f"Already in vault: {src}")
    h = file_hash(key)
    dst = os.path.join(mount, h)
    if os.path.exists(dst): die("Hash collision -- rename the file and try again.")
    shutil.move(str(src), dst)
    manifest[key] = h
    write_manifest(mount, passphrase, manifest)
    ok(f"Added: {src}")

def cmd_remove(args):
    st = require_open()
    src = str(Path(args.file).resolve())
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    if src not in manifest: die(f"Not in vault: {src}")
    h = manifest[src]
    vaulted = os.path.join(mount, h)
    if os.path.exists(vaulted):
        os.makedirs(os.path.dirname(src), exist_ok=True)
        shutil.move(vaulted, src)
    del manifest[src]
    write_manifest(mount, passphrase, manifest)
    ok(f"Restored: {src}")

def cmd_list(args):
    st = require_open()
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    if not manifest: info("Vault is empty."); return
    print(f"\n  {len(manifest)} file(s) tracked:\n")
    for orig, h in sorted(manifest.items()):
        vaulted = Path(mount) / h
        size = ""
        if vaulted.exists():
            sz = vaulted.stat().st_size
            if sz < 1024: size = f"{sz} B"
            elif sz < 1024*1024: size = f"{sz/1024:.1f} KB"
            else: size = f"{sz/(1024*1024):.1f} MB"
        print(f"  {orig}")
        print(f"    -> {h}  ({size})")
    print()

def cmd_status(args):
    v = get_default_vault()
    if v:
        p = Path(v)
        if p.exists():
            if p.is_dir():
                sz = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
            else:
                sz = p.stat().st_size
            print(f"  Default vault: {v}")
            print(f"  Size on disk:  {sz / (1024*1024):.1f} MB")
        else:
            print(f"  Default vault: {v}  (missing!)")
    else:
        print("  No vault configured. Run 'macvault init' to create one.")
    st = read_state()
    if st:
        print(f"  State:         OPEN -> {st['mount']}")
    else:
        print("  State:         locked")

def cmd_uninstall(args):
    st = read_state()
    vault_path = None
    if st:
        mount, passphrase = st["mount"], st["passphrase"]
        vault_path = st["vault"]
        manifest = read_manifest(mount, passphrase)
        for orig, h in manifest.items():
            vaulted = os.path.join(mount, h)
            if os.path.exists(vaulted):
                os.makedirs(os.path.dirname(orig), exist_ok=True)
                shutil.move(vaulted, orig)
                ok(f"Restored: {orig}")
        subprocess.run(["hdiutil", "detach", mount, "-force"], check=True)
        os.rmdir(mount)
        clear_state()
    else:
        vault_path = get_default_vault()
    if vault_path:
        p = Path(vault_path)
        if p.exists():
            if p.is_dir(): shutil.rmtree(p)
            else: p.unlink()
            ok(f"Deleted: {vault_path}")
    if CONFIG_FILE.exists(): CONFIG_FILE.unlink()
    try: VAULT_HOME.rmdir()
    except OSError: pass
    info("Removing macvault...")
    SCRIPT.unlink(missing_ok=True)
    ok("Uninstalled. No trace remains.")

def main():
    parser = argparse.ArgumentParser(
        description="macvault -- encrypted file vault for macOS",
        usage="macvault <command> [args]")
    subs = parser.add_subparsers(dest="command")
    p = subs.add_parser("init", help="Create a new vault (random name if no path given)")
    p.add_argument("vault", nargs="?", help="Custom vault path (optional)")
    p = subs.add_parser("open", help="Unlock and mount the default vault (or specify path)")
    p.add_argument("vault", nargs="?", help="Vault path (uses default if omitted)")
    subs.add_parser("close", help="Lock and unmount the vault")
    p = subs.add_parser("add", help="Move a file or folder into the vault")
    p.add_argument("file", help="Path to the file or folder")
    p = subs.add_parser("remove", help="Restore a file from the vault")
    p.add_argument("file", help="Original path of the file to restore")
    subs.add_parser("list", help="Show all tracked files (vault must be open)")
    subs.add_parser("status", help="Show vault location and lock state")
    subs.add_parser("uninstall", help="Restore all files, delete vault, remove macvault")
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)
    {"init": cmd_init, "open": cmd_open, "close": cmd_close, "add": cmd_add,
     "remove": cmd_remove, "list": cmd_list, "status": cmd_status,
     "uninstall": cmd_uninstall}[args.command](args)

if __name__ == "__main__":
    main()
'''

dest = sys.argv[1]
with open(dest, 'w') as f:
    f.write(script)
os.chmod(dest, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
print(f"[+] macvault written to {dest}")
PYEOF

echo ""
echo "[+] macvault installed to $DEST/macvault"
echo ""
echo "  Make sure $DEST is in your PATH:"
echo "    export PATH=\"$DEST:\$PATH\""
echo ""
echo "  Then just run it to see commands:"
echo "    macvault"
echo ""
echo "  Quick start:"
echo "    macvault init       # creates ~/.macvault/<random>.sparsebundle"
echo "    macvault open       # unlock & mount"
echo "    macvault add ~/secret.pdf"
echo "    macvault list"
echo "    macvault close"
