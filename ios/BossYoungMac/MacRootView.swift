import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Mac window: a permanent sidebar beside the conversation.
///
/// Everything inside the two columns is the code the web and the phone already
/// agree on — `SidebarView` is the same web-mirroring drawer the iOS client
/// shows, `LoginView` the same sign-in composition, `CapkaMessageRow` the same
/// transcript, `ModelPickerSheet` the same searchable model list. What is Mac
/// about this file is only the shell: a split view instead of a swipe-open
/// drawer, and a composer that sends on ↩ because the window is wide.
struct MacRootView: View {
  static let newChatNotification = Notification.Name("capka.mac.newChat")

  @Environment(SessionStore.self) private var session
  @Environment(\.openSettings) private var openSettings

  @State private var chat = ChatViewModel()
  @State private var list = ChatListViewModel()
  @State private var preview = FilePreviewLoader()
  @State private var columns = NavigationSplitViewVisibility.all

  @State private var showImporter = false
  @State private var showModelPicker = false
  @State private var showProjectPicker = false
  @State private var showProjects = false
  @State private var showArchived = false
  @State private var showFiles = false
  @State private var filesProject: ProjectSummary?
  @State private var renameTarget: ChatSummary?
  @State private var renameText = ""
  @State private var moveTarget: ChatSummary?
  @State private var moveProjects: [ProjectSummary] = []
  @State private var shareTarget: ChatSummary?
  @State private var starterType = "pdf"
  @State private var follow = true
  @FocusState private var composerFocused: Bool

  private var isAdmin: Bool { session.user?.role == "admin" }

  var body: some View {
    Group {
      if CapkaFixtures.isEnabled {
        // Same harness the iOS shell uses (`CAPKA_UI_FIXTURES=1`): representative
        // data so the layout can be reviewed without a reachable server.
        shell.task { CapkaFixtures.seed(session: session) }
      } else if session.isRestoring {
        ProgressView()
          .tint(Brand.primary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Brand.cream)
      } else if session.isAuthenticated {
        shell
      } else {
        LoginView()
      }
    }
  }

  // MARK: - Shell

