# M4 — Platform integration

**Status:** Draft, starts after M3. Follow top to bottom. Two load-bearing decisions are in Phase 0 —
settle them before writing code.
**Prerequisite:** M3 complete — the SwiftUI app does full CRUD against a real vault, the lock-state
machine (`AppModel`) is the spine, auto-lock is idle-timeout + lock-on-background + ⌘L, CI builds the
app unsigned and runs `AppModelTests`. See `m3-gui.md` "Where this leaves you" for the exact list of
what M4 inherits and what M3 deliberately left as a `TODO(M4)`.
**Spec:** `architecture.md` §12 (M4 row), §3.2 (A5 — another local app; the hardened-runtime note in
§3.3), §3.4 (accepted limitations — M4 adds one), §5.5 + the §7.4 `vault_version` row + line 338 (the
high-water mark belongs in the Keychain), §13.3 (release pipeline) and §13.4 (M4: `release.yml` gains
the notarization dry-run). ADR-0007 line 82 is why M4 does **not** add a vault-header slot.

---

## What M4 delivers

`architecture.md` §12: *"Keychain + Touch ID unlock; hardened runtime; entitlements; concealed
pasteboard; lock on sleep. Done when the release build passes a notarization dry-run."*

M4 is the milestone where the app stops being a Swift program that happens to run on macOS and starts
being a macOS app: it uses the Keychain as its secure sidecar store, the Secure Enclave / Touch ID as
an unlock path, the concealed-pasteboard convention, the sleep/lock notifications, and the hardened
runtime + notarization toolchain. **No cryptography changes. No vault-format change. No seam change.**
Every new line is either app-target Swift talking to a platform framework, one small injectable seam
in `PassFortVault`, or CI/release YAML.

```
PassFort/
├── Platform/                         NEW — the platform-framework code, one folder
│   ├── Keychain.swift                Phase 2   generic-password wrapper (Security.framework)
│   ├── KeychainHighWaterMark.swift   Phase 3   conforms to PassFortVault.HighWaterMarkStore
│   ├── DeviceIdentity.swift          Phase 4   a persistent per-device UUID (Keychain-backed)
│   └── BiometricUnlock.swift         Phase 5   LocalAuthentication + the password Keychain item
├── Model/
│   ├── AppModel.swift                Phase 5   +unlockWithBiometrics, +enable/disableBiometrics; Phase 7 sync close
│   ├── VaultService.swift            Phase 5   +unlock(usingBiometrics:), device id from DeviceIdentity
│   └── AutoLock.swift                Phase 6   +sleep / screen-lock observers
├── Features/
│   ├── Unlock/UnlockView.swift       Phase 5   "Unlock with Touch ID" button when the item exists
│   └── Settings/SettingsView.swift   Phase 5   Touch ID enable/disable toggle
├── Support/Pasteboard.swift          Phase 4   concealed type + a reliable expiry
└── PassFort.entitlements             Phase 1   only if the audit finds we need a non-default key

Packages/PassFortKit/Sources/PassFortVault/
└── HighWaterMark.swift               Phase 3   extract HighWaterMarkStore protocol; FileHighWaterMark keeps today's behaviour

.github/workflows/
└── release.yml                       Phase 8   NEW — tag-triggered; Release build → hardened runtime → sign → notarize (dry-run)
```

### What is **not** in M4 (do not build it here)

| Deferred to | What |
|---|---|
| **M5** | any sync UI or client, the real use of the device id, blind indexes, `com.apple.security.network.client` |
| **M7** | the *real* notarized release: `stapler staple` + a signed `.app` attached to a GitHub Release, the nightly long-run fuzz job |
| **format v2** | a biometric-unlock **header slot**. ADR-0007 (line 82) already ruled that a third slot is a real `format_version = 2` with a real re-seal migration — correct only once the format has shipped. M4 keeps biometric material in the Keychain instead (Phase 0, ADR-0008). |
| **"Last used" sidecar** | still deferred (`m3-gui.md` Phase 10, open decision 11). If a recent/frequent sort is ever added it now has a natural home — the Keychain/`UserDefaults` sidecar pattern this milestone establishes — but nothing in M4 needs it. |

### The M4 rule: platform code stays in `PassFort/Platform/`, behind a protocol where the package needs it

The app target is the only place that imports `Security`, `LocalAuthentication`, or `AppKit`
pasteboard APIs. The one place `PassFortVault` has to change is the high-water-mark store, and that is
a *protocol extraction* (Phase 3) — the package defines `HighWaterMarkStore`, the app conforms a
Keychain-backed type to it, exactly as `FaultHook` is already an injected seam. `passfort-cli` keeps
the file sidecar. If you find another genuine gap, close it in the package **with a test in
`PassFortVaultTests`**, in its own commit, and note it as a deviation from this runbook.

---

## Phase 0 — Two decisions, then calibrate expectations

### 0.1 Decision: where biometric-unlock material lives → **ADR-0008**

"Touch ID unlock" needs *something* persisted that Touch ID releases and that reconstructs a vault
session. Two shapes:

