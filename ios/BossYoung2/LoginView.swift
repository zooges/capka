import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Sign-in / register screen — vertically centered composition matching the web
/// AuthShell: wordmark, Feishu (sign-in only), then email credentials. Register
/// adds a name field and switches the primary action to create an account.
struct LoginView: View {
  @Environment(SessionStore.self) private var session
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var mode: Mode = .signIn
  @State private var name = ""
  @State private var email = ""
  @State private var password = ""
  @State private var showPassword = false
  @State private var registrationEnabled = true
  @State private var activeMethod: Method?
  @FocusState private var focused: Field?

  private enum Mode { case signIn, register }
  private enum Field: Hashable { case name, email, password }
  private enum Method { case feishu, email }

  private let formMaxWidth: CGFloat = 340

  private var isRegister: Bool { mode == .register }

  var body: some View {
    GeometryReader { geo in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          Spacer(minLength: 24)

          VStack(spacing: 0) {
            brandBlock
              .padding(.bottom, 32)
              .capkaEntrance(.blurRise)

            if let err = session.authError {
              errorBanner(err)
                .padding(.bottom, 14)
            }

            if isRegister {
              nameField
                .padding(.bottom, 11)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            emailField
              .padding(.bottom, 11)

            passwordField
              .padding(.bottom, 18)

            emailSubmitButton
              .padding(.bottom, 20)

            if registrationEnabled || isRegister {
              modeSwitch
            }

            // Feishu is the alternative, not the headline: credentials first, then
            // the usual small third-party mark underneath.
            if !isRegister {
              authDivider
                .padding(.top, 26)
                .padding(.bottom, 16)

              feishuButton
                .capkaEntrance(.blurRise, delay: 0.05)
            }
          }
          .frame(maxWidth: formMaxWidth)
          .padding(.horizontal, 28)
          .padding(.vertical, 8)
          .capkaEntrance(.blurRise, delay: 0.1)

          Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geo.size.height)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(Motion.easeOut(0.28), value: session.authError)
    .animation(Motion.easeOut(0.22), value: mode)
    .animation(Motion.easeOut(0.2), value: focused)
    .onChange(of: session.isLoggingIn) { _, loggingIn in
      if !loggingIn { activeMethod = nil }
    }
    .task {
      registrationEnabled = await CapkaAPIClient.shared.isRegistrationEnabled()
    }
    .background { atmosphere }
  }

  // MARK: - Blocks

  private var brandBlock: some View {
    Image("BrandWordmark")
      .resizable()
      .scaledToFit()
      .frame(height: 40)
      .frame(maxWidth: 200)
      .accessibilityLabel("邦信阳律师事务所")
  }

  private var feishuButton: some View {
    VStack(spacing: 7) {
      Button(action: startFeishuLogin) {
        ZStack {
          // The official mark is a three-tone swallow on transparent, drawn for a
          // light backdrop — its navy wing disappears on a dark plate. So the
          // plate stays white in both appearances, the usual treatment for a
          // third-party mark; tinting the artwork would misrepresent it.
          Circle()
            .fill(.white)
            .frame(width: 50, height: 50)
            .overlay(Circle().stroke(Brand.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

          if activeMethod == .feishu && session.isLoggingIn {
            ProgressView().tint(Brand.muted)
          } else {
            Image("FeishuGlyph")
              .resizable()
              .scaledToFit()
              .frame(width: 26, height: 26)
          }
        }
      }
      .buttonStyle(CapkaPressStyle())
      .disabled(session.isLoggingIn)
      .accessibilityLabel("使用飞书登录")

      Text("飞书")
        .font(.system(size: 11.5))
        .foregroundStyle(Brand.muted)
    }
  }

  private var authDivider: some View {
    HStack(spacing: 14) {
      capsuleRule
      Text("其他登录方式")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.muted.opacity(0.85))
        .fixedSize()
      capsuleRule
    }
  }

  private var capsuleRule: some View {
    Rectangle()
      .fill(Brand.line.opacity(0.9))
      .frame(height: 1)
  }

  private var nameField: some View {
    authField(label: "名称", systemImage: "person", focused: focused == .name) {
      TextField("你的名字", text: $name)
        .textFieldStyle(.plain)
        .capkaTextContent(.name)
        .textInputAutocapitalization(.words)
        .focused($focused, equals: .name)
        .submitLabel(.next)
        .onSubmit { focused = .email }
        .font(.system(size: 15))
        .foregroundStyle(Brand.ink)
    }
  }

  private var emailField: some View {
    authField(label: "电子邮件", systemImage: "envelope", focused: focused == .email) {
      TextField("输入工作邮箱", text: $email)
        .textFieldStyle(.plain)
        .capkaTextContent(isRegister ? .email : .username)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focused, equals: .email)
        .submitLabel(.next)
        .onSubmit { focused = .password }
        .font(.system(size: 15))
        .foregroundStyle(Brand.ink)
    }
  }

  private var passwordField: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text("密码")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(Brand.muted)
        Spacer()
        if isRegister {
          Text("至少 8 个字符")
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted.opacity(0.75))
        }
      }
      HStack(spacing: 10) {
        Image(systemName: "lock")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(focused == .password ? Brand.ink.opacity(0.55) : Brand.muted.opacity(0.55))
          .frame(width: 18)
        Group {
          if showPassword {
            TextField(isRegister ? "设置密码" : "输入密码", text: $password)
          } else {
            SecureField(isRegister ? "设置密码" : "输入密码", text: $password)
          }
        }
        .textFieldStyle(.plain)
        .capkaTextContent(isRegister ? .newPassword : .password)
        .focused($focused, equals: .password)
        .submitLabel(.go)
        .onSubmit { Task { await submitEmail() } }
        .font(.system(size: 15))
        .foregroundStyle(Brand.ink)

        Button {
          withAnimation(reduceMotion ? nil : Motion.easeOut(0.18)) {
            showPassword.toggle()
          }
        } label: {
          Image(systemName: showPassword ? "eye.slash" : "eye")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Brand.muted.opacity(0.7))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
      }
      .padding(.horizontal, 14)
      .frame(height: 50)
      .background(fieldFill(focused == .password))
      .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous)
          .stroke(fieldStroke(focused == .password), lineWidth: focused == .password ? 1.5 : 1)
      )
    }
  }

  private func authField<Content: View>(
    label: String,
    systemImage: String,
    focused isFocused: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(label)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Brand.muted)
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(isFocused ? Brand.ink.opacity(0.55) : Brand.muted.opacity(0.55))
          .frame(width: 18)
        content()
      }
      .padding(.horizontal, 14)
      .frame(height: 50)
      .background(fieldFill(isFocused))
      .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous)
          .stroke(fieldStroke(isFocused), lineWidth: isFocused ? 1.5 : 1)
      )
    }
  }

  private var emailSubmitButton: some View {
    Button {
      Task { await submitEmail() }
    } label: {
      HStack(spacing: 8) {
        if activeMethod == .email && session.isLoggingIn {
          ProgressView().tint(Brand.onPrimary)
        }
        Text(submitLabel)
          .font(.system(size: 15, weight: .semibold))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Brand.primary)
      // `Brand.primary` is near-white in dark mode, so the label has to be its
      // paired on-colour — hardcoded white disappears entirely.
      .foregroundStyle(Brand.onPrimary)
      .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous))
      .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
    .buttonStyle(CapkaPressStyle())
    .disabled(session.isLoggingIn)
  }

  private var submitLabel: String {
    if activeMethod == .email && session.isLoggingIn {
      return isRegister ? "正在创建帐户…" : "正在登录…"
    }
    return isRegister ? "创建帐户" : "登录"
  }

  private var modeSwitch: some View {
    Button {
      withAnimation(Motion.easeOut(0.22)) {
        mode = isRegister ? .signIn : .register
        session.authError = nil
        focused = nil
      }
    } label: {
      HStack(spacing: 4) {
        Text(isRegister ? "已经有帐户？" : "没有帐户？")
          .foregroundStyle(Brand.muted)
        Text(isRegister ? "登录" : "创建一个")
          .fontWeight(.semibold)
          .foregroundStyle(Brand.ink)
      }
      .font(.system(size: 13.5))
    }
    .buttonStyle(.plain)
    .disabled(session.isLoggingIn)
  }

  private func fieldFill(_ isFocused: Bool) -> Color {
    isFocused ? Brand.card : Brand.accent.opacity(0.72)
  }

  private func fieldStroke(_ isFocused: Bool) -> Color {
    isFocused ? Brand.ink.opacity(0.22) : Color.clear
  }

  private func errorBanner(_ err: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 13))
        .padding(.top, 1)
      Text(err)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .foregroundStyle(Brand.dangerText)
    .padding(.horizontal, 13)
    .padding(.vertical, 11)
    .background(Brand.dangerSurface.opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
        .stroke(Brand.dangerBorder.opacity(0.55), lineWidth: 1)
    )
    .transition(.opacity.combined(with: .offset(y: -4)))
  }

  private var atmosphere: some View {
    ZStack {
      Brand.cream
      RadialGradient(
        colors: [Brand.burgundy.opacity(0.09), Brand.burgundy.opacity(0.02), .clear],
        center: .center,
        startRadius: 20,
        endRadius: 280
      )
      .frame(width: 520, height: 520)
      .blur(radius: reduceMotion ? 0 : 2)
      LinearGradient(
        colors: [Brand.card.opacity(0.55), .clear],
        startPoint: .top,
        endPoint: .center
      )
    }
    .ignoresSafeArea()
  }

  // MARK: - Actions

  /// The phone hands off to the Feishu app; the Mac cannot — `LarkSSOSDK`
  /// ships no macOS slice — so it runs the same web OAuth round-trip the browser
  /// client uses, in a system auth sheet. Either way the button is the button.
  private func startFeishuLogin() {
    session.authError = nil
    activeMethod = .feishu
    session.isLoggingIn = true
    #if os(iOS)
      guard let vc = topViewController() else {
        session.isLoggingIn = false
        activeMethod = nil
        session.authError = "无法启动飞书登录"
        return
      }
      FeishuNativeSSO.start(from: vc)
    #else
      FeishuWebSSO.start { ok in
        session.isLoggingIn = false
        activeMethod = nil
        guard ok else { return }
        // The round-trip set the session cookie in shared storage; picking the
        // session up is the same call every other entry point makes.
        Task { await session.bootstrap() }
      }
    #endif
  }

  private func submitEmail() async {
    focused = nil
    activeMethod = .email
    if isRegister {
      await session.signUpWithEmail(name: name, email: email, password: password)
    } else {
      await session.signInWithEmail(email: email, password: password)
    }
  }

  #if os(iOS)
    private func topViewController() -> UIViewController? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
      guard var top = window?.rootViewController else { return nil }
      while let presented = top.presentedViewController { top = presented }
      return top
    }
  #endif
}
