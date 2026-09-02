# Using `passfort-cli` — a hands-on guide to the M0–M2 build

This is not a build runbook. It is a **walkthrough of everything the project can do today**, from the
command line, with real transcripts. If you have just finished M2 and want to convince yourself the
vault actually works — create one, put a password in it, break it, fix it — start here.

**What exists after M2:** the crypto core (`PFCrypto`), the Swift seam (`PassFortCrypto`), the storage
layer (`PassFortVault`), and `passfort-cli` — a Swift executable that drives the whole stack. There is
**no GUI yet** (that is M3) and **no sync** (M5). The CLI is the product for now, exactly as
`architecture.md` §12 intends: "Build M1 and M2 entirely through `passfort-cli`."

**Spec cross-refs:** vault format `§5`, data model `§7`, storage `§8`, recovery `§5.6`, export `§7.6`,
the seam `§6`. The per-milestone runbooks are `m1-crypto-core.md` and `m2-vault-storage.md`.

---

## 1. Build the CLI

```bash
cd Packages/PassFortKit
swift build                      # compiles PFCrypto (incl. the Botan amalgamation), the Swift
                                 # modules, passfort-cli, and the pf-killtest helper
```

The first build compiles Botan and takes a few minutes; after that it is incremental and fast. The
binary lands at `Packages/PassFortKit/.build/debug/passfort-cli`. Two ways to run it:

```bash
swift run passfort-cli <subcommand> …          # from Packages/PassFortKit/, rebuilds if stale
.build/debug/passfort-cli <subcommand> …        # the built binary directly
```

The rest of this guide writes `passfort-cli` for brevity. Every example uses an explicit vault path —
the CLI never falls back to a default location (the app will use
`~/Library/Application Support/PassFort/vault.sqlite`; the CLI makes you say where).

**Checkpoint:** `passfort-cli --help` lists the subcommands.

```text
$ passfort-cli --help
OVERVIEW: PassFort vault tool -- create an encrypted SQLite vault and manage accounts in it.

USAGE: passfort-cli <subcommand>

SUBCOMMANDS:
  bench                   Calibrate Argon2id for this machine and print the parameters.
  gen                     Generate random password(s). No vault needed; prints to stdout.
  init                    Create a new vault (an encrypted SQLite database) and prompt for its password.
  unlock                  Open a vault, run the manifest + anti-rollback checks, report what's inside.
  verify                  Check the manifest MAC and the anti-rollback mark, nothing else.
  add                     Create an account in the vault. Prints its id.
  list                    List accounts from the in-memory summary index -- no secrets.
  get                     Show one account -- secrets included -- on stdout.
  history                 Show an account's version timeline -- what changed, when.
  edit                    Update an account. Repeatable --set key=value; …
  rm                      Tombstone an account. The row survives until `compact` (M5).
  dump                    Print every record (tombstones included), decrypted, as JSON. Debug aid.
  export                  Decrypt the whole vault to a plaintext JSON file (§7.6), behind a typed phrase.
  recover                 Open the vault with its recovery key and set a new master password (§5.6).
  seam                    Run the M0 + M1 seam round trip end to end.
```

---

## 2. The mental model

Five things to hold in your head before you start typing.

**A vault is one SQLite file plus small sidecars.** `demo.sqlite` is the vault. Next to it you will
see:

| File | What it is | Committed? |
|---|---|---|
| `demo.sqlite` | the vault: the §5.3 header row, the sealed records, the manifest MAC — all in `vault_meta` / `records` | never (`*.sqlite` is git-ignored) |
| `demo.sqlite-wal`, `demo.sqlite-shm` | SQLite's write-ahead log and shared-memory index (`journal_mode = WAL`, §8.2) | never |
| `demo.sqlite.hw` | the **anti-rollback high-water mark** — the highest `vault_version` this machine has seen, kept *outside* the file on purpose (§5.5) | never |
| `.metadata_never_index` | a marker `VaultDatabase` drops in the directory to keep the vault out of Spotlight (§8.2) | never |

To move or back up a vault, copy **all** of `demo.sqlite*` together. Copying just the `.sqlite` while a
`-wal` exists gets you a stale vault.

