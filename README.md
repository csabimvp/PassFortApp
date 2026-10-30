# PassFort

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.svg">
  <img src="docs/images/hero-light.svg" alt="The PassFort app icon beside the vault window: a sidebar of colour-coded categories, an account list with category tiles, and an account's details with a strength pill and a one-time code." width="100%">
</picture>

[![CI](https://github.com/csabimvp/PassFortApp/actions/workflows/ci.yml/badge.svg)](https://github.com/csabimvp/PassFortApp/actions/workflows/ci.yml)

A local-first password manager for macOS. Your vault is one encrypted file on your Mac, and the
app works without an account or a network connection. A command-line client opens the same vault
on Linux, and on Windows through WSL2.

Status: personal project, in active development. There is no packaged release yet, so you build
the app and the CLI from source. Sync between devices works, but it needs a PassFort sync server,
and the one the maintainer runs isn't public.

## Features

- Accounts with usernames, passwords, URLs, notes and custom fields. Search, favourites, categories
  and password history.
- One-time codes (TOTP), added from the secret or by reading a QR code.
- A password generator for random passwords or EFF-wordlist passphrases.
- Password health: weak, reused, old and expiring passwords, and plain `http://` logins.
- Quick Access: press ⌃⌥Space in any app, search, and press Return to copy the password. ⌘Return
  opens the account's website and fills the clipboard one paste at a time: the first ⌘V pastes the
  username, the next the password. Clipboard managers don't see the copy, and it's cleared on lock
  or after 20 seconds (adjustable in Settings).
- Auto-lock when idle, on sleep and on screen lock.
- Backups to a folder you choose, with retention, optionally on every lock.
- Import from a Password Safe plain-text export or from another PassFort vault. Plaintext export
  from the CLI.
- A recovery key for a forgotten master password, and Recently Deleted for removed accounts.
- Optional end-to-end encrypted sync between devices. Each device keeps a complete vault and works
  offline, and edits made on two devices at once are kept as a conflict copy, never dropped.
- `passfort-cli`, a command-line client for the same vault format, with sync. It runs on macOS
  and on Linux, including WSL2 on Windows.

## Requirements

The app:

- macOS 26.5 or later on Apple silicon
- Xcode 26.6
- An Apple ID signed in to Xcode (a free one is enough) to sign the build

The CLI on Linux:

- Ubuntu 22.04 or 24.04 on x86_64, natively or in WSL2
- Swift 6.3.3, installed with [swiftly](https://www.swift.org/install/linux/)
- `libsqlite3-dev`, `libcurl4-openssl-dev` and `libssl-dev`

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/csabimvp/PassFortApp.git && cd PassFortApp
   ```

2. Find your development team ID. It is the `OU` field of your Apple Development certificate. If
   you don't have the certificate yet, open Xcode, go to Settings > Accounts, select your Apple ID
   and click Manage Certificates.

   ```bash
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```

3. Build and install. The script makes a Release build, signs it with your team and copies it to
   `/Applications/PassFort.app`. The first build takes a few minutes, mostly compiling the crypto
   library.

   ```bash
   DEVELOPMENT_TEAM=ABCDE12345 scripts/install_app.sh
   ```

   Replace `ABCDE12345` with your team ID. To update later, `git pull` and run the same command.
   Your vault lives in the app's sandbox container, so reinstalling doesn't touch it.

4. Optionally, build the CLI. The binary is `.build/release/passfort-cli`.

   ```bash
   cd Packages/PassFortKit && swift build -c release --product passfort-cli
   ```

### The CLI on Linux and WSL2

The CLI is built on the machine it runs on. In WSL2, keep the clone and the vault in the Linux
filesystem (under `~`), not under `/mnt/c`.

1. Install Swift 6.3.3 and the libraries:

   ```bash
   curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
   tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --quiet-shell-followup
   . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
   swiftly install 6.3.3 && swiftly use 6.3.3
   sudo apt-get install -y libsqlite3-dev libcurl4-openssl-dev libssl-dev
   ```

2. Clone and build:

   ```bash
   git clone https://github.com/csabimvp/PassFortApp.git ~/PassFortApp
   cd ~/PassFortApp/Packages/PassFortKit && swift build -c release --product passfort-cli
   ```

   The binary is `.build/release/passfort-cli`.

3. To sync, put the server's pins in `~/.config/passfort/pins`, one base64 SHA-256 per line, then
   join with the vault id from the app's Add a Device…:

   ```bash
   passfort-cli sync join ~/passfort/vault.sqlite --endpoint https://<site>/api/v1 --vault-id <id>
   ```

`copy` and `fill` use the Windows clipboard in WSL2: press Enter after each paste. On Linux outside
WSL2 there is no clipboard support, so use `get`.

## Usage

On first launch, create a vault and choose a master password. The app then shows a recovery key
once. Store it somewhere safe and offline: it is the only way back in if you forget the master
password.

- **Backups.** In Settings, choose a backup folder (a NAS share works well) and how many backups
  to keep. Backups are encrypted like the vault and verified after each write.
- **Moving to another Mac.** Copy a backup over and use Restore from Backup on the new Mac (the
  link on the first screen, or the File menu). The vault it replaces is kept as a safety copy,
  never deleted. The File menu also starts, opens or joins another vault in place of this one.
- **Sync.** In Settings ▸ Sync, enter the server address (`https://<site>/api/v1`) and its
  enrollment secret to put the open vault on the server. On another Mac, choose Join a Synced
  Vault (on the first screen, or the File menu) and paste the invite from Add a Device…. Then
  unlock with the same master password. A Linux or WSL2 machine joins with `passfort-cli sync join`
  (see [The CLI on Linux and WSL2](#the-cli-on-linux-and-wsl2)), and `passfort-cli sync now` brings
  it up to date.
- **Leaving.** `passfort-cli export` writes a whole vault as plaintext JSON after you type a
  confirmation phrase. Delete the file once you've imported it elsewhere.

The CLI works on the same vault format. On Linux, run the built binary instead of `swift run`:

```bash
cd Packages/PassFortKit
swift run passfort-cli init  vault.sqlite
swift run passfort-cli add   vault.sqlite --title github --username me --prompt-password
swift run passfort-cli get   vault.sqlite github
swift run passfort-cli fill  vault.sqlite github   # opens the site; username, then password
```

Every command is listed in [`docs/development.md`](docs/development.md#the-cli).

## Security

Everything in the vault is encrypted, including titles, usernames and URLs. The key comes from your
master password through Argon2id, and each record is sealed with XChaCha20-Poly1305. A manifest MAC
detects records that were deleted or swapped and a vault file that was rolled back. Sync is
end-to-end encrypted and treats the server as hostile. The server stores only sealed records and a
hash of a key it can't use. The app and the CLI pin the server's certificate authority, on Linux
through libcurl and OpenSSL. A hostile server can still withhold or delay changes from your other
devices. It can't read, alter or roll them back unnoticed.

PassFort has not been independently audited. The threat model, including what it does not defend
against, is in [`docs/architecture.md` §3](docs/architecture.md#3-threat-model). To report a
vulnerability, see [`SECURITY.md`](SECURITY.md).

## Architecture

The app and the CLI are built on a local Swift package, `PassFortKit`:

| Module | Language | Role |
|---|---|---|
| `PFCrypto` | C++ (Botan 3) | Holds every key and never hands one out: key derivation, record sealing, the vault header, the manifest MAC |
| `PassFortCrypto` | Swift | The only module that talks to C++; wraps it in an `actor VaultSession` |
| `PassFortVault` | Swift | Storage in SQLite (GRDB), the data model, migrations, import and export, the sync client |
| `CLinuxTLS` | C | Linux only: sync's pinned TLS through libcurl and OpenSSL, and SHA-256 and HMAC |
| `passfort-cli` | Swift | The command-line client, on macOS and Linux |
| `PassFort` | Swift | The macOS app |

The rule that shapes the design: keys stay in C++, and Swift can only ask the session to seal or
open bytes. [`docs/architecture.md`](docs/architecture.md) is the full specification, and
[`docs/adr/`](docs/adr/) records the reasoning behind each major decision. The sync contract is in
[`SyncAPI/`](SyncAPI/).

The code was written by an AI coding agent ([Claude Code](https://claude.com/claude-code)) against
the maintainer's specification and phased build plans ([`docs/runbooks/`](docs/runbooks/)).

## Development

Building, testing and the full CLI reference are in [`docs/development.md`](docs/development.md).
The quick loop:

```bash
cd Packages/PassFortKit && swift build && swift test
xcodebuild test -scheme PassFort -destination 'platform=macOS'
```

On Linux the package builds and tests the same way; the app needs a Mac.

## License

MIT, see [`LICENSE`](LICENSE). Bundled third-party code keeps its own license: Botan (BSD-2-Clause,
a `license.txt` per platform under `Packages/PassFortKit/Sources/PFCrypto/vendor/botan/`) and the
EFF large wordlist (CC BY 3.0 US). GRDB (MIT) and swift-argument-parser (Apache-2.0) are fetched by
SwiftPM. On Linux the CLI links the system's libcurl and OpenSSL.
