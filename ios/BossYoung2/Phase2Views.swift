import SwiftUI
import UniformTypeIdentifiers

// MARK: - Archived chats

struct ArchivedChatsView: View {
  @Environment(SessionStore.self) private var session
  var onOpen: (String) -> Void

  @State private var list = ChatListViewModel()
  @State private var deleteTarget: ChatSummary?

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      if list.isLoading && list.chats.isEmpty {
        ProgressView().tint(Brand.primary)
      } else if list.chats.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "archivebox")
            .font(.system(size: 26))
            .foregroundStyle(Brand.muted.opacity(0.6))
          Text("没有存档的聊天记录")
            .font(.system(size: 14))
            .foregroundStyle(Brand.muted)
        }
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(list.chats.enumerated()), id: \.element.id) { index, chat in
              HStack(spacing: 0) {
                Button {
                  onOpen(chat.id)
                } label: {
                  HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(chat.title?.isEmpty == false ? chat.title! : "新聊天")
                        .font(.system(size: 15))
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                      if let project = chat.projectName, !project.isEmpty {
                        Text(project)
                          .font(.system(size: 11))
                          .foregroundStyle(Brand.muted)
                      }
                    }
                    Spacer(minLength: 4)
                  }
                  .padding(.leading, 14)
                  .padding(.vertical, 13)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(CapkaPressStyle())

                Menu {
                  Button {
                    Task { await list.setArchived(chatId: chat.id, archived: false) }
                  } label: {
                    Label("恢复聊天", systemImage: "arrow.uturn.backward")
                  }
                  Button(role: .destructive) { deleteTarget = chat } label: {
                    Label("永久删除", systemImage: "trash")
                  }
                } label: {
                  Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.muted)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("对话选项")
                .padding(.trailing, 6)
              }
              .contextMenu {
                Button {
                  Task { await list.setArchived(chatId: chat.id, archived: false) }
                } label: {
                  Label("恢复聊天", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) { deleteTarget = chat } label: {
                  Label("永久删除", systemImage: "trash")
                }
              }

              if index < list.chats.count - 1 {
                Divider().overlay(Brand.line).padding(.leading, 14)
              }
            }
          }
          .capkaCard()
          .padding(16)
        }
      }
    }
    .navigationTitle("存档的聊天记录")
    .capkaNavigationChrome()
    .task {
      list.bind(session: session)
      await list.refreshFiltered(archived: true)
    }
    .refreshable { await list.refreshFiltered(archived: true) }
    .alert("永久删除聊天记录？", isPresented: Binding(
      get: { deleteTarget != nil },
      set: { if !$0 { deleteTarget = nil } }
    )) {
      Button("永久删除", role: .destructive) {
        if let id = deleteTarget?.id {
          Task { await list.deleteChat(chatId: id) }
        }
        deleteTarget = nil
      }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("此操作无法撤消。该聊天记录及其所有消息将被永久删除。")
    }
  }
}

// MARK: - Projects

struct ProjectsListView: View {
  @Environment(SessionStore.self) private var session
  var onOpenChat: (String) -> Void

  @State private var model = ProjectsViewModel()
  @State private var showCreate = false
  @State private var newName = ""
  @State private var newDesc = ""
  @State private var deleteTarget: ProjectSummary?

  private static let lastChatDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("使用自定义说明和模型组织您的聊天。")
            .font(.system(size: 14))
            .foregroundStyle(Brand.muted)
            .padding(.horizontal, 4)