**The master password never appears on the command line.** Every command that touches the vault
prompts for it with echo off (`getpass`), so it stays out of your shell history, `ps`, and the
scrollback. There is deliberately no `--master-password` flag.

**There is no "save" step.** Every `add` / `edit` / `rm` is a single SQLite transaction that writes the
row *and* re-computes the whole-vault manifest MAC, with an `fsync` at commit (`synchronous = FULL`).
When the command returns, the change is durably on disk. This is the one invariant the whole storage
design is built around (§8.2) — the row and the MAC can never diverge, even if the machine loses power
mid-write.

**Secrets vs. metadata.** `list` builds an in-memory index of `(id, title, username, host)` — no
passwords — by decrypting every record, and throws it away when the command exits (§8.3). `get`,
`dump`, and `export` are the only commands that put secret values on your screen or disk.

**A session is one unlock.** Each command opens its own crypto session (runs Argon2id, ~0.5 s),
does its work, and closes it (keys zeroized). There is no daemon holding the vault open between
commands — that is a GUI concern (M3 auto-lock).

---

## 3. Create a vault

```text
$ passfort-cli init demo.sqlite
New vault password:
Repeat password:
calibrating Argon2id (~500 ms)...
created demo.sqlite (64 MiB Argon2id)
```

What happened:

1. You were prompted twice for the password and it had to match — a typo here means a permanently
   unopenable vault, so `init` refuses a mismatch.
2. `--target-ms` (default 500) drove an **Argon2id calibration** on this machine: the CLI measured how
   much memory and how many passes hit ~500 ms and baked those parameters into the header. A slower
   machine gets a cheaper KDF, a faster one a more expensive KDF, for the same unlock latency (§5.2).
   The `64 MiB` in the output is the memory cost it settled on.
3. A random data-encryption key (DEK) and a vault UUID were generated, the DEK was wrapped under the
   password-derived key, and the §5.3 header was written as `vault_meta['header']`. `vault_version` was
   seeded to 0 and a manifest MAC over the empty record set was stored.
4. The `.hw` sidecar was written (`0`), and the directory got its `.metadata_never_index` marker.

Flags:

| Flag | Effect |
|---|---|
| `--target-ms <n>` | KDF calibration target in milliseconds (default 500). Lower it (`--target-ms 50`) for a throwaway test vault so unlock is snappy; leave it at 500+ for anything real. |
| `--recovery` | also generate a **recovery key** and write a two-slot header (§5.6) — see §6.3 below |
| `--force` | delete an existing vault at this path first (`demo.sqlite`, `-wal`, `-shm`, `.hw`) before creating |

**Checkpoint:** `ls demo.sqlite*` shows the vault and its `.hw` sidecar; `passfort-cli unlock
demo.sqlite` prompts for the password and prints `unlocked OK -- 0 accounts`.

---

## 4. The CRUD loop — worked example

The task: **create a vault, add a dummy account, confirm it is saved.**

### 4.1 Add an account

```text
$ passfort-cli add demo.sqlite --title "GitHub" --username octocat --url https://github.com --prompt-password
Account password:
Vault password:
F227FF95-52FA-4F0A-9264-873AF8E14128
```

`add` prints the new record's UUID on stdout (so a script can capture it). The account password was
entered at a no-echo prompt because you passed `--prompt-password`. Three ways to set the password,
pick one: `--prompt-password` (no echo), `--password <value>` (inline — convenient, but it lands in
your shell history, and `--help` says so), or `--generate-password` (a fresh random one, printed to
stderr — §4.5). With none of them, the account simply has no password field (fine for a secure note).

Everything `add` accepts:

| Flag | Notes |
|---|---|
| `--title <t>` | **required** — the one always-present field |
| `--username <u>` | |
| `--email <e>` | |
| `--password <v>` / `--prompt-password` / `--generate-password` | inline value / no-echo prompt / fresh random one; pick one |
| `--length`, `--no-symbols`, `--no-digits`, `--no-uppercase`, `--no-lowercase`, `--allow-ambiguous` | shape `--generate-password` (§4.5) |
| `--url <u>` | repeatable — `--url https://a --url https://b` |
| `--note <text>` | free-text note |
| `--category <c>` | one of `login` (default), `bankAccount`, `paymentCard`, `identity`, `secureNote`, `wifi`, `softwareLicense`, `server`, `database`, `apiCredential`, `other` |
| `--tag <t>` | repeatable |
| `--favorite` | flag |

