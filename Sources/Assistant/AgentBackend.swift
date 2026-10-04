import AgentKit
import Foundation

/// The agent functions that the assistant uses. `AgentHost` is the real one; tests use a fake.
public protocol AgentBackend: Sendable {
    func availability() async -> [AgentAvailability]
    func openSession(agent: AgentSpec, cwd: URL) async throws -> AgentSessionHandle
}

public protocol AgentSessionHandle: Sendable {
    var configOptions: [ACPConfigOption] { get }
    func setOption(_ configID: String, _ value: String) async throws -> [ACPConfigOption]
    func prompt(_ text: String) async -> AsyncThrowingStream<ACPEvent, Error>
    func cancel() async
}

extension AgentHost: AgentBackend {
    public func openSession(agent: AgentSpec, cwd: URL) async throws -> AgentSessionHandle {
        let opened: AgentSession = try await openSession(agent: agent, cwd: cwd)
        return HostSessionHandle(client: opened.client, sessionID: opened.session.id, configOptions: opened.session.configOptions)
    }
}

struct HostSessionHandle: AgentSessionHandle {
    let client: ACPClient
    let sessionID: String
    let configOptions: [ACPConfigOption]

    func setOption(_ configID: String, _ value: String) async throws -> [ACPConfigOption] {
        try await client.setConfigOption(sessionID: sessionID, configID: configID, value: value)
    }

    func prompt(_ text: String) async -> AsyncThrowingStream<ACPEvent, Error> {
        await client.prompt(sessionID: sessionID, text: text)
    }

    func cancel() async {
        await client.cancel(sessionID: sessionID)
    }
}
