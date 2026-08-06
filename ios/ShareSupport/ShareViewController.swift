import UIKit
import UniformTypeIdentifiers

/// Share Extension UI: pick an existing chat (from App Group index) or create a new one,
/// then hand files to the host app via the inbox.
final class ShareViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  private var tableView: UITableView!
  private var statusLabel: UILabel!
  private var titleLabel: UILabel!
  private var rows: [ShareChatRow] = []
  private var extractedFiles: [(name: String, data: Data)] = []
  private var busy = false
  private var didComplete = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    let cancel = UIButton(type: .system)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.setTitle("取消", for: .normal)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.text = "分享到\(ShareHostConfig.displayName)"

    statusLabel = UILabel()
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 2
    statusLabel.text = "正在读取文件…"

    tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")

    view.addSubview(cancel)
    view.addSubview(titleLabel)
    view.addSubview(statusLabel)
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

      titleLabel.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      statusLabel.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 12),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    rows = ShareChatIndex.load()
    tableView.reloadData()
    Task { await loadAttachments() }
  }

  private func loadAttachments() async {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      await MainActor.run { statusLabel.text = "没有可分享的内容" }
      return
    }

    var files: [(name: String, data: Data)] = []
    for item in items {
      guard let providers = item.attachments else { continue }
      for provider in providers {
        if let file = await loadFile(from: provider) {
          files.append(file)
        }
      }
    }

    await MainActor.run {
      extractedFiles = files
      if files.isEmpty {
        statusLabel.text = "无法读取文件。请改用「存储到文件」后再试。"
      } else if files.count == 1 {
        statusLabel.text = files[0].name
      } else {
        statusLabel.text = "\(files.count) 个文件"
      }
      tableView.reloadData()
    }
  }

  private func loadFile(from provider: NSItemProvider) async -> (name: String, data: Data)? {
    let typeIds = [
      UTType.fileURL.identifier,
      UTType.image.identifier,
      UTType.pdf.identifier,
      UTType.data.identifier,
      UTType.item.identifier,
    ]
    for typeId in typeIds where provider.hasItemConformingToTypeIdentifier(typeId) {
      if let result = await loadTyped(provider, typeId: typeId) {
        return result
      }
    }
    return nil
  }

  private func loadTyped(_ provider: NSItemProvider, typeId: String) async -> (name: String, data: Data)? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
        if let url = item as? URL {
          let accessing = url.startAccessingSecurityScopedResource()
          defer { if accessing { url.stopAccessingSecurityScopedResource() } }
          if let data = try? Data(contentsOf: url) {
            continuation.resume(returning: (url.lastPathComponent, data))
            return
          }
        }
        if let data = item as? Data {
          let name = provider.suggestedName ?? self.defaultName(for: typeId)
          continuation.resume(returning: (name, data))
          return
        }
        if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
          var name = provider.suggestedName ?? "照片.jpg"
          let lower = name.lowercased()
          if !(lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")) {
            name += ".jpg"
          }
          continuation.resume(returning: (name, data))
          return
        }
        continuation.resume(returning: nil)
      }
    }
  }

  private func defaultName(for typeId: String) -> String {
    if typeId == UTType.image.identifier { return "图片.jpg" }
    if typeId == UTType.pdf.identifier { return "文档.pdf" }
    return "文件.bin"
  }

  func numberOfSections(in tableView: UITableView) -> Int { 2 }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? 1 : max(rows.count, 1)
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    section == 0 ? nil : "最近对话"
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    var config = cell.defaultContentConfiguration()
    if indexPath.section == 0 {
      config.text = "新建对话"
      config.secondaryText = "创建对话并把文件挂到输入框"
      config.image = UIImage(systemName: "square.and.pencil")
      cell.selectionStyle = .default
    } else if rows.isEmpty {
      config.text = "暂无最近对话"
      config.secondaryText = "请先在 App 中登录并打开过对话"
      config.image = UIImage(systemName: "bubble.left.and.bubble.right")
      cell.selectionStyle = .none
    } else {
      let row = rows[indexPath.row]
      config.text = row.title
      config.secondaryText = row.projectName
      config.image = UIImage(systemName: "bubble.left")
      cell.selectionStyle = .default
    }
    cell.contentConfiguration = config
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !busy else { return }
    if indexPath.section == 1 {
      guard !rows.isEmpty else { return }
      finish(target: .chat(id: rows[indexPath.row].id))
    } else {
      finish(target: .newChat)
    }
  }

  private func finish(target: ShareInboxTarget) {
    guard !extractedFiles.isEmpty else {
      statusLabel.text = "没有可分享的文件"
      return
    }
    busy = true
    statusLabel.text = "正在准备…"
    do {
      _ = try ShareInboxStore.enqueue(files: extractedFiles, target: target)
      openHostAndComplete()
    } catch {
      busy = false
      statusLabel.text = error.localizedDescription
    }
  }

  private func openHostAndComplete() {
    let url = ShareHostConfig.shareInboxURL
    // Share extensions often cannot use extensionContext.open for custom schemes;
    // walk the responder chain (legacy openURL:) then fall back.
    var opened = false
    let selector = NSSelectorFromString("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selector) {
        _ = current.perform(selector, with: url)
        opened = true
        break
      }
      responder = current.next
    }
    if !opened {
      extensionContext?.open(url) { _ in }
    }
    // Inbox persists in the App Group even if open fails; host drains on next launch.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      self?.completeOnce()
    }
  }

  private func completeOnce() {
    guard !didComplete else { return }
    didComplete = true
    extensionContext?.completeRequest(returningItems: nil)
  }

  @objc private func cancelTapped() {
    extensionContext?.cancelRequest(
      withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
    )
  }
}
