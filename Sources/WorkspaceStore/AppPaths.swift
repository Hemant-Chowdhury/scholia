import Foundation

/// File locations of the app. Tests pass a temporary root.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The app folder in Application Support. The data of the app's old name ("Reader") moves there one time.
    public static func standard(base: URL? = nil) throws -> AppPaths {
        let base = try base ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent("Scholia", isDirectory: true)
        let legacy = base.appendingPathComponent("Reader", isDirectory: true)
        let files = FileManager.default
        if !files.fileExists(atPath: root.path), files.fileExists(atPath: legacy.path) {
            try files.moveItem(at: legacy, to: root)
        }
        return AppPaths(root: root)
    }

    public var globalIndexFile: URL { root.appendingPathComponent("index.sqlite") }

    public func workspaceFolder(id: String) -> URL {
        root.appendingPathComponent("workspaces", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
}
