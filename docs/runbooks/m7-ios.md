# M7 — iOS client

**Status:** Sketch, written ahead of the normal cadence (2026-10-21, on request). **M5 is not done** (its
own runbook is still a sketch) and M6 has no runbook yet. Only Phase 0 is safe to act on as written —
and even Phase 0.2 / 0.3 need the M5 sync client to exist before their results mean anything. Everything
past Phase 0 is a plan to *validate against the spikes*, not a set of steps to follow blind. Treat every
"Checkpoint" and command below as provisional until Phase 0 has run and M5 has shipped.

**Prerequisite:** M5 complete — two Macs converge through the deployed Azure backend, a second device
can **join an existing vault** from `GET /api/v1/vaults/{id}/header` alone, conflict copies surface in the
UI, and the `seq` floor + manifest recheck (§10.5) are wired. M7 is a client of that contract as-is.
**M7 does not depend on M6** — the web client and the iPhone client are independent consumers of the
same API, so this milestone can be built before M6 if the phone is the part you want first.

**Spec:** `architecture.md` §12 (the M7 row), §14 decisions 9, 18 and 19 (resolved / re-scoped / added in
rev 11), §4 (`PassFortiOS/` and the `PassFortAppCore` target), §9–§10 (the sync contract this client
speaks unchanged), §10.5 (anti-rollback — the `<db>.hw` sidecar travels to iOS as-is), §3.4 (the iOS
availability limitation), §5.2 (KDF parameters travel in the header — the phone must unlock with the
Mac's), §13.2 / §13.4 (the `ios` CI job). ADR-0008 holds the biometric design Phase 9 may revive.

---

## What M7 delivers

`architecture.md` §12 M7 row: *"iPhone app target sideloaded with a free Personal Team; shared
`PassFortAppCore` (lock-state machine, view models) extracted from the macOS app; join an existing vault
over sync; unlock / list / detail / edit / generator; lock on background + privacy snapshot + Data
Protection; weekly re-sign script. Done when: the iPhone and a Mac converge through Azure; an edit on
either appears on the other after sync; a weekly re-sign keeps the vault and the sync cursor."*

M7 is where PassFort stops being macOS-only. It adds **one new app target** and **one new SwiftPM
target**, and it changes **nothing** below the app layer: no vault-format change, no seam change, no
server or API change. The phone is one more device in the M5 design — it holds the same sealed rows in
the same SQLite schema, speaks the same six endpoints, and runs the same crypto core compiled for
`arm64-apple-ios`.

```
Packages/PassFortKit/
├── Package.swift                         Phase 1   platforms += .iOS(.v17); + PassFortAppCore target
└── Sources/
    ├── PFCrypto/vendor/botan/            Phase 0   builds for iOS as-is, or a second amalgamation (ADR-0001 amendment)
    ├── PassFortAppCore/                  Phase 2   NEW — shared by both apps; no interop flag, no UI framework
    │   ├── AppModel.swift                          the lock-state machine, moved from PassFort/Model/
    │   ├── AppError.swift                          moved
    │   ├── AutoLockPolicy.swift                    idle-timeout / grace rules, split out of AutoLock.swift
    │   └── …                                       whatever else in PassFort/ imports neither AppKit nor SwiftUI
    └── Tests/PassFortAppCoreTests/       Phase 2   AppModelTests move here — now run under `swift test`

PassFort/                                 Phase 2   macOS app: thinner; links PassFortAppCore; behaviour unchanged

PassFortiOS/                              Phase 3   NEW — iOS app target (synchronized group)
├── PassFortiOSApp.swift                  Phase 3
├── Features/{Join,Unlock,VaultList,AccountDetail,AccountForm,PasswordGenerator,Settings}/   Phases 5–6
├── Lifecycle/{ScenePhaseLock,PrivacyCover}.swift                                             Phase 7
├── Support/{Pasteboard,ProvisioningExpiry,VaultPaths}.swift                                  Phases 4, 6, 10
└── Assets.xcassets

scripts/install_ios.sh                    Phase 10  build Release + install over USB/Wi-Fi — the weekly re-sign
.github/workflows/ci.yml                  Phase 11  NEW `ios` job: package tests on the iOS Simulator + unsigned app build
```

### What is **not** in M7 (do not build it here)

| Deferred to | What |
|---|---|
| **M8** | hardening — fuzz, zeroization audit, threat-model review. M8's review now covers the iOS client too. |
| **never on a free account** | push notifications (real-time sync), iCloud, App Store / TestFlight distribution — all need the paid Apple Developer Program (§14.19). |
| **§1.2 non-goal** | an AutoFill credential-provider extension. It is OS credential-provider integration (a non-goal) *and* it needs App Groups to share the vault with the extension, which a Personal Team very likely can't provision. |
| **the Mac stays the owner** | creating a vault, the recovery key, plaintext export, backup / restore, vault location, KDF recalibration. The phone joins a vault; it never creates or recovers one. |
| **not now** | an iPad-specific layout (`NavigationSplitView` will give a usable one for free; it is not tested), background sync (`BGTaskScheduler`), widgets, Watch. |

### The M7 rules

- **Nothing below the app layer changes.** No vault-format change, no new seam function, no API change.
  If the phone needs the server to behave differently, that is an M5 bug — fix it in M5's code and
  tests, not with an iOS special case.
- **`PassFortAppCore` imports no UI framework and has no interop flag.** Foundation + Observation +
  `PassFortVault` + `PassFortCrypto` (through its library-evolution interface, §4 note 2), nothing else.
  An `import AppKit`, `import UIKit` or `import SwiftUI` there is a design error.
- **Platform code lives at the edges.** Pasteboard, lifecycle observers, file-protection setup and
  anything else platform-shaped live in each app target. `#if os(iOS)` inside `PassFortAppCore` or
  `PassFortVault` is a smell; one in the C++ core needs a reason written next to it.
- **The bundle identifier and the signing team are fixed forever** once the phone holds a vault.
  Changing either installs a *different app* with an empty container, and the old one dies at its
  next 7-day expiry.
- **Never hand-edit `project.pbxproj`** (`~/.claude/rules/xcode.md`). The target, its package product
  links and its signing are created in Xcode's UI.
- **No ATS exception, ever** (§9.4) — not even a Debug-only one to reach `func start` on the Mac.
  Develop the phone against a deployed endpoint (Phase 8).
- **Test vault first.** Phases 3–9 run against a throwaway vault on a dev deployment. Joining your real
  vault is the last step of Phase 10, after the re-sign checkpoint has passed.

---

## Phase 0 — Spikes, and the decisions they settle

Three go/no-go questions, each answerable in an hour or two, all before any code lands in the repo.
Same move as M0 and the M5 Azure spike: retire the scary unknowns first.

### 0.1 Free provisioning, on your actual iPhone

In a **scratch project outside this repo**: File → New → Project → iOS App. Signing & Capabilities →
Team: your Personal Team (your Apple ID), automatic signing.

1. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (reboots).
2. Run it from Xcode over USB. On first launch iOS refuses until you trust the developer:
   Settings → General → VPN & Device Management → your Apple ID → Trust.
3. Read the expiry: `security cms -D -i <the built .app>/embedded.mobileprovision | plutil -p - | grep -i expiration`.
   Expect ~7 days out.
4. **Data survives a reinstall:** have the app write a file to Application Support, rebuild and re-run
   from Xcode, confirm the file is still there.
5. **Keychain:** `SecItemAdd` a generic-password item, `SecItemCopyMatching` it back. On iOS every
   install carries a provisioning profile, so the default (app-ID-prefixed) access group should just
   work — the `-34018` that killed the macOS Keychain in M4 should not appear. Re-run after step 4's
   reinstall: is the item still readable?
6. **Pairing over Wi-Fi:** Xcode → Window → Devices and Simulators → "Connect via network". Then
   `xcrun devicectl list devices` from a terminal — note the device identifier for Phase 10.

**Exit:** the app installs and launches; you know the expiry date; data and (ideally) the Keychain item
survive a reinstall; `devicectl` sees the phone. If the Keychain fails, Phase 9 is dead — fine, it is
optional.

### 0.2 `PassFortKit` builds for iOS

On a branch (`ios-spike`), add `.iOS(.v17)` to `platforms` in `Package.swift`, then:

```bash
xcodebuild -list -package-path Packages/PassFortKit      # confirm the scheme names first
xcodebuild -scheme PassFortVault -destination 'generic/platform=iOS' \
           -package-path Packages/PassFortKit build
```

Build the `PassFortVault` product scheme, not the whole-package scheme — `passfort-cli` and
`pf-killtest` are macOS executables and have no business building for iOS.

The risk is **Botan**. `scripts/build_botan.sh` generates the amalgamation with `--os=macos`. Both are
Darwin and the module set is pure crypto, so it may well compile for iOS unchanged. If it doesn't — or
compiles but pulls in an OS feature iOS lacks — the fix is a second amalgamation generated with
`--os=ios`, and *how SwiftPM picks one per platform* is a real design question (two vendored copies,
per-platform `#if TARGET_OS_IPHONE` wrapper translation units, …). That is an **ADR-0001 amendment**;
stop and write it rather than improvising in `Package.swift`.

### 0.3 Argon2id on the phone, at your vault's parameters

The KDF parameters live in the vault header (§5.2) and were calibrated on the Mac — the starting point is
`m = 512 MiB, t = 3, p = 4`. The phone **must** unlock with exactly those. There is no per-device
recalibration without re-wrapping the DEK for every device.

In the scratch app (linking the `ios-spike` package), create a throwaway vault with the **same
parameters as your real one** (read them with `passfort-cli` against a copy, never the real file on the
phone) and time `VaultSession` unlock on the device. Watch Xcode's memory gauge.

**Exit:** unlock in under ~3 s with no jetsam kill. If it is killed: check whether the
`com.apple.developer.kernel.increased-memory-limit` capability is available to a Personal Team; if not,
lowering the vault's `m` is a deliberate security trade made **on the Mac** (a master-password re-wrap
with new parameters, §9.5) and recorded in §14 — never something the phone does on its own.

