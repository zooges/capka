import Foundation
import Network
import Observation

/// Drafts written without a usable connection, held until there is one.
///
/// The alternative — an error toast and a cleared composer — loses work the user
/// just did, and on a phone (lift, train, basement) that is the common case, not
/// the edge case. A queued message is kept on disk so it also survives the app
/// being killed, and is only ever sent once: the send is keyed by the message id
/// the server will persist, so a double flush cannot duplicate a turn.
@MainActor
@Observable
final class OutboxStore {
  struct Draft: Codable, Identifiable, Equatable {
    var id: String
    var chatId: String?
    var text: String
    /// Files already uploaded to the workspace before the connection dropped.
    var attachments: [Attachment]
    var modelId: String?
    var queuedAt: Date

    struct Attachment: Codable, Equatable {
      var name: String
      var type: String
    }
  }

  private(set) var drafts: [Draft] = []
  /// nil until the first path update — treated as online so a cold start with a
  /// slow monitor doesn't queue a message that would have sent fine.
  private(set) var isOnline = true

  private let monitor = NWPathMonitor()
  private var flushing = false

  /// Application Support is NOT created for you on iOS — writing into it before
  /// it exists fails, and with `try?` swallowing that the queue would quietly
  /// never survive a relaunch, which is the one thing it promises.
  private static var fileURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("capka-outbox.json")
  }

  init() {
    load()
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        let online = path.status == .satisfied
        let cameBack = online && !self.isOnline
        self.isOnline = online
        if cameBack { self.onReconnect?() }
      }
    }
    monitor.start(queue: DispatchQueue(label: "capka.outbox.path"))
  }

  /// Called when connectivity returns; the chat view model owns the actual send.
  var onReconnect: (() -> Void)?

  var hasPending: Bool { !drafts.isEmpty }

  func enqueue(_ draft: Draft) {
    drafts.append(draft)
    persist()
  }

  func remove(id: String) {
    drafts.removeAll { $0.id == id }
    persist()
  }

  /// Hand out the queued drafts for one flush attempt. Guarded so a reconnect
  /// that fires twice (Wi-Fi → cellular → Wi-Fi) doesn't send everything twice.
  func beginFlush() -> [Draft] {
    guard !flushing, isOnline else { return [] }
    flushing = true
    return drafts
  }

  func endFlush() {
    flushing = false
  }

  private func load() {
    guard let data = try? Data(contentsOf: Self.fileURL),
          let decoded = try? JSONDecoder().decode([Draft].self, from: data)
    else { return }
    drafts = decoded
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(drafts) else { return }
    do {
      try data.write(to: Self.fileURL, options: .atomic)
    } catch {
      // In-memory queueing still works for this session; only durability is lost.
      assertionFailure("outbox persist failed: \(error)")
    }
  }
}

// MARK: - Chat disk cache

/// Sidebar titles + last-opened transcripts kept on disk so search / reopen work
/// without a round trip to the office host (and survive brief offline windows).
final class ChatDiskCache: @unchecked Sendable {
  static let shared = ChatDiskCache()

  private let queue = DispatchQueue(label: "capka.chat-disk-cache")
  private var chatList: [ChatSummary] = []

