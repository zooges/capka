# Changelog

All notable changes to Capka are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- iOS Share Extension on BossYoung and BossYoung2: share files/images from WeChat (and the system share sheet) into a chosen or new chat as composer attachments. Capka-styled picker UI; opens the host app via `UIApplication.open` (iOS 18-safe). Requires App Group `group.com.bossyoung.capka` / `group.com.bossyoung.capka2` on the Apple Developer App IDs; new iOS build.
- Sandbox image installs Tesseract Simplified/Traditional Chinese (`tesseract-ocr-chi-sim`, `tesseract-ocr-chi-tra`) alongside English. Rebuild the sandbox image locally (`npm run sandbox:build`); do not `docker compose pull`.
- `docker-compose.mcp.yml` wechat sidecar: host mihomo proxy (`WECHAT_HTTPS_PROXY`, default `http://172.17.0.1:7890`), persistent cache volume, search/fetch rate limits and circuit-breaker env knobs. Capka on the same host should seed `MCP_WECHAT_URL=http://wechat-article-mcp:8809/mcp`; public `weixin.zooges7000.top` can remain a separate instance. See `docs/CHINA-FORK.md`.
- Project / workspace Files: upload menu can import a whole folder (web one-shot or live connect when enabled; iOS recursive upload into `/workspace/<name>/`). Bulk `/api/folders/upload` no longer requires `pc_folder_access` (live folder *connect* still does). Recreate platform; new iOS build.
- Public `/privacy` page (no login) for App Store privacy-policy URL; `src/proxy.ts` allows anonymous access. Recreate platform.
- Native macOS client (`ios/BossYoungMac`, target `BossYoungMac`, macOS 14+) sharing the iOS core under the same bundle id: sidebar + transcript window, ⌘N/⌘, , Touch ID lock, project files. Feishu signs in via web OAuth (the SDK has no macOS slice). No server change.
- iOS push notifications for finished turns (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_P8`). Unset leaves the previous behaviour; a migration adds `push_tokens`.
- iOS app (`ios/`) is now a native SwiftUI client instead of the WKWebView shell: Feishu login, streaming chat with tool steps, chat rename/pin/archive/move, projects + workspace files, and settings (skills, connectors, automations, memory). Web-matched visuals; no server change. New iOS build.
- `CAPKA_TAVILY_STEER` gates China open-web Tavily-first prompt steer (default on when `CAPKA_REGION=cn`). Set `CAPKA_TAVILY_STEER=0` or `CAPKA_WEB_SEARCH=open` on intranet hosts for open curl/Google/Bing without forcing Tavily. Passed through compose; recreate platform after changing.
- `CAPKA_IOS_URL_SCHEME` selects the Feishu Safari→iOS-shell OAuth bridge scheme (`bossyoung` default; `bossyoung2` for the intranet 邦信阳2 app). Passed through compose; recreate platform after changing.
- `MCP_ALWAYS_LOAD` keeps listed MCP servers active under progressive disclosure (no `find_tool` hop). When unset/empty and `CAPKA_REGION=cn`, defaults to `tavily`. Set `MCP_ALWAYS_LOAD=none` to disable. Passed through compose; recreate platform after changing.
- `CAPKA_REGION=cn` (or `CAPKA_CHINA=1`) scopes **Tavily MCP to general web search only** (查网页/新闻/公开互联网；call directly — already configured; never `pip install` / marketplace / `find_tool` for it). Domain MCPs (法律/元典/企查查/微信等) stay on their connectors via `find_tool` when deferred. Overseas URL fetch and Google/Bing/Baidu last-resort SERP via `curl` are allowed when sandbox egress works. Documented in `docs/CHINA-FORK.md`. Recreate the platform image after setting.
- `npm run mcp:seed-china` registers the official remote Tavily MCP (`tavily` → `https://mcp.tavily.com/mcp/`) when `TAVILY_API_KEY` is set; without the key the row is prepared disabled. Use `MCP_SEED_ONLY=tavily` to seed only that connector.

### Changed

- Default `SANDBOX_MEMORY_MB` is 2048 (was 1024 in compose / 512 in controller fallback) so scanned-PDF Chinese OCR has headroom after tmpfs. Existing hosts: set in `.env` or recreate sandbox-controller.
- iOS model brand icons download once into Application Support (memory + disk); model list prefetch warms light/dark glyphs so the picker/chip no longer re-hit jsDelivr every paint. New iOS build.
- iOS local-first cache: chat list + transcripts (recent chats prefetched), workspace listings, uploads ingested on the phone, generated/uploaded files warmed after tool writes, preview keys shared between chat chips and workspace, image thumbs prefer disk. New iOS build.
- iOS chat: follow-scroll pins to a transcript-end anchor (no longer stuck on the previous turn while streaming); file previews always cache under Application Support (chat chips included); image attachment tiles show sandbox thumbnails like the web. New iOS build.
- `GET /api/chats?search=` matches chat **title or message body** (and message metadata text), not title alone. Recreate platform. iOS sidebar placeholder says「搜索标题或内容」; local cache also scans cached transcripts. New iOS build.
- iOS sidebar search ignores cancelled keystroke requests (no more false “网络错误”), filters titles from the on-disk chat index immediately, and falls back to that cache when the host is unreachable. Chat list + last-opened transcripts are cached under Application Support for faster reopen / brief offline. New iOS build.
- iOS workspace / chat file preview caches downloads on disk (keyed by path + size/mtime), streams via `URLSession.download`, and prefetches small files after a folder list — second open is local; first open still needs the phone→host round trip. New iOS build.
- iOS sidebar account row sits lower with safe-area padding and shows the Feishu profile photo when `user.image` is present (same source as the web). New iOS build.
- iOS chat: mid-turn reloads no longer wipe richer streamed prose/groups; workspace drawer refreshes when tools write files or markup uploads; workspace UI adds refresh/upload chrome and “添加到对话”; PDF preview disables Quick Look’s native markup so only Capka 批注 remains, with per-page stroke isolation. New iOS build.
- iOS chat: tap outside the composer dismisses the keyboard and restores the home layout; model picker/chip show provider brand logos (same lobehub glyphs as the web); live SSE streams reasoning + tool/command steps into the activity rail (with poll fallback when SSE is blocked); workspace opens from a right-edge swipe on the conversation page. New iOS build.
- iOS native client: sidebar restores `BOSS & YOUNG` wordmark; account menu matches web (search / projects / archived / appearance / settings / sign-out); system/light/dark theme; mic control sits right of the composer; settings nav aligns with web personal + admin tabs (connections, users, usage, auth, activity, updates, …). New iOS build.
- iOS native client: home drops the「我能帮忙做什么」greeting (logo + composer only); assistant markdown gains tables / task lists / copyable code / link tint; message and step entrances follow the web motion curve. Capka `URLSession` ignores the system HTTP proxy so office IP deploys stay reachable under Shadowrocket. New iOS build.
- iOS login adds email/password under the Feishu button (same `POST /api/auth/sign-in/email` path as the web). New iOS build.
- iOS login screen is vertically centered with filled fields, focus rings, password reveal, and deferred notification permission (no prompt over the sign-in form). New iOS build.
- iOS login adds email sign-up (`POST /api/auth/sign-up/email`) with name/email/password; respects `registration-status` and pending-approval accounts. New iOS build.
- iOS: settings redesigned to web personal tabs (general / extensions / memory / automations) with usage limits and Telegram link; latest assistant turn gains regenerate; composer adds speech-to-text mic; left-edge swipe opens sidebar and swipe-left closes it. New iOS build.
- Empty home / new chat no longer shows a rotating welcome line — brand mark + composer only (same as iOS). Recreate platform.

### Fixed

- Composer "Select project" menu items now navigate (Base UI uses `onClick`, not Radix `onSelect`). Recreate platform.
- Project hub Settings shows Delete for every project owner (was incorrectly admin-only). Recreate platform; new iOS build for the settings delete control.
- WeChat MCP sidecar: Sogou/WeChat egress goes through host mihomo (`WECHAT` select + allowlist rotate via `MIHOMO_*` / `WECHAT_ROTATE_EVERY`); `WECHAT_NO_PROXY` defaults to intranet only. Existing host deploys: update compose/`.env` and restart the MCP.
- iOS: new-chat from the conversation top bar no longer resurrects the previous transcript (SSE chatId adoption + load race); ask cards survive rapid SSE bursts via an event queue; thinking rail no longer bounces while reasoning streams. New iOS build.
- iOS: finished thinking no longer keeps pulsing while the answer streams; reopening a chat no longer replays entrance animations on every historical reasoning row. New iOS build.
- Project Files / workspace UI copy is Simplified Chinese; legacy `user.locale=uk` is rewritten to `zh-CN` so labels never stay Ukrainian. iOS language picker drops Українська. Recreate platform; new iOS build for the settings picker.
- Moving a chat into a project no longer creates a Ukrainian carry-over folder (`Із чату «…»`); it uses `来自对话「…」` instead. Recreate platform. Already-created folders keep their old names until renamed/removed.
- iOS model catalog refreshes from `/api/models` on home, new chat, model picker open, and foreground (no longer stuck on the first in-memory list after web admin changes). New iOS build.
- iOS chat: follow-scroll no longer lands past the transcript (blank viewport after send/regenerate). Eager VStack + pin to the last message bottom after layout. New iOS build.
- iOS speech-to-text: avoid crashing when tearing down the audio tap; clearer errors when the simulator has no mic. New iOS build.
- DeepSeek / gateway `Content Exists Risk` (and similar content-filter refusals) now map to a calm `content_blocked` message instead of the raw provider string. Recreate platform.
- Always-load MCP servers (China default `tavily`) are connected on the current turn even with a cold schema cache, and a cached always-load server is pre-dialed so the first `tavily_search` skips a second `initialize`. Stops the agent from falling back to `pip install tavily-python` / empty `find_tool` after platform restart. Recreate platform.
- China prompt + deferred MCP index no longer steer every retrieval to Tavily; domain connectors (chineselaw / wechat / company registry) stay reachable via `find_tool`. Chinese `find_tool` intents for 法律/企查查/微信 expand to those servers instead of Tavily. Recreate platform.
- Login / auth screens vertically center on mobile and the iOS WKWebView shell (were top-pinned under the status bar). Recreate platform.
- Chinese-only `find_tool` queries such as「搜索网页」no longer match zero tools (BM25 was Latin-only); common zh **open-web** search intents expand to English terms that hit Tavily, while domain zh intents expand to the matching connector. Recreate platform.
- Empty home / new-chat: stays centered until focus/typing/keyboard; then collapses recent/starters so logo + composer recenter above the keyboard (matches web). In-chat uses an in-flow bottom dock + outer `--kb` padding (no `translateY`) so the composer cannot overlap messages; model chip stays in the top header. Recreate platform; new iOS build.
- In-chat keyboard: `--kb` no longer under-counts when WK `visualViewport.offsetTop` races the scroll pin (raw height gap + iOS `--native-kb` from keyboard frame). Composer stays above the keyboard on conversation pages. Recreate platform; new iOS build.
- Empty home focus: history collapse and logo/composer reflow animate (~320ms); model chip sits below the composer with a real gap (no negative margin overlap). Recreate platform.
- Removed the home `greetingHint` copy (en / zh-CN / uk), including「将文件拖放到此处…」. Recreate platform.
- iOS shell: keyboard no longer insets/offsets WK’s scroll view on top of web `--kb` (pins content offset + content inset). New iOS build.
- iOS shell: background-task expiration no longer posts the misleading 「回复可能仍在服务器处理」 local notification or clears the in-flight reply watch. Completion notifications use title「回答已完成」+ preview, and the shell re-checks busy→idle on return to the app. New iOS build; recreate platform for the React `replyBusy`/`replyDone` bridge.
- DeepSeek V4 DSML tool calls that leaked into assistant text through OpenAI-compatible gateways (LiteLLM, etc.) are parsed into real tool executions instead of showing protocol markup. Recreate the platform image after pulling.
- Reply copy button works in the iOS WKWebView shell via a native clipboard bridge (`clipboardWrite` → UIPasteboard) plus `execCommand` fallback. New iOS build; recreate platform for the web fallback.

### Security

- Settings → Connectors stays visible to every role, but MCP endpoint URLs are admin-only (web + iOS UI). `GET /api/mcp` redacts `url` for non-admins; the manage `mcp` list shows only "remote"/"local" for members. Recreate platform; new iOS build.

### Changed

- China sandbox prompt requires a real `curl`/`wget`/MCP attempt before claiming Google/YouTube/overseas sites are blocked; invent-GFW excuses stay forbidden. Recreate platform.
- China `CAPKA_REGION=cn` sandbox prompt no longer forbids overseas URLs or Google SERP via `curl`; it states the host can reach domestic and foreign sites (use `SANDBOX_*_PROXY` when needed) and tells the model not to invent GFW/"连接会被阻断" excuses when egress is on. Tavily-first remains the default for cn unless `CAPKA_TAVILY_STEER=0`. Recreate platform.
- `docker-compose.yml` sets `pull_policy: never` on platform and sandbox-controller so `compose up` no longer re-pulls GHCR and overwrites a locally tagged China-fork image. Upgrade with an explicit `docker compose pull` when intended.
- MCP tool-schema cache is process-wide (`globalThis`) and disk-backed (`/tmp/capka-mcp-tool-schemas.json`) so Next.js module duplication no longer forces a cold HTTP reconnect every turn. Recreate the platform image after pulling.
- HTTP MCP connectors no longer block time-to-first-token: schemas come from an in-process cache and connect only on the first tool call (cold cache warms schema-only in the background, then hangs up), same as stdio. A prior path still eagerly `await`ed every HTTP `initialize` in batches of 4 (~1–2s each), which dominated simple-chat latency even with `MCP_DEFER_TOKEN_PCT=0`. Recreate the platform image after pulling.
- Deferred MCP system-prompt index is now connector name + tool count only (no capability essays). `find_tool` BM25 still uses full descriptions.
- DeepSeek reasoning defaults to thinking disabled (`thinking:{type:disabled}`). V4 maps `low`/`medium` → `high` server-side, so those values never sped replies. Override with `REASONING_EFFORT=high|max` (passed through compose).
- MCP progressive disclosure now also clamps the always-on connector budget with `MCP_DEFER_TOKEN_MAX` (default 8192, compose-passed). On ~1M-token models, percent-only gating (`MCP_DEFER_TOKEN_PCT=10`) left heavy MCP schemas always-on; the absolute cap forces `find_tool` without requiring `pct=0`. Set `MCP_DEFER_TOKEN_MAX=0` for percent-only; recreate platform after changing.
- `MCP_DEFER_TOKEN_PCT` is now passed through `docker-compose.yml` into the platform, documented in `.env.example`, and treats `0` as always-defer (previously `|| 10` ignored an intentional zero). On large-window models, set `MCP_DEFER_TOKEN_PCT=1` (or `0`) then recreate platform so heavy MCP schemas load via `find_tool` instead of every turn.
- Assistant persona identity is now **B&Y AI助手** (system prompt + Telegram/login copy); product UI prefers 邦信阳 / BOSS & YOUNG over Capka. Redeploy the platform image after pulling.

### Added

- iOS shell Feishu Mobile SSO (LarkSSO): jumps to the Feishu app and returns via the App ID URL scheme; Capka completes login at `GET/POST /api/auth/feishu/native`. Requires Feishu「移动应用登录」for Bundle ID `com.bossyoung.capka`. See `ios/README.md`.
- iOS shell: left-edge swipe opens the sidebar; right-edge swipe goes to `/chat`; haptic + sound (and a local notification if backgrounded) when an assistant reply finishes.
- iOS shell: while a reply is in flight, `beginBackgroundTask` keeps the WKWebView alive briefly after swipe-to-home and posts a local notification on `replyDone` (≈30s OS limit — see `ios/README.md`).
- `/api/auth/registration-status` includes public `feishu.appId` when Feishu login is enabled.
- iOS mobile shell under `ios/` (SwiftUI + WKWebView): fixed `http://111.231.24.43:3100`, shared web Feishu login, pull-to-refresh, in-app Feishu OAuth hosts, offline retry, injects `capka-native-app` for mobile CSS. See `ios/README.md`.
- Simplified Chinese (`zh-CN`) locale with full UI strings; Chinese `Accept-Language` tags resolve to `zh-CN`.
- Feishu / Lark OAuth login (admin Authentication settings + login button).
- Configurable product brand via `NEXT_PUBLIC_PRODUCT_NAME` / `PRODUCT_NAME` (fork default: 邦信阳 / Boss & Young mark).
- Legal skills pack (`skills-pack/legal/*`) and `npm run skills:seed-legal` seeder.
- China-team fork operator guide: `docs/CHINA-FORK.md`.
- MCP SSE remote transport end-to-end (persist, probe, load tools); China MCP sidecars via `docker-compose.mcp.yml` and `npm run mcp:seed-china`.
- MCP connector token update in Connectors UI (Bearer header, encrypted at rest).
- Large zh-CN translation quality pass (auth method, tokens, marketplace, nav).

### Fixed

- iOS / mobile Settings (incl. Connectors): content stays inside the viewport — safe-area padding on the settings chrome, no horizontal bleed from connector action rows / tab strips, and native shell overflow-x lockdown. Redeploy platform; new iOS build recommended.
- iOS WKWebView shell: native safe-area CSS fallback is now `47px` (notch-class) when `--native-sat` has not been pushed yet, so opening a project from the sidebar no longer leaves the title under the status bar. Redeploy platform; new iOS build recommended.
- iOS native shell: project / projects list top chrome no longer sits under the status bar / Dynamic Island — injects `--native-sa*` (matching `globals.css`) and keeps safe-area padding on `md` breakpoints. New iOS build; redeploy platform for the extra project-hub top padding.
- Feishu Mobile SSO (`/api/auth/feishu/native`) now mints session cookies with better-call's standard base64 HMAC (the previous `base64urlnopad` signature was rejected by better-auth, so iOS returned from Feishu still bounced to `/login`). Native exchange omits `redirect_uri`; iOS prefers POST + cookie inject then `/chat`. Redeploy platform; new iOS build required for the client path.
- Feishu OAuth on phone no longer 302s workplace / in-app webviews to `bossyoung://` (UA `Lark` / `Feishu` / …). Login stays in the Feishu web app; only non-Feishu mobile browsers without `capka_native` still bridge to the iOS shell. Redeploy the platform image after pulling.
- Mobile inputs that auto-focus (sidebar chat search, command palette, model picker search) no longer trigger iOS/WKWebView page zoom — they use 16px (`text-base`) under `md`.
- File preview fullscreen keeps the top toolbar below the notch / status bar (`safe-area` + `100dvh` pin) so close / download stay tappable.
- iOS shell: downloading a file no longer leaves the top ProgressView spinning (attachment / frame-interrupted navigations now clear `isLoading`).
- iOS shell: Feishu phone login opens the Feishu app; the HTTP callback is bridged back via `bossyoung://oauth` into the WKWebView (no tunnel domain required).
- Assistant replies that name Chinese (or other non-ASCII) `/workspace/…` files again render inline chips and artifact tiles — the path matcher now uses Unicode letters instead of ASCII-only `\w`.
- Feishu OAuth no longer returns `account_not_linked` when the Feishu work email matches an existing Capka user whose email is unverified (`requireLocalEmailVerified: false`). Redeploy the platform image after pulling.
- Sandbox bridge sessions no longer die immediately when `SANDBOX_ENTRYPOINT_HOST` points at a non-executable `sandbox-entrypoint.sh` (`Permission denied` / exit 126). Deploy scripts now `chmod +x` that file.
- zh-CN tool step labels translate past-tense verbs by meaning (e.g. `Ran Python` → `运行了 Python`), not phonetic transliteration (`冉·Python`).
- Feishu OAuth callback origin is taken from the browser Host (auth route rewrites Docker's `0.0.0.0:3000` bind URL) so `redirect_uri` and the `oauth_state` cookie stay on the same entry (IP or tunnel). Register every entry's `/api/auth/oauth2/callback/feishu` in the Feishu app. Redeploy the platform image after pulling.
- Feishu login falls back to `open_id` from the token when userinfo is denied, and the login page surfaces any `?error=` from the OAuth callback (not only `error=feishu`), including an on-page alert for `account_not_linked`.
- HTTP deploys no longer emit `Strict-Transport-Security` unless `PUBLIC_URL` is `https://`.
- Feishu OAuth token exchange now POSTs JSON to Feishu's token API (better-auth's default form-urlencoded body is rejected / fails for Feishu). Redeploy the platform image after pulling this change.
- Feishu (and other OAuth) sign-in stores OAuth state in an encrypted cookie (`storeStateStrategy: "cookie"`) so HTTP IP logins no longer fail with `state_mismatch` / verification-not-found after Feishu redirects back.

### Changed

- Mobile / iOS shell: sidebar sheet, chat header, and message list pad for notch / home-indicator; home greeting top-aligns on small screens to cut the empty band under the composer; iOS shell writes `--capka-sa*` directly so WKWebView layouts work even when `env(safe-area-*)` is 0.
- iOS shell opens tapped files in system Quick Look (PDF / Word / Excel 等) via a `capkaPreview` bridge; PDF iframe glitches no longer show a full-screen connection error.
- Brand wordmark swaps to the white-type `/brand/boss-young-wordmark-on-dark.png` under `html.dark` so dark mode keeps the firm name readable.
- Feishu login button uses the official Lark bird mark instead of a generic chat glyph.
- Dev `allowedDevOrigins` includes `127.0.0.1` and `localhost` so local HMR/auth works over the loopback bind.
- UI font stack includes Noto Sans SC for Chinese body text.
- Remote MCP connectors may use Streamable HTTP or legacy SSE (`/sse` URL paths auto-detect).
- Dev platform memory ceiling raised to 8g (`PLATFORM_MEM_LIMIT`) with larger Node heap to reduce click latency under `next dev`.

## [0.14.0] - 2026-07-24

> **⚠ Breaking — `sandbox_enabled` is now enforced.** It previously saved but did nothing (no code read it). If you ever turned "Sandbox execution" off on Settings → Security, the agent will now really lose file and code access: turn it back on there.

### Added

- Agent mode is now also an instance-wide ceiling on Settings → Security — the same preset + capability switches a project has, one level up. It only ever restricts: a project asking for more is clamped, and it is the only way to change agent behaviour for chats that belong to no project. Exposed to chat as `org.agent_*` controls.

### Fixed

- The `memory_enabled` toggle added in 0.13.1 never worked: the key was missing from the settings API allow-list, so it read as 403 and every save failed. It is now part of the agent ceiling, and a test asserts every key a settings page reads is allow-listed.

### Changed

- The org agent ceiling is stored as one validated `agent_profile` setting. The former `sandbox_enabled` and `memory_enabled` keys are read once to seed it, then ignored, so the same fact is no longer stored in two places.

## [0.13.1] - 2026-07-24

### Fixed

- The `memory_enabled` kill switch now has a toggle on Settings → Security, next to agent autonomy. It shipped in 0.13.0 reachable only from chat via `manage`, unlike every other org setting.

## [0.13.0] - 2026-07-24

### Added

- Projects now have an **Agent mode**: a preset ("Assistant" or "Raw prompt") anyone can pick, plus an admin-only allow-list of capability groups (files and code, connectors, skills, managing settings from chat, long-term memory) and two prompt switches (project instructions replace the built-in persona; pass name/date/language). Turning a group off removes its tools *and* the prompt text describing them, so the model is never told about a tool it doesn't have. A tool-less project never starts a sandbox container or a connector process.
- New org setting `memory_enabled` (default on) — an instance-wide kill switch for long-term memory, settable from chat via `manage`. Off stops all memory reading and writing regardless of a project's own setting; saved memories are kept and become usable again when it's turned back on.

## [0.12.1] - 2026-07-24

### Fixed

- Telegram `/model` now lists models from the admin's shared connections, not only the user's own — on a shared-key instance every non-admin got "No models available yet" while the web picker worked. Models from deactivated connections are no longer offered.
- The library's "Browse marketplace" button now opens the Browse view instead of only adding `?tab=marketplace` to the URL.

## [0.12.0] - 2026-07-24

### Added

- Agent run limits are now operator-tunable: `TASK_TIMEOUT_MINUTES` (default 10), `MAX_AGENT_STEPS` (25), `STREAM_IDLE_SECONDS` (60), and `MAX_STREAM_RECOVERIES` (3). Raise `TASK_TIMEOUT_MINUTES` for turns doing heavy sandbox work — the ceiling covers the whole turn, tool calls included. A non-positive or non-numeric value warns at boot and falls back to the default.

### Changed

- `adm-zip` upgraded to 0.6.0, closing a crafted-ZIP memory-exhaustion advisory (GHSA-xcpc-8h2w-3j85). Skill-zip uploads were already guarded by the app's own size/entry/inflate caps.
- Dependencies refreshed to their current patch/minor releases (`next` 16.2.11, `ai` 6.0.235, `better-auth`, `pg`, `zod`, `drizzle-orm`, `vitest`).
- `shiki`, `katex`, `unist-util-visit`, and `@types/mdast` are now declared dependencies. They were imported but resolved only as transitive dependencies of `streamdown`/`ai`, so an unrelated upstream bump could break the build.

### Fixed

- Admin-only UI no longer flashes in after page load: the role now comes from the session rendered server-side instead of being probed over HTTP, which also drops a full user-listing query on first mount and fixes admin controls disappearing when that probe hit a transient 5xx. A role change now takes effect on next navigation rather than persisting stale for the tab's lifetime.

### Removed

- Unused `@ai-sdk/react` dependency and the unreferenced `scripts/seed-skills.mts` skill-seeding script.

## [0.11.0] - 2026-07-19

### Added

- Usage page is now Analytics: completed-turn / active-member / cost-per-completed-turn KPIs, project and channel breakdowns, member/model/project/channel filters, and a "Needs attention" block (projected budget overrun, members near their tier cap, failure spikes, idle seats).
- Optional instance monthly budget on the billing page (setting `usage_monthly_budget_usd`) — drives the budget share on the Spend KPI and the overrun alert.
- Users page: budget bars against tier caps, last session activity, and a per-member drawer (permission exceptions, personal tier assignment, active sessions with revoke, audit history).
- Account suspension: setting a member to "suspended" revokes their sessions in the same transaction and parks them on a dedicated screen until reactivated.
- Permissions: per-user and per-project exceptions (exception-first list, no matrix), an access checker that explains which policy wins, and per-capability change history.

### Changed

- The "Ask" policy effect is labeled "Block until approved" — it has always blocked; the label now says so until a real approval flow ships.
- Admin audit records dedicated `user.suspend`, `user.reactivate`, `user.sessions_revoke`, and `user.tier_change` actions (previously folded into generic status/billing entries).
- Duplicate capability-policy rows are cleaned up and prevented by new DB constraints (migration applies automatically at boot).

### Fixed

- Azure OpenAI model listing now shows the resource's actual deployments (the only runnable model ids) instead of the base-model catalog, whose version-suffixed ids always failed with HTTP 404 (`DeploymentNotFound`). If deployments can't be listed, the catalog is reduced to plausible deployment names, and a deployment name can always be typed into the picker — even when the list is empty.

## [0.10.11] - 2026-07-19

### Fixed

- Azure OpenAI: the model picker now accepts a typed deployment name. Azure's data plane offers no way to list deployments, and the `/openai/v1/models` suggestions are base models — if your deployment is named differently, type its exact name and pick it.

## [0.10.10] - 2026-07-19

### Fixed

- Azure OpenAI connections now accept the portal's full "Target URI" (e.g. `…/openai/v1/responses?api-version=…`) in the Base URL field — the operation path and query are stripped automatically; previously model listing failed on Foundry (`*.services.ai.azure.com`) endpoints pasted this way.
- The model picker's "could not load models" error is now localized instead of always showing in English.

## [0.10.9] - 2026-07-19

### Added

- Azure OpenAI as a first-class provider (modern v1 API): connect the resource endpoint + API key in Settings → Connections; deployments list into the model picker; Responses API by default with a Chat Completions toggle.
- Google Vertex AI as a provider via express-mode API keys (no service-account JSON); Gemini's full multimodal input and Google Search grounding work as with the direct Gemini provider.
- Amazon Bedrock as a provider via long-term Bedrock API keys; the endpoint field takes an AWS Region or a full runtime URL, and the model list resolves inference-profile ids (`eu.anthropic…`) automatically.
- Groq as a first-party connection preset (previously reachable only as a custom OpenAI-compatible endpoint).

## [0.10.8] - 2026-07-16

### Fixed

- The sandbox controller now drains HTTP traffic on `SIGTERM`/`SIGINT`, flushes pending session activity before closing Postgres, and safely retries activity writes after transient database failures instead of silently dropping them; Compose gives this drain an explicit 15-second stop window.

## [0.10.7] - 2026-07-16

### Security

- Resource-intensive workspace archives, paid ask resumes, extension installs/upgrades, and chat clone/fork operations now have per-user token-bucket limits with shared budgets across equivalent endpoints; full workspace archives also require an active account.

## [0.10.6] - 2026-07-16

### Changed

- CI now runs the database-backed runner, durable queue, realtime, billing, Telegram provisioning, automation, and folder-lease integration suites against PostgreSQL 17 instead of silently skipping the product's core persistence paths.

## [0.10.5] - 2026-07-16

### Fixed

- Terminal task payloads, finalized usage records, and governance audit entries now have configurable, replica-safe database retention with conservative per-table defaults and bounded daily cleanup batches.

## [0.10.4] - 2026-07-16

### Fixed

- Deactivating an account now revokes its existing sessions atomically, and sensitive exports, workspace downloads, memory documents, and live event streams require an active account.

## [0.10.3] - 2026-07-16

### Fixed

- File uploads up to the platform's existing 100 MB limit now pass through the Next.js proxy intact instead of being truncated at its 10 MB default.

## [0.10.2] - 2026-07-16

### Added
- The worker now logs a per-minute `ops` health line (heap, RSS, realtime listeners, NOTIFY queue depth, in-flight/aux tasks) so memory incidents can be diagnosed from the log trail.

### Changed
- Tasks now serialize by workspace rather than only by chat, preventing concurrent chats in the same project from racing over shared files, memory, and connectors.
- Added targeted database indexes for sidebar pagination, unread-message probes, and durable task-queue lookups.

### Fixed
- A realtime (SSE) subscription no longer leaks a dead listener when the Postgres LISTEN connection fails mid-subscribe; reconnect storms during a DB blip used to accumulate them.
- An SSE client that stopped reading (sleeping laptop, wedged proxy) is now disconnected once its event backlog passes ~1 MB instead of buffering events without bound.
- Background LLM calls (chat title, memory maintenance, compaction) now carry a 3-minute deadline, so a hung provider request can't pin the whole conversation context in memory indefinitely.
- Streaming flushes are serialized per turn, so a lagging database no longer stacks unbounded concurrent NOTIFY publishes (the source of the pg `client.query() when the client is already executing` warning).
- Guarded provider requests now retire their request-scoped Undici agents after use instead of retaining connection pools across repeated model and OAuth calls.
- Provider model-list failures no longer expose raw upstream errors that may contain credentials, signed URLs, or internal hostnames.
- Existing chats can no longer be retargeted to another project's workspace through a request-supplied project id, and sends are rejected while their project is being deleted.
- The task worker starts its polling fallback before the optional Postgres LISTEN fast path, so an initial LISTEN failure can no longer leave the process unable to claim work.
- A Telegram delivery failure no longer rewrites a successfully completed task as failed; execution state remains durable and the channel failure is logged separately.
- Workspace listings no longer inspect or hash symlink targets outside the workspace, and cached hashes now invalidate after same-size rewrites even when the old mtime is restored.

## [0.10.1] - 2026-07-13

### Fixed
- Share import no longer fails on large Grok/Claude/ChatGPT conversations whose raw payload exceeds the sandbox output ceiling (~1MB): the sandbox script now ships only the fields the importer reads and applies the import caps before emitting.
- sandbox-controller: a single Docker stream frame larger than the exec output ceiling is now dropped and flagged as truncated instead of bypassing the cap. Applies with the next controller image pull.
- The platform image now sets `NODE_OPTIONS=--max-old-space-size=3072` so the Node heap matches the default 4 GB container limit — previously the process crashed with "JavaScript heap out of memory" at Node's ~2 GB default. Override `NODE_OPTIONS` if you change `PLATFORM_MEM_LIMIT`.

## [0.10.0] - 2026-07-13

### Added
- Each project now has a hub at `/projects/[id]` (Overview, Files, Chats), reachable from a new "Projects" section in the sidebar.
- Chats can be moved between projects (or out of one) from the chat context menu.
- New endpoint `GET /api/sandbox/files/archive` streams a complete workspace archive; "download all" and the delete-project dialog use it.

### Changed
- The sidebar's project dropdown is replaced by a "Projects" section; the chat list is no longer filtered by a selected project.
- Creating a project now asks only for a name and description; instructions, model, and internet access moved to the project's Settings.
- Project settings moved out of the modal into a Settings tab on the project hub (fixes the model picker being clipped inside the dialog); deleting a project also moved there.

### Fixed
- Deleting a project now durably tears down its sandbox, workspace, and attached folders and pauses its automations; a failed teardown is retried by the worker.
- A new chat opening on an off-catalog default model (a stealth/preview id typed as a connection's default) no longer false-flags it as unavailable and blocks the composer; the model is now trusted as long as its connection still exists.
- The "model unavailable" notice no longer tells users to pick from a switcher "above" when the picker sits below it.
- The model picker in forms now opens upward when there's more room above the field, and caps its size to the nearest scroll container so it's never clipped below the fold or above a scroller's edge.

## [0.9.2] - 2026-07-13

### Fixed
- The project create/edit dialog no longer overflows the screen with a long system prompt: it caps at the viewport height and scrolls its fields, and the prompt field now grows further before scrolling internally.
- The project default-model field is now clearable back to "use the global default" (a reset control appears once a model is picked).
- Dialogs no longer flash their dimmed backdrop back on for a frame while closing.
- Project cards on the Projects page now align to equal height, and a project's default model shows its friendly name instead of the raw config-scoped id.
- The project memory picker (Settings → Memory) now shows the project name instead of its id.
- "Manage projects" is now reachable from the sidebar project selector, not only the profile menu.

## [0.9.1] - 2026-07-13

### Changed
- The model is now instructed to analyze delivered attachments from the inline content it already has, instead of re-reading or transcoding them with sandbox tools.
- Attachment delivery decisions are now logged (provider, model, and per-file MIME type) to diagnose whether a given file was sent natively.

### Fixed
- Google/Gemini attachments no longer produce oversized inline requests: audio, video, and PDF files over ~13 MiB now go to the agent's file tools instead of exceeding Gemini's 20 MB request cap.

## [0.9.0] - 2026-07-13

### Added
- Share-link import now also handles Gemini (`share.gemini.google` / `gemini.google.com/share`) and Grok (`grok.com/share`), alongside Claude and ChatGPT; still experimental and gated behind `CAPKA_SHARE_IMPORT`.

### Changed
- Refined English and Ukrainian interface copy for clearer terminology, more natural punctuation, and correct singular and plural forms.

### Fixed
- Attached photos are now normalized in the sandbox before the model sees them: EXIF orientation is baked into the pixels (no provider auto-rotates, so sideways phone photos were the top "the model can't read my image" cause), HEIC/HEIF/TIFF/BMP/AVIF are converted to JPEG (providers accept only JPEG/PNG/GIF/WebP — sending these raw returned a provider error), CMYK is converted to sRGB, and oversized images are downscaled by dimension rather than only by byte size. An image whose format can't be delivered (e.g. SVG) is routed to the agent's file tools instead of being wrongly reported as unreadable. The user's original file stays untouched in the workspace.
- Attached images are placed before the prompt text in the request, matching provider guidance for image understanding.
- Share-import commit is now rate-limited per user (429) and idempotent (a retried or double-clicked import reuses the created chat instead of duplicating it), and rejects oversized request bodies (413).
- Share-import parsers now whitelist message roles strictly (an unknown sender is dropped, not treated as the assistant) and guarantee the imported history starts with a user turn; ChatGPT shares without a `current_node` follow one deterministic branch instead of mixing branches.
- One-shot import sandboxes (`imp-*`) are now evicted before any chat sandbox when a user hits the live-container cap, so a preview render can't stop an active chat's workspace.

## [0.8.1] - 2026-07-13

### Fixed
- The share-import offer card now shows the Claude/ChatGPT brand mark instead of a generic icon.
- Share-link import is more robust: concurrent previews (e.g. two tabs) no longer share and wipe one sandbox session, a slow preview response can't overwrite a newer paste, and previews are rate-limited per user.
- The touch action sheet (long-press menu) now honors `prefers-reduced-motion`, shows a visible keyboard-focus state, and is chosen by pointer type rather than screen width — so a tablet gets the sheet and a narrow desktop window keeps the dropdown.

## [0.8.0] - 2026-07-11

### Added
- Import a public Claude or ChatGPT share link (**experimental**, off by default — set `CAPKA_SHARE_IMPORT=true` to enable): paste a `claude.ai/share/…` or `chatgpt.com/share/…` URL into the composer and Capka offers to import that conversation as a new chat and continue it with any configured model. The page is rendered in the sandbox (never the platform process), so it also needs sandbox egress (`SANDBOX_ALLOW_NETWORK=true`); when egress is off the attempt fails with a clear, non-blocking notice. Text/markdown only; attachments, images, and tool calls are not imported. The model is not run until the user's first reply.

### Changed
- On touch devices, long-pressing a chat row or a message now opens a full-width bottom action sheet (swipe-down / tap-outside to dismiss) instead of a cramped popover; desktop keeps the dropdown menu.

### Fixed
- The code viewer now keeps `Ctrl+A` / `Cmd+A` scoped to the open file instead of selecting text across the whole page.
- The composer no longer shows a phantom vertical scrollbar when empty or on a single line (sub-pixel rounding of the auto-grow height); it now scrolls only once the text actually exceeds the max height.

## [0.7.1] - 2026-07-11

### Changed
- Large attached images are downscaled in the sandbox (long edge 2048px) before being sent to the model, keeping them under provider per-image caps and cutting token cost; the full-resolution original stays in the workspace for `view_file` and metadata questions.

### Fixed
- The agent is no longer told it can "see" an attached photo whose bytes never reached the model (sandbox download failure, over the per-file/aggregate size cap) — it now announces only successfully delivered files as inline-readable and routes the rest to its tools, instead of answering as if it saw an image it didn't.
- Sending a message could, rarely, attach it to the wrong point in the conversation — appearing to edit or fork an earlier message — when a persisted send queue drained before the chat's history finished loading. Message parent linkage is now server-authoritative (anchored to the chat's active branch), and sends wait for history to load.
- A network drop mid-send (or mid-edit/regenerate) now surfaces a localized "no connection" message instead of the browser's raw `Failed to fetch`; failed edits/regenerations no longer fail silently.
- The composer no longer scrolls a long message back to the top on every keystroke, and no longer raises the on-screen keyboard when returning to the app on mobile (autofocus is desktop-only).
- Markdown tables in chat now scroll horizontally on narrow screens instead of crushing their columns to fit the message width.
- Chat list: more spacing between rows, and on touch devices the per-chat actions open via long-press (the always-visible ⋮ is hidden on touch, matching the message action menu).
- File tools (`read_file`, `list_files`, `search_files`, `str_replace`) no longer leak raw shell errors like `sed: can't read …: No such file or directory` into the chat; a missing/inaccessible path now reads as a plain "File not found: …". Actionable failures (e.g. over-quota) still pass through unchanged.
- Sandbox image rendering no longer exhausts the process budget under gVisor and fail with misleading `Cannot allocate memory` errors: the new `SANDBOX_PIDS_LIMIT` setting defaults to 256 (up from the previous fixed limit of 100), while `view_file` bounds ImageMagick's worker threads per render.

## [0.7.0] - 2026-07-10

### Changed
- The model picker no longer lays out and paints every catalog row on each keystroke: off-screen rows use `content-visibility: auto`, so filtering a large provider catalog (e.g. OpenRouter) stays smooth. Behaviour, keyboard navigation, and screen-reader access are unchanged.
- Chat messages, edits, and streaming answer blocks now settle in with a short opacity fade instead of the 500ms blur-rise, so the busiest surface reads calm and does no per-mount GPU blur work; the cinematic entrance stays on rare surfaces (onboarding, auth, empty states).
- Buttons and several chat transitions no longer animate every property (`transition-all` → explicit property lists), removing accidental layout/color animation and keeping motion on `transform`/`opacity`; the button press is a single `scale`, not scale + nudge.
- Tooltips now wait ~400ms before opening (was instant), so passing the cursor over controls no longer flashes stray tooltips; a series of tooltips still opens instantly after the first.
- `SECURITY.md` now documents that the workspace disk quota is enforced at command boundaries (a single command can transiently overshoot) and recommends a filesystem project quota / size-limited volume for multi-tenant or untrusted deployments, and clarifies the two-layer sandbox egress model (the `SANDBOX_ALLOW_NETWORK` kill-switch vs the `sandbox_network` org default).

### Fixed
- Workspace panel: the live file-listing refresh is now single-flighted and abortable, so a slow listing under the during-task safety-net poll can't stack overlapping requests or clobber the list with a stale/out-of-order response, and a late response can't fire after the panel closes.
- Accessibility: the "Copy redirect URI" button (Settings → Authentication) and the "Download all" button (workspace panel) now have accessible names, and copying the redirect URI is announced to screen readers via a polite live region.
- `sandbox-controller` now fails fast at boot on a malformed numeric env var (sizes, timeouts, limits) instead of silently degrading to `NaN` and disabling the guard it fed; the periodic maintenance jobs (idle sweep, GC/flush, over-quota scan) are single-flighted so a slow run under disk pressure can't overlap the next tick; and MCP stdio teardown now rejects in-flight RPCs and clears their timers immediately on session destroy instead of leaving them to the 60s timeout.
- PC folder sync now takes a server-side lease before touching files, so two browser tabs or project members can't run destructive sync operations against the same folder at once (the manifest CAS only guarded the ancestor row, not the files). The lease self-expires, so a client that dies mid-sync never locks the folder.
- `view_file` on HTML no longer fails with a "Trace/breakpoint trap" — the headless-Chromium screenshot now runs with `--headless=new --disable-dev-shm-usage`, so it stops exhausting the sandbox's tiny `/dev/shm` and crashing before the render lands.
- A finished turn whose task reached a terminal (failed/cancelled) status but whose assistant message was left stuck at "running" (a lost message write on the failure path) is now healed by the zombie reconciler, so it no longer revives a stuck spinner on every reload. Completed answers are never rewritten.
- A rare enqueue race no longer hands the client a task id that maps to no task (the stop button targeted nothing); the follow-up now always resolves to a real, cancellable turn.
- Automations: pausing (or deleting) an automation while its run is in flight is no longer undone — the scheduler's error-recovery re-arms a failed run only when the row is untouched, so a manual pause during a fire is respected instead of resurrected.
- Permissions: the "Ask" capability effect was labelled as behaving like "Allow" while the runtime actually blocks it (fail-safe, same as "Deny") until human-in-the-loop approval ships. Corrected the label and dimmed the "Ask" row to match.

### Security
- Content mutations (adding/toggling/deleting skills, enabling/disabling/uninstalling/upgrading plugins, revoking a connector's OAuth tokens) now require a write-capable, active account: a read-only `viewer` and a `pending`/`rejected` account are refused instead of relying on session presence alone. Chat branch switching still requires an active account (blocks pending).
- Unlinking Telegram now also revokes the Telegram login identity (the better-auth `account` mapping), not just the delivery link — so a previously-linked Telegram account can no longer sign in as the user after an unlink or a Telegram A→B switch.

## [0.6.7] - 2026-07-10

### Fixed
- Adding a skill, connector (MCP), or automation through chat works again: the `manage` tool's `args` object was serialized to the model with `additionalProperties: false`, silently forbidding every field (`repo`/`content`/`path`, `name`/`url`, …) so the agent could never fill it. A malformed `add` now also echoes the collection's expected shape instead of a generic error.
- The chat minimap (right-edge jump list of your own messages) is now keyboard-operable — reachable by Tab, opens on Enter, closes on Escape; it was previously mouse-hover only, leaving the jump list unreachable without a pointer.
- Reduced-motion now also collapses animation delays, so delayed and staggered entrances no longer sit invisible before appearing; added a reduced-transparency / high-contrast fallback that drops backdrop blur on overlays and chrome.
- Confirmation and approval cards play their success haptic only after the server accepts the action (error haptic on failure) instead of optimistically on press.

### Security
- Installing a skills repo through chat now pins to the exact commit shown in the approval preview instead of re-resolving the branch tip when the user approves, closing a window where upstream could swap the installed skills between preview and install.

## [0.6.6] - 2026-07-09

### Security
- Outbound fetches to user-supplied URLs (MCP servers, OAuth discovery, marketplace, custom provider base URLs, and provider model listing) now pin the TCP connection to the pre-validated IP, closing the DNS-rebinding window to a private/metadata address. First-party fixed hosts are unaffected.
- Cleared the `js-yaml` moderate advisory pulled in transitively through `gray-matter` (`npm audit`).

### Changed
- The `sandbox-controller` image now installs strictly from its lockfile (`npm ci`) and fails the build on a broken/absent lockfile instead of silently falling back to `npm install`.

### Fixed
- `GET /api/automations` resolves each automation's last-run chat in one batched query instead of one round-trip per automation.
- Workspace panel accessibility: file download buttons now have an accessible name, the closed panel is no longer reachable by keyboard (`inert`), and the usage-limit bar animates only its width.

## [0.6.5] - 2026-07-09

### Added
- More brand icons selectable for a custom OpenAI-compatible connection: model creators Upstage (Solar), Nous Research, Liquid AI; inference endpoints Hugging Face, Cloudflare Workers AI, GitHub Models.

### Changed
- Settings → Connections is now a compact list: each connection is a single row that expands to its settings, and connections can be dragged (or moved with the keyboard) to set their order. That order also drives the chat model picker, and the top enabled connection is the default a new chat opens with (marked "default").
- The xAI provider icon is now the corporate xAI mark instead of the Grok product glyph.

## [0.6.4] - 2026-07-09

### Added
- Brand icons now cover more model creators (Tencent/Hunyuan, ByteDance/Doubao, Baidu/Ernie, Databricks/DBRX, InternLM, Baichuan, Stepfun, LongCat, 01.AI/Yi) and inference providers (Groq, Cerebras, Together, Fireworks, SambaNova, DeepInfra, Novita, Hyperbolic, SiliconFlow, Nebius, Baseten, vLLM, LM Studio, Azure); the extra provider glyphs are selectable when naming a custom OpenAI-compatible connection.

### Fixed
- The activity log now shows human names instead of raw internal ids: a changed setting shows its localized title (e.g. "Interface language", not `user.locale`), and enabling/disabling/removing a connector, skill, or plugin shows the item's name instead of its opaque id.

## [0.6.3] - 2026-07-09

### Changed
- Telegram replies no longer append the model's reasoning as a collapsed
  "💭 Reasoned for Xs" block; the final message is the answer plus the tool-log
  footer only. Live thinking still shows in the streamed draft.

### Fixed
- The sandbox prompt now reflects the session's actual egress: when network is enabled (`SANDBOX_ALLOW_NETWORK=true` + `sandbox_network=bridge` or a project override), the model is told it has internet instead of the hardcoded "no network by default", so it stops refusing to install packages or make requests.

## [0.6.2] - 2026-07-09

### Fixed
- Model-catalog resync now refreshes LiteLLM-sourced rows instead of freezing them at first insert, so a model's later-known input modalities (e.g. audio for Gemini) reach the picker — fixing a spurious "model can't read this file" for audio on LiteLLM/OpenAI-compatible gateways. Resync the catalog (Settings → Connections) after upgrading.

## [0.6.1] - 2026-07-09

### Changed
- The "this model can't read that file" heads-up now appears quietly in the composer while a file is attached, instead of under the reply after sending — so the user can switch models before spending a turn.

### Fixed
- Audio attachments in a container the model transport can't serialize (opus/ogg/m4a/flac) are now transcoded to mp3 in the sandbox before sending, so voice notes reach audio-capable models over LiteLLM/OpenAI-compatible and OpenRouter — previously only wav/mp3 got through and anything else was dropped with a "can't read" notice.

## [0.6.0] - 2026-07-08

### Added
- New `view_file` tool lets the agent SEE a workspace file — image, PDF, office document (docx/pptx/xlsx…), or HTML — rendered to page images, so it can check its own generated documents for broken layout before handing them over. Offered only to vision models; on chat-completions transports (OpenAI Chat, LiteLLM/openai-compatible) the pages are delivered as a follow-up message since those can't carry an image in a tool result.
- The agent can run long sandbox work in the background: `execute_bash` with `background:true` starts a detached job and returns at once (surviving the 300s exec cap and past the reply), and a new `check_job` tool reports its status, exit code, and log tail. The job keeps running as long as the sandbox lives.

### Fixed
- A sandbox command running longer than 150s is no longer cut off by the platform's HTTP client before the controller's own 300s exec cap; the client now waits out the full exec window.

## [0.5.0] - 2026-07-08

### Added
- Connector tools are now loaded on demand once they would tax the model's context window: the agent sees a compact per-connector index plus a `find_tool` search instead of every connector's full schema each turn, cutting token cost and improving tool selection for chats with large MCP connectors (e.g. Firecrawl). Provider-agnostic (works on any model). Tune the trigger with `MCP_DEFER_TOKEN_PCT` (default 10, percent of the effective context window).

### Fixed
- `manage` no longer shows a non-admin the confirm card for attaching a server folder (or an admin-only connector): the authorization pre-flight now runs before any approval card, so a change the user can't apply isn't offered as a dead end.
- The `manage` activity timeline no longer labels a read as "Updated settings" (a false alarm when the agent only looked); a collection read now names its domain (e.g. "Reviewed connectors").

## [0.4.1] - 2026-07-07

### Added
- Optional `ACME_EMAIL` enables Caddy's ZeroSSL fallback issuer on `DOMAIN` deploys (helps when free `sslip.io` hostnames hit the shared Let's Encrypt rate limit). Applied by `up.sh`; on plain `docker compose`/Coolify, write the `email` line to `data/caddy/conf.d/email.caddy` yourself.
- `DOCKER_SOCKET` sets the socket-proxy's host socket path; required for rootless Docker (see SECURITY.md). Defaults to `/var/run/docker.sock`.
- `install.sh` opens ports 80/443 in an active `ufw`/`firewalld` on the turnkey-HTTPS path so the certificate can issue. Set `CAPKA_NO_FIREWALL=1` to manage the firewall yourself.

### Changed
- The sandbox image downloads in the background on controller boot, so the stack reports healthy in seconds instead of after a multi-GB pull; a failed pull retries with backoff, and the first sandbox call returns a clear "still preparing" message if it lands mid-download.
- `install.sh` preflights RAM/disk, requires `docker compose` v2.24+, and adapts to servers already running other sites (stays off busy 80/443/3000, binds loopback, prints how to front Capka); a `DOMAIN=` install where 80/443 are already taken now falls back to reverse-proxy mode instead of a crash-looping Caddy. It no longer reinstalls Docker over a daemon running containers.
- Default install command no longer needs `DOMAIN=` — the installer offers a free `sslip.io` HTTPS address, or type `http` for plain HTTP.
- `up.sh` waits until the app is healthy before printing the address, verifies Caddy obtained the certificate on `DOMAIN` deploys (printing firewall/DNS causes if not), and flags a running-but-unhealthy service instead of calling it "still starting". Re-run it any time to reprint the address.

### Fixed
- First install no longer fails while the sandbox image is still downloading (platform starts independently of the controller).
- Reinstalling or rotating `POSTGRES_PASSWORD` over an existing database volume no longer crash-loops on an auth error: a `db-init` one-shot verifies the role password over TCP and re-syncs it on drift, on all deploy paths (plain `docker compose up`, Coolify, and the scripts).
- A failed certificate or platform boot no longer leaves the host unreachable — Caddy starts independently and keeps a `127.0.0.1` rescue publish.
- `.env` files saved with Windows (CRLF) line endings are normalized on start.

## [0.4.0] - 2026-07-05

### Added
- New Settings → Activity page: a readable, per-day audit trail of admin and configuration changes, showing who did each action, filterable by category (People/Extensions/Settings/Security) with load-more paging. Replaces the raw action-code list that was buried under Permissions.
- Settings → Users now shows pending sign-ups with inline approve/reject (moved off Authentication), 30-day shared-key spend per person, join date, role filter, search, and account removal.

### Changed
- Settings → Usage: token/cache/blended-rate metrics moved into a collapsible "Technical details" block; the by-member list is now searchable and clicking a person filters recent activity to them.

### Fixed
- Audit trail now records skill enable/disable/remove, automation enable/disable/remove, and instance billing changes, and renders every action (including `auth_config.update`, `user.role_change`, master-key access) as a localized sentence naming the actor — several of these previously went unlogged or showed as raw keys.
- Settings nav no longer flickers on every navigation — admin-only items briefly vanished and reappeared because the route crossfade remounts the pane, re-fetching admin/billing status each time; both are now cached across remounts.
- README and `docs/DEVELOPMENT.md` no longer link to a `DEPLOY.md` that isn't in the repo (it was untracked as maintainer-private); a public `docs/DEPLOY.md` deployment guide now backs those links.

## [0.3.0] - 2026-07-05

### Added
- Telegram bot now auto-creates an account on first contact, so a new user can just message the bot instead of signing in on the web first. Governed by the existing registration mode (`open` → active, `approval` → pending, `closed` → refused) and disabled until first-run setup completes; only from private chats. For a publicly-reachable bot, prefer `approval` mode — under `open` anyone who finds the bot gets an account that can spend the shared key.
- Attach folders to a chat's sandbox, off by default via two new org settings in Settings → Security. `host_folder_access` (admin-only) bind-mounts a server folder at `/folders/<name>`; restrict mountable paths with `SANDBOX_MOUNT_ALLOW` (`:`-separated roots). `pc_folder_access` (`off`/`admins`/`everyone`) lets users sync a folder from their own computer (live sync needs Chrome/Edge; other browsers get a one-shot import + zip). See SECURITY.md.

### Fixed
- Desktop: buttons (e.g. the sidebar toggle) no longer intermittently swallow
  clicks while a reply is streaming — streamed markdown updates were triggering
  a full-page view transition ~4×/s, whose overlay also made the whole page
  appear to re-render. Route-navigation crossfades are unaffected.
- The chat scrollbar no longer flickers in and out while a reply streams into
  a fresh (not-yet-scrollable) chat.
- Desktop: dragging the scrollbar while a reply is streaming no longer snaps
  the view back on every delta (scrolling felt locked until the mouse wheel
  was used once).
- Adding a provider no longer fails with "The provider rejected the request
  (HTTP 200)" for OpenAI-compatible gateways that always stream (e.g. omniroute):
  the connection test now probes over the streaming transport that real turns
  use, and times out after 30s instead of hanging.
- Long streaming replies no longer freeze the chat on phones (dead taps,
  stuttering scroll): incoming deltas are now coalesced client-side into ~4
  renders/s, halving main-thread load at the tail of a long answer.
- Message actions (edit/fork/regenerate/version arrows) stay visible but
  disabled while a reply is streaming, instead of vanishing and reappearing.

## [0.2.4] - 2026-07-03

### Fixed
- Regenerating or editing a message after switching the model now runs the newly
  selected model instead of the chat's previously persisted one.
- Destructive confirm buttons (delete skill, delete automation) now show readable
  light text — `text-destructive-foreground` was missing from the theme, so the
  label fell back to dark text on the red background.
- With classic scrollbars (Windows/Linux), the app no longer reserves a dead
  15px strip along the right window edge; the chat column stays centered via a
  symmetric scrollbar gutter, and the workspace files panel opens flush with the
  window edge without clipping its content mid-animation.

### Changed
- Admin top banners (update available, provider out-of-credits/invalid-key, org
  change) share one calm muted style instead of a full-width amber alarm, and all
  three are now dismissible. The out-of-credits/invalid-key banner re-appears if
  the problem recurs after being resolved.
- The "model can't read this attachment" chat notice is now a quiet inline hint,
  reworded to clarify the model can't view the file directly (not that it failed).

## [0.2.3] - 2026-07-03

### Changed
- **Telegram: the turn summary (reasoning `<details>` / tool log) moved below
  the answer** — the streamed reply now finishes by typing out the footer
  instead of visibly repainting the whole message to insert a header.

## [0.2.2] - 2026-07-03

### Fixed
- **Telegram: the streamed draft no longer lingers as a "still thinking" bubble
  for ~30s next to the delivered answer** — the final message is now bridged
  into the draft so Telegram clients adopt it cleanly.
- **Pasting two screenshots no longer collapses them into one attachment** —
  clipboard bitmaps all arrive named `image.png`, so the second overwrote the
  first in the sandbox and the dedup-by-name persistence treated them as one.
  Pasted images now get a unique name; real copied filenames are left untouched.

## [0.2.1] - 2026-07-02

### Fixed
- **One-off automations (`once_at`) now fire at the user's wall-clock time, not
  the worker's UTC clock** — a "22:15" one-off scheduled 22:15 UTC before, so it
  ran hours off. One-off triggers now carry a timezone.
- **An approved `manage` action (e.g. creating an automation) could apply twice
  when the turn hit a provider retry** — the tool now executes at most once per
  call, so retries no longer duplicate the change.
- **The scheduler no longer silently drops an occurrence when firing fails** — a
  failed fire restores the due time to retry and counts toward the 3-failure
  auto-pause instead of leaving a one-off disabled with no run.
- **Settings → Automations shows the scheduler's real next-run time and flags an
  overdue run** (background worker not running) instead of a recomputed date that
  hid a stuck worker.
- **`/api/automations/:id` (enable/disable) rejects a non-boolean body** instead
  of coercing e.g. the string `"false"` to `true`.
- **A created automation now runs on the model of the chat that created it**
  (was always the account default), and due automations fire immediately on
  worker start instead of waiting up to 30s.
- **A Coolify redeploy on an unchanged image tag (`:latest` or a pinned
  `CAPKA_VERSION`) no longer keeps running the previously cached image bits**
  — `platform` and `sandbox-controller` now set `pull_policy: always`, so
  `docker compose up -d` re-checks the registry every deploy instead of only
  pulling when the tag is missing locally.
- **Settings → General "About" and the MCP client handshake now report the
  actual running version** (`CAPKA_VERSION`) instead of a frozen `package.json`
  number that never moved past `0.1.0`.

## [0.2.0] - 2026-07-02

> **⚠ Breaking — Coolify `docker_compose_location` must be `/docker-compose.yml`.**
> `docker-compose.coolify.yml`/`.prod.yml` were removed; update the Coolify
> setting (Configuration → Build) and redeploy.

### Added
- **Automations**: schedule recurring agent runs from chat (e.g. «щопонеділка о
  9 готуй зведення»); each run is a normal chat, delivered to Telegram when
  linked; 3 consecutive failures auto-pause. Admin settings:
  `automations_enabled`, `automations_per_user` (10), `automations_min_interval_minutes`
  (60). New `/settings/automations` page.
- **MCP elicitation**: a connector can ask a structured question mid-tool-call;
  ~3 min timeout, does not survive a worker restart (unlike `ask`).
- **`ask` tool**: the agent can pause a turn to ask you a question; durable
  across worker restarts; web card or Telegram field-by-field; always
  skippable.
- **GitHub token for marketplace installs** now configurable from Settings →
  Marketplace (write-only, encrypted) — raises the anonymous API rate limit
  (60/hr) to 5000/hr and reaches private repos.
- **Agent can install/edit skills straight from workspace files or a `.zip`**
  (`manage skill add {path}` / `edit {name}`) instead of pasting a whole
  SKILL.md into the tool call.
- **`agent_autonomy` setting** (admin): `supervised` (default, confirm cards)
  or `autonomous` (personal changes apply directly; org-wide changes still
  confirm).
- **Conversational settings (`manage` tool)**: users change personal prefs and
  admins change platform-wide settings from chat. Org-wide changes are
  two-phase (staged server-side, applied only by your own click), audit-logged,
  and undoable.
- **MCP connectors and skills manageable from chat** via the same `manage`
  collection (list/add/remove/enable/disable/debug/connect); OAuth connectors
  hand back a Connect link.
- **`manage` UX polish**: first-run concierge nudge, chip pickers for
  enum/boolean settings, popup OAuth, a reachability probe before confirming a
  new connector, instant locale switching, and a banner when another admin
  changes something.
- **`PLATFORM_BIND` env var** (default `0.0.0.0`) to bind the platform port to
  one interface, e.g. `127.0.0.1` behind a reverse proxy.
- **CI** (`.github/workflows/ci.yml`): typecheck, lint, tests, build on every
  push/PR.

### Changed
- **The `manage` tool description shed its per-collection reference (~40%
  smaller), cutting its per-turn token cost.** Connector/skill/automation add
  shapes and workflows now come back as a `usage` field from `get` on the
  collection (and are echoed on an invalid `add`), instead of riding along in
  every request. Malformed `manage` calls now name the missing fields, and an
  `add` whose args can't validate is rejected immediately instead of first
  asking you to approve it.
- **Claude models now cache the conversation history, not just the system
  prompt** — long Claude chats bill at roughly cache-read pricing instead of
  full price. Claude behind a LiteLLM proxy still needs
  `cache_control_injection_points` configured on the proxy.
- Chat-title generation no longer burns reasoning tokens on thinking models.
- **`manage` confirmations use native tool approval** — the turn resumes after
  you Approve/Reject instead of dead-ending.
- **`manage` chat replies show a card only when you still need to act**;
  routine results (applied settings, healthy diagnostics) drop to a one-line
  activity-rail entry instead of stacking as cards.
- **`manage` text is now localized via i18n** (English source of truth,
  `messages/<locale>.json`); a missing translation falls back to English
  instead of breaking.
- **One canonical `docker-compose.yml`** replaces the three near-duplicate
  stack files; building from source is now the opt-in
  `docker-compose.build.yml` overlay (`CAPKA_BUILD=1`).

### Fixed
- **Adding your own provider key no longer hides the org's shared
  connections** — the model picker now shows the union of your own and shared
  connections instead of only one or the other.
- **A free or newly-released model no longer fails with "isn't priced in the
  catalog"** on the shared key — falls back to OpenRouter's live price book,
  or is allowed through with a zero hold if still unpriced.
- **GitHub rate-limit/404/401 errors now read as plain-language messages**
  (e.g. "rate limit resets in Xm, ask your admin for a token") instead of
  "access denied".
- **An OAuth MCP connector now works immediately after sign-in**, instead of
  being silently ignored for up to 10 minutes.
- **The agent no longer refuses config changes it's actually allowed to
  make** — permission is now decided by the action's result, not by the model
  pre-emptively reading role labels.
- **Coolify deploys regain sandbox tuning and redeploy drain** lost when
  `docker-compose.prod.yml` was introduced (1 GB sandbox memory, 2
  sessions/user, 7-day GC grace, 35s `stop_grace_period`).
- **An automation run that stops to ask a question no longer piles up
  duplicate runs** on the next scheduled occurrence.
- **The skill-install approval card now lists the actual skills** a workspace
  path would install, instead of falling back to "couldn't read that path".

### Security
- **Platform-wide (org-scope) settings always require confirmation**, even in
  `agent_autonomy: autonomous` mode.
- **Enabling a connector, skill, or automation from chat now requires
  approval**, same as adding one (`disable` stays direct).
- **The automations API now rejects pending/rejected accounts**, not just
  unauthenticated ones.
- **A workspace skill `.zip` install is now size-capped while streaming**, not
  only at upload.
- **A double-tapped approval/answer, or racing web + Telegram responses, can
  no longer fire a turn twice.**
- **A late Telegram reply to a timed-out connector question** is no longer
  swallowed or falsely reported as answered.

### Removed
- **Fly.io and Railway deploy manifests** (`deploy/`) — platform-only deploys
  aren't supported; self-host via the installer or Coolify (guide moved to
  `DEPLOY.md`).

