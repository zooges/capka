import Foundation

enum AppConfig {
  /// Fixed Capka origin — HTTP IP deploy (no tunnel domain).
  static let baseURL = URL(string: "http://111.231.24.43:3100")!

  /// Deep-link scheme (Share Extension + Feishu bridge). Keep in sync with Info.plist.
  static let urlScheme = "bossyoung"

  static let openURLNotification = Notification.Name("capka.openURL")
  /// Workspace listing should reload (agent wrote a file, markup uploaded, …).
  static let workspaceDidChangeNotification = Notification.Name("capka.workspace.didChange")

  /// Rebuild the Capka OAuth callback URL from a `bossyoung://oauth?...` deep link.
  static func feishuCallbackURL(fromBridge url: URL) -> URL? {
    guard url.scheme?.lowercased() == urlScheme,
          (url.host?.lowercased() == "oauth" || url.path == "//oauth" || url.path.hasPrefix("/oauth"))
    else { return nil }
    var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    c?.path = "/api/auth/oauth2/callback/feishu"
    c?.query = url.query
    return c?.url
  }
}
