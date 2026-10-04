import Foundation
import Testing
@testable import AgentKit

struct AgentCatalogTests {
    func folder(with binaries: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in binaries {
            let file = folder.appendingPathComponent(name)
            try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return folder
    }

    @Test func installedAgentIsReadyAndMissingOneNamesItsBinaries() throws {
        let locator = AgentLocator(searchPath: [try folder(with: ["opencode"])])
        #expect(locator.availability(of: AgentCatalog.opencode).status == .ready)
        #expect(locator.availability(of: AgentCatalog.claude).status == .notInstalled(missing: ["claude", "npx"]))
    }

    @Test func claudeNeedsBothClaudeAndNpx() throws {
        let locator = AgentLocator(searchPath: [try folder(with: ["claude", "npx"])])
        let availability = locator.availability(of: AgentCatalog.claude)
        #expect(availability.status == .ready)
        #expect(availability.executable?.lastPathComponent == "npx")
    }

    @Test func installedButUnsupportedAgentSaysSo() throws {
        let locator = AgentLocator(searchPath: [try folder(with: ["gemini"])])
        #expect(locator.availability(of: AgentCatalog.gemini).status == .notSupportedYet)
        #expect(AgentLocator(searchPath: []).availability(of: AgentCatalog.gemini).status == .notInstalled(missing: ["gemini"]))
    }

    @Test func fileThatIsNotExecutableIsNotFound() throws {
        let dir = try folder(with: [])
        try "x".write(to: dir.appendingPathComponent("opencode"), atomically: true, encoding: .utf8)
        #expect(AgentLocator(searchPath: [dir]).find("opencode") == nil)
    }

    @Test func loginShellPathHasTheSystemFolders() {
        let path = AgentLocator.loginShellPath()
        #expect(path.contains(URL(fileURLWithPath: "/usr/bin")))
    }

    @Test func catalogListsTheWellKnownAgents() {
        #expect(AgentCatalog.all.map(\.id) == ["claude", "opencode", "gemini", "codex", "cursor"])
        #expect(AgentCatalog.all.filter(\.isSupported).map(\.id) == ["claude", "opencode"])
    }

    @Test func claudeSessionsOnlyGetReadAndWebTools() throws {
        let options = try #require(AgentCatalog.claude.sessionMeta?["claudeCode"]?["options"])
        #expect(options["tools"] == .array(["Read", "Glob", "Grep", "WebSearch", "WebFetch"].map(JSONValue.string)))
        #expect(options["strictMcpConfig"] == .bool(true))
        #expect(AgentCatalog.opencode.sessionSettings == [AgentSpec.Setting(configID: "mode", value: "plan")])
    }
}

struct AgentHostTests {
    final class Factory: @unchecked Sendable {
        let lock = NSLock()
        var transports: [FakeTransport] = []
        func make() -> FakeTransport {
            let transport = FakeTransport()
            scriptedAgent(transport)
            lock.withLock { transports.append(transport) }
            return transport
        }
        var count: Int { lock.withLock { transports.count } }
    }

    func host(_ factory: Factory, binaries: [String]) throws -> AgentHost {
        let locator = AgentLocator(searchPath: [try AgentCatalogTests().folder(with: binaries)])
        return AgentHost(locator: locator) { _, _ in factory.make() }
    }

    @Test func sessionsShareOneProcessAndApplyTheSafetySettings() async throws {
        let factory = Factory()
        let host = try host(factory, binaries: ["opencode"])
        let cwd = URL(fileURLWithPath: "/tmp/ws")
        _ = try await host.openSession(agent: AgentCatalog.opencode, cwd: cwd)
        _ = try await host.openSession(agent: AgentCatalog.opencode, cwd: cwd)
        #expect(factory.count == 1)
        let methods = factory.transports[0].sent.compactMap(JSONRPCConnection.parseLine).compactMap { $0["method"]?.stringValue }
        #expect(methods == ["initialize", "session/new", "session/set_config_option", "session/new", "session/set_config_option"])
        let setting = try #require(factory.transports[0].sent.compactMap(JSONRPCConnection.parseLine)
            .first { $0["method"]?.stringValue == "session/set_config_option" })
        #expect(setting["params"]?["configId"]?.stringValue == "mode")
        #expect(setting["params"]?["value"]?.stringValue == "plan")
    }

    @Test func agentThatIsNotInstalledThrowsAClearError() async throws {
        let host = try host(Factory(), binaries: [])
        await #expect(throws: AgentError.notInstalled(name: "Claude Code", missing: ["claude", "npx"])) {
            _ = try await host.openSession(agent: AgentCatalog.claude, cwd: URL(fileURLWithPath: "/tmp"))
        }
        #expect(AgentError.notInstalled(name: "Claude Code", missing: ["claude", "npx"]).errorDescription
            == "Claude Code is not installed. Reader cannot find: claude, npx.")
    }

    @Test func agentThatStoppedIsStartedAgain() async throws {
        let factory = Factory()
        let host = try host(factory, binaries: ["opencode"])
        let cwd = URL(fileURLWithPath: "/tmp/ws")
        _ = try await host.openSession(agent: AgentCatalog.opencode, cwd: cwd)
        factory.transports[0].finish()
        try await Task.sleep(for: .milliseconds(50))
        _ = try await host.openSession(agent: AgentCatalog.opencode, cwd: cwd)
        #expect(factory.count == 2)
    }
}