Behind the scenes: the payload was JSON-encoded, padded to the next 256-byte boundary (so
`sealed.count` stops leaking note length, §14.7), sealed with the record UUID + version + schema bound
as the AEAD's associated data (§5.4), written as a `records` row at `version = 1`, and the manifest MAC
re-computed — all in one transaction. **That is the save.** There is no further step.

### 4.2 Confirm it is there

```text
$ passfort-cli list demo.sqlite
Vault password:
ID                                    TITLE                     USERNAME              HOST
F227FF95-52FA-4F0A-9264-873AF8E14128  GitHub                    octocat               github.com
```

`list` rebuilt the in-memory index, printed it sorted by title, and dropped it. `--search <q>` filters
(case-insensitive substring over title / username / host / tag); `--all` includes tombstoned rows.

```text
$ passfort-cli get demo.sqlite GitHub
Vault password:
id             01E9C43F-8EE2-4BA4-ACA6-0B503573CF9E
version        3
title          GitHub
username       octocat-2
password       X:YXm9&r*3;V#-z(qXL3
category       login
favorite       yes
created        2026-09-02T13:57:17Z
updated        2026-09-02T13:57:18Z
pw changed     2026-09-02T13:57:18Z
revisions      3 (latest v3: password)
old passwords  1 kept -- `passfort-cli history … --passwords` to read
```

`get` takes a **UUID or a title**. Title resolution is: exact case-insensitive match first, then a
unique case-insensitive substring, else an error telling you to disambiguate. It decrypts that one
record and prints every populated field — **including the password** — to stdout, plus the audit
lines: `created` / `updated` (the last-write time, from the plaintext HLC column), `pw changed`, a
`revisions` count, and how many old passwords are kept (§4.6).

`--json` emits the same thing structured — the envelope identity and `updated_at` wrapped around the
decrypted payload:

```text
$ passfort-cli get demo.sqlite "GitHub" --json
{
  "id" : "01E9C43F-8EE2-4BA4-ACA6-0B503573CF9E",
  "is_deleted" : false,
  "payload" : {
    "category" : "login",
    "created_at" : "2026-09-02T13:57:17Z",
    "favorite" : true,
    "password" : "X:YXm9&r*3;V#-z(qXL3",
    "password_changed_at" : "2026-09-02T13:57:18Z",
    "password_history" : [ { "password" : "first-pw", "replaced_at" : "…" } ],
    "revision_history" : [
      { "at" : "…", "changed" : ["password"], "version" : 3 },
      { "at" : "…", "changed" : ["username", "favorite"], "version" : 2 },
      { "at" : "…", "changed" : ["created"], "version" : 1 }
    ],
    "schema_version" : 1,
    "title" : "GitHub",
    "username" : "octocat-2"
  },
  "updated_at" : "2026-09-02T13:57:18Z",
  "version" : 3
}
```

### 4.3 Edit it

```text
$ passfort-cli edit demo.sqlite GitHub --set password=rotated-pw --set favorite=true
Vault password:
updated F227FF95-52FA-4F0A-9264-873AF8E14128 -> version 2
```

`--set key=value` is repeatable. Valid keys: `title`, `username`, `password`, `email`, `notes`,
`favorite` (`true`/`false`/`yes`/`no`/`1`/`0`), `category`. An empty value (`--set username=`) clears an
optional field. Bad keys and bad values are rejected **before** the write transaction opens, so a
typo never half-applies. Also here:

- `--prompt-password` — set a new password at a no-echo prompt
- `--generate-password` — rotate to a fresh random password (§4.5); the new value prints to stderr
- `--add-url <u>` — append a URL (repeatable)

`--set password=…`, `--prompt-password`, and `--generate-password` are mutually exclusive — pick one.

Every edit **bumps the version** (1 → 2), restamps `updated_at`, re-seals the payload at the new
version, and re-MACs the vault. Old version, old ciphertext: gone.

### 4.4 Delete it

