# M3 — GUI

**Status:** Drafted, starts after M2. Follow top to bottom.
**Prerequisite:** M2 complete — `passfort-cli` does full CRUD against a real SQLite vault, the
restore-from-backup drill passes, CI green on `main`. See `cli-guide.md` to exercise that stack by
hand first; the GUI is a second front end onto the exact same `VaultRepository`.
**Spec:** `architecture.md` §12 (M3 row), §3.4 (accepted limitations — the GUI is where most of them
bite), §8.3 (the in-memory index), §13.1 (the locked/unlocking/unlocked/error state machine),
`docs/bootstrap.md` Phase 6 (creating the Xcode project — folded in here as Phase 1).

---

## What M3 delivers

`architecture.md` §12: *"SwiftUI unlock, list, detail, edit; auto-lock; search over the in-memory
index. Done when GUI CRUD works against a real vault."*

A macOS SwiftUI app — the `PassFort/` app target from §4 — that is a **thin shell over
`PassFortVault`**. It adds no capability the CLI doesn't already have; it adds a window, a lock-state
machine, and the in-memory search index made interactive. Every write still goes through
`VaultRepository` and its one-transaction-per-write invariant (§8.2); the app never touches a key,
never opens the database directly, never re-implements anything in `PassFortVault`.

```
PassFort/                             the .xcodeproj's file-system-synchronized group
├── PassFortApp.swift              Phase 2   @main; the scene switches on AppModel.state
├── Model/
│   ├── AppModel.swift             Phase 2   @Observable @MainActor — the lock-state machine
│   ├── AppError.swift             Phase 2   user-facing errors (mirrors CLIError's translation)
│   └── VaultService.swift         Phase 2   the Vault.* seam: device id, error mapping, calibration
├── Features/
│   ├── Unlock/UnlockView.swift    Phase 3   SecureField -> AppModel.unlock
│   ├── CreateVault/…              Phase 4   first run: password ×2, recovery key shown once
│   ├── VaultList/VaultListView.swift   Phase 5   NavigationSplitView + .searchable over summaries
│   ├── AccountDetail/…            Phase 6   decrypt-on-demand; reveal / copy
│   ├── AccountForm/…              Phase 7   add + edit, bound to a draft AccountPayload
│   └── Settings/…                 Phase 8   lock now, auto-lock timeout, rotate recovery key
└── Assets.xcassets, PassFort.entitlements   Phase 1 / M4   (Info.plist is build-generated)

PassFortTests/                     Phase 9   the state-machine tests (drive AppModel, no UI)
```

### What is **not** in M3 (do not build it here)

| Deferred to | What |
|---|---|
| **M4** | Keychain-stored high-water mark and password, Touch ID unlock, hardened runtime + entitlements + notarization, **concealed pasteboard type**, **lock on sleep/screen-lock** |
| **M5** | any sync UI, conflict copies, per-device ids, blind indexes |

M3 auto-lock is **idle timeout + lock on backgrounding + a Lock command** — enough to tear the object
graph down. The OS-integration parts of locking are M4 (§12 M4 row: "lock on sleep").

### The M3 rule: additive in the app target

Prefer to add code in the app target only. If you find a genuine gap in `PassFortVault` — something the
CLI got away with but the GUI can't — close it there **with a test in `PassFortVaultTests`**, in its
own commit, and note it as a deviation from this runbook. The one gap already anticipated is
`Vault.exists(databasePath:)` (Phase 2).

---

## Phase 0 — Calibrate expectations

Two facts to internalise before touching Xcode.

**Creating `PassFort.xcodeproj` is a manual step in Xcode's UI.** There is no supported way to script
it, and hand-editing `project.pbxproj` is forbidden (`~/.claude/rules/xcode.md`: "a bad edit can
corrupt the project"). Phase 1 is a click-through with a verification checkpoint, the same shape as
`bootstrap.md` Phase 0 (toolchain). Everything from Phase 2 on is ordinary Swift you edit in files and
build with `xcodebuild` / `swift build`.

**The app depends on `PassFortVault` *and* `PassFortCrypto`, and that is safe.** `PassFortCrypto` is
built with `-enable-library-evolution` (`Package.swift`), which publishes a textual `.swiftinterface`
its clients compile against **without inheriting `.interoperabilityMode(.Cxx)`** (§4 note 2). So the
app links `PassFortCrypto` for `VaultSession.calibrate` / `KdfParameters` / `PassFortError` — exactly
as `passfort-cli` does — and no C++ type, and no Botan header, ever reaches the app compiler. The §4
layering guarantee is intact: the app target still cannot `import PFCrypto`.

**Checkpoint:** none — this is reading. Move on when you can state why linking `PassFortCrypto` doesn't
make the app an interop target.

---

## Phase 1 — The Xcode app shell

This is `bootstrap.md` Phase 6, executed now. Do it exactly as written there; the notes below are the
M3-specific specifics.

### 1.1 Create the project (Xcode UI)

1. **Xcode → File → New → Project → macOS → App.**
   - Product Name: `PassFort`
   - Interface: **SwiftUI**, Language: **Swift**
   - **Uncheck** "Include Tests" (add a test target separately in Phase 9 so it is a clean commit)
   - Storage: **None** (no Core Data / SwiftData — the vault *is* the store)
2. **Save at the repo root.** Xcode *always* wraps the project in a `PassFort/` container folder
   (`PassFort/PassFort.xcodeproj` + `PassFort/PassFort/` sources) — there is no "don't wrap" option.
   Flatten it while the project is empty (**quit Xcode first**):

   ```bash
   cd <repo root>
   mv PassFort/PassFort.xcodeproj PassFort.xcodeproj    # .xcodeproj -> repo root
   mv PassFort/PassFort src-tmp && rm -rf PassFort && mv src-tmp PassFort   # sources -> repo root
   ```

   The synchronized root group's `path` is `PassFort` (relative to the `.xcodeproj`'s parent), so
   keeping the source folder named `PassFort/` at the repo root means the group resolves as-is —
   **no `pbxproj` edit** (`§4` shows this folder as `PassFort/`, not `App/`). Verify:
   `xcodebuild -list -project PassFort.xcodeproj` shows target/scheme `PassFort`.
