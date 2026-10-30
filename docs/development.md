# Development

How to build, test and run every part of PassFort locally. The README has the short version; this is
the full loop. Toolchain versions are pinned in the README's *Requirements* and in
`architecture.md` §4.1.

## Setup

`xcodebuild` and the Swift 6.3 toolchain need the full Xcode, not the Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app
brew install cmake                     # native-tests/ only
```

Botan is vendored and committed (ADR-0001), so it doesn't need to be installed. A Homebrew Botan is
only for running `scripts/build_botan.sh`.

## What to run, and when

| Situation | Command(s) |
|---|---|
| Edited Swift, or C++ that Swift compiles (`Sources/PFCrypto/`) | `swift build` then `swift test` (in `Packages/PassFortKit/`) |
| Edited a `.cpp` / `.hpp` under `native-tests/` or `Sources/PFCrypto/` | `cmake --build native-tests/build` then `ctest --test-dir native-tests/build` |
| Added a file to `native-tests/CMakeLists.txt` | re-run `cmake -S native-tests -B native-tests/build` first, then build |
| Touched a boundary function (`pf_*`) | also the sanitizer build (below) |
| Edited the app (`PassFort/`) | `xcodebuild test -scheme PassFort -destination 'platform=macOS'` |
| Edited `SyncAPI/` or `Sources/PassFortVault/Sync/` | `swift test --filter SyncDTOTests` (in `Packages/PassFortKit/`), then the server's suite (below) |
| Edited `Sources/CLinuxTLS/`, or code under `#if os(Linux)` | the Linux loop (below) in WSL2, or open a PR: the Mac never compiles it, only the `linux` CI job does |
| Before a commit | everything above that the change touches, plus the format checks |

## Swift package

```bash
cd Packages/PassFortKit && swift build      # all targets, including the C++ core
cd Packages/PassFortKit && swift test       # PFCryptoBoundaryTests, PassFortVaultTests, PassFortCLITests
swift test --filter PFCryptoBoundaryTests   # one suite, from inside Packages/PassFortKit/
```

`swift build` compiles every `.cpp` under `Sources/PFCrypto/` automatically, so new files join the
build without a `Package.swift` edit. It also builds `pf-killtest`, the helper process the
mid-write kill test spawns. CI points the test at it with `PF_KILLTEST_BIN`.

## Native C++ tests

Catch2 tests over `PFCrypto`'s internals, built by CMake outside the app's build graph. They
deliberately reach past the `boundary/` facade into `keyring/`, `aead/` and `manifest/`, which is the
one sanctioned exception to the layering rules (`architecture.md` §13). Run them from the repo root:

```bash
cmake -S native-tests -B native-tests/build      # configure; re-run after editing CMakeLists.txt
cmake --build native-tests/build
ctest --test-dir native-tests/build --output-on-failure
ctest --test-dir native-tests/build -R kat       # filter by test-case name (a regex)
./native-tests/build/pfcrypto_tests "[kat]"      # or by Catch2 tag, on the binary directly
```

### Sanitizer build

ASan and UBSan, in a separate build directory. Required after touching any boundary function, and
run by CI on every push. Any sanitizer report counts as a failure, even when every assertion passes.

```bash
cmake -S native-tests -B native-tests/build-san \
  -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"
cmake --build native-tests/build-san
ctest --test-dir native-tests/build-san --output-on-failure
```

## Linux and WSL2

The package builds and passes on Ubuntu x86_64, natively or in WSL2 (`m6-portable-cli.md`). CI's
`linux` job runs it in `swift:6.3.3-noble`. Install Swift 6.3.3 with `swiftly` and the libraries
as in the README (*The CLI on Linux and WSL2*), plus `cmake` for the native tests:

```bash
cd Packages/PassFortKit && swift build && swift test
swift test --sanitize=address \
  --filter 'CurlTransportTests|LinuxPinningTests|PinSetTests|OneTimeCodeTests'   # CLinuxTLS under ASan
cmake -S native-tests -B native-tests/build -DCMAKE_CXX_COMPILER=clang++        # from the repo root
cmake --build native-tests/build && ctest --test-dir native-tests/build --output-on-failure
```

