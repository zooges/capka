import Foundation

struct CapkaUser: Equatable {
  var id: String
  var name: String
  var email: String?
  var role: String?
  /// Account lifecycle: `active` / `pending` / `suspended` / `rejected`.
  var status: String?
}

struct ChatSummary: Identifiable, Equatable {
  var id: String
  var title: String?
  var pinned: Bool?
  var archived: Bool?
  var updatedAt: String?
  var unread: Bool?
  var running: Bool?
  var projectName: String?
  var projectId: String?

  static func parseList(from data: Data) throws -> [ChatSummary] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else {
      throw CapkaAPIError.decoding
    }
    return root.compactMap { item -> ChatSummary? in
      guard let obj = item as? [String: Any], let id = obj["id"] as? String else { return nil }
      return ChatSummary(
        id: id,
        title: obj["title"] as? String,
        pinned: boolValue(obj["pinned"]),
        archived: boolValue(obj["archived"]),
        updatedAt: stringValue(obj["updatedAt"]),
        unread: boolValue(obj["unread"]),
        running: boolValue(obj["running"]),
        projectName: obj["projectName"] as? String,
        projectId: obj["projectId"] as? String
      )
    }
  }

  /// Sidebar date bucket — mirrors the web's 今天 / 昨天 / 本周 / 更早 groups.
  var dateGroup: String {
    guard let date = updatedAtDate else { return "更早" }
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "今天" }
    if cal.isDateInYesterday(date) { return "昨天" }
    if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), date > weekAgo { return "本周" }
    return "更早"
  }

  var updatedAtDate: Date? {
    guard let updatedAt else { return nil }
    return ISO8601DateFormatter.capkaFractional.date(from: updatedAt)
      ?? ISO8601DateFormatter.capkaPlain.date(from: updatedAt)
  }

  static func mutated(
    _ base: ChatSummary,
    title: String? = nil,
    running: Bool? = nil,
    unread: Bool? = nil,
    pinned: Bool? = nil,
    archived: Bool? = nil
  ) -> ChatSummary {
    ChatSummary(
      id: base.id,
      title: title ?? base.title,
      pinned: pinned ?? base.pinned,
      archived: archived ?? base.archived,
      updatedAt: base.updatedAt,
      unread: unread ?? base.unread,
      running: running ?? base.running,
      projectName: base.projectName,
      projectId: base.projectId
    )
  }
}

struct ProjectSummary: Identifiable, Equatable {
  var id: String
  var name: String
  var description: String?
  var systemPrompt: String?
  var defaultModel: String?
  var sandboxNetwork: Bool?
  var chatCount: Int?
  var lastChatAt: String?

  var lastChatDate: Date? {
    guard let lastChatAt else { return nil }
    return ISO8601DateFormatter.capkaFractional.date(from: lastChatAt)
      ?? ISO8601DateFormatter.capkaPlain.date(from: lastChatAt)
  }

  static func parseList(from data: Data) throws -> [ProjectSummary] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else {
      throw CapkaAPIError.decoding
    }
    return root.compactMap { parseOne($0) }
  }

  static func parseOne(_ item: Any) -> ProjectSummary? {
    guard let obj = item as? [String: Any], let id = obj["id"] as? String else { return nil }
    let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return ProjectSummary(
      id: id,
      name: (name?.isEmpty == false ? name! : "未命名项目"),
      description: obj["description"] as? String,
      systemPrompt: obj["systemPrompt"] as? String,
      defaultModel: obj["defaultModel"] as? String,
      sandboxNetwork: boolValue(obj["sandboxNetwork"]),
      chatCount: intValue(obj["chatCount"]),
      lastChatAt: stringValue(obj["lastChatAt"])
    )
  }
}

struct WorkspaceEntry: Identifiable, Equatable {
  var id: String { path }
  var name: String
  var path: String
  var isDirectory: Bool
  var size: Int64?
}

struct SkillInfo: Identifiable, Equatable {
  var id: String
  var name: String
  var description: String?
  var enabled: Bool
  var scope: String?
  var mine: Bool?
}

struct ConnectorInfo: Identifiable, Equatable {
  var id: String
  var name: String
  var url: String?
  var enabled: Bool
  var scope: String?
  var authKind: String?
}

struct AutomationInfo: Identifiable, Equatable {
  var id: String
  var title: String
  var enabled: Bool
  var nextRunAt: String?
  var lastRunAt: String?
  var lastChatId: String?

  var statusLabel: String {
    enabled ? "活跃" : "已暂停"
  }

