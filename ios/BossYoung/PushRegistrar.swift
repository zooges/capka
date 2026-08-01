import Foundation
import Observation

/// Holds the APNs device token and hands it to the server once there is a
/// session to attach it to.
///
/// The two events arrive in either order — iOS can deliver the token before the
/// user has signed in, and a session can be restored before the token lands — so
/// both paths call `flush()` and it does nothing until it has both. Without a
/// push, a turn that outlives iOS's ~30s background budget is simply never
/// announced; the local-notification path only covers the short ones.
@MainActor
@Observable
final class PushRegistrar {
  static let shared = PushRegistrar()

  /// Posted with the chat id when the user taps a push.
  static let openChatNotification = Notification.Name("capka.push.openChat")

  private var token: String?
  private var registeredToken: String?
  private var hasSession = false

  /// A build signed with a development profile talks to APNs sandbox; the App
  /// Store / TestFlight build talks to production. The token doesn't say which,
  /// so sending to the wrong host fails with BadDeviceToken.
  private var environment: String {
    #if DEBUG
      return "sandbox"
    #else
      return "production"
    #endif
  }

  func note(token: String?) {
    self.token = token
    flush()
  }

  func noteSession(active: Bool) {
    hasSession = active
    if !active {
      // Stop this device receiving the previous user's replies. Best effort: a
      // failed unregister is corrected by the next sign-in's upsert.
      if let registeredToken {
        Task { try? await CapkaAPIClient.shared.unregisterPushToken(registeredToken) }
      }
      registeredToken = nil
      return
    }
    flush()
  }

  private func flush() {
    guard hasSession, let token, token != registeredToken else { return }
    Task {
      do {
        try await CapkaAPIClient.shared.registerPushToken(token, environment: environment)
        registeredToken = token
      } catch {
        // Retried on the next launch or session change.
      }
    }
  }
}
