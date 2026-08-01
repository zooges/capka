import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class ChatViewModel {
  /// nil = brand-new chat (home). Set after first successful send.
  var chatId: String?

  var messages: [ChatUIMessage] = []
  var draft = ""
  var models: [ModelInfo] = []
  var selectedModelId: String?
  var isLoading = false
  var isSending = false
  var error: String?
  var activeTaskId: String?
  var pendingAttachments: [(name: String, type: String)] = []
  var title: String = "新对话"

  private let api = CapkaAPIClient.shared
  private weak var session: SessionStore?
  private var streamingMessageId: String?
  private var pollTask: Task<Void, Never>?
  /// When the current turn was queued — the "no task row yet" grace is measured
  /// from here.
  private var turnStartedAt = Date.distantPast
  /// How long after queuing a missing task row still means "starting", not "done".
  private static let taskRowGrace: TimeInterval = 25

  init(chatId: String? = nil) {
    self.chatId = chatId
  }

  var isEmptyChat: Bool { messages.isEmpty && !isLoading }

  /// Context-window fill from the most recent assistant turn that reported it.
  var contextFill: Double? {
    messages.last(where: { $0.details.contextFill != nil })?.details.contextFill
  }

  var contextSummary: String? {
    guard let msg = messages.last(where: { $0.details.contextFill != nil }),
          let used = msg.details.contextTokens,
          let total = msg.details.contextWindow
    else { return nil }
    return "\(Self.compactTokens(used)) / \(Self.compactTokens(total)) Token"
  }

  /// Matches the web meter's `fmtTokens`: 1240 → "1k", 1_200_000 → "1.2M".
  private static func compactTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return "\(Int((Double(n) / 1000).rounded()))k" }
    return "\(n)"
  }
  var isBusy: Bool { activeTaskId != nil || messages.contains(where: { $0.isStreaming }) }

  func bind(session: SessionStore) {
    self.session = session
  }

  func openChat(_ id: String?) async {
    stopPolling()
    chatId = id
    messages = []
    activeTaskId = nil
    streamingMessageId = nil
    pendingAttachments = []
    draft = ""
    title = id == nil ? "新对话" : "对话"
    error = nil
    await load()
    if let id {
      await api.markChatRead(chatId: id)
    }
  }

  func startNewChat() {
    stopPolling()
    chatId = nil
    messages = []
    activeTaskId = nil
    streamingMessageId = nil
    pendingAttachments = []
    draft = ""
    title = "新对话"
    error = nil
    isSending = false
  }

  func load() async {
    guard let chatId else {
      if models.isEmpty {
        models = (try? await api.listModels()) ?? []
        if selectedModelId == nil {
          selectedModelId = models.first(where: { $0.featured == true })?.id ?? models.first?.id
        }
      }
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      async let msgs = api.fetchMessages(chatId: chatId)
      async let modelList = api.listModels()
      let loaded = try await msgs
      // Preserve in-flight optimistic user rows the server hasn't returned yet.
      let optimisticUsers = messages.filter { msg in
        msg.role == "user" && !loaded.contains(where: { $0.id == msg.id })
      }
      messages = loaded + optimisticUsers
      models = (try? await modelList) ?? models
      if selectedModelId == nil {
        selectedModelId = models.first(where: { $0.featured == true })?.id ?? models.first?.id
      }
      if let running = messages.first(where: { $0.isStreaming }) {
        streamingMessageId = running.id
        startPolling()
      } else {
        clearStreamingFlags()
      }
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Index of the latest assistant message — used to show regenerate only there.
  var latestAssistantId: String? {
    messages.last(where: { $0.role == "assistant" })?.id
  }

  func regenerate() async {
    guard let chatId, !isBusy, !isSending else { return }
    guard let lastIdx = messages.lastIndex(where: { $0.role == "assistant" }) else { return }
    let history = Array(messages.prefix(lastIdx))
    guard history.contains(where: { $0.role == "user" }) else { return }

    messages = history
    let placeholderId = "pending-regen-\(UUID().uuidString)"
    messages.append(ChatUIMessage(id: placeholderId, role: "assistant", text: "", isStreaming: true))
    streamingMessageId = placeholderId
    isSending = true
    error = nil

    do {
      let res = try await api.regenerateMessage(
        chatId: chatId,
        model: selectedModelId,
        history: history
      )
      self.chatId = res.chatId
      activeTaskId = res.taskId
      CapkaFeedback.replyStarted(chatId: chatId)
      startPolling()
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
      removePlaceholder(placeholderId)
    } catch {
      self.error = error.localizedDescription
      removePlaceholder(placeholderId)
      // Reload so a failed regen doesn't leave a truncated transcript.
      await load()
    }
    isSending = false
  }

  func send() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
    guard !isSending else { return }

    let userId = UUID().uuidString
    let display = text.isEmpty ? "（附件）" : text
    messages.append(ChatUIMessage(id: userId, role: "user", text: display, isStreaming: false))
    let placeholderId = "pending-\(userId)"
    messages.append(ChatUIMessage(id: placeholderId, role: "assistant", text: "", isStreaming: true))
    streamingMessageId = placeholderId

    draft = ""
    let attachments = pendingAttachments
    pendingAttachments = []
    isSending = true

    do {
      let res = try await api.sendMessage(
        chatId: chatId,
        text: text,
        model: selectedModelId,
        userMessageId: userId,
        attachedFiles: attachments.isEmpty ? nil : attachments.map { ["name": $0.name, "type": $0.type] }
      )
      chatId = res.chatId
      activeTaskId = res.taskId
      CapkaFeedback.replyStarted(chatId: chatId)
      startPolling()
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
      removePlaceholder(placeholderId)
    } catch {
      self.error = error.localizedDescription
      removePlaceholder(placeholderId)
    }
    isSending = false
  }

  func stop() async {
    CapkaFeedback.replyAbandoned()
    guard let taskId = activeTaskId else {
      clearStreamingFlags()
      return
    }
    do {
      try await api.cancelTask(taskId: taskId)
    } catch {
      self.error = error.localizedDescription
    }
    stopPolling()
    activeTaskId = nil
    if let mid = streamingMessageId, let idx = messages.firstIndex(where: { $0.id == mid }) {
      messages[idx].isStreaming = false
      if messages[idx].text.isEmpty { messages[idx].text = "已停止" }
    }
    streamingMessageId = nil
    if let chatId {
      messages = (try? await api.fetchMessages(chatId: chatId)) ?? messages
      clearStreamingFlags()
    }
  }

  func attach(fileURL: URL) async {
    do {
      if chatId == nil {
        chatId = try await api.createChat(title: "新对话", model: selectedModelId)
      }
      guard let chatId else { return }
      let accessing = fileURL.startAccessingSecurityScopedResource()
      defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
      let uploaded = try await api.uploadFile(chatId: chatId, fileURL: fileURL)
      pendingAttachments.append(uploaded)
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// A photo straight off the camera.
  func attach(capturedImage image: UIImage) async {
    await attachStaged { try MediaAttach.stage(image: image, basename: MediaAttach.timestampedName("照片")) }
  }

  /// A pick from the photo library, already loaded as data by the picker.
  func attach(photoData data: Data, type: UTType?) async {
    await attachStaged {
      try MediaAttach.stage(photoData: data, type: type, basename: MediaAttach.timestampedName("照片"))
    }
  }

  private func attachStaged(_ stage: () throws -> URL) async {
    do {
      let url = try stage()
      await attach(fileURL: url)
      try? FileManager.default.removeItem(at: url)
    } catch {
      self.error = error.localizedDescription
    }
  }

  func removeAttachment(at index: Int) {
    guard pendingAttachments.indices.contains(index) else { return }
    pendingAttachments.remove(at: index)
  }

  func applyEvent(_ event: [String: Any]) {
    guard let type = event["type"] as? String else { return }
    if type == "connected" { return }

    let eventChatId = event["chatId"] as? String
    if let eventChatId, let chatId, eventChatId != chatId { return }
    if chatId == nil, let eventChatId {
      chatId = eventChatId
    }

    switch type {
    case "chat:title":
      if let t = event["title"] as? String, !t.isEmpty { title = t }

    case "task:start":
      if let messageId = event["messageId"] as? String {
        promotePlaceholder(to: messageId, keepText: true)
        streamingMessageId = messageId
        upsertAssistant(messageId: messageId) { $0.isStreaming = true }
      }
      if let taskId = event["taskId"] as? String {
        activeTaskId = taskId
      }
      startPolling()

    case "task:text-delta":
      guard let messageId = event["messageId"] as? String,
            let delta = event["delta"] as? String else { return }
      promotePlaceholder(to: messageId, keepText: false)
      upsertAssistant(messageId: messageId) { msg in
        msg.text += delta
        msg.isStreaming = true
      }

    case "task:reasoning-delta":
      // Keep thinking indicator until first text delta / finish.
      break

    case "task:reset":
      guard let messageId = event["messageId"] as? String else { return }
      promotePlaceholder(to: messageId, keepText: false)
      upsertAssistant(messageId: messageId) { msg in
        msg.text = ""
        msg.isStreaming = true
      }

    case "task:finish":
      finishTurn(messageId: event["messageId"] as? String, error: event["error"] as? String)

    case "new_message", "chat:compacted":
      Task { await reloadAfterFinish() }

    default:
      break
    }
  }

  // MARK: - Polling fallback (when SSE misses finish)

  /// Safety net only — a turn ends because the server says so, never because a
  /// client timer ran out. A cold sandbox plus a few tool calls routinely runs
  /// for minutes, and the old fixed 40-tick budget cut the transcript off at
  /// 100s while the run was still going.
  private static let pollDeadline: TimeInterval = 30 * 60

  private func startPolling() {
    stopPolling()
    guard chatId != nil else { return }
    turnStartedAt = Date()
    pollTask = Task { [weak self] in
      let deadline = Date().addingTimeInterval(Self.pollDeadline)
      // Tight at first (most turns finish quickly), easing off so a long run
      // isn't hammering the endpoint for minutes.
      var interval: UInt64 = 2_000_000_000
      while Date() < deadline {
        try? await Task.sleep(nanoseconds: interval)
        guard let self, !Task.isCancelled else { return }
        await self.pollOnce()
        if self.activeTaskId == nil && !self.messages.contains(where: { $0.isStreaming }) {
          return
        }
        interval = min(interval + 1_000_000_000, 10_000_000_000)
      }
      // Past the safety cap we still don't claim it finished: reload once so a
      // completed run lands, and leave anything still running alone.
      await self?.pollOnce()
    }
  }

  private func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }

  private func pollOnce() async {
    guard let chatId else { return }
    do {
      if let task = try await api.latestTask(chatId: chatId) {
        let status = task.status
        if status == "running" || status == "queued" {
          activeTaskId = task.id
          return
        }
        // Terminal — reload transcript and clear streaming.
        await reloadAfterFinish()
        if let err = task.error, !err.isEmpty,
           let idx = messages.lastIndex(where: { $0.role == "assistant" }),
           messages[idx].text.isEmpty {
          messages[idx].text = err
        }
        return
      }
      // No task row yet. Right after send the worker may not have claimed one,
      // so treating that as "finished" would kill the turn before it starts —
      // stay put until the grace window has passed.
      if isBusy, Date().timeIntervalSince(turnStartedAt) > Self.taskRowGrace {
        await reloadAfterFinish()
      }
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      // Ignore transient poll errors.
    }
  }

  private func finishTurn(messageId: String?, error: String?) {
    if let messageId {
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        msg.isStreaming = false
        if let error, !error.isEmpty, msg.text.isEmpty {
          msg.text = error
        }
      }
    }
    clearStreamingFlags()
    activeTaskId = nil
    CapkaFeedback.replyCompleted(preview: messages.last(where: { $0.role == "assistant" })?.text)
    Task { await reloadAfterFinish() }
  }

  private func reloadAfterFinish() async {
    guard let chatId else {
      clearStreamingFlags()
      return
    }
    do {
      let loaded = try await api.fetchMessages(chatId: chatId)
      if !loaded.isEmpty {
        // Preserve any richer local streaming text if the snapshot is briefly empty.
        messages = loaded.map { server in
          guard server.text.isEmpty,
                let local = messages.first(where: { $0.id == server.id }),
                !local.text.isEmpty
          else { return server }
          var merged = server
          merged.text = local.text
          merged.isStreaming = false
          return merged
        }
      }
    } catch {
      // keep local
    }
    clearStreamingFlags()
    activeTaskId = nil
    stopPolling()
  }

  private func clearStreamingFlags() {
    for i in messages.indices where messages[i].isStreaming {
      messages[i].isStreaming = false
    }
    // Drop empty pending placeholders left behind.
    messages.removeAll { $0.id.hasPrefix("pending-") && $0.text.isEmpty }
    streamingMessageId = nil
  }

  private func removePlaceholder(_ id: String) {
    messages.removeAll { $0.id == id }
    if streamingMessageId == id { streamingMessageId = nil }
  }

  /// Replace pending-* row with the real server message id (ForEach-safe).
  private func promotePlaceholder(to realId: String, keepText: Bool) {
    guard let idx = messages.firstIndex(where: { $0.id.hasPrefix("pending-") }) else { return }
    let old = messages[idx]
    messages.remove(at: idx)
    if let existing = messages.firstIndex(where: { $0.id == realId }) {
      if keepText, messages[existing].text.isEmpty, !old.text.isEmpty {
        messages[existing].text = old.text
      }
      messages[existing].isStreaming = true
    } else {
      messages.insert(
        ChatUIMessage(id: realId, role: "assistant", text: keepText ? old.text : "", isStreaming: true),
        at: min(idx, messages.count)
      )
    }
    streamingMessageId = realId
  }

  private func upsertAssistant(messageId: String, mutate: (inout ChatUIMessage) -> Void) {
    if let idx = messages.firstIndex(where: { $0.id == messageId }) {
      mutate(&messages[idx])
    } else if let idx = messages.firstIndex(where: { $0.id.hasPrefix("pending-") }) {
      let old = messages[idx]
      messages.remove(at: idx)
      var msg = ChatUIMessage(id: messageId, role: "assistant", text: old.text, isStreaming: true)
      mutate(&msg)
      messages.insert(msg, at: min(idx, messages.count))
    } else {
      var msg = ChatUIMessage(id: messageId, role: "assistant", text: "", isStreaming: true)
      mutate(&msg)
      messages.append(msg)
    }
  }
}
