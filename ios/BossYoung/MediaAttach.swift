import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Camera and photo-library attachments. Both are staged to a temp file so the
/// picked media rides exactly the same upload path as a document pick.
enum MediaAttach {
  /// Longest edge a staged photo keeps. A 12MP camera shot is ~4000px and
  /// several megabytes; the agent never needs that, and the upload is going out
  /// over a phone connection.
  private static let maxEdge: CGFloat = 2048

  static func stage(image: UIImage, basename: String) throws -> URL {
    guard let data = downscale(image).jpegData(compressionQuality: 0.85) else {
      throw CapkaAPIError.message("无法处理这张图片")
    }
    return try write(data, name: "\(basename).jpg")
  }

  /// PNG stays PNG (screenshots, transparency); everything else — HEIC above all
  /// — is normalised to JPEG so the sandbox tooling sees a format it knows.
  static func stage(photoData: Data, type: UTType?, basename: String) throws -> URL {
    guard let image = UIImage(data: photoData) else {
      let ext = type?.preferredFilenameExtension ?? "dat"
      return try write(photoData, name: "\(basename).\(ext)")
    }
    if type == .png, let png = downscale(image).pngData() {
      return try write(png, name: "\(basename).png")
    }
    return try stage(image: image, basename: basename)
  }

  /// `照片-0801-1432.jpg` reads better in the transcript than a UUID.
  static func timestampedName(_ prefix: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMdd-HHmmss"
    return "\(prefix)-\(formatter.string(from: Date()))"
  }

  /// Redrawing also bakes in `imageOrientation`, so a photo taken sideways
  /// doesn't reach the agent rotated.
  private static func downscale(_ image: UIImage) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxEdge else { return image }
    let ratio = maxEdge / longest
    let size = CGSize(
      width: (image.size.width * ratio).rounded(),
      height: (image.size.height * ratio).rounded()
    )
    return UIGraphicsImageRenderer(size: size).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private static func write(_ data: Data, name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("capka-attach", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try data.write(to: url, options: .atomic)
    return url
  }
}

/// SwiftUI has no camera view of its own; this is the thin UIKit bridge behind
/// the composer's 拍照 action.
struct CameraPicker: UIViewControllerRepresentable {
  /// Called with the shot, or nil when the user backed out. Either way the
  /// caller is responsible for dismissing.
  let onFinish: (UIImage?) -> Void

  static var isAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.cameraCaptureMode = .photo
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onFinish: (UIImage?) -> Void

    init(onFinish: @escaping (UIImage?) -> Void) {
      self.onFinish = onFinish
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      onFinish(info[.originalImage] as? UIImage)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onFinish(nil)
    }
  }
}
