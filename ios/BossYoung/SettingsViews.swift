import SwiftUI
import UIKit

/// Settings landing screen. The web packs its nav into a horizontal tab strip on
/// phones; here the rest of the app is already list-and-push (projects, archived
/// chats, workspace files), so settings follows that instead — grouped rows that
/// push a detail page, which is also what an iOS reader expects.
struct SettingsHomeView: View {
  @Environment(SessionStore.self) private var session
  @State private var model = SettingsViewModel()
  /// Debug-only jump straight to a detail page (`CAPKA_UI_FIXTURES_SETTINGS_TAB`).
  @State private var deepLinkTab: SettingsViewModel.Tab?

  private var personalTabs: [SettingsViewModel.Tab] {
    model.visibleTabs.filter { !$0.isAdminOnly }
  }

  private var adminTabs: [SettingsViewModel.Tab] {
    model.visibleTabs.filter(\.isAdminOnly)
  }

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          accountHeader

          group(title: "个人", tabs: personalTabs)
          if !adminTabs.isEmpty {
            group(title: "管理", tabs: adminTabs)
          }

          Button(role: .destructive) {
            Task { await session.signOut() }
          } label: {
            Text("退出登录")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(Brand.dangerText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .capkaCard(radius: Brand.Radius.lg)
          }
        }
        .padding(16)
        .padding(.bottom, 28)
      }
    }
    .navigationTitle("设置")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Brand.cream, for: .navigationBar)
    .navigationDestination(item: $deepLinkTab) { tab in
      SettingsDetailView(tab: tab, model: model)
    }
    .task {
      await model.load(user: session.user)
      #if DEBUG
      if let raw = ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES_SETTINGS_TAB"] {
        deepLinkTab = SettingsViewModel.Tab(rawValue: raw)
      }
      #endif
    }
    .alert("出错了", isPresented: Binding(
      get: { model.error != nil },
      set: { if !$0 { model.error = nil } }
    )) {
      Button("好", role: .cancel) { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }

  private var accountHeader: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(Brand.accent)
        Text(String(model.displayName.prefix(1)))
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(Brand.ink.opacity(0.7))
      }
      .frame(width: 46, height: 46)

      VStack(alignment: .leading, spacing: 3) {
        Text(model.displayName.isEmpty ? "—" : model.displayName)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Brand.ink)
        Text(model.email.isEmpty ? "已登录" : model.email)
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if model.isAdmin {
        Text("管理员")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Brand.muted)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Brand.accent)
          .clipShape(Capsule())
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .capkaCard()
  }

  private func group(title: String, tabs: [SettingsViewModel.Tab]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13))
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)

      VStack(spacing: 0) {
        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
          NavigationLink {
            SettingsDetailView(tab: tab, model: model)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: tab.icon)
                .font(.system(size: 14))
                .foregroundStyle(Brand.muted)
                .frame(width: 20)
              Text(tab.title)
                .font(.system(size: 15))
                .foregroundStyle(Brand.ink)
              Spacer(minLength: 8)
              Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.muted.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
          }
          .buttonStyle(CapkaPressStyle())

          if index < tabs.count - 1 {
            Divider().overlay(Brand.line).padding(.leading, 46)
          }
        }
      }
      .capkaCard()
    }
  }
}

// MARK: - Detail pages

private struct SettingsDetailView: View {
  let tab: SettingsViewModel.Tab
  let model: SettingsViewModel

  @Environment(SessionStore.self) private var session
  @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue
  @Environment(AppLock.self) private var appLock
  @State private var lockEnabled = UserDefaults.standard.bool(forKey: AppLock.enabledKey)

