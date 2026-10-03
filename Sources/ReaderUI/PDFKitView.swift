import PDFKit
import SwiftUI

/// Shows the PDF, reports page changes to the model, and follows its navigation requests.
struct PDFKitView: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = model.pdf
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.apply(model.navigationRequest, to: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ReaderModel
        private var handledRequestID: UUID?

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage, let document = view.document else { return }
            model.pageDidChange(to: document.index(for: page))
        }

        func apply(_ request: NavigationRequest?, to view: PDFView) {
            guard let request, request.id != handledRequestID,
                  let page = view.document?.page(at: request.pageIndex) else { return }
            handledRequestID = request.id
            view.layoutDocumentView()
            if let selection = request.selection {
                view.setCurrentSelection(selection, animate: true)
                view.go(to: selection)
            } else {
                view.go(to: page)
            }
        }
    }
}
