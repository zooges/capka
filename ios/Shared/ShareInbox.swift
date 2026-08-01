import Foundation

/// The hand-off between the share extension and the app.
///
/// The extension deliberately does NOT upload: it has no session of its own to
/// keep healthy, a half-finished upload in a process iOS can kill at any moment
/// is worse than no upload, and an expired login would have to be re-explained
/// inside a sheet the user opened from Mail. So it only copies the files into
/// the shared container and leaves a manifest; the app drains it the next time
/// it comes forward, where the composer, the session and the error surface all
/// already exist.
enum ShareInbox {
  /// Must match the App Group on both targets' entitlements.
  static let appGroup = "group.com.bossyoung.capka"

  private static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
  }

  private static var inbox: URL? {
    container?.appendingPathComponent("share-inbox", isDirectory: true)
  }

  /// Copy shared files in. Returns how many landed — the extension reports that
  /// number back to the user rather than claiming success blindly.
  @discardableResult
  static func stage(_ urls: [URL]) -> Int {
    guard let inbox else { return 0 }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    var staged = 0
    for url in urls {
      // A unique prefix keeps two shares of "合同.pdf" from clobbering each other
      // while still ending in the name the user recognises.
      let destination = inbox.appendingPathComponent("\(UUID().uuidString)__\(url.lastPathComponent)")
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      do {
        try FileManager.default.copyItem(at: url, to: destination)
        staged += 1
      } catch {
        continue
      }
    }
    return staged
  }

  /// True when something is waiting — cheap enough to check on every activation.
  static var hasPending: Bool {
    guard let inbox else { return false }
    let items = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
    return !items.isEmpty
  }

  /// Move everything staged into the app's own tmp and clear the inbox. Returned
  /// URLs carry the original file name, with the uniquing prefix stripped.
  static func drain() -> [URL] {
    guard let inbox,
          let items = try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey]
          )
    else { return [] }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("capka-shared", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var out: [URL] = []
    for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let name = item.lastPathComponent.components(separatedBy: "__").dropFirst().joined(separator: "__")
      let destination = dir.appendingPathComponent(name.isEmpty ? item.lastPathComponent : name)
      try? FileManager.default.removeItem(at: destination)
      do {
        try FileManager.default.moveItem(at: item, to: destination)
        out.append(destination)
      } catch {
        try? FileManager.default.removeItem(at: item)
      }
    }
    return out
  }
}
