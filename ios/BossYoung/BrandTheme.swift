import SwiftUI
import UIKit

/// Appearance preference mirrored from the web account menu (system / light / dark).
enum ThemePreference: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var label: String {
    switch self {
    case .system: return "系统"
    case .light: return "浅色"
    case .dark: return "深色"
    }
  }

  var icon: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max"
    case .dark: return "moon"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  static let storageKey = "capka.theme"
}

/// Design tokens mirrored from the web app's `globals.css` (warm OKLCH neutrals,
/// hue 75). Light and dark variants track the web `.dark` block so SwiftUI’s
/// `preferredColorScheme` / system appearance stay in sync with the account menu.
enum Brand {
  private static func hex(_ value: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? hex(dark) : hex(light)
    })
  }

  private static func adaptiveAlpha(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? dark : light
    })
  }

  /// `--background`
  static let cream = adaptive(light: 0xF8F6F2, dark: 0x33312E)
  /// `--sidebar`
  static let sidebar = adaptive(light: 0xFBF9F6, dark: 0x2C2A28)
  /// `--card` / `--popover`
  static let card = adaptive(light: 0xFEFDFC, dark: 0x3A3835)
  /// `--muted` / `--accent` surface
  static let accent = adaptive(light: 0xF0EDE8, dark: 0x44423F)
  /// `--foreground`
  static let ink = adaptive(light: 0x1A1A1E, dark: 0xF2F0ED)
  /// `--muted-foreground`
  static let muted = adaptive(light: 0x5C5C64, dark: 0xA8A49C)
  /// `--border` / `--input`
  static let line = adaptiveAlpha(
    light: UIColor(red: 0.878, green: 0.867, blue: 0.855, alpha: 1),
    dark: UIColor(white: 1, alpha: 0.10)
  )
  /// `--primary` (filled actions)
  static let primary = adaptive(light: 0x1F1E24, dark: 0xF2F0ED)
  /// `--primary-foreground`
  static let onPrimary = adaptive(light: 0xFEFDFC, dark: 0x2A2826)
  /// `--link`
  static let link = adaptive(light: 0x1268C8, dark: 0x7EB0F0)

  static let dangerSurface = adaptive(light: 0xFBE7E1, dark: 0x4A2E2A)
  static let dangerBorder = adaptive(light: 0xEC9384, dark: 0x8A554C)
  static let dangerText = adaptive(light: 0xB43226, dark: 0xE8A090)

  static let warningSurface = adaptive(light: 0xFFEBBE, dark: 0x4A3D28)
  static let warningBorder = adaptive(light: 0xD7A03D, dark: 0x8A7040)
  static let warningText = adaptive(light: 0x825A27, dark: 0xE0C070)

  /// Brand mark accent (logo, hero glow) — never app chrome.
  static let burgundy = Color(uiColor: hex(0x8B1E23))

  /// Product wordmark shown next to the mark in the sidebar (web `productName()`).
  static let productName = "BOSS & YOUNG"

  enum Radius {
    static let sm: CGFloat = 7
    static let md: CGFloat = 9
    static let lg: CGFloat = 11
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
  }
}

/// Motion vocabulary mirrored from `globals.css`. The web deliberately grades
/// its entrances by how often they fire: the hero gets a cinematic blur-rise,
/// message rows get a cheap opacity + 4pt settle, and step rows (dozens per
/// streamed turn) get opacity only. Keep that restraint here.
enum Motion {
  /// `--ease-out: cubic-bezier(0.16, 1, 0.3, 1)`
  static func easeOut(_ duration: Double) -> Animation {
    .timingCurve(0.16, 1, 0.3, 1, duration: duration)
  }

  enum Entrance {
    /// `blur-rise` — hero / home content.
    case blurRise
    /// `message-in` — a transcript row.
    case message
    /// `step-in` — an activity row.
    case step
  }
}

/// Plays an entrance once when the view mounts, and does nothing at all when the
/// reader has asked for reduced motion.
private struct EntranceModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let entrance: Motion.Entrance
  let delay: Double

  @State private var landed = false

  private var duration: Double {
    switch entrance {
    case .blurRise: return 0.5
    case .message, .step: return 0.18
    }
  }

  private var offset: CGFloat {
    switch entrance {
    case .blurRise: return 10
    case .message: return 4
    case .step: return 0
    }
  }

  private var blur: CGFloat { entrance == .blurRise ? 12 : 0 }
  private var scale: CGFloat { entrance == .blurRise ? 0.99 : 1 }

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content
        .opacity(landed ? 1 : 0)
        .offset(y: landed ? 0 : offset)
        .scaleEffect(landed ? 1 : scale)
        .blur(radius: landed ? 0 : blur)
        .onAppear {
          withAnimation(Motion.easeOut(duration).delay(delay)) { landed = true }
        }
    }
  }
}

/// Row/card press feedback — the web's `active:scale-[0.99]`. Replaces
/// `.buttonStyle(.plain)` on tappable surfaces (it tints nothing either).
struct CapkaPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(Motion.easeOut(0.12), value: configuration.isPressed)
  }
}

extension View {
  func capkaEntrance(_ entrance: Motion.Entrance, delay: Double = 0) -> some View {
    modifier(EntranceModifier(entrance: entrance, delay: delay))
  }

  /// Hairline card surface used across the web app (border + very soft shadow).
  func capkaCard(radius: CGFloat = Brand.Radius.xl, fill: Color = Brand.card) -> some View {
    background(fill)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(Brand.line, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
  }

  func capkaPreferredColorScheme(_ preference: ThemePreference) -> some View {
    preferredColorScheme(preference.colorScheme)
  }
}
