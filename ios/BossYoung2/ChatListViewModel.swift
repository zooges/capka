import Foundation
import Observation

@MainActor
@Observable
final class ChatListViewModel {
  var chats: [ChatSummary] = []
  var isLoading = false
  var isLoadingMore = false
  var error: String?
  var nextCursor: String?
  /// The spinner belongs to the first load only. Once rows have arrived, a later
  /// fetch updates them in place instead of replacing the list with a spinner.
  var hasLoaded = false

  let api = CapkaAPIClient.shared
  weak var session: SessionStore?

  func bind(session: SessionStore) {
    self.session = session
  }

  init() {
    let cached = ChatDiskCache.shared.loadChatList()
    if !cached.isEmpty {
      chats = cached
      hasLoaded = true
    }
  }

  func refresh() async {
    await refresh(showError: true)
  }

  /// Used on home preload — failures stay silent so the composer still works.
  func refreshQuietly() async {
    await refresh(showError: false)
  }

  private func refresh(showError: Bool) async {
    isLoading = true
    if showError { error = nil }
    defer { isLoading = false }
    do {
      let page = try await api.listChats()
      chats = page.chats
      nextCursor = page.nextCursor
      hasLoaded = true
      error = nil
      ChatDiskCache.shared.saveChatList(page.chats)
      ChatDiskCache.shared.prefetchRecentMessages(chatIds: page.chats.map(\.id))
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch is CancellationError {
      return
    } catch {
      if chats.isEmpty, let cached = Optional(ChatDiskCache.shared.loadChatList()), !cached.isEmpty {
        chats = cached
        hasLoaded = true
      }
      if showError && chats.isEmpty {
        self.error = error.localizedDescription
      }
    }
  }

  func loadMore() async {
    guard let cursor = nextCursor, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await api.listChats(cursor: cursor)
      chats.append(contentsOf: page.chats)
      nextCursor = page.nextCursor
      ChatDiskCache.shared.saveChatList(chats)
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch is CancellationError {
      return
    } catch {
      self.error = error.localizedDescription
    }
  }

  func createChat() async -> String? {
    do {
      let id = try await api.createChat(title: "新对话")
      await refresh()
      return id
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
      return nil
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  func applyEvent(_ event: [String: Any]) {
    guard let type = event["type"] as? String else { return }
    if type == "chat:title", let chatId = event["chatId"] as? String, let title = event["title"] as? String {
      if let idx = chats.firstIndex(where: { $0.id == chatId }) {
        chats[idx] = ChatSummary.mutated(chats[idx], title: title)
      }
      return
    }
    if type == "task:start" || type == "task:finish" || type == "new_message" {
      Task { await refreshQuietly() }
    }
  }
}
