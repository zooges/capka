import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
  var user: CapkaUser?
  var isRestoring = true
  var authError: String?
  var isLoggingIn = false

  /// Fan-out for chat list / open chat SSE updates.
  var lastEvent: [String: Any]?
  /// Bumps on every event so SwiftUI `onChange` fires even when `type` repeats.
  var eventSeq: Int = 0

  private let api = CapkaAPIClient.shared
  private let sse = SSEClient()

  var isAuthenticated: Bool { user != nil }

  func bootstrap() async {
    isRestoring = true
    defer { isRestoring = false }
    guard api.hasSessionCookie else {
      user = nil
      return
    }
    do {
      user = try await api.getSession()
      if user != nil {
        startRealtime()
      } else {
        // Cookie present but session gone — quiet cleanup, no banner.
        api.clearCookies()
      }
    } catch {
      user = nil
      // Stale cookie + offline must not paint the Feishu-only login screen with
      // a "connection failed" banner before the user has tapped anything.
      // Drop the dead cookie so the next Feishu attempt starts clean.
      api.clearCookies()
    }
  }

  func signInWithEmail(email: String, password: String) async {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !password.isEmpty else {
      authError = "请输入电子邮件和密码"
      return
    }
    isLoggingIn = true
    authError = nil
    defer { isLoggingIn = false }
    do {
      try await api.signInWithEmail(email: trimmed, password: password)
      try await finishCredentialSession()
    } catch {
      authError = error.localizedDescription
      user = nil
    }
  }

  func signUpWithEmail(name: String, email: String, password: String) async {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      authError = "姓名为必填项"
      return
    }
    guard !trimmedEmail.isEmpty, !password.isEmpty else {
      authError = "请输入电子邮件和密码"
      return
    }
    guard password.count >= 8 else {
      authError = "密码太短（至少 8 个字符）"
      return
    }
    isLoggingIn = true
    authError = nil
    defer { isLoggingIn = false }
    do {
      try await api.signUpWithEmail(name: trimmedName, email: trimmedEmail, password: password)
      try await finishCredentialSession()
    } catch {
      authError = error.localizedDescription
      user = nil
    }
  }

  /// Load the session after email sign-in/up; pending accounts stay on the
  /// login screen with a calm approval notice (matching the web pending gate).
  private func finishCredentialSession() async throws {
    let sessionUser = try await api.getSession()
    guard let sessionUser else {
      authError = "登录成功但未能读取会话，请重试"
      return
    }
    if let status = sessionUser.status?.lowercased(), status != "active" {
      api.clearCookies()
      user = nil
      switch status {
      case "pending":
        authError = "账号已创建，正在等待管理员批准"
      case "suspended":
        authError = "您的访问已被暂停，请联系管理员"
      default:
        authError = "账号当前无法登录，请联系管理员"
      }
      return
    }
    user = sessionUser
    startRealtime()
  }

  func handleFeishuResult(_ info: [AnyHashable: Any]?) async {
    if info?["cancelled"] as? Bool == true {
      isLoggingIn = false
      return
    }
    if let err = info?["error"] as? String {
      authError = err
      isLoggingIn = false
      return
    }
    guard let code = info?["code"] as? String else {
      isLoggingIn = false
      return
    }
    isLoggingIn = true
    authError = nil
    defer { isLoggingIn = false }
    do {
      try await api.exchangeFeishuCode(
        code: code,
        codeVerifier: info?["codeVerifier"] as? String
      )
      user = try await api.getSession()
      if user == nil {
        authError = "登录成功但未能读取会话，请重试"
        return
      }
      startRealtime()
    } catch {
      authError = error.localizedDescription
      user = nil
    }
  }

  func signOut() async {
    await sse.stop()
    await api.signOut()
    user = nil
    lastEvent = nil
  }

  func noteUnauthorized() async {
    await sse.stop()
    api.clearCookies()
    user = nil
    authError = "登录已失效，请重新登录"
  }

  private func startRealtime() {
    let store = self
    Task {
      await sse.start { event in
        Task { @MainActor in
          store.lastEvent = event
          store.eventSeq &+= 1
        }
      }
    }
  }
}