  var nextRunLabel: String? {
    guard enabled, let nextRunAt,
          let date = ISO8601DateFormatter.capkaFractional.date(from: nextRunAt)
            ?? ISO8601DateFormatter.capkaPlain.date(from: nextRunAt)
    else { return nil }
    return "下次运行：" + date.formatted(date: .abbreviated, time: .shortened)
  }
}

struct PluginInfo: Identifiable, Equatable {
  var id: String
  var name: String
  var description: String?
  var enabled: Bool
  var author: String?
}

/// A plugin source (a git repo of packaged extensions) the instance trusts.
struct MarketplaceInfo: Identifiable, Equatable {
  var id: String
  var url: String
  var name: String?
  var owner: String?
  var pluginCount: Int
  var refreshedAt: String?

  var displayName: String {
    if let name, !name.isEmpty { return name }
    return url
  }
}

/// One entry in a marketplace's catalog. `installable` is false for sources the
/// server can't install from yet, so the row shows but the action doesn't.
struct CatalogItem: Identifiable, Equatable {
  var id: String { name }
  var name: String
  var description: String?
  var author: String?
  var category: String?
  var kind: String?
  var installable: Bool
  var installed: Bool
}

/// The default tier's spend caps plus the instance-wide monthly budget. Empty
/// means unlimited/unset, which is why these are strings rather than numbers.
struct TierLimits: Equatable {
  var limit5h = ""
  var limitWeek = ""
  var limitMonth = ""
  var budgetMonthly = ""
}

struct MasterKeyStatus: Equatable {
  /// `env` / `db` / `missing` — where the encryption key is coming from.
  var source: String?
  var dbKeyPresent: Bool
  /// Only returned while the key still needs to be written down.
  var key: String?
}

struct BillingWindow: Identifiable, Equatable {
  var id: String { window }
  var window: String
  var pct: Double
  var limit: Double?
}

struct BillingInfo: Equatable {
  var onSharedKey: Bool
  var ownKeysAllowed: Bool
  var tierName: String?
  var windows: [BillingWindow]
  var blocked: Bool
}

struct TelegramLinkInfo: Equatable {
  var linked: Bool
  var username: String?
  var botUsername: String?
  var linkedAt: String?
}

struct MemoryProjectDoc: Identifiable, Equatable {
  var id: String
  var name: String
  var content: String
}

struct ModelInfo: Identifiable, Equatable {
  var id: String
  var name: String
  var provider: String?
  var group: String?
  var featured: Bool?
  var context: Int?
  var vision: Bool?
  var reasoning: Bool?

  var displayGroup: String {
    if let group, !group.isEmpty { return group }
    if let provider, !provider.isEmpty { return provider.capitalized }
    return "其他"
  }

  static func parseList(from data: Data) throws -> [ModelInfo] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CapkaAPIError.decoding
    }
    let arr = (root["models"] as? [Any]) ?? []
    return arr.compactMap { item -> ModelInfo? in
      guard let obj = item as? [String: Any] else { return nil }
      // Prefer config-scoped selection when present (same as web encodeModelRef).
      let bareId = (obj["id"] as? String) ?? (obj["name"] as? String)
      guard let bareId, !bareId.isEmpty else { return nil }
      let configId = obj["configId"] as? String
      let id = (configId?.isEmpty == false) ? "\(configId!):\(bareId)" : bareId
      let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let caps = obj["capabilities"] as? [String: Any]
      let ctx: Int?
      if let i = obj["context"] as? Int { ctx = i }
      else if let d = obj["context"] as? Double { ctx = Int(d) }
      else { ctx = nil }
      return ModelInfo(
        id: id,
        name: (name?.isEmpty == false ? name! : bareId),
        provider: obj["provider"] as? String,
        group: obj["group"] as? String,
        featured: boolValue(obj["featured"]),
        context: ctx,
        vision: boolValue(caps?["vision"]),
        reasoning: boolValue(caps?["reasoning"])
      )
    }
  }
}

struct SendChatResponse: Decodable {
  var taskId: String
  var chatId: String
}

/// One row of the assistant activity rail (a tool call or a reasoning block).
struct MessageStep: Identifiable, Equatable {
  enum Kind: Equatable { case tool, reasoning }
  enum State: Equatable { case running, done, failed }

  var id: String
  var kind: Kind
  var state: State
  var label: String
  var icon: String
  var detail: String?
  /// Workspace paths of pages a `view_file`-style tool rendered. Served inline
  /// from the sandbox rather than embedded, so nothing large rides in the DB.
  var imagePaths: [String] = []
}

struct MessageAttachment: Identifiable, Equatable {
  var id: String { name }
  var name: String
  var type: String

