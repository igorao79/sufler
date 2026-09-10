import UIKit
import UniformTypeIdentifiers

/// Receives text shared from any app and hands it to Sufler.
///
/// Deliberately tiny and UI-less. Share extensions run in their own process under a hard memory
/// limit, so anything heavy — a React Native runtime in particular — is a bad trade for what is a
/// single file write.
///
/// It also does not try to launch the host app. The `openURL:` responder-chain walk that makes that
/// possible is not a public path and is a recurring rejection reason; instead the item waits in the
/// shared container and the app picks it up the next time it comes to the foreground.
final class ShareViewController: UIViewController {

  private let appGroup = "group.com.igorao.sufler"
  private let darwinNotificationName = "com.igorao.sufler.share"

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await handleShare() }
  }

  private func handleShare() async {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return finish(saved: false)
    }

    for item in items {
      for provider in item.attachments ?? [] {
        if let text = await loadText(from: provider) {
          save(title: item.attributedTitle?.string, body: text)
          return finish(saved: true)
        }
        if let (name, text) = await loadFile(from: provider) {
          save(title: name, body: text)
          return finish(saved: true)
        }
      }
    }
    finish(saved: false)
  }

  // MARK: - Loading

  private func loadText(from provider: NSItemProvider) async -> String? {
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
      if let text = item as? String, !text.isEmpty { return text }
      if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return text }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
      if let url = item as? URL, url.isFileURL == false { return url.absoluteString }
    }
    return nil
  }

  private func loadFile(from provider: NSItemProvider) async -> (String, String)? {
    let identifiers = [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier]
    for identifier in identifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
      guard let item = try? await provider.loadItem(forTypeIdentifier: identifier),
            let url = item as? URL, url.isFileURL,
            let text = try? String(contentsOf: url, encoding: .utf8)
      else { continue }
      return (url.deletingPathExtension().lastPathComponent, text)
    }
    return nil
  }

  // MARK: - Saving

  private func save(title: String?, body: String) {
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    else {
      // Nil here means the App Group is not enabled for this target in the developer portal, which
      // otherwise makes shares disappear with no error anywhere.
      NSLog("[Sufler] App Group \(appGroup) is unavailable — the shared item was dropped.")
      return
    }

    let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

    let id = UUID().uuidString
    let payload: [String: Any] = [
      "id": id,
      "title": title?.isEmpty == false ? title! : "Из общего доступа",
      "text": body,
      "createdAt": Date().timeIntervalSince1970,
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    try? data.write(to: inbox.appendingPathComponent("\(id).json"), options: .atomic)

    // Wakes the app if it happens to be running already; harmless if it is not.
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(darwinNotificationName as CFString),
      nil, nil, true)
  }

  private func finish(saved: Bool) {
    guard saved else {
      extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }
    showConfirmation()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  private func showConfirmation() {
    let label = UILabel()
    label.text = "Сохранено в Sufler"
    label.textColor = .white
    label.font = .systemFont(ofSize: 17, weight: .semibold)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    let card = UIView()
    card.backgroundColor = UIColor.black.withAlphaComponent(0.85)
    card.layer.cornerRadius = 16
    card.layer.cornerCurve = .continuous
    card.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(label)
    view.addSubview(card)

    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      label.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
      label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
    ])
  }
}
