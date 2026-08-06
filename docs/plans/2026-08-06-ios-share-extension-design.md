# iOS Share Extension — share files into chat

Date: 2026-08-06

## Decisions

- Both apps: BossYoung (`bossyoung`) and BossYoung2 (`bossyoung2`)
- After share: pick existing chat or create new
- Files land as composer pending attachments (not auto-sent)
- Extension does not call Capka APIs; host app uploads via existing `attach(fileURL:)`

## Flow

WeChat / Files / Photos → Share sheet → extension copies bytes into App Group
`inbox/<uuid>/` + `meta.json` → opens `bossyoung(2)://share-inbox` → host consumes
inbox → `openChat` / `startNewChat` → `attach` each file → chips in composer.

## App Groups

| App | Group | Extension bundle id |
|---|---|---|
| 邦信阳 | `group.com.bossyoung.capka` | `com.bossyoung.capka.share` |
| 邦信阳2 | `group.com.bossyoung.capka2` | `com.bossyoung.capka2.share` |

Enable the same App Groups on the Apple Developer App ID for both app and extension before device install.

## Code map

- `ios/ShareSupport/` — shared inbox + chat index + Share UI
- `ios/BossYoungShare/`, `ios/BossYoung2Share/` — Info.plist + entitlements
- Host: `OutboxStore.saveChatList` writes `chat-index.json`; `RootView.consumeShareInbox`
