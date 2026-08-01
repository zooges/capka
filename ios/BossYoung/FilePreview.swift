import QuickLook
import SwiftUI
import UIKit

/// Downloads a workspace file and hands it to Quick Look. Everything the agent
/// produces — docx, xlsx, pdf, images — opens in-app instead of forcing a detour
/// through the share sheet, which couldn't fetch the authenticated URL anyway.
@MainActor
@Observable
final class FilePreviewLoader {
  struct Target: Identifiable, Equatable {
    let id = UUID()
    let url: URL
  }

  var ready: Target?
  var isLoading = false
  var error: String?
  /// Set when the user chooses 批注 on the previewed file.
  var markupTarget: Target?
  /// Where an annotated copy is uploaded back to.
  var uploadChatId: String?
  var uploadProjectId: String?

  private var task: Task<Void, Never>?
  /// Guards against a superseded download clearing the spinner the newer one
  /// just raised, when a user taps two files in quick succession.
  private var generation = 0

  func open(chatId: String? = nil, projectId: String? = nil, path: String, name: String) {
    task?.cancel()
    generation &+= 1
    let token = generation
    isLoading = true
    error = nil
    task = Task { [weak self] in
      defer { if self?.generation == token { self?.isLoading = false } }
      do {
        let url = try await CapkaAPIClient.shared.downloadToTemp(
          chatId: chatId,
          projectId: projectId,
          path: path,
          filename: name
        )
        self?.uploadChatId = chatId
        self?.uploadProjectId = projectId
        guard self?.generation == token else { return }
        self?.ready = Target(url: url)
      } catch {
        guard self?.generation == token, !Task.isCancelled else { return }
        self?.error = error.localizedDescription
      }
    }
  }
}

extension FilePreviewLoader {
  /// Only a page-shaped file can be annotated; a spreadsheet has no canvas.
  static func canMarkUp(_ url: URL) -> Bool {
    ["pdf", "png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
  }

  /// Upload the annotated copy beside the original. It is a new file, never an
  /// overwrite — a markup pass is an opinion about a draft, not a correction.
  func uploadMarkup(_ url: URL) async {
    do {
      _ = try await CapkaAPIClient.shared.uploadFile(
        chatId: uploadChatId,
        projectId: uploadProjectId,
        fileURL: url
      )
      try? FileManager.default.removeItem(at: url)
    } catch {
      self.error = error.localizedDescription
    }
  }
}

extension View {
  /// Attaches the progress overlay, Quick Look sheet, and failure alert driven
  /// by `loader`. Put it on the screen that owns the loader, once.
  func filePreview(_ loader: FilePreviewLoader) -> some View {
    modifier(FilePreviewModifier(loader: loader))
  }
}

private struct FilePreviewModifier: ViewModifier {
  @Bindable var loader: FilePreviewLoader

  func body(content: Content) -> some View {
    content
      .overlay {
        if loader.isLoading {
          ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 10) {
              ProgressView().tint(Brand.primary)
              Text("正在打开…")
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
            }
            .padding(22)
            .capkaCard(radius: Brand.Radius.lg)
          }
          .transition(.opacity)
        }
      }
      .animation(Motion.easeOut(0.2), value: loader.isLoading)
      .sheet(item: $loader.ready) { target in
        QuickLookSheet(
          url: target.url,
          onDone: { loader.ready = nil },
          onMarkUp: FilePreviewLoader.canMarkUp(target.url)
            ? {
              loader.ready = nil
              loader.markupTarget = target
            }
            : nil
        )
        .ignoresSafeArea()
      }
      .sheet(item: $loader.markupTarget) { target in
        MarkupView(fileURL: target.url) { annotated in
          loader.markupTarget = nil
          guard let annotated else { return }
          Task { await loader.uploadMarkup(annotated) }
        }
      }
      .alert("无法预览", isPresented: Binding(
        get: { loader.error != nil },
        set: { if !$0 { loader.error = nil } }
      )) {
        Button("好", role: .cancel) { loader.error = nil }
      } message: {
        Text(loader.error ?? "")
      }
  }
}

/// `QLPreviewController` only grows its own 完成 button when UIKit presents it as
/// the modal root; inside a SwiftUI sheet it's a child, so wrap it in a nav
/// controller and add the button ourselves. Quick Look supplies the share action.
private struct QuickLookSheet: UIViewControllerRepresentable {
  let url: URL
  let onDone: () -> Void
  var onMarkUp: (() -> Void)?

  func makeUIViewController(context: Context) -> UINavigationController {
    let preview = QLPreviewController()
    preview.dataSource = context.coordinator
    preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "完成",
      style: .done,
      target: context.coordinator,
      action: #selector(Coordinator.done)
    )
    if onMarkUp != nil {
      preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: "批注",
        style: .plain,
        target: context.coordinator,
        action: #selector(Coordinator.markUp)
      )
    }
    return UINavigationController(rootViewController: preview)
  }

  func updateUIViewController(_ controller: UINavigationController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url, onDone: onDone, onMarkUp: onMarkUp)
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    private let item: PreviewItem
    private let onDone: () -> Void
    private let onMarkUp: (() -> Void)?

    init(url: URL, onDone: @escaping () -> Void, onMarkUp: (() -> Void)?) {
      item = PreviewItem(url: url)
      self.onDone = onDone
      self.onMarkUp = onMarkUp
    }

    @objc func markUp() { onMarkUp?() }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
      item
    }

    @objc func done() { onDone() }
  }
}

private final class PreviewItem: NSObject, QLPreviewItem {
  let previewItemURL: URL?
  let previewItemTitle: String?

  init(url: URL) {
    previewItemURL = url
    previewItemTitle = url.lastPathComponent
    super.init()
  }
}
