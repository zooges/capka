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

  @State private var canvas = PKCanvasView()
  @State private var pageIndex = 0
  @State private var isSaving = false

  /// Rendered page images — markup is drawn over these and flattened back out,
  /// which keeps one code path for PDFs and images alike.
  @State private var pages: [UIImage] = []
  /// One drawing per page, so flipping back and forth doesn't lose strokes.
  @State private var drawings: [PKDrawing] = []

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()

        if pages.isEmpty {
          ProgressView().tint(Brand.primary)
        } else {
          MarkupCanvas(
            background: pages[pageIndex],
            canvas: canvas,
            drawing: Binding(
              get: { drawings.indices.contains(pageIndex) ? drawings[pageIndex] : PKDrawing() },
              set: { if drawings.indices.contains(pageIndex) { drawings[pageIndex] = $0 } }
            )
          )
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
            Button { turn(1) } label: { Image(systemName: "chevron.right") }
              .disabled(pageIndex >= pages.count - 1)
          }
        }
      }
      .task { load() }
    }
  }

  private func turn(_ delta: Int) {
    // Commit the visible strokes before swapping the backing image out.
    if drawings.indices.contains(pageIndex) { drawings[pageIndex] = canvas.drawing }
    pageIndex = max(0, min(pages.count - 1, pageIndex + delta))
    canvas.drawing = drawings.indices.contains(pageIndex) ? drawings[pageIndex] : PKDrawing()
  }

  private func load() {
    // Cap the page count: a 300-page bundle rendered at once would be a memory
    // problem, and nobody marks up 300 pages on a phone.
    let rendered = Self.render(fileURL: fileURL, limit: 30)
    pages = rendered
    drawings = Array(repeating: PKDrawing(), count: rendered.count)
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    if drawings.indices.contains(pageIndex) { drawings[pageIndex] = canvas.drawing }
    let output = Self.flatten(pages: pages, drawings: drawings, name: fileURL.deletingPathExtension().lastPathComponent)
    onFinish(output)
  }

  /// A PDF becomes one image per page; anything else Quick Look could show is a
  /// single image.
  private static func render(fileURL: URL, limit: Int) -> [UIImage] {
    if let document = PDFDocument(url: fileURL) {
      return (0..<min(document.pageCount, limit)).compactMap { index in
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        // 2x so ink lands on a page that still reads crisply when zoomed.
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

  /// Burn the strokes into the pages and write one PDF. Flattened rather than
  /// kept as PDF annotations so the file reads the same everywhere — including
  /// in whatever the agent uses to open it next.
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
          guard index < drawings.count else { continue }
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
private struct MarkupCanvas: UIViewRepresentable {
  let background: UIImage
  let canvas: PKCanvasView
  @Binding var drawing: PKDrawing

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.backgroundColor = .clear
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 4
    scroll.delegate = context.coordinator

    let imageView = UIImageView(image: background)
    imageView.contentMode = .scaleAspectFit

    canvas.drawing = drawing
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    // Finger as well as Pencil: most people reviewing a contract on a phone do
    // not have an Apple Pencil in hand.
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

    DispatchQueue.main.async {
      guard let window = scroll.window else { return }
      let picker = PKToolPicker.shared(for: window)
      picker?.setVisible(true, forFirstResponder: canvas)
      picker?.addObserver(canvas)
      canvas.becomeFirstResponder()
    }
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {
    context.coordinator.imageView?.image = background
    context.coordinator.layout()
  }

  func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

  final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
    var container: UIView?
    var imageView: UIImageView?
    var canvas: PKCanvasView?
    weak var scroll: UIScrollView?
    private let drawing: Binding<PKDrawing>

    init(drawing: Binding<PKDrawing>) {
      self.drawing = drawing
    }

    /// The ink layer has to sit exactly on the page, or a stroke lands somewhere
    /// other than where it was drawn.
    func layout() {
      guard let scroll, let container, let imageView, let canvas,
            let image = imageView.image, image.size.width > 0
      else { return }
      let available = scroll.bounds.size
      guard available.width > 0, available.height > 0 else { return }
      let scale = min(available.width / image.size.width, available.height / image.size.height)
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      container.frame = CGRect(origin: .zero, size: size)
      imageView.frame = container.bounds
      canvas.frame = container.bounds
      scroll.contentSize = size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      drawing.wrappedValue = canvasView.drawing
    }
  }
}
