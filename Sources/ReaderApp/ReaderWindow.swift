import ReaderUI
import SwiftUI

/// Opens the workspace for a URL, then shows the reader.
struct ReaderWindow: View {
    let url: URL
    let library: Library
    @State private var model: ReaderModel?
    @State private var errorMessage: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let model {
                ReaderView(model: model)
            } else if let errorMessage {
                ContentUnavailableView("Scholia cannot open this file", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("Opening…")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            library.readerWindowOpened()
            dismissWindow(id: "library")
        }
        .onDisappear {
            if let model { library.readerClosed(model) }
            if library.readerWindowClosed() { openWindow(id: "library") }
        }
        .task(id: url) {
            do {
                model = try await library.openModel(for: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
