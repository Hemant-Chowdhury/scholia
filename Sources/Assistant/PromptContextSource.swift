import DocumentKit
import Foundation
import WorkspaceStore

/// Finds related passages and earlier threads for a prompt. It runs off the main thread (full-text search).
struct PromptContextSource: Sendable {
    let database: WorkspaceDatabase
    let document: DocumentRecord
    let aboutMe: String
    let excludedThread: String

    func input(_ selection: SelectionContext, _ action: ReadingAction, _ question: String?) -> PromptInput {
        let nearPages = (selection.pageIndex - 1)...(selection.pageIndex + 1)
        let passages = ((try? database.searchText(selection.text, limit: 12)) ?? [])
            .filter { !nearPages.contains($0.pageIndex) && $0.text.count > 40 }
            .prefix(ContextBuilder.maxPassages)
            .map { RelatedPassage(page: $0.pageIndex, text: $0.text) }
        let threads = ((try? database.relatedThreads(to: selection.text + " " + (question ?? ""),
                                                     documentID: document.id, excluding: excludedThread)) ?? [])
            .compactMap { thread -> RelatedThread? in
                let messages = (try? database.messages(threadID: thread.id)) ?? []
                guard let question = messages.first(where: { $0.role == "user" }),
                      let answer = messages.first(where: { $0.role == "assistant" && !$0.content.isEmpty }) else { return nil }
                let asked = question.action == ReadingAction.ask.rawValue || question.action == ReadingAction.followup.rawValue
                    ? question.content : "\(question.content): \(thread.title)"
                return RelatedThread(question: asked, answerStart: answer.content, page: thread.firstPage)
            }
        return PromptInput(book: BookInfo(title: document.title, author: document.author), aboutMe: aboutMe,
                           selection: selection, action: action, question: question,
                           relatedThreads: threads, relatedPassages: Array(passages))
    }
}
