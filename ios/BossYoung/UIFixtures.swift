import Foundation

/// Screenshot harness: seeds the shell with representative data so the native
/// UI can be reviewed without a reachable server. Off unless the process is
/// launched with `CAPKA_UI_FIXTURES=1`.
@MainActor
enum CapkaFixtures {
  static var isEnabled: Bool {
    #if DEBUG
      return ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES"] == "1"
    #else
      return false
    #endif
  }

  /// `CAPKA_UI_FIXTURES_ADMIN=1` seeds an admin so the admin-only settings pages
  /// are reachable in the harness.
  private static var isAdminFixture: Bool {
    ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES_ADMIN"] == "1"
  }

  static func seed(session: SessionStore) {
    session.user = CapkaUser(
      id: "u_1",
      name: "韩欣",
      email: "hanxin@boss-young.com",
      role: isAdminFixture ? "admin" : "user"
    )
    session.isRestoring = false
  }

  static func seed(chat: ChatViewModel, list: ChatListViewModel) {
    chat.models = models
    chat.selectedModelId = "claude-sonnet-4-6"
    list.chats = chats
    if ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES_HOME"] == "1" { return }
    chat.chatId = "c_1"
    chat.title = "股权转让协议审查"
    chat.messages =
      ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES_SCREEN"] == "chattail"
      ? tailMessages
      : messages
  }

  /// Blocks the main transcript scrolls past: a table, fenced code, a compaction
  /// marker, a failed step with an error notice, and a live streaming row.
  private static var tailMessages: [ChatUIMessage] {
    [
      ChatUIMessage(
        id: "t_1",
        role: "assistant",
        text: """
        对照表已经生成，保存为 `条款风险对照表.xlsx`：

        | 条款 | 风险等级 | 建议改法 |
        | --- | --- | --- |
        | 3.2 | 高 | 明确"交割日后 30 日"为自然日 |
        | 8.1 | 高 | 增加转让方逾期交割的对等违约金 |
        | 11.4 | 中 | 补充争议解决地为上海 |

        待办：

        - [x] 通读全文并定位付款条款
        - [x] 生成风险对照表
        - [ ] 出具 Word 版修改稿

        校验命令（可自行复跑）：

        ```bash
        soffice --headless --convert-to pdf 条款风险对照表.xlsx
        ```

        参考条文见 [《公司法》第七十一条](https://example.com/company-law-71)。

        ---

        需要我把它也做成 Word 版吗？
        """,
        isStreaming: false,
        details: MessageDetails(
          model: "Claude Sonnet 4.6",
          inputTokens: 18_420,
          outputTokens: 1_260,
          durationMs: 42_800,
          stepCount: 3,
          createdAt: Date().addingTimeInterval(-600),
          contextTokens: 158_000,
          contextWindow: 200_000
        )
      ),
      ChatUIMessage(id: "t_2", role: "assistant", text: "", isStreaming: false, isCompaction: true),
      ChatUIMessage(
        id: "t_3",
        role: "assistant",
        text: "转 PDF 时沙箱里的字体缺失，我换成内置中文字体重试。",
        isStreaming: false,
        error: "LibreOffice 转换失败：找不到字体 SimSun，已回退到 Noto Sans CJK。",
        steps: [
          MessageStep(
            id: "t_s1",
            kind: .tool,
            state: .failed,
            label: "运行了命令",
            icon: "terminal",
            detail: "soffice --convert-to pdf 条款风险对照表.xlsx\nError: no suitable font found"
          )
        ],
        details: MessageDetails(
          model: "Claude Sonnet 4.6",
          contextTokens: 176_000,
          contextWindow: 200_000
        )
      ),
      ChatUIMessage(
        id: "t_4",
        role: "assistant",
        text: "",
        isStreaming: true,
        steps: [
          MessageStep(
            id: "t_s2",
            kind: .tool,
            state: .running,
            label: "正在运行命令…",
            icon: "terminal",
            detail: nil
          )
        ]
      ),
    ]
  }

