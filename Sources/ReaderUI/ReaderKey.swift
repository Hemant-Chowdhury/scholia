import Assistant

/// The one-letter keys that work on the selection in the PDF view.
enum ReaderKey: String {
    case highlight = "h", explain = "e", simplify = "s", define = "d", ask = "a"

    var action: ReadingAction? {
        switch self {
        case .highlight: nil
        case .explain: .explain
        case .simplify: .simplify
        case .define: .define
        case .ask: .ask
        }
    }
}

extension ReaderModel {
    /// Runs the action of a key on the selection. Returns false when there is no selection.
    func handle(_ key: ReaderKey) -> Bool {
        guard selection != nil else { return false }
        if let action = key.action { run(action) } else { highlightSelection() }
        return true
    }
}
