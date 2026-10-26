import ArgumentParser
import Foundation
import PassFortVault

#if canImport(AppKit)
  import AppKit
#endif

// MARK: - copy

struct Copy: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Put an account's password (or username, or one-time code) on the clipboard.",
    discussion: """
      Nothing goes to stdout. The copy is hidden from clipboard managers and cleared once it is \
      pasted, after --clear-after seconds, or on Ctrl-C. The command waits until then.
      """)

  enum Field: EnumerableFlag {
    case password, username, code
  }

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String
  @Flag(help: "Which field to copy.") var field: Field = .password
  @OptionGroup var clipboard: ClipboardOptions

  func run() async throws {
    let payload = try await clipboard.payload(of: account, in: vault)
    let value: String?
    switch field {
    case .password: value = payload.password
    case .username: value = payload.username ?? payload.email
    case .code: value = payload.totp?.code()
    }
    guard let value, !value.isEmpty else {
      throw CLIError("\(payload.title) has no \(field.name) saved")
    }
    try await clipboard.run([(field.name, value)])
  }
}

extension Copy.Field {
  var name: String { self == .code ? "one-time code" : "\(self)" }
}

// MARK: - fill

struct Fill: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open an account's website, then put its username and its password on the "
      + "clipboard, one per paste.",
    discussion: """
      Paste the username, move to the password field, paste again; the clipboard then clears. \
      Press Enter to move on without pasting. Nothing goes to stdout. Only http and https \
      addresses are opened. Each value is hidden from clipboard managers and cleared after \
      --clear-after seconds unpasted, or on Ctrl-C.
      """)

  @Argument(help: "Path to the vault file.") var vault: String
  @Argument(help: "Account id (UUID) or title.") var account: String
  @Flag(help: "Don't open the website, only fill the clipboard.") var noOpen = false
  @OptionGroup var clipboard: ClipboardOptions

  func run() async throws {
    let payload = try await clipboard.payload(of: account, in: vault)
    let steps = [("username", payload.username ?? payload.email), ("password", payload.password)]
      .compactMap { label, value in value.flatMap { $0.isEmpty ? nil : (label, $0) } }
    guard !steps.isEmpty else {
      throw CLIError("\(payload.title) has no username or password saved")
    }
    try await clipboard.run(steps, opening: noOpen ? nil : payload.website)
  }
}

// MARK: - The clipboard session

/// What `copy` and `fill` share: the clear delay, and the waiting.
struct ClipboardOptions: ParsableArguments {
  @Option(help: "Seconds an unpasted value stays on the clipboard.")
  var clearAfter: Int = 20

  /// A private named pasteboard instead of the real clipboard -- for testing the commands
  /// without touching the user's clipboard.
  @Option(help: .hidden) var pasteboard: String?

  func validate() throws {
    guard clearAfter > 0 else { throw ValidationError("--clear-after must be positive") }
  }

  /// Open `vault` and decrypt `reference`'s payload.
  func payload(of reference: String, in vault: String) async throws -> AccountPayload {
    let repo = try await VaultCLI.open(vault)
    let id = try await resolveAccountID(reference, in: repo)
    guard let account = try await repo.account(id: id) else {
      throw CLIError("no account with id \(id.uuidString)")
    }
    return account.payload
  }

  @MainActor
  private func makeClipboard() throws -> any Clipboard {
    #if canImport(AppKit)
      return MacClipboard(board: pasteboard.map { NSPasteboard(name: .init($0)) } ?? .general)
    #else
      throw CLIError(
        "copy and fill need the macOS clipboard for now (WSL2: m6-portable-cli.md Phase 7) "
          + "-- use `get` or `code`")
    #endif
  }

