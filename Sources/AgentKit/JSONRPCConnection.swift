import Foundation

/// Sends and receives one line of text at a time (JSON-RPC over stdio uses one message per line).
public protocol LineTransport: Sendable {
    var lines: AsyncStream<String> { get }
    func send(_ line: String) async throws
    func close() async
}

public struct JSONRPCError: Error, Equatable, LocalizedError {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    static let stopped = JSONRPCError(code: -1, message: "The agent stopped.")
}

/// The reply that the client sends to a request from the agent.
public enum JSONRPCReply: Sendable {
    case result(JSONValue)
    case error(code: Int, message: String)
}

/// JSON-RPC 2.0 over a line transport: requests with IDs, responses, notifications, and replies to agent requests.
public actor JSONRPCConnection {
    public typealias NotificationHandler = @Sendable (String, JSONValue) -> Void
    public typealias RequestHandler = @Sendable (String, JSONValue) -> JSONRPCReply

    private let transport: LineTransport
    private let onNotification: NotificationHandler
    private let onRequest: RequestHandler
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var isClosed = false
    private var readTask: Task<Void, Never>?

    public init(transport: LineTransport, onNotification: @escaping NotificationHandler, onRequest: @escaping RequestHandler) {
        self.transport = transport
        self.onNotification = onNotification
        self.onRequest = onRequest
    }

    public func start() {
        guard readTask == nil else { return }
        let lines = transport.lines
        // The loop keeps the connection alive until the agent closes its output.
        readTask = Task {
            for await line in lines {
                guard let message = JSONRPCConnection.parseLine(line) else { continue }
                await self.handle(message)
            }
            self.closeAll()
        }
    }

    public func request(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        guard !isClosed else { throw JSONRPCError.stopped }
        let id = nextID
        nextID += 1
        let message = JSONValue.object(["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": params])
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do { try await self.write(message) } catch { self.fail(id: id, error: error) }
            }
        }
    }

    public func notify(_ method: String, _ params: JSONValue) async throws {
        guard !isClosed else { throw JSONRPCError.stopped }
        try await write(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]))
    }

    public func close() async {
        await transport.close()
        closeAll()
    }

    /// Reads one JSON-RPC message from a line. Text before it (for example, terminal escape codes, which can
    /// contain their own JSON) is skipped: each "{" is tried until a JSON-RPC object decodes.
    public nonisolated static func parseLine(_ line: String) -> JSONValue? {
        var searchStart = line.startIndex
        while let start = line[searchStart...].firstIndex(of: "{") {
            if let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line[start...].utf8)),
               value["jsonrpc"] != nil {
                return value
            }
            searchStart = line.index(after: start)
        }
        return nil
    }

    private func handle(_ message: JSONValue) async {
        let method = message["method"]?.stringValue
        if let method, let id = message["id"] {
            let reply: JSONValue
            switch onRequest(method, message["params"] ?? .null) {
            case .result(let result):
                reply = .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
            case .error(let code, let text):
                reply = .object(["jsonrpc": .string("2.0"), "id": id,
                                 "error": .object(["code": .number(Double(code)), "message": .string(text)])])
            }
            try? await write(reply)
        } else if let method {
            onNotification(method, message["params"] ?? .null)
        } else if let id = message["id"]?.intValue, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] {
                continuation.resume(throwing: JSONRPCError(code: error["code"]?.intValue ?? -32603,
                                                           message: error["message"]?.stringValue ?? "Unknown agent error."))
            } else {
                continuation.resume(returning: message["result"] ?? .null)
            }
        }
    }

    private func write(_ message: JSONValue) async throws {
        let data = try JSONEncoder().encode(message)
        try await transport.send(String(decoding: data, as: UTF8.self))
    }

    private func fail(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func closeAll() {
        isClosed = true
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: JSONRPCError.stopped) }
    }
}
