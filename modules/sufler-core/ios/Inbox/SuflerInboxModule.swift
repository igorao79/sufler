import ExpoModulesCore
import Foundation

/// Receives scripts shared from other apps.
///
/// The share extension cannot talk to the app directly — it is a separate process with a tight
/// memory budget and no way to launch its host without reaching for the `openURL:` responder-chain
/// trick, which is a recurring rejection reason. So it writes JSON into the shared App Group
/// container and posts a Darwin notification; this module drains the container and, when the app
/// happens to already be running, forwards the notification so the pickup is immediate.
public class SuflerInboxModule: Module {

  static let appGroup = "group.com.igorao.sufler"
  private static let darwinNotificationName = "com.igorao.sufler.share"

  public func definition() -> ModuleDefinition {
    Name("SuflerInbox")

    Events("onSharedItem")

    OnCreate {
      Self.observeDarwinNotification { [weak self] in
        self?.sendEvent("onSharedItem", [:])
      }
    }

    /// Reads and deletes. Draining is destructive on purpose: a shared item that stayed in the
    /// container would be re-imported on every foreground.
    AsyncFunction("drain") { () -> [[String: Any]] in
      Self.drainAll()
    }

    /// Surfaces the misconfiguration that otherwise makes shares vanish without a trace: if the
    /// App Group is not enabled for both bundle identifiers in the developer portal,
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` simply returns nil.
    Function("isAppGroupAvailable") { () -> Bool in
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil
    }
  }

  // MARK: - Container

  private static var inboxURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("Inbox", isDirectory: true)
  }

  private static func drainAll() -> [[String: Any]] {
    guard let inboxURL,
          let files = try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return [] }

    let jsonFiles = files.filter { $0.pathExtension == "json" }.sorted {
      ($0.lastPathComponent) < ($1.lastPathComponent)
    }

    var items: [[String: Any]] = []
    for file in jsonFiles {
      defer { try? FileManager.default.removeItem(at: file) }
      guard let data = try? Data(contentsOf: file),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      items.append(object)
    }
    return items
  }

  // MARK: - Darwin notifications

  private static var darwinHandler: (() -> Void)?

  private static func observeDarwinNotification(_ handler: @escaping () -> Void) {
    darwinHandler = handler
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterAddObserver(
      center,
      Unmanaged.passUnretained(self as AnyObject).toOpaque(),
      { _, _, _, _, _ in
        DispatchQueue.main.async { SuflerInboxModule.darwinHandler?() }
      },
      darwinNotificationName as CFString,
      nil,
      .deliverImmediately)
  }
}
