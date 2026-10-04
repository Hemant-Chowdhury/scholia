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
    /// The open book windows, by workspace ID (for the Study window).
    @ObservationIgnored private var readers: [String: WeakReader] = [:]

    private struct WeakReader { weak var model: ReaderModel? }

    /// Changes when a book window opens or closes (the Study window watches it).
    public private(set) var readerVersion = 0

    /// A book window closed: its reader is no longer the reader of the workspace (if a newer one did not replace it).
    public func readerClosed(_ model: ReaderModel) {
        guard readers[model.workspace.id]?.model === model else { return }
        readers[model.workspace.id] = nil
        readerVersion += 1
    }

    public func reader(forWorkspace id: String) -> ReaderModel? {
        readers[id]?.model
    }

    /// The last known file of a workspace (to open the book from a Study window).
    public func documentURL(forWorkspace id: String) -> URL? {
        recents.first { $0.workspaceID == id }.map { URL(fileURLWithPath: $0.lastPath) }
    }

    public init(paths: AppPaths? = nil) {
        var manager: WorkspaceManager?
        var startupError: String?
        do {
            manager = try WorkspaceManager(paths: paths ?? AppPaths.standard())
        } catch {
            startupError = "Scholia cannot open its data folder: \(error.localizedDescription)"
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
        let model = try ReaderModel(workspace: workspace, pdfURL: url, backend: await backend())
        readers[workspace.id] = WeakReader(model: model)
        readerVersion += 1
        return model
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