`CLinuxTLS`, `CurlTransport`, `WindowsClipboard` and the Linux-only tests (`LinuxPinningTests`,
`CurlTransportTests`) compile only here; the Apple-only ones (`PinningTests`,
`URLSessionTransportTests`) only on the Mac. In WSL2, keep the clone and any vault under `~`, not
`/mnt/c`. The ASan run reads its LeakSanitizer suppressions from `.github/lsan-suppressions.txt`
in CI (`LSAN_OPTIONS=suppressions=…`); only XCTest's runner is suppressed.

## The app

```bash
xcodebuild -scheme PassFort -destination 'platform=macOS' build
xcodebuild test -scheme PassFort -destination 'platform=macOS'
```

To install a Release build for daily use:

```bash
scripts/install_app.sh                                       # -> /Applications/PassFort.app
scripts/install_app.sh ~/Applications                        # -> a folder of your choice
scripts/install_app.sh --build-only ~/Desktop/PassFort-build # build and verify, install nothing
scripts/install_app.sh --keep-build                          # keep the ~1 GB Build/ cache
```

The script signs with your own development certificate, with the hardened runtime on and no
debugger-attach entitlement. There is no notarization (M4 was scaled back; `architecture.md` §14.18).
Quit PassFort before re-running it.

## The CLI

Install it with `scripts/install_cli.sh` (a release build in `~/.local/bin`, with zsh and bash
completion), or run it from `Packages/PassFortKit/` with `swift run passfort-cli <subcommand>`.
`init` and `sync join` prompt for a new or the synced vault's password. Every other command that
opens a vault prompts for its password and runs the manifest-MAC and anti-rollback checks
(`architecture.md` §5.5) before doing anything else.

**Which vault.** A command acts on `--vault` / `-v` (a remembered name or a path), else on
`$PASSFORT_VAULT`, else on the default vault. The names live in `~/.config/passfort/config.json`,
which holds paths only (`PASSFORT_CONFIG` points at another file, as `PASSFORT_DEVICE_FILE` does
for the device identity). `init` and `sync join` remember the first vault they create as the
default, or any vault under `--name`.

**Which account.** A title, matched case-insensitively (an exact match first, otherwise every
title containing it); a full id; or an id prefix of at least 4 characters, such as the 8 that
`list` shows. When several accounts match, a terminal gets a numbered list to pick from and a
script gets an error.

```bash
# No vault needed
passfort-cli bench    [--target-ms 500]                     # calibrate Argon2id; print params + timing
passfort-cli gen      [--length 20] [--words N] [-c N]      # passwords or passphrases to stdout
passfort-cli seam                                           # the Swift↔C++ round trip (hidden from --help)

# Vaults
passfort-cli vault    [list]                                # the remembered vaults; * is the default
passfort-cli vault add <name> <path> [--default]            # remember an existing vault
passfort-cli vault use <name>                               # make it the default
passfort-cli vault forget <name>                            # stop remembering it; the file stays
passfort-cli init     <path> [--name N] [--recovery] [--force]  # create a vault
passfort-cli unlock                                         # open + verify; report account counts
passfort-cli verify   [--accept-restore]                    # manifest + anti-rollback check only
passfort-cli passwd   [--no-recovery-key]                   # change the master password
passfort-cli recovery-key                                   # issue a new recovery key
passfort-cli recover  --key <grouped-recovery-key>          # reset the master password

# Accounts (each also takes --vault)
passfort-cli list     [--search Q] [--all]                  # summary index, no secrets
passfort-cli get      <account> [--reveal] [--json]         # one account; secrets only with --reveal / --json
passfort-cli code     <account>                             # the account's current one-time code
passfort-cli copy     <account> [--username|--code]         # to the clipboard until pasted (macOS, WSL2)
passfort-cli fill     <account> [--no-open]                 # open the site; username, then password, one per paste (macOS; WSL2: Enter between)
passfort-cli add      --title T [--username U] [--prompt-password] [--url U] [--note N] [--totp URI]
passfort-cli edit     <account> [--title T] [--username U] [--email E] [--note N] [--totp URI] [--favorite|--no-favorite] [--prompt-password] [--add-url U]
passfort-cli history  <account> [--passwords]               # the account's version timeline
passfort-cli rm       <account>                             # tombstone
passfort-cli undelete <account>                             # bring a tombstoned account back
passfort-cli audit                                          # weak, reused, old, expiring, http://

# Moving data in and out
passfort-cli import       <export.txt> [--dry-run]          # Password Safe plain-text export
passfort-cli import-vault <source> [--only T] [--dry-run]   # accounts from another vault (a name or a path)
passfort-cli backup   <folder> [--keep N]                   # consistent snapshot, no password needed
passfort-cli restore  <backup> [--yes]                      # current vault is moved aside, not deleted
passfort-cli dump                                           # every record, decrypted, as JSON (debug)
passfort-cli export   -o out.json                           # whole vault decrypted; typed phrase required

# Sync (`sync --help`)
passfort-cli sync enable --endpoint URL                     # put this vault on a server
passfort-cli sync join <path> --endpoint URL --vault-id ID [--name N]
passfort-cli sync now | status | devices | disable
```

