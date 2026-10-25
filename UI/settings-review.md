# Settings window: UI/UX review

2026-10-25. A design review of the ⌘, window as built at `71b0335`: the General, Vault, Backup
and Sync tabs (`PassFortApp.swift` `Settings { TabView { … } }`) and the sheets they open. It is a
list of findings and a proposed layout.

**Built 2026-10-25** on the `settings-redesign` branch, following
`docs/runbooks/settings-redesign.md`. That runbook's Outcome section lists where the build differs
from this proposal; the shortcut recorder and the recovery-key status are deferred.

Mockups of the proposal are on the design canvas in `UI/mockups/` (local only, gitignored):
`Settings.dc.html` (the proposed tabs, light and dark) and `SettingsStates.dc.html` (today's General
tab, the recovery-key flow, the locked and empty states, the File menu). Static previews are in
`UI/mockups/preview/`.

Files reviewed:

| Tab | View |
|---|---|
| General | `PassFort/Features/Settings/SettingsView.swift`, `ChangePasswordView.swift` |
| Vault | `PassFort/Features/Location/VaultLocationSettingsView.swift`, `CreateVault/NewVaultView.swift`, `CreateVault/LoadVaultView.swift`, `Join/JoinVaultView.swift` |
| Backup | `PassFort/Features/Settings/BackupSettingsView.swift`, `Restore/RestoreBackupButton.swift` |
| Sync | `PassFort/Features/Sync/SyncSettingsView.swift`, `DevicesList.swift`, `AddDeviceSheet.swift` |

## Overall view

The safety work underneath is good. Confirmations are careful, nothing is ever deleted, and Backup
works while the vault is locked. The surface on top has grown one feature at a time, and it shows.
The biggest problems are about structure rather than looks: Settings mixes preferences with risky
vault operations, each tab handles the locked state differently, and some important results land in
a different window from the one the user is looking at.

## The most important problems

### 1. Settings is doing two jobs

On macOS, Settings is expected to hold preferences. "Start a New Vault", "Load Vault", "Join a
Synced Vault" (Vault tab) and "Restore from Backup" (Backup tab) are operations that swap out the
whole vault. They read better as menu commands:

- File ▸ New Vault…
- File ▸ Open Vault…
- File ▸ Join Synced Vault…
- File ▸ Restore from Backup…

They already open self-explanatory sheets, so moving them costs nothing. It also removes the
paragraph under them (`VaultLocationSettingsView.swift:57`) that tries to describe three buttons at
once, and says "Either way" when there are three options.

### 2. Important results appear in a different window from the user

Rotating the recovery key (`AppModel.rotateRecoveryKey`), or changing the password with "Issue a new
recovery key" on, sets `state = .showingRecoveryKey(key)`. `RootView` then shows the key in the
**main** window, while the user is still looking at the Settings window in front of it. This is the
one screen in the app that says "write this down, you'll see it once".

If the main window is closed (the app keeps running because of the `MenuBarExtra`), there appears to
be nowhere for the key to show at all. Not yet confirmed by running it; worth checking first.

Fix: show the key as a sheet on the Settings window, or bring the main window to the front before
switching state.

### 3. "Rotate recovery key…" has no confirmation and fails silently

- It cancels the current key immediately, with no "your current key stops working" prompt.
- `guard let key = try? await repo.rotateRecoveryKey() else { return }` (`AppModel.swift:192`)
  throws away any error, so a failed click simply does nothing.
- The UI never says whether a recovery key exists or when it was last rotated.

### 4. The locked state works four different ways

| Tab | When locked |
|---|---|
| General | Buttons greyed out, no explanation |
| Vault | Greyed out, with "Unlock the vault first" as the last sentence of a long caption |
| Sync | The whole tab is replaced by one line |
| Backup | Works while locked (correct) |

Pick one pattern, for example a single "Vault is locked — unlock to change these" row at the top of
each section that needs it.

### 5. The window resizes on every tab switch

The tabs are fixed at 380 / 440 / 440 / 460 pt wide, and each adds `.padding()` around a
`.formStyle(.grouped)` form that already has its own inset. So the window jumps as you click
through, and the margins are doubled. Use one width (about 480–500 pt) and remove the outer padding.

### 6. "Crypto activity" doesn't belong in General

"Records sealed / opened" with a manual Refresh button (`SettingsView.swift:49`) is a debugging
readout. It means nothing to a user, and it sits in the tab you see first. Remove it, or move it to
`passfort-cli` or behind a debug build.

## Tab by tab

### General (in practice it only holds security settings)

- **Remove "Lock now".** It repeats the ⌘L toolbar button (`VaultListView.swift:248`). Lock should
  be a menu item instead: today ⌘L only exists on a toolbar button, so it never appears in a menu.
