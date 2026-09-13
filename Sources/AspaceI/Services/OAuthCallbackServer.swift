import Foundation
import Network

/// 在本機 loopback 埠等待一次 OAuth 轉址，取回 query 參數後立即關閉。
final class OAuthCallbackServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var isFinished = false

    func waitForCallback(port: UInt16, path: String, timeout: Duration = .seconds(300)) async throws -> [String: String] {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw OAuthError.callbackUnavailable }
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            throw OAuthError.callbackPortInUse(port)
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: [String: String].self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        self.start(listener, port: port, path: path, continuation: continuation)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw OAuthError.timedOut
                }
                defer {
                    group.cancelAll()
                    self.finish(.failure(CancellationError()))
                }
                guard let result = try await group.next() else { throw OAuthError.timedOut }
                return result
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func start(_ listener: NWListener, port: UInt16, path: String, continuation: CheckedContinuation<[String: String], Error>) {
        let alreadyFinished = lock.withLock {
            guard !isFinished else { return true }
            self.listener = listener
            self.continuation = continuation
            return false
        }
        guard !alreadyFinished else {
            continuation.resume(throwing: CancellationError())
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.finish(.failure(OAuthError.callbackPortInUse(port)))
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection, path: path)
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func handle(_ connection: NWConnection, path: String) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            guard let query = Self.parseRequest(request, expectedPath: path) else {
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            let succeeded = query["error"] == nil
            self.respond(connection, status: "200 OK", body: Self.page(succeeded: succeeded))
            self.finish(.success(query))
        }
    }

    /// 解析 HTTP 請求行；路徑不符（例如 favicon）時回傳 nil 繼續等待。
    static func parseRequest(_ request: String, expectedPath: String) -> [String: String]? {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == expectedPath else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }

    private static func page(succeeded: Bool) -> String {
        let title = succeeded ? "登入完成" : "登入失敗"
        return "<!doctype html><meta charset=\"utf-8\"><title>AspaceI</title><body style=\"font:15px -apple-system;display:grid;place-items:center;height:90vh;color:#222\"><p>\(title)</p></body>"
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        let (listener, continuation) = lock.withLock {
            isFinished = true
            defer {
                self.listener = nil
                self.continuation = nil
            }
            return (self.listener, self.continuation)
        }
        listener?.cancel()
        continuation?.resume(with: result)
    }
}
