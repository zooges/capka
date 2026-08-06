import Foundation

/// Per-target host identity for the Share Extension ↔ app handshake.
/// BossYoung2 sets `BOSSYOUNG2` in SWIFT_ACTIVE_COMPILATION_CONDITIONS.
enum ShareHostConfig {
#if BOSSYOUNG2
  static let appGroupId = "group.com.bossyoung.capka2"
  static let urlScheme = "bossyoung2"
  static let displayName = "邦信阳"
#else
  static let appGroupId = "group.com.bossyoung.capka"
  static let urlScheme = "bossyoung"
  static let displayName = "邦信阳"
#endif

  static var shareInboxURL: URL {
    URL(string: "\(urlScheme)://share-inbox")!
  }

  static func containerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }
}