  @State private var showAddProvider = false
  @State private var editProvider: ProviderConfig?
  @State private var showAddConnector = false
  @State private var tokenConnector: ConnectorInfo?
  @State private var showSkillImporter = false
  @State private var confirmDeleteUser: AdminUserRow?
  @State private var telegramBotToken = ""
  @State private var githubToken = ""
  @State private var showAddMarketplace = false
  @State private var marketplaceURL = ""

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      ScrollView {
        Group {
          switch tab {
          case .general: generalSection
          case .connections: connectionsSection
          case .memory: memorySection
          case .skills: extensionsSection
          case .automations: automationsSection
          case .security: securitySection
          case .integrations: integrationsSection
          case .authentication: authenticationSection
          case .permissions: permissionsSection
          case .billingAdmin: billingAdminSection
          case .usage: usageSection
          case .users: usersSection
          case .activity: activitySection
          case .updates: updatesSection
          }
        }
        .padding(16)
        .padding(.bottom, 28)
      }
    }
    .navigationTitle(tab.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Brand.cream, for: .navigationBar)
    .sheet(isPresented: $showAddProvider) {
      AddProviderSheet(model: model) { showAddProvider = false }
    }
    .sheet(item: $editProvider) { p in
      EditProviderSheet(model: model, provider: p) { editProvider = nil }
    }
    .sheet(isPresented: $showAddConnector) {
      AddConnectorSheet(model: model) { showAddConnector = false }
    }
    .sheet(item: $tokenConnector) { c in
      ConnectorTokenSheet(model: model, connector: c) { tokenConnector = nil }
    }
    .fileImporter(
      isPresented: $showSkillImporter,
      allowedContentTypes: [.zip],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await model.uploadSkill(fileURL: url) }
    }
    .alert("添加市场源", isPresented: $showAddMarketplace) {
      TextField("https://github.com/owner/repo", text: $marketplaceURL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("添加") {
        let url = marketplaceURL
        marketplaceURL = ""
        Task { await model.addMarketplace(url: url) }
      }
      Button("取消", role: .cancel) { marketplaceURL = "" }
    } message: {
      Text("填写打包了扩展的 git 仓库地址。")
    }
    .alert("删除用户", isPresented: Binding(
      get: { confirmDeleteUser != nil },
      set: { if !$0 { confirmDeleteUser = nil } }
    )) {
      Button("删除", role: .destructive) {
        if let user = confirmDeleteUser {
          Task { await model.deleteUser(user) }
        }
        confirmDeleteUser = nil
      }
      Button("取消", role: .cancel) { confirmDeleteUser = nil }
    } message: {
      Text("将永久删除「\(confirmDeleteUser?.name ?? "")」及其聊天记录，此操作无法撤销。")
    }
  }

  /// Right-aligned action row under a section's heading.
  private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Brand.primary)
    }
    .buttonStyle(CapkaPressStyle())
  }

  // MARK: - General

  private var generalSection: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "账户", subtitle: "您的个人资料详细信息") {
        VStack(alignment: .leading, spacing: 10) {
          Text("名称")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Brand.muted)
          TextField("你的名字", text: $model.displayName)
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Brand.accent.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))

          HStack {
            Text("电子邮件")
              .font(.system(size: 14))
              .foregroundStyle(Brand.muted)
            Spacer()
            Text(model.email.isEmpty ? "—" : model.email)
              .font(.system(size: 14))
              .foregroundStyle(Brand.ink)
              .lineLimit(1)
          }
          .padding(.top, 4)

          primaryButton(model.isSaving ? "保存中…" : "保存") {
            Task { await model.saveName() }
          }
          .disabled(model.isSaving)
        }
      }

      // The account menu in the sidebar carries the same control; keeping it here
      // too matches the web, where appearance lives on Settings → General.
      sectionCard(title: "外观", subtitle: "浅色、深色或跟随系统") {
        HStack(spacing: 8) {
          ForEach(ThemePreference.allCases) { pref in
            pill(label: pref.label, icon: pref.icon, selected: themeRaw == pref.rawValue) {
              themeRaw = pref.rawValue
            }
          }
          Spacer(minLength: 0)
        }
      }

      if AppLock.isAvailable {
        sectionCard(title: "应用锁", subtitle: "离开一分钟以上后，回到 App 需要验证身份") {
          switchRow(
            title: "使用\(AppLock.biometryLabel)解锁",
            hint: "对话与文件属于客户资料；开启后未验证前不显示内容。",
            isOn: lockEnabled
          ) { on in
            appLock.setEnabled(on)
            lockEnabled = on
          }
        }
      }

      sectionCard(title: "语言", subtitle: "界面显示语言") {
        HStack(spacing: 8) {
          ForEach([("zh-CN", "简体中文"), ("en", "English"), ("uk", "Українська")], id: \.0) { code, label in
            pill(label: label, icon: nil, selected: model.locale == code) {
              Task { await model.setLocale(code) }
            }
          }
          Spacer(minLength: 0)
        }
      }

      if let billing = model.billing, billing.onSharedKey, !billing.windows.isEmpty {
        sectionCard(title: "使用限额", subtitle: billing.tierName ?? "共享密钥额度") {
          VStack(spacing: 12) {
            ForEach(billing.windows) { w in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(windowLabel(w.window))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.ink)
                  Spacer()
                  Text("\(Int(min(100, w.pct.rounded())))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(w.pct >= 90 ? Brand.dangerText : Brand.muted)
                }
                GeometryReader { geo in
                  ZStack(alignment: .leading) {
                    Capsule().fill(Brand.accent)
                    Capsule()
                      .fill(w.pct >= 90 ? Brand.dangerText : Brand.primary.opacity(0.7))
                      .frame(width: geo.size.width * min(1, CGFloat(w.pct / 100)))
                  }
                }
                .frame(height: 6)
              }
            }
            if billing.blocked {
              Text("当前已达到限额，请稍后再试或联系管理员。")
                .font(.system(size: 12))
                .foregroundStyle(Brand.dangerText)
            }
          }
        }
      }

      sectionCard(title: "Telegram", subtitle: "把邦信阳接到 Telegram，随时收发任务") {
        telegramCard
      }

      savedBannerLine
    }
  }

  private var telegramCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      if model.telegram?.linked == true {
        HStack {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Brand.primary.opacity(0.7))
          Text("已连接\(model.telegram?.username.map { " · @\($0)" } ?? "")")
            .font(.system(size: 14))
            .foregroundStyle(Brand.ink)
          Spacer()
          Button("解除连接") {
            Task { await model.unlinkTelegram() }
          }
          .font(.system(size: 13))
          .foregroundStyle(Brand.dangerText)
        }
      } else {
        Text("生成一次性代码，在 Telegram 机器人中发送 `/link 代码`。")
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)

        if let code = model.telegramCode {
          HStack {
            Text("/link \(code)")
              .font(.system(size: 14, design: .monospaced))
              .foregroundStyle(Brand.ink)
            Spacer()
            Button("复制") {
              UIPasteboard.general.string = "/link \(code)"
            }
            .font(.system(size: 13, weight: .medium))
          }
          .padding(12)
          .background(Brand.accent.opacity(0.7))
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
        }

        HStack(spacing: 10) {
          primaryButton("生成连接代码") {
            Task { await model.generateTelegramCode() }
          }
          Button("刷新状态") {
            Task { await model.refreshTelegram() }
          }
          .font(.system(size: 13))
          .foregroundStyle(Brand.muted)
        }
      }
    }
  }

  // MARK: - Connections (providers)

  private var connectionsSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "模型连接", subtitle: "提供商密钥与默认模型。点一行可修改。") {
        VStack(spacing: 0) {
          if model.isLoading && model.providers.isEmpty {
            ProgressView().tint(Brand.primary).frame(maxWidth: .infinity).padding(.vertical, 12)
          } else if model.providers.isEmpty {
            emptyLine("尚未配置提供商")
          } else {
            ForEach(Array(model.providers.enumerated()), id: \.element.id) { index, p in
              providerRow(p)
              if index < model.providers.count - 1 { Divider().overlay(Brand.line) }
            }
          }

          Divider().overlay(Brand.line)

          HStack(spacing: 16) {
            actionButton("添加连接", systemImage: "plus") { showAddProvider = true }
            if model.isAdmin {
              actionButton("重新同步模型", systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.resyncModels() }
              }
            }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 12)
        }
      }

      savedBannerLine
    }
  }

  private func providerRow(_ p: ProviderConfig) -> some View {
    HStack(spacing: 10) {
      Button {
        editProvider = p
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(p.displayName)
              .font(.system(size: 14))
              .foregroundStyle(Brand.ink)
            if p.shared {
              Text("共享")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Brand.accent)
                .clipShape(Capsule())
            }
          }
          Text(p.defaultModel?.isEmpty == false ? p.defaultModel! : "未设默认模型")
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(CapkaPressStyle())

      Toggle("", isOn: Binding(
        get: { p.isActive },
        set: { _ in Task { await model.toggleProvider(p) } }
      ))
      .labelsHidden()
      .tint(Brand.primary)
    }
    .padding(.vertical, 9)
    .contextMenu {
      Button { editProvider = p } label: { Label("修改", systemImage: "pencil") }
      Button(role: .destructive) {
        Task { await model.deleteProvider(p) }
      } label: {
        Label("删除", systemImage: "trash")
      }
    }
  }

  // MARK: - Extensions

  private var extensionsSection: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 6) {
        ForEach(SettingsViewModel.ExtTab.allCases) { extTab in
          pill(label: extTab.rawValue, icon: nil, selected: model.extTab == extTab) {
            withAnimation(Motion.easeOut(0.18)) { model.extTab = extTab }
          }
        }
        Spacer(minLength: 0)
      }

      switch model.extTab {
      case .skills:
        sectionCard(title: "技能库", subtitle: "助手可以调用的扩展能力") {
          toggleList(
            empty: "暂无技能",
            loading: model.isLoading && model.skills.isEmpty,
            count: model.skills.count
          ) {
            ForEach(Array(model.skills.enumerated()), id: \.element.id) { index, skill in
              Toggle(isOn: Binding(
                get: { skill.enabled },
                set: { _ in Task { await model.toggleSkill(skill) } }
              )) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(skill.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
                  if let d = skill.description, !d.isEmpty {
                    Text(d).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(2)
                  }
                }
              }
              .tint(Brand.primary)
              .padding(.vertical, 9)
              .contextMenu {
                if skill.mine == true {
                  Button(role: .destructive) {
                    Task { await model.deleteSkill(skill) }
                  } label: {
                    Label("删除", systemImage: "trash")
                  }
                }
              }
              if index < model.skills.count - 1 { Divider().overlay(Brand.line) }
            }
          }
          Divider().overlay(Brand.line)
          HStack {
            actionButton("导入技能（.zip）", systemImage: "plus") { showSkillImporter = true }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 12)
        }
      case .connectors:
        sectionCard(title: "连接器", subtitle: "已配置的外部服务（MCP）") {
          toggleList(
            empty: "暂无连接器",
            loading: model.isLoading && model.connectors.isEmpty,
            count: model.connectors.count
          ) {
            ForEach(Array(model.connectors.enumerated()), id: \.element.id) { index, c in
              Toggle(isOn: Binding(
                get: { c.enabled },
                set: { _ in Task { await model.toggleConnector(c) } }
              )) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(c.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
                  if let url = c.url, !url.isEmpty {
                    Text(url).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(1)
                  }
                }
              }
              .tint(Brand.primary)
              .padding(.vertical, 9)
              .contextMenu {
                Button { tokenConnector = c } label: { Label("更新令牌", systemImage: "key") }
                Button(role: .destructive) {
                  Task { await model.deleteConnector(c) }
                } label: {
                  Label("删除", systemImage: "trash")
                }
              }
              if index < model.connectors.count - 1 { Divider().overlay(Brand.line) }
            }
          }
          Divider().overlay(Brand.line)
          HStack {
            actionButton("添加连接器", systemImage: "plus") { showAddConnector = true }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 12)
        }
      case .marketplace:
        marketplaceSection
      case .plugins:
        sectionCard(title: "插件", subtitle: "已安装的扩展包") {
          if model.plugins.isEmpty {
            emptyLine("暂无已安装插件")
          } else {
            VStack(spacing: 0) {
              ForEach(Array(model.plugins.enumerated()), id: \.element.id) { index, p in
                Toggle(isOn: Binding(
                  get: { p.enabled },
                  set: { _ in Task { await model.togglePlugin(p) } }
                )) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
                    if let d = p.description, !d.isEmpty {
                      Text(d).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(2)
                    }
                  }
                }
                .tint(Brand.primary)
                .padding(.vertical, 10)
                .contextMenu {
                  Button(role: .destructive) {
                    Task { await model.uninstallPlugin(p) }
                  } label: {
                    Label("卸载", systemImage: "trash")
                  }
                }
                if index < model.plugins.count - 1 { Divider().overlay(Brand.line) }
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Memory

  private var memorySection: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 18) {
      if !model.memoryProjects.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            pill(label: "个人", icon: nil, selected: model.selectedMemoryProjectId == nil) {
              model.selectedMemoryProjectId = nil
            }
            ForEach(model.memoryProjects) { doc in
              pill(label: doc.name, icon: nil, selected: model.selectedMemoryProjectId == doc.id) {
                model.selectedMemoryProjectId = doc.id
              }
            }
          }
        }
      }

      sectionCard(
        title: model.selectedMemoryProjectId == nil ? "个人记忆" : "项目记忆",
        subtitle: "助手会长期记住的信息"
      ) {
        VStack(alignment: .leading, spacing: 10) {
          TextField(
            "写入希望助手长期记住的信息",
            text: Binding(
              get: { model.memoryDraft },
              set: { model.memoryDraft = $0 }
            ),
            axis: .vertical
          )
            .font(.system(size: 14))
            .lineLimit(6...16)
          primaryButton(model.isSaving ? "保存中…" : "保存") {
            Task { await model.saveMemory() }
          }
          savedBannerLine
        }
      }
    }
  }

  // MARK: - Automations

  private var automationsSection: some View {
    sectionCard(title: "自动化", subtitle: "按计划自动运行，无需打开聊天。") {
      if model.automations.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("还没有自动化")
            .font(.system(size: 13))
            .foregroundStyle(Brand.ink)
          Text("可在聊天中让助手帮你创建，例如：「每周一上午 9 点，准备每周总结。」")
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.automations.enumerated()), id: \.element.id) { index, item in
            Toggle(isOn: Binding(
              get: { item.enabled },
              set: { _ in Task { await model.toggleAutomation(item) } }
            )) {
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.system(size: 14))
                  .foregroundStyle(Brand.ink)
                  .lineLimit(2)
                Text(item.nextRunLabel ?? item.statusLabel)
                  .font(.system(size: 11))
                  .foregroundStyle(Brand.muted)
              }
            }
            .tint(Brand.primary)
            .padding(.vertical, 9)
            .contextMenu {
              Button(role: .destructive) {
                Task { await model.deleteAutomation(item) }
              } label: {
                Label("删除", systemImage: "trash")
              }
            }
            if index < model.automations.count - 1 {
              Divider().overlay(Brand.line)
            }
          }
        }
      }
    }
  }

  // MARK: - Security

  /// The deployment-level egress kill switch. When the controller reports no
  /// network, the in-app switch cannot grant it — it would downgrade bridge→none
  /// anyway — so it is shown off and disabled with the reason spelled out.
  private var networkBlockedAtHost: Bool {
    model.sandbox?.allowNetwork == false
  }

  private var securitySection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "沙箱", subtitle: "助手运行代码和处理文件的隔离环境") {
        VStack(spacing: 0) {
          switchRow(
            title: "允许出站网络",
            hint: "关闭后沙箱无法访问互联网，只能处理已上传的文件。",
            isOn: model.sandboxNetworkSetting == "bridge",
            disabled: networkBlockedAtHost
          ) { on in
            Task { await model.setSandboxNetwork(on) }
          }
          if networkBlockedAtHost {
            Text("该部署已在主机层禁止沙箱出站，此开关不会生效。")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Brand.warningText)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.bottom, 10)
          }

          Divider().overlay(Brand.line)

          switchRow(
            title: "服务器文件夹",
            hint: "允许把服务器上的文件夹挂载进沙箱。",
            isOn: model.hostFolderAccess
          ) { on in
            Task { await model.setHostFolderAccess(on) }
          }

          Divider().overlay(Brand.line)

          VStack(alignment: .leading, spacing: 8) {
            Text("个人电脑文件夹")
              .font(.system(size: 14))
              .foregroundStyle(Brand.ink)
            Text("谁可以把自己电脑上的文件夹同步进沙箱。")
              .font(.system(size: 11))
              .foregroundStyle(Brand.muted)
            HStack(spacing: 8) {
              ForEach([("off", "关闭"), ("admins", "仅管理员"), ("everyone", "所有人")], id: \.0) { value, label in
                pill(label: label, icon: nil, selected: model.pcFolderAccess == value) {
                  Task { await model.setPCFolderAccess(value) }
                }
              }
              Spacer(minLength: 0)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 11)
        }
      }

      sectionCard(title: "代理", subtitle: "助手在不询问的情况下可以改动多少") {
        switchRow(
          title: "自主模式",
          hint: "开启后助手会自行完成多步任务，不再逐步征求确认。",
          isOn: model.agentAutonomy == "autonomous"
        ) { on in
          Task { await model.setAutonomous(on) }
        }
      }

      agentCeilingCard

      sectionCard(title: "网络", subtitle: "限制对外的模型提供商连接") {
        switchRow(
          title: "阻止私有地址",
          hint: "禁止提供商地址指向内网或本机，防止服务端请求伪造。",
          isOn: model.blockPrivateProviderURLs
        ) { on in
          Task { await model.setBlockPrivateProviderURLs(on) }
        }
      }

      masterKeyCard

      savedBannerLine
    }
  }

  /// Where the key that encrypts stored provider secrets comes from. A key held
  /// in the database is a convenience for first boot, not a resting place — the
  /// point of this card is to get it into the environment and then forget it.
  @ViewBuilder
  private var masterKeyCard: some View {
    sectionCard(title: "加密密钥", subtitle: "用于加密已保存的提供商密钥与令牌") {
      if let key = model.masterKey {
        kvRow("来源", masterKeySourceLabel(key.source))
        kvRow("数据库副本", key.dbKeyPresent ? "存在" : "无")
        if let secret = key.key, !secret.isEmpty {
          Text("请把下面这串写入部署环境的 CAPKA_MASTER_KEY，然后删除数据库副本：")
            .font(.system(size: 11))
            .foregroundStyle(Brand.warningText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
          HStack {
            Text(secret)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(Brand.ink)
              .lineLimit(2)
              .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("复制") { UIPasteboard.general.string = secret }
              .font(.system(size: 12, weight: .medium))
          }
          .padding(10)
          .background(Brand.warningSurface)
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
        }
        if key.dbKeyPresent {
          Button(role: .destructive) {
            Task { await model.clearDatabaseMasterKey() }
          } label: {
            Text("删除数据库中的副本")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Brand.dangerText)
          }
          .padding(.top, 6)
        }
      } else {
        emptyLine("无法读取密钥状态")
      }
    }
  }

  private func masterKeySourceLabel(_ source: String?) -> String {
    switch source {
    case "env": return "环境变量（推荐）"
    case "db": return "数据库"
    case "missing": return "未设置"
    case .some(let s): return s
    case nil: return "—"
    }
  }

  private func limitField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Brand.muted)
      TextField("不限", text: text)
        .keyboardType(.decimalPad)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Brand.accent.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
    }
  }

  // MARK: - Marketplace

  private var marketplaceSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "市场源", subtitle: "可安装扩展的 git 仓库") {
        VStack(spacing: 0) {
          if model.marketplaces.isEmpty {
            emptyLine("还没有市场源")
          } else {
            ForEach(Array(model.marketplaces.enumerated()), id: \.element.id) { index, market in
              Button {
                Task { await model.openMarketplace(market) }
              } label: {
                HStack(spacing: 10) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(market.displayName)
                      .font(.system(size: 14))
                      .foregroundStyle(Brand.ink)
                      .lineLimit(1)
                    Text("\(market.pluginCount) 个扩展")
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                  Spacer(minLength: 8)
                  if model.openMarketplaceId == market.id {
                    Image(systemName: "checkmark")
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundStyle(Brand.primary)
                  }
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
              }
              .buttonStyle(CapkaPressStyle())
              .contextMenu {
                Button { Task { await model.refreshMarketplace(market) } } label: {
                  Label("刷新目录", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                  Task { await model.removeMarketplace(market) }
                } label: {
                  Label("移除市场源", systemImage: "trash")
                }
              }
              if index < model.marketplaces.count - 1 { Divider().overlay(Brand.line) }
            }
          }
          Divider().overlay(Brand.line)
          HStack {
            actionButton("添加市场源", systemImage: "plus") { showAddMarketplace = true }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 12)
        }
      }

      if model.openMarketplaceId != nil {
        sectionCard(title: "可安装的扩展", subtitle: "安装后会出现在插件列表里") {
          if model.isLoading && model.catalog.isEmpty {
            ProgressView().tint(Brand.primary).frame(maxWidth: .infinity).padding(.vertical, 12)
          } else if model.catalog.isEmpty {
            emptyLine("这个源里没有扩展")
          } else {
            VStack(spacing: 0) {
              ForEach(Array(model.catalog.enumerated()), id: \.element.id) { index, item in
                catalogRow(item)
                if index < model.catalog.count - 1 { Divider().overlay(Brand.line) }
              }
            }
          }
        }
      }

      sectionCard(title: "GitHub Token", subtitle: "访问私有仓库或提高速率限制时才需要") {
        VStack(alignment: .leading, spacing: 10) {
          kvRow("状态", model.githubTokenConfigured ? "已配置" : "未配置")
          SecureField("粘贴 token", text: $githubToken)
            .font(.system(size: 15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Brand.accent.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
          HStack(spacing: 12) {
            primaryButton(model.isSaving ? "保存中…" : "保存") {
              let token = githubToken
              githubToken = ""
              Task { await model.saveGithubToken(token) }
            }
            .disabled(githubToken.isEmpty || model.isSaving)
            if model.githubTokenConfigured {
              Button("清除") { Task { await model.clearGithubToken() } }
                .font(.system(size: 13))
                .foregroundStyle(Brand.dangerText)
            }
          }
        }
      }

      savedBannerLine
    }
  }

  private func catalogRow(_ item: CatalogItem) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
        if let d = item.description, !d.isEmpty {
          Text(d).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(2)
        }
        if let author = item.author, !author.isEmpty {
          Text(author).font(.system(size: 10)).foregroundStyle(Brand.muted.opacity(0.8))
        }
      }
      Spacer(minLength: 8)
      if item.installed {
        Button("卸载") { Task { await model.uninstallFromMarketplace(item) } }
          .font(.system(size: 12))
          .foregroundStyle(Brand.dangerText)
      } else if item.installable {
        Button("安装") { Task { await model.installFromMarketplace(item) } }
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Brand.link)
          .disabled(model.isSaving)
      } else {
        Text("不可安装")
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }
    }
    .padding(.vertical, 10)
  }

  /// The instance-wide agent ceiling. It only ever restricts: a project asking
  /// for more still gets clamped here, which is why it also reaches chats that
  /// belong to no project.
  @ViewBuilder
  private var agentCeilingCard: some View {
    sectionCard(title: "能力上限", subtitle: "整个实例的能力天花板，项目只能更严，不能更宽") {
      if let profile = model.agentProfile {
        VStack(spacing: 0) {
          let capabilities: [(String, String, KeyPath<AgentProfile, Bool>, (inout AgentProfile, Bool) -> Void)] = [
            ("文件与代码", "沙箱容器、文件工具与工作区快照。", \.sandbox, { $0.sandbox = $1 }),
            ("连接器", "MCP 连接器与提供商自带的检索工具。", \.connectors, { $0.connectors = $1 }),
            ("技能", "技能库与技能调用工具。", \.skills, { $0.skills = $1 }),
            ("管理与提问", "控制面板工具，以及回合中向你追问的能力。", \.manage, { $0.manage = $1 }),
            ("长期记忆", "读取与写入记忆文档；关闭不会删除已有内容。", \.memory, { $0.memory = $1 }),
          ]
          ForEach(Array(capabilities.enumerated()), id: \.offset) { index, item in
            let (title, hint, keyPath, setter) = item
            switchRow(title: title, hint: hint, isOn: profile[keyPath: keyPath]) { on in
              Task { await model.updateAgentProfile { setter(&$0, on) } }
            }
            if index < capabilities.count - 1 { Divider().overlay(Brand.line) }
          }

          Divider().overlay(Brand.line)

          switchRow(
            title: "会话上下文",
            hint: "把用户名、日期和时区作为系统消息交给模型。",
            isOn: profile.sessionContext
          ) { on in
            Task { await model.updateAgentProfile { $0.sessionContext = on } }
          }

          Divider().overlay(Brand.line)

          VStack(alignment: .leading, spacing: 8) {
            Text("项目指令")
              .font(.system(size: 14))
              .foregroundStyle(Brand.ink)
            Text("追加：保留邦信阳的人设；替换：项目指令即全部系统提示。")
              .font(.system(size: 11))
              .foregroundStyle(Brand.muted)
            HStack(spacing: 8) {
              ForEach([("append", "追加"), ("replace", "替换")], id: \.0) { value, label in
                pill(label: label, icon: nil, selected: profile.persona == value) {
                  Task { await model.updateAgentProfile { $0.persona = value } }
                }
              }
              Spacer(minLength: 0)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 11)
        }
      } else {
        emptyLine("无法加载能力上限")
      }
    }
  }

  private var integrationsSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "Telegram 机器人", subtitle: "成员用来在 Telegram 里收发任务的 bot") {
        VStack(alignment: .leading, spacing: 10) {
          Text("Bot Token")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Brand.muted)
          SecureField("粘贴 BotFather 给的 token", text: $telegramBotToken)
            .font(.system(size: 15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Brand.accent.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
          Text("保存后由服务端加密存储，不可再读取。留空则不改动。")
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted)
          primaryButton(model.isSaving ? "保存中…" : "保存") {
            let token = telegramBotToken
            telegramBotToken = ""
            Task { await model.saveTelegramBotToken(token) }
          }
          .disabled(telegramBotToken.isEmpty || model.isSaving)
        }
      }

      sectionCard(title: "插件安装权限", subtitle: "谁可以从市场安装插件") {
        switchRow(
          title: "允许成员自行安装",
          hint: "关闭后只有管理员能安装插件。",
          isOn: model.membersCanInstallPlugins
        ) { on in
          Task { await model.setMembersCanInstallPlugins(on) }
        }
      }

      savedBannerLine

      connectorsMirrorCard
    }
  }

  private var connectorsMirrorCard: some View {
    sectionCard(title: "集成", subtitle: "组织级连接器（与扩展页相同数据源）") {
      toggleList(
        empty: "暂无连接器",
        loading: model.isLoading && model.connectors.isEmpty,
        count: model.connectors.count
      ) {
        ForEach(Array(model.connectors.enumerated()), id: \.element.id) { index, c in
          Toggle(isOn: Binding(
            get: { c.enabled },
            set: { _ in Task { await model.toggleConnector(c) } }
          )) {
            Text(c.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
          }
          .tint(Brand.primary)
          .padding(.vertical, 9)
          if index < model.connectors.count - 1 { Divider().overlay(Brand.line) }
        }
      }
    }
  }

  private var authenticationSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let auth = model.authConfig {
        sectionCard(title: "注册", subtitle: "谁可以创建账号") {
          VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
              Text("注册模式").font(.system(size: 14)).foregroundStyle(Brand.ink)
              Text("开放：任何人可直接注册；审批：注册后需管理员批准；关闭：不接受新注册。")
                .font(.system(size: 11)).foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
              HStack(spacing: 8) {
                ForEach([("open", "开放"), ("approval", "审批"), ("closed", "关闭")], id: \.0) { value, label in
                  pill(label: label, icon: nil, selected: auth.registrationMode == value) {
                    Task { await model.updateAuthConfig(["registrationMode": value]) }
                  }
                }
                Spacer(minLength: 0)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)

            Divider().overlay(Brand.line)

            switchRow(
              title: "邮箱注册",
              hint: "关闭后只能用飞书 / Telegram 登录。",
              isOn: auth.emailSignupEnabled
            ) { on in
              Task { await model.updateAuthConfig(["emailSignupEnabled": on]) }
            }
          }
        }

        sectionCard(title: "飞书登录", subtitle: auth.feishuReady ? "已配置 App ID 与 Secret" : "尚未配置 App ID / Secret") {
          switchRow(
            title: "启用飞书登录",
            hint: auth.feishuReady ? "登录页显示飞书入口。" : "需要先填写 App ID 与 Secret 才能开启。",
            isOn: auth.feishuEnabled,
            disabled: !auth.feishuReady
          ) { on in
            Task { await model.updateAuthConfig(["feishuEnabled": on]) }
          }
        }

        sectionCard(title: "Telegram 登录", subtitle: auth.telegramReady ? "已配置 Client ID 与 Secret" : "尚未配置 Client ID / Secret") {
          switchRow(
            title: "启用 Telegram 登录",
            hint: auth.telegramReady ? "登录页显示 Telegram 入口。" : "需要先填写 Client ID 与 Secret 才能开启。",
            isOn: auth.telegramEnabled,
            disabled: !auth.telegramReady
          ) { on in
            Task { await model.updateAuthConfig(["enabled": on]) }
          }
        }

        Text("App ID / Client Secret 属于一次性写入的敏感项，请在网页管理端填写。")
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
          .fixedSize(horizontal: false, vertical: true)

        savedBannerLine
      } else {
        sectionCard(title: "认证", subtitle: "登录方式与注册策略") {
          emptyLine("无法加载认证配置（需要管理员权限）")
        }
      }
    }
  }

  // MARK: - Permissions

  private var permissionsSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "治理规则", subtitle: "对技能与连接器的允许 / 询问 / 拒绝") {
        if model.policies.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("还没有规则")
              .font(.system(size: 13))
              .foregroundStyle(Brand.ink)
            Text("没有规则时按各能力自身的开关执行。")
              .font(.system(size: 11))
              .foregroundStyle(Brand.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(model.policies.enumerated()), id: \.element.id) { index, policy in
              policyRow(policy)
              if index < model.policies.count - 1 { Divider().overlay(Brand.line) }
            }
          }
        }
      }

      sectionCard(title: "能力开关", subtitle: "当前启用的扩展数量") {
        kvRow("技能", "\(model.skills.filter(\.enabled).count) / \(model.skills.count) 已启用")
        kvRow("连接器", "\(model.connectors.filter(\.enabled).count) / \(model.connectors.count) 已启用")
        Text("新增按用户 / 按项目的规则需要在网页「权限」页选择对象。")
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
          .padding(.top, 4)
      }
    }
  }

  private func policyRow(_ policy: PolicyRow) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(policy.capabilityKey)
          .font(.system(size: 14))
          .foregroundStyle(Brand.ink)
          .lineLimit(1)
        Text("\(policy.typeLabel) · \(policy.scopeLabel)")
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }
      Spacer(minLength: 8)

      // Only system rules are editable here — user and project rules need their
      // subject picked, which is a web-only flow.
      if policy.scope == "system" {
        Menu {
          ForEach(["allow", "ask", "deny"], id: \.self) { effect in
            Button(PolicyRow(id: "", capabilityType: "", capabilityKey: "", effect: effect, scope: "system").effectLabel) {
              Task { await model.setPolicyEffect(policy, effect: effect) }
            }
          }
          Divider()
          Button(role: .destructive) {
            Task { await model.removePolicy(policy) }
          } label: {
            Label("移除规则", systemImage: "trash")
          }
        } label: {
          HStack(spacing: 4) {
            Text(policy.effectLabel)
              .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
              .font(.system(size: 8, weight: .semibold))
          }
          .foregroundStyle(policy.effect == "deny" ? Brand.dangerText : Brand.ink)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(policy.effect == "deny" ? Brand.dangerSurface : Brand.accent)
          .clipShape(Capsule())
        }
      } else {
        Text(policy.effectLabel)
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
      }
    }
    .padding(.vertical, 10)
  }

  // MARK: - Billing

  private var billingAdminSection: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "密钥模式", subtitle: "成员用共享密钥、自带密钥，还是两者皆可") {
        VStack(spacing: 0) {
          let modes = [
            ("shared_plus_own", "共享 + 自带密钥", "成员默认用实例密钥，也可以填自己的。"),
            ("shared_only", "仅共享密钥", "成员只能用实例密钥，额度由层级控制。"),
            ("own_only", "仅自带密钥", "实例不提供密钥，每人必须自己配置。"),
          ]
          ForEach(Array(modes.enumerated()), id: \.offset) { index, item in
            let (value, title, hint) = item
            Button {
              Task { await model.setKeyMode(value) }
            } label: {
              HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(title).font(.system(size: 14)).foregroundStyle(Brand.ink)
                  Text(hint).font(.system(size: 11)).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 8)
                if model.adminKeyMode == value {
                  Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.primary)
                }
              }
              .padding(.vertical, 11)
              .contentShape(Rectangle())
            }
            .buttonStyle(CapkaPressStyle())
            if index < modes.count - 1 { Divider().overlay(Brand.line) }
          }
        }
      }

      sectionCard(title: "默认层级额度", subtitle: "留空表示不限；单位与用量页一致") {
        VStack(alignment: .leading, spacing: 12) {
          limitField("5 小时上限", text: $model.tierLimits.limit5h)
          limitField("每周上限", text: $model.tierLimits.limitWeek)
          limitField("每月上限", text: $model.tierLimits.limitMonth)
          limitField("实例月度预算", text: $model.tierLimits.budgetMonthly)
          primaryButton(model.isSaving ? "保存中…" : "保存额度") {
            Task { await model.saveTierLimits() }
          }
          .disabled(model.isSaving)
        }
      }

      sectionCard(title: "逐人层级", subtitle: "为个别成员指定层级；清除则回落到默认层级") {
        if model.adminUsers.isEmpty {
          emptyLine("还没有用户")
        } else {
          VStack(spacing: 0) {
            ForEach(Array(model.adminUsers.enumerated()), id: \.element.id) { index, user in
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(user.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
                  if let email = user.email {
                    Text(email).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(1)
                  }
                }
                Spacer(minLength: 8)
                Button("回落到默认") {
                  Task { await model.assignDefaultTier(user) }
                }
                .font(.system(size: 12))
                .foregroundStyle(Brand.link)
              }
              .padding(.vertical, 10)
              if index < model.adminUsers.count - 1 { Divider().overlay(Brand.line) }
            }
          }
        }
      }

      savedBannerLine
    }
  }

  private var usageSection: some View {
    sectionCard(title: "用量分析", subtitle: "近 \(model.adminUsage?.days ?? 30) 天汇总") {
      if let u = model.adminUsage {
        kvRow("费用", String(format: "%.4f", u.cost))
        kvRow("调用次数", "\(u.calls)")
        kvRow("输入 tokens", "\(u.inputTokens)")
        kvRow("输出 tokens", "\(u.outputTokens)")
        if let members = u.activeMembers {
          kvRow("活跃成员", "\(members)")
        }
      } else {
        emptyLine("暂无用量数据")
      }
    }
  }

  private var usersSection: some View {
    sectionCard(title: "用户", subtitle: "批准、分配角色并查看消费") {
      if model.adminUsers.isEmpty {
        emptyLine("还没有用户")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.adminUsers.enumerated()), id: \.element.id) { index, user in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(user.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.ink)
                  if let email = user.email {
                    Text(email)
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                }
                Spacer()
                Text(statusLabel(user.status))
                  .font(.system(size: 11))
                  .foregroundStyle(user.status == "pending" ? Brand.warningText : Brand.muted)
              }
              HStack(spacing: 8) {
                Menu {
                  ForEach(["admin", "user", "viewer"], id: \.self) { role in
                    Button(roleLabel(role)) {
                      Task { await model.setUserRole(user, role: role) }
                    }
                  }
                } label: {
                  Text(roleLabel(user.role))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Brand.accent)
                    .clipShape(Capsule())
                }
                if user.status == "pending" {
                  Button("批准") {
                    Task { await model.setUserStatus(user, status: "active") }
                  }
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(Brand.link)
                }
                Menu {
                  Button(user.status == "suspended" ? "恢复访问" : "暂停访问") {
                    Task {
                      await model.setUserStatus(user, status: user.status == "suspended" ? "active" : "suspended")
                    }
                  }
                  Button(role: .destructive) { confirmDeleteUser = user } label: {
                    Label("删除用户", systemImage: "trash")
                  }
                } label: {
                  Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
                }
                Spacer()
                if let cost = user.cost30d {
                  Text(String(format: "%.2f / 30d", cost))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Brand.muted)
                }
              }
            }
            .padding(.vertical, 10)
            if index < model.adminUsers.count - 1 { Divider().overlay(Brand.line) }
          }
        }
      }
    }
  }

  private var activitySection: some View {
    sectionCard(title: "活动", subtitle: "审计日志") {
      if model.audit.isEmpty {
        emptyLine("暂无活动记录")
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(model.audit.enumerated()), id: \.element.id) { index, e in
            VStack(alignment: .leading, spacing: 2) {
              Text(e.action)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.ink)
              HStack {
                Text(e.actorName ?? "系统")
                  .font(.system(size: 11))
                  .foregroundStyle(Brand.muted)
                if let key = e.targetKey {
                  Text("· \(key)")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                }
                Spacer()
                if let at = e.createdAt {
                  Text(String(at.prefix(16)).replacingOccurrences(of: "T", with: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.muted)
                }
              }
            }
            .padding(.vertical, 8)
            if index < model.audit.count - 1 { Divider().overlay(Brand.line) }
          }
        }
      }
    }
  }

  private var updatesSection: some View {
    sectionCard(title: "更新", subtitle: "当前部署版本") {
      if let u = model.updates {
        kvRow("当前版本", u.current ?? "—")
        kvRow("最新版本", u.latest ?? "—")
        kvRow("状态", u.updateAvailable ? "有可用更新" : "已是最新")
        if let name = u.releaseName, !name.isEmpty {
          kvRow("发布", name)
        }
        if let err = u.error, !err.isEmpty {
          Text(err)
            .font(.system(size: 12))
            .foregroundStyle(Brand.dangerText)
        }
        if let notes = u.notes, !notes.isEmpty {
          Text(notes)
            .font(.system(size: 12))
            .foregroundStyle(Brand.muted)
            .padding(.top, 4)
        }
      } else {
        emptyLine("无法检查更新")
      }
    }
  }

  // MARK: - Shared chrome

  private func sectionCard<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Brand.ink)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .capkaCard()
  }

  /// Title + hint on the left, switch on the right — the shape every admin
  /// toggle on the web's security page uses.
  private func switchRow(
    title: String,
    hint: String,
    isOn: Bool,
    disabled: Bool = false,
    onChange: @escaping (Bool) -> Void
  ) -> some View {
    Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14))
          .foregroundStyle(Brand.ink)
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .tint(Brand.primary)
    .disabled(disabled)
    .opacity(disabled ? 0.5 : 1)
    .padding(.vertical, 11)
  }

  private func pill(
    label: String,
    icon: String?,
    selected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        if let icon {
          Image(systemName: icon).font(.system(size: 11))
        }
        Text(label)
          .font(.system(size: 12, weight: selected ? .semibold : .regular))
      }
      .foregroundStyle(selected ? Brand.ink : Brand.muted)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(selected ? Brand.accent : Color.clear)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Brand.line, lineWidth: selected ? 0 : 1))
    }
    .buttonStyle(CapkaPressStyle())
  }

  private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Brand.onPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Brand.primary)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
    }
    .buttonStyle(CapkaPressStyle())
  }

  @ViewBuilder
  private var savedBannerLine: some View {
    if let banner = model.savedBanner {
      Text(banner)
        .font(.system(size: 12))
        .foregroundStyle(Brand.muted)
    }
  }

  private func toggleList<Content: View>(
    empty: String,
    loading: Bool,
    count: Int,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Group {
      if loading {
        ProgressView().tint(Brand.primary).frame(maxWidth: .infinity).padding(.vertical, 12)
      } else if count == 0 {
        emptyLine(empty)
      } else {
        VStack(spacing: 0) { content() }
      }
    }
  }

  private func emptyLine(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(Brand.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }

  private func kvRow(_ key: String, _ value: String) -> some View {
    HStack {
      Text(key)
        .font(.system(size: 13))
        .foregroundStyle(Brand.muted)
      Spacer()
      Text(value)
        .font(.system(size: 13))
        .foregroundStyle(Brand.ink)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 4)
  }

  private func windowLabel(_ key: String) -> String {
    switch key {
    case "h5": return "近 5 小时"
    case "d7": return "近 7 天"
    case "d30": return "近 30 天"
    default: return key
    }
  }

  private func roleLabel(_ role: String) -> String {
    switch role {
    case "admin": return "管理员"
    case "viewer": return "只读"
    default: return "用户"
    }
  }

  private func statusLabel(_ status: String) -> String {
    switch status {
    case "pending": return "待批准"
    case "suspended": return "已停用"
    case "rejected": return "已拒绝"
    default: return "正常"
    }
  }
}
