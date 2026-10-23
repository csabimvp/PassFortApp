import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PassFort

/// The vault window's layout, measured on a real window: `VaultListView` hosted with its toolbar,
/// the way the `WindowGroup` shows it.
@MainActor
struct VaultListLayoutTests {

  /// The window, its split view and the drawn toolbar separators, once SwiftUI has built them.
  private struct Hosted {
    let window: NSWindow
    let split: NSSplitView
    /// Every drawn toolbar separator's x, in window coordinates.
    let separators: () -> [CGFloat]
  }

  private func host() async throws -> Hosted {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1240, height: 720),
      styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    let model = AppModel(databasePath: "/tmp/pf-layout-\(UUID().uuidString).sqlite")
    let view = NSHostingView(rootView: VaultListView().environment(model))
    view.sceneBridgingOptions = [.toolbars, .title]
    window.contentView = view
    window.orderFront(nil)

    let frame = try #require(window.contentView?.superview)
    for _ in 0..<40 {  // up to ~4 s for SwiftUI to build the split view and its toolbar
      if let split = Self.first(NSSplitView.self, in: frame), split.arrangedSubviews.count == 3,
        !Self.separatorXs(in: frame).isEmpty
      {
        return Hosted(window: window, split: split, separators: { Self.separatorXs(in: frame) })
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    window.close()
    Issue.record("The window never showed a three-column split view with toolbar separators")
    throw CancellationError()
  }

  /// The list column's divider and the separator above it in the toolbar must be one line, even
  /// with the column at its narrowest -- a width that is also restored at the next launch.
  @Test func theToolbarSeparatorLinesUpWithTheListDividerAtItsNarrowest() async throws {
    let hosted = try await host()
    defer { hosted.window.close() }

    hosted.split.setPosition(0, ofDividerAt: 1)  // a drag past the minimum clamps to it
    try await Task.sleep(for: .milliseconds(500))
    hosted.window.layoutIfNeeded()

    let list = hosted.split.arrangedSubviews[1]
    let divider = list.convert(list.bounds, to: nil).maxX
    let separator = try #require(hosted.separators().max())
    #expect(
      abs(separator - divider) <= 1, "toolbar separator at \(separator), divider at \(divider)")
  }

  // MARK: - View tree

  private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for sub in view.subviews {
      if let match = first(type, in: sub) { return match }
    }
    return nil
  }

  /// AppKit draws a toolbar's tracking separators with a private view class; matching its name is
  /// the only way to find where one is drawn. If a macOS release renames it, the test fails in
  /// `host()` rather than passing without measuring anything.
  private static func separatorXs(in view: NSView) -> [CGFloat] {
    var found: [CGFloat] = []
    if String(describing: type(of: view)) == "NSSeparatorToolbarItemView", !view.isHidden {
      found.append(view.convert(view.bounds, to: nil).minX)
    }
    for sub in view.subviews { found += separatorXs(in: sub) }
    return found
  }
}
