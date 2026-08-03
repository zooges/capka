import SwiftUI
import UIKit
import VisionKit

/// The system document scanner: edge detection, perspective correction and
/// shadow removal, then a multi-page PDF. A photo of a contract and a scan of
/// one are not the same input — the scan is what OCR and the model can actually
/// read, which is why this is the primary paper path and 拍照 is the fallback.
struct DocumentScanner: UIViewControllerRepresentable {
  /// Called with the finished PDF on disk, or nil if the user backed out.
  let onFinish: (URL?) -> Void

  static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private let onFinish: (URL?) -> Void

    init(onFinish: @escaping (URL?) -> Void) {
      self.onFinish = onFinish
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      onFinish(Self.pdf(from: scan))
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      onFinish(nil)
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      onFinish(nil)
    }

    /// One PDF for the whole scan rather than N images: the agent gets a single
    /// document with its pages in order, which is what a contract is.
    private static func pdf(from scan: VNDocumentCameraScan) -> URL? {
      guard scan.pageCount > 0 else { return nil }
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("capka-attach", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("\(MediaAttach.timestampedName("扫描件")).pdf")

      // Page boxes follow each scanned image, so a mixed A4 / receipt scan keeps
      // each page at its own size instead of being stretched to a common one.
      let renderer = UIGraphicsPDFRenderer(bounds: .zero)
      do {
        try renderer.writePDF(to: url) { context in
          for index in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: index)
            let bounds = CGRect(origin: .zero, size: image.size)
            context.beginPage(withBounds: bounds, pageInfo: [:])
            image.draw(in: bounds)
          }
        }
      } catch {
        return nil
      }
      return url
    }
  }
}
