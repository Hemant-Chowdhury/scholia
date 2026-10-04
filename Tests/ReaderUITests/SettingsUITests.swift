import AppKit
import Assistant
import SwiftUI
import Testing
import TestSupport
@testable import ReaderUI

@MainActor
@Suite(.enabled(if: WindowTests.available))
struct SettingsUITests {
    @Test func promptSettingsShowEachPromptInAWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: PromptSettings())
        window.orderFront(nil)
        let ui = ReaderWindowUITests()
        ui.spin(0.8)
        if let folder = ProcessInfo.processInfo.environment["READER_UI_SNAPSHOT_DIR"],
           let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            // SwiftUI content draws correctly this way (no screen recording permission needed).
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: folder).appendingPathComponent("settings-prompts.png"))
        }
        let editors = ReaderWindowUITests.all(NSTextView.self, in: try #require(window.contentView))
        #expect(editors.count >= 4)
        #expect(editors.contains { $0.string.hasPrefix("You are a reading tutor") })
    }
}
