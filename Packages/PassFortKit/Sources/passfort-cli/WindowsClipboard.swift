import Foundation

// The Windows clipboard, from WSL2 (`m6-portable-cli.md` Phase 7). The browser runs on Windows, so
// that is where a copy has to land. Reached through Windows interop: `powershell.exe` (Windows
// PowerShell 5.1) with a .NET `DataObject`, never `clip.exe` -- which reads stdin in the console
// code page, mangling a non-ASCII password, and can't keep a copy out of Win+V history or the
// cloud clipboard (the Windows form of §3.2 A5).

// MARK: - The scripts and their framing

/// What runs in `powershell.exe`. Pure, so it's tested on every platform.
enum WindowsClipboardScript {
  /// Reads the value from stdin (base64 of its UTF-8), sets it as text with the three formats
  /// Windows' clipboard history and cloud clipboard honour (present; and DWORD 0 for "may
  /// include" and "may upload"), and flushes it so it outlives the process.
  static let set = """
    Add-Type -AssemblyName System.Windows.Forms
    $b64 = [Console]::In.ReadToEnd().Trim()
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $data = New-Object System.Windows.Forms.DataObject
    $data.SetText($text)
    [byte[]]$zero = 0, 0, 0, 0
    $data.SetData('ExcludeClipboardContentFromMonitorProcessing', [IO.MemoryStream]::new($zero))
    $data.SetData('CanIncludeInClipboardHistory', [IO.MemoryStream]::new($zero))
    $data.SetData('CanUploadToCloudClipboard', [IO.MemoryStream]::new($zero))
    [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
    """

  /// Empties the clipboard, whatever is on it: from WSL there's no cheap way to tell whether the
  /// copy is still ours (the Mac's `changeCount`).
  static let clear = """
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::Clear()
    """

  /// `powershell.exe`'s arguments for `script`. The script travels as `-EncodedCommand` (base64 of
  /// UTF-16LE), so no Windows command-line quoting touches it. It never contains the secret: argv
  /// is visible in the process list on both the Linux and the Windows side.
  static func arguments(for script: String) -> [String] {
    ["-NoProfile", "-NonInteractive", "-STA", "-EncodedCommand", encodedCommand(script)]
  }

  static func encodedCommand(_ script: String) -> String {
    var bytes = Data(capacity: script.utf16.count * 2)
    for unit in script.utf16 {
      bytes.append(UInt8(truncatingIfNeeded: unit))
      bytes.append(UInt8(truncatingIfNeeded: unit >> 8))
    }
    return bytes.base64EncodedString()
  }

  /// What `set` reads on stdin: the value as base64 of its UTF-8. ASCII, so the console code page
  /// can't mangle it.
  static func input(for value: String) -> Data {
    Data((Data(value.utf8).base64EncodedString() + "\n").utf8)
  }
}

// MARK: - The clipboard

#if os(Linux)
  /// `Clipboard` over the Windows clipboard, in WSL2 only (detected by `WSL_DISTRO_NAME`). About
  /// half a second of PowerShell start-up per write. It can't see a paste -- that would need a
  /// Windows process with a message loop to serve delayed rendering -- so `fill` moves on with
  /// Enter.
  final class WindowsClipboard: Clipboard {
    let noticesPastes = false
    private let powershell: URL

    /// `nil` outside WSL2, or when Windows interop can't find `powershell.exe`.
    init?() {
      guard WSL.isRunning, let powershell = WSL.windowsProgram("powershell.exe") else {
        return nil
      }
      self.powershell = powershell
    }

    func offer(_ value: String, pasted: @escaping @Sendable () -> Void) throws {
      try run(WindowsClipboardScript.set, input: WindowsClipboardScript.input(for: value))
    }

    func clear() {
      do {
        try run(WindowsClipboardScript.clear, input: Data())
      } catch {
        FileHandle.standardError.write(
          Data("Couldn't clear the Windows clipboard -- copy something else over it.\n".utf8))
      }
    }

    /// Runs `script`, with `input` on stdin, and waits. Its output is discarded: nothing the
    /// script prints is needed, and an error message is no place for a secret to turn up.
    private func run(_ script: String, input: Data) throws {
      let process = Process()
      process.executableURL = powershell
      process.arguments = WindowsClipboardScript.arguments(for: script)
      let stdin = Pipe()
      process.standardInput = stdin
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      stdin.fileHandleForWriting.write(input)
      try stdin.fileHandleForWriting.close()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw CLIError(
          "powershell.exe couldn't use the Windows clipboard (exit \(process.terminationStatus))")
      }
    }
  }

  /// Windows Subsystem for Linux: detection, and its Windows programs.
  enum WSL {
    static var isRunning: Bool {
      !(ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] ?? "").isEmpty
    }

    /// `name` on the `PATH` (WSL appends the Windows one by default), else at its usual place.
    static func windowsProgram(_ name: String) -> URL? {
      let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
      let usual = [
        "/mnt/c/Windows/System32/WindowsPowerShell/v1.0", "/mnt/c/Windows",
        "/mnt/c/Windows/System32",
      ]
      for directory in path.split(separator: ":").map(String.init) + usual {
        let candidate = URL(filePath: directory).appending(path: name)
        if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
          return candidate
        }
      }
      return nil
    }

    /// Opens `url` in the Windows default browser. `explorer.exe`, not `cmd.exe /c start` (cmd
    /// parses `&` in the URL) or `wslview` (wslu, no longer installed by default). Explorer exits
    /// with 1 even when it worked, so only a failure to start counts.
    static func open(_ url: URL) throws {
      guard let explorer = windowsProgram("explorer.exe") else {
        throw CLIError("can't find explorer.exe -- is Windows interop off? Pass --no-open")
      }
      let process = Process()
      process.executableURL = explorer
      process.arguments = [url.absoluteString]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
    }
  }
#endif
