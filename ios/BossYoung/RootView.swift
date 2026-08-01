import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
  @Environment(SessionStore.self) private var session
  @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue

  private var theme: ThemePreference {
    ThemePreference(rawValue: themeRaw) ?? .system
  }

  var body: some View {
    Group {
      if session.isRestoring {
        ZStack {
          Brand.cream.ignoresSafeArea()
          ProgressView().tint(Brand.primary)
        }
      } else if session.isAuthenticated {
        MainShellView()
      } else {
        LoginView()
      }
    }
    .capkaPreferredColorScheme(theme)
    .task {
      if CapkaFixtures.isEnabled {
        CapkaFixtures.seed(session: session)
        return
      }
      await session.bootstrap()
    }
  }
}

struct MainShellView: View {
  @Environment(SessionStore.self) private var session
  @State private var chat = ChatViewModel()
  @State private var list = ChatListViewModel()
  @State private var showSidebar = false
  @State private var showImporter = false
  @State private var importerTypes: [UTType] = [.item]
  @State private var showCamera = false
  @State private var showScanner = false
  @State private var showPhotoPicker = false
  @State private var photoPicks: [PhotosPickerItem] = []
  @State private var preview = FilePreviewLoader()
  @State private var showModelPicker = false
  @State private var showProjects = false
  @State private var showProjectPicker = false
  @State private var showArchived = false
  @State private var showSettings = false
  @State private var showFiles = false
  @State private var renameTarget: ChatSummary?
  @State private var renameText = ""
  @State private var moveTarget: ChatSummary?
  @State private var moveProjects: [ProjectSummary] = []
  @State private var filesProject: ProjectSummary?
  @State private var starterType = "pdf"
  @State private var voice = VoiceDictation()
  @State private var sidebarDragOffset: CGFloat = 0
  @State private var filesDragOffset: CGFloat = 0
  @FocusState private var composerFocused: Bool

  private var isAdmin: Bool { session.user?.role == "admin" }

