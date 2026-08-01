import UIKit
import UniformTypeIdentifiers

/// "分享到 邦信阳" from Mail, WeChat, Files, Safari — the entry point a WebView
/// shell could never provide. It resolves every shared item to a file on disk,
/// stages it in the App Group, and gets out of the way; the app picks it up and
/// opens a chat with the files already attached.
final class ShareViewController: UIViewController {
  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    statusLabel.text = "正在准备…"
    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textColor = .label
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()

    view.addSubview(spinner)
    view.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
      statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await ingest() }
  }

  private func ingest() async {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }

    var urls: [URL] = []
    for provider in providers {
      if let url = await Self.fileURL(from: provider) {
        urls.append(url)
      }
    }

    let staged = ShareInbox.stage(urls)
    spinner.stopAnimating()

    if staged == 0 {
      statusLabel.text = "这个内容没法作为文件添加。"
      finish(after: 1.4)
      return
    }
    statusLabel.text = staged == 1
      ? "已添加 1 个文件，打开「邦信阳」继续。"
      : "已添加 \(staged) 个文件，打开「邦信阳」继续。"
    finish(after: 1.2)
  }

  private func finish(after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  /// Shared items arrive as a file URL, raw data, an image, or a web URL. The
  /// first three become files; a plain web link is written out as a `.url` file
  /// so the agent can still be asked to open it.
  private static func fileURL(from provider: NSItemProvider) async -> URL? {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
       let url = await loadItem(provider, UTType.fileURL.identifier) as? URL {
      return url
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
       let image = await loadItem(provider, UTType.image.identifier) {
      if let url = image as? URL { return url }
      if let data = image as? Data { return write(data, ext: "jpg") }
      if let uiImage = image as? UIImage, let data = uiImage.jpegData(compressionQuality: 0.85) {
        return write(data, ext: "jpg")
      }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
       let data = await loadItem(provider, UTType.pdf.identifier) as? Data {
      return write(data, ext: "pdf")
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
       let url = await loadItem(provider, UTType.url.identifier) as? URL {
      return write(Data(url.absoluteString.utf8), ext: "url")
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
       let text = await loadItem(provider, UTType.plainText.identifier) as? String {
      return write(Data(text.utf8), ext: "txt")
    }
    return nil
  }

  private static func loadItem(_ provider: NSItemProvider, _ identifier: String) async -> Any? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: identifier) { item, _ in
        continuation.resume(returning: item)
      }
    }
  }

  private static func write(_ data: Data, ext: String) -> URL? {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    do {
      try data.write(to: url)
      return url
    } catch {
      return nil
    }
  }
}
