import Foundation

/// Minimal SSE reader over URLSession streaming bytes.
actor SSEClient {
  private var task: Task<Void, Never>?
  private let api: CapkaAPIClient

  init(api: CapkaAPIClient = .shared) {
    self.api = api
  }

  func start(onEvent: @escaping @Sendable ([String: Any]) -> Void) {
    task?.cancel()
    task = Task {
      while !Task.isCancelled {
        do {
          try await self.consume(onEvent: onEvent)
        } catch {
          if Task.isCancelled { break }
          try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }

  private func consume(onEvent: @escaping @Sendable ([String: Any]) -> Void) async throws {
    let req = api.eventsRequest()
    let (bytes, response) = try await api.urlSession.bytes(for: req)
    if let http = response as? HTTPURLResponse {
      guard (200..<300).contains(http.statusCode) else {
        if http.statusCode == 401 { throw CapkaAPIError.unauthorized }
        throw CapkaAPIError.http(http.statusCode, nil)
      }
    }
    var dataBuffer = ""
    for try await line in bytes.lines {
      if Task.isCancelled { break }
      if line.hasPrefix(":") {
        // heartbeat comment — flush any pending event first
        flush(&dataBuffer, onEvent: onEvent)
        continue
      }
      if line.hasPrefix("data:") {
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        // Capka sends one JSON object per event; fire immediately so we don't
        // depend on a trailing blank line (some proxies coalesce differently).
        if !dataBuffer.isEmpty {
          flush(&dataBuffer, onEvent: onEvent)
        }
        dataBuffer = payload
        // Also deliver right away — blank line is optional insurance.
        flush(&dataBuffer, onEvent: onEvent)
        continue
      }
      if line.isEmpty {
        flush(&dataBuffer, onEvent: onEvent)
      }
    }
    flush(&dataBuffer, onEvent: onEvent)
  }

  private func flush(_ buffer: inout String, onEvent: @escaping @Sendable ([String: Any]) -> Void) {
    let raw = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    buffer = ""
    guard !raw.isEmpty,
          let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    onEvent(obj)
  }
}