| | **A — password in the biometric Keychain** (recommended) | **B — a biometric header slot** |
|---|---|---|
| What's stored | the master-password bytes, as a generic-password item gated by `SecAccessControl([.biometryCurrentSet])`, `…WhenPasscodeSetThisDeviceOnly` (never synced) | a random 256-bit `bio_unlock_key` in the Keychain; `slot[2]` in the §5.3 header wraps the DEK under `HKDF(bio_unlock_key)` |
| Crypto/seam | none — Touch ID returns the password, existing `Vault.unlock(password:)` runs | new `pf_biometric_wrap` / `pf_biometric_open`, `slot_count = 3`, C++ header codec change |
| Format | unchanged | **`format_version = 2` + the first real re-seal migration** (ADR-0007 line 82 says so explicitly), plus a v2 fixture vault opened by every later build |
| Cost if the Keychain ACL is ever bypassed (an out-of-scope adversary, §3.3) | the master password leaks | one device's `bio_unlock_key` leaks; rotate by toggling Touch ID off/on |
| New `§3.4` limitation | yes — "with Touch ID on, the master password is persisted, biometric-gated, on this device" | smaller — a device-local wrapping key, not the password |

**Recommendation: A.** B has the cleaner key story, but it spends M4 — a *platform-integration*
milestone — on a vault-format break and the project's first re-seal migration, which is milestone-sized
work in its own right and belongs with a format-v2 bump that has another reason to exist. A is ~1 file
of `LocalAuthentication` + `Security` code, no ADR-worthy format risk, and it is exactly how a locked
(not signed-out) vault is reopened in the mainstream password managers. The honest cost is one new
bullet in §3.4; write it.

**Deliverable:** `docs/adr/0008-biometric-unlock-keychain.md`, status Accepted, following the template
in `docs/adr/README.md`. Sketch:

> **Context.** §12 M4 requires Touch ID unlock. Mechanically that needs a persisted secret Touch ID
> can release. A header slot (option B) is a `format_version = 2` change with a re-seal migration
> (ADR-0007 line 82); nothing else in M4 or M5 forces a v2 bump.
> **Decision.** Biometric unlock stores the **master-password bytes** in a biometric-gated,
> passcode-required, non-syncable generic-password Keychain item (`kSecAttrService =
> "app.passfort.biometric-unlock"`, `kSecAttrAccount = <vault_uuid>`, `SecAccessControl` flags
> `[.biometryCurrentSet]`, accessible `WhenPasscodeSetThisDeviceOnly`). Touch ID gates retrieval; the
> existing `Vault.unlock(password:)` path is unchanged. Enabling requires a *successful password
> unlock* first (you can only cache a password you just proved). `rewrap` updates the item; disabling,
> a failed manifest check, or `.biometryCurrentSet` invalidation deletes it.
> **Consequences.** New §3.4 limitation: with Touch ID enabled the master password is persisted on the
> device, ACL-gated, never synced. No format change, no seam change, no migration. A future
> `format_version = 2` may revisit option B; this ADR is not a barrier to that.
> **Alternatives considered.** Option B (rejected for M4 — format break + first re-seal migration for
> a platform milestone); `.userPresence` instead of `.biometryCurrentSet` (rejected as the default —
> passcode fallback weakens a password-manager unlock; offer it as an opt-in later if the UX bites);
> storing a derived key instead of the password (rejected — `Vault.unlock` takes a password; caching a
> key needs a new seam entry for no security gain over an ACL-gated password).

### 0.2 Decision: the Apple Developer Program dependency

M4's exit criterion is *"the release build passes a notarization dry-run"*, and real notarization
(`xcrun notarytool submit`) needs:

- an **Apple Developer Program** membership (the paid one) → a **Developer ID Application** certificate;
- an **App Store Connect API key** (issuer id, key id, `.p8`) as three GitHub Actions secrets (§13.3);
- `DEVELOPMENT_TEAM` set on the `PassFort` target (it is currently unset — `CODE_SIGN_STYLE =
  Automatic`, no team).

§10 / ADR-0005 deliberately dropped the Apple Developer Program dependency *for sync*. It does **not**
drop it for distribution — a notarized macOS app needs Developer ID either way, and that is the M7
"real release" bar.

**Pick one and record it in `architecture.md` §14 (open decision 16 is the CI-runner one; add a new
entry):**

- **0.2-real** — you have / will get the membership now. Phase 8 runs `notarytool submit --wait`
  against Apple for real (no `--staple`, no Release attachment — that is M7). A submission that is
  rejected fails the job. This fully meets the §13.4 M4 line.
- **0.2-local** (fallback) — no membership yet. Phase 8 does everything short of Apple: Release build
  with hardened runtime, **ad-hoc** sign (`CODE_SIGN_IDENTITY = "-"`), then assert the hardened-runtime
  flag is set, `get-task-allow` is absent, `codesign --verify --strict --deep` passes, and the
  effective entitlements match a checked-in `PassFort.entitlements.expected`. The `notarytool` step is
  wired but `if:`-gated on the secrets existing, so it lights up automatically when 0.2-real lands.
  Mark the milestone "M4 (local dry-run); notarization completes at M7".