  static func seed(settings: SettingsViewModel) {
    settings.skills = [
      SkillInfo(
        id: "sk_contract",
        name: "合同审查",
        description: "按事务所模板逐条比对，标出偏离与风险等级。",
        enabled: true,
        scope: "org",
        mine: false
      ),
      SkillInfo(
        id: "sk_minutes",
        name: "会议纪要",
        description: "把录音或速记整理成正式纪要，附待办清单。",
        enabled: true,
        scope: "personal",
        mine: true
      ),
      SkillInfo(
        id: "sk_xlsx",
        name: "表格分析",
        description: "清洗数据、做透视与图表。",
        enabled: false,
        scope: "org",
        mine: false
      ),
    ]
    settings.connectors = [
      ConnectorInfo(
        id: "mcp_lark",
        name: "飞书",
        url: "https://open.feishu.cn/mcp",
        enabled: true,
        scope: "org",
        authKind: "oauth"
      ),
      ConnectorInfo(
        id: "mcp_search",
        name: "网页搜索",
        url: "https://search.internal/mcp",
        enabled: false,
        scope: "org",
        authKind: "none"
      ),
    ]
    settings.automations = [
      AutomationInfo(
        id: "au_1",
        title: "每周一早上汇总上周会议纪要",
        enabled: true,
        nextRunAt: iso(-60 * 20),
        lastRunAt: iso(60 * 24 * 7),
        lastChatId: "c_2"
      ),
      AutomationInfo(
        id: "au_2",
        title: "月底提醒整理差旅报销",
        enabled: false,
        nextRunAt: nil,
        lastRunAt: iso(60 * 24 * 30),
        lastChatId: nil
      ),
    ]
    settings.memory = "我是公司法组的律师，常做并购与股权交易。回复用中文，先给结论再给理由。"
    settings.plugins = [
      PluginInfo(id: "pl_1", name: "合同模板包", description: "常用并购与股权协议模板。", enabled: true, author: "事务所定制"),
    ]
    settings.billing = BillingInfo(
      onSharedKey: true,
      ownKeysAllowed: true,
      tierName: "标准",
      windows: [
        BillingWindow(window: "h5", pct: 22, limit: 100),
        BillingWindow(window: "d7", pct: 48, limit: 500),
        BillingWindow(window: "d30", pct: 61, limit: 2000),
      ],
      blocked: false
    )
    settings.providers = [
      ProviderConfig(
        id: "prov_1",
        provider: "anthropic",
        label: "Anthropic",
        defaultModel: "claude-sonnet-4-5",
        baseUrl: nil,
        isActive: true,
        shared: true,
        apiStyle: "anthropic"
      )
    ]
    settings.telegram = TelegramLinkInfo(linked: false, username: nil, botUsername: "capka_bot", linkedAt: nil)
    settings.locale = "zh-CN"

    guard isAdminFixture else { return }
    settings.sandbox = SandboxCapabilities(allowNetwork: true)
    settings.sandboxNetworkSetting = "bridge"
    settings.hostFolderAccess = false
    settings.pcFolderAccess = "admins"
    settings.agentAutonomy = "supervised"
    settings.blockPrivateProviderURLs = true
    settings.agentProfile = AgentProfile(
      sandbox: true,
      connectors: true,
      skills: true,
      manage: true,
      memory: false,
      persona: "append",
      sessionContext: true
    )
    settings.policies = [
      PolicyRow(id: "po_1", capabilityType: "connector", capabilityKey: "网页搜索", effect: "deny", scope: "system"),
      PolicyRow(id: "po_2", capabilityType: "skill", capabilityKey: "合同审查", effect: "ask", scope: "system"),
      PolicyRow(id: "po_3", capabilityType: "connector", capabilityKey: "飞书", effect: "allow", scope: "project"),
    ]
    settings.adminKeyMode = "shared_plus_own"
    settings.adminMonthlyBudget = 500
    settings.adminUsage = AdminUsageSummary(
      days: 30,
      cost: 42.1875,
      inputTokens: 3_182_004,
      outputTokens: 214_880,
      calls: 1_264,
      activeMembers: 18
    )
    settings.adminUsers = [
      AdminUserRow(id: "u_1", name: "韩欣", email: "hanxin@boss-young.com", role: "admin", status: "active", cost30d: 12.4),
      AdminUserRow(id: "u_2", name: "李闻", email: "liwen@boss-young.com", role: "user", status: "pending", cost30d: nil),
    ]
    settings.authConfig = AuthConfigInfo(
      registrationMode: "approval",
      emailSignupEnabled: true,
      feishuReady: true,
      feishuEnabled: true,
      telegramReady: false,
      telegramEnabled: false
    )
    settings.updates = AdminUpdatesInfo(
      current: "0.14.0",
      latest: "0.14.0",
      updateAvailable: false,
      releaseName: nil,
      notes: nil,
      error: nil
    )
    settings.audit = [
      AuditEntry(id: "a_1", actorName: "韩欣", action: "policy.set", targetType: "connector", targetKey: "网页搜索", createdAt: iso(30)),
      AuditEntry(id: "a_2", actorName: "系统", action: "user.approve", targetType: "user", targetKey: "liwen@boss-young.com", createdAt: iso(60 * 26)),
    ]
  }