          if model.isLoading && model.projects.isEmpty {
            ProgressView().tint(Brand.primary).frame(maxWidth: .infinity).padding(.top, 40)
          } else if model.projects.isEmpty {
            VStack(spacing: 12) {
              Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(Brand.muted)
                .frame(width: 56, height: 56)
                .capkaCard(radius: Brand.Radius.xxl)
              Text("还没有项目。创建一个来组织您的聊天。")
                .font(.system(size: 14))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
              Button("创建项目") { showCreate = true }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Brand.card)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Brand.primary)
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
          } else {
            VStack(spacing: 10) {
              ForEach(model.projects) { project in
                NavigationLink {
                  ProjectHubView(project: project, onOpenChat: onOpenChat)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                      .font(.system(size: 16, weight: .medium))
                      .foregroundStyle(Brand.ink)
                    if let d = project.description, !d.isEmpty {
                      Text(d)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 12) {
                      if let n = project.chatCount {
                        HStack(spacing: 4) {
                          Image(systemName: "bubble.left").font(.system(size: 10))
                          Text("\(n) 个聊天").font(.system(size: 12))
                        }
                        .foregroundStyle(Brand.muted)
                      }
                      if let date = project.lastChatDate {
                        Text("最后聊天：\(Self.lastChatDate.string(from: date))")
                          .font(.system(size: 12))
                          .foregroundStyle(Brand.muted)
                      }
                      Spacer()
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(14)
                  .capkaCard()
                }
                .buttonStyle(CapkaPressStyle())
                .contextMenu {
                  Button(role: .destructive) { deleteTarget = project } label: {
                    Label("删除项目", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
        .padding(16)
      }
    }
    .navigationTitle("项目")
    .capkaNavigationChrome()
    .toolbar {
      ToolbarItem(placement: .capkaTrailing) {
        Button { showCreate = true } label: {
          Label("新项目", systemImage: "plus")
        }
        .foregroundStyle(Brand.primary)
      }
    }
    .task {
      model.bind(session: session)
      await model.refresh()
    }
    .refreshable { await model.refresh() }
    .alert("新项目", isPresented: $showCreate) {
      TextField("名称", text: $newName)
      TextField("描述", text: $newDesc)
      Button("创建项目") {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
          _ = await model.create(name: name, description: newDesc.isEmpty ? nil : newDesc)
          newName = ""
          newDesc = ""
        }
      }
      Button("取消", role: .cancel) {}
    }
    .alert("删除项目", isPresented: Binding(
      get: { deleteTarget != nil },
      set: { if !$0 { deleteTarget = nil } }
    )) {
      Button("删除", role: .destructive) {
        if let id = deleteTarget?.id {
          Task { await model.delete(id: id) }
        }
        deleteTarget = nil
      }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("这将删除“\(deleteTarget?.name ?? "")”及其工作区。")
    }
  }
}

struct ProjectHubView: View {
  let project: ProjectSummary
  var onOpenChat: (String) -> Void

  private enum Tab: String, CaseIterable {
    case overview = "概述"
    case files = "文件"
    case chats = "聊天记录"
    case settings = "设置"
  }

  @State private var model: ProjectHubViewModel
  @State private var tab: Tab = .overview
  @State private var confirmDelete = false
  @Environment(\.dismiss) private var dismiss

  init(project: ProjectSummary, onOpenChat: @escaping (String) -> Void) {
    self.project = project
    self.onOpenChat = onOpenChat
    _model = State(initialValue: ProjectHubViewModel(project: project))
  }

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      VStack(spacing: 0) {
        tabBar

        switch tab {
        case .overview: overviewTab
        case .files: filesTab
        case .chats: chatsTab
        case .settings: settingsTab
        }
      }
    }
    .navigationTitle(model.name.isEmpty ? project.name : model.name)
    .capkaNavigationChrome()
    .toolbar {
      ToolbarItem(placement: .capkaTrailing) {
        Button("新聊天") {
          Task {
            if let id = await model.newChat() {
              onOpenChat(id)
              dismiss()
            }
          }
        }
        .fontWeight(.medium)
        .foregroundStyle(Brand.primary)
      }
    }
    .task { await model.load() }
    .alert("出错了", isPresented: Binding(
      get: { model.error != nil },
      set: { if !$0 { model.error = nil } }
    )) {
      Button("好", role: .cancel) { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .alert("删除项目", isPresented: $confirmDelete) {
      Button("删除", role: .destructive) {
        Task {
          if await model.deleteProject() { dismiss() }
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("工作区文件将被删除。聊天记录会保留。")
    }
  }

  private var tabBar: some View {
    HStack(spacing: 18) {
      ForEach(Tab.allCases, id: \.self) { item in
        Button {
          withAnimation(Motion.easeOut(0.22)) { tab = item }
        } label: {
          VStack(spacing: 6) {
            Text(item.rawValue)
              .font(.system(size: 14, weight: tab == item ? .medium : .regular))
              .foregroundStyle(tab == item ? Brand.ink : Brand.muted)
            Rectangle()
              .fill(tab == item ? Brand.primary : Color.clear)
              .frame(height: 2)
          }
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .background(Brand.cream)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Brand.line).frame(height: 1)
    }
  }

  private var overviewTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let d = project.description, !d.isEmpty {
          Text(d)
            .font(.system(size: 14))
            .foregroundStyle(Brand.muted)
        }

        infoCard(title: "工作空间") {
          HStack(spacing: 14) {
            Text("\(model.files.filter { !$0.isDirectory }.count) 个文件")
              .font(.system(size: 13))
              .foregroundStyle(Brand.muted)
            Text("\(model.files.filter(\.isDirectory).count) 个文件夹")
              .font(.system(size: 13))
              .foregroundStyle(Brand.muted)
            Spacer()
            Button("打开文件") { tab = .files }
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Brand.primary)
          }
        }

        infoCard(title: "最近的聊天记录") {
          VStack(spacing: 0) {
            if model.chats.isEmpty {
              Text("还没有聊天记录")
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.chats.prefix(6)) { chat in
              Button {
                onOpenChat(chat.id)
                dismiss()
              } label: {
                HStack {
                  Text(chat.title?.isEmpty == false ? chat.title! : "新聊天")
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.muted.opacity(0.6))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
              }
              .buttonStyle(CapkaPressStyle())
            }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("助理想起了什么")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Brand.muted)
          TextField("项目记忆", text: Binding(
            get: { model.memory },
            set: { model.memory = $0 }
          ), axis: .vertical)
          .font(.system(size: 14))
          .lineLimit(4...10)
          .padding(12)
          .capkaCard(radius: Brand.Radius.lg)
          Button("保存") { Task { await model.saveMemory() } }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Brand.primary)
        }
      }
      .padding(16)
    }
  }

  private var chatsTab: some View {
    ScrollView {
      VStack(spacing: 0) {
        if model.chats.isEmpty {
          Text("还没有聊天记录")
            .font(.system(size: 14))
            .foregroundStyle(Brand.muted)
            .padding(.top, 40)
        }
        ForEach(Array(model.chats.enumerated()), id: \.element.id) { index, chat in
          Button {
            onOpenChat(chat.id)
            dismiss()
          } label: {
            HStack {
              Text(chat.title?.isEmpty == false ? chat.title! : "新聊天")
                .font(.system(size: 15))
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
              Spacer()
              if chat.running == true {
                ProgressView().controlSize(.mini)
              }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
          }
          .buttonStyle(CapkaPressStyle())

          if index < model.chats.count - 1 {
            Divider().overlay(Brand.line).padding(.leading, 14)
          }
        }
      }
      .capkaCard()
      .padding(16)
    }
    .refreshable { await model.load() }
  }

  private var filesTab: some View {
    WorkspaceFilesView(chatId: nil, projectId: project.id, title: "文件")
  }

  private var settingsTab: some View {
    @Bindable var model = model
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        field(title: "名称") {
          TextField("名称", text: $model.name)
            .font(.system(size: 15))
        }
        field(title: "描述") {
          TextField("描述", text: $model.descriptionText, axis: .vertical)
            .font(.system(size: 15))
            .lineLimit(2...4)
        }
        field(title: "系统指令") {
          TextField("给助手的长期说明", text: $model.systemPrompt, axis: .vertical)
            .font(.system(size: 14, design: .monospaced))
            .lineLimit(4...12)
        }

        HStack(spacing: 12) {
          Button("保存") { Task { await model.saveSettings() } }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Brand.card)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Brand.primary)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          if let banner = model.savedBanner {
            Text(banner).font(.system(size: 12)).foregroundStyle(Brand.muted)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("删除项目")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Brand.ink)
          Text("工作区文件将被删除。聊天记录会保留。")
            .font(.system(size: 12))
            .foregroundStyle(Brand.muted)
          Button("删除项目", role: .destructive) { confirmDelete = true }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Brand.dangerSurface)
            .foregroundStyle(Brand.dangerText)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .stroke(Brand.dangerBorder, lineWidth: 1)
            )
        }
        .padding(14)
        .capkaCard()
      }
      .padding(16)
    }
  }

  private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.muted)
      content()
        .padding(12)
        .capkaCard(radius: Brand.Radius.lg)
    }
  }

  private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Brand.ink)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .capkaCard()
  }
}

