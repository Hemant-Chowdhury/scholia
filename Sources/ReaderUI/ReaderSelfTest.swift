#if DEBUG
import AppKit
import DocumentKit
import PDFKit

/// End-to-end check in the real app (debug builds only). It sends an Option-click and the H key through
/// the real AppKit event loop, then writes the result and a screenshot, and quits the app.
/// Start: READER_SELF_TEST_OUT=<folder> READER_DATA_ROOT=<folder> .build/debug/Reader <pdf path>
@MainActor
public enum ReaderSelfTest {
    public static var outputFolder: URL? {
        ProcessInfo.processInfo.environment["READER_SELF_TEST_OUT"].map { URL(fileURLWithPath: $0) }
    }

    public static func run(after delay: TimeInterval = 4) {
        guard let folder = outputFolder else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { step1(folder) }
        }
    }

    private static func step1(_ folder: URL) {
        guard let window = NSApp.windows.first(where: { find(in: $0.contentView) != nil }),
              let view = find(in: window.contentView), let document = view.document,
              view.document?.page(at: 40) != nil else { return finish(folder, "FAIL: no reader window; windows: \(NSApp.windows.map { "\($0.title) visible=\($0.isVisible)" }); queue args: \(CommandLine.arguments)") }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let page = document.page(at: 40)!
        view.go(to: page)
        view.layoutDocumentView()
        let pageIndex = 40
        guard let url = document.documentURL, let source = try? PDFDocumentSource(url: url) else {
            return finish(folder, "FAIL: no document")
        }
        let paragraphs = source.paragraphs(onPage: pageIndex)
        guard let target = paragraphs.dropFirst().first ?? paragraphs.first else { return finish(folder, "FAIL: no paragraph") }
        let point = view.convert(view.convert(CGPoint(x: target.rect.midX, y: target.rect.midY), from: page), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: .option,
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                              clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                let selected = view.currentSelection?.string ?? ""
                let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: "h",
                                           charactersIgnoringModifiers: "h", isARepeat: false, keyCode: 4)
                if let key { NSApp.postEvent(key, atStart: false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated {
                        let highlights = page.annotations.filter { $0.type == "Highlight" }.count
                        finish(folder, """
                            page: \(pageIndex + 1)
                            expected: \(target.text)
                            selected: \(selected.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
                            highlight annotations on page: \(highlights)
                            app active: \(NSApp.isActive), window key: \(window.isKeyWindow), first responder: \(String(describing: window.firstResponder.map { type(of: $0) }))
                            """)
                    }
                }
            }
        }
    }

    private static func find(in view: NSView?) -> ReaderPDFView? {
        guard let view else { return nil }
        if let match = view as? ReaderPDFView { return match }
        for subview in view.subviews { if let match = find(in: subview) { return match } }
        return nil
    }

    private static func capture(_ window: NSWindow, _ file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.windowNumber)", file.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func finish(_ folder: URL, _ result: String) {
        try? result.write(to: folder.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
#endif
