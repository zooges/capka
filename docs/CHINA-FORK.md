# 中国律所团队版

## 产品定位

本分支将 Capka 用作律所助手和团队文件 Agent：由管理员统一配置模型与访问策略，团队成员在隔离沙箱中处理合同、尽调资料、扫描件和法律文书。生成内容应由负责律师结合案件事实和适用法律复核，不构成自动法律意见。

## 启动

```bash
npm run docker:dev
```

首次启动后打开 <http://127.0.0.1:3000/setup>，完成管理员账户和基础配置。

## 中文界面

提供 `zh-CN` 后，浏览器可通过 `Accept-Language` 自动选择中文；用户也可以在设置中手动切换语言。首次部署请确认中文消息文件已随镜像发布。

## 品牌

默认品牌为 **邦信阳**（上海邦信阳律师事务所），侧栏 / 登录页使用官方 B 标。可在环境中覆盖：

```dotenv
NEXT_PUBLIC_PRODUCT_NAME=邦信阳
NEXT_PUBLIC_PRODUCT_TAGLINE=上海邦信阳律师事务所 · 团队文件 Agent
```

Logo 资源位于 `public/brand/`（`boss-young-mark.png` 方标、`boss-young-wordmark.png` 横版字标）。`NEXT_PUBLIC_*` 会进入浏览器构建产物，不能存放密钥。

## 飞书登录

1. 在飞书开放平台创建企业自建应用，并在应用的网页授权/登录能力中启用 OAuth 登录。
2. 在应用中登记回调地址：`https://你的域名/api/auth/oauth2/callback/feishu`。本地调试时，使用实际可被飞书访问的 HTTPS 地址；`127.0.0.1` 不能作为公网回调地址。
3. 取得应用的 App ID 和 App Secret，并按飞书要求配置用户信息授权范围。
4. 以 Capka 管理员身份进入管理员后台的 **Authentication**，填写 Feishu App ID 与 App Secret，并打开飞书登录开关。
5. 保存后，在登录页完成一次飞书登录测试。注册是否允许新成员仍受实例的注册策略控制，应按律所的入职和离职流程设置。

## 飞书工作台

在同一企业自建应用中添加「网页应用」能力，将桌面端 / 移动端主页设为 Capka 的 HTTPS 入口（如 `https://你的域名/chat`），并配置 H5 可信域名与可用范围后发布。详见飞书文档「将网页应用嵌入工作台」。

## iOS 客户端

仓库 `ios/` 为 **移动端 WKWebView 套壳**（与网页同一套飞书/业务，外壳做手机优化：下拉刷新、安全区、断网重试等）。

```bash
open ios/BossYoung.xcodeproj
```

地址固定在 `AppConfig.swift`。说明见 [`ios/README.md`](../ios/README.md)。

## 中文联网检索

本分支默认面向中国用户。在沙箱开启出网（`SANDBOX_ALLOW_NETWORK` + 组织/会话 Internet access）时，设置：

```dotenv
CAPKA_REGION=cn
```

会在沙箱系统提示中注入 **Network & web access (China)**：Capka **没有内置网页搜索**。默认（`CAPKA_TAVILY_STEER` 未设或为 `1`）时 **Tavily 只负责一般网页/新闻/公开互联网检索**（`mcp__tavily__tavily_search`；`MCP_ALWAYS_LOAD` 在 `CAPKA_REGION=cn` 下默认预加载并预连，无需 `find_tool` / 无需 `pip install tavily`）。法律/案例/元典、企查查/工商、微信文章等应走对应 MCP（deferred 时先 `find_tool`），**不要**一律用 Tavily。沙箱可访问国内外站点（可用 `SANDBOX_*_PROXY`）；允许 `curl`/`wget` 打开具体文章 URL，以及用 Bing / Baidu / Google 结果页。未设置 `CAPKA_REGION` 时行为与上游一致。