  var body: some View {
    @Bindable var chat = chat

    ZStack {
      Brand.cream.ignoresSafeArea()

      VStack(spacing: 0) {
        topBar

        if chat.isEmptyChat {
          emptyHome(chat: chat)
        } else {
          messageList(chat: chat)
          composerCard(chat: chat, homeStyle: false)
        }
      }

      // Narrow left-edge strip — swipe right to open the chat drawer.
      if !showSidebar && !showFiles {
        HStack(spacing: 0) {
          Color.clear
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onEnded { value in
                  if value.translation.width > 56, abs(value.translation.height) < 80 {
                    showSidebar = true
                    Task { await list.refresh() }
                  }
                }
            )
          Spacer(minLength: 0)
          // Right-edge strip — swipe left to open the workspace (chat only).
          if !chat.isEmptyChat {
            Color.clear
              .frame(width: 22)
              .frame(maxHeight: .infinity)
              .contentShape(Rectangle())
              .gesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .global)
                  .onEnded { value in
                    if value.translation.width < -56, abs(value.translation.height) < 80 {
                      openWorkspace()
                    }
                  }
              )
          }
        }
        .allowsHitTesting(true)
      }

      if showSidebar {
        sidebarOverlay
          .offset(x: min(0, sidebarDragOffset))
          .transition(.move(edge: .leading).combined(with: .opacity))
          .zIndex(2)
      }

      if showFiles {
        workspaceOverlay
          .offset(x: max(0, filesDragOffset))
          .transition(.move(edge: .trailing).combined(with: .opacity))
          .zIndex(3)
      }
    }
    .animation(Motion.easeOut(0.28), value: showSidebar)
    .animation(Motion.easeOut(0.28), value: showFiles)
    .animation(Motion.easeOut(0.28), value: chat.isEmptyChat)
    .sensoryFeedback(.selection, trigger: showSidebar)
    .sensoryFeedback(.selection, trigger: showFiles)
    .alert("语音输入", isPresented: Binding(
      get: { voice.error != nil },
      set: { if !$0 { voice.error = nil } }
    )) {
      Button("好", role: .cancel) { voice.error = nil }
    } message: {
      Text(voice.error ?? "")
    }
    .onDisappear { voice.stop() }
    .task {
      chat.bind(session: session)
      list.bind(session: session)
      if CapkaFixtures.isEnabled {
        CapkaFixtures.seed(chat: chat, list: list)
        openDebugScreen(ProcessInfo.processInfo.environment["CAPKA_UI_FIXTURES_SCREEN"])
        return
      }
      await chat.load()
      await chat.flushOutbox()
      await list.refreshQuietly()
      // Real-session screen jumps for offline/online QA (Debug launchctl only).
      openDebugScreen(ProcessInfo.processInfo.environment["CAPKA_OPEN_SCREEN"])
      if let raw = ProcessInfo.processInfo.environment["CAPKA_OPEN_CHAT"], !raw.isEmpty {
        if raw == "latest" {
          if let id = list.chats.first?.id { await chat.openChat(id) }
        } else {
          await chat.openChat(raw)
        }
      }
      #if DEBUG
      if ProcessInfo.processInfo.environment["CAPKA_SEND_SMOKE"] == "1" {
        chat.draft = "iOS 连通性自检 \(Int(Date().timeIntervalSince1970))"
        await chat.send()
      }
      #endif
    }
    .onReceive(NotificationCenter.default.publisher(for: PushRegistrar.openChatNotification)) { note in
      guard let id = note.object as? String else { return }
      showSidebar = false
      Task { await chat.openChat(id) }
    }
    .onChange(of: session.eventSeq) { _, _ in
      if let event = session.lastEvent {
        chat.applyEvent(event)
        list.applyEvent(event)
      }
    }
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: importerTypes,
      allowsMultipleSelection: true
    ) { result in
      guard case .success(let urls) = result else { return }
      Task {
        for url in urls { await chat.attach(fileURL: url) }
      }
    }
    .photosPicker(
      isPresented: $showPhotoPicker,
      selection: $photoPicks,
      maxSelectionCount: 5,
      matching: .images
    )
    .onChange(of: photoPicks) { _, picks in
      guard !picks.isEmpty else { return }
      photoPicks = []
      Task {
        for pick in picks {
          guard let data = try? await pick.loadTransferable(type: Data.self) else { continue }
          await chat.attach(photoData: data, type: pick.supportedContentTypes.first)
        }
      }
    }
    .fullScreenCover(isPresented: $showScanner) {
      DocumentScanner { url in
        showScanner = false
        guard let url else { return }
        Task {
          await chat.attach(fileURL: url)
          try? FileManager.default.removeItem(at: url)
        }
      }
      .ignoresSafeArea()
    }
    .fullScreenCover(isPresented: $showCamera) {
      CameraPicker { image in
        showCamera = false
        guard let image else { return }
        Task { await chat.attach(capturedImage: image) }
      }
      .ignoresSafeArea()
    }
    .filePreview(preview)
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
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showProjectPicker) {
      ProjectContextSheet(
        currentId: chat.projectId,
        currentName: chat.projectName,
        onSelect: { project in
          // Switching context only makes sense for a chat that doesn't exist
          // yet; an existing one keeps the sandbox it was created in.
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
    }
    .sheet(item: $filesProject) { project in
      NavigationStack {
        WorkspaceFilesView(chatId: nil, projectId: project.id, title: project.name)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("完成") { filesProject = nil }.foregroundStyle(Brand.primary)
            }
          }
      }
    }
    .sheet(isPresented: $showProjects) {
      NavigationStack {
        ProjectsListView { id in
          showProjects = false
          showSidebar = false
          Task { await chat.openChat(id) }
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("完成") { showProjects = false }.foregroundStyle(Brand.primary)
          }
        }
      }
    }
    .sheet(isPresented: $showArchived) {
      NavigationStack {
        ArchivedChatsView { id in
          showArchived = false
          showSidebar = false
          Task { await chat.openChat(id) }
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("完成") { showArchived = false }.foregroundStyle(Brand.primary)
          }
        }
      }
    }
    .sheet(isPresented: $showSettings) {
      NavigationStack {
        SettingsHomeView()
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("完成") { showSettings = false }.foregroundStyle(Brand.primary)
            }
          }
      }
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

  // MARK: - Top bar

  private func openDebugScreen(_ name: String?) {
    #if DEBUG
    switch name {
    case "sidebar": showSidebar = true
    case "settings": showSettings = true
    case "projects": showProjects = true
    case "files": showFiles = true
    case "archived": showArchived = true
    default: break
    }
    #endif
  }

  private var topBar: some View {
    HStack(spacing: 8) {
      circleButton("line.3.horizontal") {
        showSidebar = true
        Task { await list.refresh() }
      }

      // Web floating header: model chip sits beside the sidebar trigger.
      if !chat.isEmptyChat {
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
        }
        .buttonStyle(CapkaPressStyle())
      }

      Spacer(minLength: 4)

      if !chat.isEmptyChat {
        circleButton("folder") { openWorkspace() }
      }
      circleButton("square.and.pencil") { chat.startNewChat() }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Brand.ink.opacity(0.75))
        .frame(width: 36, height: 36)
        .background(Brand.card)
        .clipShape(Circle())
        .overlay(Circle().stroke(Brand.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
  }

  private var currentModelName: String {
    chat.models.first(where: { $0.id == chat.selectedModelId })?.name ?? "选择型号"
  }

  private func dismissComposer() {
    composerFocused = false
    voice.stop()
  }

  private func openWorkspace() {
    dismissComposer()
    withAnimation(Motion.easeOut(0.28)) {
      showFiles = true
      filesDragOffset = 0
    }
  }

  private func closeWorkspace() {
    withAnimation(Motion.easeOut(0.28)) {
      showFiles = false
      filesDragOffset = 0
    }
  }

  // MARK: - Empty home

  private func emptyHome(chat: ChatViewModel) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: composerFocused ? 28 : 72)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onTapGesture { dismissComposer() }

        Image("BrandWordmark")
          .resizable()
          .scaledToFit()
          .frame(height: 46)
          .padding(.bottom, composerFocused ? 22 : 34)
          .capkaEntrance(.blurRise)
          .onTapGesture { dismissComposer() }

        composerCard(chat: chat, homeStyle: true)
          .padding(.horizontal, 18)
          .capkaEntrance(.blurRise, delay: 0.06)

        Button { showModelPicker = true } label: {
          HStack(spacing: 6) {
            if let model = chat.models.first(where: { $0.id == chat.selectedModelId }) {
              ProviderIconView(slug: model.iconSlug, size: 13)
            }
            if modelFeatured {
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
        }
        .padding(.top, 14)

        if !composerFocused {
          homeSuggestions
            .padding(.top, 32)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .capkaEntrance(.blurRise, delay: 0.12)
        } else {
          Color.clear
            .frame(minHeight: 120)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismissComposer() }
        }

        Spacer(minLength: 60)
          .contentShape(Rectangle())
          .onTapGesture { dismissComposer() }
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: UIScreen.main.bounds.height * 0.68)
      .animation(Motion.easeOut(0.32), value: composerFocused)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var modelFeatured: Bool {
    chat.models.first(where: { $0.id == chat.selectedModelId })?.featured == true
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
            ForEach(Array(list.chats.prefix(4).enumerated()), id: \.element.id) { index, row in
              Button {
                Task { await chat.openChat(row.id) }
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

              if index < min(4, list.chats.count) - 1 {
                Divider().overlay(Brand.line)
              }
            }
          }
          .capkaCard()
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        // Type pills + three concrete verbs, matching the web's FileTypeSuggestions:
        // picking one seeds the composer, it does not open a file picker.
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
            }
            .buttonStyle(CapkaPressStyle())
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
    .padding(.horizontal, 18)
  }

  private static let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f
  }()

  // MARK: - Messages

  private func messageList(chat: ChatViewModel) -> some View {
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
              // Uploads land at the workspace root, so the name is the path.
              onOpenAttachment: { file in
                preview.open(chatId: chat.chatId, path: file.name, name: file.name)
              },
              onOpenWorkspacePath: { rel in
                preview.open(
                  chatId: chat.chatId,
                  path: rel,
                  name: (rel as NSString).lastPathComponent
                )
              },
              chatId: chat.chatId,
              onAnswerAsk: { card, action, values in
                Task {
                  await chat.answerAsk(card, messageId: msg.id, action: action, values: values)
                }
              },
              onDecideApproval: { card, approved in
                Task { await chat.decideApproval(card, messageId: msg.id, approved: approved) }
              },
              onEdit: editHandler(chat: chat, message: msg),
              onSwitchBranch: branchHandler(chat: chat, message: msg)
            )
            .id(msg.id)
            .capkaEntrance(.message)
          }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
      }
      .scrollDismissesKeyboard(.interactively)
      .simultaneousGesture(TapGesture().onEnded { dismissComposer() })
      .refreshable { await chat.load() }
      .onChange(of: chat.messages.last?.text) { _, _ in
        guard let id = chat.messages.last?.id else { return }
        withAnimation(Motion.easeOut(0.24)) { proxy.scrollTo(id, anchor: .bottom) }
      }
      .onChange(of: chat.messages.last?.steps.count) { _, _ in
        guard let id = chat.messages.last?.id else { return }
        withAnimation(Motion.easeOut(0.24)) { proxy.scrollTo(id, anchor: .bottom) }
      }
      .onChange(of: chat.messages.count) { _, _ in
        guard let id = chat.messages.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
      }
    }
  }

  /// Only user turns are editable, and only messages with alternatives get the
  /// version arrows — nil keeps the affordance off the row entirely.
  private func editHandler(chat: ChatViewModel, message: ChatUIMessage) -> ((String) -> Void)? {
    guard message.role == "user" else { return nil }
    return { text in Task { await chat.edit(messageId: message.id, newText: text) } }
  }

  private func branchHandler(chat: ChatViewModel, message: ChatUIMessage) -> ((String) -> Void)? {
    guard message.siblingCount > 1 else { return nil }
    return { direction in
      Task { await chat.switchBranch(messageId: message.id, direction: direction) }
    }
  }

  // MARK: - Composer

  private func composerCard(chat: ChatViewModel, homeStyle: Bool) -> some View {
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
      .lineLimit(1...8)
      .font(.system(size: 16))
      .focused($composerFocused)
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 6)

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
        // Working context first, then what you add to it.
        ProjectChip(name: chat.projectName) { showProjectPicker = true }
          .padding(.leading, 4)

        // On a phone the common case is a photo of a paper document, not a file
        // sitting in the Files app — so 照片 / 拍照 come before 文件.
        Menu {
          Button {
            showPhotoPicker = true
          } label: {
            Label("照片", systemImage: "photo.on.rectangle")
          }
          if DocumentScanner.isAvailable {
            Button {
              showScanner = true
            } label: {
              Label("扫描文档", systemImage: "doc.viewfinder")
            }
          }
          if CameraPicker.isAvailable {
            Button {
              showCamera = true
            } label: {
              Label("拍照", systemImage: "camera")
            }
          }
          Button {
            importerTypes = [.item]
            showImporter = true
          } label: {
            Label("文件", systemImage: "folder")
          }
        } label: {
          Image(systemName: "paperclip")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Brand.muted)
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel("添加附件")

        Spacer(minLength: 8)

        if let fill = chat.contextFill, fill >= 0.5 {
          ContextMeter(fill: fill, summary: chat.contextSummary)
        }

        Button {
          composerFocused = true
          voice.toggle(into: $chat.draft)
        } label: {
          Image(systemName: voice.isListening ? "mic.fill" : "mic")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(voice.isListening ? Brand.dangerText : Brand.muted)
            .frame(width: 36, height: 36)
            .background(voice.isListening ? Brand.dangerSurface : Color.clear)
            .clipShape(Circle())
        }
        .accessibilityLabel(voice.isListening ? "停止语音输入" : "语音输入")
        .disabled(chat.isBusy)

        if chat.isBusy {
          Button { Task { await chat.stop() } } label: {
            Image(systemName: "stop.fill")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Brand.ink)
              .frame(width: 34, height: 34)
              .background(Brand.accent)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                  .stroke(Brand.line, lineWidth: 1)
              )
          }
          .accessibilityLabel("停止生成")
        } else {
          Button {
            voice.stop()
            Task { await chat.send() }
          } label: {
            Image(systemName: "arrow.up")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(Brand.onPrimary)
              .frame(width: 34, height: 34)
              .background(canSend(chat) ? Brand.primary : Brand.muted.opacity(0.3))
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          }
          .disabled(!canSend(chat))
          .accessibilityLabel("发送")
        }
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
    }
    .capkaCard(radius: Brand.Radius.xxl)
    .padding(.horizontal, homeStyle ? 0 : 14)
    .padding(.top, homeStyle ? 0 : 4)
    .padding(.bottom, homeStyle ? 0 : 10)
    .background(homeStyle ? Color.clear : Brand.cream)
  }

  private func canSend(_ chat: ChatViewModel) -> Bool {
    let hasText = !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // A pending question is the one next action — the web blocks the composer
    // the same way (useBackgroundChat.awaitingInput).
    return (hasText || !chat.pendingAttachments.isEmpty) && !chat.isSending && !chat.awaitingInput
  }

  // MARK: - Sidebar

  private var sidebarOverlay: some View {
    // The keyboard must not reach this GeometryReader: it feeds safeAreaInsets
    // into SidebarView, so a keyboard-driven inset change rebuilt the whole
    // drawer — the flash seen when tapping the search field. The drawer's own
    // search field sits at the top and has nothing to reveal anyway.
    GeometryReader { geo in
      let width = min(300, geo.size.width * 0.86)
      ZStack(alignment: .leading) {
        Color.black.opacity(0.28 * Double(1 + min(0, sidebarDragOffset) / width))
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(Motion.easeOut(0.28)) {
              showSidebar = false
              sidebarDragOffset = 0
            }
          }

        SidebarView(
          list: list,
          currentChatId: chat.chatId,
          safeAreaTop: geo.safeAreaInsets.top,
          safeAreaBottom: geo.safeAreaInsets.bottom,
          onNewChat: {
            chat.startNewChat()
            closeSidebar()
          },
          onOpenChat: { row in
            closeSidebar()
            Task {
              await chat.openChat(row.id, projectId: row.projectId, projectName: row.projectName)
            }
          },
          onOpenProjects: { showProjects = true },
          onOpenArchived: { showArchived = true },
          onOpenSettings: { showSettings = true },
          onClose: { closeSidebar() },
          onRename: { row in
            renameTarget = row
            renameText = row.title ?? ""
          },
          onMove: { row in
            Task {
              moveProjects = (try? await CapkaAPIClient.shared.listProjects()) ?? []
              moveTarget = row
            }
          }
        )
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .gesture(
          DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
              sidebarDragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
              if value.translation.width < -80 || value.predictedEndTranslation.width < -160 {
                closeSidebar()
              } else {
                withAnimation(Motion.easeOut(0.22)) { sidebarDragOffset = 0 }
              }
            }
        )
      }
      .ignoresSafeArea()
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
  }

  private var workspaceOverlay: some View {
    GeometryReader { geo in
      let width = min(340, geo.size.width * 0.9)
      ZStack(alignment: .trailing) {
        Color.black.opacity(0.28 * Double(1 - min(width, max(0, filesDragOffset)) / width))
          .ignoresSafeArea()
          .onTapGesture { closeWorkspace() }

        NavigationStack {
          WorkspaceFilesView(chatId: chat.chatId, projectId: nil, title: "工作区文件")
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { closeWorkspace() }
                  .foregroundStyle(Brand.primary)
              }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Brand.cream)
        .shadow(color: .black.opacity(0.12), radius: 18, x: -4)
        .gesture(
          DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
              filesDragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
              if value.translation.width > 80 || value.predictedEndTranslation.width > 160 {
                closeWorkspace()
              } else {
                withAnimation(Motion.easeOut(0.22)) { filesDragOffset = 0 }
              }
            }
        )
      }
      .ignoresSafeArea()
    }
  }

  private func closeSidebar() {
    withAnimation(Motion.easeOut(0.28)) {
      showSidebar = false
      sidebarDragOffset = 0
    }
  }
}

