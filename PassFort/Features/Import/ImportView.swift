import PassFortVault
import SwiftUI
import UniformTypeIdentifiers

/// Import a Password Safe plain-text export: pick the file, see what would come in (titles only,
/// likely duplicates marked and skipped by default), import in one transaction, then offer to move
/// the export -- every password in plain text -- to the Trash. The parsed plan is plaintext, so it
/// lives only as long as this sheet.
struct ImportView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  private enum Step {
    case choosing
    case preview(ImportPlan, file: URL)
    case done(count: Int, file: URL)
  }

  @State private var step = Step.choosing
  @State private var choosingFile = false
  @State private var skipDuplicates = true
  @State private var working = false
  @State private var error: String?
  @State private var trashed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Import from Password Safe").font(.title3).bold()
      switch step {
      case .choosing: choosing
      case .preview(let plan, let file): preview(plan, file: file)
      case .done(let count, let file): done(count: count, file: file)
      }
      if let error {
        Label(error, systemImage: "xmark.octagon").foregroundStyle(Palette.danger)
      }
    }
    .padding(24)
    .frame(width: 480)
    .disabled(working)
    .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.plainText, .text]) {
      load($0)
    }
    .onAppear { choosingFile = true }
    .onDisappear { step = .choosing }  // drop the plaintext plan with the sheet
  }

  // MARK: - Steps

  private var choosing: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "In Password Safe choose File ▸ Export To ▸ Plain Text, then pick that file here. "
          + "Nothing is written until you confirm."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Choose File…") { choosingFile = true }.keyboardShortcut(.defaultAction)
      }
    }
  }

  private func preview(_ plan: ImportPlan, file: URL) -> some View {
    let duplicates = plan.duplicates(of: model.summaries)
    let chosen = plan.accounts.indices.filter { !skipDuplicates || !duplicates.contains($0) }
    return VStack(alignment: .leading, spacing: 10) {
      Text(file.lastPathComponent).font(.caption).foregroundStyle(.secondary)

      List(plan.accounts.indices, id: \.self) { index in
        let payload = plan.accounts[index].payload
        HStack {
          Text(payload.title)
          if let tag = payload.tags.first {
            Text(tag).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          if payload.totp != nil {
            Image(systemName: "clock").help("Has a one-time code")
          }
          if duplicates.contains(index) {
            Text(skipDuplicates ? "duplicate — skipped" : "duplicate")
              .font(.caption).foregroundStyle(Palette.warning)
          }
        }
      }
      .frame(height: 220)

      if !duplicates.isEmpty {
        Toggle(
          "Skip \(duplicates.count) that look like accounts already here", isOn: $skipDuplicates)
      }
      report(plan)

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Import \(chosen.count) Account\(chosen.count == 1 ? "" : "s")") {
          let payloads = chosen.map { plan.accounts[$0].payload }
          Task { await runImport(payloads, file: file) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(chosen.isEmpty)
      }
    }
  }

  @ViewBuilder
  private func report(_ plan: ImportPlan) -> some View {
    let notes =
      plan.skipped.map { "Line \($0.line) skipped: \($0.reason)." }
      + plan.warnings.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }
      + plan.ignoredColumns.sorted { $0.key < $1.key }.map {
        "“\($0.key)” isn't imported (\($0.value) row\($0.value == 1 ? "" : "s"))."
      }
    if !notes.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(notes, id: \.self) { Text($0) }
      }
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func done(count: Int, file: URL) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Imported \(count) account\(count == 1 ? "" : "s").", systemImage: "checkmark.circle")
        .foregroundStyle(Palette.success)
      Text(
        "“\(file.lastPathComponent)” holds every password in plain text. Move it to the Trash, "
          + "then empty the Trash."
      )
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(trashed ? "Moved to Trash" : "Move Export to Trash") { trash(file) }
          .disabled(trashed)
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
  }

  // MARK: - Actions

  private func load(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      step = .preview(try PasswordSafeImport.plan(try Data(contentsOf: url)), file: url)
      error = nil
    } catch PasswordSafeImport.Failure.notPasswordSafeExport {
      error = "That isn't a Password Safe plain-text export (no Group/Title column)."
    } catch {
      self.error = "Couldn't read that file."
    }
  }

  private func runImport(_ payloads: [AccountPayload], file: URL) async {
    working = true
    defer { working = false }
    if let failure = await model.importAccounts(payloads) {
      error = failure.message
    } else {
      error = nil
      step = .done(count: payloads.count, file: file)
    }
  }

  private func trash(_ file: URL) {
    let scoped = file.startAccessingSecurityScopedResource()
    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
    do {
      try FileManager.default.trashItem(at: file, resultingItemURL: nil)
      trashed = true
    } catch {
      self.error = "Couldn't move it to the Trash -- delete it in Finder."
    }
  }
}

#Preview {
  ImportView()
    .environment(AppModel(databasePath: "/tmp/passfort-preview-nonexistent.sqlite"))
}
