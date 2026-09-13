import SwiftUI
import AppKit
import UserNotifications
import ArgusPresentation
import ArgusStore
import ArgusPlatform

@main
struct ArgusApplication: App {
  @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
  private let model: AppModel?
  private let startupError: String?

  init() {
    do {
      guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
        throw AppStartupError.bundledAppRequired
      }
      let directory: URL
      let directoryAttributes: [FileAttributeKey: Any]?
      if let override = ProcessInfo.processInfo.environment["ARGUS_DATA_DIR"], !override.isEmpty {
        directory = URL(fileURLWithPath: override, isDirectory: true)
        directoryAttributes = nil
      } else {
        directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
          appropriateFor: nil, create: true).appendingPathComponent("ARGUS", isDirectory: true)
        directoryAttributes = [.posixPermissions: 0o700]
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: directoryAttributes)
      let store = try ReminderStore(databaseURL: directory.appendingPathComponent("reminders.sqlite"))
      let client = UserNotificationClient(center: UNUserNotificationCenter.current(), clock: { Date() })
      model = AppModel(store: store, client: client, clock: { Date() },
        requestPermission: { try await client.requestAuthorization() })
      startupError = nil
    } catch {
      model = nil
      startupError = "ARGUS could not start. Use the development .app bundle, and verify its local data directory is accessible. Existing data was not replaced. \(error)"
    }
  }

  var body: some Scene {
    WindowGroup("ARGUS") {
      Group {
        if let model {
          TodayView(model: model)
            .task { lifecycle.connect(model); await model.refresh() }
        } else {
          ContentUnavailableView("Local storage unavailable", systemImage: "externaldrive.badge.exclamationmark",
            description: Text(startupError ?? "Unknown storage error"))
            .padding(40).frame(minWidth: 600, minHeight: 300)
        }
      }
    }.defaultSize(width: 1040, height: 740)
    Settings {
      if let model { SettingsView(model: model) }
    }
  }
}

/// App-scoped events remain connected when the last window closes.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
  private var model: AppModel?
  private var observers: [NSObjectProtocol] = []
  private var wakeObserver: NSObjectProtocol?
  private var refreshTimer: Timer?

  func connect(_ model: AppModel) {
    guard self.model == nil else { return }
    self.model = model
    let center = NotificationCenter.default
    for name in [NSApplication.didBecomeActiveNotification,
      NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.model?.refresh() }
      })
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.model?.refresh() }
      }
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.model?.refresh()
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private enum AppStartupError: Error { case bundledAppRequired }
