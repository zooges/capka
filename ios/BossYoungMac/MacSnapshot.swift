import AppKit
import SwiftUI

/// Renders the main screens to PNGs and quits.
///
/// A Mac app can't be inspected from a terminal — screenshots need Screen
/// Recording permission and the accessibility APIs need another. `ImageRenderer`
/// needs neither: it lays the views out offscreen and hands back a bitmap, which
/// is enough to check composition, spacing and dark mode without a human at the
/// keyboard. Debug-only, and only when `CAPKA_MAC_SNAPSHOT` names a directory.
#if DEBUG
  @MainActor
  enum MacSnapshot {
    /// Always inside the sandbox container's tmp — the app has no write access
    /// anywhere else, so naming an arbitrary path would silently produce nothing.
    static var requestedDirectory: URL? {
      guard ProcessInfo.processInfo.environment["CAPKA_MAC_SNAPSHOT"] == "1" else { return nil }
      return FileManager.default.temporaryDirectory.appendingPathComponent("capka-snapshots")
    }

    static func run(into directory: URL, session: SessionStore) {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let lock = AppLock()
      // A split view's sidebar column is drawn into its own surface, which
      // `cacheDisplay` doesn't reach — so the sidebar gets its own shot, on its
      // own, where it does capture.
      let list = ChatListViewModel()
      let chat = ChatViewModel()
      CapkaFixtures.seed(session: session)
      CapkaFixtures.seed(chat: chat, list: list)

      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        write(
          SidebarView(
            list: list,
            currentChatId: list.chats.first?.id,
            onNewChat: {}, onOpenChat: { _ in }, onOpenProjects: {},
            onOpenArchived: {}, onOpenSettings: {}, onClose: {},
            onRename: { _ in }, onMove: { _ in },
            onShare: { _ in }, onExport: { _ in }
          )
          .environment(session)
          .capkaMacControlChrome(),
          size: CGSize(width: 268, height: 800),
          appearance: appearance,
          to: directory.appendingPathComponent("sidebar-\(name).png")
        )
        write(
          LoginView().environment(session).capkaMacControlChrome(),
          size: CGSize(width: 900, height: 760),
          appearance: appearance,
          to: directory.appendingPathComponent("login-\(name).png")
        )
        write(
          MacRootView().environment(session).environment(lock).capkaMacControlChrome(),
          size: CGSize(width: 1180, height: 800),
          appearance: appearance,
          to: directory.appendingPathComponent("root-\(name).png")
        )
        write(
          NavigationStack { SettingsHomeView() }
            .environment(session).environment(lock).capkaMacControlChrome(),
          size: CGSize(width: 660, height: 640),
          appearance: appearance,
          to: directory.appendingPathComponent("settings-\(name).png")
        )
      }

      NSApplication.shared.terminate(nil)
    }

    /// Hosts the view in a real (offscreen) window and lets the run loop turn
    /// before capturing.
    ///
    /// `ImageRenderer` alone renders one frame with no lifecycle, so every
    /// entrance animation — which starts at opacity 0 and lands in `onAppear` —
    /// comes out blank. A hosting view runs the lifecycle, so what lands in the
    /// PNG is what a person would see a beat after the window opened.
    private static func write(
      _ view: some View,
      size: CGSize,
      appearance: NSAppearance.Name,
      to url: URL
    ) {
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.appearance = NSAppearance(named: appearance)
      window.isReleasedWhenClosed = false
      // SwiftUI only runs `task`/`onAppear` for a view in a window the system
      // considers on screen — a window parked at -10000 gets laid out but never
      // gets a lifecycle, so nothing loads and every screen captures empty.
      // Hence: on screen, but transparent.
      window.alphaValue = 0.01
      window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
      window.setFrameOrigin(.zero)
      let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
      host.frame = NSRect(origin: .zero, size: size)
      window.contentView = host
      window.orderFrontRegardless()

      // Entrances run ~0.5s plus their staggered delays; view-model `task`s that
      // only touch fixtures settle well inside this.
      RunLoop.current.run(until: Date().addingTimeInterval(2.0))
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
      host.cacheDisplay(in: host.bounds, to: rep)
      if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
      }
      window.orderOut(nil)
    }
  }
#endif
