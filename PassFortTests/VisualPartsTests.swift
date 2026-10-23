import Foundation
import PassFortVault
import Testing

@testable import PassFort

/// The decisions behind the mockup's visual parts: which words and how many bars a strength gets,
/// what a tile shows, how a revealed password is classed, and the health ring's score.
@MainActor
struct VisualPartsTests {

  @Test func strengthLevelsFollowTheScore() {
    #expect(
      [0, 1, 2, 3, 4].map(StrengthLevel.init(score:)) == [
        .weak, .weak, .fair, .strong, .veryStrong,
      ])
    #expect(StrengthLevel.weak.bars == 1)
    #expect(StrengthLevel.veryStrong.bars == 4)
  }

  @Test func everyLevelPasswordHealthReportsIsBelowStrong() {
    for score in 0..<PasswordAudit.weakBelow {
      #expect([.weak, .fair].contains(StrengthLevel(score: score)))
    }
  }

  @Test func commonPasswordIsWeakAndARandomOneIsVeryStrong() {
    #expect(StrengthLevel(password: "password") == .weak)
    #expect(StrengthLevel(password: "vK7#mQ2r!Tx9@pLw4sZe") == .veryStrong)
  }

  @Test func tileInitialSkipsPunctuationAndUppercases() {
    #expect(CategoryTile.initial(of: "github") == "G")
    #expect(CategoryTile.initial(of: "  (prod) db") == "P")
    #expect(CategoryTile.initial(of: "1Password") == "1")
    #expect(CategoryTile.initial(of: "—") == nil)
    #expect(CategoryTile.initial(of: "") == nil)
  }

  @Test func revealedPasswordClassesEachCharacter() {
    let classes = "a7#Ö".map(ClassedPassword.characterClass(of:))
    #expect(classes == [.letter, .digit, .symbol, .letter])
  }

  @Test func healthScoreCountsEachFlaggedAccountOnce() {
    let flagged = UUID()
    let findings = [
      AuditFinding(kind: .weak(score: 1), account: flagged),
      AuditFinding(kind: .reused(count: 2), account: flagged),
      AuditFinding(kind: .insecureURL, account: UUID()),
    ]
    let score = HealthScore(findings: findings, liveAccounts: 10)
    #expect(score.fine == 8)
    #expect(score.total == 10)
    #expect(score.fraction == 0.8)
  }

  @Test func emptyVaultScoresFull() {
    #expect(HealthScore(findings: [], liveAccounts: 0).fraction == 1)
  }
}
