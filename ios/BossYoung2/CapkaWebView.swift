import ObjectiveC
import SwiftUI
import WebKit

/// Mobile Capka shell: Feishu via LarkSSO (jump to Feishu app → native callback),
/// edge-swipe sidebar/home, haptics on reply, bossyoung2:// bridge for Safari-only.
struct CapkaWebView: UIViewRepresentable {
  @Binding var canGoBack: Bool
  @Binding var isLoading: Bool
  @Binding var loadError: String?
  var reloadToken: UUID

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> SafeAreaWebView {
    let userScript = WKUserScript(
      source: Self.mobileBootstrapJS,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    )
    let content = WKUserContentController()
    content.addUserScript(userScript)
    content.add(context.coordinator, name: "capkaPreview")
    content.add(context.coordinator, name: "capkaNative")

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.userContentController = content
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    if #available(iOS 15.0, *) {
      config.preferences.isElementFullscreenEnabled = true
    }

    let webView = SafeAreaWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    // App-shell: no Safari-like back/forward swipe or link peek; keep page scroll + our edge gestures.
    webView.allowsBackForwardNavigationGestures = false
    webView.allowsLinkPreview = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    if #available(iOS 13.0, *) {
      webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
    }
    // Keyboard must not inset/offset WK’s scroll view — Capka owns lift via --kb.
    webView.scrollView.contentInset = .zero
    webView.scrollView.scrollIndicatorInsets = .zero
    webView.scrollView.alwaysBounceVertical = true
    webView.scrollView.alwaysBounceHorizontal = false
    webView.scrollView.minimumZoomScale = 1
    webView.scrollView.maximumZoomScale = 1
    webView.scrollView.bouncesZoom = false
    webView.scrollView.pinchGestureRecognizer?.isEnabled = false
    webView.isOpaque = false
    webView.backgroundColor = UIColor(
      red: AppConfig.brandCream.r,
      green: AppConfig.brandCream.g,
      blue: AppConfig.brandCream.b,
      alpha: 1
    )
    webView.scrollView.backgroundColor = webView.backgroundColor

    let refresh = UIRefreshControl()
    refresh.tintColor = UIColor(
      red: AppConfig.brandBurgundy.r,
      green: AppConfig.brandBurgundy.g,
      blue: AppConfig.brandBurgundy.b,
      alpha: 1
    )
    refresh.addTarget(context.coordinator, action: #selector(Coordinator.pullToRefresh(_:)), for: .valueChanged)
    webView.scrollView.refreshControl = refresh

    let leftEdge = UIScreenEdgePanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.edgeOpenSidebar(_:))
    )
    leftEdge.edges = .left
    leftEdge.delegate = context.coordinator
    webView.addGestureRecognizer(leftEdge)

    let rightEdge = UIScreenEdgePanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.edgeGoHome(_:))
    )
    rightEdge.edges = .right
    rightEdge.delegate = context.coordinator
    webView.addGestureRecognizer(rightEdge)

    context.coordinator.webView = webView
    context.coordinator.leftEdgeGesture = leftEdge
    context.coordinator.rightEdgeGesture = rightEdge
    context.coordinator.startListening()
    CapkaFeedback.bindWebView(webView)
    webView.onSafeAreaChange = { [weak webView] in
      webView?.pushNativeSafeAreaVars()
    }
    webView.load(URLRequest(url: AppConfig.baseURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
    return webView
  }

  func updateUIView(_ webView: SafeAreaWebView, context: Context) {
    context.coordinator.parent = self
    if context.coordinator.lastReloadToken != reloadToken {
      context.coordinator.lastReloadToken = reloadToken
      webView.load(URLRequest(url: AppConfig.baseURL))
    }
  }

  static func dismantleUIView(_ uiView: SafeAreaWebView, coordinator: Coordinator) {
    coordinator.stopListening()
  }

  private static let mobileBootstrapJS = """
  (function () {
    if (window.__capkaNativeBoot) return;
    window.__capkaNativeBoot = true;
    try {
      document.documentElement.classList.add('capka-native-app');
      document.documentElement.dataset.capkaNative = 'ios';
      window.CapkaNativeApp = { platform: 'ios', version: '8' };
      document.cookie = 'capka_native=1; path=/; max-age=31536000; SameSite=Lax';
    } catch (e) {}

    // Clipboard: WKWebView often blocks navigator.clipboard; bridge to UIPasteboard.
    try {
      function nativeCopy(text) {
        try {
          window.webkit.messageHandlers.capkaNative.postMessage({ type: 'clipboardWrite', text: String(text == null ? '' : text) });
          return true;
        } catch (e) { return false; }
      }
      window.CapkaNativeApp = window.CapkaNativeApp || { platform: 'ios', version: '8' };
      window.CapkaNativeApp.copyText = function (text) { return nativeCopy(text); };
      window.CapkaNativeApp.replyBusy = function () {
        try { window.webkit.messageHandlers.capkaNative.postMessage({ type: 'replyBusy' }); } catch (e) {}
      };
      window.CapkaNativeApp.replyDone = function (preview) {
        try {
          window.webkit.messageHandlers.capkaNative.postMessage({
            type: 'replyDone',
            preview: String(preview == null ? '' : preview).slice(0, 120)
          });
        } catch (e) {}
      };
      if (!navigator.clipboard) {
        try { Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {} }); } catch (e) {}
      }
      if (navigator.clipboard) {
        navigator.clipboard.writeText = function (text) {
          return nativeCopy(text) ? Promise.resolve() : Promise.reject(new Error('clipboardWrite failed'));
        };
      }
    } catch (e) {}

    // Early CSS fallback before native push — notch + no horizontal bleed on Settings.
    try {
      if (!document.getElementById('capka-native-sa-fallback')) {
        var st = document.createElement('style');
        st.id = 'capka-native-sa-fallback';
        st.textContent = [
          'html[data-capka-native=\"ios\"],html.capka-native-app{--capka-sat:max(env(safe-area-inset-top,0px),var(--native-sat,47px));--capka-sab:max(env(safe-area-inset-bottom,0px),var(--native-sab,0px));}',
          'html[data-capka-native=\"ios\"] body,html.capka-native-app body{max-width:100%;overflow-x:hidden;}',
          'html[data-capka-native=\"ios\"] [data-capka-settings=\"1\"],html[data-capka-native=\"ios\"] [data-slot=\"sidebar-inset\"]{max-width:100%;overflow-x:hidden;}'
        ].join('');
        (document.head || document.documentElement).appendChild(st);
      }
    } catch (e) {}

    // Ask native to re-push safe-area CSS vars after SPA navigations / resume.
    function pingSafeArea() {
      try { window.webkit.messageHandlers.capkaNative.postMessage({ type: 'safeArea' }); } catch (e) {}
    }
    function scrollSettingsIntoView() {
      try {
        var scroller = document.querySelector('[data-capka-settings-scroll=\"1\"]');
        if (scroller && typeof scroller.scrollTop === 'number') scroller.scrollTop = 0;
        try { window.scrollTo(0, 0); } catch (e) {}
      } catch (e) {}
    }
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') pingSafeArea();
    });
    window.addEventListener('pageshow', pingSafeArea);
    var _push = history.pushState, _replace = history.replaceState;
    history.pushState = function () { var r = _push.apply(this, arguments); setTimeout(pingSafeArea, 50); setTimeout(pingSafeArea, 300); setTimeout(scrollSettingsIntoView, 80); return r; };
    history.replaceState = function () { var r = _replace.apply(this, arguments); setTimeout(pingSafeArea, 50); setTimeout(pingSafeArea, 300); return r; };
    window.addEventListener('popstate', function () { setTimeout(pingSafeArea, 50); setTimeout(pingSafeArea, 300); setTimeout(scrollSettingsIntoView, 80); });
    setTimeout(pingSafeArea, 100);
    setTimeout(pingSafeArea, 600);

    // Soft keyboard: scroll focused Settings fields into view (home-indicator
    // band). Chat composer lifts via web --kb — do NOT scrollIntoView there or
    // the dock double-rises into the message list.
    try {
      document.addEventListener('focusin', function (ev) {
        var el = ev.target;
        if (!el || !el.tagName) return;
        var tag = String(el.tagName).toLowerCase();
        if (tag !== 'input' && tag !== 'textarea' && tag !== 'select') return;
        try {
          if (!el.closest || !el.closest('[data-capka-settings=\"1\"]')) return;
        } catch (e) { return; }
        setTimeout(function () {
          try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' }); } catch (e) {
            try { el.scrollIntoView(true); } catch (e2) {}
          }
        }, 120);
      }, true);
    } catch (e) {}

    // Reply lifecycle: busy → native beginBackgroundTask; idle → replyDone notify.
    var wasBusy = false;
    function isBusy() {
      try {
        if (document.body && document.body.getAttribute('data-capka-busy') === '1') return true;
      } catch (e) {}
      return !!(
        document.querySelector('button[aria-label*=\"停止\"], button[aria-label*=\"Stop\"], button[title*=\"停止\"], button[title*=\"Stop\"]') ||
        document.querySelector('[data-task-busy=\"1\"]')
      );
    }
    function previewText() {
      try {
        var nodes = document.querySelectorAll('[data-role=\"assistant\"], [data-message-role=\"assistant\"]');
        if (nodes.length) return (nodes[nodes.length - 1].innerText || '').trim().slice(0, 120);
      } catch (e) {}
      return '';
    }
    function tickBusy() {
      var busy = isBusy();
      if (!wasBusy && busy) {
        try { window.CapkaNativeApp && window.CapkaNativeApp.replyBusy ? window.CapkaNativeApp.replyBusy() : window.webkit.messageHandlers.capkaNative.postMessage({ type: 'replyBusy' }); } catch (e) {
          try { window.webkit.messageHandlers.capkaNative.postMessage({ type: 'replyBusy' }); } catch (e2) {}
        }
      }
      if (wasBusy && !busy) {
        var text = previewText();
        try {
          if (window.CapkaNativeApp && window.CapkaNativeApp.replyDone) window.CapkaNativeApp.replyDone(text);
          else window.webkit.messageHandlers.capkaNative.postMessage({ type: 'replyDone', preview: text });
        } catch (e) {
          try { window.webkit.messageHandlers.capkaNative.postMessage({ type: 'replyDone', preview: text }); } catch (e2) {}
        }
      }
      wasBusy = busy;
    }
    setInterval(tickBusy, 500);
    document.addEventListener('visibilitychange', function () {
      // Wake: re-evaluate in case the turn finished while JS was frozen.
      try { tickBusy(); } catch (e) {}
    });
    // MutationObserver catches data-capka-busy flips without waiting for interval.
    try {
      var mo = new MutationObserver(tickBusy);
      mo.observe(document.documentElement, { attributes: true, subtree: true, attributeFilter: ['data-capka-busy', 'data-task-busy'] });
      if (document.body) mo.observe(document.body, { attributes: true, attributeFilter: ['data-capka-busy', 'data-task-busy'] });
    } catch (e) {}
  })();
  """

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    var parent: CapkaWebView
    weak var webView: SafeAreaWebView?
    weak var leftEdgeGesture: UIScreenEdgePanGestureRecognizer?
    weak var rightEdgeGesture: UIScreenEdgePanGestureRecognizer?
    var lastReloadToken: UUID?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var observers: [NSObjectProtocol] = []
    private var lastNativeKb: CGFloat = -1

    init(_ parent: CapkaWebView) {
      self.parent = parent
    }

    /// Prefer our edge swipes over WK/scroll pans when the touch starts at the screen edge.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      gestureRecognizer === leftEdgeGesture || gestureRecognizer === rightEdgeGesture
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      false
    }

    func startListening() {
      stopListening()
      observers.append(NotificationCenter.default.addObserver(
        forName: AppConfig.openURLNotification,
        object: nil,
        queue: .main
      ) { [weak self] note in
        guard let url = note.object as? URL else { return }
        self?.webView?.load(URLRequest(url: url))
      })
      observers.append(NotificationCenter.default.addObserver(
        forName: FeishuNativeSSO.resultNotification,
        object: nil,
        queue: .main
      ) { [weak self] note in
        self?.handleFeishuSSOResult(note.userInfo)
      })
      observers.append(NotificationCenter.default.addObserver(
        forName: FeishuNativeSSO.startNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.startFeishuSSO()
      })
      // WKWebView often scrolls / insets its UIScrollView when the keyboard opens;
      // that stacks on the web --kb lift and overlaps chat (or clips the home logo).
      // Keep the scroll view pinned at zero; Capka owns keyboard inset via CSS.
      // Also push the real keyboard overlap as --native-kb so web --kb cannot
      // under-count when visualViewport.offsetTop races the pin.
      let pushNativeKb: (CGFloat) -> Void = { [weak self] overlap in
        guard let self else { return }
        let rounded = (overlap * 2).rounded() / 2
        guard abs(rounded - self.lastNativeKb) > 0.5 else { return }
        self.lastNativeKb = rounded
        let px = Int(rounded.rounded())
        let js: String
        if px > 24 {
          js = """
          (function(){
            var r=document.documentElement;
            r.style.setProperty('--native-kb','\(px)px');
            try { window.dispatchEvent(new Event('capka-native-kb')); } catch(e) {}
          })();
          """
        } else {
          js = """
          (function(){
            var r=document.documentElement;
            r.style.setProperty('--native-kb','0px');
            try { window.dispatchEvent(new Event('capka-native-kb')); } catch(e) {}
          })();
          """
        }
        self.webView?.evaluateJavaScript(js, completionHandler: nil)
      }
      let pinScroll: (Notification) -> Void = { [weak self] note in
        guard let webView = self?.webView else { return }
        let scroll = webView.scrollView
        if scroll.contentInset != .zero {
          scroll.contentInset = .zero
        }
        if scroll.verticalScrollIndicatorInsets != .zero {
          scroll.verticalScrollIndicatorInsets = .zero
        }
        if scroll.contentOffset != .zero {
          scroll.setContentOffset(.zero, animated: false)
        }
        var overlap: CGFloat = 0
        if note.name != UIResponder.keyboardDidHideNotification,
           let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        {
          let inView = webView.convert(frame, from: nil)
          overlap = max(0, webView.bounds.maxY - inView.minY)
          if !webView.bounds.intersects(inView) { overlap = 0 }
        }
        pushNativeKb(overlap)
      }
      observers.append(NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillChangeFrameNotification,
        object: nil,
        queue: .main,
        using: pinScroll
      ))
      observers.append(NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardDidChangeFrameNotification,
        object: nil,
        queue: .main,
        using: pinScroll
      ))
      observers.append(NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardDidHideNotification,
        object: nil,
        queue: .main,
        using: pinScroll
      ))
    }

    func stopListening() {
      observers.forEach { NotificationCenter.default.removeObserver($0) }
      observers.removeAll()
    }

    private func presenter() -> UIViewController? {
      guard let host = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)?
        .rootViewController
      else { return nil }
      var top = host
      while let presented = top.presentedViewController { top = presented }
      return top
    }

    func startFeishuSSO() {
      guard let vc = presenter() else {
        parent.loadError = "无法启动飞书登录"
        return
      }
      FeishuNativeSSO.start(from: vc)
    }

    private func handleFeishuSSOResult(_ info: [AnyHashable: Any]?) {
      if let err = info?["error"] as? String {
        parent.loadError = err
        return
      }
      guard let code = info?["code"] as? String else {
        parent.loadError = "飞书登录未返回授权码"
        return
      }
      // Prefer URLSession → Set-Cookie inject → /chat. Loading a 302+Set-Cookie
      // directly in WKWebView on plain HTTP is unreliable and can leave the login page.
      completeFeishuNativeLogin(code: code, codeVerifier: info?["codeVerifier"] as? String)
    }

    private func completeFeishuNativeLogin(code: String, codeVerifier: String?) {
      DispatchQueue.main.async { self.parent.isLoading = true; self.parent.loadError = nil }

      var req = URLRequest(url: FeishuNativeSSO.nativeExchangeURL())
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.setValue("application/json", forHTTPHeaderField: "Accept")
      var body: [String: String] = ["code": code]
      if let codeVerifier, !codeVerifier.isEmpty {
        body["codeVerifier"] = codeVerifier
      }
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)

      URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
        guard let self else { return }
        if let error {
          DispatchQueue.main.async {
            self.parent.isLoading = false
            self.parent.loadError = error.localizedDescription
          }
          return
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
        let redirectPath = (json?["redirect"] as? String) ?? "/chat"
        let ok = (json?["ok"] as? Bool) == true || (200..<300).contains(status)

        guard ok, let http else {
          let reason = (json?["reason"] as? String) ?? (json?["error"] as? String) ?? "HTTP \(status)"
          DispatchQueue.main.async {
            self.parent.isLoading = false
            self.parent.loadError = "飞书登录失败：\(reason)"
          }
          return
        }

        self.injectCookies(from: http) {
          let dest: URL = {
            if redirectPath.hasPrefix("http") {
              return URL(string: redirectPath) ?? AppConfig.baseURL.appendingPathComponent("chat")
            }
            return URL(string: redirectPath, relativeTo: AppConfig.baseURL)?.absoluteURL
              ?? AppConfig.baseURL.appendingPathComponent("chat")
          }()
          DispatchQueue.main.async {
            self.parent.isLoading = false
            self.webView?.load(URLRequest(url: dest))
          }
        }
      }.resume()
    }

    /// Copy Set-Cookie from URLSession into the shared WKWebView cookie jar.
    private func injectCookies(from http: HTTPURLResponse, completion: @escaping () -> Void) {
      guard let webView else {
        completion()
        return
      }
      let url = http.url ?? AppConfig.baseURL
      var cookies: [HTTPCookie] = []
      if let fields = http.allHeaderFields as? [String: String] {
        cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: fields, for: url))
      }
      // URLSession also parks cookies in the shared jar; merge those for this host.
      if let shared = HTTPCookieStorage.shared.cookies(for: AppConfig.baseURL) {
        for c in shared where !cookies.contains(where: { $0.name == c.name && $0.domain == c.domain }) {
          cookies.append(c)
        }
      }
      // Last resort: parse a single Set-Cookie header (allHeaderFields can drop duplicates).
      if cookies.isEmpty, let raw = http.value(forHTTPHeaderField: "Set-Cookie") {
        cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: url)
      }

      let store = webView.configuration.websiteDataStore.httpCookieStore
      guard !cookies.isEmpty else {
        DispatchQueue.main.async { completion() }
        return
      }
      let group = DispatchGroup()
      for cookie in cookies {
        group.enter()
        store.setCookie(cookie) { group.leave() }
      }
      group.notify(queue: .main) { completion() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "capkaNative", let body = message.body as? [String: Any] {
        let type = body["type"] as? String
        if type == "replyDone" {
          CapkaFeedback.replyCompleted(preview: body["preview"] as? String)
        } else if type == "replyBusy" {
          CapkaFeedback.replyStarted()
        } else if type == "safeArea" {
          webView?.pushNativeSafeAreaVars(force: true)
        } else if type == "clipboardWrite" {
          let text = body["text"] as? String ?? ""
          UIPasteboard.general.string = text
        } else if type == "feishuLogin" {
          startFeishuSSO()
        }
        return
      }
      guard message.name == "capkaPreview",
            let body = message.body as? [String: Any],
            let urlString = body["url"] as? String,
            let webView
      else { return }
      let filename = (body["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: urlString) ?? URL(string: urlString, relativeTo: AppConfig.baseURL)?.absoluteURL
      else { return }
      CapkaNativePreview.present(
        url: url,
        filename: filename?.isEmpty == false ? filename! : url.lastPathComponent,
        from: webView
      )
    }

    @objc func pullToRefresh(_ control: UIRefreshControl) {
      webView?.reload()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        control.endRefreshing()
      }
    }

    @objc func edgeOpenSidebar(_ gr: UIScreenEdgePanGestureRecognizer) {
      guard gr.state == .ended else { return }
      webView?.evaluateJavaScript(
        """
        (function(){
          var t = document.querySelector('[data-sidebar="trigger"]');
          if (t) t.click();
        })();
        """,
        completionHandler: nil
      )
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc func edgeGoHome(_ gr: UIScreenEdgePanGestureRecognizer) {
      guard gr.state == .ended else { return }
      // From Settings/Projects prefer in-page navigation (keeps session warm).
      webView?.evaluateJavaScript(
        """
        (function(){
          try {
            var path = location.pathname || '';
            if (path.indexOf('/settings') === 0 || path.indexOf('/projects') === 0) {
              var a = document.querySelector('a[href=\"/chat\"]') || document.querySelector('a[href^=\"/chat?\"]');
              if (a) { a.click(); return 'click'; }
              location.assign('/chat');
              return 'assign';
            }
          } catch (e) {}
          location.assign('/chat');
          return 'assign';
        })();
        """,
        completionHandler: { [weak self] _, error in
          if error != nil {
            self?.webView?.load(URLRequest(url: AppConfig.baseURL.appendingPathComponent("chat")))
          }
        }
      )
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // Suppress Safari-like long-press link callouts / peek previews (forms & text selection still work).
    @available(iOS 13.0, *)
    func webView(
      _ webView: WKWebView,
      contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo,
      completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
      completionHandler(nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      DispatchQueue.main.async {
        self.parent.isLoading = true
        self.parent.loadError = nil
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      webView.scrollView.refreshControl?.endRefreshing()
      // WK may re-enable pinch after some navigations; keep zoom locked at app layer.
      webView.scrollView.minimumZoomScale = 1
      webView.scrollView.maximumZoomScale = 1
      webView.scrollView.bouncesZoom = false
      webView.scrollView.pinchGestureRecognizer?.isEnabled = false
      webView.allowsBackForwardNavigationGestures = false
      DispatchQueue.main.async {
        self.parent.isLoading = false
        self.parent.canGoBack = webView.canGoBack
        self.parent.loadError = nil
      }
      webView.evaluateJavaScript(CapkaWebView.mobileBootstrapJS, completionHandler: nil)
      if let safe = webView as? SafeAreaWebView {
        safe.pushNativeSafeAreaVars()
        safe.hideFormAccessoryBarIfNeeded()
      }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      failMainFrame(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      failMainFrame(error)
    }

    private func failMainFrame(_ error: Error) {
      webView?.scrollView.refreshControl?.endRefreshing()
      let ns = error as NSError
      let benign =
        (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
        || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorUnsupportedURL)
        || (ns.domain == "WebKitErrorDomain" && ns.code == 102)
      DispatchQueue.main.async {
        self.parent.isLoading = false
        if benign { return }
        self.parent.loadError = error.localizedDescription
      }
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url else {
        decisionHandler(.allow)
        return
      }
      let scheme = url.scheme?.lowercased() ?? ""
      if scheme == "tel" || scheme == "mailto" || scheme == "sms" {
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
        return
      }
      if scheme == "blob" || scheme == "data" || scheme == "about" {
        decisionHandler(.allow)
        return
      }
      // Feishu authorize page or feishu:// → LarkSSO (direct app jump + scheme return).
      if AppConfig.isFeishuAuthorizeURL(url) || AppConfig.isExternalAppScheme(scheme) {
        decisionHandler(.cancel)
        startFeishuSSO()
        return
      }
      if scheme == "http" || scheme == "https" {
        if AppConfig.allowsInAppNavigation(to: url) {
          decisionHandler(.allow)
        } else {
          UIApplication.shared.open(url)
          decisionHandler(.cancel)
        }
        return
      }
      decisionHandler(.cancel)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      if navigationResponse.canShowMIMEType {
        decisionHandler(.allow)
      } else if #available(iOS 14.5, *) {
        decisionHandler(.download)
        DispatchQueue.main.async {
          self.parent.isLoading = false
          webView.scrollView.refreshControl?.endRefreshing()
        }
      } else {
        decisionHandler(.allow)
      }
    }

    @available(iOS 14.5, *)
    func webView(
      _ webView: WKWebView,
      navigationResponse: WKNavigationResponse,
      didBecome download: WKDownload
    ) {
      download.delegate = self
    }

    @available(iOS 14.5, *)
    func webView(
      _ webView: WKWebView,
      navigationAction: WKNavigationAction,
      didBecome download: WKDownload
    ) {
      download.delegate = self
    }

    @available(iOS 14.5, *)
    func download(
      _ download: WKDownload,
      decideDestinationUsing response: URLResponse,
      suggestedFilename: String,
      completionHandler: @escaping (URL?) -> Void
    ) {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("capka-downloads", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let dest = dir.appendingPathComponent(suggestedFilename)
      try? FileManager.default.removeItem(at: dest)
      downloadDestinations[ObjectIdentifier(download)] = dest
      completionHandler(dest)
    }

    @available(iOS 14.5, *)
    func downloadDidFinish(_ download: WKDownload) {
      let id = ObjectIdentifier(download)
      let fileURL = downloadDestinations.removeValue(forKey: id)
      DispatchQueue.main.async {
        self.parent.isLoading = false
        self.webView?.scrollView.refreshControl?.endRefreshing()
      }
      guard let url = fileURL, let host = presenter() else { return }
      DispatchQueue.main.async {
        CapkaNativePreview.presentQuickLook(fileURL: url, from: host)
      }
    }

    @available(iOS 14.5, *)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
      downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
      DispatchQueue.main.async {
        self.parent.isLoading = false
        self.webView?.scrollView.refreshControl?.endRefreshing()
      }
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if let url = navigationAction.request.url {
        if AppConfig.isFeishuAuthorizeURL(url) || AppConfig.isExternalAppScheme(url.scheme ?? "") {
          startFeishuSSO()
        } else if AppConfig.allowsInAppNavigation(to: url) || url.scheme?.lowercased() == "blob" {
          webView.load(navigationAction.request)
        } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
          UIApplication.shared.open(url)
        }
      }
      return nil
    }
  }
}

final class SafeAreaWebView: WKWebView {
  var onSafeAreaChange: (() -> Void)?
  private var lastPushedInsets: UIEdgeInsets = .init(top: -1, left: -1, bottom: -1, right: -1)
  private var layoutPushWork: DispatchWorkItem?
  /// WK recreates its content view across navigations; re-apply when that happens.
  private weak var accessoryPatchedContentView: UIView?

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    pushNativeSafeAreaVars()
    onSafeAreaChange?()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    hideFormAccessoryBarIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hideFormAccessoryBarIfNeeded()
    layoutPushWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.pushNativeSafeAreaVars() }
    layoutPushWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  /// Removes WKWebView’s form-navigation toolbar (← → Done / 确定) above the
  /// keyboard. Not Capka UI — an internal `WKContentView` accessory. Hybrid
  /// apps (Capacitor/Cordova) use the same pattern: subclass that view and
  /// return `nil` for `inputAccessoryView`.
  func hideFormAccessoryBarIfNeeded() {
    guard let content = findWKContentView() else { return }
    if accessoryPatchedContentView === content { return }

    let baseName = NSStringFromClass(type(of: content))
    let subclassName = baseName + "_CapkaNoInputAccessory"
    let targetClass: AnyClass
    if let existing = NSClassFromString(subclassName) {
      targetClass = existing
    } else {
      guard let pair = objc_allocateClassPair(object_getClass(content), subclassName, 0) else { return }
      let sel = #selector(getter: UIResponder.inputAccessoryView)
      let block: @convention(block) (AnyObject) -> UIView? = { _ in nil }
      class_addMethod(pair, sel, imp_implementationWithBlock(block), "@@:")
      objc_registerClassPair(pair)
      targetClass = pair
    }
    object_setClass(content, targetClass)
    accessoryPatchedContentView = content
  }

  private func findWKContentView() -> UIView? {
    for view in scrollView.subviews {
      let name = NSStringFromClass(type(of: view))
      if name.contains("WKContent") {
        return view
      }
    }
    return nil
  }

  /// Prefer the key window's insets — WKWebView under `.ignoresSafeArea()` can
  /// briefly report 0, which left project pages with only 1.5rem top padding.
  private func resolvedSafeAreaInsets() -> UIEdgeInsets {
    var i = safeAreaInsets
    if i.top < 1 || i.bottom < 1 {
      let win = window
        ?? UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap(\.windows)
          .first(where: \.isKeyWindow)
      if let w = win {
        if w.safeAreaInsets.top > i.top { i.top = w.safeAreaInsets.top }
        if w.safeAreaInsets.bottom > i.bottom { i.bottom = w.safeAreaInsets.bottom }
        if w.safeAreaInsets.left > i.left { i.left = w.safeAreaInsets.left }
        if w.safeAreaInsets.right > i.right { i.right = w.safeAreaInsets.right }
      }
    }
    if i.top < 1, let status = window?.windowScene?.statusBarManager?.statusBarFrame.height, status > 0 {
      i.top = status
    }
    // Only when still zero (layout not ready): a notch-class floor, not for every phone.
    if i.top < 1 { i.top = 59 }
    return i
  }

  func pushNativeSafeAreaVars(force: Bool = false) {
    let i = resolvedSafeAreaInsets()
    if !force && i == lastPushedInsets { return }
    lastPushedInsets = i
    // globals.css: --capka-sat = max(env(...), var(--native-sat)). Inject both
    // --native-sa* (stylesheet contract) and --capka-sa* (direct override).
    let js = """
    (function(){
      var r = document.documentElement;
      var t = '\(i.top)px', b = '\(i.bottom)px', l = '\(i.left)px', ri = '\(i.right)px';
      r.style.setProperty('--native-sat', t);
      r.style.setProperty('--native-sab', b);
      r.style.setProperty('--native-sal', l);
      r.style.setProperty('--native-sar', ri);
      r.style.setProperty('--capka-sat', t);
      r.style.setProperty('--capka-sab', b);
      r.style.setProperty('--capka-sal', l);
      r.style.setProperty('--capka-sar', ri);
      r.classList.add('capka-native-app');
      try { r.dataset.capkaNative = 'ios'; } catch (e) {}
      try { document.cookie = 'capka_native=1; path=/; max-age=31536000; SameSite=Lax'; } catch (e) {}
    })();
    """
    evaluateJavaScript(js, completionHandler: nil)
  }
}
