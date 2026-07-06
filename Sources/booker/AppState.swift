import AppKit
import SwiftUI

/// Drives the picker: holds the bookmark list, the current query/results, the
/// selection, and the "enter a %s parameter" sub-mode.
final class AppState: ObservableObject {
    private let bookmarks: [Bookmark]
    private let frecency: Frecency

    @Published var query: String = ""
    @Published private(set) var results: [Bookmark] = []
    @Published var selected: Int = 0

    // %s parameter sub-mode.
    @Published private(set) var paramMode: Bool = false
    private var pendingBookmark: Bookmark?

    // Favicons.
    let favicons = FaviconStore()

    // Settings.
    @Published var showSettings: Bool = false
    @Published private(set) var frecencyCleared: Bool = false
    @Published private(set) var faviconsCleared: Bool = false
    private static let searchInLinksKey = "searchInLinks"
    private static let showFaviconsKey = "showFavicons"
    @Published var searchInLinks: Bool {
        didSet { UserDefaults.standard.set(searchInLinks, forKey: Self.searchInLinksKey) }
    }
    @Published var showFavicons: Bool {
        didSet { UserDefaults.standard.set(showFavicons, forKey: Self.showFaviconsKey) }
    }

    init(initialQuery: String = "") {
        self.bookmarks = BookmarkParser.load()
        self.frecency = Frecency()
        // Default the toggles to on when unset.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.searchInLinksKey) == nil {
            defaults.set(true, forKey: Self.searchInLinksKey)
        }
        if defaults.object(forKey: Self.showFaviconsKey) == nil {
            defaults.set(true, forKey: Self.showFaviconsKey)
        }
        self.searchInLinks = defaults.bool(forKey: Self.searchInLinksKey)
        self.showFavicons = defaults.bool(forKey: Self.showFaviconsKey)
        self.query = initialQuery
        refilter()
    }

    var placeholder: String {
        if paramMode, let bm = pendingBookmark {
            return "Parameter for \(bm.title)…"
        }
        return "Search  ·  @alias  ·  #tag"
    }

    /// Recomputes results for the current query. Called from the view's
    /// `.onChange(of:)` — NOT from a `didSet`, which would mutate published
    /// state mid-view-update and leave the list rendering stale.
    func refilter() {
        guard !paramMode else { return }   // in param mode the query holds the %s value
        results = Matcher.rank(bookmarks, query: query, frecency: frecency, searchInLinks: searchInLinks)
        selected = 0
        loadVisibleFavicons()
    }

    /// Kick off favicon loads for the current results (no-op when disabled or
    /// already cached/in-flight).
    func loadVisibleFavicons() {
        guard showFavicons else { return }
        for bm in results { favicons.load(forURL: bm.url) }
    }

    // MARK: - Settings

    func toggleSettings() {
        if showSettings {
            closeSettings()
        } else {
            showSettings = true
        }
    }

    func closeSettings() {
        showSettings = false
        frecencyCleared = false
        faviconsCleared = false
        refilter()   // pick up any changed toggle
    }

    /// Called when the search-in-links toggle flips (from the view's onChange).
    func searchInLinksChanged() {
        refilter()
    }

    func resetFrecency() {
        frecency.reset()
        frecencyCleared = true
        refilter()
    }

    func clearFaviconCache() {
        favicons.clearCache()
        faviconsCleared = true
    }

    // MARK: - Navigation

    func moveDown() {
        guard !results.isEmpty else { return }
        selected = min(selected + 1, results.count - 1)
    }

    func moveUp() {
        guard !results.isEmpty else { return }
        selected = max(selected - 1, 0)
    }

    // MARK: - Actions

    /// Enter pressed. Opens (or copies) the selected bookmark, handling %s params.
    func activate(copy: Bool) {
        if paramMode {
            guard let bm = pendingBookmark else { return }
            let filled = bm.url.replacingOccurrences(of: "%s", with: query)
            finish(url: filled, sourceURL: bm.url, copy: copy)
            return
        }

        guard results.indices.contains(selected) else { return }
        let bm = results[selected]

        if bm.needsParam {
            // Switch to parameter-entry mode instead of opening immediately.
            pendingBookmark = bm
            paramMode = true
            query = ""
            return
        }

        finish(url: bm.url, sourceURL: bm.url, copy: copy)
    }

    private func finish(url: String, sourceURL: String, copy: Bool) {
        frecency.record(url: sourceURL)
        if copy {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(url, forType: .string)
        } else if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
        NSApp.terminate(nil)
    }

    /// Escape pressed. Closes settings, backs out of param mode, or quits.
    func cancel() {
        if showSettings {
            closeSettings()
        } else if paramMode {
            paramMode = false
            pendingBookmark = nil
            query = ""
            refilter()
        } else {
            NSApp.terminate(nil)
        }
    }
}