## [0.1.6] - 2026-07-01

### Fixed
- **Cerebras gpt-oss (and similar reasoning models) no longer hang mid-turn**
  — prior reasoning is now folded into the assistant message's `content`
  instead of dropped, which was trading the earlier 400 for a silent stall.

## [0.1.5] - 2026-07-01

### Fixed
- **Reasoning models behind an OpenAI-compatible endpoint now survive
  tool-calling turns, not just plain chat** — the `reasoning_content` strip
  now also applies per tool-loop step, not only to the initial history.

## [0.1.4] - 2026-07-01

### Changed
- **Oversized MCP results (text or media) no longer flood the context window
  or the database** — parked to workspace storage with a pointer the model can
  `read_file`/grep. Tune with `MAX_MCP_MEDIA_BYTES` / `MAX_TOOL_OUTPUT_CHARS`.
- MCP tool descriptions capped at `MAX_MCP_TOOL_DESC_CHARS` (default 1024).
- Update-available banner is now dismissible per version; release notes render
  as Markdown.

### Fixed
- **Reasoning models behind an OpenAI-compatible endpoint (e.g. Cerebras via
  LiteLLM) no longer die on the second turn** — echoed `reasoning_content` is
  stripped after a rejection; DeepSeek (which requires the field) is untouched.
