import Foundation

/// File locations of the app. Tests pass a temporary root.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: base.appendingPathComponent("Reader", isDirectory: true))
    }

    public var globalIndexFile: URL { root.appendingPathComponent("index.sqlite") }

    public func workspaceFolder(id: String) -> URL {
        root.appendingPathComponent("workspaces", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
}
