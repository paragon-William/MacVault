![MacVault](macvault.jpeg)
# MacVault

A portable encrypted file vault for macOS. AES-256 at every layer. Zero trace when locked.

## Why

MacVault creates an AES-256 encrypted APFS disk image and moves your files inside. The manifest that tracks original file paths is itself encrypted with AES-256-CBC via OpenSSL. When the vault is locked, the image is just a file of random bytes — nothing reveals what's inside. No daemon, no root, no hardcoded secrets.

## Install

```bash
# One-liner (recommended)
curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash

# Or clone and run locally
git clone https://github.com/paragon-William/MacVault.git
cd MacVault && chmod +x install.sh && ./install.sh

# Custom install path
./install.sh /usr/local/bin
```

Requires only `python3` and `openssl` — both included with macOS.

## Quick start

```bash
macvault init ~/vault.img         # create a new vault (prompts for passphrase)
macvault open ~/vault.img         # unlock & mount (prompts for passphrase)
macvault add ~/Documents/tax.pdf  # move a file into the vault
macvault add ~/Desktop/project/   # move a folder into the vault
macvault list                     # show what's tracked
macvault remove ~/Documents/tax.pdf  # restore a file
macvault close                    # lock & unmount
```

## Commands

| Command | Description |
|---|---|
| `macvault init <path>` | Create a new encrypted vault at `<path>` |
| `macvault open <path>` | Unlock and mount the vault |
| `macvault close` | Lock and unmount the vault |
| `macvault add <path>` | Move a file or folder into the open vault |
| `macvault remove <path>` | Restore a file to its original location |
| `macvault list` | Show all tracked files |
| `macvault uninstall` | Restore all files, delete vault, self-destruct |

## How it works

```
macvault init ~/vault.img
  → creates AES-256 encrypted APFS sparse image
  → creates empty AES-256-CBC encrypted manifest inside

macvault open ~/vault.img
  → prompts for passphrase
  → hdiutil attach (APFS AES-256)
  → openssl decrypts .manifest.enc → in-memory manifest
  → mount at /tmp/.mv_XXXXX (hidden from Finder)

macvault add ~/secret.pdf
  → moves file into mount, named sha256(path)
  → updates manifest, re-encrypts it

macvault close
  → re-encrypts manifest
  → hdiutil detach
  → removes temp mount point
  → vault file is now opaque random data
```

## Security

- **Dual-layer AES-256**: APFS image encryption + `openssl enc -aes-256-cbc` manifest encryption. Even when mounted, file paths are ciphertext.
- **Passphrase never stored**: You provide it at runtime. No recovery — lose it, lose the data.
- **No daemon, no root**: Runs only when you invoke it. No background processes.
- **No hardcoded secrets**: The script contains zero keys or passphrases.
- **Zero trace when locked**: The vault file is indistinguishable from random bytes. No metadata reveals its contents, size, or file count.
- **PBKDF2 key derivation**: Manifest encryption uses 100,000 iterations.

