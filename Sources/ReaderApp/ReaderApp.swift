import AgentKit
import AppKit
import ReaderUI
import SwiftUI
import WorkspaceStore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs outside an .app bundle (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let files = CommandLine.arguments.dropFirst()
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        OpenQueue.shared.add(files)
        #if DEBUG
        ReaderSelfTest.run()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessTransport.terminateAll()
    }

    /// Finder: double-click or "Open With › Reader".
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenQueue.shared.add(urls)
        // With no window, nothing takes the queue; the start window opens and takes it.
        if !NSApp.windows.contains(where: \.isVisible),
           let item = NSApp.windowsMenu?.items.first(where: { $0.title == "Reader" }),
           let menu = item.menu {
            menu.performActionForItem(at: menu.index(of: item))
        }
    }
}

/// Opens the queued PDFs. Every window uses it, so the files open from whichever window is visible.
struct OpenQueueHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    private let queue = OpenQueue.shared

    func body(content: Content) -> some View {
        content.onChange(of: queue.pending, initial: true) {
            for url in queue.takeAll() { openWindow(id: "reader", value: url) }
        }
    }
}

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library(paths: Self.dataRootOverride)

    /// Debug builds can use another data folder (READER_DATA_ROOT), so a self-test does not touch real data.
    private static var dataRootOverride: AppPaths? {
        #if DEBUG
        ProcessInfo.processInfo.environment["READER_DATA_ROOT"].map { AppPaths(root: URL(fileURLWithPath: $0)) }
        #else
        nil
        #endif
    }

    var body: some Scene {
        Window("Reader", id: "library") {
            LibraryView(library: library)
                .modifier(OpenQueueHandler())
        }
        .keyboardShortcut("0")
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) { OpenPDFCommand() }
        }

        WindowGroup(id: "reader", for: URL.self) { $url in
            if let url {
                ReaderWindow(url: url, library: library)
                    .modifier(OpenQueueHandler())
            }
        }
        .defaultSize(width: 1400, height: 950)

        Settings {
            SettingsView()
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
