import Foundation
import PassFortVault

#if canImport(Darwin)
  import Darwin
#endif

/// Test-only helper for the §8.2 mid-write kill test (runbook Phase 7). It unlocks
/// an existing vault and performs **one** `update`, with a fault hook that calls
/// `_exit(1)` the instant the write reaches the named point — no `atexit`, no
/// flush, no cleanup, exactly like a power cut. The parent process
/// (`MidWriteKillTests`) then reopens the vault and asserts it is still consistent.
///
/// Usage: `pf-killtest <db-path> <afterRowWrite|afterMetaWrite|afterCommit>`
/// The vault password is fixed (`killtest`); the parent creates the vault with it.
@main
enum KillTest {
  static func main() async {
    let args = CommandLine.arguments
    guard args.count == 3, let point = FaultPoint(rawValue: args[2]) else {
      fail(
        "usage: pf-killtest <db-path> <\(FaultPoint.allCases.map(\.rawValue).joined(separator: "|"))>"
      )
    }
    let databasePath = args[1]
    let password = Data("killtest".utf8)
    let device = UUID(uuid: (9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9))

    do {
      let repository = try await Vault.unlock(
        databasePath: databasePath, password: password, deviceID: device,
        faultHook: { fired in
          guard fired == point else { return }
          FileHandle.standardError.write(Data("pf-killtest: _exit at \(fired.rawValue)\n".utf8))
          _exit(1)
        })

      guard let target = try await repository.summaries().first else {
        fail("pf-killtest: vault has no records to update")
      }
      _ = try await repository.update(id: target.id) { $0.notes = "killed at \(point.rawValue)" }
    } catch {
      fail("pf-killtest: unexpected error before the fault point: \(error)")
    }

    fail("pf-killtest: update returned without hitting the fault point")
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
  }
}