### 0.4 Decisions to record

- **A new ADR** (the next free number — ADR-0009 is the M5 sync-auth ADR, `m5-sync.md` Phase 0.2): *"iOS client: a second app target sideloaded with a free Personal Team; the
  apps share `PassFortAppCore`, not views."* It records the free-vs-paid call (§14.19) and the shared-core
  shape.
- If 0.2 needed it: the ADR-0001 amendment.
- If 0.3 forced a parameter change: §14 entry + the re-wrap, done on the Mac.

**Checkpoint:** all three spikes pass (or have a recorded workaround); the ADR is written; the
`ios-spike` branch is deleted or rebased into Phase 1.

---

## Phase 1 — `PassFortKit` goes multiplatform

1. `platforms: [.macOS(.v14), .iOS(.v17)]` — iOS 17 for `@Observable` / Observation, which `AppModel`
   already uses.
2. **Audit the package for macOS-only API.** Things to grep for:
   `homeDirectoryForCurrentUser`, `NSHomeDirectory`, `Process`, `F_FULLFSYNC`, `NSWorkspace`, hard-coded
   `~/Library` paths. `F_FULLFSYNC` exists on iOS; `Process` does not.
3. **The mid-write kill test is macOS-only** — it spawns `pf-killtest` as a separate process, which iOS
   can't. Gate that test (not the code under test) with `#if os(macOS)`; the §8.2 invariant it proves is
   platform-independent.