  private var shell: some View {
    NavigationSplitView(columnVisibility: $columns) {
      SidebarView(
        list: list,
        currentChatId: chat.chatId,
        onNewChat: {
          chat.startNewChat()
          composerFocused = true
        },
        onOpenChat: { row in
          Task { await chat.openChat(row.id, projectId: row.projectId, projectName: row.projectName) }
        },
        onOpenProjects: { showProjects = true },
        onOpenArchived: { showArchived = true },
        onOpenSettings: { openSettings() },
        onClose: { columns = columns == .detailOnly ? .all : .detailOnly },
        onRename: { row in
          renameText = row.title ?? ""
          renameTarget = row
        },
        onMove: { row in
          moveTarget = row
          Task { moveProjects = (try? await CapkaAPIClient.shared.listProjects()) ?? [] }
        },
        onShare: { row in shareTarget = row },
        onExport: { row in
          Task {
            do {
              let url = try await CapkaAPIClient.shared.exportChatMarkdown(
                chatId: row.id,
                title: row.title
              )
              NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
              list.error = "导出失败：\(error.localizedDescription)"
            }
          }
        }
      )
      .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      detail
    }
    .navigationSplitViewStyle(.balanced)
    .task {
      chat.bind(session: session)
      list.bind(session: session)
      if CapkaFixtures.isEnabled {
        CapkaFixtures.seed(chat: chat, list: list)
        return
      }
      await chat.load()
      await chat.flushOutbox()
      await list.refreshQuietly()
    }
    .onChange(of: session.eventSeq) { _, _ in
      guard let event = session.lastEvent else { return }
      chat.applyEvent(event)
      list.applyEvent(event)
    }
    .onReceive(NotificationCenter.default.publisher(for: Self.newChatNotification)) { _ in
      chat.startNewChat()
      composerFocused = true
    }
    .sheet(isPresented: $showProjects) {
      macSheet(width: 640, height: 640) {
        ProjectsListView { id in
          showProjects = false
          Task { await chat.openChat(id) }
        }
      } onClose: {
        showProjects = false
      }
    }
    .sheet(isPresented: $showArchived) {
      macSheet(width: 560, height: 600) {
        ArchivedChatsView { id in
          showArchived = false
          Task { await chat.openChat(id) }
        }
      } onClose: {
        showArchived = false
      }
    }
    .sheet(item: $filesProject) { project in
      macSheet(width: 640, height: 640) {
        WorkspaceFilesView(chatId: nil, projectId: project.id, title: project.name)
      } onClose: {
        filesProject = nil
      }
    }
    .sheet(isPresented: $showFiles) {
      macSheet(width: 640, height: 640) {
        WorkspaceFilesView(chatId: chat.chatId, projectId: chat.projectId, title: "工作区")
      } onClose: {
        showFiles = false
      }
    }
    .sheet(isPresented: $showModelPicker) {
      ModelPickerSheet(
        models: chat.models,
        selectedId: chat.selectedModelId,
        onSelect: { id in
          chat.selectedModelId = id
          showModelPicker = false
        },
        onClose: { showModelPicker = false }
      )
      .frame(width: 520, height: 600)
    }
    .sheet(isPresented: $showProjectPicker) {
      ProjectContextSheet(
        currentId: chat.projectId,
        currentName: chat.projectName,
        onSelect: { project in
          // Switching context can't retag an existing sandbox, so it starts a
          // fresh chat — same rule the phone and the web follow.
          if chat.chatId != nil { chat.startNewChat() }
          chat.selectProject(project)
          showProjectPicker = false
        },
        onOpenFiles: { project in
          showProjectPicker = false
          filesProject = project
        },
        onOpenChat: { id in
          showProjectPicker = false
          Task { await chat.openChat(id, projectId: chat.projectId, projectName: chat.projectName) }
        },
        onClose: { showProjectPicker = false }
      )
      .frame(width: 520, height: 600)
    }
    .alert("重命名", isPresented: Binding(
      get: { renameTarget != nil },
      set: { if !$0 { renameTarget = nil } }
    )) {
      TextField("标题", text: $renameText)
      Button("保存") {
        if let id = renameTarget?.id {
          Task {
            await list.rename(chatId: id, title: renameText)
            await list.refreshQuietly()
          }
        }
        renameTarget = nil
      }
      Button("取消", role: .cancel) { renameTarget = nil }
    }
    .sheet(item: $shareTarget) { row in
      ChatShareSheet(chat: row) { updated in
        if let idx = list.chats.firstIndex(where: { $0.id == updated.id }) {
          list.chats[idx] = updated
        }
      }
      .frame(width: 420, height: 480)
    }
    .confirmationDialog("移至项目", isPresented: Binding(
      get: { moveTarget != nil },
      set: { if !$0 { moveTarget = nil } }
    ), titleVisibility: .visible) {
      ForEach(moveProjects) { project in
        Button(project.name) {
          if let id = moveTarget?.id {
            Task {
              await list.moveToProject(chatId: id, projectId: project.id)
              await list.refreshQuietly()
            }
          }
          moveTarget = nil
        }
      }
      Button("移出项目") {
        if let id = moveTarget?.id {
          Task {
            await list.moveToProject(chatId: id, projectId: nil)
            await list.refreshQuietly()
          }
        }
        moveTarget = nil
      }
      Button("取消", role: .cancel) { moveTarget = nil }
    }
    .alert("出错了", isPresented: Binding(
      get: { chat.error != nil || list.error != nil },
      set: { if !$0 { chat.error = nil; list.error = nil } }
    )) {
      Button("好", role: .cancel) { chat.error = nil; list.error = nil }
    } message: {
      Text(chat.error ?? list.error ?? "")
    }
  }

  /// Sheets on a Mac need an explicit size and a way out — a phone's sheet has a
  /// drag indicator, this has a 完成 button.
  private func macSheet<Content: View>(
    width: CGFloat,
    height: CGFloat,
    @ViewBuilder content: () -> Content,
    onClose: @escaping () -> Void
  ) -> some View {
    NavigationStack {
      content()
        .toolbar {
          ToolbarItem(placement: .capkaTrailing) {
            Button("完成", action: onClose).foregroundStyle(Brand.primary)
          }
        }
    }
    .frame(width: width, height: height)
  }