**内网可出境外（如 `10.0.40.100`）**：设 `CAPKA_TAVILY_STEER=0`（或 `CAPKA_WEB_SEARCH=open`）关闭 Tavily-first 提示，改为开放网页（Google/Bing/Baidu/YouTube + `curl` 优先；Tavily 若已配置则可选、非强制）。仍可保留 `CAPKA_REGION=cn`（品牌/域名 MCP 路由）。公网中国区 CVM 可不设该变量以保持 Tavily 引导。

也可写 `CAPKA_CHINA=1`（等价）。`scripts/deploy-remote.sh` 会写入 `CAPKA_REGION=cn`。用 `MCP_ALWAYS_LOAD=none` 可关掉中国区的 Tavily 预加载；或设 `MCP_ALWAYS_LOAD=tavily,other` 追加热工具。

## 法律 skills 种子

仓库在 `skills-pack/legal/` 提供合同审核、尽职调查、OCR 字段抽取和文书起草四项系统级技能。启动数据库后运行：

```bash
npm run skills:seed-legal
```

脚本读取 `DATABASE_URL`；未设置时使用本地 `docker:dev` 数据库地址。重复运行会更新同名的 `system` / `manual` 技能并保持启用，不会新增重复记录。

沙盒镜像（`Dockerfile.sandbox`）预装 Tesseract `eng` + 简体/繁体中文（`chi_sim` / `chi_tra`）。OCR 示例：`tesseract page.png stdout -l chi_sim+eng`。改镜像后本地重建（`npm run sandbox:build`），**不要** `docker compose pull`。默认沙盒内存 `SANDBOX_MEMORY_MB=2048`。

## MCP 连接器（中国法律 / 微信）

Capka 原生支持远程 MCP（Streamable HTTP + 遗留 SSE）与沙箱内 stdio。本分支补齐了 SSE 持久化与探测，并提供法律侧车与一键注册。

### 1. 启动 MCP sidecar

默认从仓库旁的 `../chineselaw-mcp`、`../wechat-article-mcp` 构建。在 `.env` 中设置 `CHINESELAW_API_KEY`（元典开放 API），可选 `CHINESELAW_MCP_AUTH_TOKEN` / `WECHAT_MCP_AUTH_TOKEN`。

**微信 MCP（内网 P0）**：同机部署时出站走宿主机 mihomo（默认 `HTTP(S)_PROXY=http://172.17.0.1:7890`），带搜索/正文缓存、出站限流与反扒熔断；端口仅绑 `127.0.0.1:8809`。公网 `weixin.zooges7000.top` 可继续保留为独立实例，Capka 主用内网 sidecar。

```bash
# 与 docker:dev 一并拉起（或单独 up 两个 mcp 服务）
docker compose -f docker-compose.yml -f docker-compose.build.yml \
  -f docker-compose.dev.yml -f docker-compose.mcp.yml up -d --build
```

也可沿用已有的 `mcp-services` 部署，仅把连接器 URL 指到宿主机端口（见下方环境变量）。

### 2. 注册系统连接器

```bash
npm run mcp:seed-china
```

默认写入：

| 名称 | URL（compose DNS / 官方远程） |
|------|-------------------|
| `chineselaw` | `http://chineselaw-mcp:8317/mcp` |
| `wechat-article` | `http://wechat-article-mcp:8809/mcp` |
| `tavily` | `https://mcp.tavily.com/mcp/`（官方 Streamable HTTP；需 `TAVILY_API_KEY`） |

覆盖：`MCP_CHINESELAW_URL`、`MCP_WECHAT_URL`、`MCP_TAVILY_URL`。仅注册某一个时用 `MCP_SEED_ONLY=tavily`（逗号分隔）。若 MCP 跑在宿主机而非 sidecar，例如：

```bash
MCP_CHINESELAW_URL=http://host.docker.internal:8317/mcp \
MCP_WECHAT_URL=http://host.docker.internal:8809/mcp \
npm run mcp:seed-china
```

