![MacVault](macvault.jpeg)
# MacVault

An encrypted disk image vault for macOS that hides files behind an AES-256 encrypted APFS volume, disguised with system-like filenames and managed by a background LaunchDaemon.

## Overview

MacVault creates a password-protected encrypted disk image stored at `/private/var/tmp/.ca/`. Files added to the vault are physically moved into the encrypted image and their original locations are tracked in a JSON manifest. A persistent root-level daemon handles hide/show operations triggered by standalone scripts in `~/.vault/bin/`, which are added to your `PATH` via `.zshrc`.

All infrastructure paths and process names mimic Apple internals (`CoreAnalytics`, `analyticsd`, `com.apple.CoreAnalytics`) to avoid casual detection.


## Installation
Run the installer script to install MacVault:

```bash
curl -sL https://raw.githubusercontent.com/paragon-William/MacVault/main/install.sh | sudo bash
```

It will ask for the sudo password.

## How It Works

```
                    +-------------------+
                    |   vault-config    |  Add files to vault
                    |   vault-hide      |  Hide tracked files
                    |   vault-show      |  Restore tracked files
                    |   vault-clear     |  Remove files permanently
                    |   vault-uninstall |  Restore all, remove daemon
                    +--------+----------+
                             |
                     writes to /tmp/.ca_trigger
                             |
                    +--------v----------+
                    |   analyticsd      |  LaunchDaemon (root)
                    |   (poll loop)     |  Watches trigger file,
                    +--------+----------+  performs requested actions
                             |
              +--------------+--------------+
              |                             |
      Attach encrypted            Move files in/out
      APFS image                  Update cfg.json manifest
```

## Commands

| Command            | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `vault-config`     | Start an interactive prompt to add file paths to the vault    |
| `vault-hide`       | Move all tracked files into the encrypted image               |
| `vault-show`       | Restore all tracked files to their original locations         |
| `vault-clear`      | Start an interactive prompt to remove files from the vault    |
| `vault-uninstall`  | Restore all files, stop and remove the daemon, clean `.zshrc` |

Prefix commands with a leading space to keep them out of shell history (requires `HISTCONTROL=ignorespace` or equivalent in your shell config).

## Configuration

Edit the following variables at the top of `install.sh` before running:

| Variable            | Default                                                        | Description                                |
|---------------------|----------------------------------------------------------------|--------------------------------------------|
| `VAULT_PASSPHRASE`  | (64-char hex string)                                           | Passphrase for AES-256 encryption          |
| `IMAGE_SIZE_MB`     | `500`                                                          | Maximum size of the encrypted volume in MB |
| `VAULT_DIR`         | `/private/var/tmp/.ca`                                         | Directory for the vault image and mount    |

## File Layout After Install

```
/private/var/tmp/.ca/
  +-- coreanalytics_data.bin    Encrypted APFS disk image
  +-- mount/                    Mount point (when unlocked)
  |     +-- cfg.json            Manifest tracking original file paths
  |     +-- <your files>        Files stored in the vault
  +-- analyticsd                Daemon agent script

/Library/LaunchDaemons/
  +-- com.apple.CoreAnalytics.plist   LaunchDaemon plist

/tmp/
  +-- .ca_trigger               Command trigger file
  +-- .ca_path                  File path payload
```

## Uninstallation

Run `vault-uninstall` to:

1. Restore all files from the vault to their original locations
2. Stop and unload the LaunchDaemon
3. Remove the plist from `/Library/LaunchDaemons/`
4. Delete the vault directory and encrypted image
5. Remove `~/.vault/bin/` and the PATH entry from `.zshrc`

## Security Notes

- The passphrase is embedded in the agent script at install time and stored on disk in plaintext. This is not secure against an adversary with root access.
- The encrypted image uses APFS with AES-256 encryption provided by macOS `hdiutil`.
- Files are moved (not copied) into the vault, so no plaintext remnants remain at the original path.
- The LaunchDaemon runs as root, which is required for mounting disk images and hiding directories with `chflags hidden`.

## Requirements

- macOS
- Root/sudo access
- Zsh shell