  var isImage: Bool { type.hasPrefix("image/") }
}

/// Fields behind the assistant (i) popover — mirrors `chat.details.*` on the web.
struct MessageDetails: Equatable {
  var model: String?
  var inputTokens: Int?
  var outputTokens: Int?
  var durationMs: Int?
  var stepCount: Int?
  var createdAt: Date?
  /// Prompt size of this turn's last LLM call — drives the context meter.
  var contextTokens: Int?
  var contextWindow: Int?

  /// 0…1 fill of the model's context window, when both figures are known.
  var contextFill: Double? {
    guard let contextTokens, let contextWindow, contextWindow > 0 else { return nil }
    return min(1, Double(contextTokens) / Double(contextWindow))
  }

  var isEmpty: Bool {
    model == nil && inputTokens == nil && outputTokens == nil && durationMs == nil && createdAt == nil
  }
}

struct ChatUIMessage: Identifiable, Equatable {
  var id: String
  var role: String
  var text: String
  var isStreaming: Bool
  var error: String?
  var tools: [String]
  var steps: [MessageStep]
  var attachments: [MessageAttachment]
  /// Position among alternative versions of this message (edits/regenerations),
  /// and how many there are — drives the ‹ i/N › switcher.
  var siblingIndex: Int = 0
  var siblingCount: Int = 1
  var details: MessageDetails
  var isCompaction: Bool
  /// What the model now sees in place of the collapsed turns, revealed when the
  /// compaction divider is expanded.
  var compactionSummary: String?

  init(
    id: String,
    role: String,
    text: String,
    isStreaming: Bool,
    error: String? = nil,
    tools: [String] = [],
    steps: [MessageStep] = [],
    attachments: [MessageAttachment] = [],
    siblingIndex: Int = 0,
    siblingCount: Int = 1,
    details: MessageDetails = MessageDetails(),
    isCompaction: Bool = false,
    compactionSummary: String? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.isStreaming = isStreaming
    self.error = error
    self.tools = tools
    self.steps = steps
    self.attachments = attachments
    self.siblingIndex = siblingIndex
    self.siblingCount = siblingCount
    self.details = details
    self.isCompaction = isCompaction
    self.compactionSummary = compactionSummary
  }
}

/// Chinese step labels + SF Symbols, mirroring `src/lib/chat/steps.ts`
/// and the `steps.*` keys in `messages/zh-CN.json`.
enum StepDescriber {
  static func describe(toolName: String, input: [String: Any]?, running: Bool) -> (label: String, icon: String) {
    let name = toolName.lowercased()

    if name.isEmpty || name == "unknown" {
      return (running ? "正在处理…" : "使用了工具", "wrench.and.screwdriver")
    }

    if name.hasPrefix("mcp__") {
      let parts = toolName.dropFirst(5).components(separatedBy: "__")
      let server = titleCase(parts.first ?? "")
      let action = parts.count > 1 ? titleCase(parts[1]) : ""
      let label = action.isEmpty ? server : "\(server) · \(action)"
      return (running ? "\(server)…" : label, "app.connected.to.app.below.fill")
    }

    let file = basename(input?["path"] as? String)

    switch name {
    case "write_file":
      if let file { return (running ? "创建 \(file)..." : "创建 \(file)", "doc.badge.plus") }
      return (running ? "创建文件..." : "创建了一个文件", "doc.badge.plus")
    case "str_replace", "edit_file":
      if let file { return (running ? "正在编辑 \(file)..." : "编辑 \(file)", "square.and.pencil") }
      return (running ? "编辑文件..." : "编辑了一个文件", "square.and.pencil")
    case "read_file":
      if let file { return (running ? "正在读取 \(file)..." : "读取 \(file)", "doc.text") }
      return (running ? "正在读取文件..." : "读取文件", "doc.text")
    case "view_file":
      if let file { return (running ? "正在查看 \(file)..." : "已浏览 \(file)", "eye") }
      return (running ? "查看文件..." : "查看了一个文件", "eye")
    case "list_files":
      return (running ? "正在浏览文件…" : "已列出文件", "folder")
    case "search_files":
      if let q = clip(input?["pattern"] as? String, 32), !running {
        return ("搜索了“\(q)”", "magnifyingglass")
      }
      return (running ? "正在搜索文件…" : "已搜索文件", "magnifyingglass")
    case "check_job":
      return (running ? "正在检查后台任务…" : "已检查后台任务", "terminal")
    case "execute_bash":
      let background = (input?["background"] as? Bool) ?? false
      if background { return (running ? "正在启动后台任务…" : "已启动后台任务", "terminal") }
      return (running ? "正在运行命令…" : "运行了命令", "terminal")
    case "execute_python":
      return (running ? "正在运行 Python…" : "运行了 Python", "chevron.left.forwardslash.chevron.right")
    case "execute_node":
      return (running ? "正在运行 JavaScript…" : "运行了 JavaScript", "chevron.left.forwardslash.chevron.right")
    case "skill", "use_skill":
      if let skill = input?["name"] as? String, !skill.isEmpty {
        return (running ? "正在加载技能“\(skill)”…" : "技能“\(skill)”", "sparkles")
      }
      return (running ? "正在加载技能…" : "使用了技能", "sparkles")
    default:
      break
    }

    if name.contains("web") || name.contains("search") || name.contains("google")
      || name.contains("brave") || name.contains("tavily") {
      let query = clip((input?["query"] as? String) ?? (input?["q"] as? String), 40)
      if let query, !running { return ("在网上搜索了“\(query)”", "globe") }
      return (running ? "正在搜索网页…" : "已搜索网页", "globe")
    }
    if name.contains("fetch") || name.contains("http") || name.contains("url")
      || name.contains("browse") || name.contains("scrape") {
      return (running ? "正在获取页面…" : "已获取页面", "globe")
    }

    let pretty = titleCase(toolName)
    return (running ? "\(pretty)…" : pretty, "wrench.and.screwdriver")
  }

