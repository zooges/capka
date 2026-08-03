import SwiftUI

struct ModelPickerSheet: View {
  let models: [ModelInfo]
  let selectedId: String?
  let onSelect: (String) -> Void
  let onClose: () -> Void

  @State private var query = ""

  private var filtered: [ModelInfo] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return models }
    return models.filter {
      $0.name.lowercased().contains(q)
        || $0.id.lowercased().contains(q)
        || ($0.group?.lowercased().contains(q) ?? false)
        || ($0.provider?.lowercased().contains(q) ?? false)
    }
  }

  private var featured: [ModelInfo] { filtered.filter { $0.featured == true } }

  private var grouped: [(String, [ModelInfo])] {
    let rest = filtered.filter { $0.featured != true }
    let dict = Dictionary(grouping: rest, by: \.displayGroup)
    let priority = ["Anthropic", "OpenAI", "Google", "Meta", "Mistral", "DeepSeek", "xAI", "Qwen"]
    return dict.keys.sorted { a, b in
      let ia = priority.firstIndex(of: a) ?? 999
      let ib = priority.firstIndex(of: b) ?? 999
      if ia != ib { return ia < ib }
      return a < b
    }.map { ($0, dict[$0] ?? []) }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Brand.cream.ignoresSafeArea()

        VStack(spacing: 0) {
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(Brand.muted)
            TextField("搜索型号", text: $query)
              .font(.system(size: 16))
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 11)
          .capkaCard(radius: Brand.Radius.lg)
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 12)

          if models.isEmpty {
            VStack(spacing: 10) {
              ProgressView().tint(Brand.primary)
              Text("正在加载型号…")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if filtered.isEmpty {
            Text("没有匹配的型号")
              .font(.subheadline)
              .foregroundStyle(Brand.muted)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 18) {
                if !featured.isEmpty {
                  section(title: "精选", models: featured)
                }
                ForEach(grouped, id: \.0) { group, items in
                  section(title: group, models: items)
                }
              }
              .padding(.horizontal, 16)
              .padding(.bottom, 24)
            }
          }
        }
      }
      .navigationTitle("型号")
      .capkaNavigationChrome()
      .toolbar {
        ToolbarItem(placement: .capkaTrailing) {
          Button("关闭", action: onClose)
            .fontWeight(.semibold)
            .foregroundStyle(Brand.primary)
        }
      }
    }
  }

  private func section(title: String, models: [ModelInfo]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)

      VStack(spacing: 0) {
        ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
          Button {
            onSelect(model.id)
          } label: {
            HStack(alignment: .center, spacing: 12) {
              ZStack {
                RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                  .fill(Brand.accent)
                  .frame(width: 34, height: 34)
                ProviderIconView(slug: model.iconSlug, size: 20)
              }

              VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                  .font(.system(size: 15, weight: .medium))
                  .foregroundStyle(Brand.ink)
                  .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                  if let ctx = model.context, ctx > 0 {
                    Text(formatContext(ctx))
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                  if model.vision == true {
                    Label("图片", systemImage: "eye")
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                  if model.reasoning == true {
                    Label("推理", systemImage: "brain")
                      .font(.system(size: 11))
                      .foregroundStyle(Brand.muted)
                  }
                }
              }

              Spacer(minLength: 8)

              if model.id == selectedId {
                Image(systemName: "checkmark")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Brand.primary)
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
          }
          .buttonStyle(CapkaPressStyle())

          if index < models.count - 1 {
            Divider().overlay(Brand.line).padding(.leading, 58)
          }
        }
      }
      .capkaCard()
    }
  }

  private func formatContext(_ ctx: Int) -> String {
    if ctx >= 1_000_000 { return "\(ctx / 1_000_000)M 上下文" }
    if ctx >= 1_000 { return "\(ctx / 1_000)K 上下文" }
    return "\(ctx) 上下文"
  }
}