4. Run the package tests on the Simulator:

   ```bash
   xcodebuild test -scheme PassFortKit-Package -package-path Packages/PassFortKit \
                   -destination 'platform=iOS Simulator,name=iPhone 17'
   ```

   Fixture vaults are opened by `#filePath`-relative path (not bundled). The Simulator runs on the Mac's
   filesystem, so this should work — verify it rather than assume it. If the whole-package scheme drags
   the executables in, run the test targets via a test-plan or `-only-testing:` instead.

**Checkpoint:** `swift test` is green on macOS exactly as before; `PassFortVaultTests` and
`PFCryptoBoundaryTests` are green on the iOS Simulator.

---

## Phase 2 — Extract `PassFortAppCore`

The §1.2 rule was *"don't pay for a shared UI layer before there's a second platform."* There is one
now — but the layer worth sharing is the **app logic**, not the views. A shared SwiftUI view layer full
of `#if os(iOS)` is worse than two small view layers over one model.

1. New target in `Package.swift`, plus a library product so both apps can link it:

   ```swift
   .target(name: "PassFortAppCore", dependencies: ["PassFortVault", "PassFortCrypto"]),
   .testTarget(name: "PassFortAppCoreTests", dependencies: ["PassFortAppCore"]),
   ```

2. **Move what is already platform-neutral.** Go file by file through `PassFort/Model/` and
   `PassFort/Support/`: anything that imports neither AppKit nor SwiftUI moves. Expected: `AppModel`,
   `AppError`, and the parts of `VaultService` that don't encode a macOS vault-location policy.
   `AccountCategory+Display` can move if it only maps to strings / SF Symbol names.