  private static func basename(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    return path.components(separatedBy: "/").last(where: { !$0.isEmpty })
  }

  private static func clip(_ value: String?, _ limit: Int) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
  }

  private static func titleCase(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }
}

extension ISO8601DateFormatter {
  static let capkaFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  static let capkaPlain = ISO8601DateFormatter()
}

struct ProviderConfig: Identifiable, Equatable {
  var id: String
  var provider: String
  var label: String?
  var defaultModel: String?
  var baseUrl: String?
  var isActive: Bool
  var shared: Bool
  var apiStyle: String?

  var displayName: String {
    if let label, !label.isEmpty { return label }
    return provider
  }
}

/// What the add-connection form needs to know about each provider. Mirrors the
/// fields of `PROVIDER_META` in `src/lib/providers/registry.ts` that the form
/// actually reads — same order, same defaults, so the two forms agree.
struct ProviderOption: Identifiable, Equatable {
  var id: String
  var label: String
  var requiresKey: Bool
  var requiresBaseUrl: Bool
  /// Base URL is offered but may be left empty (provider has its own default).
  var optionalBaseUrl: Bool = false
  var defaultBaseUrl: String?

  var showsBaseUrl: Bool { requiresBaseUrl || optionalBaseUrl || defaultBaseUrl != nil }

  static let all: [ProviderOption] = [
    ProviderOption(id: "litellm", label: "OpenAI 兼容端点", requiresKey: true, requiresBaseUrl: true),
    ProviderOption(id: "openrouter", label: "OpenRouter", requiresKey: true, requiresBaseUrl: false),
    ProviderOption(id: "openai", label: "OpenAI", requiresKey: true, requiresBaseUrl: false),
    ProviderOption(id: "azure", label: "Azure OpenAI", requiresKey: true, requiresBaseUrl: true),
    ProviderOption(id: "anthropic", label: "Anthropic", requiresKey: true, requiresBaseUrl: false, optionalBaseUrl: true),
    ProviderOption(id: "google", label: "Google Gemini", requiresKey: true, requiresBaseUrl: false),
    ProviderOption(id: "vertex", label: "Google Vertex AI", requiresKey: true, requiresBaseUrl: false, optionalBaseUrl: true),
    ProviderOption(id: "bedrock", label: "Amazon Bedrock", requiresKey: true, requiresBaseUrl: true, defaultBaseUrl: "us-east-1"),
    ProviderOption(id: "deepseek", label: "DeepSeek", requiresKey: true, requiresBaseUrl: false, defaultBaseUrl: "https://api.deepseek.com/v1"),
    ProviderOption(id: "mistral", label: "Mistral", requiresKey: true, requiresBaseUrl: false, defaultBaseUrl: "https://api.mistral.ai/v1"),
    ProviderOption(id: "xai", label: "xAI (Grok)", requiresKey: true, requiresBaseUrl: false, defaultBaseUrl: "https://api.x.ai/v1"),
    ProviderOption(id: "groq", label: "Groq", requiresKey: true, requiresBaseUrl: false, defaultBaseUrl: "https://api.groq.com/openai/v1"),
    ProviderOption(id: "zhipu", label: "Z.AI (GLM)", requiresKey: true, requiresBaseUrl: false, defaultBaseUrl: "https://api.z.ai/api/paas/v4"),
    ProviderOption(id: "ollama", label: "Ollama（本地）", requiresKey: false, requiresBaseUrl: true, defaultBaseUrl: "http://localhost:11434/api"),
  ]

