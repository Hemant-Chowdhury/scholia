import AppKit
import DocumentKit
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import ReaderUI

/// UI tests with the real reader views in a real window, driven by real mouse and key events.
/// Set READER_UI_SNAPSHOT_DIR to save a picture of the window after each test.
@MainActor
struct ReaderWindowUITests {
    let helper = ParagraphSelectionTests()

    struct Hosted {
        let window: NSWindow
        let pdfView: ReaderPDFView
        let model: ReaderModel
    }

    func host(_ url: URL) throws -> Hosted {
        _ = NSApplication.shared
        let model = try helper.openModel(url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ReaderView(model: model))
        window.orderFront(nil)
        spin(0.8)
        let content = try #require(window.contentView)
        let pdfView = try #require(Self.find(ReaderPDFView.self, in: content))
        return Hosted(window: window, pdfView: pdfView, model: model)
    }

    func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    static func selectionBar(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("SelectionBar"), !view.isHidden { return view }
        for subview in view.subviews {
            if let match = selectionBar(in: subview) { return match }
        }
        return nil
    }

    func click(_ hosted: Hosted, pageIndex: Int, pagePoint: CGPoint, modifiers: NSEvent.ModifierFlags) throws {
        let page = try #require(hosted.pdfView.document?.page(at: pageIndex))
        hosted.pdfView.go(to: page)
        spin(0.2)
        let windowPoint = hosted.pdfView.convert(hosted.pdfView.convert(pagePoint, from: page), to: nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: modifiers, timestamp: 0,
            windowNumber: hosted.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        hosted.pdfView.mouseDown(with: event)
        spin(0.3)
    }

    func press(_ hosted: Hosted, key: String) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: hosted.window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 4))
        hosted.pdfView.keyDown(with: event)
        spin(0.3)
    }

    /// Captures the real window from the screen (with PDFKit layers), when READER_UI_SNAPSHOT_DIR is set.
    func snapshot(_ hosted: Hosted, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["READER_UI_SNAPSHOT_DIR"] else { return }
        spin(0.5)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l\(hosted.window.windowNumber)", "\(folder)/\(name).png"]
        try? capture.run()
        capture.waitUntilExit()
    }

    @Test func optionClickSelectsParagraphInTheViewAndShowsTheBar() throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        try click(hosted, pageIndex: 0, pagePoint: helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        snapshot(hosted, "option-click")
        #expect(collapsed(hosted.pdfView.currentSelection?.string) == "Agents call tools in a loop.")
        #expect(collapsed(hosted.model.selectedText) == "Agents call tools in a loop.")
        #expect(Self.selectionBar(in: hosted.window.contentView!) != nil)
    }

    @Test func secondOptionClickExtendsTheSelectionInTheView() throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        let point = try helper.center(of: 0, onPage: 0, in: url)
        try click(hosted, pageIndex: 0, pagePoint: point, modifiers: .option)
        try click(hosted, pageIndex: 0, pagePoint: point, modifiers: .option)
        #expect(collapsed(hosted.pdfView.currentSelection?.string) == "Agents call tools in a loop. The loop stops when done.")
    }

    @Test func hKeyHighlightsAndDrawsAnAnnotation() throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        try click(hosted, pageIndex: 0, pagePoint: helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try press(hosted, key: "h")
        snapshot(hosted, "highlight")
        #expect(hosted.model.highlights.count == 1)
        let page = try #require(hosted.pdfView.document?.page(at: 0))
        #expect(page.annotations.contains { $0.type == "Highlight" })
    }

    @Test func optionClickInTheMarginSelectsNothing() throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        try click(hosted, pageIndex: 0, pagePoint: CGPoint(x: 10, y: 10), modifiers: .option)
        #expect(hosted.model.selection == nil)
        #expect(Self.selectionBar(in: hosted.window.contentView!) == nil)
    }
}