3. **Xcode → Settings → Locations → Derived Data → Default.** A non-default setting here dumps a
   `Build/` folder into the repo (`.gitignore` catches it, but Default keeps the tree clean).
4. **Project → PassFort target → General → Frameworks, Libraries, and Embedded Content →
   File → Add Package Dependencies → Add Local…** → select `Packages/PassFortKit`. Add **both**
   `PassFortVault` and `PassFortCrypto` to the `PassFort` app target. (Xcode's picker only lists
   *library products*; `PassFortCrypto` was made a `.library` product for exactly this — the app
   needs it for `VaultSession.calibrate` / `KdfParameters` / `PassFortError` in Phase 2.)
5. **Deployment target: macOS 14** (matches `Package.swift` `platforms: [.macOS(.v14)]`).

### 1.2 `.gitignore` and the commit

`bootstrap.md` Phase 1 already ignores `xcuserdata/` and `*.xcuserstate`; this session also added
`Build/` (project-relative derived data). Confirm, then:

```bash
xcodebuild -list        # confirm the scheme is exactly "PassFort"
xcodebuild -scheme PassFort -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build   # must succeed
```

Commit in one focused change: `Add macOS app shell (M3)` — `PassFort.xcodeproj/` (minus xcuserdata)
and `PassFort/` (`PassFortApp.swift`, `ContentView.swift`, `Assets.xcassets`), nothing else. No
`Info.plist` file — it is build-generated (`GENERATE_INFOPLIST_FILE = YES`).

### 1.3 Wire it into CI

Extend the `swift` job in `.github/workflows/ci.yml` (or add a sibling `app` job — decide with
open decision 16 below):

```yaml
      - name: App builds (unsigned)
        run: xcodebuild -scheme PassFort -destination 'platform=macOS' build
          CODE_SIGNING_ALLOWED=NO
```

`architecture.md` §13.4 M3: "the app compiles in CI (unsigned)". Signing and notarization are M4's
`release.yml`.

> **Open decision 16 (`architecture.md` §14) — decide now.** GitHub-hosted `macos-15` bills at 10× and
> the free tier is finite; `swift` / `native` / the new app build are the only macOS jobs. Lean hosted
> until the monthly minutes actually bind, then a self-hosted runner on the dev Mac. Record the call in
> §14.

**Checkpoint:** `xcodebuild -scheme PassFort -destination 'platform=macOS' build` succeeds from a clean
checkout; the generated empty app launches and shows the default window; the app target
cannot `import PFCrypto` (try it, confirm the compile error, revert). CI is green with the app-build step.

---

## Phase 2 — The lock-state machine — DONE (2026-09-02)

The spine of the app. Everything else hangs off `AppModel.state`.

**Shipped** as `PassFort/Model/{AppError,VaultService,AppModel,AutoLock}.swift` +
`PassFort/RootView.swift`, with `PassFortApp.swift` rewired and `ContentView.swift` deleted. The app
builds (`xcodebuild -scheme PassFort … build`) and runs, showing a placeholder per state; Phases 3–5
replace those. What differs from the sketches below:

- **The project defaults every type to `@MainActor`** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  Xcode 26's "approachable concurrency"). So `VaultService` is marked **`nonisolated struct`** — the
  blocking Argon2id in `calibrate` and the async `Vault.*` calls have to run off the main actor. The
  explicit `@MainActor` on `AppModel` / `AutoLock` is redundant but kept for clarity.
- **`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`** — every file imports the module of every
  member it names. `VaultService`: `Foundation` + `PassFortCrypto` + `PassFortVault`. `AppModel`:
  `Foundation` + `Observation` + `PassFortVault`. `AppError`: none (all stdlib).
- **`AutoLock`** has an explicit `invalidate()` (called by `lock()` and before re-creating it) rather
  than a `deinit` that touches isolated state. Phase 2 = a bare countdown; Phase 8 adds the `NSEvent`
  activity monitor and the Settings interval.
- **`RootView`** is a `switch model.state` with placeholder views. `PassFortApp.swift` owns the
  `AppModel` as `@State`, injects it with `.environment(model)`, and locks on `scenePhase ==
  .background` (the Phase 8 scene line, folded in here).
- The app target is **sandboxed** (template default), so `VaultDatabase.defaultPath` resolves inside
  the app container, not the path the CLI uses — they converge in M5 (sync).

### 2.1 `Model/AppError.swift`

Mirror what `VaultCLI.open` does in the CLI — translate `PassFortError` and `VaultManifest.Failure`
into something a person can read and act on.

```swift
enum AppError: Error, Equatable {
  case wrongPassword                       // PassFortError.authFailed
  case notAVault                           // VaultError.notFound
  case tampered                            // VaultManifest.Failure.macMismatch
  case rolledBack(fileVersion: UInt64, lastSeen: UInt64)   // .rollbackDetected
  case io(String)

  var isRestorableRollback: Bool { if case .rolledBack = self { return true }; return false }
}
```

`rolledBack` carries the versions so the Unlock screen can offer "this was a backup I restored"
(Phase 3) — the GUI equivalent of `verify --accept-restore`.

### 2.2 `Model/VaultService.swift`

The one place the app calls into `PassFortKit`. Keeps the device id, the KDF target, and the error
mapping in a single spot — the app's `VaultCLI`.

