import AuthenticationServices
import SwiftUI

/// Sign-in on macOS.
///
/// The Feishu **native** SDK is iOS-only — `LarkSSOSDK.xcframework` ships
/// `ios-arm64` and an iOS simulator slice, and nothing else — so the Mac cannot
/// jump to the Feishu app the way the phone does. It uses the same web OAuth
/// round-trip the browser client uses instead, in an
/// `ASWebAuthenticationSession`, which keeps the flow inside the app and hands
/// the session cookie back to the shared `CapkaAPIClient`.
struct MacLoginView: View {
  @Environment(SessionStore.self) private var session

  @State private var email = ""
  @State private var password = ""
  @State private var feishuEnabled = false
  @State private var webAuth: WebAuthCoordinator?

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)

      VStack(spacing: 18) {
        Image("BrandWordmark")
          .resizable()
          .scaledToFit()
          .frame(height: 38)
          .accessibilityLabel("邦信阳律师事务所")

        if let error = session.authError {
          Text(error)
            .font(.system(size: 12))
            .foregroundStyle(Brand.dangerText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(spacing: 10) {
          TextField("输入工作邮箱", text: $email)
            .textContentType(.username)
          SecureField("输入密码", text: $password)
            .textContentType(.password)
            .onSubmit { signIn() }
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 300)

        Button(session.isLoggingIn ? "正在登录…" : "登录") { signIn() }
          .keyboardShortcut(.return)
          .disabled(session.isLoggingIn || email.isEmpty || password.isEmpty)

        if feishuEnabled {
          Divider().frame(width: 240)
          Button {
            startFeishu()
          } label: {
            HStack(spacing: 6) {
              Image("FeishuGlyph").resizable().scaledToFit().frame(width: 16, height: 16)
              Text("使用飞书登录").font(.system(size: 13))
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(Brand.link)
          .disabled(session.isLoggingIn)
        }
      }
      .padding(40)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.cream)
    .task {
      // Only offer Feishu when the instance actually has it configured.
      feishuEnabled = await CapkaAPIClient.shared.isFeishuLoginEnabled()
    }
  }

  private func signIn() {
    Task { await session.signInWithEmail(email: email, password: password) }
  }

  private func startFeishu() {
    let coordinator = WebAuthCoordinator()
    webAuth = coordinator
    coordinator.start { success in
      webAuth = nil
      guard success else { return }
      // The round-trip set the session cookie in the shared storage; picking the
      // session up is the same call every other entry point makes.
      Task { await session.bootstrap() }
    }
  }
}

/// Runs the web OAuth round-trip in a system sheet. Held as state for its
/// lifetime — an `ASWebAuthenticationSession` that is released mid-flow cancels
/// itself.
@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?

  func start(completion: @escaping (Bool) -> Void) {
    guard let url = CapkaAPIClient.shared.feishuWebSignInURL() else {
      completion(false)
      return
    }
    let session = ASWebAuthenticationSession(
      url: url,
      // The server finishes on its own origin and sets the cookie there; there
      // is no custom scheme to catch, so the sheet is dismissed by the user or
      // by the callback page.
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
