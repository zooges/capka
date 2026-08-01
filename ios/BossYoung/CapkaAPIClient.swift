import Foundation

enum CapkaAPIError: LocalizedError {
  case badURL
  case http(Int, String?)
  case decoding
  case unauthorized
  case message(String)

  var errorDescription: String? {
    switch self {
    case .badURL: return "无效的地址"
    case .http(let code, let body): return Self.friendlyHTTP(code: code, body: body)
    case .decoding: return "无法加载数据，请稍后重试"
    case .unauthorized: return "登录已失效，请重新登录"
    case .message(let s): return s
    }
  }

  /// Prefer the server's `error` string when present; never surface raw JSON to
  /// office users. Known codes get a calm Chinese sentence.
  private static func friendlyHTTP(code: Int, body: String?) -> String {
    if let body, let data = body.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let raw = (obj["error"] as? String) ?? (obj["message"] as? String)
      if let raw, !raw.isEmpty {
        switch raw {
        case "Chat not found":
          return "找不到这个聊天，可能已被删除"
        case "Unauthorized", "UNAUTHORIZED":
          return "登录已失效，请重新登录"
        case "Forbidden", "FORBIDDEN":
          return "没有权限执行此操作"
        default:
          if !raw.hasPrefix("{") { return raw }
        }
      }
    }
    if let body, !body.isEmpty, !body.hasPrefix("{"), !body.hasPrefix("[") {
      return body
    }
    switch code {
    case 404: return "找不到请求的内容"
    case 429: return "请求过于频繁，请稍后再试"
    case 500...599: return "服务器暂时出了问题，请稍后重试"
    default: return "请求失败（\(code)）"
    }
  }
}

final class CapkaAPIClient: @unchecked Sendable {
  static let shared = CapkaAPIClient()

  let baseURL: URL
  private let session: URLSession
  private let decoder: JSONDecoder

  init(baseURL: URL = AppConfig.baseURL) {
    self.baseURL = baseURL
    let config = URLSessionConfiguration.default
    config.httpCookieStorage = HTTPCookieStorage.shared
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 300
    // Capka is a fixed office IP. System HTTP proxies (Shadowrocket et al.)
    // often force that IP through an overseas egress and drop the connection —
    // empty dictionary disables the proxy for this session only.
    config.connectionProxyDictionary = [:]
    self.session = URLSession(configuration: config)
    self.decoder = JSONDecoder()
  }

