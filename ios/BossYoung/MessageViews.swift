import SwiftUI
import UIKit

/// One transcript row. User turns are right-aligned card bubbles; assistant
/// turns are full-width plain prose with an activity rail — same as the web.
struct CapkaMessageRow: View {
  let message: ChatUIMessage
  var isAdmin: Bool = false
  /// When set, this row is the latest assistant turn and may offer regenerate.
  var canRegenerate: Bool = false
  var onRegenerate: (() -> Void)?
  var regenerateDisabled: Bool = false
  /// Opens an attached file in Quick Look; the screen owns the loader.
  var onOpenAttachment: ((MessageAttachment) -> Void)?
  /// Opens a `/workspace/…` path the reply named. Same loader as attachments.
  var onOpenWorkspacePath: ((String) -> Void)?
  /// Which chat's workspace the reply's files live in.
  var chatId: String?

  @State private var showDetails = false
  @State private var copied = false
  @State private var showCompaction = false

  private var isUser: Bool { message.role == "user" }

  var body: some View {
    Group {
      if message.isCompaction {
        compactionDivider
      } else if isUser {
        userBubble
      } else {
        assistantBody
      }
    }
    // Text links go out through openURL; intercept the workspace ones so a file
    // the reply names opens in Quick Look rather than bouncing to Safari.
    .environment(\.openURL, OpenURLAction { url in
      guard let rel = WorkspaceLinks.path(from: url) else { return .systemAction }
      onOpenWorkspacePath?(rel)
      return .handled
    })
  }

  // MARK: - User

  private var userBubble: some View {
    HStack {
      Spacer(minLength: 44)
      VStack(alignment: .trailing, spacing: 8) {
        if !message.attachments.isEmpty {
          HStack(spacing: 8) {
            ForEach(message.attachments) { file in
              AttachmentTile(
                name: file.name,
                kind: .of(name: file.name, mime: file.type),
                onTap: onOpenAttachment.map { open in { open(file) } }
              )
            }
          }
        }
        if !message.text.isEmpty {
          Text(message.text)
            .font(.system(size: 15))
            .foregroundStyle(Brand.ink)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .capkaCard(radius: Brand.Radius.xxl)
        }
      }
      .frame(maxWidth: 300, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .contextMenu {
      Button {
        UIPasteboard.general.string = message.text
      } label: {
        Label("复制", systemImage: "doc.on.doc")
      }
    }
  }

  // MARK: - Assistant

  private var assistantBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !message.steps.isEmpty {
        ActivityRail(
          steps: message.steps,
          streaming: message.isStreaming,
          chatId: chatId,
          durationMs: message.details.durationMs
        )
      }

      if message.isStreaming && message.text.isEmpty && message.steps.isEmpty {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small).tint(Brand.muted)
          Text("思考……")
            .font(.system(size: 15))
            .foregroundStyle(Brand.muted)
        }
      }

      if !message.text.isEmpty {
        MarkdownBody(text: message.text)
      }

      if let err = message.error, !err.isEmpty, err != message.text {
        ErrorNotice(text: err)
      }

      if !message.isStreaming, !artifactPaths.isEmpty {
        artifactRow
      }

      if !message.isStreaming {
        footer
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .contextMenu {
      Button {
        UIPasteboard.general.string = message.text
      } label: {
        Label("复制", systemImage: "doc.on.doc")
      }
    }
  }

  /// Files this reply produced, surfaced as tiles so the user doesn't have to go
  /// hunting in the workspace browser for what the agent just made.
  private var artifactPaths: [String] { WorkspaceLinks.paths(in: message.text) }