At a terminal, `list`, `get`, `history`, `audit`, `sync status` and `vault list` are lightly
styled (bold headers, dim labels and ids); a pipe, a file, `NO_COLOR` or `TERM=dumb` gets the same text without escape codes. Scripts
that need fields should read `get --json`, not the human layout.

`passfort-cli <subcommand> --help` lists every option. `edit`'s options are `add`'s names, and `""`
clears a field; `--set key=value` still works. `get --reveal`, `get --json`, `history --passwords`,
`dump` and `export` write secrets in the clear. `export` writes its file with mode `0600`; delete
it when you're done.

After a `restore`, the next unlock reports a rollback on purpose, because the vault really did go
back in time. Confirm that the restore was deliberate with `verify --accept-restore`.

## The sync contract

`SyncAPI/openapi.yaml` and `SyncAPI/fixtures/dto/` are the wire contract between the client and a
sync server. `SyncDTOTests` checks the Swift DTOs against the fixtures, and the client's sync logic
is tested against `FakeSyncServer`, an in-memory server in `Tests/PassFortVaultTests/`, so
`swift test` needs no server.

The server itself lives in the separate, private `PassFortCloud` repository, which pins this one as
a submodule. After a contract change, move its pin forward and run its suite and the two-device
drill there (`architecture.md` §4, rev 15).

## Format checks

CI fails on any of these, so run them before pushing:

```bash
cd Packages/PassFortKit && swift format lint --strict --recursive Sources Tests
git ls-files '*.cpp' '*.hpp' | grep -v '/vendor/' | xargs -n1 clang-format --dry-run -Werror
shellcheck scripts/*.sh
```

Run clang-format one file at a time, as above. Version 23.1.0 fails on a long argument list with
"File name too long" before checking anything, so a batched run that passes proves nothing.

## Generated and vendored files

These are run by hand and their output is committed. CI never regenerates them; it only checks
that the committed output still matches its inputs.

```bash
scripts/build_botan.sh macos-arm64        # regenerate one target's minimized Botan 3.13.0 amalgamation
scripts/build_botan.sh linux-x86_64       # (ADR-0001); each lands in vendor/botan/<target>/
swift scripts/gen_palette.swift           # UI/tokens.json -> PaletteTokens.swift + AccentColor
swift scripts/make_icon.swift PassFort/Assets.xcassets/AppIcon.appiconset
swift scripts/make_readme_art.swift       # UI/tokens.json -> docs/images/hero-{light,dark}.svg
```

Upgrading the Botan pin is its own reviewable commit, because the version is recorded in the vault
header, and it regenerates both targets. After regenerating, rebuild both `swift build` and a clean
`cmake --build`. Colour changes start in `UI/tokens.json`; see [`UI/README.md`](../UI/README.md).

## Never commit

Any `*.pfvault` / `*.sqlite` holding real data (the migration
fixture under `Tests/` is synthetic by rule), `.build/`, `DerivedData/`, `Build/`. `.gitignore` covers
all of them. Secrets are scanned by gitleaks in CI only, after a push, so check each diff yourself.
