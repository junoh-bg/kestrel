import AppKit
import Carbon

private func kestrelHotKeyCallback(
  _ handler: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let context else { return OSStatus(eventNotHandledErr) }
  MainActor.assumeIsolated { Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action() }
  return noErr
}

@MainActor final class HotKey {
  let action: () -> Void
  private var reference: EventHotKeyRef?
  private var handler: EventHandlerRef?
  init(action: @escaping () -> Void) { self.action = action }
  func register() -> Bool {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    guard
      InstallEventHandler(
        GetApplicationEventTarget(), kestrelHotKeyCallback, 1, &type,
        Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    else { return false }
    let id = EventHotKeyID(signature: 0x4c50_4c54, id: 1)
    let status = RegisterEventHotKey(
      UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0,
      &reference)
    if status != noErr {
      if let handler { RemoveEventHandler(handler) }
      handler = nil
    }
    return status == noErr
  }
  func unregister() {
    if let reference { UnregisterEventHotKey(reference) }
    reference = nil
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }
}
