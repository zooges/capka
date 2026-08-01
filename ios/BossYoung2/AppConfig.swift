import Foundation

enum AppConfig {
  /// Capka origin for 邦信阳 (capka2 / BossYoung2).
  static let baseURL = URL(string: "https://agent.boss-young.com")!

  static let brandBurgundy = (r: 0x8B / 255.0, g: 0x1E / 255.0, b: 0x23 / 255.0)
  static let brandCream = (r: 0xF0 / 255.0, g: 0xED / 255.0, b: 0xE8 / 255.0)

  /// Deep-link scheme for this app only (must not collide with 邦信阳 `bossyoung://`).
  static let urlScheme = "bossyoung2"

  static let openURLNotification = Notification.Name("capka.openURL")

  static func isFeishuAuthHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    let roots = ["feishu.cn", "feishu.net", "larksuite.com", "larkoffice.com"]
    return roots.contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  static func isFeishuAuthorizeURL(_ url: URL) -> Bool {
    guard isFeishuAuthHost(url.host) else { return false }
    let path = url.path.lowercased()
    return path.contains("/authen/") && path.contains("authorize")
  }

  /// Capka + Feishu / Lark hosts stay inside the shell.
  static func allowsInAppNavigation(to url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    if let app = baseURL.host?.lowercased(), host == app || host.hasSuffix(".\(app)") {
      return true
    }
    let feishu = [
      "feishu.cn", "feishu.net",
      "larksuite.com", "larkoffice.com", "larksuitecdn.com",
      "bytedance.com", "byteoversea.com", "byteimg.com",
    ]
    return feishu.contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  /// Open with UIApplication (jump to Feishu app) — never load in WKWebView.
  static func isExternalAppScheme(_ scheme: String) -> Bool {
    let s = scheme.lowercased()
    let prefixes = [
      "feishu", "lark", "larksso", "larkoffice",
      "bytedance", "snssdk", "aweme",
      "itms-apps", "itms-appss", "itunes",
    ]
    return prefixes.contains { s == $0 || s.hasPrefix("\($0).") || s.hasPrefix("\($0)+") }
  }

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
