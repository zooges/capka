import SwiftUI

/// Sidebar + transcript, the shape a Mac window wants. The chat list, the
/// transcript rows, the composer's model/project pickers and every settings page
/// are the same types the iOS client uses; only this container is new.
struct MacRootView: View {
  static let newChatNotification = Notification.Name("capka.mac.newChat")

  @Environment(SessionStore.self) private var session
  @State private var chat = ChatViewModel()
  @State private var list = ChatListViewModel()
  @State private var preview = FilePreviewLoader()
  @State private var showImporter = false
  @State private var showProjectPicker = false
  @State private var filesProject: ProjectSummary?
  @State private var search = ""
  @State private var searchTask: Task<Void, Never>?
  @State private var renameTarget: ChatSummary?
  @State private var renameText = ""
  @State private var moveTarget: ChatSummary?
  @State private var moveProjects: [ProjectSummary] = []
  @FocusState private var composerFocused: Bool

  var body: some View {
    Group {
      if session.isRestoring {
        ProgressView().tint(Brand.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if session.isAuthenticated {
        shell
      } else {
        MacLoginView()
      }
    }
    .background(Brand.cream)
  }

  private var shell: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    } detail: {
      transcript
    }
    .task {
      chat.bind(session: session)
      list.bind(session: session)
      await chat.load()
      await chat.flushOutbox()
      await list.refreshQuietly()
    }
    .onChange(of: session.eventSeq) { _, _ in
      if let event = session.lastEvent {
        chat.applyEvent(event)
        list.applyEvent(event)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: Self.newChatNotification)) { _ in
      chat.startNewChat()
      composerFocused = true
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

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(spacing: 0) {
      List(selection: Binding(
        get: { chat.chatId },
        set: { id in
          guard let id, let row = list.chats.first(where: { $0.id == id }) else { return }
          Task { await chat.openChat(row.id, projectId: row.projectId, projectName: row.projectName) }
        }
      )) {
        ForEach(list.chats) { row in
          HStack(spacing: 8) {
            Text(row.title?.isEmpty == false ? row.title! : "新聊天")
              .font(.system(size: 13))
              .lineLimit(1)
            Spacer(minLength: 4)
            if row.running == true {
              ProgressView().controlSize(.mini)
            }
          }
          .tag(row.id)
          .contextMenu {
            Button("重命名…") {
              renameText = row.title ?? ""
              renameTarget = row
            }
            Button("移至项目…") {
              moveTarget = row
              Task { moveProjects = (try? await CapkaAPIClient.shared.listProjects()) ?? [] }
            }
            Button(row.pinned == true ? "取消置顶" : "置顶") {
              Task { await list.setPinned(chatId: row.id, pinned: !(row.pinned == true)) }
            }
            Button("归档") { Task { await list.setArchived(chatId: row.id, archived: true) } }
            Divider()
            Button("删除", role: .destructive) {
              Task { await list.deleteChat(chatId: row.id) }
            }
          }
        }
      }
      .listStyle(.sidebar)
      .searchable(text: $search, placement: .sidebar, prompt: "搜索聊天记录")
      .onChange(of: search) { _, value in
        searchTask?.cancel()
        searchTask = Task {
          try? await Task.sleep(nanoseconds: 300_000_000)
          guard !Task.isCancelled else { return }
          await list.refreshFiltered(search: value.isEmpty ? nil : value)
        }
      }

      Divider()

      HStack(spacing: 8) {
        if let user = session.user {
          Text(user.name).font(.system(size: 12)).foregroundStyle(Brand.muted).lineLimit(1)
        }
        Spacer(minLength: 4)
        Button("退出") { Task { await session.signOut() } }
          .font(.system(size: 12))
          .buttonStyle(.plain)
          .foregroundStyle(Brand.dangerText)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .toolbar {
      ToolbarItem {
        Button { chat.startNewChat(); composerFocused = true } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("新聊天")
      }
    }
  }

  // MARK: - Transcript

  private var transcript: some View {
    @Bindable var chat = chat
    return VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(chat.messages) { msg in
              CapkaMessageRow(
                message: msg,
                isAdmin: session.user?.role == "admin",
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
                }
              )
              .id(msg.id)
            }
          }
          .padding(.vertical, 12)
          .frame(maxWidth: 780, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
        .onChange(of: chat.messages.last?.text) { _, _ in
          guard let id = chat.messages.last?.id else { return }
          proxy.scrollTo(id, anchor: .bottom)
        }
        .onChange(of: chat.messages.count) { _, _ in
          guard let id = chat.messages.last?.id else { return }
          withAnimation(Motion.easeOut(0.24)) { proxy.scrollTo(id, anchor: .bottom) }
        }
      }

      Divider()
      composer
    }
    .filePreview(preview)
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
      guard case .success(let urls) = result else { return }
      Task { for url in urls { await chat.attach(fileURL: url) } }
    }
    .sheet(isPresented: $showProjectPicker) {
      ProjectContextSheet(
        currentId: chat.projectId,
        currentName: chat.projectName,
        onSelect: { project in
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
      .frame(width: 520, height: 560)
    }
    .sheet(item: $filesProject) { project in
      NavigationStack {
        WorkspaceFilesView(chatId: nil, projectId: project.id, title: project.name)
          .toolbar {
            ToolbarItem(placement: .capkaTrailing) {
              Button("完成") { filesProject = nil }
            }
          }
      }
      .frame(width: 620, height: 620)
    }
  }

  /// The phone shows a searchable sheet because a list of forty models does not
  /// fit on a phone. A Mac has a menu bar's worth of room, so the same list —
  /// featured first, then grouped by provider — goes in a pull-down where a Mac
  /// user expects to find it.
  private var modelMenu: some View {
    let featured = chat.models.filter { $0.featured == true }
    let priority = ["Anthropic", "OpenAI", "Google", "Meta", "Mistral", "DeepSeek", "xAI", "Qwen"]
    let grouped = Dictionary(grouping: chat.models.filter { $0.featured != true }, by: \.displayGroup)
    let groups = grouped.keys.sorted { a, b in
      let ia = priority.firstIndex(of: a) ?? 999
      let ib = priority.firstIndex(of: b) ?? 999
      return ia == ib ? a < b : ia < ib
    }

    return Menu {
      if chat.models.isEmpty {
        Text("正在加载型号…")
      }
      ForEach(featured) { model in modelButton(model) }
      if !featured.isEmpty && !groups.isEmpty { Divider() }
      ForEach(groups, id: \.self) { group in
        Menu(group) {
          ForEach(grouped[group] ?? []) { model in modelButton(model) }
        }
      }
    } label: {
      Text(chat.models.first { $0.id == chat.selectedModelId }?.name ?? "选择型号")
        .font(.system(size: 12))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .foregroundStyle(Brand.muted)
    .help("选择型号")
  }

  private func modelButton(_ model: ModelInfo) -> some View {
    Button {
      chat.selectedModelId = model.id
    } label: {
      if model.id == chat.selectedModelId {
        Label(model.name, systemImage: "checkmark")
      } else {
        Text(model.name)
      }
    }
  }

  private var composer: some View {
    @Bindable var chat = chat
    return VStack(alignment: .leading, spacing: 8) {
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
        }
        .frame(maxHeight: 120)
      }

      TextField("分配任务或提出任何问题", text: $chat.draft, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .lineLimit(1...10)
        .focused($composerFocused)
        // A vertical TextField on macOS submits on ↩ and inserts a newline on
        // ⌥↩ — the Mac convention, and the opposite of the phone's. ⌘↩ on the
        // send button below works too, for the muscle memory people bring from
        // the web client.
        .onSubmit { Task { await chat.send() } }

      HStack(spacing: 8) {
        ProjectChipButton(name: chat.projectName) { showProjectPicker = true }
        Button { showImporter = true } label: { Image(systemName: "paperclip") }
          .buttonStyle(.plain)
          .foregroundStyle(Brand.muted)
          .help("添加附件")
        modelMenu

        Spacer(minLength: 8)

        if chat.isBusy {
          Button("停止") { Task { await chat.stop() } }
        } else {
          Button("发送") { Task { await chat.send() } }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              && chat.pendingAttachments.isEmpty)
        }
      }
    }
    .padding(12)
    .frame(maxWidth: 780)
    .frame(maxWidth: .infinity)
  }
}

/// The composer's project chip, in a Mac control idiom.
struct ProjectChipButton: View {
  let name: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: name == nil ? "folder.badge.plus" : "folder.fill")
        Text(name ?? "选择项目").lineLimit(1)
      }
      .font(.system(size: 12))
    }
    .buttonStyle(.plain)
    .foregroundStyle(name == nil ? Brand.muted : Brand.ink)
    .help(name.map { "项目：\($0)" } ?? "选择项目")
  }
}