```swift
import Foundation        // Data, UUID, Date
import PassFortCrypto     // VaultSession, KdfParameters, PassFortError
import PassFortVault      // Vault, VaultRepository, RecoveryKey, HighWaterMark, VaultError, VaultManifest

struct VaultService {
  /// Single device until M5 sync (matches SealedRecord's M2 constant). M4/M5 issue a real one.
  static let deviceID = UUID(uuid: (0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0))

  let databasePath: String

  func exists() -> Bool { Vault.exists(databasePath: databasePath) }        // Phase 2.3

  /// Blocks ~500 ms on Argon2id calibration -- callers run it off the main actor.
  func calibrate(targetMs: UInt32) throws -> KdfParameters {
    try VaultSession.calibrate(targetMs: targetMs)
  }

  func createVault(password: Data, params: KdfParameters, recovery: Bool) async throws
    -> (repo: VaultRepository, recoveryKey: RecoveryKey?)
  {
    do {
      if recovery {
        let (repo, key) = try await Vault.createWithRecovery(
          databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID)
        return (repo, key)
      } else {
        let repo = try await Vault.create(
          databasePath: databasePath, password: password, params: params, deviceID: Self.deviceID)
        return (repo, nil)
      }
    } catch { throw Self.map(error) }
  }

  func unlock(password: Data) async throws -> VaultRepository {
    do {
      return try await Vault.unlock(
        databasePath: databasePath, password: password, deviceID: Self.deviceID)
    } catch { throw Self.map(error) }
  }

  /// The GUI's `verify --accept-restore`: clear the sidecar mark, then unlock repairs it forward.
  func acceptRestoredBackup() throws {
    try HighWaterMark(sidecarFor: databasePath).reset()
  }

  private static func map(_ error: Error) -> AppError {
    switch error {
    case PassFortError.authFailed: return .wrongPassword
    case VaultError.notFound: return .notAVault
    case VaultManifest.Failure.macMismatch: return .tampered
    case VaultManifest.Failure.rollbackDetected(let v, let hw): return .rolledBack(fileVersion: v, lastSeen: hw)
    default: return .io(String(describing: error))
    }
  }
}
```

### 2.3 `Vault.exists` — the one `PassFortVault` addition — DONE

The app needs "is there a vault here yet?" before it can decide between the Unlock and Create screens.
`Vault.unlock` throwing `.notAVault` works but forces a full open; a cheap check is cleaner.

Shipped as `Vault.exists(databasePath:)` in `Vault.swift`, delegating to
`VaultDatabase.vaultExists(atPath:)` in `Database.swift` (where GRDB already lives). It opens the file
**read-only** — the sketch's `VaultDatabase(path:)` would have run the migrator, creating our three
tables on a non-vault file at that path:

```swift
// Database.swift
public static func vaultExists(atPath path: String) -> Bool {
  guard FileManager.default.fileExists(atPath: path) else { return false }
  var config = Configuration()
  config.readonly = true
  guard let queue = try? DatabaseQueue(path: path, configuration: config) else { return false }
  return (try? queue.read { db in try VaultMeta.read(db, .header) != nil }) ?? false
}
```

`VaultService.exists()` is the one-line wrapper. Tests: `DatabaseTests.vaultExistsIsSideEffectFree`
(missing / bare / migrated-but-headerless → false, and a bare file stays 0 bytes) and
`VaultRecoveryTests.vaultExistsReflectsWhetherAVaultIsThere` (false, then true after `Vault.create`).
Commit: `PassFortVault: Vault.exists for the M3 first-run check`.

### 2.4 `Model/AppModel.swift`

```swift
import Observation
import PassFortVault

@MainActor @Observable
final class AppModel {
  enum State: Equatable {
    case needsVault                         // no vault file -> Create screen
    case locked(AppError? = nil)            // Unlock screen, optionally showing the last failure
    case unlocking                          // Argon2id in flight -> spinner
    case unlocked

    var isUnlocking: Bool { self == .unlocking }
  }

  private(set) var state: State = .locked()
  private(set) var repo: VaultRepository?           // non-nil ONLY in .unlocked
  private(set) var summaries: [AccountSummary] = []

  private let service: VaultService
  private var autoLock: AutoLock?                    // Phase 8

  init(databasePath: String = VaultDatabase.defaultPath) {
    self.service = VaultService(databasePath: databasePath)
    self.state = service.exists() ? .locked() : .needsVault
  }

  func unlock(password: Data) async {
    state = .unlocking
    do {
      let repo = try await service.unlock(password: password)
      try await adoptUnlocked(repo)
    } catch let error as AppError {
      state = .locked(error)
    } catch {
      state = .locked(.io(String(describing: error)))
    }
  }

  func acceptRestoreAndRetry(password: Data) async {
    do { try service.acceptRestoredBackup() } catch { /* surfaced on the retry */ }
    await unlock(password: password)
  }

  func lock() {
    repo = nil                              // -> VaultSession.deinit -> pf_session_close zeroizes
    summaries = []
    autoLock = nil
    state = .locked()
  }

  private func adoptUnlocked(_ repo: VaultRepository) async throws {
    self.repo = repo
    self.summaries = try await repo.summaries()
    self.autoLock = AutoLock { [weak self] in self?.lock() }
    self.state = .unlocked
  }

  func refreshSummaries() async {
    guard let repo else { return }
    summaries = (try? await repo.summaries()) ?? summaries
  }
}
```

**Why it is shaped this way.**

- **`@MainActor @Observable`** — the model is UI state, so it lives on the main actor. `VaultRepository`
  is an `actor`, so every call into it is an `await` that hops off main and back; the ~0.5 s Argon2id
  in `unlock` therefore never blocks the UI, and `state = .unlocking` gives SwiftUI a frame to show a
  spinner before the hop.
