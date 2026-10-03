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

    public func refreshRecents() {
        recents = (try? manager?.recents()) ?? []
    }

    public func openModel(for url: URL) async throws -> ReaderModel {
        guard let manager else { throw CocoaError(.fileReadUnknown) }
        let workspace = try await Task.detached(priority: .userInitiated) { try manager.open(pdfAt: url) }.value
        refreshRecents()
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }
}
