import SwiftUI

/// The macOS client. It shares this repo's whole core — models, API client,
/// session, chat view model, settings — with the iOS app, and supplies its own
/// view layer.
///
/// Not a port of the iOS screens: a Mac window is wide and persistent, so the
/// chat list belongs in a real sidebar rather than a drawer you swipe open, and
/// settings belong in a Settings scene behind ⌘, rather than a modal sheet.
/// Reusing the iOS layout would have meant shipping gesture affordances no Mac
/// user looks for.
@main
struct BossYoungMacApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var session = SessionStore()
  @State private var appLock = AppLock()
  @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue

  private var theme: ThemePreference {
    ThemePreference(rawValue: themeRaw) ?? .system
  }

  var body: some Scene {
    WindowGroup {
      ZStack {
        MacRootView()
          .environment(session)
          .environment(appLock)
        if appLock.isLocked {
          AppLockView(lock: appLock)
            .transition(.opacity)
            .zIndex(10)
        }
      }
      .animation(Motion.easeOut(0.2), value: appLock.isLocked)
      .capkaMacControlChrome()
      .capkaPreferredColorScheme(theme)
      .frame(minWidth: 820, minHeight: 560)
      .task {
        #if DEBUG
          if let directory = MacSnapshot.requestedDirectory {
            MacSnapshot.run(into: directory, session: session)
            return
          }
        #endif
        appLock.lockIfEnabled()
        await session.bootstrap()
      }
      // A Mac "backgrounds" by losing key window rather than being suspended.
      // Treating that as the start of the grace period is what makes the lock
      // mean anything on a machine you walk away from.
      .onChange(of: scenePhase) { _, phase in
        switch phase {
        case .active: appLock.noteForegrounded()
        case .inactive, .background: appLock.noteBackgrounded()
        @unknown default: break
        }
      }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("新聊天") {
          NotificationCenter.default.post(name: MacRootView.newChatNotification, object: nil)
        }
        .keyboardShortcut("n")
      }
      // The web's ⌘K opens a command palette over the page; here the sidebar's
      // search field is permanently on screen, so the shortcut goes straight to
      // it. ⌘F, because on a Mac that is what "find in this list" is called.
      CommandGroup(after: .toolbar) {
        Button("搜索聊天记录") {
          NotificationCenter.default.post(name: SidebarView.focusSearchNotification, object: nil)
        }
        .keyboardShortcut("f")
      }
    }

    Settings {
      MacSettingsScene()
        .environment(session)
        .environment(appLock)
        .capkaMacControlChrome()
        .capkaPreferredColorScheme(theme)
    }
  }
}

extension View {
  /// Strips AppKit's default control chrome from the whole window.
  ///
  /// Every button and field in this app draws its own surface — a pill, a card,
  /// a tinted capsule — because that is what the web does. On iOS a bare
  /// `Button`/`TextField` adds nothing on top of that, so the shared views
  /// mostly don't name a style. On macOS the defaults are a bordered push
  /// button and a bezelled text field, which show up as a grey slab behind each
  /// row and a white box inside each field.
  ///
  /// Both styles come from the environment, so setting them once at the window
  /// root fixes every shared screen at once; anything that genuinely wants a
  /// system control still overrides it locally.
  func capkaMacControlChrome() -> some View {
    buttonStyle(.plain).textFieldStyle(.plain)
  }
}

/// ⌘, opens the same settings the iOS app shows in a sheet — the list and every
/// detail page are shared; only the container differs.
struct MacSettingsScene: View {
  var body: some View {
    NavigationStack {
      SettingsHomeView()
    }
    .frame(width: 640, height: 620)
  }
}
