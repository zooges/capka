import Foundation

/// Lightweight chat rows the Share Extension can read without the full Capka models.
struct ShareChatRow: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var title: String
  var updatedAt: String?
  var projectName: String?
}

enum ShareChatIndex {
  private static let fileName = "chat-index.json"
  private static let maxRows = 40

  private static var fileURL: URL? {
    ShareHostConfig.containerURL()?.appendingPathComponent(fileName)
  }

  static func load() -> [ShareChatRow] {
    guard let url = fileURL,
          let data = try? Data(contentsOf: url),
          let rows = try? JSONDecoder().decode([ShareChatRow].self, from: data)
    else { return [] }
    return rows
  }

  static func save(_ rows: [ShareChatRow]) {
    guard let url = fileURL else { return }
    let trimmed = Array(rows.prefix(maxRows))
    guard let data = try? JSONEncoder().encode(trimmed) else { return }
    try? data.write(to: url, options: .atomic)
  }

  /// Convenience for the main app's `ChatSummary` list (duck-typed via closures
  /// so ShareSupport stays free of CapkaModels).
  static func saveChats(
    _ chats: [(id: String, title: String?, updatedAt: String?, projectName: String?, archived: Bool?)]
  ) {
    let rows: [ShareChatRow] = chats.compactMap { chat in
      if chat.archived == true { return nil }
      let title = (chat.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        ?? "未命名对话"
      return ShareChatRow(
        id: chat.id,
        title: title,
        updatedAt: chat.updatedAt,
        projectName: chat.projectName
      )
    }
    save(rows)
  }
}
