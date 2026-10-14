import AppKit
import KestrelCore
import Testing

@testable import Kestrel

@Test @MainActor func failedCaptureDisableRetainsCaptureAndPendingHistory() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let board = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
    board.clearContents()
  }

  let model = try AppModel(directory: directory, pasteboard: board)
  model.setCapture(true)
  #expect(model.captureEnabled)
  #expect(try model.store.load().captureEnabled)

  try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
  model.acceptClipboardText("Queued while saving is unavailable")
  model.setCapture(false)

  #expect(model.captureEnabled)
  #expect(model.state.captureEnabled)
  #expect(model.errorMessage != nil)
  #expect(try model.store.load().captureEnabled)

  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  model.flushPendingClipboard()
  #expect(
    try model.store.load().history.contains { $0.text == "Queued while saving is unavailable" })

  model.setCapture(false)
  #expect(!model.captureEnabled)
  #expect(!(try AppModel(directory: directory, pasteboard: board)).captureEnabled)
}

@Test @MainActor func failedCaptureEnableRemainsPaused() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let board = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
    board.clearContents()
  }

  let model = try AppModel(directory: directory, pasteboard: board)
  try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
  model.setCapture(true)

  #expect(!model.captureEnabled)
  #expect(!model.state.captureEnabled)
  #expect(model.errorMessage != nil)
  #expect(!(try model.store.load()).captureEnabled)
}

@Test @MainActor func captureChangeNotificationObservesCommittedState() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let board = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: directory)
    board.clearContents()
  }

  let model = try AppModel(directory: directory, pasteboard: board)
  var observedRuntimeCapture: Bool?
  var observedStoredCapture: Bool?
  model.changed = {
    observedRuntimeCapture = model.captureEnabled
    observedStoredCapture = model.state.captureEnabled
  }

  model.setCapture(true)

  #expect(observedRuntimeCapture == true)
  #expect(observedStoredCapture == true)
}