  /// Open `site`, if given, then offer each `(label, value)` in turn until it is pasted (or Enter
  /// is pressed), then clear. Stops and clears on Ctrl-C (exit 130) or when a value goes
  /// unpasted for `clearAfter`.
  @MainActor
  func run(_ steps: [(label: String, value: String)], opening site: URL? = nil) async throws {
    let board = try makeClipboard()
    if let site {
      try openInBrowser(site)
      note("Opened \(site.host() ?? site.absoluteString)")
    }
    let (events, input) = AsyncStream.makeStream(of: ClipEvent.self)
    let interrupt = watchInterrupt(input)
    defer { interrupt.cancel() }
    watchEnter(input)

    for (index, step) in steps.enumerated() {
      board.offer(step.value) { input.yield(.pasted(index)) }
      let next = index + 1 < steps.count ? "; Enter skips to the \(steps[index + 1].label)" : ""
      note("\(step.label.prefix(1).uppercased())\(step.label.dropFirst()) ready -- paste it\(next)")
      let timeout = Task {
        try? await Task.sleep(for: .seconds(clearAfter))
        if !Task.isCancelled { input.yield(.timeout(index)) }
      }
      defer { timeout.cancel() }

      // Ignore what an earlier step's paste or timer sends late.
      var event: ClipEvent?
      for await candidate in events where candidate.belongs(to: index) {
        event = candidate
        break
      }
      switch event {
      case .pasted:
        // Hand the value over before replacing it (see `Pasteboard.advanceDelay` in the app).
        try? await Task.sleep(for: .milliseconds(250))
      case .enter:
        break
      case .timeout:
        board.clear()
        note("Cleared -- nothing pasted for \(clearAfter) s.")
        return
      case .interrupt, nil:
        board.clear()
        note("Cleared.")
        throw ExitCode(130)
      }
    }
    board.clear()
    note("Clipboard cleared.")
  }
}

private enum ClipEvent {
  case pasted(Int)
  case timeout(Int)
  case enter
  case interrupt

  func belongs(to step: Int) -> Bool {
    switch self {
    case .pasted(let index), .timeout(let index): index == step
    case .enter, .interrupt: true
    }
  }
}

/// Ctrl-C clears instead of leaving a secret behind.
private func watchInterrupt(_ input: AsyncStream<ClipEvent>.Continuation) -> DispatchSourceSignal {
  signal(SIGINT, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  source.setEventHandler { input.yield(.interrupt) }
  source.resume()
  return source
}

/// Each line on stdin moves on. Without a terminal (stdin at EOF) only pastes and the timer do.
private func watchEnter(_ input: AsyncStream<ClipEvent>.Continuation) {
  Thread.detachNewThread {
    while readLine() != nil { input.yield(.enter) }
  }
}

/// Progress goes to stderr; the commands print nothing to stdout.
private func note(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

private func openInBrowser(_ url: URL) throws {
  #if canImport(AppKit)
    guard NSWorkspace.shared.open(url) else { throw CLIError("couldn't open \(url)") }
  #else
    throw CLIError("can't open a browser here -- pass --no-open")
  #endif
}

// MARK: - Clipboards

/// Where `copy` and `fill` put secrets: the macOS pasteboard, and in WSL2 the Windows clipboard
/// (`m6-portable-cli.md` Phase 7).
@MainActor
protocol Clipboard {
  /// Put `value` there, hidden from clipboard managers, and call `pasted` when an app pastes it
  /// -- if this clipboard can tell. Replaces whatever was offered before.
  func offer(_ value: String, pasted: @escaping @Sendable () -> Void)
  /// Remove the last offer, if it is still what's on the clipboard.
  func clear()
}

#if canImport(AppKit)
  /// The macOS pasteboard, as the app uses it: the concealed type (nspasteboard.org), and the
  /// value only *promised* -- handed over when an app pastes it, which is how `fill` knows to
  /// move on.
  final class MacClipboard: NSObject, Clipboard, NSPasteboardItemDataProvider {
    private static let concealedType = NSPasteboard.PasteboardType(
      "org.nspasteboard.ConcealedType")

    private let board: NSPasteboard
    private var value: String?
    private var pasted: (@Sendable () -> Void)?
    private var stamp: Int?

    init(board: NSPasteboard) { self.board = board }

    func offer(_ value: String, pasted: @escaping @Sendable () -> Void) {
      self.value = value
      self.pasted = pasted
      let item = NSPasteboardItem()
      item.setString("", forType: Self.concealedType)  // the convention needs only the type
      item.setDataProvider(self, forTypes: [.string])
      board.clearContents()
      board.writeObjects([item])
      stamp = board.changeCount
    }

    func clear() {
      if board.changeCount == stamp { board.clearContents() }
      value = nil
      stamp = nil
    }

    // AppKit calls this on the main thread.
    nonisolated func pasteboard(
      _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
      provideDataForType type: NSPasteboard.PasteboardType
    ) {
      let value = MainActor.assumeIsolated { () -> String? in
        defer {
          pasted?()
          pasted = nil
        }
        return self.value
      }
      if let value { item.setString(value, forType: type) }
    }

    nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
  }
#endif
