import AgentKit
import Assistant
import Foundation
import Observation
import WorkspaceStore

/// Opens workspaces for the windows and keeps the recent documents list.
@MainActor
@Observable
public final class Library {
    public private(set) var recents: [RecentDocument] = []
    public private(set) var startupError: String?
    @ObservationIgnored private let manager: WorkspaceManager?
    @ObservationIgnored private var openReaderWindows = 0
    /// One agent host for the app; the agent search PATH comes from the login shell (read one time, off the main thread).
    @ObservationIgnored private var agentHost: AgentHost?

    public init(paths: AppPaths? = nil) {
        var manager: WorkspaceManager?
        var startupError: String?
        do {
            manager = try WorkspaceManager(paths: paths ?? AppPaths.standard())
        } catch {
            startupError = "Reader cannot open its data folder: \(error.localizedDescription)"
        }
        self.manager = manager
        self.startupError = startupError
        refreshRecents()
    }

    public func readerWindowOpened() {
        openReaderWindows += 1
    }

    /// Returns true when the closed window was the last reader window, so the start window can come back.
    public func readerWindowClosed() -> Bool {
        guard openReaderWindows > 0 else { return false }
        openReaderWindows -= 1
        return openReaderWindows == 0
    }

    public func refreshRecents() {
        recents = (try? manager?.recents()) ?? []
    }

    public func openModel(for url: URL) async throws -> ReaderModel {
        guard let manager else { throw CocoaError(.fileReadUnknown) }
        let workspace = try await Task.detached(priority: .userInitiated) { try manager.open(pdfAt: url) }.value
        refreshRecents()
        return try ReaderModel(workspace: workspace, pdfURL: url, backend: await backend())
    }

    public func backend() async -> AgentBackend {
        if let agentHost { return agentHost }
        let locator = await Task.detached(priority: .userInitiated) { AgentLocator.standard() }.value
        if let agentHost { return agentHost }
        let host = AgentHost(locator: locator)
        agentHost = host
        return host
    }

    /// Stops the agent programs (when the app quits).
    public func shutdownAgents() async {
        await agentHost?.shutdown()
    }
}
