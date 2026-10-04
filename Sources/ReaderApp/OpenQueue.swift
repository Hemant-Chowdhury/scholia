import Foundation
import Observation

/// PDFs that wait to open in a reader window. Finder ("Open With"), the command line and the Open
/// command add files; the first visible window takes them and opens one reader window for each.
@MainActor
@Observable
final class OpenQueue {
    static let shared = OpenQueue()

    private(set) var pending: [URL] = []

    func add(_ urls: [URL]) {
        pending += urls.filter { $0.pathExtension.lowercased() == "pdf" }
    }

    func takeAll() -> [URL] {
        defer { pending = [] }
        return pending
    }
}
