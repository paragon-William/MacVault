![MacVault](macvault.jpeg)
# MacVault

A portable encrypted file store for macOS. AES-256 at every layer. Zero trace when locked. Installs as a bland system utility.

## Install

```bash
# One-liner (installs as `mvs` to ~/.local/bin)
curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash

# Custom name and path
./install.sh /usr/local/bin mytool
```

Requires only `python3` and `openssl` — both included with macOS.

## Quick start

```bash
mvs init                        # creates ~/.local/share/mvs/<random>.sparsebundle
mvs open                        # prompts for passphrase, mounts
mvs add ~/Documents/tax.pdf     # move a file into the store
mvs add ~/Desktop/project/      # move a folder (drag & drop works)
mvs list                        # show what's tracked
mvs remove ~/Documents/tax.pdf  # restore a file by path
mvs remove                      # interactive: pick by number
mvs restore                     # restore ALL files at once
mvs close                       # lock & unmount
mvs status                      # check what's where
```

## Commands

| Command | Description |
|---|---|
| `mvs init [path]` | Create store (random name at default location if no path) |
| `mvs open [path]` | Unlock and mount (default store if no path) |
| `mvs close` | Lock and unmount |
| `mvs add [path]` | Move file in (interactive prompt if no path) |
| `mvs remove [path]` | Restore file (numbered list if no path) |
| `mvs list` | Show all tracked files |
| `mvs restore` | Restore ALL files (keeps store intact) |
| `mvs status` | Show location and lock state |
| `mvs uninstall` | Restore all, delete store, remove self |

## How it works

```
mvs init
  → creates AES-256 encrypted APFS sparsebundle at ~/.local/share/mvs/<random>.sparsebundle
  → creates empty AES-256-CBC encrypted manifest inside
  → saves path to ~/.local/share/mvs/config.json

mvs open
  → prompts for passphrase
  → hdiutil attach (APFS AES-256) at /tmp/.mvs_XXXXX (hidden from Finder)
  → openssl decrypts .manifest.enc → in-memory index

mvs add ~/secret.pdf
  → moves file into mount, named sha256(path)
  → updates encrypted manifest

mvs close
  → re-encrypts manifest → hdiutil detach → removes temp mount
  → vault file is opaque random data
```

## Security

- **Dual-layer AES-256**: APFS image encryption + `openssl enc -aes-256-cbc` manifest encryption. Even when mounted, file paths are ciphertext.
- **Passphrase never stored**: Provided at runtime. No recovery — lose it, lose the data.
- **No daemon, no root**: Runs only when invoked. No background processes.
- **No hardcoded secrets**: Zero keys or passphrases in the script.
- **Zero trace when locked**: The sparsebundle is indistinguishable from random bytes.
- **PBKDF2 key derivation**: Manifest encryption uses 100,000 iterations.