- The context-window meter and auto-compaction no longer overstate usage on
  multi-step turns — now keyed off the last step's prompt size, not the
  cumulative sum.

## [0.1.3] - 2026-07-01

### Fixed
- **Completes the gVisor egress fix** (0.1.2 was partial) — iptables lock
  moved to writable `/tmp`, stale sandbox container names are force-removed on
  conflict. No config change needed.

## [0.1.2] - 2026-07-01

### Fixed
- **Sandbox egress under gVisor no longer kills every container**
  (iptables-legacy + `NET_RAW` capability + `--net-raw=true` runtime flag).
  **Existing gVisor hosts must re-run `install-gvisor.sh` and reload Docker.**
- Controller now recovers from a stopped (not just removed) sandbox container.

## [0.1.1] - 2026-07-01

Partial gVisor egress fix — **superseded by 0.1.2**, which adds the missing
`NET_RAW` capability. Use 0.1.2.

## [0.1.0] - 2026-06-30

> **⚠ Breaking — sandbox network egress is now fail-closed.** Set
> `SANDBOX_ALLOW_NETWORK=true` if sandboxes need outbound network access.

### Added
- AGPL-3.0 license; `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, CLA.
- One-variable automatic HTTPS via the Caddy TLS overlay (`DOMAIN=…`).
- Railway and Coolify deploy templates.
- Postgres backup/restore scripts and an optional scheduled-backup overlay.
- `CAPKA_VERSION` image pinning and an upgrade runbook (`docs/UPGRADE.md`).
- `ee/` boundary reserved for the commercial edition.
- Marketplace installs are pinned to a concrete git commit, disabled by
  default pending admin review, and upgrades show a file-level diff before the
  pin moves.
- Boot-time configuration audit surfaces misconfigured/missing env as one
  block at startup.
- A Content-Security-Policy (the inline-safe slice).

### Changed
- The host-agnostic `docker-compose.yml` is now canonical; the Coolify variant
  moved to `docker-compose.coolify.yml`.
- `docker compose pull` now fetches the sandbox image too.
- Sandbox image base and duckdb/yq versions are pinned (were `latest`).

### Security
- Sandbox egress fail-closed behind `SANDBOX_ALLOW_NETWORK` (see breaking note
  above); the egress firewall refuses to start if its rules can't be verified.
- Governance `ask` now fails safe (deny) instead of allowing.
- SSRF guard broadened (0.0.0.0/multicast/IPv6) and strips
  `Authorization`/`Cookie` on cross-host redirects.
- Zip uploads get a decompression-bomb guard.
- Foreign keys + money-column precision added; audit log extended.
- Billing holds always release; first-run setup can no longer self-promote
  admin; pending accounts are rejected centrally.
- Pinned `postcss` ≥8.5.10 and `dompurify` ≥3.4.11 (prior advisories).
- Account status and marketplace upgrade consent are fail-closed; one billing
  hold per task; marketplace fetches/catalog size are capped.
- **Production master key is fail-closed**: with `NODE_ENV=production` and no
  `CAPKA_MASTER_KEY`, the app refuses to start. Set `CAPKA_MASTER_KEY` or
  `ALLOW_DB_MASTER_KEY=true` to keep the insecure fallback.
- HSTS is now sent by the platform too, not only the Caddy TLS profile.