  private var artifactRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("产出文件")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.muted)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(artifactPaths, id: \.self) { rel in
            let name = (rel as NSString).lastPathComponent
            AttachmentTile(
              name: name,
              kind: .of(name),
              onTap: onOpenWorkspacePath.map { open in { open(rel) } }
            )
          }
        }
        .padding(.vertical, 2)
      }
    }
    .padding(.top, 2)
  }

  private var footer: some View {
    HStack(spacing: 0) {
      Button {
        UIPasteboard.general.string = message.text
        copied = true
        Task {
          try? await Task.sleep(nanoseconds: 1_400_000_000)
          copied = false
        }
      } label: {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
          .font(.system(size: 13))
          .foregroundStyle(Brand.muted)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("复制")

      if canRegenerate {
        Button {
          onRegenerate?()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Brand.muted)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .disabled(regenerateDisabled)
        .opacity(regenerateDisabled ? 0.35 : 1)
        .accessibilityLabel("重新生成")
      }

      if !message.details.isEmpty {
        Button { showDetails = true } label: {
          Image(systemName: "info.circle")
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .popover(isPresented: $showDetails) {
          MessageDetailsCard(details: message.details, isAdmin: isAdmin)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("详情")
      }

      Spacer()
    }
    .opacity(0.8)
  }

  private var compactionDivider: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        Rectangle().fill(Brand.line).frame(height: 1)
        Button {
          guard message.compactionSummary?.isEmpty == false else { return }
          withAnimation(Motion.easeOut(0.22)) { showCompaction.toggle() }
        } label: {
          HStack(spacing: 5) {
            Text("📋").font(.system(size: 11))
            Text("上下文压缩")
              .font(.system(size: 11))
              .foregroundStyle(Brand.muted)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 4)
          .background(showCompaction ? Brand.accent : Color.clear)
          .clipShape(Capsule())
          .overlay(Capsule().stroke(Brand.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        Rectangle().fill(Brand.line).frame(height: 1)
      }

      if showCompaction, let summary = message.compactionSummary, !summary.isEmpty {
        MarkdownBody(text: summary)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Brand.accent.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
              .stroke(Brand.line, lineWidth: 1)
          )
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
  }
}

// MARK: - Activity rail

struct ActivityRail: View {
  let steps: [MessageStep]
  let streaming: Bool
  /// Addresses the workspace stream for a step's rendered pages.
  var chatId: String?
  /// Turn duration from metadata, used for the "为 42s 工作" header.
  var durationMs: Int?

  @State private var expanded = false
  @State private var userToggled = false
  @State private var openStep: String?

  private var hasReasoning: Bool { steps.contains { $0.kind == .reasoning } }

  /// Same rules as the web `ActivityGroup` header.
  private var summary: String {
    if let durationMs {
      let text = Self.shortDuration(durationMs)
      return hasReasoning ? "针对 \(text) 的推理" : "为 \(text) 工作"
    }
    if streaming { return "思考……" }
    return hasReasoning ? "推理" : "活动"
  }

  private static func shortDuration(_ ms: Int) -> String {
    let sec = max(0, Int((Double(ms) / 1000).rounded()))
    if sec < 60 { return "\(sec)s" }
    let m = sec / 60
    let s = sec % 60
    return s > 0 ? "\(m)m \(s)s" : "\(m)m"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        userToggled = true
        withAnimation(Motion.easeOut(0.22)) { expanded.toggle() }
      } label: {
        HStack(spacing: 6) {
          Text(summary)
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
            .opacity(streaming ? 0.6 : 1)
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Brand.muted.opacity(0.4))
            .rotationEffect(.degrees(expanded ? 90 : 0))
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // Live runs open themselves and fold away once the answer starts, unless
      // the reader has taken manual control — same as the web.
      .onAppear { if streaming { expanded = true } }
      .onChange(of: streaming) { _, isStreaming in
        guard !userToggled else { return }
        withAnimation(Motion.easeOut(0.22)) { expanded = isStreaming }
      }

      if expanded {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(steps) { step in
            stepRow(step).capkaEntrance(.step)
          }
        }
        .padding(.top, 6)
        .overlay(alignment: .topLeading) {
          Rectangle()
            .fill(Brand.line)
            .frame(width: 1)
            .padding(.leading, 13)
            .padding(.vertical, 16)
        }
      }
    }
  }

  private func stepRow(_ step: MessageStep) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        guard step.detail != nil || !step.imagePaths.isEmpty else { return }
        withAnimation(Motion.easeOut(0.2)) {
          openStep = openStep == step.id ? nil : step.id
        }
      } label: {
        HStack(spacing: 10) {
          ZStack {
            Circle()
              .fill(Brand.cream)
              .frame(width: 27, height: 27)
              .overlay(Circle().stroke(Brand.line, lineWidth: 1))
            if step.state == .running {
              ProgressView().controlSize(.mini).tint(Brand.muted)
            } else {
              Image(systemName: step.state == .failed ? "exclamationmark.triangle" : step.icon)
                .font(.system(size: 12))
                .foregroundStyle(step.state == .failed ? Brand.dangerText : Brand.muted)
            }
          }

          Text(step.label)
            .font(.system(size: 13))
            .italic(step.kind == .reasoning)
            .foregroundStyle(step.state == .failed ? Brand.dangerText : Brand.ink.opacity(0.85))
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          if step.detail != nil || !step.imagePaths.isEmpty {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(Brand.muted)
              .rotationEffect(.degrees(openStep == step.id ? 90 : 0))
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if openStep == step.id {
        VStack(alignment: .leading, spacing: 8) {
          if let detail = step.detail {
            Text(detail)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(Brand.muted)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
              .background(Brand.accent)
              .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
          }
          if !step.imagePaths.isEmpty, let chatId {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(step.imagePaths, id: \.self) { path in
                  StepThumbnail(chatId: chatId, path: path)
                }
              }
            }
          }
        }
        .padding(.leading, 37)
      }
    }
    .padding(.vertical, 3)
  }
}

