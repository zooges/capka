import PDFKit
import PencilKit
import SwiftUI
import UIKit

/// Annotate a file the agent produced and hand the marked-up copy back.
///
/// This is the review half of the loop the app was missing: the agent writes a
/// draft, the lawyer circles the two clauses that are wrong, and the annotated
/// copy goes back into the workspace as a NEW file — the original is never
/// overwritten, because a markup pass is an opinion about a draft, not a
/// correction of it.
struct MarkupView: View {
  let fileURL: URL
  /// Called with the flattened PDF, or nil on cancel.
  let onFinish: (URL?) -> Void

  @State private var pageIndex = 0
  @State private var isSaving = false
  @State private var pages: [UIImage] = []
  /// One drawing per page — never share a single PKDrawing across pages.
  @State private var drawings: [PKDrawing] = []

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()

        if pages.isEmpty {
          ProgressView().tint(Brand.primary)
        } else {
          // `id: pageIndex` forces a fresh canvas binding when the page flips,
          // so strokes from page N cannot leak into page N+1.
          MarkupCanvas(
            background: pages[pageIndex],
            drawing: Binding(
              get: { drawings.indices.contains(pageIndex) ? drawings[pageIndex] : PKDrawing() },
              set: { if drawings.indices.contains(pageIndex) { drawings[pageIndex] = $0 } }
            )
          )
          .id(pageIndex)
          .ignoresSafeArea(edges: .bottom)
        }
      }
      .navigationTitle(pages.count > 1 ? "批注 · 第 \(pageIndex + 1) / \(pages.count) 页" : "批注")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Brand.cream, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { onFinish(nil) }.foregroundStyle(Brand.muted)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(isSaving ? "保存中…" : "保存") { save() }
            .fontWeight(.semibold)
            .foregroundStyle(Brand.primary)
            .disabled(isSaving || pages.isEmpty)
        }
        if pages.count > 1 {
          ToolbarItemGroup(placement: .bottomBar) {
            Button { turn(-1) } label: { Image(systemName: "chevron.left") }
              .disabled(pageIndex == 0)
            Spacer()
            Text("\(pageIndex + 1) / \(pages.count)")
              .font(.system(size: 13))
              .foregroundStyle(Brand.muted)
            Spacer()
            Button { turn(1) } label: { Image(systemName: "chevron.right") }
              .disabled(pageIndex >= pages.count - 1)
          }
        }
      }
      .task { load() }
    }
  }

  private func turn(_ delta: Int) {
    pageIndex = max(0, min(pages.count - 1, pageIndex + delta))
  }

  private func load() {
    let rendered = Self.render(fileURL: fileURL, limit: 30)
    pages = rendered
    drawings = Array(repeating: PKDrawing(), count: rendered.count)
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    let output = Self.flatten(
      pages: pages,
      drawings: drawings,
      name: fileURL.deletingPathExtension().lastPathComponent
    )
    onFinish(output)
  }

  private static func render(fileURL: URL, limit: Int) -> [UIImage] {
    if let document = PDFDocument(url: fileURL) {
      return (0..<min(document.pageCount, limit)).compactMap { index in
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
          UIColor.white.setFill()
          context.fill(CGRect(origin: .zero, size: size))
          context.cgContext.translateBy(x: 0, y: size.height)
          context.cgContext.scaleBy(x: 2, y: -2)
          page.draw(with: .mediaBox, to: context.cgContext)
        }
      }
    }
    if let image = UIImage(contentsOfFile: fileURL.path) {
      return [image]
    }
    return []
  }

  private static func flatten(pages: [UIImage], drawings: [PKDrawing], name: String) -> URL? {
    guard !pages.isEmpty else { return nil }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("capka-attach", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(name)-批注.pdf")

    let renderer = UIGraphicsPDFRenderer(bounds: .zero)
    do {
      try renderer.writePDF(to: url) { context in
        for (index, page) in pages.enumerated() {
          let bounds = CGRect(origin: .zero, size: page.size)
          context.beginPage(withBounds: bounds, pageInfo: [:])
          page.draw(in: bounds)
          guard index < drawings.count, !drawings[index].bounds.isNull else { continue }
          // Strokes live in the same coordinate space as the background image
          // (canvas is laid out 1:1 with the page pixels).
          drawings[index].image(from: bounds, scale: 1).draw(in: bounds)
        }
      }
    } catch {
      return nil
    }
    return url
  }
}

