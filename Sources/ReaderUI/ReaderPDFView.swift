import PDFKit

/// PDFView with Option-click paragraph selection and the H key for highlight.
final class ReaderPDFView: PDFView {
    /// Gets the page index and the point in page coordinates. Returns true when it handled the click.
    var onOptionClick: ((Int, CGPoint) -> Bool)?
    var onHighlightKey: (() -> Void)?
    /// Clicks on the selection bar must reach the bar.
    weak var selectionBar: NSView?
    /// The event that AppKit is dispatching. Tests replace it, because only the app's own event loop sets
    /// `NSApp.currentEvent`.
    static var currentEvent: () -> NSEvent? = { NSApp.currentEvent }

    /// PDFKit sends clicks to its internal page views, which never call this class. For an Option-click,
    /// this view takes the click itself, so `mouseDown` can select the paragraph.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, let event = Self.currentEvent(), event.type == .leftMouseDown,
              event.modifierFlags.contains(.option) else { return hit }
        if let bar = selectionBar, hit === bar || hit.isDescendant(of: bar) { return hit }
        return self
    }

    /// Option-click on a paragraph selects it. Any other Option-click goes to PDFView, so its
    /// Option-drag (rectangle selection) still works when it starts outside a paragraph.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onOptionClick, let document {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            if let page = page(for: point, nearest: false),
               onOptionClick(document.index(for: page), convert(point, to: page)) {
                return
            }
        }
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    /// The plain H key, with no Command, Control or Option.
    static func isHighlightKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == "h"
    }

    override func keyDown(with event: NSEvent) {
        if Self.isHighlightKey(event), currentSelection?.string?.isEmpty == false, let onHighlightKey {
            onHighlightKey()
            return
        }
        super.keyDown(with: event)
    }
}
