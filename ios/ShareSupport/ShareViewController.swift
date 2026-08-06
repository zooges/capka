import UIKit
import UniformTypeIdentifiers

/// Share Extension UI: Capka-styled picker → App Group inbox → open host app.
final class ShareViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  private let tableView = UITableView(frame: .zero, style: .plain)
  private let brandLabel = UILabel()
  private let titleLabel = UILabel()
  private let fileCard = UIView()
  private let fileIcon = UIImageView()
  private let fileLabel = UILabel()
  private let fileSubLabel = UILabel()
  private let statusRow = UIView()
  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var statusRowHeight: NSLayoutConstraint!

  private var rows: [ShareChatRow] = []
  private var extractedFiles: [(name: String, data: Data)] = []
  private var busy = false
  private var didComplete = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = ShareBrand.background
    buildChrome()
    rows = ShareChatIndex.load()
    tableView.reloadData()
    Task { await loadAttachments() }
  }

  // MARK: - Layout

  private func buildChrome() {
    let cancel = UIButton(type: .system)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.setTitle("取消", for: .normal)
    cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
    cancel.setTitleColor(ShareBrand.textMuted, for: .normal)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    brandLabel.translatesAutoresizingMaskIntoConstraints = false
    brandLabel.text = ShareBrand.productWordmark
    brandLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    brandLabel.textColor = ShareBrand.burgundy
    brandLabel.letterSpacing = 0.8

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "分享到\(ShareHostConfig.displayName)"
    titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    titleLabel.textColor = ShareBrand.text

    fileCard.translatesAutoresizingMaskIntoConstraints = false
    fileCard.backgroundColor = ShareBrand.surface
    fileCard.layer.cornerRadius = ShareBrand.radiusXl
    fileCard.layer.cornerCurve = .continuous
    fileCard.layer.borderWidth = 1
    fileCard.layer.borderColor = ShareBrand.border.cgColor

    fileIcon.translatesAutoresizingMaskIntoConstraints = false
    fileIcon.contentMode = .scaleAspectFit
    fileIcon.tintColor = ShareBrand.burgundy
    fileIcon.image = UIImage(systemName: "doc.fill")

    fileLabel.translatesAutoresizingMaskIntoConstraints = false
    fileLabel.font = .systemFont(ofSize: 15, weight: .medium)
    fileLabel.textColor = ShareBrand.text
    fileLabel.numberOfLines = 2
    fileLabel.text = "正在读取文件…"

    fileSubLabel.translatesAutoresizingMaskIntoConstraints = false
    fileSubLabel.font = .systemFont(ofSize: 12, weight: .regular)
    fileSubLabel.textColor = ShareBrand.textMuted
    fileSubLabel.text = "将作为附件放进输入框，不会自动发送"

    let fileTextStack = UIStackView(arrangedSubviews: [fileLabel, fileSubLabel])
    fileTextStack.axis = .vertical
    fileTextStack.spacing = 2
    fileTextStack.translatesAutoresizingMaskIntoConstraints = false

    fileCard.addSubview(fileIcon)
    fileCard.addSubview(fileTextStack)

    statusRow.translatesAutoresizingMaskIntoConstraints = false
    statusRow.clipsToBounds = true

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
    statusLabel.textColor = ShareBrand.textMuted
    statusLabel.numberOfLines = 1

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.color = ShareBrand.burgundy
    spinner.hidesWhenStopped = true

    statusRow.addSubview(statusLabel)
    statusRow.addSubview(spinner)

    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundColor = .clear
    tableView.separatorStyle = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
    tableView.register(ShareChatCell.self, forCellReuseIdentifier: ShareChatCell.reuseId)
    tableView.register(ShareActionCell.self, forCellReuseIdentifier: ShareActionCell.reuseId)
    tableView.register(ShareEmptyCell.self, forCellReuseIdentifier: ShareEmptyCell.reuseId)

    view.addSubview(cancel)
    view.addSubview(brandLabel)
    view.addSubview(titleLabel)
    view.addSubview(fileCard)
    view.addSubview(statusRow)
    view.addSubview(tableView)

    statusRowHeight = statusRow.heightAnchor.constraint(equalToConstant: 0)

    NSLayoutConstraint.activate([
      cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

      brandLabel.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      brandLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      titleLabel.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 18),
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      fileCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
      fileCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      fileCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      fileIcon.leadingAnchor.constraint(equalTo: fileCard.leadingAnchor, constant: 14),
      fileIcon.centerYAnchor.constraint(equalTo: fileCard.centerYAnchor),
      fileIcon.widthAnchor.constraint(equalToConstant: 28),
      fileIcon.heightAnchor.constraint(equalToConstant: 28),

      fileTextStack.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 12),
      fileTextStack.trailingAnchor.constraint(equalTo: fileCard.trailingAnchor, constant: -14),
      fileTextStack.topAnchor.constraint(equalTo: fileCard.topAnchor, constant: 14),
      fileTextStack.bottomAnchor.constraint(equalTo: fileCard.bottomAnchor, constant: -14),

      statusRow.topAnchor.constraint(equalTo: fileCard.bottomAnchor),
      statusRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      statusRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      statusRowHeight,

      statusLabel.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),
      statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),

      spinner.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
      spinner.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor, constant: -20),

      tableView.topAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: 4),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  private func setStatusVisible(_ visible: Bool, text: String? = nil) {
    if let text { statusLabel.text = text }
    statusRowHeight.constant = visible ? 28 : 0
    UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
  }

  // MARK: - Attachments

  private func loadAttachments() async {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      await MainActor.run { showFileState(title: "没有可分享的内容", ok: false) }
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
        showFileState(title: "无法读取文件", subtitle: "可先「存储到文件」再分享", ok: false)
      } else if files.count == 1 {
        showFileState(title: files[0].name, subtitle: "将作为附件放进输入框，不会自动发送", ok: true)
      } else {
        showFileState(
          title: "\(files.count) 个文件",
          subtitle: files.map(\.name).prefix(3).joined(separator: "、")
            + (files.count > 3 ? "…" : ""),
          ok: true
        )
      }
      tableView.reloadData()
    }
  }

  private func showFileState(title: String, subtitle: String? = nil, ok: Bool) {
    fileLabel.text = title
    fileSubLabel.text = subtitle
    fileSubLabel.isHidden = subtitle == nil
    fileIcon.image = UIImage(systemName: ok ? "paperclip" : "exclamationmark.triangle.fill")
    fileIcon.tintColor = ok ? ShareBrand.burgundy : ShareBrand.textMuted
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

  // MARK: - Table

  func numberOfSections(in tableView: UITableView) -> Int { 2 }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? 1 : max(rows.count, 1)
  }

  func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    guard section == 1 else { return UIView(frame: .zero) }
    let wrap = UIView()
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "最近对话"
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = ShareBrand.textMuted
    wrap.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
      label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
      label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 18),
      label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
    ])
    return wrap
  }

  func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    section == 0 ? 8 : 40
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 0 {
      let cell = tableView.dequeueReusableCell(withIdentifier: ShareActionCell.reuseId, for: indexPath) as! ShareActionCell
      cell.configure(enabled: !extractedFiles.isEmpty && !busy)
      return cell
    }
    if rows.isEmpty {
      let cell = tableView.dequeueReusableCell(withIdentifier: ShareEmptyCell.reuseId, for: indexPath) as! ShareEmptyCell
      return cell
    }
    let cell = tableView.dequeueReusableCell(withIdentifier: ShareChatCell.reuseId, for: indexPath) as! ShareChatCell
    cell.configure(row: rows[indexPath.row], enabled: !extractedFiles.isEmpty && !busy)
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !busy, !extractedFiles.isEmpty else { return }
    if indexPath.section == 1 {
      guard !rows.isEmpty else { return }
      finish(target: .chat(id: rows[indexPath.row].id))
    } else {
      finish(target: .newChat)
    }
  }

  // MARK: - Finish + open host

  private func finish(target: ShareInboxTarget) {
    busy = true
    setStatusVisible(true, text: "正在打开\(ShareHostConfig.displayName)…")
    spinner.startAnimating()
    tableView.reloadData()
    tableView.isUserInteractionEnabled = false

    do {
      _ = try ShareInboxStore.enqueue(files: extractedFiles, target: target)
      openHostAndComplete()
    } catch {
      busy = false
      spinner.stopAnimating()
      setStatusVisible(true, text: error.localizedDescription)
      tableView.isUserInteractionEnabled = true
      tableView.reloadData()
    }
  }

  private func openHostAndComplete() {
    let url = ShareHostConfig.shareInboxURL
    openContainingApp(url) { [weak self] success in
      DispatchQueue.main.async {
        guard let self else { return }
        if !success {
          self.spinner.stopAnimating()
          self.setStatusVisible(true, text: "已保存，请手动打开\(ShareHostConfig.displayName)")
        }
        // Give the system a beat to switch apps before tearing down the extension.
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.25 : 0.8)) {
          self.completeOnce()
        }
      }
    }
  }

  /// iOS 18+ requires `UIApplication.open(_:options:)` — deprecated `openURL:` always fails.
  private func openContainingApp(_ url: URL, completion: @escaping (Bool) -> Void) {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: completion)
        return
      }
      responder = current.next
    }

    // Responder chain sometimes omits UIApplication; reach it via the class method.
    let sharedSel = NSSelectorFromString("sharedApplication")
    if let unmanaged = (UIApplication.self as AnyObject).perform(sharedSel),
       let application = unmanaged.takeUnretainedValue() as? UIApplication
    {
      application.open(url, options: [:], completionHandler: completion)
      return
    }

    // Last resort — custom schemes often fail here; inbox still drains on next launch.
    if let context = extensionContext {
      context.open(url, completionHandler: completion)
    } else {
      completion(false)
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

// MARK: - Brand copy

private extension ShareBrand {
  static let productWordmark = "BOSS & YOUNG"
}

private extension UILabel {
  var letterSpacing: CGFloat {
    get { 0 }
    set {
      guard let text else { return }
      let attributed = NSMutableAttributedString(string: text)
      attributed.addAttribute(.kern, value: newValue, range: NSRange(location: 0, length: attributed.length))
      attributedText = attributed
    }
  }
}

// MARK: - Cells

private final class ShareActionCell: UITableViewCell {
  static let reuseId = "ShareActionCell"
  private let card = UIView()
  private let icon = UIImageView()
  private let title = UILabel()
  private let subtitle = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.backgroundColor = .clear

    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = ShareBrand.fill
    card.layer.cornerRadius = ShareBrand.radiusXl
    card.layer.cornerCurve = .continuous

    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.image = UIImage(systemName: "square.and.pencil")
    icon.tintColor = ShareBrand.onFill
    icon.contentMode = .scaleAspectFit

    title.translatesAutoresizingMaskIntoConstraints = false
    title.text = "新建对话"
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    title.textColor = ShareBrand.onFill

    subtitle.translatesAutoresizingMaskIntoConstraints = false
    subtitle.text = "创建对话并把文件挂到输入框"
    subtitle.font = .systemFont(ofSize: 12, weight: .regular)
    subtitle.textColor = ShareBrand.onFill.withAlphaComponent(0.72)

    let text = UIStackView(arrangedSubviews: [title, subtitle])
    text.axis = .vertical
    text.spacing = 2
    text.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(card)
    card.addSubview(icon)
    card.addSubview(text)

    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 22),
      icon.heightAnchor.constraint(equalToConstant: 22),

      text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
      text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
      text.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
      text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func configure(enabled: Bool) {
    card.alpha = enabled ? 1 : 0.45
    isUserInteractionEnabled = enabled
  }

  override func setHighlighted(_ highlighted: Bool, animated: Bool) {
    super.setHighlighted(highlighted, animated: animated)
    UIView.animate(withDuration: 0.12) {
      self.card.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
      self.card.alpha = highlighted ? 0.88 : (self.isUserInteractionEnabled ? 1 : 0.45)
    }
  }
}