  static func seed(projects: ProjectsViewModel) {
    projects.projects = [
      ProjectSummary(
        id: "p_1",
        name: "海德并购",
        description: "海德科技 60% 股权收购，尽调与交易文件。",
        systemPrompt: "涉及本项目时，默认按买方立场审查。",
        defaultModel: nil,
        sandboxNetwork: false,
        chatCount: 7,
        lastChatAt: iso(12)
      ),
      ProjectSummary(
        id: "p_2",
        name: "常年顾问 · 明远",
        description: nil,
        systemPrompt: nil,
        defaultModel: nil,
        sandboxNetwork: false,
        chatCount: 2,
        lastChatAt: iso(60 * 24 * 9)
      ),
    ]
  }

  static func seed(workspace: WorkspaceViewModel) {
    workspace.entries = [
      WorkspaceEntry(name: "尽调材料", path: "尽调材料", isDirectory: true, size: nil),
      WorkspaceEntry(name: "输出", path: "输出", isDirectory: true, size: nil),
      WorkspaceEntry(
        name: "股权转让协议（第三稿）.docx",
        path: "股权转让协议（第三稿）.docx",
        isDirectory: false,
        size: 148_320
      ),
      WorkspaceEntry(
        name: "条款风险对照表.xlsx",
        path: "条款风险对照表.xlsx",
        isDirectory: false,
        size: 20_480
      ),
      WorkspaceEntry(name: "notes.md", path: "notes.md", isDirectory: false, size: 1_204),
    ]
  }

