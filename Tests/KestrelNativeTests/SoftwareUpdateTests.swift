import AppKit
import CryptoKit
import KestrelCore
import Testing

@testable import Kestrel

@Test @MainActor func generalSettingsOffersManualAndAutomaticUpdateControls() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let settings = SettingsWindow(
    model: try AppModel(directory: directory, pasteboard: .withUniqueName()))
  func buttons(_ view: NSView) -> [NSButton] {
    (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
  }
  let check = try #require(
    buttons(settings.window.contentView!).first { $0.title == "Check for Updates…" })
  var checks = 0
  var preferences: [Bool] = []
  settings.checkForUpdates = { checks += 1 }
  settings.automaticUpdateChecksChanged = { preferences.append($0) }
  settings.configureUpdates(available: true, automaticallyChecks: false)
  #expect(check.isEnabled)
  check.performClick(nil)
  #expect(checks == 1)
  settings.automaticUpdateChecks.performClick(nil)
  #expect(preferences == [true])
  settings.configureUpdates(available: false, automaticallyChecks: true)
  #expect(!check.isEnabled)
  #expect(settings.automaticUpdateChecks.state == .on)
  #expect(preferences == [true], "Refreshing settings must not write the preference")
}

@Test func committedUpdateFeedHasAValidPublicSignature() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let feed = try String(
    contentsOf: root.appendingPathComponent("docs/updates/appcast.xml"), encoding: .utf8)
  let pattern = try NSRegularExpression(
    pattern: "<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n$")
  let match = try #require(
    pattern.firstMatch(in: feed, range: NSRange(feed.startIndex..., in: feed)))
  let signatureRange = try #require(Range(match.range(at: 1), in: feed))
  let lengthRange = try #require(Range(match.range(at: 2), in: feed))
  let blockRange = try #require(Range(match.range, in: feed))
  let content = Data(feed[..<blockRange.lowerBound].utf8)
  #expect(content.count == Int(feed[lengthRange]))
  let signature = try #require(Data(base64Encoded: String(feed[signatureRange])))
  let publicKey = try Curve25519.Signing.PublicKey(
    rawRepresentation: #require(
      Data(base64Encoded: "PFTV8NVCUW0zrvvqjBXfHFKJUFNEEZLyT6kmtdwfc00=")))
  #expect(publicKey.isValidSignature(signature, for: content))
  var tampered = content
  tampered[tampered.startIndex] ^= 1
  #expect(!publicKey.isValidSignature(signature, for: tampered))
}
