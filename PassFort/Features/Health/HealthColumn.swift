import PassFortVault
import SwiftUI

/// The middle column for Password Health: the audit's findings, grouped by what is wrong. Holds
/// account ids and kinds only — no password value reaches this view. Selecting a finding shows its
/// account in the detail column.
struct HealthColumn: View {
  @Environment(AppModel.self) private var model
  /// `nil` while the audit runs.
  let findings: [AuditFinding]?
  let query: String
  @Binding var selection: UUID?

  var body: some View {
    Group {
      if let findings {
        let visible = findings.filter { finding in
          model.summaries.first { $0.id == finding.account }.map { matches($0, query: query) }
            ?? false
        }
        if findings.isEmpty {
          ContentUnavailableView(
            "All clear", systemImage: "checkmark.shield",
            description: Text(
              "Nothing weak, reused, old, expiring or on http://.\n\(Self.privacyNote)"))
        } else if visible.isEmpty {
          ContentUnavailableView("No matches", systemImage: "magnifyingglass")
        } else {
          list(visible, score: HealthScore(findings: findings, liveAccounts: liveCount))
        }
      } else {
        ProgressView("Checking…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private static let privacyNote = "Checked on this Mac. Nothing is sent anywhere."

  private var liveCount: Int { model.summaries.count { !$0.isDeleted } }

  /// The score ring and "36 of 42 accounts are fine": the list's first row, so it scrolls with the
  /// findings as the mockup draws it.
  private func summary(_ score: HealthScore) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().stroke(.quaternary, lineWidth: 4)
        Circle()
          .trim(from: 0, to: score.fraction)
          .stroke(score.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 36, height: 36)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(score.fine) of \(score.total) accounts are fine").font(.headline)
        Text(Self.privacyNote).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
  }

  private func list(_ findings: [AuditFinding], score: HealthScore) -> some View {
    List(selection: $selection) {
      summary(score).selectionDisabled()
      ForEach(HealthGroup.allCases) { group in
        let rows = findings.filter { HealthGroup($0.kind) == group }
        if !rows.isEmpty {
          Section {
            ForEach(rows, id: \.self) { finding in
              let summary = model.summaries.first { $0.id == finding.account }
              HStack(spacing: 10) {
                CategoryTile(
                  title: summary?.title ?? "", category: summary?.category ?? .other, size: 24)
                Text(summary?.title ?? "Unknown account").lineLimit(1)
                Spacer()
                Text(HealthGroup.detail(finding.kind))
                  .font(.caption).foregroundStyle(.secondary)
              }
              .tag(finding.account)
            }
          } header: {
            Label {
              Text("\(group.title) (\(rows.count))")
            } icon: {
              Image(systemName: group.symbol).foregroundStyle(group.color)
            }
          }
        }
      }
    }
  }

}

/// How much of the vault the audit found nothing wrong with: every live account not named by a
/// finding. An empty vault scores full, so the ring never shows red for nothing.
struct HealthScore: Equatable {
  let fine: Int
  let total: Int

  init(findings: [AuditFinding], liveAccounts: Int) {
    let flagged = Set(findings.map(\.account)).count
    total = liveAccounts
    fine = max(0, liveAccounts - flagged)
  }

  var fraction: Double { total == 0 ? 1 : Double(fine) / Double(total) }

  /// Success from 80 % fine, warning from half, danger below.
  var color: Color {
    switch fraction {
    case 0.8...: Palette.success
    case 0.5...: Palette.warning
    default: Palette.danger
    }
  }
}

/// The sections the health column shows, in order of how much each matters.
enum HealthGroup: CaseIterable, Identifiable {
  case reused, weak, expired, old, insecureURL

  var id: Self { self }

  init(_ kind: AuditFinding.Kind) {
    switch kind {
    case .reused: self = .reused
    case .weak: self = .weak
    case .expired, .expiringSoon: self = .expired
    case .old: self = .old
    case .insecureURL: self = .insecureURL
    }
  }

  var title: String {
    switch self {
    case .reused: "Reused passwords"
    case .weak: "Weak passwords"
    case .expired: "Expired or expiring"
    case .old: "Not changed in over a year"
    case .insecureURL: "Insecure http:// sites"
    }
  }

  /// Red for what puts an account at risk now, amber for what will or might, grey for age.
  var color: Color {
    switch self {
    case .reused, .weak: Palette.danger
    case .expired, .insecureURL: Palette.warning
    case .old: .secondary
    }
  }

  var symbol: String {
    switch self {
    case .reused: "arrow.triangle.2.circlepath"
    case .weak: "exclamationmark.shield"
    case .expired: "calendar.badge.exclamationmark"
    case .old: "clock.arrow.circlepath"
    case .insecureURL: "lock.open"
    }
  }

  /// The short trailing text on a row.
  static func detail(_ kind: AuditFinding.Kind) -> String {
    let day = Date.FormatStyle(date: .abbreviated, time: .omitted)
    switch kind {
    case .reused(let count): return "used by \(count) accounts"
    case .weak(let score): return "strength \(score)/4"
    case .expired(let on): return "expired \(on.formatted(day))"
    case .expiringSoon(let on): return "expires \(on.formatted(day))"
    case .old(let since): return "since \(since.formatted(day))"
    case .insecureURL: return "http://"
    }
  }
}