- **`repo` is non-nil only in `.unlocked`.** That is the whole security model of the lock: `lock()`
  drops the `VaultRepository`, which drops its `VaultSession`, whose `deinit` calls
  `pf_session_close` and zeroizes the RootKeys / DEK / subkeys. The in-memory index
  (`summaries`, decrypted titles — §3.4) is dropped in the same call. There is no code path where a
  key or a decrypted title outlives `.unlocked`.
- **`deinit` timing is not guaranteed instant** (the `VaultSession` doc comment says so). Acceptable
  for M3. M4 adds an explicit `await session.close()` on lock so zeroization is synchronous.
- **Password is `Data`, not `String`** at this layer — but it arrives from a SwiftUI `SecureField`
  bound to a `String`, which is unwipeable (§3.4). Convert at the last moment
  (`Data(field.utf8)`), don't hold the `String` longer than the view.

**Checkpoint:** unit-drive `AppModel` (Phase 9 territory, but stub it now): a fresh model on a missing
path is `.needsVault`; on an existing vault it is `.locked`; `unlock` with the wrong password lands in
`.locked(.wrongPassword)` with `repo == nil`; `lock()` from `.unlocked` clears `repo` and `summaries`.

---

## Phase 3 — The Unlock screen — DONE (2026-09-02)

Shipped as `PassFort/Features/Unlock/UnlockView.swift`, wired into `RootView` for the `.locked` **and**
`.unlocking` states (it shows its own spinner). Differences from the sketch:

- **The password is cleared on success, not on submit.** `.onChange(of: model.state)` clears it when
  `state == .unlocked`; keeping it on a failure lets the user fix a typo — or the rollback banner
  reuse it — without retyping. The `String` is unwipeable regardless (§3.4).
- **`AppModel.unlock` gained `guard !state.isUnlocking`** — `.keyboardShortcut(.defaultAction)` plus a
  focused `SecureField` can fire twice in one tick; without the guard that's two concurrent Argon2id
  runs racing on `repo`. (`.onSubmit` was dropped; the default-action button is the single trigger.)
- The rollback banner's button is `.disabled` while the password is empty or a retry is in flight.

**Checkpoint:** wrong password → red banner, stays on the screen; right password → `.unlocked`. The
rollback path's mechanism is covered by
`VaultRepositoryTests.acceptingARestoredBackupClearsTheMarkThenReopens`; exercising it through the app
means manipulating the sandboxed container vault by hand (M4 territory).

```swift
struct UnlockView: View {
  @Environment(AppModel.self) private var model
  @State private var password = ""

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "lock.fill").font(.largeTitle)
      SecureField("Master password", text: $password)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 280)
        .onSubmit(unlock)

      if case .locked(let error?) = model.state {
        errorBanner(error)
      }
      Button("Unlock", action: unlock)
        .keyboardShortcut(.defaultAction)
        .disabled(password.isEmpty || model.state.isUnlocking)

      if model.state.isUnlocking { ProgressView("Deriving key…") }
    }
    .padding(40)
  }

  private func unlock() {
    let bytes = Data(password.utf8)
    password = ""                            // drop the String copy asap (best-effort, §3.4)
    Task { await model.unlock(password: bytes) }
  }

  @ViewBuilder private func errorBanner(_ error: AppError) -> some View {
    switch error {
    case .wrongPassword:
      Label("Wrong password.", systemImage: "xmark.octagon").foregroundStyle(.red)
    case .tampered:
      Label("This vault was modified outside PassFort and isn't safe to open.",
            systemImage: "exclamationmark.triangle").foregroundStyle(.red)
    case .rolledBack(let fileVersion, let lastSeen):
      VStack(spacing: 8) {
        Label("This vault is older than the last version this Mac saw "
              + "(\(fileVersion) vs \(lastSeen)).", systemImage: "clock.arrow.circlepath")
        Text("A restored backup and a rolled-back file look the same. If you restored a backup "
             + "on purpose, accept it:")
          .font(.caption).foregroundStyle(.secondary)
        Button("This was a backup I restored") {
          let bytes = Data(password.utf8); password = ""
          Task { await model.acceptRestoreAndRetry(password: bytes) }
        }
      }
    case .notAVault, .io:
      Label("Couldn't open the vault.", systemImage: "xmark.octagon").foregroundStyle(.red)
    }
  }
}
```

**Why the rollback branch has a button.** The CLI answers a rollback with a printed
`verify --accept-restore` hint; the GUI does the same thing as one click — `HighWaterMark.reset()`
then retry the unlock, which passes the (now-zero) rollback check and repairs the mark forward. It is
still a deliberate act behind an explanatory sentence, not an automatic recovery.

**Checkpoint:** wrong password shows the red banner and stays on the Unlock screen; the right password
transitions to `.unlocked`; simulate a rollback (`cli-guide.md` §6.2, then launch the app) and confirm
the "backup I restored" button clears it.

---

## Phase 4 — First run: create a vault — DONE (2026-09-02)

Shipped as `PassFort/Features/CreateVault/{CreateVaultView,RecoveryKeyView}.swift` + `AppModel`
`createVault` / `confirmRecoveryKeyShown` / a `.showingRecoveryKey(RecoveryKey)` state. Differences
from the sketch:

- **The recovery key is a state case, not a `pendingRecoveryKey` sidecar.**
  `.showingRecoveryKey(RecoveryKey)` (`RecoveryKey` is `Equatable`, so `State` stays `Equatable`); the
  open vault parks in `private var stagedRepo` — keeping "repo non-nil only in `.unlocked`" true — and
  `confirmRecoveryKeyShown()` moves it into `adoptUnlocked`. `RecoveryKeyView` is a full screen (via
  `RootView`), not a sheet.
- **`createVault` returns `AppError?`** rather than flipping to `.locked`. `CreateVaultView` shows the
  returned error inline and stays put; state only leaves `.needsVault` on success.
