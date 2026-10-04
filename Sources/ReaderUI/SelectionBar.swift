import Assistant
import SwiftUI

/// The small bar above the selection: the assistant actions and Highlight.
struct SelectionBar: View {
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 2) {
            action(.explain, "Explain", "sparkles", key: "E")
            action(.simplify, "Simplify", "text.badge.minus", key: "S")
            action(.define, "Define", "character.book.closed", key: "D")
            action(.ask, "Ask…", "questionmark.bubble", key: "A")
            Divider().frame(height: 16).padding(.horizontal, 4)
            if model.selectionHighlights.isEmpty {
                Button { model.highlightSelection() } label: { Label("Highlight", systemImage: "highlighter") }
                    .help("Highlight (H)")
            } else {
                Button { model.removeSelectionHighlights() } label: { Label("Remove highlight", systemImage: "eraser") }
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .fixedSize()
    }

    private func action(_ action: ReadingAction, _ title: String, _ icon: String, key: String) -> some View {
        Button { model.run(action) } label: { Label(title, systemImage: icon) }
            .help("\(title) (\(key))")
    }
}