// MARK: - Error notice

struct ErrorNotice: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 13))
        .foregroundStyle(Brand.dangerText)
      Text(text)
        .font(.system(size: 13))
        .foregroundStyle(Brand.dangerText)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(Brand.dangerSurface)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
        .stroke(Brand.dangerBorder, lineWidth: 1)
    )
  }
}

// MARK: - Details popover

struct MessageDetailsCard: View {
  let details: MessageDetails
  let isAdmin: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let model = details.model {
        row("型号", model)
      }
      if let steps = details.stepCount {
        row("步骤", "\(steps)")
      }
      if let input = details.inputTokens {
        row("输入令牌", format(input))
      }
      if let output = details.outputTokens {
        row("输出 Token", format(output))
      }
      if let ms = details.durationMs {
        row("工作时间", duration(ms))
      }
      if let created = details.createdAt {
        row("已发送", created.formatted(date: .abbreviated, time: .shortened))
      }
    }
    .padding(14)
    .frame(minWidth: 220)
    .background(Brand.card)
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(Brand.muted)
      Spacer(minLength: 16)
      Text(value)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Brand.ink)
        .lineLimit(1)
    }
  }

  private func format(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
  }

  private func duration(_ ms: Int) -> String {
    let seconds = ms / 1000
    if seconds < 60 { return "\(seconds)s" }
    return "\(seconds / 60)m \(seconds % 60)s"
  }
}

// MARK: - Context meter

/// Ring that appears once the context window is at least half full, like the
/// web composer's meter. Tapping shows the raw token counts. Turns amber at the
/// ~75% mark where the server starts compacting, and adds the percentage then.
struct ContextMeter: View {
  let fill: Double
  let summary: String?

  @State private var showPopover = false

  private var warn: Bool { fill >= 0.75 }

  var body: some View {
    Button { showPopover = true } label: {
      HStack(spacing: 4) {
        if warn {
          Text("\(Int(min(1, fill) * 100))%")
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(Brand.warningText)
        }
        ZStack {
          Circle()
            .stroke(Brand.muted.opacity(0.35), lineWidth: 2)
          Circle()
            .trim(from: 0, to: min(1, fill))
            .stroke(
              warn ? Brand.warningText : Brand.primary.opacity(0.5),
              style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
      }
      .padding(.horizontal, 6)
      .frame(height: 34)
    }
    .popover(isPresented: $showPopover) {
      VStack(alignment: .leading, spacing: 4) {
        Text("上下文：\(Int(fill * 100))%")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Brand.ink)
        if let summary {
          Text(summary)
            .font(.system(size: 12))
            .foregroundStyle(Brand.muted)
        }
      }
      .padding(14)
      .presentationCompactAdaptation(.popover)
    }
  }
}

// MARK: - Attachment tile (88pt square, like the web FileTile)

struct AttachmentTile: View {
  let name: String
  let kind: FileKind
  var onRemove: (() -> Void)?
  /// Set on transcript tiles to open Quick Look. Never set together with
  /// `onRemove` — a tap gesture on the tile would fight the remove button.
  var onTap: (() -> Void)?

