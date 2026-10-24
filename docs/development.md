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
| Before a commit | everything above that the change touches, plus the format checks |

## Swift package

```bash
cd Packages/PassFortKit && swift build      # all targets, including the C++ core
cd Packages/PassFortKit && swift test       # PFCryptoBoundaryTests + PassFortVaultTests
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

Run it from `Packages/PassFortKit/` with `swift run passfort-cli <subcommand>`, or use the built
binary at `.build/debug/passfort-cli`. `init` prompts for a new master password. Every other command
prompts for the password and runs the manifest-MAC and anti-rollback checks (`architecture.md` §5.5)
before doing anything else.

```bash
# No vault needed
passfort-cli seam                                           # the Swift↔C++ round trip, end to end
passfort-cli bench    [--target-ms 500]                     # calibrate Argon2id; print params + timing
passfort-cli gen      [--length 20] [--words N] [-c N]      # passwords or passphrases to stdout

# Vault lifecycle
passfort-cli init     <vault> [--recovery] [--force]        # create a vault
passfort-cli unlock   <vault>                               # open + verify; report account counts
passfort-cli verify   <vault> [--accept-restore]            # manifest + anti-rollback check only
passfort-cli passwd   <vault> [--no-recovery-key]           # change the master password
passfort-cli recover  <vault> --key <grouped-recovery-key>  # reset the master password

# Accounts
passfort-cli add      <vault> --title T [--username U] [--prompt-password] [--url U] [--note N] [--totp URI]
passfort-cli list     <vault> [--search Q] [--all]          # summary index, no secrets
passfort-cli get      <vault> <id|title> [--json]           # one account, secrets to stdout
passfort-cli code     <vault> <id|title>                    # the account's current one-time code
passfort-cli history  <vault> <id|title> [--passwords]      # the account's version timeline
passfort-cli edit     <vault> <id|title> --set password=… [--add-url U] [--prompt-password]
passfort-cli rm       <vault> <id|title>                    # tombstone
passfort-cli undelete <vault> <id|title>                    # bring a tombstoned account back
passfort-cli audit    <vault>                               # weak, reused, old, expiring, http://

# Moving data in and out
passfort-cli import       <vault> <export.txt> [--dry-run]  # Password Safe plain-text export
passfort-cli import-vault <vault> <source> [--only T] [--dry-run]   # accounts from another vault
passfort-cli backup   <vault> <folder> [--keep N]           # consistent snapshot, no password needed
passfort-cli restore  <backup> <vault> [--yes]              # current vault is moved aside, not deleted
passfort-cli dump     <vault>                               # every record, decrypted, as JSON (debug)
passfort-cli export   <vault> -o out.json                   # whole vault decrypted; typed phrase required
```

`passfort-cli <subcommand> --help` lists every option. An account reference is a record UUID or a
title (an exact match, otherwise a unique substring). `get`, `history --passwords`, `dump` and
`export` write secrets in the clear. `export` writes its file with mode `0600`; delete it when you're
done.

After a `restore`, the next unlock reports a rollback on purpose, because the vault really did go
back in time. Confirm that the restore was deliberate with `verify <vault> --accept-restore`.

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
scripts/build_botan.sh                    # regenerate the minimized Botan 3.13.0 amalgamation (ADR-0001)
swift scripts/gen_palette.swift           # UI/tokens.json -> PaletteTokens.swift + AccentColor
swift scripts/make_icon.swift PassFort/Assets.xcassets/AppIcon.appiconset
swift scripts/make_readme_art.swift       # UI/tokens.json -> docs/images/hero-{light,dark}.svg
```

Upgrading the Botan pin is its own reviewable commit, because the version is recorded in the vault
header. After regenerating the amalgamation, rebuild both `swift build` and a clean
`cmake --build`. Colour changes start in `UI/tokens.json`; see [`UI/README.md`](../UI/README.md).

## Never commit

Any `*.pfvault` / `*.sqlite` holding real data (the migration
fixture under `Tests/` is synthetic by rule), `.build/`, `DerivedData/`, `Build/`. `.gitignore` covers
all of them. Secrets are scanned by gitleaks in CI only, after a push, so check each diff yourself.