- **Explain when the app locks.** Lock on sleep and on screen lock are built (`AutoLock.swift`) but
  never mentioned. A one-line footer ("Also locks when your Mac sleeps or the screen locks") builds
  trust. "Lock after inactivity" is also clearer than "Auto-lock after".
- **Add the settings people expect:**
  - *Clear clipboard after*: currently fixed at 20 s (`Pasteboard.copyTransient`). Every major
    password manager lets you change this.
  - *Show in menu bar*: the `MenuBarExtra` key icon is always there, with no way to turn it off.
- **Shortcut conflict.** When another app owns ⌃⌥Space, the message says so but offers no way out,
  because the shortcut can't be changed. A shortcut recorder would fix it. If not now, the message
  should at least say what to do.

### Vault

- **Location.** "Vault file: path" plus "Kept in: PassFort's own storage" says the same thing twice.
  Replace the second line with a **Show in Finder** button, which is the most useful action on that
  row.
- **Button label.** "Use Default Location" moves the file and asks for confirmation, so it should be
  "Move Back to Default…", with the ellipsis.
- **Space.** Three buttons in one row at 440 pt is cramped. "Join a Synced Vault…" is greyed out with
  no reason when sync isn't available. Both go away if these move to the File menu (problem 1).

### Backup (the best tab)

- **Ambiguous label.** "Remove" next to the folder could mean deleting the backups. Use "Stop Using
  Folder" or "Forget Folder".
- **Empty state.** With no folder chosen, the whole tab shows greyed-out controls. Show a short empty
  state instead: one line plus one main **Choose Folder…** button, and reveal the rest once a folder
  is set.
- **Status line.** "Last backup Oct 25, 14:02 · version 37" shows `vault_version`, an internal
  counter. A relative time works better ("2 hours ago"), along with how many backups the folder holds
  and a Show in Finder link.
- **Footer.** The last explanation sits in its own empty section (`BackupSettingsView.swift:56`).
  Make it the section's footer.

### Sync

- **Sync Now.** It sits alone on its own right-aligned row. Put it at the end of the Status row.
- **"This vault" section.** Information and an action are mixed: "Add a Device…" sits between "This
  Mac" and "Sync on since". It belongs with the Devices list, as a header button or a footer row.
  "This Mac" also appears in both sections; the Devices list badge is enough.
- **Vault ID.** It is shown with a copy button, but the invite sheet already covers joining. Move it
  to the invite sheet or a disclosure group.
- **Paused state.** `SyncController.isPaused` is set automatically after a hard problem, and only
  Sync Now clears it. It isn't a user setting, but the Status row should say plainly that sync is
  paused and why, with the problem (`SyncProblemSheet`) one click away.
- **Server field placeholder.** `https://….azurestaticapps.net/api/v1` exposes the hosting setup.
  `https://your-server/api/v1` is neutral.

## Across all tabs

- **Too much text.** Nearly every section ends in a paragraph of `.caption`, `.secondary` text: 3–4
  sentences on Vault and Sync, two separate paragraphs on Backup. Cut it roughly in half and use
  section footers. The sheets are where detail belongs.
- **Button placement.** Vault and Backup put buttons on the left; Sync right-aligns them with
  `Spacer()`. Grouped forms in System Settings put the action at the end of the row it acts on.
- **Capitalisation.** General uses "Lock now" and "Change master password…", while other tabs use
  title case ("Back Up Now", "Choose Folder…"). macOS buttons are title case.
- **Errors.** Vault errors need an "OK" click to clear; the other tabs' errors don't. Pick one.

## Proposed layout

| Tab | Contents |
|---|---|
| **General** | Lock after inactivity (+ sleep / screen-lock footer), Clear clipboard after, Quick Access shortcut, Show in menu bar |
| **Security** *(needs unlock)* | Change Master Password…, Recovery key: last rotated date + Rotate… (with confirmation) |
| **Vault** | Location, Show in Finder, Move…, Move Back to Default… |
| **Backup** | As now, with the fixes above |
| **Sync** | Status + Sync Now · Devices + Add a Device… · Server details · Turn Off… |
| **File menu** | New Vault…, Open Vault…, Join Synced Vault…, Restore from Backup…, Lock ⌘L |

## Suggested order of work

1. **Recovery key in the right window** (problem 2), then the rotation confirmation and error
   (problem 3). These are the only findings that touch a security-critical flow.
2. **Quick wins**, mostly small edits: one window width and no outer padding, remove Lock now and
   Crypto activity, fix labels and capitalisation, move captions into section footers, the Backup
   "Remove" label.
3. **One locked-state pattern** across tabs (problem 4).
4. **Structural changes**: the File menu move (problem 1) with Lock as a menu item, the Security tab,
   and the new clipboard and menu bar settings.
