import Foundation
import Testing
@testable import AgentKit

/// Real agents, run only on request: READER_LIVE_AGENT=claude (or opencode) swift test --filter LiveAgentTests
struct LiveAgentTests {
    static let agentID = ProcessInfo.processInfo.environment["READER_LIVE_AGENT"]

    @Test(.enabled(if: agentID != nil))
    func realAgentAnswersAPrompt() async throws {
        let spec = try #require(AgentCatalog.all.first { $0.id == Self.agentID })
        let host = AgentHost(locator: .standard())
        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let opened = try await host.openSession(agent: spec, cwd: cwd)
        if let model = opened.session.option("model")?.choices.first(where: { $0.value == "haiku" }) {
            _ = try await opened.client.setConfigOption(sessionID: opened.session.id, configID: "model", value: model.value)
        }
        var text = ""
        for try await event in await opened.client.prompt(sessionID: opened.session.id, text: "Reply with exactly: hello reader") {
            if case .text(let chunk) = event { text += chunk }
        }
        await host.shutdown()
        #expect(text.lowercased().contains("hello reader"))
    }
}