同机 Capka 指向内网微信 MCP（推荐）：

```bash
MCP_WECHAT_URL=http://wechat-article-mcp:8809/mcp \
WECHAT_MCP_AUTH_TOKEN=... \
MCP_SEED_ONLY=wechat-article \
npm run mcp:seed-china
```

微信 sidecar 可选环境变量：`WECHAT_HTTPS_PROXY`（默认 docker0→mihomo `:7890`）、`WECHAT_NO_PROXY`（仅内网；搜狗/微信应走 mihomo `WECHAT` 选择组做多出口）、`MIHOMO_API_BASE` / `MIHOMO_API_SECRET` / `MIHOMO_WECHAT_GROUP` / `MIHOMO_WECHAT_ALLOWLIST`（遇反爬或 `WECHAT_ROTATE_EVERY` 时切节点）、`WECHAT_SEARCH_MIN_INTERVAL_MS`、`WECHAT_CIRCUIT_COOLDOWN_MS`。健康检查：`curl -s http://127.0.0.1:8809/health`（含 `proxyConfigured` / `circuitOpen` / `mihomo`）。
有 Bearer 鉴权时，把对应 `*_MCP_AUTH_TOKEN` / `TAVILY_API_KEY` 一并传入种子脚本（会用 `CAPKA_MASTER_KEY` 或库内 `auth_secret` 加密写入）。缺少 `TAVILY_API_KEY` 时仍会写入 `tavily` 行但保持 **disabled**，便于之后在设置 → Connectors 粘贴 Token，或补上密钥后重跑：

```bash
TAVILY_API_KEY=tvly-... MCP_SEED_ONLY=tavily npm run mcp:seed-china
```

### 3. 使用与自检

- 设置 → Customize → **Connectors**（`/settings/skills?tab=connectors`）查看共享连接器与连通性。
- URL 以 `/sse` 结尾时自动按 SSE 传输保存；也可在 API 中显式传 `transport: "sse" | "http"`。
- 在对话中让助手调用法律检索 / 微信文章工具前，确认连接器已启用且健康检查为 Connected。

## 生产机防覆盖（重要）

中国版本地构建会打成与官方相同的标签 `ghcr.io/lyosu/capka-platform:latest`。若 compose 里仍是 `pull_policy: always`，任意一次未叠加 `docker-compose.build.yml` 的 `docker compose up` 都会从 GHCR **覆盖**本地镜像，登录页退回上游 Capka（中文案/邦信阳品牌从运行镜像消失）。**数据库与 `.env` 通常仍在。**

CVM / 生产必须：

1. `platform` 与 `sandbox-controller` 使用 `pull_policy: never`（不要改回 `always`）
2. 更新只用本地构建，例如：
   `docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build --pull never platform`
   或保证 `.env` 中 `CAPKA_BUILD=1` 后走 `./scripts/up.sh`
3. **禁止** `./scripts/update.sh`、`docker compose pull`、1Panel/Watchtower 对本栈自动更新

## 生产加固

- 对不受信任或多租户工作负载设置 `SANDBOX_RUNTIME=runsc`，并按项目文档安装和验证 gVisor。
- 在宿主机使用 rootless Docker；设置 `DOCKER_SOCKET` 指向 rootless daemon 的 socket。
- 依据团队规模配置每用户并发会话、沙箱内存、进程数和工作区保留期配额。
- 默认禁止沙箱出网：设置 `SANDBOX_ALLOW_NETWORK=false`；仅在业务确有需要并完成网络边界评估后开放。
- 限制主机目录挂载范围，妥善保管数据库、对象存储、模型供应商和 OAuth 密钥。

## AGPL 提醒

本项目采用 AGPL-3.0-only。对外提供网络服务且修改了本项目代码时，通常需要向该服务的用户提供相应修改后的源代码，并保留许可证与版权声明。上线前请由法律和开源合规负责人确认具体义务。
