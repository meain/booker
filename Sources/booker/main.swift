import AppKit
import Combine
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
    private var cancellables = Set<AnyCancellable>()
    /// Picker frame to restore after an overlay (settings/form) closes.
    private var savedPickerFrame: NSRect?
    private let settingsSize = NSSize(width: 640, height: 500)
    private let formWidth: CGFloat = 600

    init(initialQuery: String) {
        self.state = AppState(initialQuery: initialQuery)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shotMode = ProcessInfo.processInfo.environment["BOOKER_SHOT"] != nil
        let content = PickerView(state: state, favicons: state.favicons, screenshotMode: shotMode)
        let hosting = NSHostingView(rootView: content)

        window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true  // drag anywhere to move
        window.minSize = NSSize(width: 360, height: 160)

        // Restore the last size/position; center only on the very first launch.
        // The autosave name persists frame changes to UserDefaults automatically.
        let autosave = NSWindow.FrameAutosaveName("BookerMain")
        if !window.setFrameUsingName(autosave) {
            positionWindow()
        }
        window.setFrameAutosaveName(autosave)

        installEditMenu()
        installKeyMonitor()
        observeOverlaySize()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Debug helper: BOOKER_SHOT=/path renders the window to a PNG and exits.
        if let shot = ProcessInfo.processInfo.environment["BOOKER_SHOT"] {
            // Force light appearance so the solid screenshot background is light.
            window.appearance = NSAppearance(named: .aqua)
            let delay = Double(ProcessInfo.processInfo.environment["BOOKER_SHOT_DELAY"] ?? "0.7") ?? 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let view = self.window.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                {
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

    /// Resize the window when opening settings (default size) or the add/edit
    /// form (exact fitted height); restore the picker size when both close.
    private func observeOverlaySize() {
        state.$showSettings.combineLatest(state.$showForm, state.$formHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] settings, form, formHeight in
                self?.applyOverlaySize(settings: settings, form: form, formHeight: formHeight)
            }
            .store(in: &cancellables)
    }

    private func applyOverlaySize(settings: Bool, form: Bool, formHeight: CGFloat) {
        if form || settings {
            if savedPickerFrame == nil { savedPickerFrame = window.frame }
            let size: NSSize
            if form {
                size = NSSize(width: formWidth, height: formHeight > 0 ? ceil(formHeight) : 360)
            } else {
                size = settingsSize
            }
            // Anchor the top edge and horizontal center so it grows downward.
            let top = window.frame.maxY
            let cx = window.frame.midX
            let origin = NSPoint(x: cx - size.width / 2, y: top - size.height)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        } else if let f = savedPickerFrame {
            window.setFrame(f, display: true)
            savedPickerFrame = nil
        }
    }

    /// A bare NSApplication has no menu, so the standard editing key equivalents
    /// (⌘V/⌘C/⌘X/⌘A/⌘Z) don't reach text fields. Provide a minimal Edit menu.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    private func installKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            let ctrl = event.modifierFlags.contains(.control)

            // In the add/edit form, only Escape is intercepted; SwiftUI handles
            // typing, Tab, and the ⌘↩ Save shortcut.
            if self.state.showForm {
                if event.keyCode == 53 { self.state.cancel(); return nil }  // Escape
                return event
            }
            // ⌘, toggles settings from anywhere.
            if cmd && event.keyCode == 43 {
                self.state.toggleSettings()
                return nil
            }
            // While settings are open, only Escape is intercepted; let SwiftUI
            // handle the toggle/button/tab interactions.
            if self.state.showSettings {
                if event.keyCode == 53 {  // Escape
                    self.state.cancel()
                    return nil
                }
                return event
            }
            // ⌘N add, ⌘E edit selected, ⌘⌫ delete selected.
            if cmd && event.keyCode == 45 { self.state.openAddForm(seed: self.state.query); return nil }
            if cmd && event.keyCode == 14 { self.state.openEditForm(); return nil }
            if cmd && event.keyCode == 51 { self.state.requestDeleteSelected(); return nil }

            switch event.keyCode {
            case 36, 76:  // Return / Enter
                self.state.activate(copy: cmd)
                return nil
            case 53:  // Escape
                self.state.cancel()
                return nil
            case 125:  // Down arrow
                self.state.moveDown()
                return nil
            case 126:  // Up arrow
                self.state.moveUp()
                return nil
            case 45 where ctrl:  // Ctrl-n
                self.state.moveDown()
                return nil
            case 35 where ctrl:  // Ctrl-p
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
// Honors the persisted searchInLinks setting; override with BOOKER_SEARCH_LINKS=0/1.
if CommandLine.arguments.dropFirst().first == "rank" {
    let query = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    let searchInLinks: Bool
    if let e = ProcessInfo.processInfo.environment["BOOKER_SEARCH_LINKS"] {
        searchInLinks = (e != "0")
    } else {
        searchInLinks = UserDefaults.standard.object(forKey: "searchInLinks") as? Bool ?? true
    }
    let ranked = Matcher.rank(BookmarkParser.load(), query: query, frecency: Frecency(), searchInLinks: searchInLinks)
    for r in ranked {
        let bm = r.bookmark
        let meta = (bm.aliases.map { "@\($0)" } + bm.tags.map { "#\($0)" }).joined(separator: " ")
        let url = r.param.map { bm.url.replacingOccurrences(of: "%s", with: $0) } ?? bm.url
        print("\(bm.title)\t\(meta)\t\(url)")
    }
    exit(0)
}

// Any remaining args become the initial search query (like `,bm open <term>`).
let initialQuery = CommandLine.arguments.dropFirst().joined(separator: " ")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon; still shows a key window
let delegate = AppDelegate(initialQuery: initialQuery)
app.delegate = delegate
app.run()