  static func of(_ id: String) -> ProviderOption? { all.first { $0.id == id } }
}

struct AdminUserRow: Identifiable, Equatable {
  var id: String
  var name: String
  var email: String?
  var role: String
  var status: String
  var cost30d: Double?
}

struct AdminUsageSummary: Equatable {
  var days: Int
  var cost: Double
  var inputTokens: Int
  var outputTokens: Int
  var calls: Int
  var activeMembers: Int?
}

struct AdminUpdatesInfo: Equatable {
  var current: String?
  var latest: String?
  var updateAvailable: Bool
  var releaseName: String?
  var notes: String?
  var error: String?
}

struct AuditEntry: Identifiable, Equatable {
  var id: String
  var actorName: String?
  var action: String
  var targetType: String?
  var targetKey: String?
  var createdAt: String?
}

struct AuthConfigInfo: Equatable {
  var registrationMode: String?
  var emailSignupEnabled: Bool
  var feishuReady: Bool
  var feishuEnabled: Bool
  var telegramReady: Bool
  var telegramEnabled: Bool
}

struct SandboxCapabilities: Equatable {
  /// `nil` means the controller did not report a value.
  var allowNetwork: Bool?
}

/// The instance-wide agent ceiling (`/api/settings/agent-profile`). Mirrors
/// `agentProfileSchema` in `src/lib/agents/profile.ts`: every field has a
/// default, so any stored shape parses into a complete profile. It only ever
/// restricts — a project asking for more still gets clamped to this.
struct AgentProfile: Equatable {
  var sandbox = true
  var connectors = true
  var skills = true
  var manage = true
  var memory = true
  /// "append" keeps Capka's persona above project instructions; "replace" drops it.
  var persona = "append"
  var sessionContext = true

  static func parse(_ root: [String: Any]) -> AgentProfile {
    let caps = root["capabilities"] as? [String: Any] ?? [:]
    var profile = AgentProfile()
    profile.sandbox = boolValue(caps["sandbox"]) ?? true
    profile.connectors = boolValue(caps["connectors"]) ?? true
    profile.skills = boolValue(caps["skills"]) ?? true
    profile.manage = boolValue(caps["manage"]) ?? true
    profile.memory = boolValue(caps["memory"]) ?? true
    profile.persona = (root["persona"] as? String) ?? "append"
    profile.sessionContext = boolValue(root["sessionContext"]) ?? true
    return profile
  }

  var payload: [String: Any] {
    [
      "capabilities": [
        "sandbox": sandbox,
        "connectors": connectors,
        "skills": skills,
        "manage": manage,
        "memory": memory,
      ],
      "persona": persona,
      "sessionContext": sessionContext,
    ]
  }
}

/// One governance rule from `/api/admin/policies`. The mobile page only edits
/// system-scope rules; user- and project-scoped ones are shown but read-only,
/// because picking their subject needs the web's pickers.
struct PolicyRow: Identifiable, Equatable {
  var id: String
  var capabilityType: String
  var capabilityKey: String
  /// allow / deny / ask
  var effect: String
  /// system / user / project
  var scope: String

  var scopeLabel: String {
    switch scope {
    case "user": return "按用户"
    case "project": return "按项目"
    default: return "全实例"
    }
  }

  var effectLabel: String {
    switch effect {
    case "allow": return "允许"
    case "deny": return "拒绝"
    default: return "每次询问"
    }
  }

  var typeLabel: String {
    capabilityType == "connector" ? "连接器" : "技能"
  }
}

private func boolValue(_ any: Any?) -> Bool? {
  if any == nil || any is NSNull { return nil }
  if let b = any as? Bool { return b }
  if let i = any as? Int { return i != 0 }
  if let s = any as? String {
    switch s.lowercased() {
    case "true", "t", "1", "yes": return true
    case "false", "f", "0", "no": return false
    default: return nil
    }
  }
  return nil
}

private func stringValue(_ any: Any?) -> String? {
  if let s = any as? String { return s }
  if let n = any as? NSNumber { return n.stringValue }
  return nil
}

private func intValue(_ any: Any?) -> Int? {
  if let i = any as? Int { return i }
  if let d = any as? Double { return Int(d) }
  if let n = any as? NSNumber { return n.intValue }
  return nil
}
