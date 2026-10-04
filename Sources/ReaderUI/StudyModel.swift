import Assistant
import Foundation
import Observation
import WorkspaceStore

/// The Study window of one book: all threads by chapter, a search, and the selected thread (shown through the
/// reader's assistant, so the book window and the Study window show the same conversation).
@MainActor
@Observable
public final class StudyModel {
    public struct Section: Identifiable {
        public let title: String
        public let items: [ThreadSummary]
        public var id: String { title }
    }

    public let reader: ReaderModel
    public var query = ""
    public private(set) var selectedID: String?
    private var summaries: [ThreadSummary] = []

    public init(reader: ReaderModel) {
        self.reader = reader
        reload()
    }

    public func reload() {
        summaries = (try? reader.workspace.database.threadSummaries(documentID: reader.workspace.document.id)) ?? []
    }

    /// Threads that match the search (title, questions and answers), grouped by chapter in page order.
    public var sections: [Section] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var visible = summaries
        if !text.isEmpty {
            let found = Set((try? reader.workspace.database.searchThreads(text, documentID: reader.workspace.document.id)) ?? [])
            visible = summaries.filter {
                found.contains($0.id) || $0.thread.title.localizedCaseInsensitiveContains(text)
                    || $0.question.localizedCaseInsensitiveContains(text)
            }
        }
        var order: [String] = []
        var groups: [String: [ThreadSummary]] = [:]
        for summary in visible {
            let chapter = summary.structuralPath.components(separatedBy: " › ").first.flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
            if groups[chapter] == nil { order.append(chapter) }
            groups[chapter, default: []].append(summary)
        }
        return order.map { Section(title: $0, items: groups[$0] ?? []) }
    }

    public var count: Int { summaries.count }

    /// The thread that the assistant shows (it can change in the book window).
    public func follow(_ threadID: String?) {
        selectedID = threadID
    }

    /// Opens a thread. While an answer is running, the assistant keeps its thread, and so does the selection.
    public func select(_ threadID: String) {
        guard let summary = summaries.first(where: { $0.id == threadID }) else { return }
        reader.assistant.open(thread: summary.thread)
        selectedID = reader.assistant.currentThread?.id
    }
}
