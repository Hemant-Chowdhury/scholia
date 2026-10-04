import Assistant
import SwiftUI
import WorkspaceStore

/// The Study window: all questions of the book on the left, the selected conversation large on the right.
public struct StudyView: View {
    @Bindable var study: StudyModel
    @Environment(\.openWindow) private var openWindow
    @State private var draft = ""

    public init(study: StudyModel) {
        self.study = study
    }

    private var reader: ReaderModel { study.reader }
    private var assistant: AssistantModel { reader.assistant }

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { study.selectedID }, set: { if let id = $0 { study.select(id) } })) {
                if study.count == 0 {
                    Text("No questions yet. In the book window, select text and press E (Explain), S, D, A or R.")
                        .foregroundStyle(.secondary)
                }
                ForEach(study.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { StudyRow(summary: $0).tag($0.id) }
                    }
                }
            }
            .searchable(text: $study.query, placement: .sidebar, prompt: "Search questions and answers")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            if let thread = assistant.currentThread, thread.id == study.selectedID {
                detail(thread)
            } else {
                ContentUnavailableView("Select a question", systemImage: "text.book.closed",
                                       description: Text("Your questions and answers about this book are on the left."))
            }
        }
        .navigationTitle("Study: \(reader.workspace.document.title)")
        .onChange(of: assistant.allThreads.map(\.updatedAt)) { study.reload() }
        .onChange(of: assistant.currentThread?.id) { study.follow(assistant.currentThread?.id) }
    }

    private func detail(_ thread: ThreadRecord) -> some View {
        VStack(spacing: 0) {
            ThreadView(reader: reader, thread: thread)
                .font(.system(size: 15))
                .lineSpacing(3)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            Divider()
            HStack(spacing: 8) {
                TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(send)
                    .disabled(assistant.isRunning)
                if assistant.isRunning {
                    Button("Stop") { assistant.stop() }
                } else {
                    Button("Send", action: send).keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxWidth: 780)
            .padding(12)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: "reader", value: reader.pdfURL)
                    reader.open(thread)
                } label: { Label("Show in PDF", systemImage: "doc.text.magnifyingglass") }
                    .help("Show this text in the book window")
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        assistant.followUp(text)
        draft = ""
    }
}

struct StudyRow: View {
    let summary: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.thread.title).font(.body.weight(.medium)).lineLimit(2)
            HStack(spacing: 4) {
                Text(summary.question).foregroundStyle(.tint)
                Text("· Page \(summary.thread.firstPage + 1)")
                if summary.messageCount > 2 { Text("· \(summary.messageCount / 2) answers") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !summary.answerStart.isEmpty {
                Text(summary.answerStart.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}
