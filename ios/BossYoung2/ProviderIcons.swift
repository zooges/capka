import SwiftUI
import UIKit

/// Resolves a model/group/provider to the same brand-icon slug the web uses
/// (`src/lib/models/normalize.ts` → `@lobehub/icons`).
enum ProviderIconSlug {
  private static let rules: [(NSRegularExpression, String)] = {
    let patterns: [(String, String)] = [
      (#"anthropic|claude"#, "anthropic"),
      (#"openai|gpt|o\d|davinci"#, "openai"),
      (#"google|gemini|palm|gemma"#, "google"),
      (#"\bmeta\b|\bllama"#, "meta"),
      (#"mistral|mixtral|codestral|magistral"#, "mistral"),
      (#"deepseek"#, "deepseek"),
      (#"x-?ai|grok"#, "xai"),
      (#"qwen|alibaba|tongyi"#, "qwen"),
      (#"cohere|command"#, "cohere"),
      (#"perplexity|sonar"#, "perplexity"),
      (#"microsoft|phi\b"#, "microsoft"),
      (#"amazon|nova|titan|bedrock"#, "amazon"),
      (#"nvidia|nemotron"#, "nvidia"),
      (#"ai21|jamba"#, "ai21"),
      (#"minimax"#, "minimax"),
      (#"xiaomi|mimo"#, "xiaomi"),
      (#"zhipu|z\.?ai|glm"#, "zhipu"),
      (#"moonshot|kimi"#, "moonshot"),
      (#"tencent|hunyuan"#, "hunyuan"),
      (#"bytedance|doubao"#, "doubao"),
      (#"baidu|ernie|wenxin"#, "baidu"),
      (#"databricks|dbrx"#, "dbrx"),
      (#"internlm"#, "internlm"),
      (#"baichuan"#, "baichuan"),
      (#"stepfun"#, "stepfun"),
      (#"longcat"#, "longcat"),
      (#"01[.-]?ai|\byi\b"#, "yi"),
      (#"upstage|\bsolar\b"#, "upstage"),
      (#"nous|hermes"#, "nousresearch"),
      (#"liquid|\blfm\b"#, "liquid"),
      (#"ollama"#, "ollama"),
      (#"openrouter"#, "openrouter"),
      (#"siliconflow|siliconcloud"#, "siliconcloud"),
      (#"azure"#, "azure"),
    ]
    return patterns.compactMap { pattern, slug in
      guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
      return (re, slug)
    }
  }()

  static func resolve(icon: String?, group: String?, provider: String?, name: String?) -> String {
    if let icon, !icon.isEmpty, icon != "generic" {
      return icon.lowercased()
    }
    if let hit = match(group) { return hit }
    if let hit = match(provider) { return hit }
    if let hit = match(name) { return hit }
    if let provider, !provider.isEmpty {
      let slug = provider.lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      if !slug.isEmpty { return slug }
    }
    return "generic"
  }

  private static func match(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    for (re, slug) in rules {
      if re.firstMatch(in: value, options: [], range: range) != nil { return slug }
    }
    return nil
  }
}

// MARK: - Disk + memory cache

/// One download per slug/theme; later paints come from memory / Application Support.
enum ProviderIconCache {
  private static let memory = NSCache<NSString, UIImage>()
  private static let io = DispatchQueue(label: "capka.provider-icon-cache", qos: .utility)
  private static var inflight = [String: Task<UIImage?, Never>]()
  private static let lock = NSLock()

  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    // Brand icons are immutable at this package pin — keep a large HTTP cache too.
    config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.timeoutIntervalForRequest = 20
    return URLSession(configuration: config)
  }()

  private static var root: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("capka-provider-icons", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func remoteURL(slug: String, dark: Bool) -> URL? {
    guard slug != "generic", !slug.isEmpty else { return nil }
    let folder = dark ? "dark" : "light"
    return URL(string: "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-png@1.74.0/\(folder)/\(slug).png")
  }

  private static func cacheKey(slug: String, dark: Bool) -> String {
    "\(dark ? "dark" : "light")/\(slug)"
  }

  private static func fileURL(key: String) -> URL {
    // Flatten path separators for a single directory.
    let name = key.replacingOccurrences(of: "/", with: "_") + ".png"
    return root.appendingPathComponent(name)
  }

  static func cachedImage(slug: String, dark: Bool) -> UIImage? {
    let key = cacheKey(slug: slug, dark: dark)
    if let hit = memory.object(forKey: key as NSString) { return hit }
    let url = fileURL(key: key)
    guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
    memory.setObject(image, forKey: key as NSString)
    return image
  }

  @MainActor
  static func image(slug: String, dark: Bool) async -> UIImage? {
    let key = cacheKey(slug: slug, dark: dark)
    if let hit = cachedImage(slug: slug, dark: dark) { return hit }
    guard let remote = remoteURL(slug: slug, dark: dark) else { return nil }

    lock.lock()
    if let existing = inflight[key] {
      lock.unlock()
      return await existing.value
    }
    let task = Task<UIImage?, Never> {
      await download(slug: slug, dark: dark, key: key, remote: remote)
    }
    inflight[key] = task
    lock.unlock()

    let image = await task.value
    lock.lock()
    inflight[key] = nil
    lock.unlock()
    return image
  }

  private static func download(slug: String, dark: Bool, key: String, remote: URL) async -> UIImage? {
    do {
      var req = URLRequest(url: remote)
      req.cachePolicy = .returnCacheDataElseLoad
      let (data, response) = try await session.data(for: req)
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let image = UIImage(data: data)
      else { return nil }
      memory.setObject(image, forKey: key as NSString)
      let dest = fileURL(key: key)
      io.async { try? data.write(to: dest, options: .atomic) }
      return image
    } catch {
      return nil
    }
  }

  /// Warm icons for the current model list (both themes) so the picker/chip never flash.
  static func prefetch(slugs: [String]) {
    let unique = Array(Set(slugs.map { $0.lowercased() }.filter { !$0.isEmpty && $0 != "generic" }))
    guard !unique.isEmpty else { return }
    Task(priority: .utility) {
      for slug in unique {
        _ = await image(slug: slug, dark: false)
        _ = await image(slug: slug, dark: true)
      }
    }
  }
}

/// Brand glyph matching the web model picker (`ProviderGlyph` / lobehub icons).
/// Uses a durable disk cache so each slug/theme is downloaded once.
struct ProviderIconView: View {
  let slug: String?
  var size: CGFloat = 18

  @Environment(\.colorScheme) private var colorScheme
  @State private var image: UIImage?

  private var resolved: String {
    let s = (slug ?? "generic").lowercased()
    return s.isEmpty ? "generic" : s
  }

  private var dark: Bool { colorScheme == .dark }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else if resolved == "generic" {
        fallback
      } else {
        // Prefer an instant disk/memory hit; never show a spinner on a cache miss
        // longer than a soft placeholder — icons are decorative.
        fallback
          .opacity(0.35)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
    .task(id: "\(resolved)-\(dark)") {
      guard resolved != "generic" else {
        image = nil
        return
      }
      if let hit = ProviderIconCache.cachedImage(slug: resolved, dark: dark) {
        image = hit
        return
      }
      image = await ProviderIconCache.image(slug: resolved, dark: dark)
    }
  }

  private var fallback: some View {
    Image(systemName: "sparkles")
      .font(.system(size: size * 0.62, weight: .medium))
      .foregroundStyle(Brand.muted)
      .frame(width: size, height: size)
  }
}

extension ModelInfo {
  var iconSlug: String {
    ProviderIconSlug.resolve(icon: icon, group: group, provider: provider, name: name)
  }
}
