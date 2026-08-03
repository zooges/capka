import SwiftUI

/// The project a chat runs in, chosen from the composer.
///
/// This is not a label. Sessions are keyed by `projectId ?? chatId`, so picking a
/// project puts the conversation in that project's shared sandbox and workspace
/// alongside its other chats — the agent starts with those files and that
/// project's instructions already in hand. Putting the control at the composer,
/// next to the attach button, is what makes that legible: you choose the context
/// in the same place you choose the file and the model.
struct ProjectChip: View {
  let name: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: name == nil ? "folder.badge.plus" : "folder.fill")
          .font(.system(size: 12))
        Text(name ?? "选择项目")
          .font(.system(size: 12, weight: name == nil ? .regular : .medium))
          .lineLimit(1)
      }
      .foregroundStyle(name == nil ? Brand.muted : Brand.ink)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(name == nil ? Color.clear : Brand.accent)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Brand.line, lineWidth: name == nil ? 1 : 0))
    }
    .buttonStyle(CapkaPressStyle())
    .accessibilityLabel(name.map { "项目：\($0)" } ?? "选择项目")
  }
}

/// Tapping the chip opens this: pick a project when none is set, or work with
/// the current one. Both live in one sheet so the chip has a single, predictable
/// destination rather than two behaviours the user has to learn.
struct ProjectContextSheet: View {
  let currentId: String?
  let currentName: String?
  /// nil clears the project (the chat runs in its own sandbox).
  let onSelect: (ProjectSummary?) -> Void
  let onOpenFiles: (ProjectSummary) -> Void
  let onOpenChat: (String) -> Void
  let onClose: () -> Void

  @State private var model = ProjectsViewModel()
  @Environment(SessionStore.self) private var session
  @State private var showCreate = false
  @State private var newName = ""

  private var current: ProjectSummary? {
    model.projects.first { $0.id == currentId }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let current {
              currentProjectCard(current)
            }
            projectList
          }
          .padding(16)
          .padding(.bottom, 28)
        }
      }
      .navigationTitle(current == nil ? "选择项目" : "项目")
      .capkaNavigationChrome()
      .toolbar {
        ToolbarItem(placement: .capkaLeading) {
          Button("完成", action: onClose).foregroundStyle(Brand.primary)
        }
        ToolbarItem(placement: .capkaTrailing) {
          Button { showCreate = true } label: { Image(systemName: "plus") }
            .foregroundStyle(Brand.primary)
        }
      }
      .task {
        model.bind(session: session)
        await model.refresh()
      }
      .alert("新建项目", isPresented: $showCreate) {
        TextField("项目名称", text: $newName)
        Button("创建") {
          let name = newName
          newName = ""
          Task {
            if let created = await model.create(name: name, description: nil) {
              onSelect(created)
            }
          }
        }
        Button("取消", role: .cancel) { newName = "" }
      } message: {
        Text("同一项目下的聊天共用一个沙箱与工作区。")
      }
    }
  }

  /// What the project gives this conversation, and the ways into it. These are
  /// the same surfaces the project hub has — brought to where the chat is,
  /// instead of three levels away in the sidebar.
  private func currentProjectCard(_ project: ProjectSummary) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(project.name)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Brand.ink)
        if let description = project.description, !description.isEmpty {
          Text(description)
            .font(.system(size: 12))
            .foregroundStyle(Brand.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text("\(project.chatCount ?? 0) 个聊天 · 共用沙箱与工作区")
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 12)

      Divider().overlay(Brand.line)

      row(icon: "folder", title: "项目文件", hint: "本项目所有聊天共用") {
        onOpenFiles(project)
      }
      Divider().overlay(Brand.line).padding(.leading, 44)
      NavigationLink {
        ProjectHubView(project: project, onOpenChat: onOpenChat)
      } label: {
        rowLabel(icon: "slider.horizontal.3", title: "项目设置与记忆", hint: "指令、默认模型、长期记忆")
      }
      .buttonStyle(CapkaPressStyle())

      Divider().overlay(Brand.line).padding(.leading, 44)

      row(icon: "xmark.circle", title: "不使用项目", hint: "新聊天将使用自己的沙箱", destructive: true) {
        onSelect(nil)
      }
    }
    .padding(14)
    .capkaCard()
  }

  private var projectList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(current == nil ? "选择一个项目" : "切换到")
        .font(.system(size: 13))
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)

      if model.projects.isEmpty {
        Text(model.isLoading ? "正在加载…" : "还没有项目，右上角可以新建。")
          .font(.system(size: 13))
          .foregroundStyle(Brand.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .capkaCard()
      } else {
        VStack(spacing: 0) {
          let others = model.projects.filter { $0.id != currentId }
          ForEach(Array(others.enumerated()), id: \.element.id) { index, project in
            Button {
              onSelect(project)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "folder")
                  .font(.system(size: 14))
                  .foregroundStyle(Brand.muted)
                  .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                  Text(project.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.ink)
                  Text("\(project.chatCount ?? 0) 个聊天")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 8)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
              .contentShape(Rectangle())
            }
            .buttonStyle(CapkaPressStyle())
            if index < others.count - 1 {
              Divider().overlay(Brand.line).padding(.leading, 46)
            }
          }
        }
        .capkaCard()
      }
    }
  }

  private func row(
    icon: String,
    title: String,
    hint: String,
    destructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      rowLabel(icon: icon, title: title, hint: hint, destructive: destructive)
    }
    .buttonStyle(CapkaPressStyle())
  }

  private func rowLabel(
    icon: String,
    title: String,
    hint: String,
    destructive: Bool = false
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(destructive ? Brand.dangerText : Brand.muted)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15))
          .foregroundStyle(destructive ? Brand.dangerText : Brand.ink)
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(Brand.muted)
      }
      Spacer(minLength: 8)
      if !destructive {
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Brand.muted.opacity(0.6))
      }
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}
