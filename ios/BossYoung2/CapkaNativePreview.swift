import QuickLook
import UIKit
import WebKit

/// Downloads an authenticated Capka file URL (using the WKWebView cookie jar)
/// and presents iOS Quick Look so users can preview PDF / Office / images in-app.
enum CapkaNativePreview {
  static func present(url: URL, filename: String, from webView: WKWebView) {
    guard let host = topViewController() else { return }

    let hud = UIAlertController(title: nil, message: "正在打开预览…", preferredStyle: .alert)
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.startAnimating()
    hud.view.addSubview(indicator)
    NSLayoutConstraint.activate([
      indicator.centerYAnchor.constraint(equalTo: hud.view.centerYAnchor),
      indicator.leadingAnchor.constraint(equalTo: hud.view.leadingAnchor, constant: 24),
    ])
    host.present(hud, animated: true)

    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
      var request = URLRequest(url: url)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let matched = cookies.filter { cookieApplies($0, to: url) }
      let headers = HTTPCookie.requestHeaderFields(with: matched)
      for (k, v) in headers {
        request.setValue(v, forHTTPHeaderField: k)
      }

      let task = URLSession.shared.downloadTask(with: request) { temp, response, error in
        DispatchQueue.main.async {
          hud.dismiss(animated: true) {
            if let error {
              presentError(error.localizedDescription, from: host)
              return
            }
            guard let temp else {
              presentError("下载失败", from: host)
              return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
              presentError("无法打开文件（\(status)）", from: host)
              return
            }
            do {
              let dir = FileManager.default.temporaryDirectory.appendingPathComponent("capka-preview", isDirectory: true)
              try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
              let safe = filename.replacingOccurrences(of: "/", with: "_")
              let dest = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
              try? FileManager.default.removeItem(at: dest)
              try FileManager.default.moveItem(at: temp, to: dest)
              presentQuickLook(fileURL: dest, from: host)
            } catch {
              presentError(error.localizedDescription, from: host)
            }
          }
        }
      }
      task.resume()
    }
  }

  static func presentQuickLook(fileURL: URL, from host: UIViewController) {
    let preview = QLPreviewController()
    let item = FilePreviewItem(url: fileURL)
    let ds = PreviewDataSource(item: item)
    // Retain data source on the controller via associated object
    objc_setAssociatedObject(preview, &AssociatedKeys.dataSource, ds, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    preview.dataSource = ds
    host.present(preview, animated: true)
  }

  private static func cookieApplies(_ cookie: HTTPCookie, to url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    var domain = cookie.domain.lowercased()
    if domain.hasPrefix(".") { domain.removeFirst() }
    return host == domain || host.hasSuffix(".\(domain)")
  }

  private static func topViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
    else { return nil }
    var top = root
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  private static func presentError(_ message: String, from host: UIViewController) {
    let alert = UIAlertController(title: "无法预览", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    host.present(alert, animated: true)
  }
}

private enum AssociatedKeys {
  static var dataSource: UInt8 = 0
}

private final class FilePreviewItem: NSObject, QLPreviewItem {
  let previewItemURL: URL?
  let previewItemTitle: String?

  init(url: URL) {
    previewItemURL = url
    previewItemTitle = url.lastPathComponent
    super.init()
  }
}

private final class PreviewDataSource: NSObject, QLPreviewControllerDataSource {
  let item: FilePreviewItem
  init(item: FilePreviewItem) { self.item = item }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }
}