// MARK: - Workspace files

struct WorkspaceFilesView: View {
  let chatId: String?
  let projectId: String?
  let title: String
  /// Pin a workspace file onto the chat composer (name + mime only — already on disk).
  var onAttachToChat: ((WorkspaceEntry) -> Void)?

  @State private var model: WorkspaceViewModel
  @State private var showImporter = false
  /// `.item` = multi file pick; `.folder` = single directory pick.
  @State private var importFolders = false
  @State private var preview = FilePreviewLoader()
  @State private var attachBanner: String?
  @State private var reloadTask: Task<Void, Never>?
  @State private var uploadingFolder = false

  init(
    chatId: String?,
    projectId: String?,
    title: String,
    onAttachToChat: ((WorkspaceEntry) -> Void)? = nil
  ) {
    self.chatId = chatId
    self.projectId = projectId
    self.title = title
    self.onAttachToChat = onAttachToChat
    _model = State(initialValue: WorkspaceViewModel(chatId: chatId, projectId: projectId))
  }

  private var fileCount: Int { model.visible.filter { !$0.isDirectory }.count }
  private var folderCount: Int { model.visible.filter(\.isDirectory).count }

  var body: some View {
    ZStack {
      Brand.cream.ignoresSafeArea()

      VStack(spacing: 0) {
        workspaceHeader

        if model.isLoading && model.entries.isEmpty {
          ProgressView().tint(Brand.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = model.error, model.entries.isEmpty {
          VStack(spacing: 10) {
            Text(err)
              .font(.system(size: 13))
              .foregroundStyle(Brand.muted)
              .multilineTextAlignment(.center)
            Button("重试") { Task { await model.load() } }
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Brand.primary)
          }
          .padding(24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visible.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "folder")
              .font(.system(size: 28, weight: .light))
              .foregroundStyle(Brand.muted.opacity(0.55))
            Text("暂无文件")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(Brand.ink)
            Text("助手生成的文档会出现在这里。也可点右上角上传文件或文件夹。")
              .font(.system(size: 12))
              .foregroundStyle(Brand.muted)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 28)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              Text(summaryLine)
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
                .padding(.horizontal, 4)

              VStack(spacing: 0) {
                ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, entry in
                  row(entry)
                  if index < model.visible.count - 1 {
                    Divider().overlay(Brand.line).padding(.leading, 52)
                  }
                }
              }
              .capkaCard()
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 20)
          }
        }
      }
    }
    .navigationTitle(title)
    .capkaNavigationChrome()
    .task { await model.load() }
    .refreshable { await model.load() }
    .onReceive(NotificationCenter.default.publisher(for: AppConfig.workspaceDidChangeNotification)) { note in
      // Someone else's session changing files is not a reason to reload ours;
      // debounce because a running turn posts one of these per tool call.
      if let scope = note.object as? String, scope != chatId, scope != projectId { return }
      reloadTask?.cancel()
      reloadTask = Task {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        await model.load()
      }
    }
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: importFolders ? [.folder] : [.item],
      allowsMultipleSelection: !importFolders
    ) { result in
      guard case .success(let urls) = result else { return }
      Task {
        if importFolders, let folder = urls.first {
          uploadingFolder = true
          defer { uploadingFolder = false }
          await model.uploadFolder(folderURL: folder)
        } else {
          for url in urls { await model.upload(fileURL: url) }
        }
      }
    }
    .filePreview(preview)
    .overlay(alignment: .bottom) {
      if let attachBanner {
        Text(attachBanner)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Brand.onPrimary)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Brand.primary)
          .clipShape(Capsule())
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(Motion.easeOut(0.22), value: attachBanner)
  }

  private var summaryLine: String {
    var parts: [String] = []
    if folderCount > 0 { parts.append("\(folderCount) 个文件夹") }
    if fileCount > 0 { parts.append("\(fileCount) 个文件") }
    return parts.isEmpty ? "空文件夹" : parts.joined(separator: " · ")
  }

  private var workspaceHeader: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        if model.canGoUp {
          Button {
            Task { await model.goUp() }
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Brand.ink)
              .frame(width: 32, height: 32)
              .background(Brand.accent)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          }
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(model.path == "." ? "根目录" : (model.path as NSString).lastPathComponent)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Brand.ink)
            .lineLimit(1)
          Text(model.path == "." ? "/" : model.path)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Brand.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Button {
          Task { await model.load() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Brand.muted)
            .frame(width: 32, height: 32)
        }
        .accessibilityLabel("刷新")

        Menu {
          Button {
            importFolders = false
            showImporter = true
          } label: {
            Label("上传文件", systemImage: "doc.badge.plus")
          }
          Button {
            importFolders = true
            showImporter = true
          } label: {
            Label("上传文件夹", systemImage: "folder.badge.plus")
          }
        } label: {
          Group {
            if uploadingFolder {
              ProgressView()
                .controlSize(.mini)
                .tint(Brand.onPrimary)
            } else {
              Image(systemName: "arrow.up.doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.onPrimary)
            }
          }
          .frame(width: 32, height: 32)
          .background(Brand.primary)
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
        }
        .disabled(uploadingFolder)
        .accessibilityLabel("上传")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)

      Divider().overlay(Brand.line)
    }
    .background(Brand.sidebar)
  }

  @ViewBuilder
  private func row(_ entry: WorkspaceEntry) -> some View {
    let content = HStack(spacing: 12) {
      FileGlyph(kind: .of(entry.name, isDirectory: entry.isDirectory))
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.name)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Brand.ink)
          .lineLimit(1)
        if entry.isDirectory {
          Text("文件夹")
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted)
        } else if let size = entry.size {
          Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            .font(.system(size: 11))
            .foregroundStyle(Brand.muted)
        }
      }
      Spacer(minLength: 6)
      if entry.isDirectory {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Brand.muted.opacity(0.6))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .contentShape(Rectangle())

    if entry.isDirectory {
      Button { Task { await model.open(entry) } } label: { content }
        .buttonStyle(CapkaPressStyle())
    } else {
      HStack(spacing: 0) {
        Button {
          preview.open(
            chatId: chatId,
            projectId: projectId,
            path: entry.path,
            name: entry.name,
            size: entry.size,
            modifiedAt: entry.modifiedAt
          )
        } label: {
          content
        }
        .buttonStyle(CapkaPressStyle())

        // The plus must do what it looks like it does — attach, not preview.
        if onAttachToChat != nil {
          Button { attachToChat(entry) } label: {
            Image(systemName: "plus.circle")
              .font(.system(size: 17))
              .foregroundStyle(Brand.muted.opacity(0.7))
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(CapkaPressStyle())
          .accessibilityLabel("添加到对话")
        }
      }
      .contextMenu {
        Button {
          preview.open(
            chatId: chatId,
            projectId: projectId,
            path: entry.path,
            name: entry.name,
            size: entry.size,
            modifiedAt: entry.modifiedAt
          )
        } label: {
          Label("打开", systemImage: "eye")
        }
        if onAttachToChat != nil {
          Button { attachToChat(entry) } label: {
            Label("添加到对话", systemImage: "text.badge.plus")
          }
        }
      }
    }
  }

  private func attachToChat(_ entry: WorkspaceEntry) {
    guard let onAttachToChat else { return }
    onAttachToChat(entry)
    attachBanner = "已添加到对话 · \(entry.name)"
    Task {
      try? await Task.sleep(nanoseconds: 1_600_000_000)
      if attachBanner?.contains(entry.name) == true { attachBanner = nil }
    }
  }
}
