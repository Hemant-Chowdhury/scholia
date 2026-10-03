import DocumentKit
import Foundation
import Observation
import PDFKit
import WorkspaceStore

public struct SearchResult: Identifiable {
    public let id = UUID()
    public let pageIndex: Int
    public let snippet: String
    public let selection: PDFSelection
}

/// A request to move the PDF view. Each request has a new ID, so the same page can be requested again.
public struct NavigationRequest: Equatable {
    public let id = UUID()
    public let pageIndex: Int
    public let selection: PDFSelection?

    public static func == (lhs: NavigationRequest, rhs: NavigationRequest) -> Bool { lhs.id == rhs.id }
}

/// A request to set the selection in the PDF view. Each request has a new ID.
public struct SelectionRequest: Equatable {
    public let id = UUID()
    public let selection: PDFSelection?

    public static func == (lhs: SelectionRequest, rhs: SelectionRequest) -> Bool { lhs.id == rhs.id }
}

/// State and actions of one reader window.
@MainActor
@Observable
public final class ReaderModel {
    public let workspace: OpenedWorkspace
    public let pdfURL: URL
    public let pdf: PDFDocument
    public let outline: [OutlineEntry]
    public private(set) var currentPage: Int
    public private(set) var indexProgress: IndexProgress
    public private(set) var searchResults: [SearchResult] = []
    public private(set) var navigationRequest: NavigationRequest?
    public private(set) var lastError: String?
    public private(set) var selection: PDFSelection?
    public private(set) var selectionRequest: SelectionRequest?
    public private(set) var highlights: [StoredHighlight]
    /// The checked location of each highlight, by highlight ID. A highlight whose text cannot be found is missing.
    public private(set) var resolvedLocators: [String: PDFLocator]
    @ObservationIgnored private let source: PDFDocumentSource
    @ObservationIgnored private var paragraphCache: [Int: [Paragraph]] = [:]
    @ObservationIgnored private var selectedParagraphs: [Paragraph] = []
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    public init(workspace: OpenedWorkspace, pdfURL: URL) throws {
        let source = try PDFDocumentSource(url: pdfURL)
        let stored = try workspace.database.document(id: workspace.document.id) ?? workspace.document
        let lastPage = min(max(stored.lastPage, 0), max(source.pdf.pageCount - 1, 0))
        self.workspace = workspace
        self.pdfURL = pdfURL
        self.source = source
        self.pdf = source.pdf
        self.outline = source.outline
        self.currentPage = lastPage
        self.indexProgress = IndexProgress(indexedPages: stored.indexedPages, pageCount: stored.pageCount)
        self.navigationRequest = NavigationRequest(pageIndex: lastPage, selection: nil)
        let highlights = try workspace.database.highlights(documentID: workspace.document.id)
        self.highlights = highlights
        self.resolvedLocators = Self.resolve(highlights, in: source.pdf)
    }

    public var structuralPath: [String] { StructuralPath.path(forPage: currentPage, in: outline) }

    public func pageDidChange(to pageIndex: Int) {
        guard pageIndex != currentPage else { return }
        currentPage = pageIndex
        do {
            try workspace.database.setLastPage(pageIndex, documentID: workspace.document.id)
        } catch {
            lastError = "Reader cannot save the current page: \(error.localizedDescription)"
        }
    }

    public var selectedText: String? { selection?.string }

    public func selectionDidChange(_ selection: PDFSelection?) {
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.selection = text.isEmpty ? nil : selection
        selectedParagraphs = []
    }

