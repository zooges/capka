import SwiftUI
import UserNotifications

@main
struct BossYoungApp: SwiftUI.App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var session = SessionStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(session)
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
        }
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background:
            CapkaFeedback.applicationDidEnterBackground()
          case .active:
            CapkaFeedback.applicationWillEnterForeground()
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
    return true
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
