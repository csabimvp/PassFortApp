import Carbon.HIToolbox

/// A system-wide keyboard shortcut via Carbon's `RegisterEventHotKey` — the one API that delivers
/// a global key combination to a sandboxed app without the Accessibility permission an event tap
/// would need. It sees only the registered combination, never other keystrokes.
///
/// Unregistered on `deinit`. Creation fails (returns `nil`) when another app already owns the
/// combination.
@MainActor
final class GlobalHotKey {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: @MainActor () -> Void

  /// - Parameters:
  ///   - keyCode: a virtual key code (`kVK_Space`, ...).
  ///   - modifiers: Carbon modifier flags (`controlKey | optionKey`, ...).
  init?(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
    self.action = action

    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        // Carbon delivers hot-key events on the main run loop.
        guard let context else { return OSStatus(eventNotHandledErr) }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { hotKey.action() }
        return noErr
      }, 1, &pressed, context, &handler)
    guard installed == noErr else { return nil }

    let id = EventHotKeyID(signature: OSType(0x5046_4851), id: 1)  // 'PFHQ'
    let registered = RegisterEventHotKey(
      UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
    guard registered == noErr else {
      if let handler { RemoveEventHandler(handler) }
      return nil
    }
  }

  isolated deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
  }
}
