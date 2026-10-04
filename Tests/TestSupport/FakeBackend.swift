import AgentKit
import Foundation
import Assistant

/// A scripted agent backend. Each prompt gets the next script; a script is a list of events, or an error.
public final class FakeBackend: AgentBackend, @unchecked Sendable {
    public enum Step: Sendable { case events([ACPEvent]), fail(String), waitForCancel([ACPEvent]) }

    public let lock = NSLock()
    public var scripts: [Step] = []
    public var prompts: [String] = []
    public var sessionsOpened = 0
    public var optionsSet: [(String, String)] = []
    public var installed = true
    public var cancelled = false
    /// Seconds that openSession waits, like a slow first `npx` start.
    public var openDelay: Double = 0

    public init() {}

    public func availability() async -> [AgentAvailability] {
        [AgentAvailability(spec: AgentCatalog.claude, status: installed ? .ready : .notInstalled(missing: ["claude"]), executable: nil),
         AgentAvailability(spec: AgentCatalog.opencode, status: .ready, executable: nil)]
    }

    public func openSession(agent: AgentSpec, cwd: URL) async throws -> AgentSessionHandle {
        guard installed || agent.id != "claude" else { throw AgentError.notInstalled(name: agent.name, missing: ["claude"]) }
        if openDelay > 0 { try await Task.sleep(for: .seconds(openDelay)) }
        lock.withLock { sessionsOpened += 1 }
        return FakeSession(backend: self)
    }

    public func nextStep(for prompt: String) -> Step {
        lock.withLock {
            prompts.append(prompt)
            return scripts.isEmpty ? .events([.text("ok"), .done(stopReason: "end_turn")]) : scripts.removeFirst()
        }
    }
}

public struct FakeSession: AgentSessionHandle {
    let backend: FakeBackend

    public var configOptions: [ACPConfigOption] {
        [ACPConfigOption(id: "model", name: "Model", currentValue: "opus",
                         choices: [ACPChoice(value: "opus", name: "Opus"), ACPChoice(value: "haiku", name: "Haiku")])]
    }

    public func setOption(_ configID: String, _ value: String) async throws -> [ACPConfigOption] {
        backend.lock.withLock { backend.optionsSet.append((configID, value)) }
        return [ACPConfigOption(id: "model", name: "Model", currentValue: value, choices: configOptions[0].choices)]
    }

    public func prompt(_ text: String) async -> AsyncThrowingStream<ACPEvent, Error> {
        let step = backend.nextStep(for: text)
        let backend = self.backend
        return AsyncThrowingStream { continuation in
            Task {
                switch step {
                case .events(let events):
                    for event in events { continuation.yield(event); try? await Task.sleep(for: .milliseconds(5)) }
                    continuation.finish()
                case .fail(let message):
                    continuation.finish(throwing: JSONRPCError(code: -32603, message: message))
                case .waitForCancel(let events):
                    events.forEach { continuation.yield($0) }
                    while !backend.lock.withLock({ backend.cancelled }) { try? await Task.sleep(for: .milliseconds(5)) }
                    continuation.yield(.done(stopReason: "cancelled"))
                    continuation.finish()
                }
            }
        }
    }

    public func cancel() async {
        backend.lock.withLock { backend.cancelled = true }
    }
}
