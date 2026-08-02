import SwiftUI

/// Mirrors `chat.panel.getToWork` in `messages/zh-CN.json` — same four types,
/// same three verbs each, same prompt text seeded into the composer.
enum HomeStarters {
  struct Action {
    let label: String
    let prompt: String
    let icon: String
  }

  struct Group {
    let id: String
    let title: String
    let actions: [Action]
  }

  static let all: [Group] = [
    Group(id: "pdf", title: "PDF 文件", actions: [
      Action(label: "提取文本", prompt: "从我将附上的 PDF 中提取文本： ", icon: "text.viewfinder"),
      Action(label: "填写表格", prompt: "填写我将附上的 PDF 中的表单字段： ", icon: "square.and.pencil"),
      Action(label: "转换为Word", prompt: "将我要附加的 PDF 转换为可编辑的 Word 文档。", icon: "doc.text"),
    ]),
    Group(id: "spreadsheet", title: "电子表格", actions: [
      Action(label: "分析数据", prompt: "分析我将附上的电子表格并总结主要趋势： ", icon: "chart.bar"),
      Action(label: "构建图表", prompt: "从我将附上的电子表格中构建一个清晰的图表。", icon: "chart.xyaxis.line"),
      Action(label: "清理数据", prompt: "清理并整理我将附上的电子表格中的数据。", icon: "eraser"),
    ]),
    Group(id: "document", title: "文件", actions: [
      Action(label: "总结一下", prompt: "总结一下我将附上的文件： ", icon: "doc.plaintext"),
      Action(label: "翻译一下", prompt: "翻译我要附加的文件 ", icon: "character.book.closed"),
      Action(label: "让它看起来干净", prompt: "重新格式化我要附加的文档，使其看起来干净、专业。", icon: "text.alignleft"),
    ]),
    Group(id: "image", title: "图片", actions: [
      Action(label: "拉出文字", prompt: "从我要附加的图像中提取文本： ", icon: "doc.text.viewfinder"),
      Action(label: "删除背景", prompt: "从我要附加的图像中删除背景。", icon: "eraser"),
      Action(label: "调整大小或转换", prompt: "调整或转换我要附加的图像： ", icon: "crop"),
    ]),
  ]
}