3. **Split `AutoLock.swift`.** It imports AppKit today. The *policy* (idle timeout, grace period, what
   counts as activity) moves to `AutoLockPolicy`; the *observers* (`NSWorkspace` sleep / screen-lock
   notifications) stay in `PassFort/`. iOS gets its own observers in Phase 7.
4. **Stays in `PassFort/`:** every view, `Pasteboard`, `AppRelauncher`, `Location/`, `Backup/`,
   `Palette` — macOS-shaped by nature.
5. **Move the tests.** `AppModelTests` move from the Xcode test target to `PassFortAppCoreTests`, which
   means they now run under `swift test` in the fast loop — a win independent of iOS.
6. Link the `PassFortAppCore` product into the macOS target via Xcode → target → General → Frameworks.

This also settles open decision 9: field validation and formatting stay in `PassFortVault` (where the
CLI also sees them); view-model state lives in `PassFortAppCore`.

**Checkpoint:** the macOS app behaves identically — run through unlock / CRUD / auto-lock / lock-on-sleep
by hand; `swift test` includes the moved `AppModelTests` and is green; `scripts/install_app.sh` still
produces a working app.

---

## Phase 3 — The iOS app target

In Xcode (never by editing `project.pbxproj`):

1. File → New → Target → iOS → App. Product name **`PassFortiOS`**, SwiftUI, Swift, no Core Data, no
   tests (logic tests live in the package).
2. **Bundle identifier: choose it once and write it down** — see the M7 rules. Something like
   `<your reverse domain>.passfort.ios`.
3. Folder `PassFortiOS/` as a file-system-synchronized group (`~/.claude/rules/xcode.md`); generated
   Info.plist (`GENERATE_INFOPLIST_FILE`), same as the macOS target.