Everything else in M4 is independent of this choice — do Phases 1–7 first; Phase 8 is where it bites.

### 0.3 Calibrate

- **The app is already sandboxed** (`ENABLE_APP_SANDBOX = YES`, both configs). Keychain access from a
  sandboxed app to *its own* default access group (`$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`)
  needs **no `keychain-access-groups` entitlement** — you only declare that to *share* items between
  apps, which we don't. LocalAuthentication needs no entitlement. So the Phase 1 audit may well
  conclude "no `.entitlements` file needed" — that is a fine outcome, not a missing step.
- **`MACOSX_DEPLOYMENT_TARGET` is `26.5`** in the project today (the CI `swift` job pins `macos-26` for
  exactly this reason), not the `14` the M3 runbook sketched. Touch ID / `LAContext` and the concealed
  pasteboard type are both old API — no deployment-target pressure from M4.
- **`deinit` timing.** M3 accepted that `lock()` drops `VaultRepository` → `VaultSession.deinit` →
  `pf_session_close` "eventually". Phase 7 makes that teardown synchronous (`m3-gui.md` Phase 2 note:
  "M4 adds an explicit `await session.close()` on lock").

**Checkpoint:** none — this is reading and two decisions. Move on with ADR-0008 written and 0.2 chosen.

---

## Phase 1 — Hardened runtime + the entitlements audit

Small, and it unblocks nothing else, but do it first so every later Release build in the milestone is
already hardened.

### 1.1 Turn on the hardened runtime (Release)

**Xcode → PassFort target → Signing & Capabilities → + Capability → Hardened Runtime.** That sets
`ENABLE_HARDENED_RUNTIME = YES`. Leave every Hardened Runtime *exception* checkbox **off** — we need
none of them:

| Exception | Need it? |
|---|---|
| Allow JIT / unsigned executable memory / DYLD env vars | No — no JIT, no plugins, no injected dylibs |
| Disable library validation | No |
| Allow execution of JIT-compiled code | No |
| Audio input / camera / location / etc. | No |

Keep it on Release only if you can (`ENABLE_HARDENED_RUNTIME[config=Release] = YES`); Debug can stay
unhardened so the debugger attaches without ceremony. The CI unsigned build (`CODE_SIGNING_ALLOWED=NO`)
is unaffected.

### 1.2 Confirm `get-task-allow` is not in the Release entitlements

§3.3 / §13.3: the Release build must not carry `com.apple.security.get-task-allow` (it is what lets a
debugger attach; Xcode adds it to Debug automatically). Automatic signing already handles this — verify
it after a Release build in Phase 8 with:

```bash
codesign -d --entitlements :- "$APP" | grep -c get-task-allow   # must print 0 for Release
```

### 1.3 The sandbox entitlement audit

Enumerate what the app actually does against the `com.apple.security.*` keys:

| Capability | M4 need | Entitlement |
|---|---|---|
| App sandbox | already on | `com.apple.security.app-sandbox` (build-setting-generated) |
| Read/write the vault in the app container | yes, default | none beyond sandbox |
| Keychain (own access group) | yes (Phases 2–5) | **none** (§0.3) |
| Touch ID via `LAContext` | yes (Phase 5) | none |
| Network | **no** (M5) | — `com.apple.security.network.client` is an M5 line, note it |
| User-selected file (plaintext export target) | the M2 export writes a path the user picks | if the export UI uses `NSOpenPanel`/`.fileExporter`, add `com.apple.security.files.user-selected.read-write`. Check whether M3 shipped an export UI — if it did not, this is M-later. |

If the audit turns up exactly one key (the user-selected-file one, and only if an export UI exists),
add a `PassFort/PassFort.entitlements` with that key plus `com.apple.security.app-sandbox = YES` and
point `CODE_SIGN_ENTITLEMENTS` at it. Otherwise **add no file** and let the build settings generate
the sandbox entitlement.

Also drop `PassFort/PassFort.entitlements.expected` — a copy of the *effective* Release entitlements
(`codesign -d --entitlements`) — for Phase 8's diff check. If there is no `.entitlements` file, the
"expected" is the two-line sandbox-only set that automatic signing produces.

**Checkpoint:** `xcodebuild -scheme PassFort -configuration Release -destination 'platform=macOS'
CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build` succeeds; `codesign -d --entitlements :- "$APP"`
shows sandbox on, `get-task-allow` absent, and nothing you did not deliberately add. CI's existing
unsigned build still passes.

---

## Phase 2 — The `Keychain` helper

One small file, `PassFort/Platform/Keychain.swift`. Everything Keychain in M4 goes through it — the
high-water mark (Phase 3), the device id (Phase 4), the biometric password (Phase 5).

