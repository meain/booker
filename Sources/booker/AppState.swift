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

    init(initialQuery: String = "") {
        self.bookmarks = BookmarkParser.load()
        self.frecency = Frecency()
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
        results = Matcher.rank(bookmarks, query: query, frecency: frecency)
        selected = 0
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

    /// Escape pressed. Backs out of param mode, or quits.
    func cancel() {
        if paramMode {
            paramMode = false
            pendingBookmark = nil
            query = ""
            refilter()
        } else {
            NSApp.terminate(nil)
        }
    }
}
