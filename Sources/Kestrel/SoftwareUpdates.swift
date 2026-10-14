import AppKit
import Sparkle

/// Sparkle owns download verification, replacement, and relaunch.
@MainActor final class SoftwareUpdates {
  private let controller = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
  private var observations: [NSKeyValueObservation] = []
  var changed: (() -> Void)?

  var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  func start() {
    let updater = controller.updater
    observations = [
      updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.changed?() }
      },
      updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.changed?() }
      },
    ]
    controller.startUpdater()
    changed?()
  }

  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    NSApp.activate(ignoringOtherApps: true)
    controller.checkForUpdates(nil)
  }
}
