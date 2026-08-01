# 邦信阳 iOS 客户端（移动端套壳）

SwiftUI + `WKWebView` 加载 Capka；飞书登录走 **飞书移动登录 SDK（LarkSSO）** 直接跳飞书 App 再回本 App。

本目录有两个并行工程：

| 工程 | Bundle ID | 显示名 | Capka 地址 | 飞书 App ID | 深链 |
|------|-----------|--------|------------|-------------|------|
| `BossYoung.xcodeproj` | `com.bossyoung.capka` | 邦信阳 | `http://111.231.24.43:3100` | `cli_aaeda20205b41ce4` | `bossyoung://` |
| `BossYoung2.xcodeproj` | `com.bossyoung.capka2` | 邦信阳 | `https://agent.boss-young.com` | `cli_aae198a5e278dcc7` | `bossyoung2://` |

```bash
open ios/BossYoung.xcodeproj   # 现网
open ios/BossYoung2.xcodeproj  # 内网并行 TestFlight
```

两工程共用 `ios/Vendor/LarkSSOSDK.xcframework` 与 `LarkSSO.bundle`。

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
| 左边缘右滑 | 打开侧边栏 |
| 右边缘左滑 | 回到 `/chat`（设置页优先 SPA 跳转，避免整页重载） |
| 助手回复完成 | 震动 + 短提示音；退到后台 / 非前台时本地通知 |

## 后台与通知（iOS 限制）

iOS **不允许** App 在划到桌面后无限期常驻。本壳的做法：

1. 页面检测到助手正在生成时，经 JS bridge 通知原生（`replyBusy`）；网页侧同时写 `data-capka-busy`。
2. 进入后台时调用 `beginBackgroundTask`，并在原生侧定时轮询 busy 状态（后台 JS `setInterval` 会被系统大幅节流），尽量在系统预算内（通常约 **30 秒**）等到真实结束。
3. **真正结束后**（`replyDone` 或原生轮询发现 busy→idle）发本地通知，标题为「回答已完成」，正文为回复摘要（需用户允许通知权限）。
4. 后台预算用尽时**不会**再发「回复可能仍在服务器处理」这类误导通知；任务在服务器可继续，回到 App 后会再检查一次，若已完成则补发完成反馈。
5. 超长任务（冷启动沙箱 + 多工具调用数分钟）在挂起后无法再本地侦测完成——那需要服务端推送（当前未做）。

未使用静音音频保活。真正保活靠 `beginBackgroundTask`，不能指望 BGAppRefresh 接住流式回复。

## 其它

| 项 | 说明 |
|----|------|
| 下拉刷新 | `UIRefreshControl` |
| 文件预览 | 系统 Quick Look |
| 安全区 | 注入 `--native-sa*` 与 `--capka-sa*`（对齐 `globals.css`） |
| 键盘高度 | 注入 `--native-kb`（UIKeyboard 与 WebView 重叠高度）；网页 `useKeyboardInset` 取 `max(visualViewport, --native-kb)` 抬升对话页 composer |
| 键盘上方工具条 | 隐藏 WKWebView 自带的表单导航条（← → 完成），非 Capka UI |

Xcode 选 Team → 真机 / TestFlight。此工程（BossYoung2）需在 App Store Connect 单独建应用（Bundle ID `com.bossyoung.capka2`），主屏幕显示名为「邦信阳」。