// MARK: - Home starters

/// Mirrors `chat.panel.getToWork` in `messages/zh-CN.json` — same four types,
/// same three verbs each, same prompt text seeded into the composer.
private enum HomeStarters {
  struct Action {
    let label: String
    let prompt: String
    let icon: String
  }

  struct Group {
    let id: String
    let title: String
    let actions: [Action]
  }

  static let all: [Group] = [
    Group(id: "pdf", title: "PDF 文件", actions: [
      Action(label: "提取文本", prompt: "从我将附上的 PDF 中提取文本： ", icon: "text.viewfinder"),
      Action(label: "填写表格", prompt: "填写我将附上的 PDF 中的表单字段： ", icon: "square.and.pencil"),
      Action(label: "转换为Word", prompt: "将我要附加的 PDF 转换为可编辑的 Word 文档。", icon: "doc.text"),
    ]),
    Group(id: "spreadsheet", title: "电子表格", actions: [
      Action(label: "分析数据", prompt: "分析我将附上的电子表格并总结主要趋势： ", icon: "chart.bar"),
      Action(label: "构建图表", prompt: "从我将附上的电子表格中构建一个清晰的图表。", icon: "chart.xyaxis.line"),
      Action(label: "清理数据", prompt: "清理并整理我将附上的电子表格中的数据。", icon: "eraser"),
    ]),
    Group(id: "document", title: "文件", actions: [
      Action(label: "总结一下", prompt: "总结一下我将附上的文件： ", icon: "doc.plaintext"),
      Action(label: "翻译一下", prompt: "翻译我要附加的文件 ", icon: "character.book.closed"),
      Action(label: "让它看起来干净", prompt: "重新格式化我要附加的文档，使其看起来干净、专业。", icon: "text.alignleft"),
    ]),
    Group(id: "image", title: "图片", actions: [
      Action(label: "拉出文字", prompt: "从我要附加的图像中提取文本： ", icon: "doc.text.viewfinder"),
      Action(label: "删除背景", prompt: "从我要附加的图像中删除背景。", icon: "eraser"),
      Action(label: "调整大小或转换", prompt: "调整或转换我要附加的图像： ", icon: "crop"),
    ]),
  ]
}