```text
$ passfort-cli rm demo.sqlite GitHub
Vault password:
tombstoned F227FF95-52FA-4F0A-9264-873AF8E14128
```

`rm` **tombstones** — it sets `is_deleted = 1`, bumps the version, and re-seals. The row survives
(hidden from `list` unless `--all`, and `get`/`edit` on it fail with "no account matches") until a
future `compact` purges it. M2 has no `compact` subcommand yet — tombstones just accumulate, which is
harmless at this scale and correct for M5 sync, where "deleted" has to mean "deleted on every device".

### 4.5 Generate a password

`passfort-cli gen` is a standalone generator — no vault, straight to stdout:

```text
$ passfort-cli gen
~126 bits of entropy each
q4(^:o%!GP2RTYvwDUiG

$ passfort-cli gen --length 32 --no-symbols --count 3
~187 bits of entropy each
uEzMAePpPerACoRb79cXT7Gx3WaYy9AK
2E6taA53NEaX7EBC3jwYqPMxw85Q8AfJ
yyrTwh3SD32XSQS7AGG6m2iQpYNTmxbL
```

Defaults: length 20, all four character classes (lowercase, uppercase, digits, symbols), at least one
of each, and the look-alikes `0 O 1 l I` excluded. Flags:

| Flag | Effect |
|---|---|
| `--length <n>` | 1–1024, default 20 |
| `--count <n>` / `-c` | how many to print (default 1) |
| `--no-lowercase` / `--no-uppercase` / `--no-digits` / `--no-symbols` | drop a character class |
| `--allow-ambiguous` | keep `0 O 1 l I` |

The entropy line (`~N bits`) goes to **stderr**, so `passfort-cli gen | pbcopy` copies only the
password. An impossible policy (every class off, `--length` too short to fit one of each class, an
empty symbol set) fails with a message rather than a bad password.

The same generator backs `add --generate-password` and `edit --generate-password`, with the same
shaping flags:

```text
$ passfort-cli add demo.sqlite --title Router --generate-password --length 28 --no-symbols
generated password: sZno8fgUpVHHX7iH6NMDqccfyF8m
Vault password:
E15CE885-8D8F-4D59-A988-A598B894A402

$ passfort-cli edit demo.sqlite Router --generate-password --length 40
generated password: cqBJ4U@,Dyg)PvVS,Cz28k!WwL@PxrPL&eT?EpPg
Vault password:
updated E15CE885-8D8F-4D59-A988-A598B894A402 -> version 2
```

