import Foundation

/// One open agent session.
public struct AgentSession: Sendable {
    public let client: ACPClient
    public let session: ACPSession
}

/// Starts agent programs (one process for each agent, shared by its sessions) and opens sessions with
/// Reader's safety settings. A process that stopped is started again.
public actor AgentHost {
    public typealias TransportFactory = @Sendable (AgentSpec, AgentAvailability) throws -> LineTransport

    private let locator: AgentLocator
    private let makeTransport: TransportFactory
    private var clients: [String: ACPClient] = [:]

    public init(locator: AgentLocator, makeTransport: TransportFactory? = nil) {
        self.locator = locator
        let path = locator.pathVariable
        self.makeTransport = makeTransport ?? { spec, availability in
            guard let executable = availability.executable else {
                throw AgentError.notInstalled(name: spec.name, missing: spec.requiredBinaries)
            }
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = path
            environment.removeValue(forKey: "TERM_PROGRAM")
            return try ProcessTransport(executable: executable, arguments: Array(spec.command.dropFirst()),
                                        environment: environment,
                                        currentDirectory: FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    public func availability() -> [AgentAvailability] {
        AgentCatalog.all.map(locator.availability(of:))
    }

    public func openSession(agent: AgentSpec, cwd: URL) async throws -> AgentSession {
        do {
            return try await open(agent: agent, cwd: cwd)
        } catch let error as JSONRPCError where error == .stopped {
            clients[agent.id] = nil
            return try await open(agent: agent, cwd: cwd)
        }
    }

    public func shutdown() async {
        for client in clients.values { await client.close() }
        clients = [:]
    }

    private func open(agent: AgentSpec, cwd: URL) async throws -> AgentSession {
        let client = try await client(for: agent)
        let session = try await client.newSession(cwd: cwd, meta: agent.sessionMeta)
        var options = session.configOptions
        for setting in agent.sessionSettings {
            options = try await client.setConfigOption(sessionID: session.id, configID: setting.configID, value: setting.value)
        }
        let merged = session.configOptions.map { original in options.first { $0.id == original.id } ?? original }
        return AgentSession(client: client, session: ACPSession(id: session.id, configOptions: merged))
    }

    private func client(for agent: AgentSpec) async throws -> ACPClient {
        if let existing = clients[agent.id] { return existing }
        let availability = locator.availability(of: agent)
        switch availability.status {
        case .notInstalled(let missing): throw AgentError.notInstalled(name: agent.name, missing: missing)
        case .notSupportedYet: throw AgentError.notSupported(name: agent.name)
        case .ready: break
        }
        let client = ACPClient(transport: try makeTransport(agent, availability))
        try await client.start()
        clients[agent.id] = client
        return client
    }
}
