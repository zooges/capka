import SwiftUI

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

/// Brand glyph matching the web model picker (`ProviderGlyph` / lobehub icons).
/// Loads the official static PNG from jsDelivr (same artwork as `@lobehub/icons`).
struct ProviderIconView: View {
  let slug: String?
  var size: CGFloat = 18

  @Environment(\.colorScheme) private var colorScheme

  private var resolved: String {
    let s = (slug ?? "generic").lowercased()
    return s.isEmpty ? "generic" : s
  }

  private var remoteURL: URL? {
    guard resolved != "generic" else { return nil }
    let folder = colorScheme == .dark ? "dark" : "light"
    return URL(string: "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-png@1.74.0/\(folder)/\(resolved).png")
  }

  var body: some View {
    Group {
      if let remoteURL {
        AsyncImage(url: remoteURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
          case .failure:
            fallback
          case .empty:
            ProgressView()
              .controlSize(.mini)
          @unknown default:
            fallback
          }
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
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
