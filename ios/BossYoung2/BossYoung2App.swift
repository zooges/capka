import SwiftUI
import UserNotifications

@main
struct BossYoung2App: SwiftUI.App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var session = SessionStore()
  @State private var appLock = AppLock()

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()
          .environment(session)
          .environment(appLock)
        if appLock.isLocked {
          AppLockView(lock: appLock)
            .transition(.opacity)
            .zIndex(10)
        }
      }
        .animation(Motion.easeOut(0.2), value: appLock.isLocked)
        .task { appLock.lockIfEnabled() }
        .onOpenURL { url in
          if FeishuNativeSSO.handleOpenURL(url) {
            return
          }
          if let callback = AppConfig.feishuCallbackURL(fromBridge: url) {
            NotificationCenter.default.post(name: AppConfig.openURLNotification, object: callback)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: FeishuNativeSSO.resultNotification)) { note in
          Task { await session.handleFeishuResult(note.userInfo) }
        }
        // Ask only after sign-in — the login composition must stay unobscured.
        // Feishu SSO is registered lazily on first tap (SDK may prompt for push).
        .onChange(of: session.isAuthenticated) { _, ok in
          if ok { CapkaFeedback.requestNotificationPermissionIfNeeded() }
          PushRegistrar.shared.noteSession(active: ok)
        }
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background:
            CapkaFeedback.applicationDidEnterBackground()
            appLock.noteBackgrounded()
          case .active:
            CapkaFeedback.applicationWillEnterForeground()
            appLock.noteForegrounded()
            if session.isAuthenticated {
              CapkaFeedback.requestNotificationPermissionIfNeeded()
            }
          default:
            break
          }
        }
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    // Registering is cheap and idempotent; the token is only *sent* once there
    // is a session to attach it to (see PushRegistrar).
    application.registerForRemoteNotifications()
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushRegistrar.shared.note(token: deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // No push is a degraded experience, not a broken one — the local
    // notification path still covers turns that finish quickly.
    PushRegistrar.shared.note(token: nil)
  }

  /// Tapping a push opens the chat it came from.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let chatId = response.notification.request.content.userInfo["chatId"] as? String {
      NotificationCenter.default.post(name: PushRegistrar.openChatNotification, object: chatId)
    }
    completionHandler()
  }

  func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    FeishuNativeSSO.handleOpenURL(url)
  }

  /// Show reply-done banners even if a bit of UI is still visible (inactive).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }
}
