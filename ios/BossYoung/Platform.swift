import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// The thin seam between iOS and macOS.
///
/// Almost all of this app is platform-neutral SwiftUI — models, the API client,
/// the view models and most views compile unchanged. UIKit only shows up at the
/// leaves: a colour, a clipboard, an image, a screen width. Rather than dusting
/// `#if os(...)` through every one of those call sites, they go through here, so
/// a reader of `MessageViews` or `BrandTheme` sees one vocabulary and the
/// platform difference stays in one file.
///
/// The genuinely platform-specific *features* — the document scanner, the
/// camera, PencilKit markup, the Feishu SDK — are NOT shimmed. They are excluded
/// from the macOS target entirely, because pretending a Mac has a rear camera
/// would be worse than not offering the button.
#if os(macOS)
  typealias PlatformColor = NSColor
  typealias PlatformImage = NSImage
#else
  typealias PlatformColor = UIColor
  typealias PlatformImage = UIImage
#endif

enum Platform {
  /// A colour that follows the system appearance. Both platforms have this, but
  /// spell it completely differently.
  static func adaptiveColor(light: PlatformColor, dark: PlatformColor) -> Color {
    #if os(macOS)
      return Color(
        nsColor: NSColor(name: nil) { appearance in
          appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
      )
    #else
      return Color(
        uiColor: UIColor { traits in
          traits.userInterfaceStyle == .dark ? dark : light
        }
      )
    #endif
  }

  static func color(red: Double, green: Double, blue: Double, alpha: Double = 1) -> PlatformColor {
    #if os(macOS)
      return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    #else
      return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    #endif
  }

  static func copyToPasteboard(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif
  }

  /// Used only to give the home composer a sensible minimum height; a window can
  /// be any size on a Mac, so callers should treat this as a hint.
  static var referenceHeight: CGFloat {
    #if os(macOS)
      return NSScreen.main?.frame.height ?? 900
    #else
      return UIScreen.main.bounds.height
    #endif
  }

  /// Success feedback for a finished reply. Macs have no Taptic Engine; the
  /// sound in `CapkaFeedback` carries the whole signal there.
  static func successFeedback() {
    #if os(iOS)
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(.success)
    #endif
  }

  /// Open a file with whatever the system considers its default handler. On iOS
  /// this is Quick Look's job (see `FilePreview`); on macOS, the Finder's.
  static func openInDefaultApp(_ url: URL) {
    #if os(macOS)
      NSWorkspace.shared.open(url)
    #endif
  }
}
