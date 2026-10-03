import SwiftUI

/// The small bar above the selection. M3 adds the LLM actions here.
struct SelectionBar: View {
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 4) {
            if model.selectionHighlights.isEmpty {
                Button { model.highlightSelection() } label: {
                    Label("Highlight", systemImage: "highlighter")
                }
                .help("Highlight (H)")
            } else {
                Button { model.removeSelectionHighlights() } label: {
                    Label("Remove highlight", systemImage: "eraser")
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
        .fixedSize()
    }
}
