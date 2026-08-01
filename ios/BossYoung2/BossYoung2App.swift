import SwiftUI
import UserNotifications

@main
struct BossYoung2App: SwiftUI.App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL { url in
          if FeishuNativeSSO.handleOpenURL(url) {
            return
          }
          if let callback = AppConfig.feishuCallbackURL(fromBridge: url) {
            NotificationCenter.default.post(name: AppConfig.openURLNotification, object: callback)
          }
        }
        .onAppear {
          FeishuNativeSSO.registerIfNeeded()
          CapkaFeedback.requestNotificationPermissionIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background:
            CapkaFeedback.applicationDidEnterBackground()
          case .active:
            CapkaFeedback.applicationWillEnterForeground()
            CapkaFeedback.requestNotificationPermissionIfNeeded()
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
    FeishuNativeSSO.registerIfNeeded()
    UNUserNotificationCenter.current().delegate = self
    CapkaFeedback.requestNotificationPermissionIfNeeded()
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
