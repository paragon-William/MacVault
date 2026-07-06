![MacVault](macvault.jpeg)
# MacVault
# Stable 1.0.19

A portable encrypted file store for macOS (and now Linux). AES‑256 at every layer. Zero trace when locked. Installs as an innocuous system utility.

## Install

~~~bash
curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | bash
~~~

## Quick start

~~~bash
mvs init                        # creates a vault named 'default'
mvs open                        # unlocks and mounts
mvs add ~/Documents/tax.pdf     # move a file into the vault
mvs add ~/Desktop/project/      # move a folder (drag & drop works)
mvs list                        # show tracked files
mvs show                        # restore all to origin (keeps tracking)
mvs hide                        # instant re‑hide
mvs close                       # lock and unmount
mvs status                      # vault location and state
~~~

## Commands

| Command | Description |
|---|---|
| `mvs init [name]` | Create a new vault (default name: `default`) |
| `mvs open [name]` | Unlock and mount a vault |
| `mvs close` | Lock and unmount |
| `mvs add [path]` | Move files/folders into the vault |
| `mvs remove [path]` | Restore files (interactive if no path) |
| `mvs list` | Show all tracked files |
| `mvs show` | Restore all files to origin (tracking preserved) |
| `mvs hide` | Hide all tracked files back into the vault |
| `mvs restore` | Restore all files and clear tracking |
| `mvs status` | Show vault location, state, and size |
| `mvs log` | Show encrypted audit log |
| `mvs vault create <name>` | Create an additional vault |
| `mvs vault use <name>` | Switch the active vault |
| `mvs vault list` | List all vaults |
| `mvs disguise [name]` | Move vault to a stealthy system path |
| `mvs uninstall` | Restore everything and delete vault + binary |

## Multi‑vault

Create multiple vaults for different purposes. Switch between them with `vault use`. Each vault is an independent encrypted sparsebundle with its own passphrase and manifest.

## Keychain integration (macOS)

Passphrases are securely stored in the macOS Keychain after first use. Subsequent `open` commands will not prompt for a passphrase.

## Plugin system

Place executable scripts in `~/.mvs/plugins/` named `on-open`, `on-close`, `on-add`, `on-remove`. They will be invoked with relevant file paths when the corresponding event occurs.

## Audit log

Every operation (add, remove, hide, show, restore, open, close) is recorded in an encrypted, append‑only log inside the vault. View with `mvs log`.

## Cross‑platform

Linux support is included (requires `cryptsetup` and `ext4`). The tool automatically selects the appropriate backend.

## Security

- **Dual‑layer AES‑256**: APFS/LUKS image encryption + `openssl enc -aes-256-cbc -pbkdf2` manifest encryption.
- **Keychain storage**: Passphrases never stored on disk in plaintext.
- **Atomic manifest writes**: Prevents corruption on crash.
- **No daemon, no root**: Runs only when invoked.