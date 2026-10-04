import Foundation
import Testing
@testable import AgentKit

/// A scripted ACP agent: it answers initialize, session/new, set_config_option and session/prompt.
func scriptedAgent(_ transport: FakeTransport, promptUpdates: [String] = [], promptError: String? = nil) {
    transport.responder = { message in
        guard let method = message["method"]?.stringValue, let id = message["id"]?.intValue else { return [] }
        switch method {
        case "initialize":
            return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"protocolVersion":1,"agentInfo":{"name":"Fake"}}}"#]
        case "session/new":
            return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"sessionId":"s1","configOptions":[{"id":"model","name":"Model","currentValue":"opus","options":[{"value":"opus","name":"Opus"},{"value":"haiku","name":"Haiku"}]},{"id":"mode","name":"Mode","currentValue":"default","options":[{"value":"default","name":"Default"}]}]}}"#]
        case "session/set_config_option":
            // Like the real agents: the reply lists the options, with the new value of the changed one.
            let config = message["params"]?["configId"]?.stringValue ?? ""
            let value = message["params"]?["value"]?.stringValue ?? ""
            let model = config == "model" ? value : "opus"
            let mode = config == "mode" ? value : "default"
            return [#"{"jsonrpc":"2.0","id":\#(id),"result":{"configOptions":[{"id":"model","name":"Model","currentValue":"\#(model)","options":[{"value":"opus","name":"Opus"},{"value":"haiku","name":"Haiku"}]},{"id":"mode","name":"Mode","currentValue":"\#(mode)","options":[{"value":"default","name":"Default"},{"value":"plan","name":"Plan"}]}]}}"#]
        case "session/prompt":
            let updates = promptUpdates.map { #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":\#($0)}}"# }
            if let promptError {
                return updates + [#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32603,"message":"\#(promptError)"}}"#]
            }
            return updates + [#"{"jsonrpc":"2.0","id":\#(id),"result":{"stopReason":"end_turn"}}"#]
        default:
            return [#"{"jsonrpc":"2.0","id":\#(id),"result":null}"#]
        }
    }
}

struct ACPClientTests {
    func startedClient(_ transport: FakeTransport) async throws -> ACPClient {
        let client = ACPClient(transport: transport)
        try await client.start()
        return client
    }

    @Test func newSessionReadsTheModelOptions() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport)
        let client = try await startedClient(transport)
        let session = try await client.newSession(cwd: URL(fileURLWithPath: "/tmp/ws"), meta: nil)
        #expect(session.id == "s1")
        let model = try #require(session.option("model"))
        #expect(model.currentValue == "opus")
        #expect(model.choices == [ACPChoice(value: "opus", name: "Opus"), ACPChoice(value: "haiku", name: "Haiku")])
        let sentNew = try #require(transport.sent.compactMap(JSONRPCConnection.parseLine).first { $0["method"]?.stringValue == "session/new" })
        #expect(sentNew["params"]?["cwd"]?.stringValue == "/tmp/ws")
        #expect(sentNew["params"]?["mcpServers"] == .array([]))
    }

    @Test func newSessionSendsTheMeta() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport)
        let client = try await startedClient(transport)
        _ = try await client.newSession(cwd: URL(fileURLWithPath: "/tmp/ws"), meta: .object(["claudeCode": .object([:])]))
        let sentNew = try #require(transport.sent.compactMap(JSONRPCConnection.parseLine).first { $0["method"]?.stringValue == "session/new" })
        #expect(sentNew["params"]?["_meta"]?["claudeCode"] == .object([:]))
    }

    @Test func setConfigOptionReturnsTheNewValue() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport)
        let client = try await startedClient(transport)
        let options = try await client.setConfigOption(sessionID: "s1", configID: "model", value: "haiku")
        #expect(options.first { $0.id == "model" }?.currentValue == "haiku")
    }

    @Test func promptStreamsTextToolsAndDone() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport, promptUpdates: [
            #"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking"}}"#,
            #"{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Read chapter","status":"pending"}"#,
            #"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"An agent "}}"#,
            #"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed"}"#,
            #"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"is a loop."}}"#,
            #"{"sessionUpdate":"usage_update","used":10}"#,
        ])
        let client = try await startedClient(transport)
        var events: [ACPEvent] = []
        for try await event in await client.prompt(sessionID: "s1", text: "Explain") { events.append(event) }
        #expect(events == [
            .thought("thinking"),
            .tool(id: "t1", title: "Read chapter", status: "pending"),
            .text("An agent "),
            .tool(id: "t1", title: nil, status: "completed"),
            .text("is a loop."),
            .done(stopReason: "end_turn"),
        ])
        let prompt = try #require(transport.sent.compactMap(JSONRPCConnection.parseLine).first { $0["method"]?.stringValue == "session/prompt" })
        #expect(prompt["params"]?["prompt"] == .array([.object(["type": .string("text"), "text": .string("Explain")])]))
    }

    @Test func promptErrorEndsTheStreamWithTheAgentMessage() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport, promptUpdates: [#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"part"}}"#],
                      promptError: "Usage limit reached.")
        let client = try await startedClient(transport)
        var texts: [String] = []
        await #expect(throws: JSONRPCError(code: -32603, message: "Usage limit reached.")) {
            for try await event in await client.prompt(sessionID: "s1", text: "Explain") {
                if case .text(let text) = event { texts.append(text) }
            }
        }
        #expect(texts == ["part"])
    }

    @Test func permissionRequestsAreAlwaysRefused() async throws {
        let transport = FakeTransport()
        scriptedAgent(transport)
        _ = try await startedClient(transport)
        let count = transport.sent.count
        transport.push(#"{"jsonrpc":"2.0","id":99,"method":"session/request_permission","params":{"sessionId":"s1","toolCall":{"title":"rm -rf"},"options":[{"optionId":"a","name":"Allow","kind":"allow_once"},{"optionId":"r","name":"Reject","kind":"reject_once"}]}}"#)
        await transport.waitForSent(count + 1)
        let reply = try #require(transport.sentJSON(count))
        #expect(reply["id"]?.intValue == 99)
        #expect(reply["result"]?["outcome"]?["outcome"]?.stringValue == "selected")
        #expect(reply["result"]?["outcome"]?["optionId"]?.stringValue == "r")
    }

    @Test func permissionWithoutARejectOptionIsCancelled() {
        let reply = ACPClient.permissionReply(.object(["options": .array([.object(["optionId": .string("a"), "kind": .string("allow_once")])])]))
        guard case .result(let result) = reply else { Issue.record("expected a result"); return }
        #expect(result["outcome"]?["outcome"]?.stringValue == "cancelled")
    }

    @Test func fileAndTerminalRequestsAreRefused() {
        guard case .error(let code, _) = ACPClient.requestReply("fs/write_text_file", .null) else {
            Issue.record("expected an error"); return
        }
        #expect(code == -32601)
    }
}

struct ProcessTransportTests {
    @Test func linesGoToTheProcessAndComeBack() async throws {
        let transport = try ProcessTransport(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                                             environment: [:], currentDirectory: URL(fileURLWithPath: "/tmp"))
        try await transport.send(#"{"a":1}"#)
        try await transport.send(#"{"b":2}"#)
        var received: [String] = []
        for await line in transport.lines {
            received.append(line)
            if received.count == 2 { break }
        }
        #expect(received == [#"{"a":1}"#, #"{"b":2}"#])
        await transport.close()
    }

    @Test func processThatEndsFinishesTheLines() async throws {
        let transport = try ProcessTransport(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"],
                                             environment: [:], currentDirectory: URL(fileURLWithPath: "/tmp"))
        var received: [String] = []
        for await line in transport.lines { received.append(line) }
        #expect(received == ["hello"])
    }

    @Test func missingProgramThrows() {
        #expect(throws: (any Error).self) {
            try ProcessTransport(executable: URL(fileURLWithPath: "/nonexistent/agent"), arguments: [],
                                 environment: [:], currentDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }
}