The generated value prints to **stderr** (so `add`'s stdout stays just the UUID); the account is
otherwise created / updated exactly as in §4.1 / §4.3.

### 4.6 See an account's history

Every `add` / `edit` / `rm` bumps the account's `version`. `passfort-cli history` shows what changed
at each one:

```text
$ passfort-cli history demo.sqlite GitHub
Vault password:
GitHub  (01E9C43F-8EE2-4BA4-ACA6-0B503573CF9E, currently v3)
  v3  2026-09-02T13:57:18Z  password
  v2  2026-09-02T13:57:18Z  username, favorite
  v1  2026-09-02T13:57:17Z  created

previous passwords (1):
  2026-09-02T13:57:18Z  (hidden -- pass --passwords)
```

Two things are recorded, automatically, inside the sealed payload (so they sync and export like any
other field):

- **Revision history** — one line per version: which *field names* changed, and when. **Names only,
  never the values** — the log stays small and doesn't scatter secrets across dozens of entries.
  `create` writes `created`, `rm` writes `deleted`. A no-op `edit` (nothing actually changed) records
  nothing. Capped at the last 50; older entries drop off.
- **Password history** — the *old password values*, kept so a backup from before a rotation stays
  openable. Hidden by default; `--passwords` prints them (a secret, gated the same way `get` is):

```text
$ passfort-cli history demo.sqlite GitHub --passwords
…
previous passwords (1):
  2026-09-02T13:57:18Z  first-pw
```

Capped at the last 24. `get` shows the summary (`pw changed`, `revisions`, `old passwords`);
`history` is the full timeline; `dump` / `export` carry both arrays in full.

**Checkpoint for §4:** `add` then `list` shows the row; `get` shows the secret you stored and the
`updated` / `revisions` lines; `edit` takes it to version 2; `history` lists v1→v2 with the changed
fields; `rm` hides it from `list` but `list --all` still shows it flagged `[deleted]`; `gen` prints a
password and `add --generate-password` stores one.

---

## 5. Bulk inspect and escape the format

### 5.1 `dump` — everything, decrypted (debug aid)

```text
$ passfort-cli dump demo.sqlite
Vault password:
dumping 1 record(s) -- plaintext secrets follow
[
  {
    "id" : "01A28F89-B4F0-467E-9F8E-4505E067E16D",
    "is_deleted" : false,
    "payload" : { "category" : "login", "created_at" : "…", "title" : "Bank", "username" : "me01",
                  "revision_history" : [ { "at" : "…", "changed" : ["created"], "version" : 1 } ],
                  "schema_version" : 1 },
    "updated_at" : "…",
    "version" : 1
  }
]
```

`dump` decrypts **every** record (tombstones included) and prints a JSON array to stdout — the same
`{id, version, updated_at, is_deleted, payload}` shape as `get --json`. It is a debugging aid — no
confirmation, straight to the terminal — so use it in a scratch directory, not over a shared screen.

### 5.2 `export` — the sanctioned escape hatch (§7.6)

```text
$ passfort-cli export demo.sqlite -o export.json
This writes every password in the clear to export.json.
Type "EXPORT PLAINTEXT" to continue:EXPORT PLAINTEXT
Vault password:
wrote 2 account(s) to export.json (mode 0600). Delete it when you are done.
```

`export` is `dump` with guard rails: you must type the exact phrase `EXPORT PLAINTEXT` (read from
stdin, not a password prompt), the output goes to a file created `0600` that must not already exist,
and the file carries the vault UUID and an `exported_at` timestamp so it is a complete, dated
snapshot. This exists because the format is ours — "escaping the format is always possible" (§1.3) is
a design promise, and a tested way out is mandatory.

```json
{
  "accounts" : [
    { "id" : "…", "is_deleted" : true,  "payload" : { … }, "updated_at" : "…", "version" : 2 },
    { "id" : "…", "is_deleted" : false, "payload" : { … }, "updated_at" : "…", "version" : 1 }
  ],
  "exported_at" : "2026-09-02T05:05:12Z",
  "schema_version" : 1,
  "vault_uuid" : "…"
}
```

**Delete `export.json` when you are done with it** — nothing does that for you.

---

## 6. Integrity and anti-rollback

### 6.1 `verify` — is this vault intact and current?

```text
$ passfort-cli verify demo.sqlite
Vault password:
verify OK -- manifest and vault_version consistent
```

`verify` does exactly two checks and nothing else:

1. **Anti-rollback:** is the file's `vault_version` at least the value in the `.hw` sidecar? If the
   file is *behind*, someone rolled it back (or restored a backup) — §6.2.
2. **Manifest MAC:** re-derive the HMAC over every row in UUID order and compare it to the stored MAC.
   If a row was added, deleted, or edited outside a proper transaction, this fails.

`unlock` runs the same checks and additionally reports the account counts; `verify` is the
minimal "just tell me if it's sound" command.

### 6.2 The restore-from-backup drill

This is the M2 exit criterion — worth doing once by hand so you trust it.

```text
$ passfort-cli init v.sqlite --target-ms 150
  … (password prompts) …
created v.sqlite (64 MiB Argon2id)

$ passfort-cli add v.sqlite --title Bank --username me01
Vault password:
01A28F89-B4F0-467E-9F8E-4505E067E16D

# Back up the DATABASE files (.sqlite + any -wal / -shm). Not the .hw sidecar —
# that is this machine's "high-water" bookmark; a real backup wouldn't carry it.
$ mkdir backup && cp v.sqlite v.sqlite-wal v.sqlite-shm backup/ 2>/dev/null; ls backup/
v.sqlite      v.sqlite-shm  v.sqlite-wal

# Move the vault forward.
$ passfort-cli add v.sqlite --title Email --username me02
Vault password:
2094D814-5B7E-4567-A2DB-3544EF5B04BD

# "Restore" the older copy — indistinguishable from an attacker rolling the file back.
$ rm -f v.sqlite-wal v.sqlite-shm && cp backup/* .

$ passfort-cli verify v.sqlite
Vault password:
Error: rollback detected -- the file is at vault_version 1 but this machine last saw 2. A restored
backup and an attacker rolling the file back look the same from inside the file. If you deliberately
restored a backup, run:

    passfort-cli verify v.sqlite --accept-restore
```

The file is internally consistent — its row and its MAC agree. What gives the rollback away is the
`v.sqlite.hw` sidecar, which you did **not** restore and which still says `2`. The check is cheap and
runs before the MAC recompute.

```text
$ passfort-cli verify v.sqlite --accept-restore
anti-rollback mark cleared; re-verifying...
Vault password:
verify OK -- manifest and vault_version consistent

$ passfort-cli verify v.sqlite
Vault password:
verify OK -- manifest and vault_version consistent
```

`--accept-restore` deletes the `.hw` sidecar, then re-runs the open — which passes the rollback check
(the mark is now `0`) and, having verified the MAC, **repairs the mark forward** to the restored
file's version. It is a deliberate, one-line act; there is no separate `restore` subcommand precisely
because accepting a rollback should feel deliberate.

### 6.3 `recover` — you forgot the master password

Only possible if the vault was created with `--recovery`. On `init --recovery` you saw:

```text
================================================================
RECOVERY KEY -- write it down now and store it offline. Shown once.
It unlocks this vault without the master password; anyone who has it
can open the vault.

    7C8F-AVFM-HWKC-FVYB-TKBN-16NG-CRQS-9RM6-QQDG-EP87-49JF-1BMJ-76BG-3

================================================================
```

That is 256 bits of CSPRNG output in Crockford Base32 — 13 groups of four symbols, a hyphen, then a
**check symbol** (the last character; it can be `0-9`, `A-Z` minus `I L O U`, or one of `* ~ $ = U`).
The banner goes to **stderr**, so piping stdout stays clean. To use it:

```text
$ passfort-cli recover v.sqlite --key 7C8F-AVFM-HWKC-FVYB-TKBN-16NG-CRQS-9RM6-QQDG-EP87-49JF-1BMJ-76BG-3
New vault password:
Repeat password:
recovered v.sqlite -- master password reset.

================================================================
RECOVERY KEY -- write it down now and store it offline. Shown once.
…
    7C4E-Y4ZK-8WMJ-NEPS-A7ET-7Q6D-CHCP-C0GZ-BPWA-Z8AE-8GA2-GM7C-YN50-$
================================================================
```

`recover` opens the DEK through the recovery slot, re-wraps it under the new password, and writes the
new header. The DEK — and therefore every record — is untouched. The **old recovery slot is
consumed**, so `recover` immediately rotates in a fresh key and prints it; write the new one down. The
old master password no longer opens the vault:

```text
$ passfort-cli unlock v.sqlite     # with the OLD password
Vault password:
Error: AuthFailed -- wrong password or corrupt vault
```

The key input is forgiving: case-insensitive, hyphens and spaces optional, `I`/`L` read as `1` and
`O` as `0`. A one-symbol slip fails the check symbol and is rejected as malformed, not silently
mis-decoded.

---

## 7. Crypto self-tests (no vault needed)

### 7.1 `bench` — what does Argon2id cost on this machine?

```text
$ passfort-cli bench --target-ms 250
kdf          argon2id
memory       65536 KiB (64 MiB)
iterations   3
parallelism  4
calibration  0.510308084 seconds
one unlock   0.514335500 seconds
```

`bench` runs the same calibration `init` uses, then creates a throwaway in-memory header and times one
real unlock against it. Use it to pick a sensible `--target-ms` for your hardware, or to sanity-check
that a machine isn't so slow the KDF becomes painful.

### 7.2 `seam` — is the whole C++ ↔ Swift stack wired up?

```text
$ passfort-cli seam
seam OK -- 19 bytes round-tripped through C++
botan Botan 3.13.0 (unreleased, revision git:2a81eef56c96c237e590c27f9a75e60317c9c700)
M1 seam OK
```

`seam` is the M0 + M1 smoke test: it bounces bytes through the C++ boundary, prints the linked Botan
version, then calibrates → creates → opens a session → seals → opens a record → confirms a mismatched
record id yields `AuthFailed`. If this passes, the seam is intact. It is the fastest "did I break the
build" check.

---

## 8. Run the automated test suites

The CLI walkthrough above is the *manual* confidence check. The real coverage is in the test suites —
run these at every runbook checkpoint and before every commit.

### 8.1 Swift — the seam, the vault, the storage invariants

```bash
cd Packages/PassFortKit
swift build                                       # also builds the pf-killtest helper
swift test                                        # every Swift target — ~56 tests, 10 suites
```

Useful filters (Swift Testing / XCTest name match):

```bash
swift test --filter PFCryptoBoundaryTests         # the seam fuzz suite (null / zero / huge / closed-session)
swift test --filter VaultRepositoryTests          # CRUD, tombstones, one-transaction-per-write, anti-rollback
swift test --filter VaultManifestTests            # manifest MAC: determinism, tamper, rollback
swift test --filter MidWriteKillTests             # the §8.2 kill test — spawns pf-killtest and _exit()s it mid-write
swift test --filter MigrationTests                # the checked-in v1 fixture vault still migrates (§13.4)
swift test --filter RecoveryKeyTests              # Crockford Base32 round-trip, check symbol, grouped form
```

The kill test needs the helper binary. `swift build` produces it at `.build/debug/pf-killtest`; the
test finds it there, or via `PF_KILLTEST_BIN` if you set it (CI does). If you see "pf-killtest not
found", run `swift build` first.

### 8.2 Native — RFC known-answer tests, tamper tests, seam fuzz over the C++ internals

```bash
# from the repo root
cmake -S native-tests -B native-tests/build
cmake --build native-tests/build
ctest --test-dir native-tests/build --output-on-failure
```

Filter by name:

```bash
ctest --test-dir native-tests/build -R kat        # RFC 9106 / 8439 / 5869 known-answer tests
ctest --test-dir native-tests/build -R tamper     # flip one bit in nonce/ct/tag/AAD/header -> AuthFailed
ctest --test-dir native-tests/build -R recovery   # the §5.6 header slot + pf_recovery_wrap/open
```

Under the sanitizers (a separate, uncached build dir — this is what CI's `native` job runs second):

```bash
cmake -S native-tests -B native-tests/build-san \
  -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"
cmake --build native-tests/build-san
ctest --test-dir native-tests/build-san --output-on-failure
```

### 8.3 Lint

```bash
cd Packages/PassFortKit
swift format lint --strict --recursive Sources Tests      # Swift — must be clean

# C++ — one file per invocation (clang-format 23.1.0 mangles a long argv, see CLAUDE.md)
git ls-files '*.cpp' '*.hpp' | grep -v '/vendor/' | xargs -n1 clang-format --dry-run -Werror
```

### 8.4 The whole CI pipeline, locally

CI (`.github/workflows/ci.yml`) runs five jobs: `swift`, `native`, `lint`, `secrets`, `deps`. To
reproduce the important ones before pushing:

```bash
# swift job
cd Packages/PassFortKit && swift build && swift test && swift format lint --strict --recursive Sources Tests
# native job
cmake -S native-tests -B native-tests/build && cmake --build native-tests/build && \
  ctest --test-dir native-tests/build --output-on-failure
# deps job — Package.resolved must not drift
cd Packages/PassFortKit && swift package resolve && git diff --exit-code Package.resolved
```

`secrets` (gitleaks) is also enforced by a pre-commit hook, so a clean commit already passed it.

**Checkpoint for §8:** `swift test` green, `ctest` green (both plain and `-san`), `swift format lint`
clean.

---

## 9. Command reference

| Command | Prompts | Writes | Purpose |
|---|---|---|---|
| `bench [--target-ms N]` | — | — | calibrate Argon2id, time one unlock |
| `seam` | — | — | M0 + M1 seam smoke test |
| `gen [--length N] [--count K] [--no-symbols …]` | — | — | print random password(s), no vault |
| `init <vault> [--recovery] [--force] [--target-ms N]` | new password ×2 | vault + `.hw` | create a vault |
| `unlock <vault>` | password | `.hw` (repair only) | open + verify + report counts |
| `verify <vault> [--accept-restore]` | password | `.hw` (on `--accept-restore`) | manifest + anti-rollback check only |
| `add <vault> --title T [--prompt-password \| --generate-password] […]` | password (+ account pw if `--prompt-password`) | one row + MAC | create an account |
| `list <vault> [--search Q] [--all]` | password | — | summary index, no secrets |
| `get <vault> <id\|title> [--json]` | password | — | one account + audit lines; `--json` wraps `{id, version, updated_at, is_deleted, payload}` |
| `history <vault> <id\|title> [--passwords]` | password | — | version timeline (changed fields per version); `--passwords` reveals old password values |
| `edit <vault> <id\|title> --set k=v … [--add-url U] [--prompt-password \| --generate-password]` | password | one row + MAC | update an account |
| `rm <vault> <id\|title>` | password | one row + MAC | tombstone an account |
| `dump <vault>` | password | — | every record decrypted, JSON, stdout |
| `export <vault> -o FILE` | phrase, then password | `FILE` (0600) | plaintext snapshot of the whole vault |
| `recover <vault> --key GROUPED` | new password ×2 | header + fresh recovery slot | reset the master password via the recovery key |

### Error messages you may hit

| Message | Meaning |
|---|---|
| `AuthFailed -- wrong password or corrupt vault` | wrong master password, or a tampered header. A decrypt failure and a wrong password are deliberately indistinguishable (§13.1) — no oracle. |
| `rollback detected -- the file is at vault_version X but this machine last saw Y` | the file is behind the `.hw` mark — a restored backup or a rollback. Use `verify --accept-restore` if it was you. |
| `manifest MAC mismatch -- a record was added, removed, or edited outside PassFort` | the row set does not match the stored MAC. The vault is not safe to use. |
| `<path> is not a PassFort vault (no header row)` | the SQLite file exists but has no `vault_meta['header']`. |
| `"<ref>" matches N accounts -- narrow it or pass the id` | title resolution was ambiguous. |
| `recovery key rejected -- wrong key` / `this vault has no recovery slot` | `recover` failed — wrong key, or the vault was created without `--recovery`. |

---

## 10. A clean-room script for the whole thing

Drop this in a scratch directory to exercise every path in one go (low KDF cost for speed — never do
that with a real vault):

```bash
set -e
V=scratch.sqlite
rm -f "$V"*

passfort-cli gen --length 24                          # standalone generator, no vault

# You will be prompted for the master password on each line below.
passfort-cli init   "$V" --target-ms 50
ID=$(passfort-cli add "$V" --title "Example" --username alice --generate-password \
       --url https://example.com --tag demo)          # generated pw -> stderr; UUID -> $ID
passfort-cli list   "$V"
passfort-cli get    "$V" "$ID"
passfort-cli edit   "$V" "$ID" --generate-password --set favorite=true
passfort-cli get    "$V" Example --json
passfort-cli history "$V" "$ID"                       # v1 created -> v2 fav -> v3 password
passfort-cli verify "$V"

mkdir -p bak && cp "$V" "$V"-wal "$V"-shm bak/ 2>/dev/null    # backup the db family at v2 (not .hw)
passfort-cli edit   "$V" "$ID" --set notes="moved on"        # -> v3
rm -f "$V"-wal "$V"-shm && cp bak/* .                        # roll the file back to v2
passfort-cli verify "$V"           || true                   # -> rollback detected (.hw still says v3)
passfort-cli verify "$V" --accept-restore                    # -> OK, mark repaired forward

passfort-cli rm     "$V" "$ID"
passfort-cli list   "$V" --all
passfort-cli dump   "$V"
passfort-cli export "$V" -o scratch-export.json    # type EXPORT PLAINTEXT when asked
rm -rf "$V"* bak scratch-export.json               # clean up secrets
```

---

## Where this leaves you

You have driven the entire M0–M2 stack from the command line: created an encrypted vault, done full
CRUD, verified the manifest, survived a simulated rollback, and recovered a lost password. Everything
the GUI will do in M3 already works here — the GUI is a second front end onto the same
`VaultRepository`, not new capability. Next: `m3-gui.md`.
