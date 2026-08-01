import SwiftUI
import UIKit

/// Settings shell matching web `/settings` nav: personal tabs + admin tabs.
struct SettingsHomeView: View {
  @Environment(SessionStore.self) private var session
  @State private var model = SettingsViewModel()

  var body: some View {
    @Bindable var model = model
    ZStack {
      Brand.cream.ignoresSafeArea()

      VStack(spacing: 0) {
        tabBar(model: model)
        Divider().overlay(Brand.line)

        ScrollView {
          Group {
            switch model.tab {
            case .general: generalSection(model: model)
            case .connections: connectionsSection(model: model)
            case .memory: memorySection(model: model)
            case .skills: extensionsSection(model: model)
            case .automations: automationsSection(model: model)
            case .security: securitySection(model: model)
            case .integrations: integrationsSection(model: model)
            case .authentication: authenticationSection(model: model)
            case .permissions: permissionsSection(model: model)
            case .billingAdmin: billingAdminSection(model: model)
            case .usage: usageSection(model: model)
            case .users: usersSection(model: model)
            case .activity: activitySection(model: model)
            case .updates: updatesSection(model: model)
            }
          }
          .padding(16)
          .padding(.bottom, 28)
        }
      }
    }
    .navigationTitle("设置")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Brand.cream, for: .navigationBar)
    .task { await model.load(user: session.user) }
    .alert("出错了", isPresented: Binding(
      get: { model.error != nil },
      set: { if !$0 { model.error = nil } }
    )) {
      Button("好", role: .cancel) { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }

  // MARK: - Tabs

  private func tabBar(model: SettingsViewModel) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(model.visibleTabs) { tab in
          Button {
            withAnimation(Motion.easeOut(0.2)) { model.tab = tab }
          } label: {
            HStack(spacing: 5) {
              Image(systemName: tab.icon)
                .font(.system(size: 12))
              Text(tab.title)
                .font(.system(size: 13, weight: model.tab == tab ? .semibold : .regular))
            }
            .foregroundStyle(model.tab == tab ? Brand.ink : Brand.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(model.tab == tab ? Brand.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
  }

  // MARK: - General

  private func generalSection(model: SettingsViewModel) -> some View {
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

          Button {
            Task { await model.saveName() }
          } label: {
            Text(model.isSaving ? "保存中…" : "保存")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Brand.onPrimary)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Brand.primary)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          }
          .disabled(model.isSaving)
        }
      }

      sectionCard(title: "语言", subtitle: "界面显示语言") {
        HStack(spacing: 8) {
          ForEach([("zh-CN", "简体中文"), ("en", "English"), ("uk", "Українська")], id: \.0) { code, label in
            Button {
              Task { await model.setLocale(code) }
            } label: {
              Text(label)
                .font(.system(size: 12, weight: model.locale == code ? .semibold : .regular))
                .foregroundStyle(model.locale == code ? Brand.ink : Brand.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(model.locale == code ? Brand.accent : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Brand.line, lineWidth: model.locale == code ? 0 : 1))
            }
            .buttonStyle(.plain)
          }
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
        telegramCard(model: model)
      }

      if let banner = model.savedBanner {
        Text(banner)
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
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
  }

  private func telegramCard(model: SettingsViewModel) -> some View {
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
          Button("生成连接代码") {
            Task { await model.generateTelegramCode() }
          }
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Brand.onPrimary)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Brand.primary)
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))

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

  private func connectionsSection(model: SettingsViewModel) -> some View {
    sectionCard(title: "模型连接", subtitle: "提供商 API 密钥与默认模型。新增密钥请在网页完成。") {
      if model.isLoading && model.providers.isEmpty {
        ProgressView().tint(Brand.primary).frame(maxWidth: .infinity).padding(.vertical, 12)
      } else if model.providers.isEmpty {
        emptyLine("尚未配置提供商")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.providers.enumerated()), id: \.element.id) { index, p in
            Toggle(isOn: Binding(
              get: { p.isActive },
              set: { _ in Task { await model.toggleProvider(p) } }
            )) {
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
                if let modelId = p.defaultModel, !modelId.isEmpty {
                  Text(modelId)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                }
              }
            }
            .tint(Brand.primary)
            .padding(.vertical, 9)
            .contextMenu {
              Button(role: .destructive) {
                Task { await model.deleteProvider(p) }
              } label: {
                Label("删除", systemImage: "trash")
              }
            }
            if index < model.providers.count - 1 { Divider().overlay(Brand.line) }
          }
        }
      }
    }
  }

  // MARK: - Extensions

  private func extensionsSection(model: SettingsViewModel) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 6) {
        ForEach(SettingsViewModel.ExtTab.allCases) { tab in
          Button {
            withAnimation(Motion.easeOut(0.18)) { model.extTab = tab }
          } label: {
            Text(tab.rawValue)
              .font(.system(size: 12.5, weight: model.extTab == tab ? .semibold : .regular))
              .foregroundStyle(model.extTab == tab ? Brand.ink : Brand.muted)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(model.extTab == tab ? Brand.card : Color.clear)
              .clipShape(Capsule())
              .overlay(Capsule().stroke(Brand.line, lineWidth: 1))
          }
          .buttonStyle(.plain)
        }
        Spacer()
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
              if index < model.skills.count - 1 { Divider().overlay(Brand.line) }
            }
          }
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
              if index < model.connectors.count - 1 { Divider().overlay(Brand.line) }
            }
          }
        }
      case .plugins:
        sectionCard(title: "插件", subtitle: "已安装的扩展包") {
          if model.plugins.isEmpty {
            emptyLine("暂无已安装插件")
          } else {
            VStack(spacing: 0) {
              ForEach(Array(model.plugins.enumerated()), id: \.element.id) { index, p in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 14)).foregroundStyle(Brand.ink)
                    if let d = p.description, !d.isEmpty {
                      Text(d).font(.system(size: 11)).foregroundStyle(Brand.muted).lineLimit(2)
                    }
                  }
                  Spacer()
                  Text(p.enabled ? "已启用" : "已停用")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                }
                .padding(.vertical, 10)
                if index < model.plugins.count - 1 { Divider().overlay(Brand.line) }
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Memory

  private func memorySection(model: SettingsViewModel) -> some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 18) {
      if !model.memoryProjects.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            memoryChip(title: "个人", selected: model.selectedMemoryProjectId == nil) {
              model.selectedMemoryProjectId = nil
            }
            ForEach(model.memoryProjects) { doc in
              memoryChip(title: doc.name, selected: model.selectedMemoryProjectId == doc.id) {
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
          Button {
            Task { await model.saveMemory() }
          } label: {
            Text(model.isSaving ? "保存中…" : "保存")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Brand.onPrimary)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Brand.primary)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          }
          if let banner = model.savedBanner {
            Text(banner).font(.system(size: 12)).foregroundStyle(Brand.muted)
          }
        }
      }
    }
  }

  private func memoryChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? Brand.ink : Brand.muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Brand.accent : Brand.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Brand.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Automations

  private func automationsSection(model: SettingsViewModel) -> some View {
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

  // MARK: - Admin pages

  private func securitySection(model: SettingsViewModel) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      sectionCard(title: "沙箱网络", subtitle: "执行环境是否允许出站访问") {
        kvRow("控制器上报", networkLabel(model.sandbox?.allowNetwork))
        kvRow("实例设置", model.sandboxNetworkSetting ?? "—")
        Text("完整开关与主机文件夹策略请在网页设置中调整。")
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
          .padding(.top, 4)
      }
    }
  }

  private func integrationsSection(model: SettingsViewModel) -> some View {
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

  private func authenticationSection(model: SettingsViewModel) -> some View {
    sectionCard(title: "认证", subtitle: "登录方式与注册策略") {
      if let auth = model.authConfig {
        kvRow("注册模式", auth.registrationMode ?? "—")
        kvRow("邮箱注册", auth.emailSignupEnabled ? "已开启" : "已关闭")
        kvRow("飞书", auth.feishuReady ? (auth.feishuEnabled ? "已就绪 · 开启" : "已就绪 · 关闭") : "未配置")
        kvRow("Telegram", auth.telegramReady ? (auth.telegramEnabled ? "已就绪 · 开启" : "已就绪 · 关闭") : "未配置")
        Text("Client ID / Secret 等敏感项请在网页管理端修改。")
          .font(.system(size: 12))
          .foregroundStyle(Brand.muted)
          .padding(.top, 6)
      } else {
        emptyLine("无法加载认证配置（需要管理员权限）")
      }
    }
  }

  private func permissionsSection(model: SettingsViewModel) -> some View {
    sectionCard(title: "权限", subtitle: "组织级代理能力上限") {
      Text("沙箱、连接器、技能、记忆等治理策略的详细编辑请在网页「权限」页完成。移动端可查看扩展与连接器开关状态。")
        .font(.system(size: 13))
        .foregroundStyle(Brand.muted)
      kvRow("技能", "\(model.skills.filter(\.enabled).count) / \(model.skills.count) 已启用")
      kvRow("连接器", "\(model.connectors.filter(\.enabled).count) / \(model.connectors.count) 已启用")
    }
  }

  private func billingAdminSection(model: SettingsViewModel) -> some View {
    sectionCard(title: "密钥与限额", subtitle: "实例密钥模式与预算") {
      kvRow("密钥模式", keyModeLabel(model.adminKeyMode))
      if let budget = model.adminMonthlyBudget {
        kvRow("月度预算", String(format: "%.2f", budget))
      } else {
        kvRow("月度预算", "未设置")
      }
      Text("层级分配与模式切换请在网页完成。")
        .font(.system(size: 12))
        .foregroundStyle(Brand.muted)
        .padding(.top, 4)
    }
  }

  private func usageSection(model: SettingsViewModel) -> some View {
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

  private func usersSection(model: SettingsViewModel) -> some View {
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

  private func activitySection(model: SettingsViewModel) -> some View {
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

  private func updatesSection(model: SettingsViewModel) -> some View {
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

  private func networkLabel(_ value: Bool?) -> String {
    guard let value else { return "未知" }
    return value ? "允许出站" : "禁止出站"
  }

  private func keyModeLabel(_ mode: String?) -> String {
    switch mode {
    case "shared_plus_own": return "共享 + 自带密钥"
    case "shared_only": return "仅共享密钥"
    case "own_only": return "仅自带密钥"
    case .some(let m): return m
    case nil: return "—"
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