// MARK: - Model picker

private struct ModelPickerSheet: View {
  let models: [ModelInfo]
  let selectedId: String?
  let onSelect: (String) -> Void
  let onClose: () -> Void

  @State private var query = ""

  private var filtered: [ModelInfo] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return models }
    return models.filter {
      $0.name.lowercased().contains(q)
        || $0.id.lowercased().contains(q)
        || ($0.group?.lowercased().contains(q) ?? false)
        || ($0.provider?.lowercased().contains(q) ?? false)
    }
  }

  private var featured: [ModelInfo] { filtered.filter { $0.featured == true } }

  private var grouped: [(String, [ModelInfo])] {
    let rest = filtered.filter { $0.featured != true }
    let dict = Dictionary(grouping: rest, by: \.displayGroup)
    let priority = ["Anthropic", "OpenAI", "Google", "Meta", "Mistral", "DeepSeek", "xAI", "Qwen"]
    return dict.keys.sorted { a, b in
      let ia = priority.firstIndex(of: a) ?? 999
      let ib = priority.firstIndex(of: b) ?? 999
      if ia != ib { return ia < ib }
      return a < b
    }.map { ($0, dict[$0] ?? []) }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()

        VStack(spacing: 0) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(Brand.muted)
            TextField("搜索型号", text: $query)
              .font(.system(size: 16))
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 11)
          .capkaCard(radius: Brand.Radius.lg)
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 12)

          if models.isEmpty {
            VStack(spacing: 10) {
              ProgressView().tint(Brand.primary)
              Text("正在加载型号…")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if filtered.isEmpty {
            Text("没有匹配的型号")
              .font(.subheadline)
              .foregroundStyle(Brand.muted)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 18) {
                if !featured.isEmpty {
                  section(title: "精选", models: featured)
                }
                ForEach(grouped, id: \.0) { group, items in
                  section(title: group, models: items)
                }
              }
              .padding(.horizontal, 16)
              .padding(.bottom, 24)
            }
          }
        }
      }
      .navigationTitle("型号")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("关闭", action: onClose)
            .fontWeight(.semibold)
            .foregroundStyle(Brand.primary)
        }
      }
    }
  }

  private func section(title: String, models: [ModelInfo]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)

      VStack(spacing: 0) {
        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
          Button {
            onSelect(model.id)
          } label: {
            HStack(alignment: .center, spacing: 12) {
              ZStack {
                RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                  .fill(Brand.accent)
                  .frame(width: 34, height: 34)
                ProviderIconView(slug: model.iconSlug, size: 20)
              }

              VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                  .font(.system(size: 15, weight: .medium))
                  .foregroundStyle(Brand.ink)
                  .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                  if let ctx = model.context, ctx > 0 {
                    Text(formatContext(ctx))
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                  if model.vision == true {
                    Label("图片", systemImage: "eye")
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                  if model.reasoning == true {
                    Label("推理", systemImage: "brain")
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                }
              }

              Spacer(minLength: 8)

              if model.id == selectedId {
                Image(systemName: "checkmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Brand.primary)
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
          }
          .buttonStyle(CapkaPressStyle())

          if index < models.count - 1 {
            Divider().overlay(Brand.line).padding(.leading, 58)
          }
        }
      }
      .capkaCard()
    }
  }

  private func formatContext(_ ctx: Int) -> String {
    if ctx >= 1_000_000 { return "\(ctx / 1_000_000)M 上下文" }
    if ctx >= 1_000 { return "\(ctx / 1_000)K 上下文" }
    return "\(ctx) 上下文"
  }
}
