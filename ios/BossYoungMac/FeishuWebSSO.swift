import AppKit
import AuthenticationServices

/// Feishu sign-in on macOS.
///
/// `LarkSSOSDK.xcframework` ships `ios-arm64` and an iOS simulator slice and
/// nothing else, so the Mac cannot hand off to the Feishu app the way the phone
/// does. It runs the same web OAuth round-trip the browser client uses, inside
/// an `ASWebAuthenticationSession` — the flow stays in the app, and the session
/// cookie lands in the shared storage `CapkaAPIClient` reads.
@MainActor
enum FeishuWebSSO {
  /// The session cancels itself if it is released mid-flow, so it outlives the
  /// call that started it.
  private static var active: Session?

  static func start(completion: @escaping (Bool) -> Void) {
    guard let url = CapkaAPIClient.shared.feishuWebSignInURL() else {
      completion(false)
      return
    }
    let session = Session()
    active = session
    session.run(url: url) { ok in
      active = nil
      completion(ok)
    }
  }

  @MainActor
  final class Session: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(url: URL, completion: @escaping (Bool) -> Void) {
      let session = ASWebAuthenticationSession(
        url: url,
        // The server finishes on its own origin and sets the cookie there, so
        // there is no custom scheme to catch — the sheet closes on the callback
        // page or when the user dismisses it.
        callbackURLScheme: nil
      ) { _, error in
        completion(error == nil)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      session.start()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
      MainActor.assumeIsolated { NSApplication.shared.keyWindow ?? ASPresentationAnchor() }
    }
  }
}