  // MARK: - Detail

  @ViewBuilder
  private var detail: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
        if chat.isEmptyChat {
          home
        } else {
          messageList
          composer
        }
      }
    }
    .filePreview(preview)
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      guard case .success(let urls) = result else { return }
      Task { for url in urls { await chat.attach(fileURL: url) } }
    }
  }

  /// The web's floating header: sidebar toggle, model chip, workspace, new chat.
  private var topBar: some View {
    HStack(spacing: 8) {
      toolButton("sidebar.leading", help: "显示或隐藏侧边栏") {
        withAnimation(Motion.easeOut(0.22)) {
          columns = columns == .detailOnly ? .all : .detailOnly
        }
      }

      if !chat.isEmptyChat {
        modelChip
      }

      Spacer(minLength: 4)

      if !chat.isEmptyChat {
        toolButton("folder", help: "工作区文件") { showFiles = true }
      }
      toolButton("square.and.pencil", help: "新聊天（⌘N）") {
        chat.startNewChat()
        composerFocused = true
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  private func toolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Brand.ink.opacity(0.75))
        .frame(width: 30, height: 30)
        .background(Brand.card)
        .clipShape(Circle())
        .overlay(Circle().stroke(Brand.line, lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var modelChip: some View {
    Button { showModelPicker = true } label: {
      HStack(spacing: 6) {
        if let model = chat.models.first(where: { $0.id == chat.selectedModelId }) {
          ProviderIconView(slug: model.iconSlug, size: 14)
        }
        Text(currentModelName)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
      }
      .foregroundStyle(Brand.ink.opacity(0.8))
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .capkaCard(radius: 999)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("选择型号")
  }

  private var currentModelName: String {
    chat.models.first { $0.id == chat.selectedModelId }?.name ?? "选择型号"
  }

  // MARK: - Home

  /// Same composition as the web's empty `/chat`: wordmark, composer, model
  /// chip, then recents and the file-type starters.
  private var home: some View {
    ScrollView {
      VStack(spacing: 0) {
        Spacer(minLength: 40)

        Image("BrandWordmark")
          .resizable()
          .scaledToFit()
          .frame(height: 44)
          .frame(maxWidth: 220)
          .padding(.bottom, 30)
          .capkaEntrance(.blurRise)

        composerCard(homeStyle: true)
          .capkaEntrance(.blurRise, delay: 0.06)

        Button { showModelPicker = true } label: {
          HStack(spacing: 6) {
            if let model = chat.models.first(where: { $0.id == chat.selectedModelId }) {
              ProviderIconView(slug: model.iconSlug, size: 13)
            }
            if chat.models.first(where: { $0.id == chat.selectedModelId })?.featured == true {
              Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(Brand.burgundy)
            }
            Text(currentModelName)
              .font(.system(size: 13, weight: .medium))
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .semibold))
          }
          .foregroundStyle(Brand.ink.opacity(0.8))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .capkaCard(radius: 999)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)

        homeSuggestions
          .padding(.top, 32)
          .capkaEntrance(.blurRise, delay: 0.12)

        Spacer(minLength: 48)
      }
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 24)
    }
  }

  private var homeSuggestions: some View {
    VStack(alignment: .leading, spacing: 22) {
      if !list.chats.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("最近")
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
            .padding(.horizontal, 4)

          VStack(spacing: 0) {
            let recents = Array(list.chats.prefix(4))
            ForEach(Array(recents.enumerated()), id: \.element.id) { index, row in
              Button {
                Task { await chat.openChat(row.id, projectId: row.projectId, projectName: row.projectName) }
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                  Text(row.title?.isEmpty == false ? row.title! : "新聊天")
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                  Spacer(minLength: 10)
                  if let date = row.updatedAtDate {
                    Text(Self.shortDate.string(from: date))
                      .font(.system(size: 12))
                      .foregroundStyle(Brand.muted)
                  }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
              }
              .buttonStyle(CapkaPressStyle())

              if index < recents.count - 1 {
                Divider().overlay(Brand.line)
              }
            }
          }
          .capkaCard()
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Text("开始工作")
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
          ForEach(HomeStarters.all, id: \.id) { group in
            Button { starterType = group.id } label: {
              Text(group.title)
                .font(.system(size: 12))
                .foregroundStyle(starterType == group.id ? Brand.ink : Brand.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(starterType == group.id ? Brand.accent : .clear)
                .clipShape(Capsule())
                .overlay(
                  Capsule().stroke(
                    starterType == group.id ? Brand.ink.opacity(0.2) : .clear,
                    lineWidth: 1
                  )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)

        let actions = HomeStarters.all.first { $0.id == starterType }?.actions ?? []
        VStack(spacing: 0) {
          ForEach(Array(actions.enumerated()), id: \.element.label) { index, action in
            Button {
              chat.draft = action.prompt
              composerFocused = true
            } label: {
              HStack(spacing: 12) {
                Image(systemName: action.icon)
                  .font(.system(size: 14))
                  .foregroundStyle(Brand.muted)
                  .frame(width: 18)
                Text(action.label)
                  .font(.system(size: 14))
                  .foregroundStyle(Brand.ink)
                Spacer(minLength: 8)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 11)
              .contentShape(Rectangle())
            }
            .buttonStyle(CapkaPressStyle())

            if index < actions.count - 1 {
              Divider().overlay(Brand.line)
            }
          }
        }
        .capkaCard()
      }
    }
  }

  private static let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f
  }()

  // MARK: - Transcript

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if chat.isLoading && chat.messages.isEmpty {
            ProgressView()
              .tint(Brand.primary)
              .frame(maxWidth: .infinity)
              .padding(.top, 40)
          }
          ForEach(chat.messages) { msg in
            CapkaMessageRow(
              message: msg,
              isAdmin: isAdmin,
              canRegenerate: msg.id == chat.latestAssistantId && !msg.isStreaming,
              onRegenerate: { Task { await chat.regenerate() } },
              regenerateDisabled: chat.isBusy || chat.isSending,
              onOpenAttachment: { file in
                preview.open(chatId: chat.chatId, path: file.name, name: file.name)
              },
              onOpenWorkspacePath: { rel in
                preview.open(chatId: chat.chatId, path: rel, name: (rel as NSString).lastPathComponent)
              },
              chatId: chat.chatId,
              onAnswerAsk: { card, action, values in
                Task { await chat.answerAsk(card, messageId: msg.id, action: action, values: values) }
              },
              onDecideApproval: { card, approved in
                Task { await chat.decideApproval(card, messageId: msg.id, approved: approved) }
              },
              onSendText: { text in
                chat.draft = text
                Task { await chat.send() }
              },
              onEdit: editHandler(msg),
              onSwitchBranch: branchHandler(msg)
            )
            .id(msg.id)
            .capkaEntrance(.message)
          }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: 780, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      // Scrolling back over a streaming reply must win over following it.
      .simultaneousGesture(
        DragGesture(minimumDistance: 8).onChanged { value in
          if value.translation.height > 0 { follow = false }
        }
      )
      .onChange(of: chat.messages.last?.text) { _, _ in
        guard follow, let id = chat.messages.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
      }
      .onChange(of: chat.messages.last?.steps.count) { _, _ in
        guard follow, let id = chat.messages.last?.id else { return }
        withAnimation(Motion.easeOut(0.24)) { proxy.scrollTo(id, anchor: .bottom) }
      }
      .onChange(of: chat.messages.count) { _, _ in
        follow = true
        guard let id = chat.messages.last?.id else { return }
        withAnimation(Motion.easeOut(0.24)) { proxy.scrollTo(id, anchor: .bottom) }
      }
      .overlay(alignment: .bottom) {
        if !follow {
          Button {
            follow = true
            guard let id = chat.messages.last?.id else { return }
            withAnimation(Motion.easeOut(0.3)) { proxy.scrollTo(id, anchor: .bottom) }
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
              if chat.isBusy {
                Text("正在回复").font(.system(size: 12, weight: .medium))
              }
            }
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .capkaCard(radius: 999)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.bottom, 10)
          .transition(.opacity.combined(with: .offset(y: 8)))
        }
      }
      .animation(Motion.easeOut(0.2), value: follow)
    }
  }

  /// Only user turns are editable, and only messages with alternatives get the
  /// version arrows — nil keeps the affordance off the row entirely.
  private func editHandler(_ message: ChatUIMessage) -> ((String) -> Void)? {
    guard message.role == "user" else { return nil }
    return { text in Task { await chat.edit(messageId: message.id, newText: text) } }
  }

  private func branchHandler(_ message: ChatUIMessage) -> ((String) -> Void)? {
    guard message.siblingCount > 1 else { return nil }
    return { direction in
      Task { await chat.switchBranch(messageId: message.id, direction: direction) }
    }
  }

  // MARK: - Composer

  private var composer: some View {
    composerCard(homeStyle: false)
  }

  private func composerCard(homeStyle: Bool) -> some View {
    @Bindable var chat = chat
    return VStack(spacing: 0) {
      if !chat.pendingAttachments.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(Array(chat.pendingAttachments.enumerated()), id: \.offset) { index, file in
              AttachmentTile(
                name: file.name,
                kind: .of(name: file.name, mime: file.type),
                onRemove: { chat.removeAttachment(at: index) }
              )
            }
          }
          .padding(.horizontal, 14)
          .padding(.top, 14)
        }
        .frame(maxHeight: 132)
      }

      TextField(
        chat.pendingAttachments.isEmpty ? "分配任务或提出任何问题" : "添加有关文件的消息...",
        text: $chat.draft,
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .lineLimit(1...10)
      .font(.system(size: 15))
      .focused($composerFocused)
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 6)
      // A vertical TextField on macOS submits on ↩ and inserts a newline on ⌥↩ —
      // the Mac convention, and the opposite of the phone's.
      .onSubmit { Task { await chat.send() } }

      if !chat.outbox.isOnline {
        HStack(spacing: 6) {
          Image(systemName: "wifi.slash").font(.system(size: 11))
          Text(chat.outbox.hasPending ? "离线 · 有待发送的消息" : "离线 · 消息会在恢复网络后发出")
            .font(.system(size: 11))
          Spacer(minLength: 0)
        }
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
      }

      HStack(spacing: 6) {
        ProjectChip(name: chat.projectName) { showProjectPicker = true }
          .padding(.leading, 4)

        // No camera or scanner here — a Mac attaches a file, which is also the
        // only thing the web composer offers.
        Button { showImporter = true } label: {
          Image(systemName: "paperclip")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Brand.muted)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("添加附件")

        Spacer(minLength: 8)

        if let fill = chat.contextFill, fill >= 0.5 {
          ContextMeter(fill: fill, summary: chat.contextSummary)
        }

        if chat.isBusy {
          Button { Task { await chat.stop() } } label: {
            Image(systemName: "stop.fill")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Brand.ink)
              .frame(width: 30, height: 30)
              .background(Brand.accent)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                  .stroke(Brand.line, lineWidth: 1)
              )
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help("停止生成")
        } else {
          Button { Task { await chat.send() } } label: {
            Image(systemName: "arrow.up")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(Brand.onPrimary)
              .frame(width: 30, height: 30)
              .background(canSend ? Brand.primary : Brand.muted.opacity(0.3))
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!canSend)
          .help("发送（⌘↩）")
        }
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
    }
    .capkaCard(radius: Brand.Radius.xxl)
    .frame(maxWidth: homeStyle ? .infinity : 780)
    .padding(.horizontal, homeStyle ? 0 : 16)
    .padding(.vertical, homeStyle ? 0 : 10)
    .frame(maxWidth: .infinity)
  }

  private var canSend: Bool {
    let hasText = !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // A pending question is the one next action — the web blocks the composer
    // the same way (useBackgroundChat.awaitingInput).
    return (hasText || !chat.pendingAttachments.isEmpty) && !chat.isSending && !chat.awaitingInput
  }
}
