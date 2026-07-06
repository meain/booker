import AppKit
import SwiftUI

/// Borderless windows can't become key by default; allow it so the search
/// field can take keyboard focus.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let state: AppState
    private var monitor: Any?

    init(initialQuery: String) {
        self.state = AppState(initialQuery: initialQuery)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = PickerView(state: state)
        let hosting = NSHostingView(rootView: content)

        window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        positionWindow()
        installKeyMonitor()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Debug helper: BOOKER_SHOT=/path renders the window to a PNG and exits.
        if let shot = ProcessInfo.processInfo.environment["BOOKER_SHOT"] {
            let delay = Double(ProcessInfo.processInfo.environment["BOOKER_SHOT_DELAY"] ?? "0.7") ?? 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let view = self.window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: shot))
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Center the window on the screen that currently has the mouse.
    private func positionWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            let ctrl = event.modifierFlags.contains(.control)

            switch event.keyCode {
            case 36, 76:                 // Return / Enter
                self.state.activate(copy: cmd)
                return nil
            case 53:                     // Escape
                self.state.cancel()
                return nil
            case 125:                    // Down arrow
                self.state.moveDown()
                return nil
            case 126:                    // Up arrow
                self.state.moveUp()
                return nil
            case 45 where ctrl:          // Ctrl-n
                self.state.moveDown()
                return nil
            case 35 where ctrl:          // Ctrl-p
                self.state.moveUp()
                return nil
            default:
                return event
            }
        }
    }
}

// Headless mode for debugging/scripting: `booker list` dumps the parsed
// bookmarks as `url<TAB>title | tags | aliases` without opening a window.
if CommandLine.arguments.dropFirst().first == "list" {
    for bm in BookmarkParser.load() {
        let tags = bm.tags.map { "#\($0)" }.joined(separator: " ")
        let aliases = bm.aliases.map { "@\($0)" }.joined(separator: " ")
        print("\(bm.url)\t\(bm.title) | \(tags) | \(aliases)")
    }
    exit(0)
}

// `booker rank <query>` prints the ranked results for a query (debug/scripting).
if CommandLine.arguments.dropFirst().first == "rank" {
    let query = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    let ranked = Matcher.rank(BookmarkParser.load(), query: query, frecency: Frecency())
    for bm in ranked {
        let meta = (bm.aliases.map { "@\($0)" } + bm.tags.map { "#\($0)" }).joined(separator: " ")
        print("\(bm.title)\t\(meta)")
    }
    exit(0)
}

// Any remaining args become the initial search query (like `,bm open <term>`).
let initialQuery = CommandLine.arguments.dropFirst().joined(separator: " ")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; still shows a key window
let delegate = AppDelegate(initialQuery: initialQuery)
app.delegate = delegate
app.run()
