import SwiftUI
import WorkspaceStore

/// The reader window: outline and search results on the left, the PDF on the right.
public struct ReaderView: View {
    let model: ReaderModel
    @State private var query = ""

    public init(model: ReaderModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            ReaderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            PDFKitView(model: model)
                .navigationTitle(model.workspace.document.title)
                .navigationSubtitle(model.structuralPath.joined(separator: " › "))
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search in document")
        .onSubmit(of: .search) { model.search(query) }
        .onChange(of: query) { if query.isEmpty { model.search("") } }
        .toolbar {
            ToolbarItem { IndexStatusView(progress: model.indexProgress, error: model.lastError) }
        }
        .task { model.startIndexing() }
        .onDisappear { model.stopIndexing() }
    }
}

struct ReaderSidebar: View {
    let model: ReaderModel

    var body: some View {
        List {
            if !model.searchResults.isEmpty {
                Section("Results (\(model.searchResults.count))") {
                    ForEach(model.searchResults) { result in
                        Button { model.show(result) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.snippet).lineLimit(2)
                                Text("Page \(result.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Contents") {
                if model.outline.isEmpty {
                    Text("This document has no outline.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.outline.enumerated()), id: \.offset) { _, entry in
                    Button(entry.title) { model.go(toPage: entry.pageIndex) }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat(entry.level) * 12)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct IndexStatusView: View {
    let progress: IndexProgress
    let error: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle").labelStyle(.iconOnly).help(error)
        } else if !progress.isComplete {
            HStack(spacing: 6) {
                ProgressView(value: Double(progress.indexedPages), total: Double(max(progress.pageCount, 1)))
                    .frame(width: 80)
                Text("Indexing \(progress.indexedPages)/\(progress.pageCount)").font(.caption).monospacedDigit()
            }
        }
    }
}