```swift
import Foundation
import Security
import LocalAuthentication   // for the AC-gated variant

/// A thin wrapper over `kSecClassGenericPassword` in the app's own (default) access group.
/// Every item is `…ThisDeviceOnly` — nothing PassFort puts in the Keychain is ever iCloud-synced.
enum Keychain {
  enum Failure: Error, Equatable { case status(OSStatus), unexpectedData, userCancelled, biometryUnavailable }

  /// Plain item — no user-presence gate. For the anti-rollback mark and the device id.
  static func set(_ data: Data, service: String, account: String) throws { … }
  static func get(service: String, account: String) throws -> Data? { … }
  static func delete(service: String, account: String) throws { … }

  /// Biometry-gated item. `set` needs the device unlocked; `get` triggers the Touch ID
  /// prompt (or throws `.userCancelled`). Used only for the master-password item (Phase 5).
  static func setBiometryGated(_ data: Data, service: String, account: String) throws { … }
  static func getBiometryGated(service: String, account: String,
                               prompt: String, context: LAContext = LAContext()) throws -> Data? { … }
}
```

**Shape notes that matter:**

- **`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`** for every item. `ThisDeviceOnly` keeps it off
  iCloud Keychain (a synced master password would defeat the point). `WhenPasscodeSet` means the item
  ceases to exist if the user removes their device passcode — acceptable; a Mac with no passcode has
  no Secure Enclave gate to offer anyway.
- **The AC-gated variant** builds its access control with
  `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
  .biometryCurrentSet, &error)`. `.biometryCurrentSet` (not `.biometryAny`) so enrolling a new
  fingerprint invalidates the cached password — that is the point.
- **`set` is upsert:** `SecItemCopyMatching` → `SecItemUpdate` or `SecItemAdd`. Don't leak
  `errSecDuplicateItem`.
- **Map `errSecUserCanceled` / `-128`** to `.userCancelled` so the Unlock view can tell "user backed
  out of Touch ID" from "Touch ID failed".
- **No logging of values.** §13.1: no secret in a log. This file logs `OSStatus` codes and nothing
  else.
- Sandboxed-app caveat: the *first* `SecItemAdd` for a given service may surface a one-time system
  prompt ("PassFort wants to use the … keychain") depending on macOS version — expected, benign,
  once.

**Checkpoint:** a throwaway test (or a debug menu item) round-trips `Data` through `set`/`get`/`delete`
for the plain variant; `getBiometryGated` shows the Touch ID sheet and returns the bytes on a good
scan, `.userCancelled` on cancel.

---

## Phase 3 — The anti-rollback high-water mark, in the Keychain

§5.5 and the §7.4 `vault_version` row both say the native app caches the high-water mark **in the
Keychain**; §3.4 contrasts that with the web client, which can only use wipeable browser storage. M2
shipped it as a `0600` sidecar file (`<db>.hw`) with a `// M4 moves this to the Keychain` note already
in `HighWaterMark.swift`. This is that move.

### 3.1 Extract `HighWaterMarkStore` in `PassFortVault` (own commit, in `Packages/PassFortKit`)

```swift
// HighWaterMark.swift
public protocol HighWaterMarkStore: Sendable {
  func read() throws -> UInt64
  func write(_ version: UInt64) throws
  func reset() throws
}

/// Today's behaviour, unchanged — the `<db>.hw` 0600 sidecar. Renamed from `HighWaterMark`.
/// Still the default for `passfort-cli` and every `PassFortVaultTests` case.
public struct FileHighWaterMark: HighWaterMarkStore {
  public init(sidecarFor databasePath: String) { … }
  public init(url: URL) { … }               // kept — the tests use it
  …
}
```

`Vault.unlock` / `.create` / `.createWithRecovery` / `.recover` gain a
`highWater: HighWaterMarkStore = FileHighWaterMark(sidecarFor: databasePath)` parameter — same default
behaviour, now overridable. `VaultRepository.open` / `.bootstrap` already take the value; widen their
type from the concrete struct to the protocol.

Update the four call sites and the CLI (no behaviour change — it passes nothing, gets the file store).
Tests: the existing anti-rollback suite (`VaultRepositoryTests`, `VaultManifestTests`,
`MidWriteKillTests`, `AccountHistoryTests`) keeps passing with `FileHighWaterMark`; add one
`InMemoryHighWaterMark` test double in `PassFortVaultTests` and a test that `Vault.unlock` honours an
injected store (mark ahead → repaired forward; mark behind → `rollbackDetected`).

Commit: `PassFortVault: HighWaterMarkStore protocol for the M4 Keychain backing`.

### 3.2 `KeychainHighWaterMark` in the app

```swift
// PassFort/Platform/KeychainHighWaterMark.swift
import PassFortVault

struct KeychainHighWaterMark: HighWaterMarkStore {
  let vaultUUID: UUID
  private var service: String { "app.passfort.rollback-guard" }
  private var account: String { vaultUUID.uuidString }

  func read() throws -> UInt64 {
    guard let d = try Keychain.get(service: service, account: account), d.count == 8 else { return 0 }
    return d.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }
  func write(_ v: UInt64) throws {
    var be = v.bigEndian
    try Keychain.set(withUnsafeBytes(of: &be) { Data($0) }, service: service, account: account)
  }
  func reset() throws { try Keychain.delete(service: service, account: account) }
}
```