    /// Selects the paragraph at the point, or adds the next paragraph when the point is in the current
    /// paragraph selection. Returns false when no paragraph is at the point.
    @discardableResult
    public func optionClick(at point: CGPoint, onPage pageIndex: Int) -> Bool {
        guard let hit = paragraphs(onPage: pageIndex).first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) })
        else { return false }
        if selectedParagraphs.contains(hit) {
            if let last = selectedParagraphs.last, let next = paragraph(after: last) {
                selectedParagraphs.append(next)
            }
        } else {
            selectedParagraphs = [hit]
        }
        let segments = selectedParagraphs
            .filter { $0.textRange.location != NSNotFound }
            .map { PDFLocator.Segment(pageIndex: $0.pageIndex, location: $0.textRange.location, length: $0.textRange.length) }
        let newSelection = PDFLocator(segments: segments).selection(in: pdf)
        selection = newSelection
        selectionRequest = SelectionRequest(selection: newSelection)
        return true
    }

    private func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        if let cached = paragraphCache[pageIndex] { return cached }
        let paragraphs = source.paragraphs(onPage: pageIndex)
        paragraphCache[pageIndex] = paragraphs
        return paragraphs
    }

    private func paragraph(after paragraph: Paragraph) -> Paragraph? {
        let samePage = paragraphs(onPage: paragraph.pageIndex)
        if paragraph.index + 1 < samePage.count { return samePage[paragraph.index + 1] }
        let upper = min(paragraph.pageIndex + 4, pdf.pageCount)
        guard paragraph.pageIndex + 1 < upper else { return nil }
        for page in (paragraph.pageIndex + 1)..<upper {
            if let first = paragraphs(onPage: page).first { return first }
        }
        return nil
    }

    public var selectionHighlights: [StoredHighlight] {
        guard let selection, let locator = PDFLocator(selection: selection, in: pdf) else { return [] }
        return highlights.filter { resolvedLocators[$0.highlight.id]?.overlaps(locator) == true }
    }

    private func reloadHighlights() throws {
        highlights = try workspace.database.highlights(documentID: workspace.document.id)
        resolvedLocators = Self.resolve(highlights, in: pdf)
    }

    private static func resolve(_ highlights: [StoredHighlight], in pdf: PDFDocument) -> [String: PDFLocator] {
        highlights.reduce(into: [:]) { result, stored in
            if let saved = try? PDFLocator.from(json: stored.anchor.locatorJSON),
               let resolved = saved.resolved(expectedText: stored.anchor.text, in: pdf) {
                result[stored.highlight.id] = resolved
            }
        }
    }

    public func highlightSelection() {
        guard let selection, let locator = PDFLocator(selection: selection, in: pdf), selectionHighlights.isEmpty else { return }
        do {
            let now = Date()
            let anchor = AnchorRecord(
                id: UUID().uuidString, documentID: workspace.document.id, kind: DocumentKind.pdf.rawValue,
                locatorJSON: try locator.json(), text: selection.string ?? "",
                structuralPath: StructuralPath.path(forPage: locator.firstPage, in: outline).joined(separator: " › "),
                firstPage: locator.firstPage, createdAt: now)
            let highlight = HighlightRecord(id: UUID().uuidString, anchorID: anchor.id, color: "yellow", createdAt: now)
            try workspace.database.addHighlight(highlight, anchor: anchor)
            try reloadHighlights()
        } catch {
            lastError = "Reader cannot save the highlight: \(error.localizedDescription)"
        }
    }

    public func removeSelectionHighlights() {
        do {
            for stored in selectionHighlights {
                try workspace.database.removeHighlight(id: stored.highlight.id)
            }
            try reloadHighlights()
        } catch {
            lastError = "Reader cannot remove the highlight: \(error.localizedDescription)"
        }
    }

    public func show(_ highlight: StoredHighlight) {
        let selection = resolvedLocators[highlight.highlight.id]?.selection(in: pdf)
        navigationRequest = NavigationRequest(pageIndex: highlight.anchor.firstPage, selection: selection)
    }

    public func go(toPage pageIndex: Int) {
        navigationRequest = NavigationRequest(pageIndex: pageIndex, selection: nil)
    }

    public func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchResults = pdf.findString(query, withOptions: .caseInsensitive).prefix(200).compactMap { selection in
            guard let page = selection.pages.first, let context = selection.copy() as? PDFSelection else { return nil }
            context.extend(atStart: 40)
            context.extend(atEnd: 40)
            let snippet = (context.string ?? query).replacingOccurrences(of: "\n", with: " ")
            return SearchResult(pageIndex: pdf.index(for: page), snippet: snippet, selection: selection)
        }
    }

    public func show(_ result: SearchResult) {
        navigationRequest = NavigationRequest(pageIndex: result.pageIndex, selection: result.selection)
    }

    public func startIndexing() {
        guard indexTask == nil else { return }
        let workspace = self.workspace
        let pdfURL = self.pdfURL
        let pageCount = workspace.document.pageCount
        indexTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try DocumentIndexer.run(workspace: workspace, pdfURL: pdfURL) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.indexProgress = progress }
                }
                // Progress tasks can arrive in a different order, so the final state is set last.
                await MainActor.run { [weak self] in
                    self?.indexProgress = IndexProgress(indexedPages: pageCount, pageCount: pageCount)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = "Reader cannot index this document: \(error.localizedDescription)"
                }
            }
        }
    }

    public func stopIndexing() {
        indexTask?.cancel()
        indexTask = nil
    }
}