  var body: some View {
    if let onTap {
      tile
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    } else {
      tile
    }
  }

  private var tile: some View {
    VStack(spacing: 4) {
      ZStack {
        RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous)
          .fill(kind.tint)
          .frame(width: 88, height: 88)
          .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.xl, style: .continuous)
              .stroke(Brand.line, lineWidth: 1)
          )
        Image(systemName: kind.icon)
          .font(.system(size: 24))
          .foregroundStyle(kind.color)

        if let onRemove {
          Button(action: onRemove) {
            Image(systemName: "xmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(Brand.cream)
              .frame(width: 20, height: 20)
              .background(Brand.ink)
              .clipShape(Circle())
          }
          .offset(x: 40, y: -40)
        }
      }
      Text(name)
        .font(.system(size: 11))
        .foregroundStyle(Brand.muted)
        .lineLimit(1)
        .frame(width: 88)
    }
  }
}

// MARK: - Markdown

/// Block-level markdown renderer for assistant prose. Covers what the web's
/// Streamdown shows and what `.chat-prose` restyles: headings, hanging lists
/// (incl. nesting and task boxes), quote panels, GFM tables, fenced code with a
/// copy action, links, inline-code chips and horizontal rules.
struct MarkdownBody: View {
  let text: String

  private enum Block {
    case paragraph(String)
    case heading(String, Int)
    case bullet(String, indent: Int, checked: Bool?)
    case ordered(String, Int, indent: Int)
    case quote(String)
    case code(String, language: String?)
    case table(header: [String], rows: [[String]])
    case rule
  }

