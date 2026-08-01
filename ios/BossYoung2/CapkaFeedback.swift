import Foundation
import UIKit
import UserNotifications
import AudioToolbox
import WebKit

/// Haptics, soft system sound, and local notification when an assistant
/// reply finishes. Also owns a short `beginBackgroundTask` so WKWebView can
/// finish an in-flight turn after swipe-to-home (≈30s Apple limit — not indefinite).
///
/// While backgrounded, JS `setInterval` is heavily throttled, so we poll the
/// page from native on a Timer for the duration of the background task.
/// Background-task expiration must NOT be treated as “reply done” — keep
/// expecting the real busy→idle edge (or check again when the user returns).
enum CapkaFeedback {
  private static let impact = UINotificationFeedbackGenerator()
  private static var bgTask = UIBackgroundTaskIdentifier.invalid
  private static var expectingReply = false
  private static var permissionRequested = false
  private static var pollTimer: Timer?
  private static weak var pollWebView: WKWebView?
  /// Require two consecutive idle polls so a transient DOM gap does not fire early.
  private static var consecutiveIdlePolls = 0
  /// After iOS ends our background budget, wait until foreground to confirm completion.
  private static var pendingForegroundCheck = false
  private static var lastPreview: String?

  static func bindWebView(_ webView: WKWebView?) {
    pollWebView = webView
  }

  static func requestNotificationPermissionIfNeeded() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        guard !permissionRequested else { return }
        permissionRequested = true
        DispatchQueue.main.async {
          center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
      case .denied:
        break
      default:
        break
      }
    }
  }

  /// Call when the page reports the assistant is generating (`replyBusy`).
  static func replyStarted() {
    DispatchQueue.main.async {
      expectingReply = true
      pendingForegroundCheck = false
      consecutiveIdlePolls = 0
      lastPreview = nil
      requestNotificationPermissionIfNeeded()
      if UIApplication.shared.applicationState != .active {
        beginReplyBackgroundTask()
        startBackgroundPoll()
      }
    }
  }

  static func replyCompleted(preview: String?) {
    DispatchQueue.main.async {
      guard expectingReply else {
        endReplyBackgroundTask()
        stopBackgroundPoll()
        return
      }
      expectingReply = false
      pendingForegroundCheck = false
      consecutiveIdlePolls = 0
      let text = preview ?? lastPreview
      impact.prepare()
      impact.notificationOccurred(.success)
      AudioServicesPlaySystemSound(1007) // soft "tweet" / mail-sent style
      notifyIfNotActive(preview: text)
      stopBackgroundPoll()
      endReplyBackgroundTask()
    }
  }

  /// Extend runtime while a reply may still be streaming after leaving the app.
  static func applicationDidEnterBackground() {
    requestNotificationPermissionIfNeeded()
    if expectingReply {
      consecutiveIdlePolls = 0
      beginReplyBackgroundTask()
      startBackgroundPoll()
    }
  }

  static func applicationWillEnterForeground() {
    stopBackgroundPoll()
    endReplyBackgroundTask()
    guard expectingReply else { return }
    // JS may have missed the busy→idle edge while suspended; poll once (and
    // briefly again) so a finished reply still surfaces as 回答已完成 if needed.
    pendingForegroundCheck = true
    consecutiveIdlePolls = 0
    DispatchQueue.main.async {
      pollBusyFromWebView(requireConsecutiveIdle: false)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard expectingReply else { return }
      pollBusyFromWebView(requireConsecutiveIdle: false)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      guard expectingReply else { return }
      pollBusyFromWebView(requireConsecutiveIdle: false)
      pendingForegroundCheck = false
    }
  }

  private static func notifyIfNotActive(preview: String?) {
    // inactive (Control Center / app switcher) + background both need a banner.
    guard UIApplication.shared.applicationState != .active else { return }
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
    guard bgTask == .invalid else { return }
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "capka.reply") {
      // Time budget exhausted (~30s). Do NOT pretend the reply finished —
      // keep expectingReply so foreground / a late JS bridge can still notify.
      DispatchQueue.main.async {
        stopBackgroundPoll()
        // One last attempt before the process may suspend.
        if expectingReply {
          pendingForegroundCheck = true
          pollBusyFromWebView(requireConsecutiveIdle: false)
        }
        endReplyBackgroundTask()
      }
    }
  }

  private static func endReplyBackgroundTask() {
    guard bgTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(bgTask)
    bgTask = .invalid
  }

  private static func startBackgroundPoll() {
    stopBackgroundPoll()
    consecutiveIdlePolls = 0
    // Slightly aggressive while we still have a background budget.
    let timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
      pollBusyFromWebView(requireConsecutiveIdle: true)
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    pollBusyFromWebView(requireConsecutiveIdle: true)
  }

  private static func stopBackgroundPoll() {
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private static func pollBusyFromWebView(requireConsecutiveIdle: Bool) {
    guard expectingReply, let webView = pollWebView else { return }
    let js = """
    (function(){
      var busy = false;
      try {
        busy = document.body && document.body.getAttribute('data-capka-busy') === '1';
      } catch (e) {}
      if (!busy) {
        try {
          busy = !!(
            document.querySelector('[data-task-busy="1"]') ||
            document.querySelector('button[aria-label*="停止"], button[aria-label*="Stop"], button[title*="停止"], button[title*="Stop"]')
          );
        } catch (e) {}
      }
      var text = '';
      if (!busy) {
        try {
          var nodes = document.querySelectorAll('[data-role="assistant"], [data-message-role="assistant"]');
          if (nodes.length) text = (nodes[nodes.length - 1].innerText || '').trim().slice(0, 120);
          if (!text) {
            var arts = document.querySelectorAll('[data-slot="message"], .prose, [class*="assistant"]');
            // last-resort: leave empty — native uses default body copy
          }
        } catch (e) {}
      }
      return JSON.stringify({ busy: !!busy, preview: text });
    })();
    """
    webView.evaluateJavaScript(js) { result, error in
      // evaluateJavaScript often fails once WK is frozen — ignore, keep waiting.
      if error != nil { return }
      guard let raw = result as? String,
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return }
      let busy = obj["busy"] as? Bool ?? true
      if let preview = obj["preview"] as? String, !preview.isEmpty {
        lastPreview = preview
      }
      DispatchQueue.main.async {
        guard expectingReply else { return }
        if busy {
          consecutiveIdlePolls = 0
          return
        }
        if requireConsecutiveIdle {
          consecutiveIdlePolls += 1
          // Two idle samples (~1.4s) avoids a single flaky read.
          guard consecutiveIdlePolls >= 2 else { return }
        }
        replyCompleted(preview: (obj["preview"] as? String) ?? lastPreview)
      }
    }
  }
}
