import Foundation
import Testing

@testable import passfort_cli

/// The WSL2 clipboard's PowerShell side (`m6-portable-cli.md` Phase 7), as far as it can be checked
/// without Windows: what goes in argv, what goes on stdin, and what the scripts ask .NET for. The
/// clipboard itself is checked by hand on the Windows PC.
@Suite struct WindowsClipboardScriptTests {

  private let secret = "Pässwörd-ŐűÉ-€-日本語-🔑-\"q\"-$x-&-%PATH%"

  @Test func theScriptTravelsAsUTF16LEBase64() throws {
    for script in [WindowsClipboardScript.set, WindowsClipboardScript.clear] {
      let bytes = try #require(Data(base64Encoded: WindowsClipboardScript.encodedCommand(script)))
      #expect(String(data: bytes, encoding: .utf16LittleEndian) == script)
    }
  }

  @Test func argvCarriesTheScriptButNeverTheValue() {
    let arguments = WindowsClipboardScript.arguments(for: WindowsClipboardScript.set)
    #expect(
      Array(arguments.prefix(4)) == ["-NoProfile", "-NonInteractive", "-STA", "-EncodedCommand"])
    #expect(arguments.count == 5)
    let joined = arguments.joined(separator: " ")
    #expect(!joined.contains(secret))
    #expect(!joined.contains(Data(secret.utf8).base64EncodedString()))
    #expect(!WindowsClipboardScript.set.contains(secret), "the script is fixed; the value is stdin")
  }

  @Test func stdinIsASCIIBase64OfTheUTF8() throws {
    let input = WindowsClipboardScript.input(for: secret)
    #expect(input.allSatisfy { $0 < 0x80 }, "the console code page can't touch ASCII")
    let line = try #require(String(data: input, encoding: .ascii))
    #expect(line.hasSuffix("\n"))
    let decoded = try #require(Data(base64Encoded: line.trimmingCharacters(in: .newlines)))
    #expect(String(decoding: decoded, as: UTF8.self) == secret)
  }

  @Test func theCopyIsKeptOutOfHistoryAndTheCloud() {
    let script = WindowsClipboardScript.set
    for format in [
      "ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory",
      "CanUploadToCloudClipboard",
    ] {
      #expect(script.contains("'\(format)'"), "\(format)")
    }
    #expect(
      script.contains("[byte[]]$zero = 0, 0, 0, 0"), "a DWORD 0: may not include, may not upload")
    #expect(script.contains("SetDataObject($data, $true)"), "flushed, so it outlives PowerShell")
    #expect(script.contains("[Console]::In.ReadToEnd()"))
    #expect(WindowsClipboardScript.clear.contains("[System.Windows.Forms.Clipboard]::Clear()"))
  }

  @Test func promptsSayWhatEnterDoes() {
    #expect(
      ClipboardOptions.prompt(following: "password", noticesPastes: true)
        == "; Enter skips to the password")
    #expect(ClipboardOptions.prompt(following: nil, noticesPastes: true) == "")
    #expect(
      ClipboardOptions.prompt(following: "password", noticesPastes: false)
        == ", then press Enter for the password")
    #expect(
      ClipboardOptions.prompt(following: nil, noticesPastes: false)
        == ", then press Enter to clear it")
  }
}