  var hasSessionCookie: Bool {
    guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return false }
    return cookies.contains { $0.name.contains("session_token") }
  }

  func clearCookies() {
    guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return }
    for c in cookies {
      HTTPCookieStorage.shared.deleteCookie(c)
    }
  }

  // MARK: - Auth

  /// Public flag from `GET /api/auth/registration-status`.
  func isRegistrationEnabled() async -> Bool {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/registration-status"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await send(req)
      let http = try requireHTTP(response)
      guard (200..<300).contains(http.statusCode),
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return true }
      if let enabled = obj["enabled"] as? Bool { return enabled }
      return true
    } catch {
      return true
    }
  }

  /// better-auth email/password sign-in (`POST /api/auth/sign-in/email`).
  func signInWithEmail(email: String, password: String) async throws {
    try await postCredentialAuth(
      path: "api/auth/sign-in/email",
      body: ["email": email, "password": password]
    )
  }

  /// better-auth email sign-up (`POST /api/auth/sign-up/email`).
  func signUpWithEmail(name: String, email: String, password: String) async throws {
    try await postCredentialAuth(
      path: "api/auth/sign-up/email",
      body: ["name": name, "email": email, "password": password]
    )
  }

  private func postCredentialAuth(path: String, body: [String: String]) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent(path))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    storeCookies(from: http)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.message(Self.friendlyAuthError(json: json, status: http.statusCode))
    }
    guard hasSessionCookie else {
      throw CapkaAPIError.message("登录成功但未写入会话，请重试")
    }
  }

  /// Map better-auth `code` values to the calm Chinese copy used on the web.
  private static func friendlyAuthError(json: [String: Any]?, status: Int) -> String {
    let code = (json?["code"] as? String)?.uppercased() ?? ""
    switch code {
    case "INVALID_EMAIL_OR_PASSWORD", "INVALID_PASSWORD",
      "USER_NOT_FOUND", "CREDENTIAL_ACCOUNT_NOT_FOUND":
      return "电子邮件或密码无效"
    case "INVALID_EMAIL", "VALIDATION_ERROR":
      let msg = (json?["message"] as? String) ?? ""
      if msg.localizedCaseInsensitiveContains("email") {
        return "请输入有效的电子邮件地址"
      }
      return "请检查填写内容后重试"
    case "PASSWORD_TOO_SHORT":
      return "密码太短（至少 8 个字符）"
    case "PASSWORD_TOO_LONG":
      return "密码太长"
    case "EMAIL_NOT_VERIFIED":
      return "登录前请先确认您的电子邮件"
    case "USER_ALREADY_EXISTS", "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL":
      return "使用此电子邮件的帐户已存在"
    default:
      if status == 401 || status == 403 { return "电子邮件或密码无效" }
      let msg = (json?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let msg, !msg.isEmpty, !msg.hasPrefix("{") {
        if msg.localizedCaseInsensitiveContains("already") { return "使用此电子邮件的帐户已存在" }
        return msg
      }
      return "登录失败，请重试"
    }
  }

  func exchangeFeishuCode(code: String, codeVerifier: String?) async throws {
    var req = URLRequest(url: FeishuNativeSSO.nativeExchangeURL())
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: String] = ["code": code]
    if let codeVerifier, !codeVerifier.isEmpty {
      body["codeVerifier"] = codeVerifier
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    storeCookies(from: http)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let ok = (json?["ok"] as? Bool) == true || (200..<300).contains(http.statusCode)
    guard ok else {
      let reason = (json?["reason"] as? String) ?? (json?["error"] as? String) ?? "HTTP \(http.statusCode)"
      if reason == "pending" {
        throw CapkaAPIError.message("账号待管理员审批，通过后即可登录")
      }
      throw CapkaAPIError.message("飞书登录失败：\(reason)")
    }
    guard hasSessionCookie else {
      throw CapkaAPIError.message("登录成功但未写入会话，请重试")
    }
  }

  func getSession() async throws -> CapkaUser? {
    let url = baseURL.appendingPathComponent("api/auth/get-session")
    var req = URLRequest(url: url)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    if http.statusCode == 401 { return nil }
    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 404 || data.isEmpty { return nil }
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    if data.isEmpty || data == Data("null".utf8) { return nil }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    // better-auth: { session, user } — or nullish session
    if obj["session"] == nil && obj["user"] == nil {
      return nil
    }
    let userObj = (obj["user"] as? [String: Any]) ?? obj
    guard let id = userObj["id"] as? String else { return nil }
    let name = (userObj["name"] as? String)
      ?? (userObj["email"] as? String)
      ?? "用户"
    return CapkaUser(
      id: id,
      name: name,
      email: userObj["email"] as? String,
      role: userObj["role"] as? String,
      status: userObj["status"] as? String
    )
  }

  func signOut() async {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/sign-out"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    _ = try? await session.data(for: req)
    clearCookies()
  }

  // MARK: - Chats

  func listChats(
    cursor: String? = nil,
    archived: Bool? = false,
    projectId: String? = nil,
    search: String? = nil
  ) async throws -> (chats: [ChatSummary], nextCursor: String?) {
    var c = URLComponents(url: baseURL.appendingPathComponent("api/chats"), resolvingAgainstBaseURL: false)!
    var items: [URLQueryItem] = []
    if let cursor, !cursor.isEmpty {
      items.append(URLQueryItem(name: "cursor", value: cursor))
    }
    if let archived {
      items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false"))
    }
    if let projectId {
      items.append(URLQueryItem(name: "projectId", value: projectId))
    }
    if let search, !search.isEmpty {
      items.append(URLQueryItem(name: "search", value: search))
    }
    c.queryItems = items.isEmpty ? nil : items
    var req = URLRequest(url: c.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let chats = try ChatSummary.parseList(from: data)
    let next = http.value(forHTTPHeaderField: "X-Next-Cursor")
    return (chats, next)
  }

  func createChat(title: String? = nil, model: String? = nil, projectId: String? = nil) async throws -> String {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/chats"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: String] = [:]
    if let title { body["title"] = title }
    if let model { body["model"] = model }
    if let projectId { body["projectId"] = projectId }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = json["id"] as? String
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return id
  }

  func patchChat(
    id: String,
    title: String? = nil,
    pinned: Bool? = nil,
    archived: Bool? = nil,
    projectId: String?? = nil
  ) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/chats/\(id)"))
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: Any] = [:]
    if let title { body["title"] = title }
    if let pinned { body["pinned"] = pinned }
    if let archived { body["archived"] = archived }
    if let projectId {
      body["projectId"] = projectId.map { $0 as Any } ?? NSNull()
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
      throw CapkaAPIError.http(http.statusCode, msg ?? String(data: data, encoding: .utf8))
    }
  }

  func deleteChat(id: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/chats/\(id)"))
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  // MARK: - Messages

  func fetchMessages(chatId: String) async throws -> [ChatUIMessage] {
    var c = URLComponents(url: baseURL.appendingPathComponent("api/chat"), resolvingAgainstBaseURL: false)!
    c.queryItems = [URLQueryItem(name: "chatId", value: chatId)]
    var req = URLRequest(url: c.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw CapkaAPIError.decoding
    }
    return arr.map { Self.mapUIMessage($0) }
  }

  func sendMessage(
    chatId: String?,
    text: String,
    model: String?,
    userMessageId: String?,
    attachedFiles: [[String: String]]?,
    history: [[String: Any]]? = nil
  ) async throws -> SendChatResponse {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: Any] = ["userMessage": text]
    if let chatId { body["chatId"] = chatId }
    if let model, !model.isEmpty { body["model"] = model }
    if let userMessageId { body["userMessageId"] = userMessageId }
    if let attachedFiles { body["attachedFiles"] = attachedFiles }
    if let history { body["messages"] = history }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
      throw CapkaAPIError.http(http.statusCode, msg ?? String(data: data, encoding: .utf8))
    }
    return try decoder.decode(SendChatResponse.self, from: data)
  }

  /// Regenerate the latest assistant turn — empty `userMessage` skips inserting
  /// a new user row (same contract as the web `regenerate()` hook).
  func regenerateMessage(
    chatId: String,
    model: String?,
    history: [ChatUIMessage]
  ) async throws -> SendChatResponse {
    let payload: [[String: Any]] = history.map { msg in
      [
        "id": msg.id,
        "role": msg.role,
        "parts": [["type": "text", "text": msg.text]],
      ]
    }
    return try await sendMessage(
      chatId: chatId,
      text: "",
      model: model,
      userMessageId: nil,
      attachedFiles: nil,
      history: payload
    )
  }

  func cancelTask(taskId: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/tasks/\(taskId)/cancel"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  struct TaskSnapshot {
    var id: String
    var status: String
    var error: String?
  }

  func latestTask(chatId: String) async throws -> TaskSnapshot? {
    var c = URLComponents(url: baseURL.appendingPathComponent("api/tasks"), resolvingAgainstBaseURL: false)!
    c.queryItems = [URLQueryItem(name: "chatId", value: chatId)]
    var req = URLRequest(url: c.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    if data.isEmpty || data == Data("null".utf8) { return nil }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["id"] as? String,
          let status = obj["status"] as? String
    else { return nil }
    return TaskSnapshot(id: id, status: status, error: obj["error"] as? String)
  }

  func markChatRead(chatId: String) async {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/chats/\(chatId)/read"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    _ = try? await session.data(for: req)
  }

  func listModels() async throws -> [ModelInfo] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/models"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return try ModelInfo.parseList(from: data)
  }

  func uploadFile(chatId: String? = nil, projectId: String? = nil, fileURL: URL) async throws -> (name: String, type: String) {
    let boundary = "Boundary-\(UUID().uuidString)"
    var req = URLRequest(url: baseURL.appendingPathComponent("api/sandbox/files/upload"))
    req.httpMethod = "POST"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    let filename = fileURL.lastPathComponent
    let mime = mimeType(for: fileURL)
    let fileData = try Data(contentsOf: fileURL)

    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }
    if let chatId {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"chatId\"\r\n\r\n\(chatId)\r\n")
    }
    if let projectId {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"projectId\"\r\n\r\n\(projectId)\r\n")
    }
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"path\"\r\n\r\n.\r\n")
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: \(mime)\r\n\r\n")
    body.append(fileData)
    append("\r\n--\(boundary)--\r\n")
    req.httpBody = body

    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return (filename, mime)
  }

  // MARK: - Projects

  func listProjects() async throws -> [ProjectSummary] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/projects"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return try ProjectSummary.parseList(from: data)
  }

  func createProject(name: String, description: String? = nil) async throws -> ProjectSummary {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/projects"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: Any] = ["name": name]
    if let description, !description.isEmpty { body["description"] = description }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let project = ProjectSummary.parseOne(obj)
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return project
  }

  func updateProject(id: String, name: String?, description: String?, systemPrompt: String?) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/projects/\(id)"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    var body: [String: Any] = [:]
    if let name { body["name"] = name }
    if let description { body["description"] = description }
    if let systemPrompt { body["systemPrompt"] = systemPrompt }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func deleteProject(id: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/projects/\(id)"))
    req.httpMethod = "DELETE"
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
      throw CapkaAPIError.http(http.statusCode, msg ?? String(data: data, encoding: .utf8))
    }
  }

  // MARK: - Workspace files

  func listFiles(chatId: String? = nil, projectId: String? = nil, path: String = ".") async throws -> [WorkspaceEntry] {
    var c = URLComponents(url: baseURL.appendingPathComponent("api/sandbox/files"), resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "depth", value: "1")]
    if let chatId { items.append(URLQueryItem(name: "chatId", value: chatId)) }
    if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }
    c.queryItems = items
    var req = URLRequest(url: c.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let entries = root["entries"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return entries.compactMap { e in
      guard let name = e["name"] as? String, let path = e["path"] as? String else { return nil }
      let isDir = boolValue(e["isDirectory"]) ?? false
      let size: Int64?
      if let i = e["size"] as? Int { size = Int64(i) }
      else if let d = e["size"] as? Double { size = Int64(d) }
      else { size = nil }
      return WorkspaceEntry(name: name, path: path, isDirectory: isDir, size: size)
    }
  }

  func downloadURL(chatId: String? = nil, projectId: String? = nil, path: String, inline: Bool = true) -> URL? {
    var c = URLComponents(url: baseURL.appendingPathComponent("api/sandbox/files/download"), resolvingAgainstBaseURL: false)!
    var items = [URLQueryItem(name: "path", value: path)]
    if inline { items.append(URLQueryItem(name: "inline", value: "1")) }
    if let chatId { items.append(URLQueryItem(name: "chatId", value: chatId)) }
    if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }
    c.queryItems = items
    return c.url
  }

  /// Quick Look needs a real file on disk. Pulls one through the same cookie
  /// session as every other call and keeps the original filename so the
  /// extension still picks the right renderer.
  func downloadToTemp(
    chatId: String? = nil,
    projectId: String? = nil,
    path: String,
    filename: String
  ) async throws -> URL {
    guard let url = downloadURL(chatId: chatId, projectId: projectId, path: path, inline: true) else {
      throw CapkaAPIError.badURL
    }
    var req = URLRequest(url: url)
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("capka-preview", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let safe = filename.replacingOccurrences(of: "/", with: "_")
    let dest = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
    try data.write(to: dest, options: .atomic)
    return dest
  }

  // MARK: - Settings / skills / connectors

  func putTimezone(_ timezone: String) async {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/timezone"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["timezone": timezone])
    _ = try? await session.data(for: req)
  }

  func putLocale(_ locale: String) async {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/locale"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["locale": locale])
    _ = try? await session.data(for: req)
  }

  func updateUserName(_ name: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/auth/update-user"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func fetchBilling() async throws -> BillingInfo? {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/me/billing"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let onShared = boolValue(root["onSharedKey"]) ?? false
    let ownKeys = boolValue(root["ownKeysAllowed"]) ?? true
    guard let limits = root["limits"] as? [String: Any] else {
      return BillingInfo(onSharedKey: onShared, ownKeysAllowed: ownKeys, tierName: nil, windows: [], blocked: false)
    }
    let windows = (limits["windows"] as? [[String: Any]] ?? []).compactMap { w -> BillingWindow? in
      guard let window = w["window"] as? String else { return nil }
      let pct = (w["pct"] as? Double) ?? Double(w["pct"] as? Int ?? 0)
      let limit = (w["limit"] as? Double) ?? (w["limit"] as? Int).map(Double.init)
      return BillingWindow(window: window, pct: pct, limit: limit)
    }
    return BillingInfo(
      onSharedKey: onShared,
      ownKeysAllowed: ownKeys,
      tierName: limits["tierName"] as? String,
      windows: windows,
      blocked: boolValue(limits["blocked"]) ?? false
    )
  }

  func fetchTelegramLink() async throws -> TelegramLinkInfo {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/telegram/link"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return TelegramLinkInfo(
      linked: boolValue(root["linked"]) ?? false,
      username: root["username"] as? String,
      botUsername: root["botUsername"] as? String,
      linkedAt: root["linkedAt"] as? String
    )
  }

  func createTelegramLinkCode() async throws -> String {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/telegram/link"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let code = root["code"] as? String
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return code
  }

  func unlinkTelegram() async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/telegram/link"))
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func fetchMemoryDocs() async throws -> (user: String, projects: [MemoryProjectDoc]) {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/memory-docs"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let user = (root["user"] as? String) ?? ""
    let projects = (root["projects"] as? [[String: Any]] ?? []).compactMap { o -> MemoryProjectDoc? in
      guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
      return MemoryProjectDoc(id: id, name: name, content: (o["content"] as? String) ?? "")
    }
    return (user, projects)
  }

  func listPlugins() async throws -> [PluginInfo] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/extensions"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = root["plugins"] as? [[String: Any]]
    else {
      // Capability may be missing on older hosts — treat as empty.
      if http.statusCode == 404 { return [] }
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return arr.compactMap { o in
      guard let id = o["id"] as? String else { return nil }
      let name = (o["name"] as? String) ?? id
      return PluginInfo(
        id: id,
        name: name,
        description: o["description"] as? String,
        enabled: boolValue(o["enabled"]) ?? true,
        author: o["author"] as? String
      )
    }
  }

  func listSkills() async throws -> [SkillInfo] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/skills"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = root["skills"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return arr.compactMap { o in
      guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
      return SkillInfo(
        id: id,
        name: name,
        description: o["description"] as? String,
        enabled: boolValue(o["enabled"]) ?? true,
        scope: o["scope"] as? String,
        mine: boolValue(o["mine"])
      )
    }
  }

  func setSkillEnabled(id: String, enabled: Bool) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/skills"))
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "enabled": enabled])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func listConnectors() async throws -> [ConnectorInfo] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/mcp"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = root["servers"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return arr.compactMap { o in
      guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
      return ConnectorInfo(
        id: id,
        name: name,
        url: o["url"] as? String,
        enabled: boolValue(o["enabled"]) ?? true,
        scope: o["scope"] as? String,
        authKind: o["authKind"] as? String
      )
    }
  }

  func setConnectorEnabled(id: String, enabled: Bool) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/mcp"))
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "enabled": enabled])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func listAutomations() async throws -> [AutomationInfo] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/automations"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = root["automations"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return arr.compactMap { o in
      guard let id = o["id"] as? String else { return nil }
      let title = (o["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      return AutomationInfo(
        id: id,
        title: (title?.isEmpty == false ? title! : "未命名自动化"),
        enabled: boolValue(o["enabled"]) ?? true,
        nextRunAt: o["nextRunAt"] as? String,
        lastRunAt: o["lastRunAt"] as? String,
        lastChatId: o["lastChatId"] as? String
      )
    }
  }

  func setAutomationEnabled(id: String, enabled: Bool) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/automations/\(id)"))
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["enabled": enabled])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func deleteAutomation(id: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/automations/\(id)"))
    req.httpMethod = "DELETE"
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func fetchMemory() async throws -> String {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/memory-docs"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return (root["user"] as? String) ?? ""
  }

  func fetchProjectMemory(projectId: String) async throws -> String {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/memory-docs"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let projects = root["projects"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return (projects.first { $0["id"] as? String == projectId }?["content"] as? String) ?? ""
  }

  func saveMemory(_ content: String, projectId: String? = nil) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/memory-docs"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["content": content]
    if let projectId { body["projectId"] = projectId }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  // MARK: - Settings: connections + admin

  func listProviders() async throws -> [ProviderConfig] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/providers"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return root.compactMap { o in
      guard let id = o["id"] as? String, let provider = o["provider"] as? String else { return nil }
      return ProviderConfig(
        id: id,
        provider: provider,
        label: o["label"] as? String,
        defaultModel: o["defaultModel"] as? String,
        baseUrl: o["baseUrl"] as? String,
        isActive: boolValue(o["isActive"]) ?? true,
        shared: boolValue(o["shared"]) ?? false,
        apiStyle: o["apiStyle"] as? String
      )
    }
  }

  /// Add a provider connection. Mirrors `POST /api/settings/providers`; the key
  /// is encrypted server-side with the instance master key, never stored here.
  func createProvider(
    provider: String,
    apiKey: String?,
    baseUrl: String?,
    defaultModel: String?,
    label: String?,
    shared: Bool,
    apiStyle: String?
  ) async throws {
    var body: [String: Any] = ["provider": provider, "shared": shared]
    if let apiKey, !apiKey.isEmpty { body["apiKey"] = apiKey }
    if let baseUrl, !baseUrl.isEmpty { body["baseUrl"] = baseUrl }
    if let defaultModel, !defaultModel.isEmpty { body["defaultModel"] = defaultModel }
    if let label, !label.isEmpty { body["label"] = label }
    if let apiStyle, !apiStyle.isEmpty { body["apiStyle"] = apiStyle }
    try await mutate(path: "api/settings/providers", method: "POST", json: body)
  }

  func updateProvider(
    id: String,
    defaultModel: String? = nil,
    label: String? = nil,
    shared: Bool? = nil,
    apiStyle: String? = nil
  ) async throws {
    var body: [String: Any] = ["id": id]
    if let defaultModel { body["defaultModel"] = defaultModel }
    if let label { body["label"] = label }
    if let shared { body["shared"] = shared }
    if let apiStyle { body["apiStyle"] = apiStyle }
    try await mutate(path: "api/settings/providers", method: "PUT", json: body)
  }

  /// One live call against the provider before saving. Returns the sample reply
  /// so the admin sees proof it worked, not just a green tick.
  func testProvider(
    provider: String,
    apiKey: String?,
    modelId: String,
    baseUrl: String?,
    apiStyle: String?
  ) async throws -> String {
    var body: [String: Any] = ["provider": provider, "modelId": modelId]
    if let apiKey, !apiKey.isEmpty { body["apiKey"] = apiKey }
    if let baseUrl, !baseUrl.isEmpty { body["baseUrl"] = baseUrl }
    if let apiStyle, !apiStyle.isEmpty { body["apiStyle"] = apiStyle }
    let root = try await mutateJSON(path: "api/settings/providers/test", method: "POST", json: body)
    return (root["text"] as? String) ?? "连接成功"
  }

  /// Re-reads every enabled provider's model list into the catalog.
  func resyncModels() async throws {
    try await mutate(path: "api/admin/models/resync", method: "POST", json: [:])
  }

  func setProviderEnabled(id: String, enabled: Bool) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/providers"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "enabled": enabled])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func deleteProvider(id: String) async throws {
    var comps = URLComponents(url: baseURL.appendingPathComponent("api/settings/providers"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "id", value: id)]
    var req = URLRequest(url: comps.url!)
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func listAdminUsers() async throws -> [AdminUserRow] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/users"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let users = root["users"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return users.compactMap { o in
      guard let id = o["id"] as? String else { return nil }
      let cost = (o["cost30d"] as? Double) ?? (o["cost30d"] as? Int).map(Double.init)
      return AdminUserRow(
        id: id,
        name: (o["name"] as? String) ?? "—",
        email: o["email"] as? String,
        role: (o["role"] as? String) ?? "user",
        status: (o["status"] as? String) ?? "active",
        cost30d: cost
      )
    }
  }

  func updateAdminUser(userId: String, role: String? = nil, status: String? = nil) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/users"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["userId": userId]
    if let role { body["role"] = role }
    if let status { body["status"] = status }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func fetchAdminUsage(days: Int = 30) async throws -> AdminUsageSummary {
    var comps = URLComponents(url: baseURL.appendingPathComponent("api/admin/usage"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "days", value: String(days))]
    var req = URLRequest(url: comps.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let totals = root["totals"] as? [String: Any] ?? [:]
    return AdminUsageSummary(
      days: (root["days"] as? Int) ?? days,
      cost: (totals["cost"] as? Double) ?? Double(totals["cost"] as? Int ?? 0),
      inputTokens: (totals["inputTokens"] as? Int) ?? 0,
      outputTokens: (totals["outputTokens"] as? Int) ?? 0,
      calls: (totals["calls"] as? Int) ?? 0,
      activeMembers: root["activeMembers"] as? Int
    )
  }

  func fetchAdminBilling() async throws -> (keyMode: String?, monthlyBudget: Double?) {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/billing"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let budget = (root["monthlyBudget"] as? Double) ?? (root["monthlyBudget"] as? Int).map(Double.init)
    return (root["keyMode"] as? String, budget)
  }

  func fetchAuthConfig() async throws -> AuthConfigInfo {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/auth-config"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    let feishu = root["feishu"] as? [String: Any] ?? [:]
    let telegram = root["telegram"] as? [String: Any] ?? [:]
    return AuthConfigInfo(
      registrationMode: root["registrationMode"] as? String,
      emailSignupEnabled: boolValue(root["emailSignupEnabled"]) ?? false,
      feishuReady: boolValue(feishu["ready"]) ?? false,
      feishuEnabled: boolValue(feishu["enabledToggle"]) ?? boolValue(feishu["enabled"]) ?? false,
      telegramReady: boolValue(telegram["ready"]) ?? false,
      telegramEnabled: boolValue(telegram["enabledToggle"]) ?? boolValue(telegram["enabled"]) ?? false
    )
  }

  func fetchAdminUpdates() async throws -> AdminUpdatesInfo {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/updates"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return AdminUpdatesInfo(
      current: root["current"] as? String,
      latest: root["latest"] as? String,
      updateAvailable: boolValue(root["updateAvailable"]) ?? false,
      releaseName: root["releaseName"] as? String,
      notes: root["notes"] as? String,
      error: root["error"] as? String
    )
  }

  func fetchAuditLog(limit: Int = 40) async throws -> [AuditEntry] {
    var comps = URLComponents(url: baseURL.appendingPathComponent("api/admin/audit"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
    var req = URLRequest(url: comps.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let entries = root["entries"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return entries.compactMap { o in
      guard let id = o["id"] as? String, let action = o["action"] as? String else { return nil }
      return AuditEntry(
        id: id,
        actorName: o["actorName"] as? String,
        action: action,
        targetType: o["targetType"] as? String,
        targetKey: o["targetKey"] as? String,
        createdAt: o["createdAt"] as? String
      )
    }
  }

  func fetchSandboxCapabilities() async throws -> SandboxCapabilities {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/sandbox-capabilities"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return SandboxCapabilities(allowNetwork: boolValue(root["allowNetwork"]))
  }

  func fetchSetting(key: String) async throws -> String? {
    var comps = URLComponents(url: baseURL.appendingPathComponent("api/settings"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "key", value: key)]
    var req = URLRequest(url: comps.url!)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let s = root["value"] as? String { return s }
    if let b = root["value"] as? Bool { return b ? "true" : "false" }
    return nil
  }

  /// Generic key/value settings write. The server enforces its own allow-list
  /// (`src/app/api/settings/keys.ts`), so an unknown key comes back 403.
  // MARK: - Skills / connectors / plugins (writes)

  /// Skills arrive as an Anthropic-compatible zip; the server unpacks and
  /// validates it (`ingestSkillZip`), so the client just posts the file.
  func uploadSkillZip(fileURL: URL) async throws {
    let boundary = "Boundary-\(UUID().uuidString)"
    var req = URLRequest(url: baseURL.appendingPathComponent("api/skills"))
    req.httpMethod = "POST"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
    append("Content-Type: application/zip\r\n\r\n")
    body.append(try Data(contentsOf: fileURL))
    append("\r\n--\(boundary)--\r\n")
    req.httpBody = body

    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func deleteSkill(id: String) async throws {
    try await mutate(path: "api/skills", method: "DELETE", query: [URLQueryItem(name: "id", value: id)])
  }

  func createConnector(
    name: String,
    url: String,
    authKind: String,
    token: String?,
    oauthClientId: String?,
    oauthClientSecret: String?,
    transport: String?
  ) async throws {
    var body: [String: Any] = ["name": name, "url": url, "authKind": authKind]
    // The server takes bearer auth as a header map, matching the web form.
    if let token, !token.isEmpty { body["headers"] = ["Authorization": "Bearer \(token)"] }
    if let oauthClientId, !oauthClientId.isEmpty { body["oauthClientId"] = oauthClientId }
    if let oauthClientSecret, !oauthClientSecret.isEmpty { body["oauthClientSecret"] = oauthClientSecret }
    if let transport, !transport.isEmpty { body["transport"] = transport }
    try await mutate(path: "api/mcp", method: "POST", json: body)
  }

  func updateConnectorToken(id: String, token: String) async throws {
    try await mutate(
      path: "api/mcp",
      method: "PATCH",
      json: ["id": id, "headers": ["Authorization": "Bearer \(token)"]]
    )
  }

  func deleteConnector(id: String) async throws {
    try await mutate(path: "api/mcp", method: "DELETE", query: [URLQueryItem(name: "id", value: id)])
  }

  /// Probe a connector URL before saving. Returns the server's status string
  /// (`ok`, `needs_login`, `error`, …) plus whatever detail it sent.
  func testConnector(url: String, token: String?, transport: String?) async throws -> (status: String, detail: String?) {
    var body: [String: Any] = ["url": url]
    if let token, !token.isEmpty { body["headers"] = ["Authorization": "Bearer \(token)"] }
    if let transport, !transport.isEmpty { body["transport"] = transport }
    let root = try await mutateJSON(path: "api/mcp/test", method: "POST", json: body)
    let status = (root["status"] as? String) ?? "unknown"
    let detail = (root["error"] as? String) ?? (root["serverName"] as? String)
    return (status, detail)
  }

  func setPluginEnabled(id: String, enabled: Bool) async throws {
    try await mutate(path: "api/extensions", method: "PATCH", json: ["id": id, "enabled": enabled])
  }

  func uninstallPlugin(id: String) async throws {
    try await mutate(path: "api/extensions", method: "DELETE", query: [URLQueryItem(name: "id", value: id)])
  }

  // MARK: - Admin writes

  func deleteAdminUser(userId: String) async throws {
    try await mutate(
      path: "api/admin/users",
      method: "DELETE",
      query: [URLQueryItem(name: "userId", value: userId)]
    )
  }

  /// `POST /api/admin/auth-config` takes a partial patch; only send what changed.
  func updateAuthConfig(_ patch: [String: Any]) async throws {
    try await mutate(path: "api/admin/auth-config", method: "POST", json: patch)
  }

  func putSetting(key: String, value: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key, "value": value])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func fetchAgentProfile() async throws -> AgentProfile {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/agent-profile"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return AgentProfile.parse(root)
  }

  func putAgentProfile(_ profile: AgentProfile) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/settings/agent-profile"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: profile.payload)
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func setProviderKeyMode(_ mode: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/billing"))
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["action": "setMode", "mode": mode])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func listPolicies() async throws -> [PolicyRow] {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/policies"))
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode),
          let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = root["policies"] as? [[String: Any]]
    else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return rows.compactMap { o in
      guard let id = o["id"] as? String,
            let type = o["capabilityType"] as? String,
            let key = o["capabilityKey"] as? String,
            let effect = o["effect"] as? String
      else { return nil }
      return PolicyRow(
        id: id,
        capabilityType: type,
        capabilityKey: key,
        effect: effect,
        scope: (o["scope"] as? String) ?? "system"
      )
    }
  }

  /// Upsert a system-scope rule. The server keys on (type, key, scope), so this
  /// replaces an existing system rule rather than stacking a second one.
  func setSystemPolicy(capabilityType: String, capabilityKey: String, effect: String) async throws {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/admin/policies"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
      "capabilityType": capabilityType,
      "capabilityKey": capabilityKey,
      "effect": effect,
      "scope": "system",
    ])
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func clearPolicy(id: String) async throws {
    var comps = URLComponents(url: baseURL.appendingPathComponent("api/admin/policies"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "id", value: id)]
    var req = URLRequest(url: comps.url!)
    req.httpMethod = "DELETE"
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  private func boolValue(_ any: Any?) -> Bool? {
    if any == nil || any is NSNull { return nil }
    if let b = any as? Bool { return b }
    if let i = any as? Int { return i != 0 }
    return nil
  }

  func eventsRequest() -> URLRequest {
    var req = URLRequest(url: baseURL.appendingPathComponent("api/events"))
    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    return req
  }

  var urlSession: URLSession { session }

  // MARK: - Helpers

  /// A JSON write that only needs to succeed. `query` goes on the URL (the
  /// DELETE endpoints here take their id there), `json` in the body.
  @discardableResult
  private func mutate(
    path: String,
    method: String,
    json: [String: Any]? = nil,
    query: [URLQueryItem]? = nil
  ) async throws -> Data {
    var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if let query, !query.isEmpty { comps.queryItems = query }
    var req = URLRequest(url: comps.url!)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let json, !json.isEmpty {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: json)
    }
    let (data, response) = try await send(req)
    let http = try requireHTTP(response)
    try throwIfUnauthorized(http, data: data)
    guard (200..<300).contains(http.statusCode) else {
      throw CapkaAPIError.http(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  /// Same, for the writes whose response body carries something we show.
  private func mutateJSON(
    path: String,
    method: String,
    json: [String: Any]? = nil,
    query: [URLQueryItem]? = nil
  ) async throws -> [String: Any] {
    let data = try await mutate(path: path, method: method, json: json, query: query)
    return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
  }

  /// Single egress point, so every transport failure reaches the UI as one of
  /// our plain-language sentences instead of a raw `NSURLErrorDomain` string.
  private func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await session.data(for: req)
    } catch {
      throw CapkaAPIError.message(Self.friendlyNetworkError(error))
    }
  }

  private func requireHTTP(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let http = response as? HTTPURLResponse else { throw CapkaAPIError.decoding }
    return http
  }

  private func throwIfUnauthorized(_ http: HTTPURLResponse, data: Data) throws {
    if http.statusCode == 401 {
      throw CapkaAPIError.unauthorized
    }
  }

  /// Ensure Set-Cookie lands in the jar (URLSession can miss dotted cookie names / IP hosts).
  private func storeCookies(from http: HTTPURLResponse) {
    let url = http.url ?? baseURL
    var cookies: [HTTPCookie] = []
    if let fields = http.allHeaderFields as? [String: String] {
      cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: fields, for: url))
    }
    if cookies.isEmpty, let raw = http.value(forHTTPHeaderField: "Set-Cookie") {
      cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: url)
    }
    for cookie in cookies {
      HTTPCookieStorage.shared.setCookie(cookie)
    }
  }

  private static func friendlyNetworkError(_ error: Error) -> String {
    let ns = error as NSError
    guard ns.domain == NSURLErrorDomain else {
      return "网络错误：\(error.localizedDescription)"
    }
    // A VPN / proxy that routes this office IP abroad is by far the most common
    // cause here, and it looks identical to "server down" from the client side.
    let proxyHint = "请检查网络，或关闭 VPN / 代理后重试"
    switch ns.code {
    case NSURLErrorNotConnectedToInternet:
      return "当前没有网络连接，请连接 Wi-Fi 或蜂窝网络后重试"
    case NSURLErrorTimedOut:
      return "连接服务器超时，\(proxyHint)"
    case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
      NSURLErrorNetworkConnectionLost, NSURLErrorBadServerResponse,
      NSURLErrorSecureConnectionFailed, NSURLErrorDNSLookupFailed:
      return "无法连接服务器，\(proxyHint)"
    case NSURLErrorDataNotAllowed:
      return "当前网络不允许连接，请在「设置 › 蜂窝网络」中允许本应用使用数据"
    default:
      return "网络错误：\(error.localizedDescription)"
    }
  }

  static func mapUIMessage(_ raw: [String: Any]) -> ChatUIMessage {
    let id = raw["id"] as? String ?? UUID().uuidString
    let role = raw["role"] as? String ?? "assistant"
    let meta = raw["metadata"] as? [String: Any]
    let status = meta?["taskStatus"] as? String
    let streaming = status == "running"

    var textChunks: [String] = []
    var tools: [String] = []
    var steps: [MessageStep] = []

    if let parts = raw["parts"] as? [Any] {
      for (index, part) in parts.enumerated() {
        guard let p = part as? [String: Any] else { continue }
        let type = (p["type"] as? String ?? "").lowercased()

        if type == "text" || type.hasSuffix("-text") || type == "output_text" {
          if let t = p["text"] as? String, !t.isEmpty {
            textChunks.append(t)
          } else if let t = p["content"] as? String, !t.isEmpty {
            textChunks.append(t)
          }
          continue
        }

        if type == "reasoning" {
          guard let t = (p["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !t.isEmpty
          else { continue }
          steps.append(
            MessageStep(
              id: "\(id)-reason-\(index)",
              kind: .reasoning,
              state: streaming ? .running : .done,
              label: "推理",
              icon: "lightbulb",
              detail: t
            )
          )
          continue
        }

        if type.contains("tool") {
          let name = (p["toolName"] as? String) ?? (p["name"] as? String) ?? ""
          if !name.isEmpty { tools.append(name) }
          let state = (p["state"] as? String ?? "").lowercased()
          let stepState: MessageStep.State
          switch state {
          case "output-error": stepState = .failed
          case "output-available", "": stepState = .done
          default: stepState = streaming ? .running : .done
          }
          let described = StepDescriber.describe(
            toolName: name,
            input: p["input"] as? [String: Any],
            running: stepState == .running
          )
          var detail = p["errorText"] as? String
          if detail == nil, let input = p["input"] as? [String: Any] {
            detail = (input["command"] as? String) ?? (input["code"] as? String)
          }
          steps.append(
            MessageStep(
              id: (p["toolCallId"] as? String) ?? "\(id)-tool-\(index)",
              kind: .tool,
              state: stepState,
              label: described.label,
              icon: described.icon,
              detail: detail
            )
          )
        }
      }
    }

    var text = textChunks.joined(separator: "\n\n")
    if text.isEmpty, let content = raw["content"] as? String, !content.isEmpty {
      text = content
    }

    let error = (meta?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    let attachments: [MessageAttachment] = (meta?["attachedFiles"] as? [[String: Any]] ?? []).compactMap {
      guard let name = $0["name"] as? String else { return nil }
      return MessageAttachment(name: name, type: ($0["type"] as? String) ?? "application/octet-stream")
    }

    let usage = meta?["usage"] as? [String: Any]
    func intOf(_ any: Any?) -> Int? {
      if let i = any as? Int { return i }
      if let d = any as? Double { return Int(d) }
      return nil
    }
    let created = (meta?["createdAt"] as? String).flatMap {
      ISO8601DateFormatter.capkaFractional.date(from: $0) ?? ISO8601DateFormatter.capkaPlain.date(from: $0)
    }
    let details = MessageDetails(
      model: meta?["model"] as? String,
      inputTokens: intOf(usage?["input"]),
      outputTokens: intOf(usage?["output"]),
      durationMs: intOf(meta?["durationMs"]),
      stepCount: steps.isEmpty ? nil : steps.count,
      createdAt: created,
      contextTokens: intOf(meta?["contextTokens"]),
      contextWindow: intOf(meta?["contextWindow"])
    )

    return ChatUIMessage(
      id: id,
      role: role,
      text: text,
      isStreaming: streaming,
      error: (error?.isEmpty == false ? error : nil),
      tools: tools,
      steps: steps,
      attachments: attachments,
      details: details,
      isCompaction: meta?["compaction"] != nil && !(meta?["compaction"] is NSNull),
      compactionSummary: (meta?["compaction"] as? [String: Any])?["summary"] as? String
    )
  }

  private func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "pdf": return "application/pdf"
    case "txt", "md": return "text/plain"
    case "csv": return "text/csv"
    case "json": return "application/json"
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    default: return "application/octet-stream"
    }
  }
}
