import SwiftUI

/// Drawer that mirrors the web `app-sidebar.tsx`: brand header, new chat,
/// search, projects, pinned chats, date-grouped recents, account footer.
struct SidebarView: View {
  @Environment(SessionStore.self) private var session
  @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue

  let list: ChatListViewModel
  let currentChatId: String?
  let safeAreaTop: CGFloat
  let safeAreaBottom: CGFloat

  var onNewChat: () -> Void
  var onOpenChat: (String) -> Void
  var onOpenProjects: () -> Void
  var onOpenArchived: () -> Void
  var onOpenSettings: () -> Void
  var onClose: () -> Void
  var onRename: (ChatSummary) -> Void
  var onMove: (ChatSummary) -> Void

  @State private var search = ""
  @State private var searchTask: Task<Void, Never>?
  @State private var deleteTarget: ChatSummary?
  @State private var showAccountMenu = false
  @FocusState private var searchFocused: Bool

  private var theme: ThemePreference {
    ThemePreference(rawValue: themeRaw) ?? .system
  }

  private static let groupOrder = ["今天", "昨天", "本周", "更早"]

  private var pinned: [ChatSummary] { list.chats.filter { $0.pinned == true } }

  private var groups: [(String, [ChatSummary])] {
    let rest = list.chats.filter { $0.pinned != true }
    let dict = Dictionary(grouping: rest, by: \.dateGroup)
    return Self.groupOrder.compactMap { key in
      guard let items = dict[key], !items.isEmpty else { return nil }
      return (key, items)
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear.frame(height: safeAreaTop)

        header
        newChatButton
        searchField

        Divider().overlay(Brand.line).padding(.top, 4)

        content

        Divider().overlay(Brand.line)
        accountFooter
      }

      if showAccountMenu {
        Color.black.opacity(0.18)
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(Motion.easeOut(0.2)) { showAccountMenu = false }
          }

        accountMenuCard
          .padding(.horizontal, 10)
          .padding(.bottom, max(8, safeAreaBottom))
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(3)
      }
    }
    .background(Brand.sidebar)
    .animation(Motion.easeOut(0.22), value: showAccountMenu)
    .onDisappear {
      searchTask?.cancel()
      showAccountMenu = false
      // The drawer is torn down on close; drop any active filter so the home
      // screen's "最近" list isn't left showing search results.
      if !search.isEmpty {
        Task { await list.refreshQuietly() }
      }
    }
    .alert("删除聊天记录", isPresented: Binding(
      get: { deleteTarget != nil },
      set: { if !$0 { deleteTarget = nil } }
    )) {
      Button("删除", role: .destructive) {
        if let id = deleteTarget?.id {
          Task { await list.deleteChat(chatId: id) }
        }
        deleteTarget = nil
      }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("这将永久删除“\(deleteTarget?.title ?? "新聊天")”及其所有消息。")
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      Image("BrandMark")
        .resizable()
        .scaledToFit()
        .frame(width: 28, height: 28)
      Text(Brand.productName)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Brand.ink)
        .lineLimit(1)
      Spacer(minLength: 4)
      Button(action: onClose) {
        Image(systemName: "sidebar.leading")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Brand.muted)
          .frame(width: 32, height: 32)
      }
      .accessibilityLabel("关闭侧边栏")
    }
    .padding(.horizontal, 14)
    .padding(.top, 6)
    .padding(.bottom, 6)
  }

  private var newChatButton: some View {
    Button(action: onNewChat) {
      HStack(spacing: 10) {
        Image(systemName: "plus")
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 16)
        Text("新聊天").font(.system(size: 14, weight: .medium))
        Spacer()
      }
      .foregroundStyle(Brand.ink)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .padding(.horizontal, 8)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13))
        .foregroundStyle(Brand.muted)
      TextField("搜索聊天记录...", text: $search)
        .font(.system(size: 14))
        .submitLabel(.search)
        .autocorrectionDisabled()
        .focused($searchFocused)
      if !search.isEmpty {
        Button {
          search = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Brand.accent)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
    .padding(.horizontal, 12)
    .padding(.top, 2)
    .padding(.bottom, 8)
    .onChange(of: search) { _, value in
      searchTask?.cancel()
      searchTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await list.refreshFiltered(search: value.isEmpty ? nil : value)
      }
    }
  }

  // MARK: - Body

  @ViewBuilder
  private var content: some View {
    if list.isLoading && list.chats.isEmpty {
      ProgressView().tint(Brand.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let err = list.error, list.chats.isEmpty {
      VStack(spacing: 12) {
        Text(err)
          .font(.footnote)
          .foregroundStyle(Brand.muted)
          .multilineTextAlignment(.center)
        Button("重试") { Task { await list.refresh() } }
          .foregroundStyle(Brand.primary)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if list.chats.isEmpty {
      VStack(spacing: 10) {
        Image("BrandMark")
          .resizable()
          .scaledToFit()
          .frame(width: 28, height: 28)
          .opacity(0.35)
        Text(search.isEmpty ? "开始新的聊天" : "没有找到聊天记录")
          .font(.footnote)
          .foregroundStyle(Brand.muted)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
          navRow(title: "项目", icon: "folder", action: onOpenProjects)
          navRow(title: "已归档", icon: "archivebox", action: onOpenArchived)

          if !pinned.isEmpty {
            Section {
              ForEach(pinned) { row in chatRow(row) }
            } header: {
              groupLabel("已固定")
            }
          }

          ForEach(groups, id: \.0) { title, items in
            Section {
              ForEach(items) { row in chatRow(row) }
            } header: {
              groupLabel(title)
            }
          }

          // Paging uses the unfiltered endpoint, so only offer it outside search.
          if list.nextCursor != nil && search.isEmpty {
            ProgressView()
              .controlSize(.small)
              .tint(Brand.muted)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .onAppear { Task { await list.loadMore() } }
          }
        }
        .padding(.bottom, 12)
      }
    }
  }

  private func groupLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Brand.muted)
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Brand.sidebar)
  }

  private func navRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 13))
          .frame(width: 16)
        Text(title).font(.system(size: 14))
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Brand.muted)
      }
      .foregroundStyle(Brand.ink)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .padding(.horizontal, 8)
  }

  @ViewBuilder
  private func chatRow(_ row: ChatSummary) -> some View {
    Button {
      onOpenChat(row.id)
    } label: {
      SidebarChatRow(chat: row, selected: row.id == currentChatId)
    }
    .buttonStyle(CapkaPressStyle())
    .contextMenu {
      Button { onRename(row) } label: { Label("重命名", systemImage: "pencil") }
      Button {
        Task { await list.setPinned(chatId: row.id, pinned: !(row.pinned == true)) }
      } label: {
        Label(row.pinned == true ? "取消固定" : "固定", systemImage: row.pinned == true ? "pin.slash" : "pin")
      }
      Button { onMove(row) } label: { Label("移至项目", systemImage: "folder") }
      Button {
        Task { await list.setArchived(chatId: row.id, archived: true) }
      } label: {
        Label("存档", systemImage: "archivebox")
      }
      Button(role: .destructive) { deleteTarget = row } label: {
        Label("删除", systemImage: "trash")
      }
    }
  }

  // MARK: - Footer + account menu (web dropdown)

  private var accountFooter: some View {
    Button {
      withAnimation(Motion.easeOut(0.22)) { showAccountMenu.toggle() }
    } label: {
      HStack(spacing: 10) {
        ZStack {
          Circle().fill(Brand.accent).frame(width: 28, height: 28)
          Text(String(session.user?.name.prefix(1) ?? "?"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Brand.ink)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(session.user?.name ?? "账户")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Brand.ink)
            .lineLimit(1)
          if let email = session.user?.email, !email.isEmpty {
            Text(email)
              .font(.system(size: 11))
              .foregroundStyle(Brand.muted)
              .lineLimit(1)
          }
        }
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Brand.muted)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .padding(.bottom, max(0, safeAreaBottom - 6))
      .contentShape(Rectangle())
    }
    .buttonStyle(CapkaPressStyle())
  }

  private var accountMenuCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let user = session.user {
        VStack(alignment: .leading, spacing: 2) {
          Text(user.name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Brand.ink)
          if let email = user.email, !email.isEmpty {
            Text(email)
              .font(.system(size: 12))
              .foregroundStyle(Brand.muted)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        Divider().overlay(Brand.line)
      }

      menuRow(icon: "magnifyingglass", title: "搜索") {
        showAccountMenu = false
        searchFocused = true
      }
      menuRow(icon: "folder", title: "项目") {
        showAccountMenu = false
        onOpenProjects()
      }
      menuRow(icon: "archivebox", title: "已归档") {
        showAccountMenu = false
        onOpenArchived()
      }

      themeMenuBlock

      Divider().overlay(Brand.line).padding(.vertical, 4)

      menuRow(icon: "gearshape", title: "设置") {
        showAccountMenu = false
        onOpenSettings()
      }
      Button {
        showAccountMenu = false
        Task { await session.signOut() }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "rectangle.portrait.and.arrow.right")
            .font(.system(size: 14))
            .frame(width: 18)
          Text("退出登录")
            .font(.system(size: 14))
          Spacer()
        }
        .foregroundStyle(Brand.dangerText)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
      }
      .buttonStyle(CapkaPressStyle())
    }
    .background(Brand.card)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous)
        .stroke(Brand.line, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
  }

  private var themeMenuBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: theme.icon)
          .font(.system(size: 14))
          .frame(width: 18)
        Text("外观")
          .font(.system(size: 14))
        Spacer()
      }
      .foregroundStyle(Brand.ink)
      .padding(.horizontal, 14)
      .padding(.top, 10)
      .padding(.bottom, 4)

      HStack(spacing: 6) {
        ForEach(ThemePreference.allCases) { pref in
          Button {
            themeRaw = pref.rawValue
          } label: {
            HStack(spacing: 4) {
              Image(systemName: pref.icon)
                .font(.system(size: 11))
              Text(pref.label)
                .font(.system(size: 12, weight: theme == pref ? .semibold : .regular))
            }
            .foregroundStyle(theme == pref ? Brand.ink : Brand.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(theme == pref ? Brand.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .stroke(Brand.line, lineWidth: theme == pref ? 0 : 1)
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 10)
    }
  }

  private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 14))
          .frame(width: 18)
        Text(title)
          .font(.system(size: 14))
        Spacer()
      }
      .foregroundStyle(Brand.ink)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(CapkaPressStyle())
  }
}

struct SidebarChatRow: View {
  let chat: ChatSummary
  let selected: Bool

  var body: some View {
    HStack(spacing: 8) {
      if chat.running == true {
        ProgressView().controlSize(.mini).tint(Brand.muted)
      } else if chat.unread == true && !selected {
        Circle().fill(Brand.primary).frame(width: 7, height: 7)
      }

      Text(chat.title?.isEmpty == false ? chat.title! : "新聊天")
        .font(.system(size: 14, weight: selected ? .medium : .regular))
        .foregroundStyle(Brand.ink)
        .lineLimit(1)

      Spacer(minLength: 4)

      if let project = chat.projectName, !project.isEmpty {
        HStack(spacing: 3) {
          Image(systemName: "folder")
            .font(.system(size: 9))
          Text(project)
            .font(.system(size: 11))
            .lineLimit(1)
        }
        .foregroundStyle(Brand.muted.opacity(0.8))
        .frame(maxWidth: 100, alignment: .trailing)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? Brand.accent : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
    .padding(.horizontal, 8)
    .contentShape(Rectangle())
  }
}
