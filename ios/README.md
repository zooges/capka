# 邦信阳 iOS 客户端

飞书登录走 **飞书移动登录 SDK（LarkSSO）** 直接跳飞书 App 再回本 App。

本目录有两个并行工程，均为**原生 SwiftUI**（同一套 UI/能力，连不同 Capka 与飞书应用）：

| 工程 | 形态 | Bundle ID | 显示名 | Capka 地址 | 飞书 App ID | 深链 |
|------|------|-----------|--------|------------|-------------|------|
| `BossYoung.xcodeproj` | 原生 SwiftUI | `com.bossyoung.capka` | 邦信阳 | `http://111.231.24.43:3100` | `cli_aaeda20205b41ce4` | `bossyoung://` |
| `BossYoung2.xcodeproj` | 原生 SwiftUI（同源复刻） | `com.bossyoung.capka2` | 邦信阳 | `https://agent.boss-young.com` | `cli_aae198a5e278dcc7` | `bossyoung2://` |

```bash
open ios/BossYoung.xcodeproj   # 现网
open ios/BossYoung2.xcodeproj  # 内网 / agent.boss-young.com
```

两工程共用 `ios/Vendor/LarkSSOSDK.xcframework` 与 `LarkSSO.bundle`。

## 原生能力（两工程相同）

直接调 Capka HTTP API，不加载网页：`CapkaAPIClient` 走 cookie 会话，`SSEClient`
接 `/api/events` 的实时流，`ChatViewModel` 在 SSE 漏掉 finish 时回退到轮询
`latestTask`。UI 对齐 Web 端：`FileKinds.swift` 对应 `src/lib/file-kinds.ts`，
首页的「开始工作」四类动作对应 `messages/zh-CN.json` 的 `chat.panel.getToWork`。

| 项 | 说明 |
|----|------|
| 附件 | 回形针菜单：照片（`PhotosPicker`）/ 拍照（相机）/ 文件。图片按最长边 2048px 缩放，HEIC 转 JPEG，PNG 保留 |
| 文件预览 | 工作区文件与对话中的附件点击后经会话下载再交给 Quick Look；导出走 Quick Look 自带的分享按钮 |
| 语音输入 | `SFSpeechRecognizer` 直接写入输入框 |
| 设置 | 分组列表 + 二级页（与项目、归档、工作区同一套列表样式） |
| 调试 | `CAPKA_UI_FIXTURES=1` 用假数据启动；`CAPKA_OPEN_SCREEN` / `CAPKA_OPEN_CHAT` 跳到某个界面；`CAPKA_UI_FIXTURES_ADMIN=1` 以管理员身份进入（均仅 Debug） |

品牌图与启动底色都带深色变体，主题可在侧边栏账户区或设置 → 通用 → 外观切换。

差异仅在 `AppConfig`（`baseURL` / `urlScheme`）、`FeishuNativeSSO.feishuAppId`、
`Info.plist` 的 URL Types，以及 Bundle ID。

## 飞书登录（App）

### 邦信阳（现网 / BossYoung）

1. 开放平台自建应用 → **添加能力 → 移动应用登录**（并发布）。
2. 填写 iOS：Bundle ID `com.bossyoung.capka`，Team ID `5FSTWGBV38`。
3. App 内点「使用飞书登录」→ 跳飞书 → 授权 → 经 scheme `cliaaeda20205b41ce4` 回 App → `/api/auth/feishu/native` 落 session。

### 邦信阳（capka2 / BossYoung2）

1. **另一套**飞书自建应用（App ID `cli_aae198a5e278dcc7`）→ 移动应用登录。
2. Bundle ID `com.bossyoung.capka2`，Team ID `5FSTWGBV38`；回跳 scheme `cliaae198a5e278dcc7`。
3. 在对应 Capka（`https://agent.boss-young.com`）管理后台 Authentication 填该应用的 App ID / Secret 并开启飞书登录。
4. 平台建议设 `CAPKA_IOS_URL_SCHEME=bossyoung2`，以便 Safari OAuth 回调桥回本 App（原生 LarkSSO 主路径不依赖此项）。

网页 OAuth 重定向仍为各实例自己的：

```text
https://agent.boss-young.com/api/auth/oauth2/callback/feishu
```

飞书**工作台 / 内置浏览器**登录不会再跳 `bossyoung(2)://`（服务端按 UA 跳过桥接）。

## 手势与反馈

| 项 | 说明 |
|----|------|
| 左边缘右滑 | 打开侧边栏 |
| 助手回复完成 | 震动 + 短提示音；退到后台 / 非前台时本地通知 |

## 后台与通知（iOS 限制）

iOS **不允许** App 在划到桌面后无限期常驻。两工程都靠 `beginBackgroundTask`
撑住系统预算（通常约 **30 秒**）：`CapkaFeedback` 在后台按 2 秒轮询
`latestTask`，连续两次读到终态才算结束。

**真正结束后**才发本地通知，标题「回答已完成」，正文为回复摘要（需用户允许通知权限）。
后台预算用尽时**不会**发「回复可能仍在服务器处理」这类误导通知；任务在服务器继续跑，
回到 App 时会再检查一次，若已完成则补发完成反馈。

未使用静音音频保活，也不能指望 BGAppRefresh 接住流式回复。

Xcode 选 Team → 真机 / TestFlight。两个工程在 App Store Connect 各自建应用
（`com.bossyoung.capka` / `com.bossyoung.capka2`），主屏幕显示名都是「邦信阳」。
