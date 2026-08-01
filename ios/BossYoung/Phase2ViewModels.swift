import Foundation
import Observation
import SwiftUI

// MARK: - Chat list actions (Phase 2)

extension ChatListViewModel {
  func refreshFiltered(archived: Bool = false, projectId: String? = nil, search: String? = nil) async {
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let page = try await api.listChats(archived: archived, projectId: projectId, search: search)
      chats = page.chats
      nextCursor = page.nextCursor
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func rename(chatId: String, title: String) async {
    do {
      try await api.patchChat(id: chatId, title: title)
      if let idx = chats.firstIndex(where: { $0.id == chatId }) {
        chats[idx] = ChatSummary.mutated(chats[idx], title: title)
      }
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setPinned(chatId: String, pinned: Bool) async {
    do {
      try await api.patchChat(id: chatId, pinned: pinned)
      if let idx = chats.firstIndex(where: { $0.id == chatId }) {
        chats[idx] = ChatSummary.mutated(chats[idx], pinned: pinned)
      }
      await refreshQuietly()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setArchived(chatId: String, archived: Bool) async {
    do {
      try await api.patchChat(id: chatId, archived: archived)
      chats.removeAll { $0.id == chatId }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func deleteChat(chatId: String) async {
    do {
      try await api.deleteChat(id: chatId)
      chats.removeAll { $0.id == chatId }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func moveToProject(chatId: String, projectId: String?) async {
    do {
      try await api.patchChat(id: chatId, projectId: .some(projectId))
      await refreshQuietly()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Projects

@MainActor
@Observable
final class ProjectsViewModel {
  var projects: [ProjectSummary] = []
  var isLoading = false
  var error: String?
  private let api = CapkaAPIClient.shared
  private weak var session: SessionStore?

  func bind(session: SessionStore) { self.session = session }

  func refresh() async {
    if CapkaFixtures.isEnabled {
      CapkaFixtures.seed(projects: self)
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      projects = try await api.listProjects()
      error = nil
    } catch CapkaAPIError.unauthorized {
      await session?.noteUnauthorized()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func create(name: String, description: String?) async -> ProjectSummary? {
    do {
      let p = try await api.createProject(name: name, description: description)
      await refresh()
      return p
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  func delete(id: String) async {
    do {
      try await api.deleteProject(id: id)
      projects.removeAll { $0.id == id }
    } catch {
      self.error = error.localizedDescription
    }
  }
}

@MainActor
@Observable
final class ProjectHubViewModel {
  let project: ProjectSummary
  var chats: [ChatSummary] = []
  var files: [WorkspaceEntry] = []
  var name: String
  var descriptionText: String
  var systemPrompt: String
  var memory = ""
  var isLoading = false
  var error: String?
  var savedBanner: String?

  private let api = CapkaAPIClient.shared

  init(project: ProjectSummary) {
    self.project = project
    self.name = project.name
    self.descriptionText = project.description ?? ""
    self.systemPrompt = project.systemPrompt ?? ""
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let chatPage = api.listChats(archived: false, projectId: project.id)
      async let fileList = api.listFiles(projectId: project.id)
      async let memoryDoc = api.fetchProjectMemory(projectId: project.id)
      chats = try await chatPage.chats
      files = (try? await fileList) ?? []
      memory = (try? await memoryDoc) ?? ""
    } catch {
      self.error = error.localizedDescription
    }
  }

  func saveSettings() async {
    do {
      try await api.updateProject(
        id: project.id,
        name: name,
        description: descriptionText,
        systemPrompt: systemPrompt
      )
      savedBanner = "已保存"
    } catch {
      self.error = error.localizedDescription
    }
  }

  func saveMemory() async {
    do {
      try await api.saveMemory(memory, projectId: project.id)
      savedBanner = "已保存"
    } catch {
      self.error = error.localizedDescription
    }
  }

  func newChat() async -> String? {
    do {
      return try await api.createChat(title: "新对话", projectId: project.id)
    } catch {
      self.error = error.localizedDescription
      return nil
    }
  }

  func upload(fileURL: URL) async {
    do {
      let accessing = fileURL.startAccessingSecurityScopedResource()
      defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
      _ = try await api.uploadFile(projectId: project.id, fileURL: fileURL)
      files = try await api.listFiles(projectId: project.id)
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Workspace browser (chat or project sandbox)

@MainActor
@Observable
final class WorkspaceViewModel {
  let chatId: String?
  let projectId: String?

  var entries: [WorkspaceEntry] = []
  var path = "."
  var isLoading = false
  var error: String?

  private let api = CapkaAPIClient.shared

  init(chatId: String?, projectId: String?) {
    self.chatId = chatId
    self.projectId = projectId
  }

  var canGoUp: Bool { path != "." && !path.isEmpty }

  var visible: [WorkspaceEntry] {
    entries
      .filter { !$0.name.hasPrefix(".") }
      .sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
      }
  }

  func load() async {
    if CapkaFixtures.isEnabled {
      CapkaFixtures.seed(workspace: self)
      return
    }
    guard chatId != nil || projectId != nil else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      entries = try await api.listFiles(chatId: chatId, projectId: projectId, path: path)
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  func open(_ entry: WorkspaceEntry) async {
    guard entry.isDirectory else { return }
    path = entry.path
    await load()
  }

  func goUp() async {
    let parts = path.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }
    path = parts.count <= 1 ? "." : parts.dropLast().joined(separator: "/")
    await load()
  }

  func upload(fileURL: URL) async {
    do {
      let accessing = fileURL.startAccessingSecurityScopedResource()
      defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
      _ = try await api.uploadFile(chatId: chatId, projectId: projectId, fileURL: fileURL)
      await load()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Settings

@MainActor
@Observable
final class SettingsViewModel {
  /// Mirrors web `/settings` nav keys (personal + admin).
  enum Tab: String, CaseIterable, Identifiable {
    case general
    case connections
    case memory
    case skills
    case automations
    case security
    case integrations
    case authentication
    case permissions
    case billingAdmin
    case usage
    case users
    case activity
    case updates

    var id: String { rawValue }

    var title: String {
      switch self {
      case .general: return "通用"
      case .connections: return "连接"
      case .memory: return "记忆"
      case .skills: return "扩展"
      case .automations: return "自动化"
      case .security: return "安全性"
      case .integrations: return "集成"
      case .authentication: return "认证"
      case .permissions: return "权限"
      case .billingAdmin: return "密钥与限额"
      case .usage: return "分析"
      case .users: return "用户"
      case .activity: return "活动"
      case .updates: return "更新"
      }
    }

    var icon: String {
      switch self {
      case .general: return "gearshape"
      case .connections: return "link"
      case .memory: return "brain"
      case .skills: return "sparkles"
      case .automations: return "calendar"
      case .security: return "lock"
      case .integrations: return "puzzlepiece.extension"
      case .authentication: return "key"
      case .permissions: return "checkmark.shield"
      case .billingAdmin: return "creditcard"
      case .usage: return "chart.bar"
      case .users: return "person.2"
      case .activity: return "scroll"
      case .updates: return "arrow.down.circle"
      }
    }

    var isAdminOnly: Bool {
      switch self {
      case .general, .connections, .memory, .skills, .automations: return false
      default: return true
      }
    }
  }

  enum ExtTab: String, CaseIterable, Identifiable {
    case skills = "技能"
    case connectors = "连接器"
    case plugins = "插件"
    var id: String { rawValue }
  }

  var extTab: ExtTab = .skills
  var isAdmin = false

  var displayName = ""
  var email = ""
  var locale = "zh-CN"
  var skills: [SkillInfo] = []
  var connectors: [ConnectorInfo] = []
  var plugins: [PluginInfo] = []
  var automations: [AutomationInfo] = []
  var providers: [ProviderConfig] = []
  var memory = ""
  var memoryProjects: [MemoryProjectDoc] = []
  var selectedMemoryProjectId: String?
  var billing: BillingInfo?
  var telegram: TelegramLinkInfo?
  var telegramCode: String?
  var adminUsers: [AdminUserRow] = []
  var adminUsage: AdminUsageSummary?
  var adminKeyMode: String?
  var adminMonthlyBudget: Double?
  var authConfig: AuthConfigInfo?
  var updates: AdminUpdatesInfo?
  var audit: [AuditEntry] = []
  var sandbox: SandboxCapabilities?
  /// Admin security switches, each a row in the generic key/value settings table.
  var sandboxNetworkSetting: String?
  var hostFolderAccess = false
  var pcFolderAccess = "off"
  var agentAutonomy = "supervised"
  var blockPrivateProviderURLs = false
  var agentProfile: AgentProfile?
  var policies: [PolicyRow] = []
  var isLoading = false
  var isSaving = false
  var error: String?
  var savedBanner: String?

  private let api = CapkaAPIClient.shared

  var visibleTabs: [Tab] {
    let showConnections = isAdmin || (billing?.ownKeysAllowed ?? false)
    return Tab.allCases.filter { tab in
      if tab == .connections { return showConnections }
      if tab.isAdminOnly { return isAdmin }
      return true
    }
  }

  var memoryDraft: String {
    get {
      if let id = selectedMemoryProjectId,
         let doc = memoryProjects.first(where: { $0.id == id }) {
        return doc.content
      }
      return memory
    }
    set {
      if let id = selectedMemoryProjectId,
         let idx = memoryProjects.firstIndex(where: { $0.id == id }) {
        memoryProjects[idx].content = newValue
      } else {
        memory = newValue
      }
    }
  }

  func load(user: CapkaUser?) async {
    if CapkaFixtures.isEnabled {
      CapkaFixtures.seed(settings: self)
      displayName = user?.name ?? "韩欣"
      email = user?.email ?? "hanxin@boss-young.com"
      isAdmin = user?.role == "admin"
      return
    }
    isLoading = true
    defer { isLoading = false }
    displayName = user?.name ?? ""
    email = user?.email ?? ""
    isAdmin = user?.role == "admin"
    async let skillsTask = api.listSkills()
    async let connectorsTask = api.listConnectors()
    async let automationsTask = api.listAutomations()
    async let memoryTask = api.fetchMemoryDocs()
    async let billingTask = api.fetchBilling()
    async let telegramTask = api.fetchTelegramLink()
    async let pluginsTask = api.listPlugins()
    async let providersTask = api.listProviders()
    skills = (try? await skillsTask) ?? []
    connectors = (try? await connectorsTask) ?? []
    automations = (try? await automationsTask) ?? []
    if let docs = try? await memoryTask {
      memory = docs.user
      memoryProjects = docs.projects
    }
    billing = try? await billingTask
    telegram = try? await telegramTask
    plugins = (try? await pluginsTask) ?? []
    providers = (try? await providersTask) ?? []
    await api.putTimezone(TimeZone.current.identifier)

    if isAdmin {
      async let usersTask = api.listAdminUsers()
      async let usageTask = api.fetchAdminUsage()
      async let billTask = api.fetchAdminBilling()
      async let authTask = api.fetchAuthConfig()
      async let updatesTask = api.fetchAdminUpdates()
      async let auditTask = api.fetchAuditLog()
      async let sandboxTask = api.fetchSandboxCapabilities()
      async let netTask = api.fetchSetting(key: "sandbox_network")
      async let hostFoldersTask = api.fetchSetting(key: "host_folder_access")
      async let pcFoldersTask = api.fetchSetting(key: "pc_folder_access")
      async let autonomyTask = api.fetchSetting(key: "agent_autonomy")
      async let blockPrivateTask = api.fetchSetting(key: "block_private_provider_urls")
      async let profileTask = api.fetchAgentProfile()
      async let policiesTask = api.listPolicies()
      adminUsers = (try? await usersTask) ?? []
      adminUsage = try? await usageTask
      if let b = try? await billTask {
        adminKeyMode = b.keyMode
        adminMonthlyBudget = b.monthlyBudget
      }
      authConfig = try? await authTask
      updates = try? await updatesTask
      audit = (try? await auditTask) ?? []
      sandbox = try? await sandboxTask
      sandboxNetworkSetting = try? await netTask
      hostFolderAccess = (try? await hostFoldersTask) == "true"
      pcFolderAccess = (try? await pcFoldersTask) ?? "off"
      agentAutonomy = (try? await autonomyTask) ?? "supervised"
      blockPrivateProviderURLs = (try? await blockPrivateTask) == "true"
      agentProfile = try? await profileTask
      policies = (try? await policiesTask) ?? []
    }
  }

  // MARK: - Admin security switches

  /// Apply optimistically and roll back on failure, like the web page — the UI
  /// must never claim a restriction that isn't actually in force.
  private func writeSetting(key: String, value: String, rollback: @escaping () -> Void) async {
    do {
      try await api.putSetting(key: key, value: value)
      savedBanner = "已更新"
    } catch {
      rollback()
      self.error = error.localizedDescription
    }
  }

  func setSandboxNetwork(_ allowed: Bool) async {
    let previous = sandboxNetworkSetting
    sandboxNetworkSetting = allowed ? "bridge" : "none"
    await writeSetting(key: "sandbox_network", value: allowed ? "bridge" : "none") {
      self.sandboxNetworkSetting = previous
    }
  }

  func setHostFolderAccess(_ enabled: Bool) async {
    hostFolderAccess = enabled
    await writeSetting(key: "host_folder_access", value: enabled ? "true" : "false") {
      self.hostFolderAccess = !enabled
    }
  }

  func setPCFolderAccess(_ value: String) async {
    let previous = pcFolderAccess
    pcFolderAccess = value
    await writeSetting(key: "pc_folder_access", value: value) {
      self.pcFolderAccess = previous
    }
  }

  func setAutonomous(_ autonomous: Bool) async {
    let previous = agentAutonomy
    agentAutonomy = autonomous ? "autonomous" : "supervised"
    await writeSetting(key: "agent_autonomy", value: agentAutonomy) {
      self.agentAutonomy = previous
    }
  }

  func setBlockPrivateProviderURLs(_ enabled: Bool) async {
    blockPrivateProviderURLs = enabled
    await writeSetting(key: "block_private_provider_urls", value: enabled ? "true" : "false") {
      self.blockPrivateProviderURLs = !enabled
    }
  }

  func updateAgentProfile(_ mutate: (inout AgentProfile) -> Void) async {
    guard let previous = agentProfile else { return }
    var next = previous
    mutate(&next)
    agentProfile = next
    do {
      try await api.putAgentProfile(next)
      savedBanner = "已更新"
    } catch {
      agentProfile = previous
      self.error = error.localizedDescription
    }
  }

  // MARK: - Governance policies

  func setPolicyEffect(_ policy: PolicyRow, effect: String) async {
    guard policy.scope == "system" else { return }
    guard let idx = policies.firstIndex(where: { $0.id == policy.id }) else { return }
    let previous = policies[idx].effect
    policies[idx].effect = effect
    do {
      try await api.setSystemPolicy(
        capabilityType: policy.capabilityType,
        capabilityKey: policy.capabilityKey,
        effect: effect
      )
      policies = (try? await api.listPolicies()) ?? policies
    } catch {
      policies[idx].effect = previous
      self.error = error.localizedDescription
    }
  }

  func removePolicy(_ policy: PolicyRow) async {
    do {
      try await api.clearPolicy(id: policy.id)
      policies.removeAll { $0.id == policy.id }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setKeyMode(_ mode: String) async {
    let previous = adminKeyMode
    adminKeyMode = mode
    do {
      try await api.setProviderKeyMode(mode)
      savedBanner = "已更新"
    } catch {
      adminKeyMode = previous
      self.error = error.localizedDescription
    }
  }

  func toggleProvider(_ p: ProviderConfig) async {
    do {
      try await api.setProviderEnabled(id: p.id, enabled: !p.isActive)
      if let idx = providers.firstIndex(where: { $0.id == p.id }) {
        providers[idx].isActive = !p.isActive
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func deleteProvider(_ p: ProviderConfig) async {
    do {
      try await api.deleteProvider(id: p.id)
      providers.removeAll { $0.id == p.id }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setUserRole(_ user: AdminUserRow, role: String) async {
    do {
      try await api.updateAdminUser(userId: user.id, role: role)
      if let idx = adminUsers.firstIndex(where: { $0.id == user.id }) {
        adminUsers[idx].role = role
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setUserStatus(_ user: AdminUserRow, status: String) async {
    do {
      try await api.updateAdminUser(userId: user.id, status: status)
      if let idx = adminUsers.firstIndex(where: { $0.id == user.id }) {
        adminUsers[idx].status = status
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func saveName() async {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      error = "姓名为必填项"
      return
    }
    isSaving = true
    defer { isSaving = false }
    do {
      try await api.updateUserName(trimmed)
      savedBanner = "名称已保存"
    } catch {
      self.error = error.localizedDescription
    }
  }

  func setLocale(_ value: String) async {
    locale = value
    await api.putLocale(value)
    savedBanner = "语言已更新"
  }

  func toggleSkill(_ skill: SkillInfo) async {
    do {
      try await api.setSkillEnabled(id: skill.id, enabled: !skill.enabled)
      if let idx = skills.firstIndex(where: { $0.id == skill.id }) {
        skills[idx].enabled = !skill.enabled
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func toggleConnector(_ c: ConnectorInfo) async {
    do {
      try await api.setConnectorEnabled(id: c.id, enabled: !c.enabled)
      if let idx = connectors.firstIndex(where: { $0.id == c.id }) {
        connectors[idx].enabled = !c.enabled
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func toggleAutomation(_ automation: AutomationInfo) async {
    do {
      try await api.setAutomationEnabled(id: automation.id, enabled: !automation.enabled)
      if let idx = automations.firstIndex(where: { $0.id == automation.id }) {
        automations[idx].enabled = !automation.enabled
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func deleteAutomation(_ automation: AutomationInfo) async {
    do {
      try await api.deleteAutomation(id: automation.id)
      automations.removeAll { $0.id == automation.id }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func saveMemory() async {
    isSaving = true
    defer { isSaving = false }
    do {
      try await api.saveMemory(memoryDraft, projectId: selectedMemoryProjectId)
      savedBanner = "记忆已保存"
    } catch {
      self.error = error.localizedDescription
    }
  }

  func generateTelegramCode() async {
    do {
      telegramCode = try await api.createTelegramLinkCode()
    } catch {
      self.error = error.localizedDescription
    }
  }

  func unlinkTelegram() async {
    do {
      try await api.unlinkTelegram()
      telegram = TelegramLinkInfo(linked: false, username: nil, botUsername: telegram?.botUsername, linkedAt: nil)
      telegramCode = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  func refreshTelegram() async {
    telegram = try? await api.fetchTelegramLink()
  }
}
