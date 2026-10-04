import Foundation
import Testing
@testable import AgentKit

struct JSONValueTests {
    @Test func decodesAndEncodesAllKinds() throws {
        let text = #"{"a":1,"b":"x","c":[true,null,2.5],"d":{"e":false}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value["a"]?.intValue == 1)
        #expect(value["b"]?.stringValue == "x")
        #expect(value["c"]?.arrayValue?.count == 3)
        #expect(value["c"]?.arrayValue?[0] == .bool(true))
        #expect(value["d"]?["e"] == .bool(false))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test func wholeNumbersAreWrittenWithoutFraction() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["id": .number(7)]))
        #expect(String(decoding: data, as: UTF8.self) == #"{"id":7}"#)
    }
}

struct JSONRPCConnectionTests {
    final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var notifications: [(String, JSONValue)] = []
        func add(_ method: String, _ params: JSONValue) { lock.withLock { notifications.append((method, params)) } }
        var methods: [String] { lock.withLock { notifications.map(\.0) } }
    }

    func makeConnection(_ transport: FakeTransport, recorder: Recorder = Recorder(),
                        requests: @escaping @Sendable (String, JSONValue) -> JSONRPCReply = { _, _ in .error(code: -32601, message: "no") })
        async -> JSONRPCConnection {
        let connection = JSONRPCConnection(transport: transport, onNotification: { recorder.add($0, $1) }, onRequest: requests)
        await connection.start()
        return connection
    }

    @Test func requestGetsTheResultWithTheSameID() async throws {
        let transport = FakeTransport()
        let connection = await makeConnection(transport)
        let result = Task { try await connection.request("initialize", .object(["protocolVersion": .number(1)])) }
        await transport.waitForSent(1)
        let sent = try #require(transport.sentJSON(0))
        #expect(sent["method"]?.stringValue == "initialize")
        #expect(sent["jsonrpc"]?.stringValue == "2.0")
        let id = try #require(sent["id"]?.intValue)
        transport.push(#"{"jsonrpc":"2.0","id":\#(id),"result":{"ok":true}}"#)
        #expect(try await result.value["ok"] == .bool(true))
    }

    @Test func errorResponseThrowsWithTheAgentMessage() async throws {
        let transport = FakeTransport()
        let connection = await makeConnection(transport)
        let result = Task { try await connection.request("session/prompt", .object([:])) }
        await transport.waitForSent(1)
        let id = try #require(transport.sentJSON(0)?["id"]?.intValue)
        transport.push(#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32603,"message":"Endpoint is unavailable."}}"#)
        await #expect(throws: JSONRPCError(code: -32603, message: "Endpoint is unavailable.")) { try await result.value }
    }

    @Test func notificationsGoToTheHandler() async throws {
        let transport = FakeTransport()
        let recorder = Recorder()
        _ = await makeConnection(transport, recorder: recorder)
        transport.push(#"{"jsonrpc":"2.0","method":"session/update","params":{"x":1}}"#)
        for _ in 0..<100 where recorder.methods.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.methods == ["session/update"])
    }

    @Test func noiseBeforeTheJSONOnALineIsIgnored() async throws {
        let transport = FakeTransport()
        let recorder = Recorder()
        _ = await makeConnection(transport, recorder: recorder)
        transport.push("\u{1b}]777;notify;warp://cli-agent;{\"v\":1}\u{07}" + #"{"jsonrpc":"2.0","method":"session/update","params":{}}"#)
        transport.push("plain text that is not JSON")
        for _ in 0..<100 where recorder.methods.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.methods == ["session/update"])
    }

    @Test func agentRequestsGetTheHandlerReply() async throws {
        let transport = FakeTransport()
        _ = await makeConnection(transport) { method, _ in
            method == "session/request_permission" ? .result(.object(["picked": .string("reject")])) : .error(code: -32601, message: "no")
        }
        transport.push(#"{"jsonrpc":"2.0","id":"abc","method":"session/request_permission","params":{}}"#)
        transport.push(#"{"jsonrpc":"2.0","id":5,"method":"fs/write_text_file","params":{}}"#)
        await transport.waitForSent(2)
        let first = try #require(transport.sentJSON(0))
        #expect(first["id"]?.stringValue == "abc")
        #expect(first["result"]?["picked"]?.stringValue == "reject")
        let second = try #require(transport.sentJSON(1))
        #expect(second["id"]?.intValue == 5)
        #expect(second["error"]?["code"]?.intValue == -32601)
    }

    @Test func pendingRequestsFailWhenTheAgentStops() async throws {
        let transport = FakeTransport()
        let connection = await makeConnection(transport)
        let result = Task { try await connection.request("session/prompt", .object([:])) }
        await transport.waitForSent(1)
        transport.finish()
        await #expect(throws: JSONRPCError.self) { try await result.value }
        await #expect(throws: JSONRPCError.self) { try await connection.request("again", .null) }
    }
}
