import PDFKit

/// PDFView with Option-click paragraph selection and the H key for highlight.
final class ReaderPDFView: PDFView {
    /// Gets the page index and the point in page coordinates. Returns true when it handled the click.
    var onOptionClick: ((Int, CGPoint) -> Bool)?
    var onHighlightKey: (() -> Void)?

    /// Option-click always belongs to Reader. A click with no paragraph under it does nothing, so
    /// PDFView's own Option-drag (rectangle selection) is not available.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onOptionClick {
            let point = convert(event.locationInWindow, from: nil)
            if let document, let page = page(for: point, nearest: false) {
                _ = onOptionClick(document.index(for: page), convert(point, to: page))
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, event.charactersIgnoringModifiers == "h",
           currentSelection?.string?.isEmpty == false, let onHighlightKey {
            onHighlightKey()
            return
        }
        super.keyDown(with: event)
    }
}
