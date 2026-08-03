import Foundation

enum AppConfig {
  /// Capka origin for 邦信阳 (capka2 / BossYoung2).
  static let baseURL = URL(string: "https://agent.boss-young.com")!

  /// Deep-link scheme for this app only (must not collide with 邦信阳 `bossyoung://`).
  static let urlScheme = "bossyoung2"

  static let openURLNotification = Notification.Name("capka.openURL")
  /// Workspace listing should reload (agent wrote a file, markup uploaded, …).
  static let workspaceDidChangeNotification = Notification.Name("capka.workspace.didChange")

  /// Rebuild the Capka OAuth callback URL from a `bossyoung2://oauth?...` deep link.
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
