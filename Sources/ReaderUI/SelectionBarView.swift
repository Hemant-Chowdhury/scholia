import AppKit
import Assistant

/// The small bar above the selection, with native buttons: Explain, Simplify, Define, Ask…, Resources and Highlight.
/// It is an AppKit view (not SwiftUI): it lives next to the PDF view, and NSButton handles real clicks there.
final class SelectionBarView: NSVisualEffectView {
    enum Action: Equatable {
        case reading(ReadingAction)
        case highlight
        case removeHighlight
    }

    var onAction: ((Action) -> Void)?
    private let highlightButton = NSButton()
    private var highlighted = false

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let buttons = [
            button("Explain", symbol: "sparkles", key: "E", action: .reading(.explain)),
            button("Simplify", symbol: "text.badge.minus", key: "S", action: .reading(.simplify)),
            button("Define", symbol: "character.book.closed", key: "D", action: .reading(.define)),
            button("Ask…", symbol: "questionmark.bubble", key: "A", action: .reading(.ask)),
            button("Resources", symbol: "globe", key: "R", action: .reading(.resources)),
        ]
        configure(highlightButton, title: "Highlight", symbol: "highlighter", help: "Highlight (H)")
        highlightButton.target = self
        highlightButton.action = #selector(highlightClicked)

        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: buttons + [separator, highlightButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows "Remove highlight" when the selection is already highlighted.
    func setHighlighted(_ value: Bool) {
        guard value != highlighted else { return }
        highlighted = value
        configure(highlightButton, title: value ? "Remove highlight" : "Highlight",
                  symbol: value ? "eraser" : "highlighter", help: value ? "Remove the highlight" : "Highlight (H)")
    }

    /// The button with this title (for tests and the self-test).
    func button(titled title: String) -> NSButton? {
        subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private var actions: [ObjectIdentifier: Action] = [:]

    private func button(_ title: String, symbol: String, key: String, action: Action) -> NSButton {
        let button = NSButton()
        configure(button, title: title, symbol: symbol, help: "\(title) (\(key))")
        button.target = self
        button.action = #selector(clicked(_:))
        actions[ObjectIdentifier(button)] = action
        return button
    }

    private func configure(_ button: NSButton, title: String, symbol: String, help: String) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.toolTip = help
    }

    @objc private func clicked(_ sender: NSButton) {
        if let action = actions[ObjectIdentifier(sender)] { onAction?(action) }
    }

    @objc private func highlightClicked() {
        onAction?(highlighted ? .removeHighlight : .highlight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
