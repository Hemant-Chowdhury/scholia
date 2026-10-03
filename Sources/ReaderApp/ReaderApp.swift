import AppKit
import ReaderUI
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs outside an .app bundle (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()

    var body: some Scene {
        Window("Reader", id: "library") {
            LibraryView(library: library)
        }
        .keyboardShortcut("0")
        .commands {
            CommandGroup(replacing: .newItem) { OpenPDFCommand() }
        }

        WindowGroup(id: "reader", for: URL.self) { $url in
            if let url {
                ReaderWindow(url: url, library: library)
            }
        }
    }
}

/// Shows the system open panel for one PDF.
@MainActor
func choosePDF() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}

struct OpenPDFCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open PDF…") {
            if let url = choosePDF() { openWindow(id: "reader", value: url) }
        }
        .keyboardShortcut("o")
    }
}