/// PencilKit over a fixed background, with the system tool picker.
/// Canvas size matches the page image exactly so save/flatten needs no rescale.
private struct MarkupCanvas: UIViewRepresentable {
  let background: UIImage
  @Binding var drawing: PKDrawing

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.backgroundColor = .clear
    scroll.minimumZoomScale = 0.25
    scroll.maximumZoomScale = 4
    scroll.delegate = context.coordinator
    scroll.alwaysBounceVertical = true
    scroll.alwaysBounceHorizontal = true

    let imageView = UIImageView(image: background)
    imageView.contentMode = .scaleToFill

    let canvas = PKCanvasView()
    canvas.drawing = drawing
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    canvas.drawingPolicy = .anyInput
    canvas.delegate = context.coordinator

    let container = UIView()
    container.addSubview(imageView)
    container.addSubview(canvas)
    scroll.addSubview(container)

    context.coordinator.container = container
    context.coordinator.imageView = imageView
    context.coordinator.canvas = canvas
    context.coordinator.scroll = scroll
    context.coordinator.drawing = $drawing

    DispatchQueue.main.async {
      context.coordinator.layout(fit: true)
      guard let window = scroll.window else { return }
      let picker = PKToolPicker.shared(for: window)
      picker?.setVisible(true, forFirstResponder: canvas)
      picker?.addObserver(canvas)
      canvas.becomeFirstResponder()
    }
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {
    // Keep the binding current — makeCoordinator only runs once per view
    // identity, and we recreate via `.id(pageIndex)`.
    context.coordinator.drawing = $drawing
    if context.coordinator.canvas?.drawing != drawing {
      context.coordinator.canvas?.drawing = drawing
    }
    // Every stroke passes through here (binding write → view update). Re-running
    // layout would reset the frames in unzoomed page coordinates and fight the
    // pinch, so relayout only for a genuine page-image swap — or until the
    // initial fit has landed (the async fit in makeUIView can beat the bounds).
    if context.coordinator.imageView?.image !== background || !context.coordinator.didInitialFit {
      context.coordinator.imageView?.image = background
      context.coordinator.layout(fit: false)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

  final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
    var container: UIView?
    var imageView: UIImageView?
    var canvas: PKCanvasView?
    weak var scroll: UIScrollView?
    var drawing: Binding<PKDrawing>
    var didInitialFit = false

    init(drawing: Binding<PKDrawing>) {
      self.drawing = drawing
    }

    func layout(fit: Bool) {
      guard let scroll, let container, let imageView, let canvas,
            let image = imageView.image, image.size.width > 0
      else { return }
      let pageSize = image.size
      container.frame = CGRect(origin: .zero, size: pageSize)
      imageView.frame = container.bounds
      canvas.frame = container.bounds
      scroll.contentSize = pageSize

      let available = scroll.bounds.size
      guard available.width > 0, available.height > 0 else { return }
      if fit || !didInitialFit {
        let scale = min(available.width / pageSize.width, available.height / pageSize.height)
        scroll.zoomScale = max(scroll.minimumZoomScale, min(scroll.maximumZoomScale, scale))
        didInitialFit = true
      }
      applyInsets()
    }

    private func applyInsets() {
      guard let scroll else { return }
      let scaled = scroll.contentSize
      let insetX = max((scroll.bounds.width - scaled.width) * 0.5, 0)
      let insetY = max((scroll.bounds.height - scaled.height) * 0.5, 0)
      scroll.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { applyInsets() }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      drawing.wrappedValue = canvasView.drawing
    }
  }
}
