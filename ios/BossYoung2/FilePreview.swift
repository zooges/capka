import SwiftUI
#if os(iOS)
  import QuickLook
  import UIKit
#endif

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
  var successBanner: String?
  /// Set when the user chooses 批注 on the previewed file.
  var markupTarget: Target?
  /// Where an annotated copy is uploaded back to.
  var uploadChatId: String?
  var uploadProjectId: String?

  private var task: Task<Void, Never>?
  /// Guards against a superseded download clearing the spinner the newer one
  /// just raised, when a user taps two files in quick succession.
  private var generation = 0

  func open(
    chatId: String? = nil,
    projectId: String? = nil,
    path: String,
    name: String,
    size: Int64? = nil,
    modifiedAt: String? = nil
  ) {
    task?.cancel()
    generation &+= 1
    let token = generation
    if let hit = PreviewDiskCache.lookup(
      chatId: chatId,
      projectId: projectId,
      path: path,
      filename: name,
      size: size,
      modifiedAt: modifiedAt
    ) {
      uploadChatId = chatId
      uploadProjectId = projectId
      ready = Target(url: hit)
      return
    }
    isLoading = true
    error = nil
    task = Task { [weak self] in
      defer { if self?.generation == token { self?.isLoading = false } }
      do {
        let url = try await CapkaAPIClient.shared.downloadToTemp(
          chatId: chatId,
          projectId: projectId,
          path: path,
          filename: name,
          size: size,
          modifiedAt: modifiedAt
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
      let uploaded = try await CapkaAPIClient.shared.uploadFile(
        chatId: uploadChatId,
        projectId: uploadProjectId,
        fileURL: url
      )
      try? FileManager.default.removeItem(at: url)
      successBanner = "已保存「\(uploaded.name)」"
      NotificationCenter.default.post(
        name: AppConfig.workspaceDidChangeNotification,
        object: uploadChatId ?? uploadProjectId
      )
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

#if os(iOS)

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
              Text("正在下载文件…")
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
      .alert("批注已保存", isPresented: Binding(
        get: { loader.successBanner != nil },
        set: { if !$0 { loader.successBanner = nil } }
      )) {
        Button("好", role: .cancel) { loader.successBanner = nil }
      } message: {
        Text(loader.successBanner ?? "")
      }
  }
}

/// `QLPreviewController` only grows its own 完成 button when UIKit presents it as
/// the modal root; inside a SwiftUI sheet it's a child, so wrap it in a nav
/// controller and add the button ourselves. Quick Look supplies the share action.
///
/// Native QL markup is disabled — Capka's 批注 is the only annotation path, so
/// the lawyer never sees two pencils that save in different places.
private struct QuickLookSheet: UIViewControllerRepresentable {
  let url: URL
  let onDone: () -> Void
  var onMarkUp: (() -> Void)?

  func makeUIViewController(context: Context) -> UINavigationController {
    let preview = QLPreviewController()
    preview.dataSource = context.coordinator
    preview.delegate = context.coordinator
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

  final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
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

    func previewController(
      _ controller: QLPreviewController,
      editingModeFor previewItem: QLPreviewItem
    ) -> QLPreviewItemEditingMode {
      .disabled
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

#endif

#if os(macOS)

/// macOS has no Quick Look *sheet* — a file opens in whatever the Finder would
/// use. The loader is unchanged; only the presentation differs, so every call
/// site keeps the one `filePreview(_:)` vocabulary.
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
              Text("正在下载文件…")
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
            }
            .padding(22)
            .capkaCard(radius: Brand.Radius.lg)
          }
        }
      }
      .onChange(of: loader.ready) { _, target in
        guard let target else { return }
        Platform.openInDefaultApp(target.url)
        loader.ready = nil
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

#endif