private final class ShareChatCell: UITableViewCell {
  static let reuseId = "ShareChatCell"
  private let card = UIView()
  private let icon = UIImageView()
  private let title = UILabel()
  private let subtitle = UILabel()
  private let chevron = UIImageView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.backgroundColor = .clear

    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = ShareBrand.surface
    card.layer.cornerRadius = ShareBrand.radiusXl
    card.layer.cornerCurve = .continuous
    card.layer.borderWidth = 1
    card.layer.borderColor = ShareBrand.border.cgColor

    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.image = UIImage(systemName: "bubble.left")
    icon.tintColor = ShareBrand.textMuted
    icon.contentMode = .scaleAspectFit

    title.translatesAutoresizingMaskIntoConstraints = false
    title.font = .systemFont(ofSize: 15, weight: .medium)
    title.textColor = ShareBrand.text
    title.numberOfLines = 1

    subtitle.translatesAutoresizingMaskIntoConstraints = false
    subtitle.font = .systemFont(ofSize: 12, weight: .regular)
    subtitle.textColor = ShareBrand.textMuted
    subtitle.numberOfLines = 1

    chevron.translatesAutoresizingMaskIntoConstraints = false
    chevron.image = UIImage(systemName: "chevron.right")
    chevron.tintColor = ShareBrand.textMuted.withAlphaComponent(0.55)
    chevron.contentMode = .scaleAspectFit
    chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

