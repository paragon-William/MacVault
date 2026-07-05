#!/bin/bash
# ============================================================
# MacVault — One-liner installer
#   curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
# ============================================================
set -euo pipefail

DEST="${1:-$HOME/.local/bin}"
NAME="${2:-mvs}"

echo "[*] Installing $NAME to $DEST ..."

command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required."; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "[!] openssl required."; exit 1; }

mkdir -p "$DEST"

python3 - "$DEST/$NAME" << 'PYEOF'
import sys, os, stat

script = r'''#!/usr/bin/env python3
"""
  init              Create store at ~/.local/share/mvs/<random>.sparsebundle
  init <path>       Create store at custom path
  open              Open default store
  open <path>       Open store at custom path
  close             Lock & unmount
  add <path>        Move a file into the store
  remove <path>     Restore a file from the store
  list              Show tracked files
  status            Show store location & state
  restore           Restore ALL files (keeps store intact)
  uninstall         Restore all, delete store, remove self
"""

import argparse, hashlib, json, os, secrets, shutil, subprocess, sys, tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve()
BIN_NAME = SCRIPT.name
VAULT_HOME = Path.home() / ".local" / "share" / "mvs"
CONFIG_FILE = VAULT_HOME / "config.json"
STATE_FILE = Path(f"/tmp/.mvs_{os.getuid()}")
VAULT_SIZE_MB = int(os.environ.get("MACVAULT_SIZE", "5120"))

C = {"R":chr(27)+"[91m","G":chr(27)+"[92m","Y":chr(27)+"[93m","B":chr(27)+"[94m","C":chr(27)+"[96m",
     "W":chr(27)+"[97m","D":chr(27)+"[2m","X":chr(27)+"[0m","BD":chr(27)+"[1m"+chr(27)+"[2m"}

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

def die(msg): print(f"{C['R']}[!]{C['X']} {msg}", file=sys.stderr); sys.exit(1)
def ok(msg):  print(f"{C['G']}[+]{C['X']} {msg}")
def info(msg): print(f"{C['C']}[*]{C['X']} {msg}")

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
    if not st: die("Store is not open. Run '" + BIN_NAME + " open' first.")
    if not Path(st["mount"]).is_mount():
        clear_state()
        die("Mount point gone. Run '" + BIN_NAME + " open' again.")
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

def resolve_path(input_path):
    p = input_path.replace('\\', '')
    p = os.path.expanduser(p)
    p = p.rstrip('/')
    if os.path.exists(p): return p
    if os.path.exists(p + '.app'): return p + '.app'
    return p

def add_one(src, mount, passphrase, manifest):
    key = str(Path(src).resolve())
    if key in manifest:
        print(f"  [!] Already in store: {src}")
        return manifest
    h = file_hash(key)
    dst = os.path.join(mount, h)
    if os.path.exists(dst):
        print(f"  [!] Hash collision -- rename and try again.")
        return manifest
    shutil.move(str(Path(src).resolve()), dst)
    manifest[key] = h
    write_manifest(mount, passphrase, manifest)
    ok(f"Added: {key}")
    return manifest

def remove_one(orig_key, mount, passphrase, manifest):
    if orig_key not in manifest:
        print(f"  [!] Not in store: {orig_key}")
        return manifest
    h = manifest[orig_key]
    vaulted = os.path.join(mount, h)
    if os.path.exists(vaulted):
        os.makedirs(os.path.dirname(orig_key), exist_ok=True)
        shutil.move(vaulted, orig_key)
    del manifest[orig_key]
    write_manifest(mount, passphrase, manifest)
    ok(f"Restored: {orig_key}")
    return manifest

def cmd_init(args):
    if args.vault:
        vault = Path(args.vault).resolve()
    else:
        VAULT_HOME.mkdir(parents=True, exist_ok=True)
        vault = VAULT_HOME / random_basename()
    if vault.exists(): die(f"Already exists: {vault}")
    info(f"Creating store: {vault}")
    passphrase = getpass_verify("Set passphrase: ")
    subprocess.run(
        ["hdiutil", "create", "-size", f"{VAULT_SIZE_MB}m", "-fs", "APFS",
         "-encryption", "AES-256", "-stdinpass", "-type", "SPARSEBUNDLE",
         "-volname", "vault", str(vault)],
        input=passphrase.encode(), check=True)
    mount = tempfile.mkdtemp(prefix=".mvs_", dir="/tmp")
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
        if not vault_path: die("No store found. Run '" + BIN_NAME + "' init first.")
    vault = Path(vault_path)
    if not vault.exists(): die(f"Vault not found: {vault}")
    if read_state(): die("A store is already open. Run '" + BIN_NAME + "' close first.")
    passphrase = getpass_verify("Passphrase: ")
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
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    if args.file:
        resolved = resolve_path(args.file)
        if not os.path.exists(resolved): die(f"File not found: {resolved}")
        add_one(resolved, mount, passphrase, manifest)
    else:
        print("[vault] Enter paths to add (Ctrl+C to exit)")
        print("        Drag & drop works. Backslashes auto-stripped.")
        manifest = read_manifest(mount, passphrase)
        try:
            while True:
                p = input("path> ").strip()
                if not p: continue
                resolved = resolve_path(p)
                if not os.path.exists(resolved):
                    print(f"  [!] Not found: {resolved}")
                    continue
                print(f"  -> {resolved}")
                manifest = add_one(resolved, mount, passphrase, manifest)
        except (KeyboardInterrupt, EOFError):
            print()

def cmd_remove(args):
    st = require_open()
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    if args.file:
        resolved = resolve_path(args.file)
        key = str(Path(resolved).resolve())
        if key not in manifest:
            key = str(Path(os.path.expanduser(args.file.replace('\\', ''))).resolve())
        if key not in manifest: die(f"Not in vault: {args.file}")
        remove_one(key, mount, passphrase, manifest)
    else:
        if not manifest: info("Vault is empty."); return
        items = sorted(manifest.items())
        try:
            while True:
                print(f"\n  {len(items)} file(s) in vault:\n")
                for i, (orig, h) in enumerate(items, 1):
                    vaulted = Path(mount) / h
                    size = ""
                    if vaulted.exists():
                        sz = vaulted.stat().st_size
                        if sz < 1024: size = f"{sz} B"
                        elif sz < 1024*1024: size = f"{sz/1024:.1f} KB"
                        else: size = f"{sz/(1024*1024):.1f} MB"
                    print(f"  [{i}] {orig}  ({size})")
                print(f"  [a] restore ALL  [q] quit")
                choice = input("\n  pick> ").strip()
                if choice.lower() == 'q': break
                if choice.lower() == 'a':
                    manifest = cmd_restore_inner(mount, passphrase, manifest)
                    items = sorted(manifest.items())
                    if not items: break
                    continue
                try:
                    idx = int(choice) - 1
                    if 0 <= idx < len(items):
                        manifest = remove_one(items[idx][0], mount, passphrase, manifest)
                        items = sorted(manifest.items())
                        if not items: info("Vault is now empty."); break
                    else:
                        print(f"  [!] Invalid number: {choice}")
                except ValueError:
                    print(f"  [!] Enter a number, 'a' for all, or 'q' to quit")
        except (KeyboardInterrupt, EOFError):
            print()

def cmd_restore_inner(mount, passphrase, manifest):
    for orig, h in list(manifest.items()):
        vaulted = os.path.join(mount, h)
        if os.path.exists(vaulted):
            os.makedirs(os.path.dirname(orig), exist_ok=True)
            shutil.move(vaulted, orig)
            ok(f"Restored: {orig}")
    manifest.clear()
    write_manifest(mount, passphrase, manifest)
    return manifest

def cmd_restore(args):
    st = require_open()
    mount, passphrase = st["mount"], st["passphrase"]
    manifest = read_manifest(mount, passphrase)
    if not manifest: info("Vault is already empty."); return
    cmd_restore_inner(mount, passphrase, manifest)
    ok("All files restored. Vault is now empty.")

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
        print(f"  {C['D']}No store configured. Run '{BIN_NAME} init' to create one.{C['X']}")
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
    info("Removing " + BIN_NAME + "...")
    SCRIPT.unlink(missing_ok=True)
    ok("Uninstalled. No trace remains.")

def main():
    parser = argparse.ArgumentParser(
        description="file utility",
        usage=BIN_NAME + " <command> [args]")
    subs = parser.add_subparsers(dest="command")
    p = subs.add_parser("init", help="Create a new store")
    p.add_argument("vault", nargs="?", help="Custom path (optional)")
    p = subs.add_parser("open", help="Unlock and mount the default store")
    p.add_argument("vault", nargs="?", help="Store path (uses default if omitted)")
    subs.add_parser("close", help="Lock and unmount")
    p = subs.add_parser("add", help="Move files in (interactive if no path)")
    p.add_argument("file", nargs="?", help="Path to file or folder")
    p = subs.add_parser("remove", help="Restore files (numbered list if no path)")
    p.add_argument("file", nargs="?", help="Original path to restore")
    subs.add_parser("list", help="Show tracked files")
    subs.add_parser("restore", help="Restore ALL files")
    subs.add_parser("status", help="Show location and lock state")
    subs.add_parser("uninstall", help="Restore all, delete store, remove self")
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)
    {"init": cmd_init, "open": cmd_open, "close": cmd_close, "add": cmd_add,
     "remove": cmd_remove, "list": cmd_list, "restore": cmd_restore,
     "status": cmd_status, "uninstall": cmd_uninstall}[args.command](args)

if __name__ == "__main__":
    main()
'''

dest = sys.argv[1]
with open(dest, 'w') as f:
    f.write(script)
os.chmod(dest, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
print(f"[+] {os.path.basename(dest)} written to {dest}")
PYEOF

echo ""
echo "[+] $NAME installed to $DEST/$NAME"
echo ""
echo "  Make sure $DEST is in your PATH:"
echo "    export PATH=\"$DEST:\$PATH\""
echo ""
echo "  Keep commands out of zsh history (prefix with a space):"
echo "    echo 'setopt HIST_IGNORE_SPACE' >> ~/.zshrc && source ~/.zshrc"
echo ""
echo "  Then just run it to see commands:"
echo "    $NAME"
echo ""
echo "  Quick start:"
echo "    $NAME init       # creates ~/.local/share/mvs/<random>.sparsebundle"
echo "    $NAME open       # unlock & mount"
echo "     $NAME add       # interactive add (drag & drop paths)"
echo "    $NAME list       # show tracked files"
echo "     $NAME remove    # interactive remove (pick by number)"
echo "    $NAME restore    # restore ALL files at once"
echo "    $NAME close      # lock it all up"
