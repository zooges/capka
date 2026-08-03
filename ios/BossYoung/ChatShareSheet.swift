import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Mirrors the web chat share dialog: private / link / logged-in users, with a
/// copyable `/share/<token>` URL once published.
struct ChatShareSheet: View {
  let chat: ChatSummary
  var onUpdated: (ChatSummary) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var visibility: String
  @State private var shareToken: String?
  @State private var saving = false
  @State private var error: String?
  @State private var copied = false

  init(chat: ChatSummary, onUpdated: @escaping (ChatSummary) -> Void) {
    self.chat = chat
    self.onUpdated = onUpdated
    _visibility = State(initialValue: chat.visibility ?? "private")
    _shareToken = State(initialValue: chat.shareToken)
  }

  private var shareURL: URL? {
    guard let token = shareToken, !token.isEmpty else { return nil }
    return AppConfig.baseURL.appendingPathComponent("share/\(token)")
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("选择谁可以通过链接查看此对话")
          .font(.system(size: 14))
          .foregroundStyle(Brand.muted)

        VStack(spacing: 8) {
          option(
            value: "private",
            icon: "lock.fill",
            title: "仅自己",
            hint: "只有你可以查看"
          )
          option(
            value: "link",
            icon: "globe",
            title: "任何有链接的人",
            hint: "即使没有账户也可以查看"
          )
          option(
            value: "users",
            icon: "person.2.fill",
            title: "仅登录用户",
            hint: "需要本站账户才能查看"
          )
        }

        if visibility != "private", let shareURL {
          HStack(spacing: 8) {
            Text(shareURL.absoluteString)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(Brand.ink)
              .lineLimit(2)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              Platform.copyToPasteboard(shareURL.absoluteString)
              copied = true
              Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                copied = false
              }
            } label: {
              Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.primary)
                .frame(width: 36, height: 36)
                .background(Brand.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel(copied ? "已复制" : "复制链接")
          }
          .padding(10)
          .background(Brand.cream, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        if visibility != "private" {
          Button {
            Task { await setVisibility("private") }
          } label: {
            Text("取消发布")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(Brand.muted)
          }
          .disabled(saving)
        }

        if let error {
          Text(error)
            .font(.system(size: 13))
            .foregroundStyle(.red)
        }

        Spacer(minLength: 0)
      }
      .padding(20)
      .background(Brand.cream.ignoresSafeArea())
      .navigationTitle("分享对话")
      .capkaNavigationChrome()
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("完成") { dismiss() }.foregroundStyle(Brand.primary)
        }
      }
      .overlay {
        if saving {
          ProgressView()
            .controlSize(.regular)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
    }
  }

  private func option(value: String, icon: String, title: String, hint: String) -> some View {
    let active = visibility == value
    return Button {
      Task { await setVisibility(value) }
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 14))
          .foregroundStyle(Brand.muted)
          .frame(width: 20)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Brand.ink)
          Text(hint)
            .font(.system(size: 12))
            .foregroundStyle(Brand.muted)
        }
        Spacer(minLength: 4)
        if active {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.primary)
            .padding(.top, 2)
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(active ? Brand.accent : Brand.sidebar)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(active ? Brand.primary.opacity(0.35) : Brand.line, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(saving)
  }

  private func setVisibility(_ next: String) async {
    guard next != visibility || (next != "private" && shareToken == nil) else { return }
    let previous = visibility
    saving = true
    error = nil
    visibility = next
    defer { saving = false }
    do {
      let result = try await CapkaAPIClient.shared.patchChat(id: chat.id, visibility: next)
      if let v = result.visibility { visibility = v }
      if let token = result.shareToken { shareToken = token }
      onUpdated(
        ChatSummary.mutated(
          chat,
          visibility: result.visibility ?? next,
          shareToken: result.shareToken ?? shareToken
        )
      )
    } catch {
      visibility = previous
      self.error = "无法更新访问权限"
    }
  }
}

/// Temp file handed to the system share sheet after a Markdown export.
struct ChatExportItem: Identifiable {
  let id = UUID()
  let url: URL
}

#if os(iOS)
struct ActivityShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
