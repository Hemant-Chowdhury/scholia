import Foundation

public struct ACPChoice: Sendable, Equatable, Hashable {
    public let value: String
    public let name: String

    public init(value: String, name: String) {
        self.value = value
        self.name = name
    }
}

/// A session setting that the agent offers, for example the model.
public struct ACPConfigOption: Sendable, Equatable {
    public let id: String
    public let name: String
    public let currentValue: String?
    public let choices: [ACPChoice]

    public init(id: String, name: String, currentValue: String?, choices: [ACPChoice]) {
        self.id = id
        self.name = name
        self.currentValue = currentValue
        self.choices = choices
    }

    static func parseAll(_ value: JSONValue?) -> [ACPConfigOption] {
        (value?.arrayValue ?? []).compactMap { option in
            guard let id = option["id"]?.stringValue else { return nil }
            return ACPConfigOption(id: id, name: option["name"]?.stringValue ?? id,
                                   currentValue: option["currentValue"]?.stringValue,
                                   choices: flatten(option["options"]))
        }
    }

    /// Options can be a flat list or groups with their own "options".
    private static func flatten(_ value: JSONValue?) -> [ACPChoice] {
        (value?.arrayValue ?? []).flatMap { item -> [ACPChoice] in
            if let value = item["value"]?.stringValue {
                return [ACPChoice(value: value, name: item["name"]?.stringValue ?? value)]
            }
            return flatten(item["options"])
        }
    }
}

public struct ACPSession: Sendable, Equatable {
    public let id: String
    public let configOptions: [ACPConfigOption]

    public func option(_ id: String) -> ACPConfigOption? { configOptions.first { $0.id == id } }
}

public enum ACPEvent: Sendable, Equatable {
    case text(String)
    case thought(String)
    case tool(id: String, title: String?, status: String?)
    case done(stopReason: String)
}

/// An Agent Client Protocol client. It refuses every permission request and every file or terminal request.
public actor ACPClient {
    private let transport: LineTransport
    private let router = SessionRouter()
    private var connection: JSONRPCConnection?

    public init(transport: LineTransport) {
        self.transport = transport
    }

    @discardableResult
    public func start() async throws -> JSONValue {
        let router = self.router
        let connection = JSONRPCConnection(
            transport: transport,
            onNotification: { method, params in
                guard method == "session/update", let sessionID = params["sessionId"]?.stringValue,
                      let event = ACPClient.event(from: params["update"]) else { return }
                router.yield(event, to: sessionID)
            },
            onRequest: { method, params in ACPClient.requestReply(method, params) })
        await connection.start()
        self.connection = connection
        return try await connection.request("initialize", .object([
            "protocolVersion": .number(1),
            "clientCapabilities": .object([
                "fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]),
                "terminal": .bool(false),
            ]),
            "clientInfo": .object(["name": .string("Scholia"), "version": .string("0.1")]),
        ]))
    }

    public func newSession(cwd: URL, meta: JSONValue?) async throws -> ACPSession {
        var params: [String: JSONValue] = ["cwd": .string(cwd.path), "mcpServers": .array([])]
        if let meta { params["_meta"] = meta }
        let result = try await requireConnection().request("session/new", .object(params))
        guard let id = result["sessionId"]?.stringValue else {
            throw JSONRPCError(code: -32603, message: "The agent did not start a session.")
        }
        return ACPSession(id: id, configOptions: ACPConfigOption.parseAll(result["configOptions"]))
    }

    public func setConfigOption(sessionID: String, configID: String, value: String) async throws -> [ACPConfigOption] {
        let result = try await requireConnection().request("session/set_config_option", .object([
            "sessionId": .string(sessionID), "configId": .string(configID), "value": .string(value),
        ]))
        return ACPConfigOption.parseAll(result["configOptions"])
    }

    /// Sends a prompt. The stream gives the agent's text and tool activity, then `.done`, or it throws the agent error.
    public func prompt(sessionID: String, text: String) -> AsyncThrowingStream<ACPEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ACPEvent.self)
        router.register(continuation, for: sessionID)
        let router = self.router
        Task {
            do {
                let connection = try self.requireConnection()
                let result = try await connection.request("session/prompt", .object([
                    "sessionId": .string(sessionID),
                    "prompt": .array([.object(["type": .string("text"), "text": .string(text)])]),
                ]))
                router.finish(sessionID, last: .done(stopReason: result["stopReason"]?.stringValue ?? "end_turn"))
            } catch {
                router.fail(sessionID, error)
            }
        }
        return stream
    }

    public func cancel(sessionID: String) async {
        try? await connection?.notify("session/cancel", .object(["sessionId": .string(sessionID)]))
    }

    public func close() async {
        await connection?.close()
    }

    private func requireConnection() throws -> JSONRPCConnection {
        guard let connection else { throw JSONRPCError(code: -1, message: "The agent is not started.") }
        return connection
    }

    static func event(from update: JSONValue?) -> ACPEvent? {
        guard let update, let kind = update["sessionUpdate"]?.stringValue else { return nil }
        switch kind {
        case "agent_message_chunk":
            return update["content"]?["text"]?.stringValue.map(ACPEvent.text)
        case "agent_thought_chunk":
            return update["content"]?["text"]?.stringValue.map(ACPEvent.thought)
        case "tool_call", "tool_call_update":
            guard let id = update["toolCallId"]?.stringValue else { return nil }
            let title = update["title"]?.stringValue
            let status = update["status"]?.stringValue
            if kind == "tool_call_update" && title == nil && status == nil { return nil }
            return .tool(id: id, title: title, status: status)
        default:
            return nil
        }
    }

    /// The reply to a request from the agent. Reader never allows a tool through a permission request,
    /// and it does not give the agent file or terminal access.
    static func requestReply(_ method: String, _ params: JSONValue) -> JSONRPCReply {
        method == "session/request_permission"
            ? permissionReply(params)
            : .error(code: -32601, message: "Scholia does not support \(method).")
    }

    static func permissionReply(_ params: JSONValue) -> JSONRPCReply {
        let options = params["options"]?.arrayValue ?? []
        let reject = options.first { $0["kind"]?.stringValue == "reject_once" }
            ?? options.first { $0["kind"]?.stringValue?.hasPrefix("reject") == true }
        if let optionID = reject?["optionId"]?.stringValue {
            return .result(.object(["outcome": .object(["outcome": .string("selected"), "optionId": .string(optionID)])]))
        }
        return .result(.object(["outcome": .object(["outcome": .string("cancelled")])]))
    }
}

/// Sends session updates to the stream of the prompt that is running in that session.
final class SessionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [String: AsyncThrowingStream<ACPEvent, Error>.Continuation] = [:]

    func register(_ continuation: AsyncThrowingStream<ACPEvent, Error>.Continuation, for sessionID: String) {
        let old = lock.withLock { () -> AsyncThrowingStream<ACPEvent, Error>.Continuation? in
            defer { streams[sessionID] = continuation }
            return streams[sessionID]
        }
        old?.finish()
    }

    func yield(_ event: ACPEvent, to sessionID: String) {
        _ = lock.withLock { streams[sessionID] }?.yield(event)
    }

    func finish(_ sessionID: String, last: ACPEvent) {
        let continuation = lock.withLock { streams.removeValue(forKey: sessionID) }
        continuation?.yield(last)
        continuation?.finish()
    }

    func fail(_ sessionID: String, _ error: Error) {
        lock.withLock { streams.removeValue(forKey: sessionID) }?.finish(throwing: error)
    }
}
