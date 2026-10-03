import ReaderUI
import SwiftUI

/// The start window: an open button and the recent documents.
struct LibraryView: View {
    let library: Library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = library.startupError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Button("Open PDF…") {
                if let url = choosePDF() { openWindow(id: "reader", value: url) }
            }
            .buttonStyle(.borderedProminent)
            Text("Recent").font(.headline)
            if library.recents.isEmpty {
                Text("No documents yet.").foregroundStyle(.secondary)
            }
            List(library.recents, id: \.contentHash) { recent in
                Button {
                    openWindow(id: "reader", value: URL(fileURLWithPath: recent.lastPath))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent.title)
                        Text(recent.lastPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { library.refreshRecents() }
    }
}
