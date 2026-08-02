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