- **`AppError.message`** added (a plain sentence per case) — `CreateVaultView` and `UnlockView`'s
  simple branches both use it now.
- Calibration runs in `Task.detached(priority: .userInitiated) { service.calibrate() }` — `service` is
  captured as a local (it is a `nonisolated struct`, Sendable) so the ~500 ms Argon2id is genuinely
  off the main actor.

**Checkpoint:** `.needsVault` → the Create form; create-with-recovery shows the grouped key once,
gates on "I've written it down", then lands `.unlocked` with an empty list. Cross-check with
`passfort-cli list <container-path>/vault.sqlite` — note the app's vault lives in its **sandbox
container**, not the CLI's default path.

```swift
struct CreateVaultView: View {
  @Environment(AppModel.self) private var model
  @State private var password = ""
  @State private var confirm = ""
  @State private var withRecovery = true
  @State private var working = false

  var body: some View {
    Form {
      SecureField("Master password", text: $password)
      SecureField("Repeat password", text: $confirm)
      Toggle("Also create a recovery key", isOn: $withRecovery)
      Text("The recovery key is your only way back in if you forget this password. "
           + "You'll see it once.").font(.caption).foregroundStyle(.secondary)
      Button("Create vault") { create() }
        .disabled(working || password.isEmpty || password != confirm)
      if working { ProgressView("Calibrating & creating…") }
    }
    .padding(40).frame(width: 360)
  }

  private func create() {
    working = true
    let pw = Data(password.utf8); password = ""; confirm = ""
    Task { await model.createVault(password: pw, recovery: withRecovery); working = false }
  }
}
```

`AppModel.createVault` runs calibration off the main actor and, on success with a recovery key, sets
`state` to a `.showRecoveryKey(RecoveryKey)` case (or presents a sheet) that **blocks progress behind
an explicit "I've written it down" confirmation** before dropping the key and moving to `.unlocked`.

```swift
func createVault(password: Data, recovery: Bool) async {
  do {
    let params = try await Task.detached { try self.service.calibrate(targetMs: 500) }.value
    let (repo, key) = try await service.createVault(password: password, params: params, recovery: recovery)
    if let key { pendingRecoveryKey = key }          // UI shows it, then calls confirmRecoveryShown()
    try await adoptUnlocked(repo)
  } catch { state = .needsVault /* + surface the error */ }
}
```

**Why calibration is `Task.detached`.** `VaultSession.calibrate` is synchronous and blocks its thread
for ~500 ms running trial hashes. `Task.detached` gets it off the main actor so the `ProgressView`
actually animates. (`Vault.create` / `Vault.unlock` are already `nonisolated async` and hop off main
on their own.)

**Checkpoint:** launching against a path with no vault shows the Create screen; creating with recovery
shows the key exactly once, requires the confirmation, then lands unlocked with an empty list;
`passfort-cli list <that vault>` from a terminal shows the same (empty) vault.

---

## Phase 5 — The vault list — DONE (2026-09-02)

Shipped as `PassFort/Features/VaultList/VaultListView.swift`, wired into `RootView` for `.unlocked`.
Close to the sketch; notes:

- **Sorted, not just filtered** — `rows` sorts by title (`localizedCaseInsensitiveCompare`) after the
  substring filter, matching `passfort-cli list`.
- **`detail:` and the add sheet are inline placeholders** — Phase 6 drops in `AccountDetailView`,
  Phase 7 `AccountFormView`. Selecting a row already works (`selection: AccountSummary.ID?`).
- Empty / no-match state via `ContentUnavailableView` in an `.overlay`; a `favorite` star in the row.
- `.frame(minWidth: 720, minHeight: 420)` on the split view — the window grows on first unlock (the
  lock / create screens are compact). ⌘L on the Lock toolbar button.

**Checkpoint (met):** builds and runs; the app boots to `CreateVaultView` (no vault in the sandbox
container yet), and after a create → `VaultListView` with an empty list. Search + sort are pure
Swift over `model.summaries`; ⌘L → `model.lock()` → back to `UnlockView`, `summaries` emptied.

```swift
struct VaultListView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: AccountSummary.ID?
  @State private var query = ""
  @State private var showingAdd = false

  private var rows: [AccountSummary] {
    let live = model.summaries.filter { !$0.isDeleted }
    guard !query.isEmpty else { return live }
    let q = query.lowercased()
    return live.filter {
      $0.title.lowercased().contains(q)
        || ($0.username?.lowercased().contains(q) ?? false)
        || ($0.host?.lowercased().contains(q) ?? false)
        || $0.tags.contains { $0.lowercased().contains(q) }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(rows, selection: $selection) { row in
        VStack(alignment: .leading) {
          Text(row.title).font(.body)
          if let sub = row.username ?? row.host { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
      }
      .searchable(text: $query)
      .toolbar {
        ToolbarItem { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        ToolbarItem { Button("Lock") { model.lock() }.keyboardShortcut("l", modifiers: .command) }
      }
    } detail: {
      if let id = selection { AccountDetailView(accountID: id) } else { ContentUnavailableView("Select an account", systemImage: "key") }
    }
    .sheet(isPresented: $showingAdd) { AccountFormView(mode: .create) }
  }
}
```

**Why filtering is in the view, over `model.summaries`.** That array *is* the §8.3 in-memory index —
decrypted `(id, title, username, host, tags)`, no secrets, rebuilt on unlock, dropped on lock. Search
and sort happen in Swift over it, exactly as the CLI's `list` does and exactly as the web client will
(§11.3). At hobby scale it is a millisecond of work per keystroke.

**Checkpoint:** the list shows every non-tombstoned account after unlock; `.searchable` filters live;
⌘L locks and returns to the Unlock screen with `model.summaries` emptied.

---

