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
    private let state = AppState()
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = PickerView(state: state)
        let hosting = NSHostingView(rootView: content)

        window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
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
    }

    /// Place the window centered horizontally, in the upper third of the
    /// screen that currently has the mouse.
    private func positionWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY + frame.height * 0.12
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; still shows a key window
let delegate = AppDelegate()
app.delegate = delegate
app.run()
