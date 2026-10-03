import ReaderUI
import SwiftUI

/// Opens the workspace for a URL, then shows the reader.
struct ReaderWindow: View {
    let url: URL
    let library: Library
    @State private var model: ReaderModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                ReaderView(model: model)
            } else if let errorMessage {
                ContentUnavailableView("Reader cannot open this file", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("Opening…")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task(id: url) {
            do {
                model = try await library.openModel(for: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