  private static var root: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("capka-chat-cache", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private static var listURL: URL { root.appendingPathComponent("chats.json") }
  private static var messagesDir: URL {
    let dir = root.appendingPathComponent("messages", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private init() {
    if let data = try? Data(contentsOf: Self.listURL),
       let decoded = try? JSONDecoder().decode([ChatSummary].self, from: data) {
      chatList = decoded
    }
  }

  func loadChatList() -> [ChatSummary] {
    queue.sync { chatList }
  }

  /// Sign-out: chats, transcripts, listings and preview files all belong to the
  /// account that just left, and must not greet whoever signs in next.
  func wipe() {
    queue.sync { wipeLocked() }
  }

  /// A session can also change hands without a sign-out (expired cookie, shared
  /// iPad) — stamp the cache with its owner and wipe when a different user lands.
  func adoptOwner(userId: String) {
    queue.sync {
      let previous = (try? String(
        contentsOf: Self.root.appendingPathComponent("owner.txt"),
        encoding: .utf8
      ))?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let previous, previous != userId {
        wipeLocked()
      }
      // Recompute the URL after a wipe — the root accessor recreates the
      // directory, otherwise the stamp write lands in a deleted folder.
      try? userId.write(
        to: Self.root.appendingPathComponent("owner.txt"),
        atomically: true,
        encoding: .utf8
      )
    }
  }

  private func wipeLocked() {
    chatList = []
    try? FileManager.default.removeItem(at: Self.root)
    PreviewDiskCache.wipe()
  }

  func saveChatList(_ chats: [ChatSummary]) {
    queue.sync {
      // Merge by id so a search page (subset) never wipes the full sidebar cache.
      var byId = Dictionary(uniqueKeysWithValues: chatList.map { ($0.id, $0) })
      for chat in chats { byId[chat.id] = chat }
      // Prefer the server page order for rows it returned; keep the rest after.
      var merged: [ChatSummary] = []
      var seen = Set<String>()
      for chat in chats {
        merged.append(chat)
        seen.insert(chat.id)
      }
      for chat in chatList where !seen.contains(chat.id) {
        merged.append(chat)
      }
      // Cap so Application Support doesn't grow without bound on a long-lived phone.
      if merged.count > 200 { merged = Array(merged.prefix(200)) }
      chatList = merged
      if let data = try? JSONEncoder().encode(merged) {
        try? data.write(to: Self.listURL, options: .atomic)
      }
      // Keep the Share Extension's chat picker in sync (App Group).
      ShareChatIndex.saveChats(merged.map {
        ($0.id, $0.title, $0.updatedAt, $0.projectName, $0.archived)
      })
    }
  }

  func chats(matching query: String) -> [ChatSummary] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return loadChatList() }
    let contentHits = chatIdsMatchingMessageCache(q)
    return loadChatList().filter { chat in
      (chat.title ?? "").localizedCaseInsensitiveContains(q)
        || (chat.projectName ?? "").localizedCaseInsensitiveContains(q)
        || contentHits.contains(chat.id)
    }
  }

  /// Scan cached transcripts (opened chats) for a case-insensitive substring.
  private func chatIdsMatchingMessageCache(_ query: String) -> Set<String> {
    queue.sync {
      guard let files = try? FileManager.default.contentsOfDirectory(
        at: Self.messagesDir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ) else { return [] }
      var hits = Set<String>()
      for url in files where url.pathExtension == "json" {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8),
              raw.localizedCaseInsensitiveContains(query)
        else { continue }
        hits.insert(url.deletingPathExtension().lastPathComponent)
      }
      return hits
    }
  }

  func saveMessagesJSON(chatId: String, data: Data) {
    queue.async {
      let url = Self.messagesDir.appendingPathComponent("\(chatId).json")
      try? data.write(to: url, options: .atomic)
      Self.pruneMessages(keeping: 80)
    }
  }

  func loadMessagesJSON(chatId: String) -> Data? {
    queue.sync {
      try? Data(contentsOf: Self.messagesDir.appendingPathComponent("\(chatId).json"))
    }
  }

  // MARK: Workspace listings

  private static var listingsDir: URL {
    let dir = root.appendingPathComponent("listings", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private static func listingKey(chatId: String?, projectId: String?, path: String) -> String {
    let scope = projectId ?? chatId ?? "_"
    let raw = "\(scope)|\(path)"
    return raw
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
  }

  func saveListing(chatId: String?, projectId: String?, path: String, entries: [WorkspaceEntry]) {
    queue.async {
      let url = Self.listingsDir.appendingPathComponent("\(Self.listingKey(chatId: chatId, projectId: projectId, path: path)).json")
      guard let data = try? JSONEncoder().encode(entries) else { return }
      try? data.write(to: url, options: .atomic)
    }
  }

  func loadListing(chatId: String?, projectId: String?, path: String) -> [WorkspaceEntry]? {
    queue.sync {
      let url = Self.listingsDir.appendingPathComponent("\(Self.listingKey(chatId: chatId, projectId: projectId, path: path)).json")
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? JSONDecoder().decode([WorkspaceEntry].self, from: data)
    }
  }

  /// Pull recent transcripts into the message cache so reopen / search is local.
  func prefetchRecentMessages(chatIds: [String], limit: Int = 12) {
    let ids = Array(chatIds.prefix(limit))
    Task.detached(priority: .utility) {
      for id in ids {
        if ChatDiskCache.shared.loadMessagesJSON(chatId: id) != nil { continue }
        _ = try? await CapkaAPIClient.shared.fetchMessages(chatId: id)
      }
    }
  }

  private static func pruneMessages(keeping maxFiles: Int) {
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: messagesDir,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ), files.count > maxFiles else { return }
    let ranked = files.compactMap { url -> (URL, Date)? in
      let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      return (url, date)
    }
    .sorted { $0.1 < $1.1 }
    for item in ranked.prefix(files.count - maxFiles) {
      try? FileManager.default.removeItem(at: item.0)
    }
  }
}
