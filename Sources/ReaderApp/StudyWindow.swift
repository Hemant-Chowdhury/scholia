import ReaderUI
import SwiftUI

/// Shows the Study view of an open book. A Study window that macOS restores without its book asks to open the book.
struct StudyWindow: View {
    let workspaceID: String
    let library: Library
    @State private var study: StudyModel?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let study {
                StudyView(study: study)
            } else {
                ContentUnavailableView {
                    Label("Open the book first", systemImage: "book.closed")
                } description: {
                    Text("The Study window shows the questions of an open book.")
                } actions: {
                    if let url = library.documentURL(forWorkspace: workspaceID) {
                        Button("Open the book") { openWindow(id: "reader", value: url) }
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        // Follow the open book window of this workspace: a new window gives a new reader, a closed one gives none.
        .onChange(of: library.readerVersion, initial: true) { attach() }
    }

    private func attach() {
        let reader = library.reader(forWorkspace: workspaceID)
        if reader !== study?.reader { study = reader.map(StudyModel.init(reader:)) }
    }
}