## Phase 6 — Account detail (decrypt on demand) — DONE (2026-09-02)

Shipped as `PassFort/Features/AccountDetail/AccountDetailView.swift` +
`PassFort/Support/Pasteboard.swift`, wired into `VaultListView`'s `detail:`. Notes:

- **`.task(id: accountID)` clears `account` first, then loads.** In a
  `NavigationSplitView` the detail view keeps identity when the selection changes, so the guard
  matters — otherwise the previous account's plaintext flashes while the next one decrypts.
  `.onDisappear` drops it on lock / deselect.
- **`Pasteboard`** (`copy` / `copyTransient`) is its own file — `copyTransient` clears after 20 s
  unless `changeCount` moved. `RecoveryKeyView` now uses `Pasteboard.copy` (no auto-clear). Both carry
  the `TODO(M4): concealed pasteboard type`.
- **History section** — `revisionHistory` as `v3 · password · date` rows, `passwordHistory` behind a
  `DisclosureGroup`, straight off `account.payload` (§7.2, populated by `VaultRepository`). No new
  plumbing.
- The **Edit** toolbar button opens a placeholder sheet — Phase 7 wires `AccountFormView`.

**Checkpoint:** builds and boots. Selecting a row → `repo.account(id:)` (one `pf_open`) → the form;
Reveal toggles the password; switching rows re-decrypts; ⌘L mid-view tears it down. The one
`pf_open`-per-selection path is what `VaultRepositoryTests.createRoundTripsThroughAccount` covers at
the library level.

```swift
struct AccountDetailView: View {
  @Environment(AppModel.self) private var model
  let accountID: UUID

  @State private var account: Account?
  @State private var reveal = false
  @State private var editing = false

  var body: some View {
    Group {
      if let account {
        Form {
          LabeledContent("Title", value: account.payload.title)
          if let u = account.payload.username { LabeledContent("Username", value: u) }
          if let p = account.payload.password {
            HStack {
              Text(reveal ? p : String(repeating: "•", count: 12)).font(.system(.body, design: .monospaced))
              Spacer()
              Button(reveal ? "Hide" : "Reveal") { reveal.toggle() }
              Button("Copy") { Pasteboard.copyTransient(p) }        // Phase 6 note
            }
          }
          // email, urls, notes, tags, category, created …
        }
        .toolbar { Button("Edit") { editing = true } }
        .sheet(isPresented: $editing) { AccountFormView(mode: .edit(account)) }
      } else { ProgressView() }
    }
    .task(id: accountID) { account = try? await model.repo?.account(id: accountID) }
    .onDisappear { account = nil; reveal = false }
  }
}
```

**Why `.task(id:)` + `.onDisappear`.** The detail view decrypts **one** record when it appears
(`repo.account(id:)` → one `pf_open`) and drops it when it disappears. Decrypt-on-demand, scoped to a
single view's lifetime — the first two mitigations in §3.4, verbatim. `dump`-style en-masse decryption
never happens in the app.

**History section.** `account.payload.revisionHistory` (newest-first `{version, at, changed}`) and
`passwordHistory` (old password values) are already populated by `VaultRepository` on every edit
(architecture §7.2) — a disclosure group listing "v3 · password · 2 Sep" and a "previous passwords"
list behind a reveal, mirroring `passfort-cli history`. `account.lastUpdated` gives the "last
modified" line. No new plumbing — it's all in the payload the view already has.

**Pasteboard (`Pasteboard.copyTransient`).** M3: write the string and schedule a clear after ~20 s
(`NSPasteboard.general.clearContents()`), best-effort. **M4 replaces this** with the concealed
pasteboard type (`org.nspasteboard.ConcealedType`, so clipboard managers skip it) and a proper
expiry — that is the A5 mitigation and it belongs with the other platform-integration work. Leave a
`// TODO(M4): concealed pasteboard type` here.

**Checkpoint:** selecting a row decrypts and shows it; Reveal toggles the password; navigating away and
back re-decrypts (confirm with a breakpoint that `account` went to `nil`); locking mid-view tears
everything down.

---

## Phase 7 — Add, edit, delete — DONE (2026-09-02)

Shipped as `PassFort/Features/AccountForm/AccountFormView.swift` + `AppModel`
`createAccount` / `updateAccount` / `deleteAccount` / `writeCounter`. Notes:

- **Writes go through `AppModel`, not the view.** `write(_:)` runs the `VaultRepository` call, bumps
  `writeCounter`, refreshes `summaries`, and maps `VaultError.staleWrite` → a readable message. The
  form just calls `model.createAccount(payload)` etc. and shows the returned `AppError?`.
- **`AccountDetailView` reloads on `writeCounter`** (`.onChange`) so an edit is reflected without
  re-selecting; a delete leaves it showing `account.isDeleted` → an "Account deleted" state.
- **URLs / tags are edited as text** (newline- / comma-separated), parsed on save — keeps the form
  simple and doesn't lose a second URL on edit. `optional(_:)` is a local `String?`↔`String` binding
  helper (empty ⇄ nil).
- **Generate** → `PasswordPolicy().generate()` (default policy) — the same generator as
  `passfort-cli gen`. A policy popover is a later nicety.
- Delete is behind a `.confirmationDialog`; edit-mode only.

**Checkpoint (manual):** add → row appears (v1); edit → v2, detail reflects it; delete → row leaves
the list; `passfort-cli list <container-path>/vault.sqlite --all` agrees at every step. The
`repo.create` / `.update` / `.delete` paths themselves are covered by `VaultRepositoryTests` +
`AccountHistoryTests`.

```swift
struct AccountFormView: View {

```swift
struct AccountFormView: View {
  enum Mode { case create, edit(Account) }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let mode: Mode
  @State private var draft: AccountPayload
  @State private var saving = false

