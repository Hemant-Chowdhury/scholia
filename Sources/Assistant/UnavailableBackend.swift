import AgentKit
import Foundation

/// A backend with no agents (for windows and tests that do not use the assistant).
public struct UnavailableBackend: AgentBackend {
    public init() {}

    public func availability() async -> [AgentAvailability] { [] }

    public func openSession(agent: AgentSpec, cwd: URL) async throws -> AgentSessionHandle {
        throw AgentError.notSupported(name: agent.name)
    }
}
