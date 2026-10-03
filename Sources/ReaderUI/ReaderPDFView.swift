import PDFKit

/// PDFView with Option-click paragraph selection and the H key for highlight.
final class ReaderPDFView: PDFView {
    /// Gets the page index and the point in page coordinates. Returns true when it handled the click.
    var onOptionClick: ((Int, CGPoint) -> Bool)?
    var onHighlightKey: (() -> Void)?

    /// Option-click on a paragraph selects it. Any other Option-click goes to PDFView, so its
    /// Option-drag (rectangle selection) still works when it starts outside a paragraph.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onOptionClick, let document {
            let point = convert(event.locationInWindow, from: nil)
            if let page = page(for: point, nearest: false),
               onOptionClick(document.index(for: page), convert(point, to: page)) {
                return
            }
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