    let text = UIStackView(arrangedSubviews: [title, subtitle])
    text.axis = .vertical
    text.spacing = 2
    text.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(card)
    card.addSubview(icon)
    card.addSubview(text)
    card.addSubview(chevron)

    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

      icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
      icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 20),
      icon.heightAnchor.constraint(equalToConstant: 20),

      chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
      chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 12),

      text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
      text.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
      text.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
      text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func configure(row: ShareChatRow, enabled: Bool) {
    title.text = row.title
    let project = row.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    subtitle.text = (project?.isEmpty == false) ? project : "个人对话"
    subtitle.isHidden = false
    card.alpha = enabled ? 1 : 0.5
    isUserInteractionEnabled = enabled
  }

  override func setHighlighted(_ highlighted: Bool, animated: Bool) {
    super.setHighlighted(highlighted, animated: animated)
    UIView.animate(withDuration: 0.12) {
      self.card.backgroundColor = highlighted ? ShareBrand.surfaceMuted : ShareBrand.surface
    }
  }
}

private final class ShareEmptyCell: UITableViewCell {
  static let reuseId = "ShareEmptyCell"

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.backgroundColor = .clear

    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = ShareBrand.surface
    card.layer.cornerRadius = ShareBrand.radiusXl
    card.layer.cornerCurve = .continuous
    card.layer.borderWidth = 1
    card.layer.borderColor = ShareBrand.border.cgColor

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "暂无最近对话\n请先在 App 中登录并打开过对话"
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = ShareBrand.textMuted
    label.textAlignment = .center
    label.numberOfLines = 0

    contentView.addSubview(card)
    card.addSubview(label)
    NSLayoutConstraint.activate([
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      label.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
      label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
      label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }
}