  var body: some View {
    // `.chat-prose` puts 0.75rem between blocks and tightens the gap under a
    // heading; list items sit closer together than paragraphs do.
    VStack(alignment: .leading, spacing: 0) {
      let items = blocks
      ForEach(Array(items.enumerated()), id: \.offset) { index, block in
        view(for: block)
          .padding(.top, topGap(at: index, in: items))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .tint(Brand.link)
  }

  private func topGap(at index: Int, in items: [Block]) -> CGFloat {
    guard index > 0 else { return 0 }
    if case .heading = items[index] { return 20 }
    let previousWasHeading: Bool = { if case .heading = items[index - 1] { return true } else { return false } }()
    if previousWasHeading { return 6 }
    let bothList = isListItem(items[index]) && isListItem(items[index - 1])
    return bothList ? 4 : 12
  }

  private func isListItem(_ block: Block) -> Bool {
    switch block {
    case .bullet, .ordered: return true
    default: return false
    }
  }

  @ViewBuilder
  private func view(for block: Block) -> some View {
    switch block {
    case .paragraph(let s):
      inline(s, size: 16)
        .lineSpacing(5)
        .textSelection(.enabled)
    case .heading(let s, let level):
      inline(
        s,
        size: headingSize(level),
        weight: .semibold,
        color: level >= 5 ? Brand.muted : Brand.ink
      )
      .tracking(level <= 1 ? -0.35 : level == 2 ? -0.2 : 0)
    case .bullet(let s, let indent, let checked):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if let checked {
          Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.system(size: 13))
            .foregroundStyle(checked ? Brand.primary.opacity(0.7) : Brand.muted)
        } else {
          Text("•").font(.system(size: 16)).foregroundStyle(Brand.muted)
        }
        inline(s, size: 16).lineSpacing(4)
      }
      .padding(.leading, CGFloat(indent) * 18)
    case .ordered(let s, let n, let indent):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(n).")
          .font(.system(size: 15))
          .monospacedDigit()
          .foregroundStyle(Brand.muted)
        inline(s, size: 16).lineSpacing(4)
      }
      .padding(.leading, CGFloat(indent) * 18)
    case .quote(let s):
      inline(s, size: 15, color: Brand.muted)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous))
    case .code(let s, let language):
      CodeBlock(code: s, language: language)
    case .table(let header, let rows):
      MarkdownTable(header: header, rows: rows)
    case .rule:
      Rectangle().fill(Brand.line).frame(height: 1).padding(.vertical, 4)
    }
  }

  private func headingSize(_ level: Int) -> CGFloat {
    switch level {
    case 1: return 24
    case 2: return 20
    case 3: return 18
    case 4: return 16
    default: return 15
    }
  }

  private func inline(
    _ raw: String,
    size: CGFloat,
    weight: Font.Weight = .regular,
    color: Color = Brand.ink
  ) -> Text {
    Text(MarkdownInline.attributed(raw, size: size, color: color))
      .font(.system(size: size, weight: weight))
      .foregroundColor(color)
  }

  private var blocks: [Block] {
    var result: [Block] = []
    var paragraph: [String] = []
    var codeLines: [String] = []
    var codeLanguage: String?
    var inCode = false
    var tableRows: [[String]] = []

    func flushParagraph() {
      let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if !joined.isEmpty { result.append(.paragraph(joined)) }
      paragraph.removeAll()
    }

    // A table needs its whole run of `|`-rows before it can be emitted; the
    // second row is the alignment divider and is dropped.
    func flushTable() {
      defer { tableRows.removeAll() }
      guard let header = tableRows.first else { return }
      let body = tableRows.dropFirst().filter { !$0.allSatisfy(Self.isAlignmentCell) }
      guard !body.isEmpty || tableRows.count == 1 else {
        result.append(.table(header: header, rows: []))
        return
      }
      result.append(.table(header: header, rows: Array(body)))
    }

    for line in text.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        if inCode {
          result.append(.code(codeLines.joined(separator: "\n"), language: codeLanguage))
          codeLines.removeAll()
          codeLanguage = nil
          inCode = false
        } else {
          flushParagraph()
          flushTable()
          let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
          codeLanguage = info.isEmpty ? nil : info.components(separatedBy: " ").first
          inCode = true
        }
        continue
      }
      if inCode {
        codeLines.append(line)
        continue
      }

      if trimmed.hasPrefix("|") {
        flushParagraph()
        tableRows.append(Self.tableCells(trimmed))
        continue
      }
      if !tableRows.isEmpty { flushTable() }

      if trimmed.isEmpty {
        flushParagraph()
        continue
      }
      if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        flushParagraph()
        result.append(.rule)
        continue
      }
      if trimmed.hasPrefix("#") {
        flushParagraph()
        let level = trimmed.prefix(while: { $0 == "#" }).count
        let body = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        result.append(.heading(body, level))
        continue
      }
      if trimmed.hasPrefix(">") {
        flushParagraph()
        result.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
        continue
      }

      let indent = Self.indentLevel(line)
      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
        flushParagraph()
        var body = String(trimmed.dropFirst(2))
        var checked: Bool?
        if body.hasPrefix("[ ] ") {
          checked = false
          body = String(body.dropFirst(4))
        } else if body.hasPrefix("[] ") {
          checked = false
          body = String(body.dropFirst(3))
        } else if body.lowercased().hasPrefix("[x] ") {
          checked = true
          body = String(body.dropFirst(4))
        }
        result.append(.bullet(body, indent: indent, checked: checked))
        continue
      }
      if let match = trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
        flushParagraph()
        let number = Int(trimmed[trimmed.startIndex..<trimmed.index(before: match.upperBound)]
          .trimmingCharacters(in: CharacterSet(charactersIn: ".) "))) ?? 1
        result.append(.ordered(String(trimmed[match.upperBound...]), number, indent: indent))
        continue
      }

      paragraph.append(line)
    }

    if inCode, !codeLines.isEmpty {
      result.append(.code(codeLines.joined(separator: "\n"), language: codeLanguage))
    }
    flushTable()
    flushParagraph()
    return result
  }

  private static func indentLevel(_ line: String) -> Int {
    var spaces = 0
    for ch in line {
      if ch == " " { spaces += 1 } else if ch == "\t" { spaces += 4 } else { break }
    }
    return min(3, spaces / 2)
  }

  private static func tableCells(_ line: String) -> [String] {
    var body = line
    if body.hasPrefix("|") { body.removeFirst() }
    if body.hasSuffix("|") { body.removeLast() }
    return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  private static func isAlignmentCell(_ cell: String) -> Bool {
    !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
  }
}

