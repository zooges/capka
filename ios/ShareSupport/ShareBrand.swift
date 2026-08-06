import UIKit

/// UIKit tokens mirrored from `BrandTheme` (cream / ink / burgundy).
enum ShareBrand {
  static let cream = UIColor(rgb: 0xF8F6F2)
  static let creamDark = UIColor(rgb: 0x33312E)
  static let card = UIColor(rgb: 0xFEFDFC)
  static let cardDark = UIColor(rgb: 0x3A3835)
  static let accent = UIColor(rgb: 0xF0EDE8)
  static let accentDark = UIColor(rgb: 0x44423F)
  static let ink = UIColor(rgb: 0x1A1A1E)
  static let inkDark = UIColor(rgb: 0xF2F0ED)
  static let muted = UIColor(rgb: 0x5C5C64)
  static let mutedDark = UIColor(rgb: 0xA8A49C)
  static let line = UIColor(red: 0.878, green: 0.867, blue: 0.855, alpha: 1)
  static let lineDark = UIColor(white: 1, alpha: 0.10)
  static let primary = UIColor(rgb: 0x1F1E24)
  static let primaryDark = UIColor(rgb: 0xF2F0ED)
  static let onPrimary = UIColor(rgb: 0xFEFDFC)
  static let onPrimaryDark = UIColor(rgb: 0x2A2826)
  static let burgundy = UIColor(rgb: 0x8B1E23)

  static let radiusSm: CGFloat = 7
  static let radiusMd: CGFloat = 9
  static let radiusLg: CGFloat = 11
  static let radiusXl: CGFloat = 16
  static let radiusXxl: CGFloat = 20

  static var background: UIColor { adaptive(light: cream, dark: creamDark) }
  static var surface: UIColor { adaptive(light: card, dark: cardDark) }
  static var surfaceMuted: UIColor { adaptive(light: accent, dark: accentDark) }
  static var text: UIColor { adaptive(light: ink, dark: inkDark) }
  static var textMuted: UIColor { adaptive(light: muted, dark: mutedDark) }
  static var border: UIColor { adaptive(light: line, dark: lineDark) }
  static var fill: UIColor { adaptive(light: primary, dark: primaryDark) }
  static var onFill: UIColor { adaptive(light: onPrimary, dark: onPrimaryDark) }

  static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in
      traits.userInterfaceStyle == .dark ? dark : light
    }
  }
}

private extension UIColor {
  convenience init(rgb: UInt32, alpha: CGFloat = 1) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: alpha
    )
  }
}