  init(mode: Mode) {
    self.mode = mode
    switch mode {
    case .create: _draft = State(initialValue: AccountPayload(title: ""))
    case .edit(let account): _draft = State(initialValue: account.payload)
    }
  }

  var body: some View {
    Form {
      TextField("Title", text: $draft.title)
      TextField("Username", text: Binding($draft.username, default: ""))
      HStack {
        SecureField("Password", text: Binding($draft.password, default: ""))
        Button("Generate") { draft.password = try? PasswordPolicy().generate() }   // + a policy popover
      }
      // email, url list, notes, category picker, tags, favorite toggle …
      HStack {
        if case .edit(let account) = mode {
          Button("Delete", role: .destructive) { Task { await delete(account.id) } }
        }
        Spacer()
        Button("Save") { Task { await save() } }.disabled(saving || draft.title.isEmpty)
      }
    }
    .padding(24).frame(width: 420)
  }

  private func save() async {
    saving = true
    defer { saving = false }
    guard let repo = model.repo else { return }
    do {
      switch mode {
      case .create:            _ = try await repo.create(draft)
      case .edit(let account): _ = try await repo.update(id: account.id) { $0 = draft }
      }
      await model.refreshSummaries()
      dismiss()
    } catch { /* surface: e.g. VaultError.staleWrite -> "changed elsewhere, reopen" */ }
  }

  private func delete(_ id: UUID) async {
    try? await model.repo?.delete(id: id)
    await model.refreshSummaries()
    dismiss()
  }
}
```

**Why a draft copy + `{ $0 = draft }`.** `VaultRepository.update` takes a mutation closure and does the
decrypt → mutate → bump version → re-seal → re-MAC dance in one transaction (§8.2). The form edits a
detached `AccountPayload`; the closure assigns it wholesale. Same semantics as
`passfort-cli edit --set`. The `unknown` forward-compat bag rides along untouched because it is part of
the payload value being assigned.

**The "Generate" button** calls `PasswordPolicy.generate()` from `PassFortVault` — the same generator
`passfort-cli gen` / `add --generate-password` use. M3 can start with the default policy and add a
small popover (length slider, class toggles) later; the policy is `Codable`, so a per-vault default in
`vault_meta` is a cheap follow-up if you want one.

**After every write, `refreshSummaries()`** — the in-memory index is a snapshot, not a live query, so
it needs an explicit rebuild. Cheap (§8.3).

**Checkpoint:** add creates a row (version 1) and it appears in the list; edit takes it to version 2
and the detail view reflects the change; delete tombstones it and it leaves the list;
`passfort-cli list <vault> --all` from a terminal agrees on every step.

---

## Phase 8 — Auto-lock — DONE (2026-09-02)

`AutoLock` (Phase 2's stub) grew the `NSEvent` activity monitor + `bump()`; `PassFort/Features/Settings/
SettingsView.swift` + a `Settings` scene added. Notes:

- **`invalidate()`, no `deinit`.** The event monitor and the countdown task are both dropped in
  `invalidate()`, which `AppModel` calls on `lock()` / before re-arming — cleaner than a `deinit` that
  touches actor-isolated state.
- **Timeout is `@AppStorage("autoLockSeconds")`** (a `Picker`: 1 / 5 / 15 / 60 min — discrete beats a
  slider for this). `SettingsView.onChange` → `model.autoLockSettingDidChange()` re-arms `AutoLock`
  with the new interval, no relaunch.
- **`SettingsView`** also has "Lock now" and "Rotate recovery key…" (→ `AppModel.rotateRecoveryKey`,
  which reuses `.showingRecoveryKey` / `stagedRepo` — the same one-time-shown gate as Phase 4, then
  back to `.unlocked`). Both disabled unless unlocked.
- Lock on system sleep / screen lock stays **M4** (`TODO(M4)` in `AutoLock`).

**Checkpoint:** builds + boots. Idle past the timeout → `.locked`; ⌘-Tab away (`.background`) → locked
on return; changing the Settings picker re-arms without a relaunch; ⌘L works from the list toolbar.

```swift
@MainActor
final class AutoLock {
  private var task: Task<Void, Never>?
  private var monitor: Any?
  private let timeout: Duration
  private let onLock: () -> Void

  init(timeout: Duration = .seconds(300), onLock: @escaping () -> Void) {
    self.timeout = timeout
    self.onLock = onLock
    self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown]) {
      [weak self] event in self?.bump(); return event
    }
    bump()
  }

  func bump() {
    task?.cancel()
    task = Task { [timeout, onLock] in
      try? await Task.sleep(for: timeout)
      if !Task.isCancelled { onLock() }
    }
  }

  deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
```

Plus, in the scene:

```swift
@main struct PassFortApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView().environment(model)
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.lock() } }
    }
  }
}
```

**What M3 auto-lock covers:** an idle timer (reset on key/mouse activity), lock on the window going to
`.background`, and the ⌘L command from Phase 5. `lock()` drops `repo` → session zeroized, index
dropped.

**What it does not cover (M4):** lock on system sleep (`NSWorkspace.willSleepNotification`) and on
screen lock (`com.apple.screenIsLocked` via `DistributedNotificationCenter`) — those are in the §12 M4
row alongside Touch ID and the hardened runtime. A `// TODO(M4)` in `AutoLock` is enough.

**Settings** (Phase 8, `Features/Settings/`): a slider for the idle timeout (persist to
`UserDefaults` — it is a preference, not a secret), a "Lock now" button, and "Rotate recovery key"
(`repo.rotateRecoveryKey()` → show the new key once, same confirmation gate as Phase 4).

**Checkpoint:** leave the app idle past the timeout → it returns to the Unlock screen; ⌘-Tab away and
background it → locked on return; the timeout slider takes effect without a relaunch.

---

## Phase 9 — Tests and CI — IN PROGRESS

