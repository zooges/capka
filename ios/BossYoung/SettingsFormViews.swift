import SwiftUI

/// The sheets behind the settings pages' write actions — adding a provider
/// connection, editing one, and adding an MCP connector. Each ends in a live
/// probe against the thing being configured, because a saved-but-broken
/// connection is the failure mode an admin finds out about from a user.

// MARK: - Shared chrome

/// A labelled field row, matching the login screen's field treatment.
struct FormField<Content: View>: View {
  let label: String
  var hint: String?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Brand.muted)
      content()
        .font(.system(size: 15))
        .foregroundStyle(Brand.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Brand.accent.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
      if let hint {
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// The outcome line under a 测试连接 button.
struct ProbeResultLine: View {
  let outcome: ProbeOutcome

  var body: some View {
    switch outcome {
    case .ok(let text):
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
        Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(Brand.primary.opacity(0.8))
    case .failed(let text):
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12))
        Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(Brand.dangerText)
    }
  }
}

private struct SheetChrome<Content: View>: View {
  let title: String
  let saveLabel: String
  let canSave: Bool
  let isSaving: Bool
  let onSave: () -> Void
  let onCancel: () -> Void
  @ViewBuilder let content: () -> Content

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            content()
          }
          .padding(16)
          .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Brand.cream, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消", action: onCancel).foregroundStyle(Brand.muted)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(isSaving ? "保存中…" : saveLabel, action: onSave)
            .fontWeight(.semibold)
            .foregroundStyle(canSave && !isSaving ? Brand.primary : Brand.muted)
            .disabled(!canSave || isSaving)
        }
      }
    }
  }
}

// MARK: - Add a provider connection

struct AddProviderSheet: View {
  let model: SettingsViewModel
  let onDone: () -> Void

  @State private var provider = "openai"
  @State private var label = ""
  @State private var apiKey = ""
  @State private var baseUrl = ""
  @State private var defaultModel = ""
  @State private var shared = true
  /// Only meaningful for the `openai` provider; the server nulls it elsewhere.
  @State private var apiStyle = "responses"
  @State private var probe: ProbeOutcome?
  @State private var isProbing = false

  private var meta: ProviderOption { ProviderOption.of(provider) ?? ProviderOption.all[0] }

  private var canSave: Bool {
    if meta.requiresKey && apiKey.trimmingCharacters(in: .whitespaces).isEmpty { return false }
    if meta.requiresBaseUrl && baseUrl.trimmingCharacters(in: .whitespaces).isEmpty { return false }
    return true
  }

