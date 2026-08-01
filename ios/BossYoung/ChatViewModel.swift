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
  /// Drafts written offline, flushed when the connection returns.
  let outbox = OutboxStore()
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
    outbox.onReconnect = { [weak self] in
      Task { await self?.flushOutbox() }
    }
  }

  /// Send everything queued while offline, oldest first, stopping at the first
  /// failure so ordering is preserved and a still-flaky link doesn't burn the
  /// whole queue.
  func flushOutbox() async {
    let pending = outbox.beginFlush()
    defer { outbox.endFlush() }
    guard !pending.isEmpty else { return }

    for item in pending.sorted(by: { $0.queuedAt < $1.queuedAt }) {
      do {
        let res = try await api.sendMessage(
          chatId: item.chatId ?? chatId,
          text: item.text,
          model: item.modelId ?? selectedModelId,
          userMessageId: item.id,
          attachedFiles: item.attachments.isEmpty
            ? nil
            : item.attachments.map { ["name": $0.name, "type": $0.type] }
        )
        outbox.remove(id: item.id)
        if let index = messages.firstIndex(where: { $0.id == item.id }) {
          messages[index].isQueued = false
        }
        if item.chatId == nil || item.chatId == chatId {
          chatId = res.chatId
          activeTaskId = res.taskId
          CapkaFeedback.replyStarted(chatId: chatId)
          startPolling()
        }
      } catch {
        break
      }
    }
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

  /// Rewrite a user turn and re-run from there. The original stays reachable as
  /// a sibling, so the ‹ i/N › switcher can go back to it.
  func edit(messageId: String, newText: String) async {
    let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let chatId, !isSending, !isBusy else { return }
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

    let history = Array(messages.prefix(index))
    let editedId = UUID().uuidString
    // Editing keeps whatever was attached to the original turn.
    let attachments = messages[index].attachments

    messages = history
    messages.append(ChatUIMessage(id: editedId, role: "user", text: text, isStreaming: false, attachments: attachments))
    let placeholderId = "pending-\(editedId)"
    messages.append(ChatUIMessage(id: placeholderId, role: "assistant", text: "", isStreaming: true))
    streamingMessageId = placeholderId
    isSending = true
    error = nil

    do {
      let res = try await api.editMessage(
        chatId: chatId,
        newText: text,
        editedMessageId: editedId,
        model: selectedModelId,
        history: history,
        attachedFiles: attachments.isEmpty
          ? nil
          : attachments.map { ["name": $0.name, "type": $0.type] }
      )
      self.chatId = res.chatId
      activeTaskId = res.taskId
      CapkaFeedback.replyStarted(chatId: self.chatId)
      startPolling()
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
      removePlaceholder(placeholderId)
    } catch {
      self.error = error.localizedDescription
      removePlaceholder(placeholderId)
      // A failed edit must not leave the transcript truncated.
      await load()
    }
    isSending = false
  }

  /// True while the agent is waiting on an answer — the composer stands down so
  /// the question card is the one next action, as on the web.
  var awaitingInput: Bool {
    messages.contains { msg in
      msg.groups.contains { group in
        if case .ask(let card) = group { return card.isAwaiting }
        if case .approval(let card) = group { return card.isAwaiting }
        return false
      }
    }
  }

  /// Record an approval decision. Like `ask`, this resumes the same turn.
  func decideApproval(_ card: ApprovalCardData, messageId: String, approved: Bool) async {
    do {
      try await api.respondToApproval(
        messageId: messageId,
        toolCallId: card.toolCallId,
        approved: approved
      )
      CapkaFeedback.replyStarted(chatId: chatId)
      startPolling()
    } catch {
      self.error = error.localizedDescription
      await load()
    }
  }

  /// Answer a suspended question. This resumes the same turn server-side, so
  /// there is nothing to append locally — the reload settles the card.
  func answerAsk(_ card: AskCardData, messageId: String, action: String, values: [String: [String]]) async {
    do {
      try await api.answerAsk(
        messageId: messageId,
        toolCallId: card.toolCallId,
        action: action,
        values: values,
        kind: card.kind
      )
      CapkaFeedback.replyStarted(chatId: chatId)
      startPolling()
    } catch {
      self.error = error.localizedDescription
      await load()
    }
  }

  /// Flip to the previous/next version of a message. The server decides which
  /// branch is visible, so the transcript is reloaded rather than patched.
  func switchBranch(messageId: String, direction: String) async {
    guard let chatId, !isBusy else { return }
    do {
      try await api.switchBranch(chatId: chatId, messageId: messageId, direction: direction)
      await load()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func send() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
    guard !isSending else { return }

    let userId = UUID().uuidString

    // No connection: keep the work rather than throwing an error at a composer
    // we just cleared. The same id is reused on flush, so the turn cannot be
    // created twice.
    guard outbox.isOnline else {
      outbox.enqueue(OutboxStore.Draft(
        id: userId,
        chatId: chatId,
        text: text,
        attachments: pendingAttachments.map { .init(name: $0.name, type: $0.type) },
        modelId: selectedModelId,
        queuedAt: Date()
      ))
      messages.append(ChatUIMessage(
        id: userId,
        role: "user",
        text: text.isEmpty ? "（附件）" : text,
        isStreaming: false,
        isQueued: true
      ))
      draft = ""
      pendingAttachments = []
      return
    }

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

  /// Files handed over by the share extension. They open a fresh chat so a share
  /// never lands in the middle of an unrelated conversation, and they are
  /// attached — not sent — because only the user knows what to ask about them.
  func adoptShared(_ urls: [URL]) async {
    guard !urls.isEmpty else { return }
    if !messages.isEmpty || chatId != nil {
      startNewChat()
    }
    for url in urls {
      await attach(fileURL: url)
      try? FileManager.default.removeItem(at: url)
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
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        msg.appendStreamedText(delta)
        msg.isStreaming = true
      }

    case "task:reasoning-delta":
      guard let messageId = event["messageId"] as? String,
            let delta = event["delta"] as? String, !delta.isEmpty else { return }
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        msg.appendStreamedReasoning(delta, id: "\(messageId)-reason-\(msg.groups.count)")
        msg.isStreaming = true
      }

    case "task:tool-input-start":
      guard let messageId = event["messageId"] as? String,
            let toolCallId = event["toolCallId"] as? String else { return }
      let toolName = (event["toolName"] as? String) ?? ""
      let described = StepDescriber.describe(toolName: toolName, input: nil, running: true)
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        msg.upsertStreamedStep(
          MessageStep(id: toolCallId, kind: .tool, state: .running, label: described.label, icon: described.icon)
        )
        msg.isStreaming = true
      }

    case "task:tool-call":
      guard let messageId = event["messageId"] as? String,
            let toolCallId = event["toolCallId"] as? String else { return }
      let toolName = (event["toolName"] as? String) ?? ""
      let args = event["args"] as? [String: Any]
      let described = StepDescriber.describe(toolName: toolName, input: args, running: true)
      var detail: String?
      if let args {
        detail = (args["command"] as? String) ?? (args["code"] as? String)
      }
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        msg.upsertStreamedStep(
          MessageStep(
            id: toolCallId,
            kind: .tool,
            state: .running,
            label: described.label,
            icon: described.icon,
            detail: detail
          )
        )
        msg.isStreaming = true
      }

    case "task:tool-result":
      guard let messageId = event["messageId"] as? String,
            let toolCallId = event["toolCallId"] as? String else { return }
      let isError = (event["isError"] as? Bool) == true
      let toolName = (event["toolName"] as? String)
      promotePlaceholder(to: messageId, keepText: true)
      let media = (event["result"] as? [String: Any]).flatMap { result -> [String]? in
        guard result["kind"] as? String == "media",
              let pages = result["pages"] as? [[String: Any]] else { return nil }
        return pages.compactMap { $0["path"] as? String }.prefix(4).map { $0 }
      }
      upsertAssistant(messageId: messageId) { msg in
        msg.upsertStreamedStep(
          MessageStep(id: toolCallId, kind: .tool, state: isError ? .failed : .done, label: "", icon: "wrench")
        ) { step in
          step.state = isError ? .failed : .done
          if let toolName, !toolName.isEmpty {
            let described = StepDescriber.describe(toolName: toolName, input: nil, running: false)
            step.label = described.label
            step.icon = described.icon
          } else if step.label.hasSuffix("…") {
            // Soften the running ellipsis once the step settles.
            step.label = String(step.label.dropLast())
          } else if step.label.hasSuffix("...") {
            step.label = String(step.label.dropLast(3))
          }
          if let media { step.imagePaths = media }
        }
        msg.isStreaming = true
      }

    case "task:ask":
      // The event carries the form, so the question card can be built live
      // rather than waiting for the finished turn to reload.
      guard let messageId = event["messageId"] as? String,
            let form = event["form"] as? [String: Any] else { return }
      promotePlaceholder(to: messageId, keepText: true)
      let askCard = CapkaAPIClient.askCard(
        toolCallId: event["toolCallId"] as? String,
        form: form
      )
      upsertAssistant(messageId: messageId) { msg in
        msg.upsertCard(.ask(askCard))
        msg.isStreaming = true
      }

    case "task:tool-approval":
      guard let messageId = event["messageId"] as? String,
            let toolCallId = event["toolCallId"] as? String else { return }
      promotePlaceholder(to: messageId, keepText: true)
      upsertAssistant(messageId: messageId) { msg in
        // Promote the step already on screen into the decision card.
        let label = msg.steps.first(where: { $0.id == toolCallId })?.label ?? "该操作需要你确认"
        msg.upsertCard(.approval(ApprovalCardData(
          toolCallId: toolCallId,
          label: label,
          detail: nil,
          approved: nil,
          reason: nil
        )))
        msg.isStreaming = true
      }

    case "task:reset":
      guard let messageId = event["messageId"] as? String else { return }
      promotePlaceholder(to: messageId, keepText: false)
      upsertAssistant(messageId: messageId) { msg in
        msg.resetGroups()
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
          // SSE may be blocked by a proxy — hydrate text/steps from the
          // persisted snapshot so the activity rail still moves mid-turn.
          await syncLiveMessages()
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

  /// Merge a mid-turn server snapshot onto the live transcript without wiping
  /// richer local SSE text/steps when the snapshot lags a beat.
  private func syncLiveMessages() async {
    guard let chatId else { return }
    do {
      let loaded = try await api.fetchMessages(chatId: chatId)
      guard !loaded.isEmpty else { return }
      let previous = messages
      messages = loaded.map { server in
        var merged = server
        if let local = previous.first(where: { $0.id == server.id }) {
          if local.text.count > server.text.count {
            merged.text = local.text
          }
          if local.steps.count > server.steps.count {
            merged.steps = local.steps
          } else if local.steps.count == server.steps.count {
            // Prefer the longer reasoning detail when both sides have the step.
            merged.steps = zip(server.steps, local.steps).map { s, l in
              var out = s
              if (l.detail?.count ?? 0) > (s.detail?.count ?? 0) {
                out.detail = l.detail
              }
              if out.state == .done || out.state == .failed { return out }
              if l.state == .running { out.state = .running }
              return out
            }
          }
          if local.isStreaming || streamingMessageId == server.id {
            merged.isStreaming = true
          }
        } else if streamingMessageId == server.id || activeTaskId != nil {
          merged.isStreaming = true
        }
        return merged
      }
      // Keep an in-flight placeholder if the server hasn't written the row yet.
      for local in previous where local.id.hasPrefix("pending-") {
        if !messages.contains(where: { $0.id == local.id || ($0.isStreaming && $0.role == "assistant") }) {
          messages.append(local)
        }
      }
    } catch {
      // keep local
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
          guard server.groups.isEmpty, server.text.isEmpty,
                let local = messages.first(where: { $0.id == server.id }),
                !local.groups.isEmpty || !local.text.isEmpty
          else { return server }
          var merged = server
          merged.groups = local.groups
          merged.text = local.text
          merged.steps = local.steps
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
      if keepText, messages[existing].groups.isEmpty, !old.groups.isEmpty {
        messages[existing].groups = old.groups
        messages[existing].rebuildFlattened()
      } else if keepText, messages[existing].text.isEmpty, !old.text.isEmpty {
        messages[existing].text = old.text
      }
      messages[existing].isStreaming = true
    } else {
      var promoted = ChatUIMessage(id: realId, role: "assistant", text: "", isStreaming: true)
      if keepText {
        promoted.groups = old.groups
        promoted.rebuildFlattened()
        if promoted.text.isEmpty { promoted.text = old.text }
      }
      messages.insert(promoted, at: min(idx, messages.count))
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
      msg.groups = old.groups
      if !msg.groups.isEmpty { msg.rebuildFlattened() }
      mutate(&msg)
      messages.insert(msg, at: min(idx, messages.count))
    } else {
      var msg = ChatUIMessage(id: messageId, role: "assistant", text: "", isStreaming: true)
      mutate(&msg)
      messages.append(msg)
    }
  }
}
