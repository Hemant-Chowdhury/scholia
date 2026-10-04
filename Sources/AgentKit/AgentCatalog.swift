import Foundation

/// A well-known agent program and how Reader starts it.
public struct AgentSpec: Sendable, Equatable, Identifiable {
    public struct Setting: Sendable, Equatable {
        public let configID: String
        public let value: String
    }

    public let id: String
    public let name: String
    /// All of these must be installed. The first word of `command` must be one of them.
    public let requiredBinaries: [String]
    /// The command that starts the ACP server on stdio.
    public let command: [String]
    public let isSupported: Bool
    public let installHint: String
    public let loginHint: String
    /// `_meta` for `session/new`.
    public let sessionMeta: JSONValue?
    /// Settings that Reader applies to each new session (for example, a read-only mode).
    public let sessionSettings: [Setting]
    public let note: String?
    /// Models to show before the first session reports its own list.
    public var knownModels: [ACPChoice] = []
    /// The model that Reader uses until the reader chooses one.
    public var defaultModel: String?
}

public enum AgentCatalog {
    /// Claude Code through the ACP adapter (pinned version: its `_meta` options carry the safety settings).
    /// The session gets only read and search tools and no MCP servers. The user's own settings are not loaded
    /// (they can allow tools with no request), so a read outside the workspace needs a permission request,
    /// which Reader refuses. WebFetch is not given: a malicious PDF could tell the agent to send data out.
    public static let claude = AgentSpec(
        id: "claude", name: "Claude Code", requiredBinaries: ["claude", "npx"],
        command: ["npx", "-y", "@agentclientprotocol/claude-agent-acp@0.85.1"], isSupported: true,
        installHint: "Install Claude Code from https://claude.com/claude-code and Node.js (for npx).",
        loginHint: "Run `claude` in Terminal and log in.",
        sessionMeta: .object(["claudeCode": .object(["options": .object([
            "tools": .array(["Read", "Glob", "Grep", "WebSearch"].map(JSONValue.string)),
            "strictMcpConfig": .bool(true),
            "settingSources": .array([]),
            "permissionMode": .string("default"),
            // Web search runs with no request (Find resources needs it); everything else still asks.
            "allowedTools": .array([.string("WebSearch")]),
            "disallowedTools": .array(["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "Agent", "Task", "WebFetch"]
                .map(JSONValue.string)),
        ])])]),
        sessionSettings: [], note: nil,
        knownModels: [ACPChoice(value: "opus", name: "Opus"), ACPChoice(value: "sonnet", name: "Sonnet"),
                      ACPChoice(value: "haiku", name: "Haiku")],
        defaultModel: "sonnet")

    /// OpenCode. Its read-only "plan" mode is used; a changed tool set makes its free tier refuse requests.
    public static let opencode = AgentSpec(
        id: "opencode", name: "OpenCode", requiredBinaries: ["opencode"], command: ["opencode", "acp"], isSupported: true,
        installHint: "Install OpenCode from https://opencode.ai.",
        loginHint: "Run `opencode auth login` in Terminal to use your own model providers.",
        sessionMeta: nil, sessionSettings: [AgentSpec.Setting(configID: "mode", value: "plan")],
        note: "Without a login, OpenCode has only free models, which are sometimes not available.")

    public static let gemini = unsupported("gemini", "Gemini CLI", ["gemini"], "Install the Gemini CLI from https://github.com/google-gemini/gemini-cli.")
    public static let codex = unsupported("codex", "Codex", ["codex"], "Install Codex from https://github.com/openai/codex.")
    public static let cursor = unsupported("cursor", "Cursor", ["cursor-agent"], "Install the Cursor CLI from https://cursor.com/cli.")

    public static let all = [claude, opencode, gemini, codex, cursor]

    private static func unsupported(_ id: String, _ name: String, _ binaries: [String], _ hint: String) -> AgentSpec {
        AgentSpec(id: id, name: name, requiredBinaries: binaries, command: binaries, isSupported: false,
                  installHint: hint, loginHint: "", sessionMeta: nil, sessionSettings: [],
                  note: "Scholia finds this agent, but it does not support it yet.")
    }
}

public enum AgentStatus: Sendable, Equatable {
    case ready
    case notInstalled(missing: [String])
    case notSupportedYet
}

public struct AgentAvailability: Sendable, Equatable, Identifiable {
    public var id: String { spec.id }
    public let spec: AgentSpec
    public let status: AgentStatus
    /// The program to start (the first word of the command), when it is installed.
    public let executable: URL?

    public init(spec: AgentSpec, status: AgentStatus, executable: URL?) {
        self.spec = spec
        self.status = status
        self.executable = executable
    }
}

public enum AgentError: Error, Equatable, LocalizedError {
    case notInstalled(name: String, missing: [String])
    case notSupported(name: String)
    case unsafeSession(name: String)
    case timedOut(name: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let name, let missing):
            "\(name) is not installed. Scholia cannot find: \(missing.joined(separator: ", "))."
        case .notSupported(let name):
            "Scholia does not support \(name) yet."
        case .unsafeSession(let name):
            "\(name) did not accept Scholia's read-only settings, so Scholia did not use it."
        case .timedOut(let name):
            "\(name) did not start in time. Check that it works in Terminal, then try again."
        }
    }
}

/// Finds agent programs. A Mac app that starts from Finder does not get the shell PATH, so the PATH comes
/// from the user's login shell, plus common install folders.
public struct AgentLocator: Sendable {
    public let searchPath: [URL]

    public init(searchPath: [URL]) {
        self.searchPath = searchPath
    }

    public static func standard() -> AgentLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home.path)/.local/bin", "\(home.path)/.opencode/bin",
                     "\(home.path)/.npm-global/bin", "\(home.path)/.bun/bin"].map { URL(fileURLWithPath: $0) }
        var seen = Set<String>()
        let all = (loginShellPath() + extra).filter { seen.insert($0.path).inserted }
        return AgentLocator(searchPath: all)
    }

    /// The PATH of the user's login shell, or the system folders when the shell gives nothing.
    public static func loginShellPath() -> [URL] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var text = ""
        if (try? process.run()) != nil {
            text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
        }
        let system = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let parts = text.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return (parts + system.filter { !parts.contains($0) }).map { URL(fileURLWithPath: $0) }
    }

    public var pathVariable: String { searchPath.map(\.path).joined(separator: ":") }

    public func find(_ binary: String) -> URL? {
        searchPath.lazy.map { $0.appendingPathComponent(binary) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func availability(of spec: AgentSpec) -> AgentAvailability {
        let missing = spec.requiredBinaries.filter { find($0) == nil }
        guard missing.isEmpty else { return AgentAvailability(spec: spec, status: .notInstalled(missing: missing), executable: nil) }
        guard spec.isSupported else { return AgentAvailability(spec: spec, status: .notSupportedYet, executable: nil) }
        return AgentAvailability(spec: spec, status: .ready, executable: spec.command.first.flatMap(find))
    }
}