4. Deployment target iOS 17 (matches `Package.swift`). iPhone only for now (Phase 0 decides nothing
   about iPad; don't promise it).
5. Signing: Automatic, Team = your Personal Team.
6. Frameworks: `PassFortAppCore`, `PassFortVault`, `PassFortCrypto` (the last for
   `VaultSession.calibrate` / `KdfParameters` / `PassFortError`, as on macOS).

**Checkpoint:** a blank `PassFortiOS` runs on your iPhone from Xcode, and from the CLI:

```bash
xcodebuild -scheme PassFortiOS -destination 'generic/platform=iOS Simulator' \
           CODE_SIGNING_ALLOWED=NO build
```

---

## Phase 4 — Where the vault lives on the phone

- **Path:** `Application Support/PassFort/vault.sqlite` (+ `-wal`, `-shm`, and the `<db>.hw` rollback
  sidecar from §10.5). No user-chosen location — that is a macOS feature (`Location/`), not ported.
- **Data Protection: `.complete`** on the `PassFort/` directory before the database is created, so every
  file in it (including WAL and the sidecar) is unreadable while the device is locked. This is safe
  *because* the app locks on background (Phase 7) and never syncs in the background (Phase 8): nothing
  needs the DB while the phone is locked.
- **Device backups:** leave the directory in iCloud / Finder backups. It is ciphertext (A1-equivalent,
  §3.2), and a phone restored from an old backup catches up from the server on its first sync — the
  `seq` floor and the server agree again after one pull.
- **Device identity:** M5's `DeviceIdentity` (`m5-sync.md` A.5) — a per-install `device.json` in
  `Application Support/PassFort/`, outside the vault file. It works unchanged on iOS and survives
  re-signs (Phase 0.1 step 4). Platform string `ios`.

**Checkpoint:** a unit test in the iOS target (or a Debug-only assertion at startup) confirms the
directory's `FileProtectionType` is `.complete`; a fresh install creates the directory with no vault.

---

## Phase 5 — Join an existing vault (first run)

The phone has **no "create vault"** flow. First run is *join*:

1. **Enter the endpoint and vault id.** Paste them, or — nicer — scan a QR code the Mac app shows under
   Settings → "Add a device". The QR holds the endpoint URL and the vault UUID **only**: no token, no
   key, no password. (A QR scanner needs `NSCameraUsageDescription`, nothing a Personal Team lacks. If
   you want it, the Mac-side "Add a device" sheet is a small M5-adjacent addition to `PassFort/`.)
2. **`GET /api/v1/vaults/{id}/header`** → write the header to the fresh local DB.
3. **Master password → `VaultSession` unlock** over that header (Argon2id on the phone, Phase 0.3).
4. **`POST …/session` with `session.authKey()`** — only possible *after* step 3 succeeded.

   This ordering is a security property, and with ADR-0009's DEK-derived auth key (`m5-sync.md` D1) it
   is enforced by construction: `k_auth` is derived from the DEK, so a forged header (wrong KEK → unwrap
   fails) yields no key and nothing is sent. Under the old password-derived design, a forged header with
   cheap KDF parameters could have harvested a cheap offline-cracking target; `kdf_params_sane` only
   bounds parameters from above. If ADR-0009 lands differently, restore the explicit "unwrap first"
   rule here and in M5's join.
5. **Full pull** (`GET …/changes?since=0`, paged) → ingest through the same `SyncEngine` path M5 built —
   one commit per page covering the rows, the manifest re-MAC (§8.2) and `sync_cursor`.
6. Land on the vault list.

M5's `JoinVaultView` on the Mac is the template for this screen and its progress steps.

**As M5 shipped (2026-10-25), checked against this phase:** the order above is what
`VaultJoin.join` does. The header is fetched, it must unwrap, and only then does `k_auth` exist,
so step 4's property holds by construction. The Mac's **Add a Device…** sheet (Settings ▸ Sync)
already exists. Its QR code carries `passfort://join?endpoint=<api root>&vault=<uuid>`
(`SyncInvite`), with nothing secret in it, so the phone only needs a scanner. `SyncInvite` and
`SyncEndpoint`, which parses the address and adds `/api/v1` to a bare host, live in the Mac app
target (`PassFort/Sync/`). Move them into `PassFortAppCore` in Phase 2 rather than copying them.
The Mac starts a join from its first screen or File ▸ Join Synced Vault…, which sets the open
vault aside rather than replacing it. The phone has no vault to set aside, so it needs only the
first-run path.

Recovery stays on the Mac: if the master password is forgotten, the recovery key (§5.6) is used there,
and the phone re-joins afterwards.

**Checkpoint:** a phone with a fresh install joins the dev deployment's test vault and shows exactly the
records the Mac shows; `verify` on the Mac's copy and the phone's manifest agree on the record set.

---

## Phase 6 — The screens

Built on `PassFortAppCore`'s `AppModel`; one SwiftUI file per screen, iOS idioms throughout.

| Screen | Notes |
|---|---|
| **Unlock** | `SecureField`, autocorrect / capitalization off. **No `.textContentType(.password)`** — that invites iOS to offer saving the master password to iCloud Keychain. |
| **List** | `NavigationSplitView` (collapses to a stack on iPhone); categories / favourites as on the Mac's sidebar (`AccountSummary.category`, §7.5); `.searchable` over the in-memory index (§8.3); pull-to-refresh = sync (Phase 8). |
| **Detail** | decrypt on demand (§3.4), reveal / copy password, username, URL; conflict copies badged as on the Mac. |
| **Add / Edit** | the same validation as the Mac via `PassFortVault` (decision 9); writes go through `VaultRepository` unchanged. |
| **Password generator** | a sheet; generator logic shared via `PassFortAppCore` if Phase 2 moved it, else moved now. |
| **Settings** | sync status + last sync, auto-lock grace (Phase 7), lock now, Face ID (Phase 9), signature expiry (Phase 10). No backup, export, vault location or recovery — Mac only. |

**Pasteboard** (`PassFortiOS/Support/Pasteboard.swift`):

```swift
UIPasteboard.general.setItems(
    [[UTType.plainText.identifier: value]],
    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(clearAfter)]
)
```

`.localOnly` keeps a copied password off Universal Clipboard (so it never lands on the Mac);
`.expirationDate` is enforced by the OS — better than the macOS timer-based clear. Use the same
clear interval as the Mac.

**Checkpoint:** full CRUD on the phone against the test vault; an edit made on the phone is visible on
the Mac after a sync, and vice versa.

---

## Phase 7 — Lifecycle and locking

| Event | Action |
|---|---|
| `scenePhase → .inactive` | show `PrivacyCover` over the window so the app-switcher snapshot holds no secrets |
| `scenePhase → .background` | record the time; lock immediately if grace = 0 (the default) |
| back to `.active` | if elapsed > grace → lock; remove the cover |
| `protectedDataWillBecomeUnavailable` (device locking) | lock immediately, regardless of grace |
| idle timeout while active | `AutoLockPolicy` (Phase 2); "activity" = any `AppModel` action — navigation, copy, edit. Not raw touches: tracking every touch needs a `UIWindow` subclass, which isn't worth it. |

Lock means what it means on the Mac: `VaultSession.close()` (zeroizes in C++), drop the in-memory index
and any decrypted `Data`, return to Unlock (§3.4).

**Grace period:** default **0** (lock on every app switch). Typing a long master password after every
trip to Safari is painful — that is what Phase 9 (Face ID) is for, not a reason to default to a long
grace. Offer 0 / 30 s / 1 min in Settings.

Screen recording / screenshots are out of scope (§3.3) — no capture detection.

**Checkpoint:** on a real device: app switcher shows the cover; switching away and back locks (grace 0);
locking the phone with grace set to 1 min still locks; idle timeout locks.

---

## Phase 8 — Sync on the phone

The M5 engine, unchanged; only the **trigger points** are iOS-specific:

- after unlock (and after join);
- on return to `.active` while unlocked;
- after every local write (debounced, as on the Mac);
- pull-to-refresh on the list;
- a periodic pull while active and unlocked (e.g. every 60 s — at personal scale this stays far inside
  the Functions free grant, §10.1).

**Never in the background.** With Data Protection `.complete` and the session closed on background, a
background task could neither read the DB nor seal anything. Offline edits commit locally (§8.2) and
push on the next foreground sync.

**What "the same data all the time" means here:** both devices converge *at each sync* — in practice
seconds after you open the app. Truly live updates would need push notifications, which need the paid
program (§14.19).

**Transport:** M5's `PinnedTransport` (SPKI pinning, §9.4) as-is. The Mac reads its pins from a
bundled `SyncPins.txt`, so the phone target bundles the same file. **Develop against a deployed
endpoint** — a throwaway dev resource group from M5's Bicep (cost ≈ $0, teardown is `az group delete`).
No ATS exception to reach `func start` on the Mac's LAN IP, not even in Debug.

**Checkpoint (the conflict drill):** put the phone in Airplane Mode, edit record X on the phone and on
the Mac, reconnect, sync both → both devices show the winner plus a conflict copy (§9.3), and nothing
was silently lost.

---

## Phase 9 — Face ID (optional)

Only if Phase 0.1 showed the Keychain works under a Personal Team and survives a re-sign.

ADR-0008 holds the design (option A: the master-password bytes in a biometric-gated, passcode-required,
this-device-only generic-password item; Face ID releases them and the normal `unlock(password:)` runs).
ADR-0008 was amended to "not adopted" for macOS, and ADRs are immutable — so adopting it **on iOS
only** is a **new ADR** that cites ADR-0008 for the design and records why iOS differs (every iOS install
carries a provisioning profile, so the entitlement problem that killed it on macOS doesn't exist here).

- `NSFaceIDUsageDescription` in the generated Info.plist (build setting
  `INFOPLIST_KEY_NSFaceIDUsageDescription`).
- `.biometryCurrentSet` — re-enrolling a face invalidates the item; fall back to the master password.
- The master password is always the fallback, and the Settings toggle deletes the item when turned off.

**Checkpoint:** Face ID unlocks; changing the enrolled face forces the master password; turning the
toggle off deletes the item (verify with `SecItemCopyMatching` → `errSecItemNotFound`).

---

## Phase 10 — Living with a 7-day signature

The free Personal Team's profile expires every ~7 days; after that the app won't launch until it is
reinstalled from the Mac. **The data and the sync cursor survive** (Phase 0.1). This phase makes the
re-sign a one-command habit.

### 10.1 `scripts/install_ios.sh`

The iOS sibling of `scripts/install_app.sh`:

```bash
#!/usr/bin/env bash
# Build PassFortiOS (Release) and install it on the paired iPhone -- the weekly
# re-sign for a free Personal Team (architecture.md §14.19, m7-ios.md Phase 10).
set -euo pipefail
: "${PASSFORT_IOS_DEVICE:?set to the identifier from 'xcrun devicectl list devices'}"

xcodebuild -scheme PassFortiOS -configuration Release \
           -destination 'generic/platform=iOS' \
           -derivedDataPath Build/ios -allowProvisioningUpdates -quiet build

xcrun devicectl device install app --device "$PASSFORT_IOS_DEVICE" \
      Build/ios/Build/Products/Release-iphoneos/PassFortiOS.app
```

`-allowProvisioningUpdates` lets `xcodebuild` mint a fresh 7-day profile without opening Xcode. Works
over USB or Wi-Fi once the phone is paired (Phase 0.1 step 6). `shellcheck` it (`lint` job).

### 10.2 Show the expiry in the app

`PassFortiOS/Support/ProvisioningExpiry.swift` reads `embedded.mobileprovision` from the app bundle,
extracts the embedded plist (the bytes between `<?xml` and `</plist>`), and decodes `ExpirationDate`
with `PropertyListSerialization`. Settings shows "Signature expires in N days"; a banner appears on the
list when fewer than 2 days remain. Plus a recurring calendar reminder — belt and braces.

### 10.3 The fallback when it lapses anyway

If the signature lapses away from the Mac, the vault is unreachable *on the phone* until the next
install — an availability problem, never a confidentiality one (§3.4). The Mac app and, once M6
exists, the web client in Safari are the fallbacks.

### 10.4 Join the real vault

Only now — after a re-sign has been proven not to lose data — sign the phone out of the test vault
(delete and reinstall the app) and join the real one.

**Checkpoint:** run `scripts/install_ios.sh` over Wi-Fi with the app holding a synced vault → the app
relaunches with the vault, the sync cursor and (if Phase 9) the Face ID item intact; no re-join needed.
Settings shows a fresh ~7-day expiry.

---

## Phase 11 — Tests, CI, and the doc sweep

### Coverage

| What | Where |
|---|---|
| Lock-state machine, auto-lock policy, grace rules | `PassFortAppCoreTests` — `swift test` (macOS) **and** the iOS Simulator |
| Core crypto + storage on iOS | `PFCryptoBoundaryTests`, `PassFortVaultTests` on the Simulator (Phase 1) |
| Join ordering (unwrap before auth response) | a `SyncEngine` test with a stub server serving a forged cheap-parameter header → `AuthFailed`, **no** `POST /session` issued |
| Data Protection on the vault directory | iOS-target unit test (Phase 4) |
| Lifecycle locking, privacy cover, conflict drill, re-sign survival | by hand on the device — checkpoints of Phases 7, 8, 10 |

### CI (`ci.yml`, new `ios` job, macOS runner)

- package tests on the iOS Simulator (Phase 1 command);
- `PassFortiOS` built for the Simulator, unsigned (`CODE_SIGNING_ALLOWED=NO`).

It is a second macOS job, so it spends the scarce macOS minutes (§14.16). If minutes bind, run it on
pushes that touch `PassFortiOS/`, `Packages/` or `Package.resolved` only.

### Doc sweep (part of the milestone, not a follow-up)

- `architecture.md`: mark the M7 row done; record what Phase 0 actually found (Botan, Argon2 timing,
  Keychain) and close §14.19 if the free account held up; bump the rev line.
- `README.md` Testing section and `CLAUDE.md` Commands: add the Simulator test command and
  `scripts/install_ios.sh`.
- `docs/runbooks/README.md`: M7 status.

**Checkpoint:** the `ios` job is green on `main`; the doc sweep is committed.

---

## Where this leaves you

- **Two native clients, one core.** The iPhone runs the same C++ crypto core, the same
  `PassFortVault` storage and the same sync engine as the Mac; only the views and the platform glue
  differ. The vault format, the seam and the server never noticed.
- **`PassFortAppCore`** exists, holds the app logic both platforms share, and its tests run in the fast
  `swift test` loop.
- **The phone is a joining device, not an owner.** Vault creation, recovery, export and backup stay on
  the Mac.
- **A known, managed availability cost:** the free Personal Team's 7-day signature, handled by
  `scripts/install_ios.sh`, an in-app expiry warning, and the Mac (and later web) client as fallback.
  §14.19 records when paying $99 would be worth it.
- **Deferred, tracked:** AutoFill extension (non-goal + needs the paid program), push-driven live sync,
  background sync, iPad layout, widgets.
- **Next:** M8 — hardening. Its threat-model review now has an iOS section: Data Protection class,
  snapshot privacy, the pasteboard options, the join ordering, and (if adopted) the Face ID item.
