import Foundation
import UIKit
import LarkSSOSDK

/// Feishu Mobile SSO (LarkSSO): jump to Feishu app, return via App ID scheme,
/// then Capka completes login via `/api/auth/feishu/native` and injects the session cookie.
enum FeishuNativeSSO {
  static let feishuAppId = "cli_aae198a5e278dcc7"
  static var feishuScheme: String { feishuAppId.replacingOccurrences(of: "_", with: "") }

  static let startNotification = Notification.Name("capka.feishuNativeSSO.start")
  static let resultNotification = Notification.Name("capka.feishuNativeSSO.result")

  private static var registered = false
  private static let host = FeishuSSOHostController()
  /// Dedup: SwiftUI `onOpenURL` + UIApplicationDelegate can both deliver the same return URL.
  private static var lastCode: String?
  private static var lastCodeAt: Date?

  static func registerIfNeeded() {
    guard !registered else { return }
    registered = true
    LarkSSO.register(apps: [
      LarkSSOSDK.App(server: .feishu, appId: feishuAppId, scheme: feishuScheme),
    ])
    LarkSSO.setupLang("zh")
    _ = LarkSSO.setupLog()
  }

  @discardableResult
  static func handleOpenURL(_ url: URL) -> Bool {
    registerIfNeeded()
    return LarkSSO.handleURL(url)
  }

  /// Returns true once per auth code (30s window) so a double URL delivery does not
  /// burn the one-time Feishu code on a second exchange.
  static func shouldHandleCode(_ code: String) -> Bool {
    let now = Date()
    if lastCode == code, let at = lastCodeAt, now.timeIntervalSince(at) < 30 {
      return false
    }
    lastCode = code
    lastCodeAt = now
    return true
  }

  static func start(from presenter: UIViewController) {
    registerIfNeeded()
    let request = SSORequest(
      server: .feishu,
      scope: [
        "contact:user.base:readonly",
        "contact:user.email:readonly",
      ],
      useChallengeCode: true
    )
    LarkSSO.send(request: request, viewController: presenter, delegate: host)
  }

  static func nativeCallbackURL(code: String, codeVerifier: String?) -> URL? {
    var c = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)
    c?.path = "/api/auth/feishu/native"
    var items = [URLQueryItem(name: "code", value: code)]
    if let codeVerifier, !codeVerifier.isEmpty {
      items.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
    }
    c?.queryItems = items
    return c?.url
  }

  static func nativeExchangeURL() -> URL {
    AppConfig.baseURL.appendingPathComponent("api/auth/feishu/native")
  }
}

private final class FeishuSSOHostController: NSObject, LarkSSODelegate {
  func lkSSODidReceive(response: SSOResponse) {
    if response.isSuccess, response.codeVerifier != nil {
      response.safeHandleResultWithCodeVerifier { code, verifier in
        guard FeishuNativeSSO.shouldHandleCode(code) else { return }
        NotificationCenter.default.post(
          name: FeishuNativeSSO.resultNotification,
          object: nil,
          userInfo: ["code": code, "codeVerifier": verifier]
        )
      } failure: { err in
        Self.postFailure(err)
      }
    } else {
      response.safeHandleResult { code in
        guard FeishuNativeSSO.shouldHandleCode(code) else { return }
        NotificationCenter.default.post(
          name: FeishuNativeSSO.resultNotification,
          object: nil,
          userInfo: ["code": code]
        )
      } failure: { err in
        Self.postFailure(err)
      }
    }
  }

  private static func postFailure(_ err: SSOError) {
    if err.type == .cancelled { return }
    NotificationCenter.default.post(
      name: FeishuNativeSSO.resultNotification,
      object: nil,
      userInfo: ["error": err.localizedDescription]
    )
  }
}
