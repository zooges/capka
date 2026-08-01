import LocalAuthentication
import Observation
import SwiftUI

/// Optional biometric lock over the whole app. The transcripts here are client
/// documents, so an unattended unlocked phone is a confidentiality problem, not
/// just a privacy one — but it stays opt-in because a lock the user didn't ask
/// for is the fastest way to make them stop using the app.
@MainActor
@Observable
final class AppLock {
  static let enabledKey = "capka.appLock.enabled"
  /// Re-lock after this long in the background. Short enough to matter, long
  /// enough that switching out to copy a clause doesn't cost a Face ID scan.
  private static let graceInterval: TimeInterval = 60

  /// True while the app must not show its contents.
  var isLocked = false
  var lastError: String?

  private var backgroundedAt: Date?

  var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: Self.enabledKey)
  }

  /// Whether this device can actually do it — no point offering the switch on a
  /// device with neither biometrics nor a passcode.
  static var isAvailable: Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
  }

  static var biometryLabel: String {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    switch context.biometryType {
    case .faceID: return "面容 ID"
    case .touchID: return "触控 ID"
    default: return "设备密码"
    }
  }

  func setEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    if !enabled { isLocked = false }
  }

  /// Lock on launch when the feature is on, so a cold start always authenticates.
  func lockIfEnabled() {
    if isEnabled { isLocked = true }
  }

  func noteBackgrounded() {
    guard isEnabled else { return }
    backgroundedAt = Date()
  }

  func noteForegrounded() {
    guard isEnabled else { return }
    guard let since = backgroundedAt else { return }
    if Date().timeIntervalSince(since) >= Self.graceInterval {
      isLocked = true
    }
    backgroundedAt = nil
  }

  /// Falls back to the device passcode: biometrics can fail for reasons that
  /// have nothing to do with who is holding the phone (wet hands, a mask).
  func authenticate() async {
    guard isLocked else { return }
    let context = LAContext()
    context.localizedFallbackTitle = "使用密码"
    do {
      let ok = try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: "解锁以查看你的对话与文件"
      )
      if ok {
        isLocked = false
        lastError = nil
      }
    } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
      // Staying locked IS the correct outcome of a cancel — say nothing.
      lastError = nil
    } catch {
      lastError = "无法验证身份，请重试"
    }
  }
}

/// The cover shown while locked. Deliberately blank apart from the mark: it also
/// stands in for the app switcher snapshot, so nothing readable is captured.
struct AppLockView: View {
  let lock: AppLock

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()
      VStack(spacing: 22) {
        Image("BrandMark")
          .resizable()
          .scaledToFit()
          .frame(width: 46, height: 46)
          .opacity(0.7)

        Button {
          Task { await lock.authenticate() }
        } label: {
          Text("使用\(AppLock.biometryLabel)解锁")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Brand.onPrimary)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Brand.primary)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous))
        }
        .buttonStyle(CapkaPressStyle())

        if let error = lock.lastError {
          Text(error)
            .font(.system(size: 12))
            .foregroundStyle(Brand.dangerText)
        }
      }
    }
    .task { await lock.authenticate() }
  }
}
