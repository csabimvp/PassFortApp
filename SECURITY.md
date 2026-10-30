# Security

PassFort is a personal project. It has not been independently audited. Use it knowing that, and keep
an export or a backup of anything you can't afford to lose.

## Reporting a vulnerability

Please report it privately through GitHub: the repository's **Security** tab, then
**Report a vulnerability**. Don't open a public issue for it.

Useful to include: what an attacker can do, what they need first (a copy of the vault file, access
to the unlocked Mac, control of the sync server), and the steps or a test that shows it. Expect a
reply within a couple of weeks; this is maintained in spare time.

## What the design defends against

The threat model is `docs/architecture.md` §3. In short:

- **A stolen vault file.** Every record, titles and usernames included, is sealed with
  XChaCha20-Poly1305 under a key that only the master password (through Argon2id) or the recovery
  key unwraps. A manifest MAC and a version counter catch a deleted, swapped or rolled-back record.
- **A hostile sync server.** The server only ever sees sealed records and a hash of an auth key
  derived from the vault key. It can't read, forge or roll back records. It can withhold or delay
  other devices' updates, and it sees metadata: record count, sizes and update times. Every client
  pins the server's certificate authority: the apps through the system's TLS, and the CLI on
  Linux and WSL2 through libcurl and OpenSSL. A pin that doesn't match stops sync.
- **No error-message oracle.** A wrong password and a tampered record fail the same way.
- **Keys stay in one place.** Key material lives only in the C++ core, is wiped on lock, and is
  kept out of swap where the OS allows locking memory (macOS and Linux both do by default).

## What it does not defend against

Listed in §3.3 and §3.4. The main ones: a compromised OS, root-level malware or a keylogger;
someone with a debugger on the running, unlocked app; and decrypted values held in memory while the
vault is unlocked (Swift can't reliably wipe them). Argon2id slows down guessing a weak master
password; it can't make one strong.

The CLI shows plaintext wherever it runs, so terminal scrollback and the machine itself see what you
open. On Linux its TLS doesn't check certificate revocation; the pins narrow what a revoked
certificate could do.