The test *file* is written — `PassFortTests/AppModelTests.swift` (9 tests, drive `AppModel` directly,
no UI). Creating the **target** is a manual Xcode step (a unit-test bundle is ~10 interlinked
`pbxproj` objects + a scheme `TestAction` — not safe to hand-write):

1. **File → New → Target → macOS → Unit Testing Bundle.** Name it **`PassFortTests`**, Testing System
   **Swift Testing**, Target to be Tested **PassFort**. Xcode creates a `PassFortTests/` synchronized
   folder (it picks up the already-present `AppModelTests.swift`) and adds a `TestAction` to the
   shared `PassFort.xcscheme`.
2. Delete the template `PassFortTests.swift` Xcode adds alongside.
3. **PassFortTests target → General → Frameworks and Libraries → add `PassFortVault` and
   `PassFortCrypto`** — the tests `import` them directly (for `KdfParameters` / `Vault` /
   `HighWaterMark`). `@testable import PassFort` reaches `AppModel` etc.
4. `xcodebuild test -scheme PassFort -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` green
   locally.
5. **CI:** add the step to the `swift` job, right after "App builds (unsigned)":

   ```yaml
         - name: App tests
           run: |
             xcodebuild test \
               -project PassFort.xcodeproj -scheme PassFort \
               -destination 'platform=macOS' \
               CODE_SIGNING_ALLOWED=NO
   ```

6. Commit: the new target + the updated `PassFort.xcscheme` + `project.pbxproj` + the CI step, as
   `m3: Phase 9 — AppModel state-machine tests + CI`.

### The tests (`PassFortTests/AppModelTests.swift`)

Nine tests, `@MainActor struct AppModelTests`, driving `AppModel` directly (no UI):

| Test | Asserts |
|---|---|
| `freshPathNeedsAVault` | missing path → `.needsVault` |
| `existingVaultStartsLocked` | a real vault → `.locked()` |
| `wrongPasswordStaysLockedWithNoRepo` | `.locked(.wrongPassword)`, `repo == nil` |
| `rightPasswordUnlocks` | `.unlocked`, `repo != nil`, empty index |
| `unlockThenLockTearsDown` | after `lock()`: `.locked`, `repo == nil`, `summaries == []` |
| `createWithoutRecoveryGoesStraightToUnlocked` | `.needsVault` → `createVault(recovery: false)` → `.unlocked` |
| `createWithRecoveryShowsTheKeyThenUnlocks` | → `.showingRecoveryKey` (`repo` still parked), then `confirmRecoveryKeyShown()` → `.unlocked` |
| `accountWritesRefreshTheIndexAndBumpTheCounter` | `createAccount` / `deleteAccount` update `summaries` and `writeCounter` |
| `aRolledBackVaultOffersRestoreThenUnlocks` | force `HighWaterMark` ahead → `.locked(.rolledBack(0, 5))`; `acceptRestoreAndRetry` → `.unlocked` |

The create-flow tests run real Argon2id (via `model.createVault`); the rest use the `fastParams`
8-MiB KDF. The file-level rollback detection stays covered by `VaultRepositoryTests` — the app test
just forces the sidecar mark and checks the `AppModel` transition.

**Checkpoint:** once the target exists — `xcodebuild test -project PassFort.xcodeproj -scheme PassFort
-destination 'platform=macOS'` green locally and in CI; `swift test` (the package suites) still green.

---

## Phase 10 — "Last used" — DEFERRED past M3 (2026-09-02)

`architecture.md` §14 open decision 11: `usedAt` is a write-amplification trap, so "last used" would
be a **local-only, un-synced, not-in-the-manifest-MAC** sidecar — a schema-v2 migration + a new
fixture (§13.4), or a sibling `usage.sqlite`.

**Decision: not built.** The M3 list sorts by title and that is enough; a "recent" sort doesn't earn
a storage-layer change and a new migration right now. `usedAt` stays `nil`; open decision 11 stays
open, re-scoped as "M4+ if a recent/frequent sort is added". Recorded in §14.

If it is built later: it records a timestamp on detail-view open, device-local, and **never** touches
the `usedAt` payload field.

---

## Where this leaves you

- **A working macOS app** doing full CRUD against a real encrypted vault — the M3 exit criterion
  (Phase 7). Phases 2–8 shipped; Phase 9 is written and waits on the test target (a manual Xcode
  step); Phase 10 is deferred.
- **The lock-state machine** is the spine: a key or a decrypted title exists only while
  `state == .unlocked`, and `lock()` (idle, background, or ⌘L) tears the whole graph down.
- **Everything still goes through `VaultRepository`** — the app added a window and a search box, not
  capability. The CLI and the GUI are two front ends onto one storage layer.
- **Deviations logged in each phase's "DONE" block:** `PassFort/` not `App/` (Phase 1); every type
  `@MainActor` by default so `VaultService` is `nonisolated` (Phase 2); `Vault.exists` read-only
  (Phase 2.3); `PassFortCrypto` made a `.library` product; `AppError.message`; writes centralized in
  `AppModel.write(_:)`.
- **Post-plan UI polish** (not phases, landed after the checkpoint):
  `Features/PasswordGenerator/PasswordGeneratorView.swift` — the `passfort-cli gen` knobs (length,
  the four classes, exclude-look-alikes, `@AppStorage`-persisted), reachable from the **Tools** menu
  (⌘⌥G) and the account form's "Generate…". Detail view: copy buttons on username / email, URLs as
  browser `Link`s.
- **Next:** M4 — platform integration. Keychain-backed high-water mark and password, Touch ID unlock,
  hardened runtime + entitlements + a notarization dry-run in `release.yml`, the concealed pasteboard
  type, and lock-on-sleep/screen-lock. Ask for `m4-platform.md` when you get here.