/// The `/workspace/…` paths an assistant writes are files it just produced, so
/// they must read as files, not as raw paths. Mirrors `remarkWorkspacePaths` +
/// `artifacts.ts` on the web: same pattern, same traversal rejection, same
/// "caption it with the file name" result.
enum WorkspaceLinks {
  static let scheme = "capka-workspace"

  /// Same expression as `WORKSPACE_PATH_RE`, including the Unicode classes that
  /// let zh-CN file names become links too.
  private static let pattern = #"/workspace/((?:(?!/workspace/)[\p{L}\p{N}\p{M}/._\- ()\[\]（）【】])+\.\w+)"#

  private static let regex = try? NSRegularExpression(pattern: pattern)

  /// A captured path is only safe if it stays inside the workspace. A prompt-
  /// injected reply could otherwise produce a tappable `/workspace/../../etc/…`.
  static func isSafe(_ rel: String) -> Bool {
    guard !rel.hasPrefix("/") else { return false }
    return rel.split(separator: "/", omittingEmptySubsequences: false)
      .allSatisfy { $0 != ".." && $0 != "." }
  }

  /// Unique workspace paths the reply names, first-seen order — the same
  /// definition of "artifact" the web and the Telegram channel use: only what
  /// the model actually named, never every file the run happened to touch.
  static func paths(in text: String) -> [String] {
    guard let regex else { return [] }
    let source = text as NSString
    var seen = Set<String>()
    var out: [String] = []
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      guard match.numberOfRanges > 1 else { continue }
      let rel = source.substring(with: match.range(at: 1))
      guard isSafe(rel), seen.insert(rel).inserted else { continue }
      out.append(rel)
    }
    return out
  }

  static func url(for rel: String) -> URL? {
    guard let encoded = rel.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
    return URL(string: "\(scheme)://open?path=\(encoded)")
  }

  static func path(from url: URL) -> String? {
    guard url.scheme == scheme else { return nil }
    guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "path" })?.value
    else { return nil }
    let rel = raw.removingPercentEncoding ?? raw
    return isSafe(rel) ? rel : nil
  }

  /// Rewrite bare paths — and paths the model wrapped in inline code — into
  /// markdown links captioned with the file name, before the string reaches the
  /// markdown parser.
  static func linkify(_ raw: String) -> String {
    guard let regex else { return raw }
    let source = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: source.length))
    guard !matches.isEmpty else { return raw }

    var out = ""
    var cursor = 0
    for match in matches {
      guard match.numberOfRanges > 1 else { continue }
      let rel = source.substring(with: match.range(at: 1))
      guard isSafe(rel), let url = url(for: rel) else { continue }

      // Swallow the backticks when the whole path sits in inline code, so the
      // result is one link rather than a link inside a code chip.
      var start = match.range.location
      var end = match.range.location + match.range.length
      if start > 0, end < source.length,
         source.substring(with: NSRange(location: start - 1, length: 1)) == "`",
         source.substring(with: NSRange(location: end, length: 1)) == "`" {
        start -= 1
        end += 1
      }
      guard start >= cursor else { continue }

      out += source.substring(with: NSRange(location: cursor, length: start - cursor))
      let name = (rel as NSString).lastPathComponent
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: "]", with: "\\]")
      out += "[\(name)](\(url.absoluteString))"
      cursor = end
    }
    guard cursor > 0 else { return raw }
    out += source.substring(from: cursor)
    return out
  }
}

