import SwiftUI

/// How a file is presented wherever it appears — glyph, accent, and tint behind
/// it. Mirrors `src/lib/file-kinds.ts`, including its deliberate use of fixed
/// palette colours (a file type's colour is a stable marker, not a theme token).
struct FileKind {
  let icon: String
  let color: Color
  let tint: Color

  private static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
    .opacity(opacity)
  }

  static let folder = FileKind(
    icon: "folder.fill",
    color: Brand.primary.opacity(0.7),
    tint: Brand.primary.opacity(0.1)
  )
  static let image = FileKind(icon: "photo", color: hex(0xA78BFA), tint: hex(0x8B5CF6, opacity: 0.1))
  static let sheet = FileKind(icon: "tablecells", color: hex(0x34D399), tint: hex(0x10B981, opacity: 0.1))
  static let doc = FileKind(icon: "doc.text", color: hex(0x60A5FA), tint: hex(0x3B82F6, opacity: 0.1))
  static let code = FileKind(
    icon: "chevron.left.forwardslash.chevron.right",
    color: hex(0xFBBF24),
    tint: hex(0xF59E0B, opacity: 0.1)
  )
  static let video = FileKind(icon: "film", color: hex(0xFB7185), tint: hex(0xF43F5E, opacity: 0.1))
  static let audio = FileKind(icon: "waveform", color: hex(0xE879F9), tint: hex(0xD946EF, opacity: 0.1))
  static let archive = FileKind(icon: "doc.zipper", color: hex(0xFB923C), tint: hex(0xF97316, opacity: 0.1))
  static let other = FileKind(icon: "doc", color: Brand.muted, tint: Brand.accent)

  private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic", "tiff", "avif"]
  private static let sheetExts: Set<String> = ["xlsx", "xls", "csv", "numbers", "tsv"]
  private static let docExts: Set<String> = ["docx", "doc", "pdf", "odt", "rtf", "txt", "md", "log", "pages"]
  private static let codeExts: Set<String> = [
    "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "go", "rs", "java", "kt",
    "swift", "php", "css", "scss", "html", "vue", "svelte", "sh", "bash", "zsh",
    "sql", "c", "h", "cpp", "cc", "hpp", "json", "jsonc", "yaml", "yml", "toml",
    "xml", "graphql", "gql", "dockerfile", "ini", "env",
  ]
  private static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
  private static let audioExts: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "ogg"]
  private static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2"]

  static func of(_ name: String, isDirectory: Bool = false) -> FileKind {
    if isDirectory { return folder }
    let ext = name.contains(".") ? (name.components(separatedBy: ".").last ?? "").lowercased() : ""
    if imageExts.contains(ext) { return image }
    if sheetExts.contains(ext) { return sheet }
    if docExts.contains(ext) { return doc }
    if codeExts.contains(ext) { return code }
    if videoExts.contains(ext) { return video }
    if audioExts.contains(ext) { return audio }
    if archiveExts.contains(ext) { return archive }
    return other
  }

  /// Fallback for message attachments, where the server gives a MIME type and
  /// the name may lack a usable extension.
  static func of(name: String, mime: String) -> FileKind {
    let byName = of(name)
    guard byName.icon == other.icon else { return byName }
    if mime.hasPrefix("image/") { return image }
    if mime.hasPrefix("video/") { return video }
    if mime.hasPrefix("audio/") { return audio }
    if mime.contains("sheet") || mime.contains("csv") || mime.contains("excel") { return sheet }
    if mime.contains("pdf") || mime.contains("word") || mime.contains("document") || mime.hasPrefix("text/") {
      return doc
    }
    if mime.contains("zip") || mime.contains("tar") || mime.contains("gzip") { return archive }
    return other
  }
}

/// Rounded tinted square holding a file's glyph — the web's `h-9 w-9 rounded-lg`
/// icon chip.
struct FileGlyph: View {
  let kind: FileKind
  var size: CGFloat = 34

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
        .fill(kind.tint)
      Image(systemName: kind.icon)
        .font(.system(size: size * 0.44))
        .foregroundStyle(kind.color)
    }
    .frame(width: size, height: size)
  }
}