  private static func iso(_ minutesAgo: Int) -> String {
    ISO8601DateFormatter.capkaPlain.string(
      from: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo))
    )
  }

  private static var models: [ModelInfo] {
    [
      ModelInfo(
        id: "claude-sonnet-4-6",
        name: "Claude Sonnet 4.6",
        provider: "anthropic",
        group: "Anthropic",
        featured: true,
        context: 200_000,
        vision: true,
        reasoning: true
      ),
      ModelInfo(
        id: "deepseek-v3",
        name: "DeepSeek V3",
        provider: "deepseek",
        group: "DeepSeek",
        featured: false,
        context: 128_000,
        vision: false,
        reasoning: false
      ),
    ]
  }

  private static var chats: [ChatSummary] {
    [
      ChatSummary(
        id: "c_1",
        title: "股权转让协议审查",
        pinned: true,
        archived: false,
        updatedAt: iso(12),
        unread: false,
        running: false,
        projectName: "海德并购",
        projectId: "p_1"
      ),
      ChatSummary(
        id: "c_2",
        title: "整理上周的会议纪要",
        pinned: false,
        archived: false,
        updatedAt: iso(90),
        unread: true,
        running: true,
        projectName: nil,
        projectId: nil
      ),
      ChatSummary(
        id: "c_3",
        title: "把差旅报销表拆成按部门汇总",
        pinned: false,
        archived: false,
        updatedAt: iso(60 * 26),
        unread: false,
        running: false,
        projectName: nil,
        projectId: nil
      ),
      ChatSummary(
        id: "c_4",
        title: "翻译 NDA 第 7 条并标注风险",
        pinned: false,
        archived: false,
        updatedAt: iso(60 * 24 * 4),
        unread: false,
        running: false,
        projectName: "海德并购",
        projectId: "p_1"
      ),
    ]
  }

  private static var messages: [ChatUIMessage] {
    [
      ChatUIMessage(
        id: "m_1",
        role: "user",
        text: "帮我看看这份股权转让协议，重点是付款节奏和违约责任，有问题的地方列出来。",
        isStreaming: false,
        attachments: [
          MessageAttachment(name: "股权转让协议（第三稿）.docx", type: "application/msword")
        ]
      ),
      ChatUIMessage(
        id: "m_2",
        role: "assistant",
        text: """
        我读完了协议全文，有 **三处** 需要你先确认：

        ## 付款节奏
        1. 第 3.2 条约定首期款在"交割日后 30 个工作日内"支付，但第 3.1 条把交割日定义为"工商变更完成日"——两者叠加后最长可能拖到 3 个月。
        2. 尾款 20% 没有约定最晚支付时点。

        ## 违约责任
        - 第 8.1 条只约定了受让方逾期付款的违约金（日万分之三），转让方一侧没有对应条款，责任明显不对等。

        > 建议把尾款支付与"目标公司完成审计"解绑，改为固定日期。

        下面是我整理后的对照表，已经存到工作区：

        ```
        条款   风险等级   建议改法
        3.2    高        明确"交割日后 30 日"为自然日
        8.1    高        增加转让方逾期交割的对等违约金
        ```
        """,
        isStreaming: false,
        steps: [
          MessageStep(
            id: "s_1",
            kind: .tool,
            state: .done,
            label: "读取 股权转让协议（第三稿）.docx",
            icon: "doc.text",
            detail: nil
          ),
          MessageStep(
            id: "s_2",
            kind: .reasoning,
            state: .done,
            label: "思考过程",
            icon: "brain",
            detail: "先定位付款与违约条款，再检查双方责任是否对等。"
          ),
          MessageStep(
            id: "s_3",
            kind: .tool,
            state: .done,
            label: "创建 条款风险对照表.xlsx",
            icon: "doc.badge.plus",
            detail: nil
          ),
        ],
        details: MessageDetails(
          model: "Claude Sonnet 4.6",
          inputTokens: 18_420,
          outputTokens: 1_260,
          durationMs: 42_800,
          stepCount: 3,
          createdAt: Date().addingTimeInterval(-720),
          contextTokens: 124_000,
          contextWindow: 200_000
        )
      ),
      ChatUIMessage(
        id: "m_3",
        role: "user",
        text: "把对照表导出成 PDF 发我。",
        isStreaming: false
      ),
      ChatUIMessage(
        id: "m_4",
        role: "assistant",
        text: "正在把表格转成 PDF……",
        isStreaming: true,
        steps: [
          MessageStep(
            id: "s_4",
            kind: .tool,
            state: .done,
            label: "读取 条款风险对照表.xlsx",
            icon: "doc.text",
            detail: nil
          ),
          MessageStep(
            id: "s_5",
            kind: .tool,
            state: .running,
            label: "正在运行命令…",
            icon: "terminal",
            detail: nil
          ),
        ],
        details: MessageDetails(
          model: "Claude Sonnet 4.6",
          contextTokens: 131_000,
          contextWindow: 200_000
        )
      ),
    ]
  }
}
