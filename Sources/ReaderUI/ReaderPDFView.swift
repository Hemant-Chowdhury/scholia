import PDFKit

/// PDFView with Option-click paragraph selection and the H key for highlight.
final class ReaderPDFView: PDFView {
    /// Gets the page index and the point in page coordinates. Returns true when it handled the click.
    var onOptionClick: ((Int, CGPoint) -> Bool)?
    /// Handles a reading key (H, E, S, D or A). Returns true when it used the key.
    var onKey: ((ReaderKey) -> Bool)?
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

    /// The first click in an inactive window also selects (an Option-click must not be lost).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The reading key of an event: a plain letter, with no Command, Control or Option.
    static func readerKey(_ event: NSEvent) -> ReaderKey? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let letter = event.charactersIgnoringModifiers?.lowercased(), letter.count == 1 else { return nil }
        return ReaderKey(rawValue: letter)
    }

    override func keyDown(with event: NSEvent) {
        if let key = Self.readerKey(event), let onKey, onKey(key) { return }
        super.keyDown(with: event)
    }
}
