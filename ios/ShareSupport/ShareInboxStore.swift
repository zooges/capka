import Foundation

struct ShareInboxFile: Codable, Equatable, Sendable {
  var name: String
  var relativePath: String
}

enum ShareInboxTarget: Codable, Equatable, Sendable {
  case chat(id: String)
  case newChat

  private enum CodingKeys: String, CodingKey { case type, chatId }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "chat":
      self = .chat(id: try c.decode(String.self, forKey: .chatId))
    default:
      self = .newChat
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .chat(let id):
      try c.encode("chat", forKey: .type)
      try c.encode(id, forKey: .chatId)
    case .newChat:
      try c.encode("new", forKey: .type)
    }
  }
}

struct ShareInboxItem: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var createdAt: TimeInterval
  var target: ShareInboxTarget
  var files: [ShareInboxFile]
}

enum ShareInboxStore {
  static let didReceiveNotification = Notification.Name("capka.shareInbox.didReceive")

  private static var inboxRoot: URL? {
    ShareHostConfig.containerURL()?.appendingPathComponent("inbox", isDirectory: true)
  }

  /// Copy shared files into the App Group and record a pending inbox item.
  @discardableResult
  static func enqueue(files: [(name: String, data: Data)], target: ShareInboxTarget) throws -> ShareInboxItem {
    guard let root = inboxRoot else {
      throw ShareInboxError.appGroupUnavailable
    }
    let id = UUID().uuidString
    let itemDir = root.appendingPathComponent(id, isDirectory: true)
    let filesDir = itemDir.appendingPathComponent("files", isDirectory: true)
    try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

    var recorded: [ShareInboxFile] = []
    var usedNames = Set<String>()
    for file in files {
      let safe = uniqueName(file.name, used: &usedNames)
      let rel = "files/\(safe)"
      let dest = itemDir.appendingPathComponent(rel)
      try file.data.write(to: dest, options: .atomic)
      recorded.append(ShareInboxFile(name: safe, relativePath: rel))
    }
    guard !recorded.isEmpty else { throw ShareInboxError.noFiles }

    let item = ShareInboxItem(
      id: id,
      createdAt: Date().timeIntervalSince1970,
      target: target,
      files: recorded
    )
    let meta = itemDir.appendingPathComponent("meta.json")
    try JSONEncoder().encode(item).write(to: meta, options: .atomic)
    return item
  }

  /// Oldest-first pending items (skips corrupt folders).
  static func pendingItems() -> [ShareInboxItem] {
    guard let root = inboxRoot else { return [] }
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.creationDateKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    return dirs.compactMap { dir -> ShareInboxItem? in
      let meta = dir.appendingPathComponent("meta.json")
      guard let data = try? Data(contentsOf: meta),
            let item = try? JSONDecoder().decode(ShareInboxItem.self, from: data)
      else { return nil }
      return item
    }
    .sorted { $0.createdAt < $1.createdAt }
  }

  static func fileURLs(for item: ShareInboxItem) -> [URL] {
    guard let root = inboxRoot else { return [] }
    let dir = root.appendingPathComponent(item.id, isDirectory: true)
    return item.files.map { dir.appendingPathComponent($0.relativePath) }
  }

  static func remove(_ item: ShareInboxItem) {
    guard let root = inboxRoot else { return }
    try? FileManager.default.removeItem(at: root.appendingPathComponent(item.id, isDirectory: true))
  }

  static func isShareInboxURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == ShareHostConfig.urlScheme
      && url.host?.lowercased() == "share-inbox"
  }

  private static func uniqueName(_ name: String, used: inout Set<String>) -> String {
    let base = (name as NSString).lastPathComponent
    let cleaned = base.isEmpty ? "file.bin" : base
    if !used.contains(cleaned) {
      used.insert(cleaned)
      return cleaned
    }
    let ns = cleaned as NSString
    let stem = ns.deletingPathExtension
    let ext = ns.pathExtension
    var i = 2
    while true {
      let candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
      if !used.contains(candidate) {
        used.insert(candidate)
        return candidate
      }
      i += 1
    }
  }
}

enum ShareInboxError: LocalizedError {
  case appGroupUnavailable
  case noFiles

  var errorDescription: String? {
    switch self {
    case .appGroupUnavailable: return "无法访问 App Group 共享目录"
    case .noFiles: return "没有可分享的文件"
    }
  }
}
