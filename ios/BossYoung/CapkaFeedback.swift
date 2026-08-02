import Foundation
import UserNotifications
import AudioToolbox
#if os(macOS)
  import AppKit
#endif
#if os(iOS)
  import UIKit
#endif

/// Haptics, a soft system sound, and a local notification when an assistant
/// reply finishes. Also owns a short `beginBackgroundTask` so a turn started
/// just before swipe-to-home can still be seen through (≈30s Apple budget — not
/// indefinite).
///
/// While backgrounded the app polls `latestTask` for the watched chat, because
/// the SSE stream is the first thing the system tears down. Background-task
/// expiration must NOT be treated as "reply done" — keep expecting the real
/// running→terminal edge, and check again when the user returns.
@MainActor
enum CapkaFeedback {
  #if os(iOS)
    private static var bgTask = UIBackgroundTaskIdentifier.invalid
  #endif
  private static var expectingReply = false
  private static var permissionRequested = false
  private static var pollTimer: Timer?
  /// Chat whose task we poll while backgrounded.
  private static var watchedChatId: String?
  /// Require two consecutive terminal reads so one flaky response can't fire early.
  private static var consecutiveIdlePolls = 0
  private static var pollInFlight = false

  /// "Is the user looking at us right now" — the one thing both platforms need
  /// from the app lifecycle, spelled very differently on each.
  private static var isFrontmost: Bool {
    #if os(macOS)
      return NSApplication.shared.isActive
    #else
      return UIApplication.shared.applicationState == .active
    #endif
  }

  static func requestNotificationPermissionIfNeeded() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      Task { @MainActor in
        guard !permissionRequested else { return }
        permissionRequested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
      }
    }
  }

  /// Call when a turn has been queued and the assistant is generating.
  static func replyStarted(chatId: String?) {
    expectingReply = true
    watchedChatId = chatId
    consecutiveIdlePolls = 0
    requestNotificationPermissionIfNeeded()
    if !Self.isFrontmost {
      beginReplyBackgroundTask()
      startBackgroundPoll()
    }
  }

  static func replyCompleted(preview: String?) {
    guard expectingReply else {
      stopBackgroundPoll()
      endReplyBackgroundTask()
      return
    }
    expectingReply = false
    watchedChatId = nil
    consecutiveIdlePolls = 0
    Platform.successFeedback()
    AudioServicesPlaySystemSound(1007) // soft "tweet" / mail-sent style
    notifyIfNotActive(preview: preview)
    stopBackgroundPoll()
    endReplyBackgroundTask()
  }

  /// The user stopped the turn — drop the watch without the completion chime.
  static func replyAbandoned() {
    expectingReply = false
    watchedChatId = nil
    consecutiveIdlePolls = 0
    stopBackgroundPoll()
    endReplyBackgroundTask()
  }

  /// Extend runtime while a reply may still be streaming after leaving the app.
  static func applicationDidEnterBackground() {
    // Do not request notification permission here — backgrounding during login
    // would cover the sign-in composition with the system prompt.
    guard expectingReply else { return }
    consecutiveIdlePolls = 0
    beginReplyBackgroundTask()
    startBackgroundPoll()
  }

  static func applicationWillEnterForeground() {
    stopBackgroundPoll()
    endReplyBackgroundTask()
    guard expectingReply else { return }
    // The turn may well have finished while the process was suspended; one
    // immediate read surfaces it instead of waiting on a reconnected stream.
    consecutiveIdlePolls = 0
    pollTaskStatus(requireConsecutiveIdle: false)
  }

  private static func notifyIfNotActive(preview: String?) {
    // inactive (Control Center / app switcher) + background both need a banner.
    guard !Self.isFrontmost else { return }
    let trimmed = preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let content = UNMutableNotificationContent()
    content.title = "回答已完成"
    content.body = trimmed.isEmpty ? "打开 App 查看完整回复" : String(trimmed.prefix(120))
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: "capka.reply.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
  }

  private static func beginReplyBackgroundTask() {
    #if os(iOS)
    guard bgTask == .invalid else { return }
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "capka.reply") {
      // Time budget exhausted (~30s). Do NOT pretend the reply finished — keep
      // expectingReply so the foreground check can still notify.
      Task { @MainActor in
        stopBackgroundPoll()
        endReplyBackgroundTask()
      }
    }
    #endif
  }

  private static func endReplyBackgroundTask() {
    #if os(iOS)
    guard bgTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(bgTask)
    bgTask = .invalid
    #endif
  }

  private static func startBackgroundPoll() {
    stopBackgroundPoll()
    consecutiveIdlePolls = 0
    // Slightly aggressive while we still have a background budget.
    let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      Task { @MainActor in pollTaskStatus(requireConsecutiveIdle: true) }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    pollTaskStatus(requireConsecutiveIdle: true)
  }

  private static func stopBackgroundPoll() {
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private static func pollTaskStatus(requireConsecutiveIdle: Bool) {
    guard expectingReply, !pollInFlight, let chatId = watchedChatId else { return }
    pollInFlight = true
    Task {
      defer { pollInFlight = false }
      let api = CapkaAPIClient.shared
      let snapshot: CapkaAPIClient.TaskSnapshot?
      do {
        snapshot = try await api.latestTask(chatId: chatId)
      } catch {
        // Transient — a dropped request is not evidence the turn ended.
        return
      }
      guard expectingReply, watchedChatId == chatId else { return }
      if snapshot?.status == "running" || snapshot?.status == "queued" {
        consecutiveIdlePolls = 0
        return
      }
      if requireConsecutiveIdle {
        consecutiveIdlePolls += 1
        guard consecutiveIdlePolls >= 2 else { return }
      }
      // Body copy for the banner; a failed fetch just falls back to the default.
      let preview = (try? await api.fetchMessages(chatId: chatId))?
        .last(where: { $0.role == "assistant" })?.text
      guard expectingReply, watchedChatId == chatId else { return }
      replyCompleted(preview: preview)
    }
  }
}
