import DocumentKit
import PDFKit
import SwiftUI
import WorkspaceStore

/// Shows the PDF, reports page and selection changes to the model, follows its requests,
/// draws the highlights, and shows the selection bar.
struct PDFKitView: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = model.pdf
        let model = self.model
        view.onOptionClick = { pageIndex, point in model.optionClick(at: point, onPage: pageIndex) }
        view.onHighlightKey = { model.highlightSelection() }
        context.coordinator.observe(view)
        return view
    }

    static func dismantleNSView(_ view: ReaderPDFView, coordinator: Coordinator) {
        coordinator.stopKeyMonitor()
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.apply(model.navigationRequest, to: view)
        coordinator.apply(model.selectionRequest, to: view)
        coordinator.sync(model.highlights, in: view)
        coordinator.positionBar(for: model.selection, in: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ReaderModel
        private var handledNavigationID: UUID?
        private var handledSelectionID: UUID?
        private var applyingSelection = false
        private var drawn: [String: [PDFAnnotation]] = [:]
        private lazy var bar = NSHostingView(rootView: SelectionBar(model: model))
        private var keyMonitor: Any?

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: PDFView) {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
            center.addObserver(self, selector: #selector(selectionChanged(_:)), name: .PDFViewSelectionChanged, object: view)
            center.addObserver(self, selector: #selector(layoutChanged(_:)), name: .PDFViewScaleChanged, object: view)
            startKeyMonitor(for: view)
            if let clip = view.documentView?.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                center.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: clip)
                scrollTarget = view
            }
        }

        private weak var scrollTarget: PDFView?

        @objc private func scrolled(_ notification: Notification) {
            guard let view = scrollTarget else { return }
            positionBar(for: model.selection, in: view)
        }

        /// H highlights the selection in this window, also when PDFKit's internal views have the focus.
        /// Typing in a text field (for example, the search field) is not changed.
        private func startKeyMonitor(for view: PDFView) {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard ReaderPDFView.isHighlightKey(event) else { return event }
                let eventWindow = event.window
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let view, eventWindow === view.window,
                          !(view.window?.firstResponder is NSText), self.model.selection != nil else { return false }
                    self.model.highlightSelection()
                    return true
                }
                return handled ? nil : event
            }
        }

        func stopKeyMonitor() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage, let document = view.document else { return }
            model.pageDidChange(to: document.index(for: page))
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard !applyingSelection, let view = notification.object as? PDFView else { return }
            model.selectionDidChange(view.currentSelection)
        }

        @objc private func layoutChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            positionBar(for: model.selection, in: view)
        }

        func apply(_ request: NavigationRequest?, to view: PDFView) {
            guard let request, request.id != handledNavigationID,
                  let page = view.document?.page(at: request.pageIndex) else { return }
            handledNavigationID = request.id
            view.layoutDocumentView()
            if let selection = request.selection {
                view.setCurrentSelection(selection, animate: true)
                view.go(to: selection)
            } else {
                view.go(to: page)
            }
        }

        func apply(_ request: SelectionRequest?, to view: PDFView) {
            guard let request, request.id != handledSelectionID else { return }
            handledSelectionID = request.id
            applyingSelection = true
            view.setCurrentSelection(request.selection, animate: false)
            applyingSelection = false
        }

        /// Adds annotations for new highlights and removes annotations for deleted highlights.
        func sync(_ highlights: [StoredHighlight], in view: PDFView) {
            guard let document = view.document else { return }
            let wanted = Set(highlights.map(\.highlight.id))
            for (id, annotations) in drawn where !wanted.contains(id) {
                annotations.forEach { $0.page?.removeAnnotation($0) }
                drawn[id] = nil
            }
            for stored in highlights where drawn[stored.highlight.id] == nil {
                guard let locator = model.resolvedLocators[stored.highlight.id] else { continue }
                drawn[stored.highlight.id] = HighlightGeometry.lineRects(for: locator, in: document).compactMap { item in
                    guard let page = document.page(at: item.pageIndex) else { return nil }
                    let annotation = PDFAnnotation(bounds: item.rect, forType: .highlight, withProperties: nil)
                    let size = item.rect.size
                    annotation.quadrilateralPoints = [
                        NSValue(point: CGPoint(x: 0, y: size.height)), NSValue(point: CGPoint(x: size.width, y: size.height)),
                        NSValue(point: .zero), NSValue(point: CGPoint(x: size.width, y: 0)),
                    ]
                    annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
                    page.addAnnotation(annotation)
                    return annotation
                }
            }
        }

        /// Puts the bar above the first line of the selection. The bar is a subview of the PDF view itself
        /// (PDFKit's page views would cover it in the document view), so it moves again when the view scrolls.
        func positionBar(for selection: PDFSelection?, in view: PDFView) {
            guard let selection, let page = selection.pages.first else {
                bar.isHidden = true
                return
            }
            if bar.superview !== view {
                view.addSubview(bar)
                (view as? ReaderPDFView)?.selectionBar = bar
            }
            let rect = view.convert(selection.bounds(for: page), from: page)
            let size = bar.fittingSize
            let y = view.isFlipped ? rect.minY - size.height - 6 : rect.maxY + 6
            let maxY = view.bounds.height - size.height - 4
            bar.frame = CGRect(x: min(max(rect.minX, 4), max(view.bounds.width - size.width - 4, 4)),
                               y: min(max(y, 4), max(maxY, 4)), width: size.width, height: size.height)
            bar.isHidden = !view.bounds.intersects(rect)
        }
    }
}