/// Inline markdown → `AttributedString`, with the chip treatment `.chat-prose`
/// gives inline code and the palette's one accent hue for links.
enum MarkdownInline {
  static func attributed(_ raw: String, size: CGFloat, color: Color) -> AttributedString {
    var string = (try? AttributedString(
      markdown: WorkspaceLinks.linkify(raw),
      options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(raw)

    for run in string.runs {
      if run.inlinePresentationIntent?.contains(.code) == true {
        string[run.range].font = .system(size: size * 0.875, design: .monospaced)
        string[run.range].backgroundColor = Brand.accent
        string[run.range].foregroundColor = color
      }
      if let link = run.link {
        // A workspace file reads as a file, not as a web link: same accent, but
        // medium weight and underlined so it looks like something to open.
        if link.scheme == WorkspaceLinks.scheme {
          string[run.range].font = .system(size: size, weight: .medium)
          string[run.range].underlineStyle = .single
        } else {
          string[run.range].underlineStyle = nil
        }
        string[run.range].foregroundColor = Brand.link
      }
    }
    return string
  }
}

/// Fenced code: 13pt mono on a tinted panel that scrolls sideways rather than
/// wrapping, with the copy action the web floats into the block's top-right.
private struct CodeBlock: View {
  let code: String
  let language: String?

  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header row keeps the copy action clear of the code, the way Streamdown
      // structures the block (the web hides the label but keeps this row).
      HStack(spacing: 6) {
        Text((language ?? "").lowercased())
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(Brand.muted)
        Spacer(minLength: 8)
        Button {
          UIPasteboard.general.string = code
          copied = true
          Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
          }
        } label: {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(copied ? Brand.primary.opacity(0.7) : Brand.muted)
            .frame(width: 24, height: 20)
            .contentShape(Rectangle())
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 6)

      ScrollView(.horizontal, showsIndicators: false) {
        Text(code)
          .font(.system(size: 13, design: .monospaced))
          .foregroundStyle(Brand.ink)
          .textSelection(.enabled)
          .padding(.horizontal, 12)
          .padding(.bottom, 11)
          .padding(.top, 1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.accent)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
  }
}

/// GFM table. Columns size to their content and the whole grid scrolls sideways
/// on a narrow screen — the web makes the same call rather than crushing cells.
private struct MarkdownTable: View {
  let header: [String]
  let rows: [[String]]

  private var columnCount: Int {
    max(header.count, rows.map(\.count).max() ?? 0)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        row(header, isHeader: true)
        Divider().overlay(Brand.line)
        ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
          row(cells, isHeader: false)
          if index < rows.count - 1 {
            Divider().overlay(Brand.line)
          }
        }
      }
      .padding(.vertical, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Brand.card)
    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
        .stroke(Brand.line, lineWidth: 1)
    )
  }

  private func row(_ cells: [String], isHeader: Bool) -> some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(0..<columnCount, id: \.self) { column in
        Text(
          MarkdownInline.attributed(
            column < cells.count ? cells[column] : "",
            size: isHeader ? 12 : 13,
            color: isHeader ? Brand.muted : Brand.ink
          )
        )
        .font(.system(size: isHeader ? 12 : 13, weight: isHeader ? .semibold : .regular))
        .foregroundStyle(isHeader ? Brand.muted : Brand.ink)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 56, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
    }
  }
}


/// One page a tool rendered, streamed inline from the sandbox. `URLSession`'s
/// shared cookie jar is the one the API client authenticates with, so
/// `AsyncImage` is already signed in. A page rotated out of the sandbox 404s —
/// show nothing rather than a broken frame, matching the web.
private struct StepThumbnail: View {
  let chatId: String
  let path: String

  var body: some View {
    AsyncImage(url: CapkaAPIClient.shared.downloadURL(chatId: chatId, path: path, inline: true)) { phase in
      switch phase {
      case .success(let image):
        image
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 150)
          .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
              .stroke(Brand.line, lineWidth: 1)
          )
      case .failure:
        EmptyView()
      default:
        RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
          .fill(Brand.accent)
          .frame(width: 110, height: 150)
          .overlay(ProgressView().controlSize(.small).tint(Brand.muted))
      }
    }
  }
}
