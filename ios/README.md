# 邦信阳 iOS 客户端

飞书登录走 **飞书移动登录 SDK（LarkSSO）** 直接跳飞书 App 再回本 App。

本目录有两个并行工程，形态不同：

| 工程 | 形态 | Bundle ID | 显示名 | Capka 地址 | 飞书 App ID | 深链 |
|------|------|-----------|--------|------------|-------------|------|
| `BossYoung.xcodeproj` | **原生 SwiftUI** | `com.bossyoung.capka` | 邦信阳 | `http://111.231.24.43:3100` | `cli_aaeda20205b41ce4` | `bossyoung://` |
| `BossYoung2.xcodeproj` | `WKWebView` 套壳 | `com.bossyoung.capka2` | 邦信阳 | `https://agent.boss-young.com` | `cli_aae198a5e278dcc7` | `bossyoung2://` |

```bash
open ios/BossYoung.xcodeproj   # 现网（原生）
open ios/BossYoung2.xcodeproj  # 内网并行 TestFlight（套壳）
```

两工程共用 `ios/Vendor/LarkSSOSDK.xcframework` 与 `LarkSSO.bundle`。

## 原生工程（BossYoung）

直接调 Capka HTTP API，不加载网页：`CapkaAPIClient` 走 cookie 会话，`SSEClient`
接 `/api/events` 的实时流，`ChatViewModel` 在 SSE 漏掉 finish 时回退到轮询
`latestTask`。UI 对齐 Web 端：`FileKinds.swift` 对应 `src/lib/file-kinds.ts`，
首页的「开始工作」四类动作对应 `messages/zh-CN.json` 的 `chat.panel.getToWork`。

| 项 | 说明 |
|----|------|
| 附件 | 回形针菜单：照片（`PhotosPicker`）/ 拍照（相机）/ 文件。图片按最长边 2048px 缩放，HEIC 转 JPEG，PNG 保留 |
| 文件预览 | 工作区文件与对话中的附件点击后经会话下载再交给 Quick Look；导出走 Quick Look 自带的分享按钮 |
| 语音输入 | `SFSpeechRecognizer` 直接写入输入框 |
| 调试 | `CAPKA_UI_FIXTURES=1` 用假数据启动；`CAPKA_OPEN_SCREEN` / `CAPKA_OPEN_CHAT` 直接跳到某个界面（仅 Debug） |

## 飞书登录（App）

### 邦信阳（现网）

1. 开放平台自建应用 → **添加能力 → 移动应用登录**（并发布）。
2. 填写 iOS：Bundle ID `com.bossyoung.capka`，Team ID `5FSTWGBV38`。
3. App 内点「使用飞书登录」→ 跳飞书 → 授权 → 经 scheme `cliaaeda20205b41ce4` 回 App → `/api/auth/feishu/native` 落 session。

### 邦信阳（capka2 / 内网）

1. **另一套**飞书自建应用（App ID `cli_aae198a5e278dcc7`）→ 移动应用登录。
2. Bundle ID `com.bossyoung.capka2`，Team ID `5FSTWGBV38`；回跳 scheme `cliaae198a5e278dcc7`。
3. 在对应 Capka（`https://agent.boss-young.com`）管理后台 Authentication 填该应用的 App ID / Secret 并开启飞书登录。
4. 平台建议设 `CAPKA_IOS_URL_SCHEME=bossyoung2`，以便 Safari OAuth 回调桥回本 App（原生 LarkSSO 主路径不依赖此项）。

网页 OAuth 重定向仍为各实例自己的：

```text
http://<host>:3100/api/auth/oauth2/callback/feishu
```

飞书**工作台 / 内置浏览器**登录不会再跳 `bossyoung(2)://`（服务端按 UA 跳过桥接）。

## 手势与反馈

| 项 | 说明 |
|----|------|
| 左边缘右滑 | 打开侧边栏（两工程一致） |
| 右边缘左滑 | 套壳：回到 `/chat`（设置页优先 SPA 跳转，避免整页重载） |
| 助手回复完成 | 震动 + 短提示音；退到后台 / 非前台时本地通知 |

## 后台与通知（iOS 限制）

iOS **不允许** App 在划到桌面后无限期常驻。两个工程都靠 `beginBackgroundTask`
撑住系统预算（通常约 **30 秒**），差别只在「怎么知道回复结束了」：

- **原生**：`CapkaFeedback` 在后台按 2 秒轮询 `latestTask`，连续两次读到终态才算结束。
- **套壳**：网页写 `data-capka-busy`，原生定时 `evaluateJavaScript` 读它（后台 JS `setInterval` 会被系统大幅节流）。

**真正结束后**才发本地通知，标题「回答已完成」，正文为回复摘要（需用户允许通知权限）。
后台预算用尽时**不会**发「回复可能仍在服务器处理」这类误导通知；任务在服务器继续跑，
回到 App 时会再检查一次，若已完成则补发完成反馈。超长任务（冷启动沙箱 + 多工具调用
数分钟）在挂起后无法再本地侦测完成——那需要服务端推送（当前未做）。

未使用静音音频保活，也不能指望 BGAppRefresh 接住流式回复。

## 套壳工程专有（BossYoung2）

| 项 | 说明 |
|----|------|
| 下拉刷新 | `UIRefreshControl` |
| 文件预览 | JS bridge `capkaPreview` → 原生下载 → Quick Look |
| 安全区 | 注入 `--native-sa*` 与 `--capka-sa*`（对齐 `globals.css`） |
| 键盘高度 | 注入 `--native-kb`（UIKeyboard 与 WebView 重叠高度）；网页 `useKeyboardInset` 取 `max(visualViewport, --native-kb)` 抬升对话页 composer |
| 键盘上方工具条 | 隐藏 WKWebView 自带的表单导航条（← → 完成），非 Capka UI |

Xcode 选 Team → 真机 / TestFlight。两个工程在 App Store Connect 各自建应用
（`com.bossyoung.capka` / `com.bossyoung.capka2`），主屏幕显示名都是「邦信阳」。
