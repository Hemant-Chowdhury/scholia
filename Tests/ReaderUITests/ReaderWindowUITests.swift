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
        try host(model: helper.openModel(url))
    }

    func host(model: ReaderModel) throws -> Hosted {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ReaderView(model: model))
        window.orderFront(nil)
        spin(0.8)
        let content = try #require(window.contentView)
        let pdfView = try #require(Self.find(ReaderPDFView.self, in: content))
        return Hosted(window: window, pdfView: pdfView, model: model)
    }

    /// Dispatches the event like AppKit does: `NSApp.sendEvent` finds the window, the window hit-tests the
    /// views. Only the app's event loop sets `NSApp.currentEvent`, so the test gives the event to the view.
    func deliver(_ event: NSEvent) {
        ReaderPDFView.currentEvent = { event }
        defer { ReaderPDFView.currentEvent = { NSApp.currentEvent } }
        if event.type == .keyDown {
            event.window?.sendEvent(event)
        } else {
            NSApp.sendEvent(event)
        }
    }

    /// Lets queued main-thread work run (for example, the selection bar position), which `spin` cannot do.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func all<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found = view.subviews.flatMap { all(type, in: $0) }
        if let match = view as? T { found.insert(match, at: 0) }
        return found
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    static func selectionBar(in view: NSView) -> NSView? {
        if view is SelectionBarView, !view.isHidden { return view }
        for subview in view.subviews {
            if let match = selectionBar(in: subview) { return match }
        }
        return nil
    }

    /// A point on the Explain button (the first button) of the selection bar, in window coordinates.
    static func explainButtonPoint(_ hosted: Hosted) -> CGPoint? {
        guard let bar = hosted.window.contentView.flatMap(selectionBar(in:)) else { return nil }
        return bar.convert(CGPoint(x: 30, y: bar.bounds.midY), to: nil)
    }

    func click(_ hosted: Hosted, pageIndex: Int, pagePoint: CGPoint, modifiers: NSEvent.ModifierFlags) throws {
        let page = try #require(hosted.pdfView.document?.page(at: pageIndex))
        hosted.pdfView.go(to: page)
        spin(0.2)
        let windowPoint = hosted.pdfView.convert(hosted.pdfView.convert(pagePoint, from: page), to: nil)
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: hosted.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        deliver(event)
        spin(0.3)
    }

    func press(_ hosted: Hosted, key: String) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: hosted.window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 4))
        deliver(event)
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

    @Test func optionClickSelectsParagraphInTheViewAndShowsTheBar() async throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        try click(hosted, pageIndex: 0, pagePoint: helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try await settle()
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


    @Test func hKeyAfterClickingTheSidebarStillHighlights() throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        hosted.window.makeFirstResponder(nil)
        try click(hosted, pageIndex: 0, pagePoint: helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try press(hosted, key: "h")
        #expect(hosted.model.highlights.count == 1)
    }

    @Test func aClickOnTheBarDoesNotReachThePDFView() async throws {
        let url = try helper.makeBook()
        let hosted = try host(url)
        try click(hosted, pageIndex: 0, pagePoint: helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try await settle()
        let point = try #require(Self.explainButtonPoint(hosted))
        let frameView = try #require(hosted.window.contentView?.superview)
        let hit = try #require(frameView.hitTest(frameView.convert(point, from: nil)))
        // PDFKit's gesture recognizers take clicks on any view inside the PDF view.
        #expect(hit !== hosted.pdfView && !hit.isDescendant(of: hosted.pdfView), "click goes to \(type(of: hit))")
    }

    @Test func highlightKeyDecisionIgnoresModifiedKeys() throws {
        func key(_ chars: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                          isARepeat: false, keyCode: 4))
        }
        #expect(ReaderPDFView.readerKey(try key("h", [])) == .highlight)
        #expect(ReaderPDFView.readerKey(try key("E", [])) == .explain)
        #expect(ReaderPDFView.readerKey(try key("r", [])) == .resources)
        #expect(ReaderKey.resources.action == .resources)
        #expect(ReaderPDFView.readerKey(try key("h", .command)) == nil)
        #expect(ReaderPDFView.readerKey(try key("j", [])) == nil)
    }
}
