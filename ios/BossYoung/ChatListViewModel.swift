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

  let api = CapkaAPIClient.shared
  weak var session: SessionStore?

  func bind(session: SessionStore) {
    self.session = session
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
      error = nil
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      if showError {
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
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
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