  var body: some View {
    SheetChrome(
      title: "添加连接",
      saveLabel: "保存",
      canSave: canSave,
      isSaving: model.isSaving,
      onSave: { Task { if await save() { onDone() } } },
      onCancel: onDone
    ) {
      FormField(label: "提供商") {
        Menu {
          ForEach(ProviderOption.all) { option in
            Button(option.label) {
              provider = option.id
              baseUrl = option.defaultBaseUrl ?? ""
              probe = nil
            }
          }
        } label: {
          HStack {
            Text(meta.label)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
          }
          .foregroundStyle(Brand.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      FormField(label: "名称", hint: "留空则显示提供商名称") {
        TextField("例如：公司 Anthropic 账号", text: $label)
          .textInputAutocapitalization(.never)
      }

      if meta.requiresKey {
        FormField(label: "API 密钥", hint: "保存后由服务端用实例主密钥加密，App 不留存") {
          SecureField("粘贴密钥", text: $apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }

      if meta.showsBaseUrl {
        FormField(
          label: meta.requiresBaseUrl ? "接口地址" : "接口地址（可选）",
          hint: meta.requiresBaseUrl ? nil : "留空则使用该提供商的默认端点"
        ) {
          TextField("https://…", text: $baseUrl)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        }
      }

      if provider == "openai" {
        FormField(label: "接口协议") {
          Picker("", selection: $apiStyle) {
            Text("Responses").tag("responses")
            Text("Chat Completions").tag("chat")
          }
          .pickerStyle(.segmented)
          .padding(.vertical, 4)
        }
      }

      FormField(label: "默认模型", hint: "测试连接时也用它；可留空") {
        TextField("例如：claude-sonnet-4-6", text: $defaultModel)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }

      Toggle(isOn: $shared) {
        VStack(alignment: .leading, spacing: 2) {
          Text("共享给全体成员").font(.system(size: 14)).foregroundStyle(Brand.ink)
          Text("关闭则只有你自己能用这个连接。")
            .font(.system(size: 11)).foregroundStyle(Brand.muted)
        }
      }
      .tint(Brand.primary)

      probeRow

      if let probe {
        ProbeResultLine(outcome: probe)
      }
    }
  }

  private var probeRow: some View {
    HStack(spacing: 10) {
      Button {
        Task { await runProbe() }
      } label: {
        HStack(spacing: 6) {
          if isProbing { ProgressView().controlSize(.small).tint(Brand.ink) }
          Text(isProbing ? "测试中…" : "测试连接")
            .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Brand.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Brand.accent)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
      }
      .buttonStyle(CapkaPressStyle())
      .disabled(isProbing || defaultModel.trimmingCharacters(in: .whitespaces).isEmpty)

      if defaultModel.trimmingCharacters(in: .whitespaces).isEmpty {
        Text("填写默认模型后可测试")
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }
      Spacer(minLength: 0)
    }
  }

  private func runProbe() async {
    isProbing = true
    defer { isProbing = false }
    probe = await model.testProvider(
      provider: provider,
      apiKey: apiKey,
      modelId: defaultModel.trimmingCharacters(in: .whitespaces),
      baseUrl: baseUrl,
      apiStyle: provider == "openai" ? apiStyle : nil
    )
  }

  private func save() async -> Bool {
    await model.createProvider(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      defaultModel: defaultModel.trimmingCharacters(in: .whitespaces),
      label: label.trimmingCharacters(in: .whitespaces),
      shared: shared,
      apiStyle: provider == "openai" ? apiStyle : nil
    )
  }
}

// MARK: - Edit an existing connection

/// The key itself is never editable — it is write-only on the server. To change
/// a key you delete the connection and add it again, same as the web.
struct EditProviderSheet: View {
  let model: SettingsViewModel
  let provider: ProviderConfig
  let onDone: () -> Void

  @State private var label: String
  @State private var defaultModel: String
  @State private var shared: Bool
  @State private var apiStyle: String

  init(model: SettingsViewModel, provider: ProviderConfig, onDone: @escaping () -> Void) {
    self.model = model
    self.provider = provider
    self.onDone = onDone
    _label = State(initialValue: provider.label ?? "")
    _defaultModel = State(initialValue: provider.defaultModel ?? "")
    _shared = State(initialValue: provider.shared)
    _apiStyle = State(initialValue: provider.apiStyle ?? "responses")
  }

  var body: some View {
    SheetChrome(
      title: provider.displayName,
      saveLabel: "保存",
      canSave: true,
      isSaving: model.isSaving,
      onSave: {
        Task {
          let ok = await model.updateProvider(
            provider,
            defaultModel: defaultModel.trimmingCharacters(in: .whitespaces),
            label: label.trimmingCharacters(in: .whitespaces),
            shared: shared,
            apiStyle: provider.provider == "openai" ? apiStyle : nil
          )
          if ok { onDone() }
        }
      },
      onCancel: onDone
    ) {
      FormField(label: "名称") {
        TextField("显示名称", text: $label).textInputAutocapitalization(.never)
      }

      FormField(label: "默认模型") {
        TextField("例如：claude-sonnet-4-6", text: $defaultModel)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }

      if provider.provider == "openai" {
        FormField(label: "接口协议") {
          Picker("", selection: $apiStyle) {
            Text("Responses").tag("responses")
            Text("Chat Completions").tag("chat")
          }
          .pickerStyle(.segmented)
          .padding(.vertical, 4)
        }
      }

      Toggle(isOn: $shared) {
        VStack(alignment: .leading, spacing: 2) {
          Text("共享给全体成员").font(.system(size: 14)).foregroundStyle(Brand.ink)
          Text("关闭则只有你自己能用这个连接。")
            .font(.system(size: 11)).foregroundStyle(Brand.muted)
        }
      }
      .tint(Brand.primary)

      Text("API 密钥保存后不可读取。要更换密钥，请删除此连接后重新添加。")
        .font(.system(size: 11))
        .foregroundStyle(Brand.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Add an MCP connector

struct AddConnectorSheet: View {
  let model: SettingsViewModel
  let onDone: () -> Void

  @State private var name = ""
  @State private var url = ""
  @State private var authKind = "none"
  @State private var token = ""
  @State private var oauthClientId = ""
  @State private var oauthClientSecret = ""
  @State private var transport = "auto"
  @State private var probe: ProbeOutcome?
  @State private var isProbing = false

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && url.trimmingCharacters(in: .whitespaces).hasPrefix("http")
  }

  private var wireTransport: String? { transport == "auto" ? nil : transport }

  var body: some View {
    SheetChrome(
      title: "添加连接器",
      saveLabel: "保存",
      canSave: canSave,
      isSaving: model.isSaving,
      onSave: {
        Task {
          let ok = await model.createConnector(
            name: name.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            authKind: authKind,
            token: token,
            oauthClientId: oauthClientId,
            oauthClientSecret: oauthClientSecret,
            transport: wireTransport
          )
          if ok { onDone() }
        }
      },
      onCancel: onDone
    ) {
      FormField(label: "名称") {
        TextField("例如：企查查", text: $name).textInputAutocapitalization(.never)
      }

      FormField(label: "服务地址") {
        TextField("https://…/mcp", text: $url)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
      }

      FormField(label: "传输方式", hint: "自动即由服务端协商，通常无需更改") {
        Picker("", selection: $transport) {
          Text("自动").tag("auto")
          Text("HTTP").tag("http")
          Text("SSE").tag("sse")
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
      }

      FormField(label: "鉴权方式") {
        Picker("", selection: $authKind) {
          Text("无").tag("none")
          Text("令牌").tag("token")
          Text("OAuth").tag("oauth")
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
      }

      if authKind == "token" {
        FormField(label: "访问令牌", hint: "以 Authorization: Bearer 发送，服务端加密存储") {
          SecureField("粘贴令牌", text: $token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }

      if authKind == "oauth" {
        FormField(label: "OAuth Client ID") {
          TextField("client id", text: $oauthClientId)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        FormField(label: "OAuth Client Secret") {
          SecureField("client secret", text: $oauthClientSecret)
            .textInputAutocapitalization(.never)
        }
        Text("OAuth 授权本身需要在网页端完成一次跳转。")
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }

      HStack(spacing: 10) {
        Button {
          Task {
            isProbing = true
            defer { isProbing = false }
            probe = await model.testConnector(
              url: url.trimmingCharacters(in: .whitespaces),
              token: token,
              transport: wireTransport
            )
          }
        } label: {
          HStack(spacing: 6) {
            if isProbing { ProgressView().controlSize(.small).tint(Brand.ink) }
            Text(isProbing ? "测试中…" : "测试连接")
              .font(.system(size: 13, weight: .medium))
          }
          .foregroundStyle(Brand.ink)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Brand.accent)
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
        }
        .buttonStyle(CapkaPressStyle())
        .disabled(isProbing || !url.trimmingCharacters(in: .whitespaces).hasPrefix("http"))
        Spacer(minLength: 0)
      }

      if let probe {
        ProbeResultLine(outcome: probe)
      }
    }
  }
}

// MARK: - Update a connector's token

struct ConnectorTokenSheet: View {
  let model: SettingsViewModel
  let connector: ConnectorInfo
  let onDone: () -> Void

  @State private var token = ""

  var body: some View {
    SheetChrome(
      title: connector.name,
      saveLabel: "更新",
      canSave: !token.isEmpty,
      isSaving: model.isSaving,
      onSave: {
        Task {
          if await model.updateConnectorToken(connector, token: token) { onDone() }
        }
      },
      onCancel: onDone
    ) {
      FormField(label: "访问令牌", hint: "替换现有令牌；旧令牌无法读取。") {
        SecureField("粘贴新令牌", text: $token)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
    }
  }
}