Keyed on `vault_uuid` (the plaintext §5.3 field — `pf_session_vault_uuid` / `session.vaultUUID`), not
the file path, so it survives the app container moving and is ready for M5's multi-vault world.

### 3.3 One-time migration from the sidecar

`VaultService.unlock` path, before the first `Vault.unlock` with the Keychain store: if the Keychain
item is absent **and** a `<db>.hw` sidecar exists, read the sidecar value, `write` it to the Keychain,
then delete the sidecar. Idempotent, runs at most once per vault. A fresh M4 install with no prior
sidecar just starts at 0, which is correct for a vault the app has never opened. Log the migration at
`info` (the *fact*, not the value).

`AppModel.acceptRestoreAndRetry` → `service.acceptRestoredBackup()` now calls
`KeychainHighWaterMark(...).reset()` instead of `HighWaterMark(sidecarFor:).reset()`.

**Checkpoint:** unlock an existing app vault → the `.hw` sidecar disappears and the same value is in
the Keychain (`security find-generic-password -s app.passfort.rollback-guard`); a normal edit bumps it;
`security delete-generic-password` behind the app's back then relaunch → the rollback banner appears
(the mark went backwards to 0); the "backup I restored" button clears it. `AppModelTests`'
`aRolledBackVaultOffersRestoreThenUnlocks` is retargeted to the Keychain store (or parameterised over
both).

---

## Phase 4 — Persistent device identity

Small, and M5 is the real consumer, but it is platform-integration-shaped and the Keychain helper is
right here. `VaultService.deviceID` is a zero UUID today with a `// M4/M5 issue a real one` note.

```swift
// PassFort/Platform/DeviceIdentity.swift
enum DeviceIdentity {
  /// A stable per-install UUID. Created once, kept in the Keychain (survives app-container
  /// reset and "delete app, reinstall" only if the user keeps the Keychain — acceptable;
  /// M5 registers it server-side on first sync anyway).
  static func current() -> UUID {
    let service = "app.passfort.device-id", account = "default"
    if let d = try? Keychain.get(service: service, account: account),
       let s = String(data: d, encoding: .utf8), let u = UUID(uuidString: s) { return u }
    let u = UUID()
    try? Keychain.set(Data(u.uuidString.utf8), service: service, account: account)
    return u
  }
}
```

`VaultService` swaps `static let deviceID = UUID(uuid: (0,0,...))` for `let deviceID =
DeviceIdentity.current()`. Nothing in the sealed data or the manifest depends on the device id yet
(M2 `SealedRecord` uses it only as an HLC actor tag), so this is a no-op for correctness in M4 — but
it means M5 does not open on a zero id. Note it as "wired, not yet meaningful" in the phase.

**Checkpoint:** two launches return the same UUID; it is non-zero; `AppModelTests` still green (they
construct `AppModel` with an explicit test path — make sure they don't now pick up a real device id in
a way that matters; they shouldn't).

---

## Phase 5 — Touch ID unlock (ADR-0008 lands here)

The milestone's headline feature. Depends on Phase 0.1 / ADR-0008 and the Phase 2 helper.

### 5.1 `BiometricUnlock` — the policy + the item

```swift
// PassFort/Platform/BiometricUnlock.swift
import LocalAuthentication
import PassFortVault   // nothing crypto — just for the vault UUID type flow

struct BiometricUnlock {
  let vaultUUID: UUID
  private var service: String { "app.passfort.biometric-unlock" }
  private var account: String { vaultUUID.uuidString }

  /// Is Touch ID even available on this Mac (hardware + enrolled)?
  static var isAvailable: Bool {
    var e: NSError?
    return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
  }

  /// Has the user turned it on for this vault (is there an item)?
  var isEnabled: Bool { (try? Keychain.get(service: service, account: account)) != nil
      /* note: get on a biometry item throws without a prompt for existence checks —
         use a `SecItemCopyMatching` with `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`
         so "does it exist" never shows a sheet */ }

  /// Called only right after a successful password unlock.
  func enable(password: Data) throws {
    try Keychain.setBiometryGated(password, service: service, account: account)
  }

  func disable() { try? Keychain.delete(service: service, account: account) }

  /// Shows the Touch ID sheet; returns the stored password bytes or throws.
  func retrievePassword(reason: String = "Unlock your PassFort vault") throws -> Data {
    let ctx = LAContext()
    ctx.localizedFallbackTitle = ""       // no "Enter Password" fallback to the login password
    guard let d = try Keychain.getBiometryGated(service: service, account: account,
                                                prompt: reason, context: ctx)
    else { throw Keychain.Failure.unexpectedData }
    return d
  }
}
```

- **`.biometryCurrentSet` invalidation is silent** — a changed fingerprint set makes
  `retrievePassword` throw `errSecAuthFailed`. Treat any failure here as "biometric unlock is gone":
  fall back to the password field, and `disable()` the (now-dead) item so the button stops offering
  it.
- **Enable only after a password unlock.** You cannot cache a secret you have not just verified.
  `AppModel` holds the just-used password bytes only across the `enable` call, then drops them.

### 5.2 `VaultService` + `AppModel`

`VaultService` gains:

```swift
func unlock(usingBiometricsFor vaultPath: String) async throws -> VaultRepository {
  // vault UUID: read it cheaply from the header (a read-only open, like Vault.exists),
  // or cache it from the last successful unlock in UserDefaults (non-secret).
  let bio = BiometricUnlock(vaultUUID: try vaultUUID(at: vaultPath))
  let password = try bio.retrievePassword()
  defer { /* password is Data we own — resetBytes best-effort (§3.4) */ }
  return try await unlock(password: password)   // same path as a typed password
}
```

`AppModel` gains `unlockWithBiometrics()` (mirrors `unlock(password:)` — `state = .unlocking`, same
`adoptUnlocked` / error mapping; a `Keychain.Failure.userCancelled` returns quietly to `.locked()`
with no banner), `enableBiometrics(password:)`, `disableBiometrics()`, and a `biometricsEnabled`
published flag the Unlock and Settings views read. On `rewrap` (Settings → rotate/change password, if
that exists) — re-`enable` with the new password so the cached copy doesn't go stale; if that is
awkward, `disable()` on any password change and let the user re-opt-in.

### 5.3 UI

- **`UnlockView`:** when `BiometricUnlock.isAvailable && model.biometricsEnabled`, show a "Unlock with
  Touch ID" button above the password field, and auto-invoke it once on first appearance (a `@State`
  `didAutoPrompt` guard — don't loop if the user cancels). The password field stays as the fallback.
- **`SettingsView`:** a `Toggle("Unlock with Touch ID")`, disabled unless `BiometricUnlock.isAvailable`
  and the vault is currently unlocked (you need the live password to enable). Flipping it on calls
  `model.enableBiometrics` with the password the model still holds from this session — decision point:
  either keep the session password in `AppModel` for the lifetime of `.unlocked` (a longer-lived
  copy — note it in §3.4's existing "unwipeable String/Data" bullet, it doesn't add a *new* category)
  or prompt for the password in the toggle's confirmation sheet. Prompting is cleaner; recommend it.

### 5.4 §3.4 — write the limitation

Add to `architecture.md` §3.4:

> - **With Touch ID unlock enabled, the master password is persisted on the device** in a
>   biometric-gated, passcode-required, non-syncable Keychain item (ADR-0008). Retrieval requires a
>   live biometric match; the item is deleted on disable, on a failed manifest check, or when the
>   enrolled fingerprint set changes. A compromise of the Keychain ACL — an adversary class already
>   out of scope (§3.3) — yields the master password. Users who do not enable it are unaffected.

**Checkpoint:** enable in Settings (password prompt) → relaunch → "Unlock with Touch ID" appears and
auto-prompts → good scan lands `.unlocked`; cancel → password field, no banner; disable → button gone,
`security find-generic-password -s app.passfort.biometric-unlock` finds nothing; enrol/remove a
fingerprint in System Settings → next Touch ID attempt fails gracefully and the item is cleared.

---

## Phase 6 — Lock on sleep and screen lock; synchronous teardown

`m3-gui.md` Phase 8 left `// TODO(M4): also lock on NSWorkspace.willSleepNotification / screen lock` in
`AutoLock.swift`, and the §12 M4 row says "lock on sleep".

### 6.1 The observers

In `AutoLock` (or a sibling `SystemLockObserver` it owns):

```swift
// sleep
NSWorkspace.shared.notificationCenter.addObserver(
  forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.onLock() }

// screen lock / screensaver — DistributedNotificationCenter, names are not in a public header
DistributedNotificationCenter.default().addObserver(
  forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.onLock() }
```

- `com.apple.screenIsLocked` is undocumented-but-stable; if it ever stops arriving the app still locks
  on sleep, on idle timeout, and on background — this is defence in depth, not the only line.
- `willSleepNotification` fires *before* sleep; the lock (drop `repo` → zeroize) completes
  synchronously on the main actor before the machine suspends. Good.
- Balance every `addObserver` with `removeObserver` in `invalidate()` (the Phase 2 pattern — no
  `deinit` touching isolated state).
- Sandbox: both notification centers are available to a sandboxed app; no entitlement.

### 6.2 Make `lock()` zeroize synchronously

`m3-gui.md` Phase 2: *"M4 adds an explicit `await session.close()` on lock so zeroization is
synchronous."* Today `AppModel.lock()` is sync and just nils `repo`, relying on `deinit`.

- Add `func close() async` to `VaultSession` (`PassFortCrypto`) that calls `pf_session_close` and nils
  the handle, guarded so `deinit`'s close is a no-op after it. `VaultRepository` gets a matching
  `func close() async` that calls through.
- `AppModel.lock()` becomes: capture `repo`, nil it and clear `summaries` / `autoLock` immediately (UI
  is locked *now*), then `Task { await repo?.close() }` to force the zeroize rather than wait for ARC.
- The sleep path: since `willSleepNotification` is synchronous-ish, kick the same `Task`; the sensitive
  state (`repo` reference, `summaries`) is already gone before the method returns even if the C++
  close lands a beat later.

**Checkpoint:** `pmset sleepnow` (or close the lid) → on wake the app is on the Unlock screen; ⌃⌘Q
(lock screen) → same; a breakpoint in `VaultSession.close` confirms it runs on `lock()`, and the
`deinit` path confirms it does *not* double-close. `AppModelTests` gains
`lockClosesTheSessionNotJustDropsIt` (assert via a spy or the session's own `isClosed`).

---

## Phase 7 — Concealed pasteboard type + a reliable expiry

`Pasteboard.swift` carries the `// M4` note already. §3.2 A5 (another local app reads our clipboard);
§13.1 web-client row has the parallel "clipboard clears on schedule".

```swift
enum Pasteboard {
  private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  static func copyTransient(_ s: String, clearAfter seconds: Double = 20) {
    let pb = NSPasteboard.general
    pb.clearContents()
    // Set BOTH: .string so paste works everywhere; the concealed type so well-behaved
    // clipboard managers (§ the nspasteboard.org convention) skip persisting it.
    pb.setString(s, forType: .string)
    pb.setString(s, forType: concealed)
    scheduleClear(after: seconds, ownerChangeCount: pb.changeCount)
  }

  static func copy(_ s: String) {          // recovery key: no auto-clear, still concealed
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
    pb.setString(s, forType: concealed)
  }
}
```

**"Reliable" expiry.** The M3 version scheduled a `Task.sleep` that dies if the app is killed. Improve:

- On copy, also stamp `NSPasteboard`'s `changeCount` and persist "clear the pasteboard if changeCount
  is still N" so a relaunch within the window can still honour it — or, simpler and enough at this
  scale, additionally clear on `applicationDidResignActive` / `willSleep` / lock (the secret should
  not outlive the session anyway). Recommend: keep the timed clear **and** clear on lock/sleep/resign.
- Guard the timed clear with the `changeCount` check (already there) so we never wipe something the
  user copied afterwards.

`RecoveryKeyView` already uses `Pasteboard.copy`; it now also gets the concealed type — good, a
recovery key is exactly what a clipboard manager should not archive.

**Checkpoint:** copy a password → paste into a text field works → after 20 s the clipboard is empty
(`pbpaste` prints nothing); copy then copy something else → the something-else survives; copy a
password then lock → clipboard empties immediately; with a clipboard-manager installed (e.g. Maccy),
the password does not appear in its history.

---

## Phase 8 — `release.yml` and the notarization dry-run

§13.3 (the release table) and §13.4 ("**M4** — `release.yml` gains the notarization dry-run; a build
that fails the hardened-runtime or notarization check fails the job"). New workflow, **tag-triggered
only** — nothing in the per-push `ci.yml` holds Apple credentials (§13.2).

```yaml
name: Release
on:
  push:
    tags: ['v*.*.*']            # semver tag, never a branch push (§13.3)
permissions:
  contents: read
jobs:
  macos-app:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: latest-stable }

      - name: Release build, hardened runtime, ad-hoc signed
        run: |
          xcodebuild -project PassFort.xcodeproj -scheme PassFort \
            -configuration Release -destination 'platform=macOS' \
            -derivedDataPath dd \
            CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
            ENABLE_HARDENED_RUNTIME=YES
          echo "APP=$(find dd/Build/Products/Release -name 'PassFort.app' -maxdepth 2)" >> "$GITHUB_ENV"

      - name: Hardened-runtime + entitlements assertions   # always run — the M4 floor
        run: |
          codesign -d -v "$APP" 2>&1 | grep -q 'flags=.*runtime' \
            || { echo '::error::hardened runtime flag missing'; exit 1; }
          test "$(codesign -d --entitlements :- "$APP" 2>/dev/null | grep -c get-task-allow)" = 0 \
            || { echo '::error::get-task-allow present in Release'; exit 1; }
          codesign -d --entitlements :- "$APP" 2>/dev/null > effective.entitlements
          diff <(plutil -convert xml1 -o - PassFort/PassFort.entitlements.expected) \
               <(plutil -convert xml1 -o - effective.entitlements) \
            || { echo '::error::entitlements drifted from PassFort.entitlements.expected'; exit 1; }
          codesign --verify --strict --deep --verbose=2 "$APP"

      - name: Notarization (real submit — dry run, no staple)
        if: ${{ secrets.APPLE_API_KEY_ID != '' }}      # 0.2-local: skipped until the membership lands
        env:
          KEY_ID:   ${{ secrets.APPLE_API_KEY_ID }}
          ISSUER:   ${{ secrets.APPLE_API_ISSUER_ID }}
          KEY_P8:   ${{ secrets.APPLE_API_KEY_P8 }}
        run: |
          echo "$KEY_P8" > key.p8
          # re-sign with the real Developer ID from a job-scoped keychain here (omitted) …
          ditto -c -k --keepParent "$APP" PassFort.zip
          xcrun notarytool submit PassFort.zip \
            --key key.p8 --key-id "$KEY_ID" --issuer "$ISSUER" --wait
          # M4: stop here. M7 adds `xcrun stapler staple "$APP"` + attach to a GitHub Release.
        # secret hygiene: no `set -x`, key.p8 is job-ephemeral, logs are public (§13.2)
```

- **0.2-local:** the `if:` guard means the job is green on the assertions alone until the Apple secrets
  exist. Record the milestone as "M4 dry-run local; notarize at M7" in §14.
- **0.2-real:** add the three secrets, set `DEVELOPMENT_TEAM`, import the Developer ID cert into a
  job-scoped keychain (`security create-keychain` / `import` / `set-key-partition-list`), re-sign
  before `ditto`, and a rejected `notarytool submit` fails the job — meeting the §13.4 line in full.
- **`native` job note (§13.4 M7, not now):** the nightly long-run fuzz stays out of this file.
- Once `ci.yml` *and* this workflow are green, add the CI status badge to `README.md` (§13.3, the
  README convention "earns a badge only when CI actually runs" — CI has run since M1, so the badge is
  arguably overdue; add it now).

**Checkpoint:** push a throwaway tag `v0.0.0-m4-test` → the workflow runs, the assertions pass on a
Release build; delete the tag. 0.2-real: the notarize step reaches "Accepted".

---

## Phase 9 — Tests and CI

New/changed coverage, all runnable via the existing `swift` job plus the app-test step:

| Where | Test | Asserts |
|---|---|---|
| `PassFortVaultTests` | `unlockHonoursAnInjectedHighWaterMarkStore` | mark ahead → repaired; mark behind → `rollbackDetected` — against `InMemoryHighWaterMark` |
| `PassFortVaultTests` | existing anti-rollback suite | unchanged, still on `FileHighWaterMark` |
| `AppModelTests` | `rolledBackVault…` retargeted | drives `KeychainHighWaterMark` (or param'd over both stores) |
| `AppModelTests` | `lockClosesTheSessionNotJustDropsIt` | `lock()` runs `VaultSession.close`; `deinit` then no-ops |
| `AppModelTests` | `biometricUnlockRoundTrip` | `enableBiometrics(pw)` → new `AppModel` → `unlockWithBiometrics()` → `.unlocked`. Needs a `BiometricUnlock` seam that a test can fake — inject a `KeychainProviding` protocol, or gate the test on `BiometricUnlock.isAvailable` and skip in CI (CI macOS runners have no Touch ID). Prefer the injected fake so it runs headless. |
| `AppModelTests` | `disableBiometricsDeletesTheItem` | after `disableBiometrics()`, the fake store is empty |
| — | Keychain helper | a small `KeychainTests` for the plain variant (round-trip, upsert, delete, missing → nil). The biometry variant can't run unattended — exclude it, note why. |

CI wiring: no new job. The `swift` job's "App tests" step already runs `xcodebuild test`; the new
`AppModelTests` cases ride along. Add `release.yml` as Phase 8. Keep the CI comment in `ci.yml`
honest — it currently enumerates the M2 storage suites; add the M4 store-injection line.

**Checkpoint:** `swift test` green over `Packages/PassFortKit`; `xcodebuild test -scheme PassFort` green
locally and in CI; the `release.yml` assertions green on a test tag.

---

## Where this leaves you

- **A macOS app that behaves like one:** hardened runtime, sandbox with no gratuitous exceptions,
  Keychain-backed anti-rollback mark, optional Touch ID unlock, concealed pasteboard, and a lock that
  fires on idle / background / ⌘L / **sleep / screen-lock** and tears the session down synchronously.
- **No crypto, format, or seam change.** The one package change is the `HighWaterMarkStore` protocol
  extraction — an injection seam, like `FaultHook`. `passfort-cli` is untouched and keeps the file
  sidecar.
- **Two decisions recorded:** ADR-0008 (biometric unlock stores the password in the biometric-gated
  Keychain, not a header slot — option B waits for a format-v2 bump); and the Apple Developer Program
  call in §14 (real notarization now, or local dry-run until M7).
- **`architecture.md` edits this milestone:** §3.4 gains the Touch ID limitation bullet; §14 gains the
  notarization-membership decision; the rev line moves. ADR-0008 is added and the `docs/adr/README.md`
  table row with it.
- **`release.yml` exists** and enforces the hardened-runtime / entitlements floor on every tag; the
  notarize step is either live (0.2-real) or one `if:`-guard away from live (0.2-local).
- **Deferred, tracked:** the real stapled+published release and the nightly fuzz job (M7); the device
  id becomes meaningful and `com.apple.security.network.client` gets added (M5); a biometric header
  slot only if a `format_version = 2` ever happens for another reason.
- **Next:** M5 — sync against the Azure backend. Do the Azure spike first (`architecture.md` §15
  step 6): one HTTP Function + Table Storage on Azurite, `passfort-cli` pushing and pulling sealed
  blobs, before the milestone is on the board. Ask for `m5-sync.md` when the spike is done.
