import AppKit
import SwiftUI

/// Initial values seeded into BookmarkFormView when it opens.
struct FormSeed {
    var url: String
    var title: String
    var tags: String
    var aliases: String

    static let empty = FormSeed(url: "", title: "", tags: "", aliases: "")
}

/// A row in the results list: a matched bookmark, an "open all" group for a
/// shared alias, or an "add this URL" affordance.
enum ResultRow: Identifiable {
    case bookmark(MatchResult)
    case openAll(alias: String, bookmarks: [Bookmark])
    case add(query: String)

    var id: String {
        switch self {
        case .bookmark(let m): return "bm:\(m.bookmark.id)"
        case .openAll(let a, _): return "all:\(a)"
        case .add: return "add"
        }
    }
}

/// Drives the picker: holds the bookmark list, the current query/results, the
/// selection, and the "enter a %s parameter" sub-mode.
final class AppState: ObservableObject {
    private var bookmarks: [Bookmark]
    private let frecency: Frecency

    @Published var query: String = ""
    @Published private(set) var results: [ResultRow] = []
    @Published var selected: Int = 0

    // %s parameter sub-mode.
    @Published private(set) var paramMode: Bool = false
    private var pendingBookmark: Bookmark?

    // Add/edit form.
    @Published var showForm: Bool = false
    /// Seed values populated when the form opens; read once by BookmarkFormView on appear.
    private(set) var formSeed: FormSeed = .empty
    /// File line being edited; nil means a new bookmark (append).
    private(set) var editingLine: Int?

    // Delete confirmation: id of the bookmark awaiting a confirm keypress.
    @Published var pendingDeleteID: Int?

    // Measured natural height of the add/edit form, so the window can fit it.
    @Published var formHeight: CGFloat = 0

    // Error banner: set when a file write fails, cleared after display.
    @Published var errorMessage: String? = nil

    // Favicons.
    let favicons = FaviconStore()

    // Settings.
    @Published var showSettings: Bool = false
    @Published private(set) var frecencyCleared: Bool = false
    @Published private(set) var faviconsCleared: Bool = false
    private static let searchInLinksKey = "searchInLinks"
    private static let showFaviconsKey = "showFavicons"
    private static let highlightColorKey = "highlightColorHex"
    static let defaultHighlightHex = "#808080"
    /// Hex of the grey (default) highlight behind matched text in results.
    @Published var highlightColorHex: String {
        didSet { UserDefaults.standard.set(highlightColorHex, forKey: Self.highlightColorKey) }
    }
    @Published var searchInLinks: Bool {
        didSet { UserDefaults.standard.set(searchInLinks, forKey: Self.searchInLinksKey) }
    }
    @Published var showFavicons: Bool {
        didSet { UserDefaults.standard.set(showFavicons, forKey: Self.showFaviconsKey) }
    }
    /// The bookmarks file path shown in settings (resolves to the effective path).
    @Published var bookmarkFilePath: String = ""
    @Published private(set) var bookmarkCount: Int = 0

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
        self.highlightColorHex = defaults.string(forKey: Self.highlightColorKey) ?? Self.defaultHighlightHex
        // Show the stored path, or the resolved effective path if unset.
        self.bookmarkFilePath = defaults.string(forKey: BookmarkParser.fileDefaultsKey) ?? BookmarkParser.filePath
        self.bookmarkCount = bookmarks.count
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
        guard !paramMode else { return }  // in param mode the query holds the %s value
        pendingDeleteID = nil
        let matches = Matcher.rank(bookmarks, query: query, frecency: frecency, searchInLinks: searchInLinks)

        var rows: [ResultRow] = matches.map { .bookmark($0) }
        // "Open all" row when the query is an exact alias shared by ≥2 bookmarks.
        if let group = sharedAliasGroup() {
            rows.insert(.openAll(alias: group.alias, bookmarks: group.bookmarks), at: 0)
        }
        // "Add" row when a URL-looking query matches nothing.
        if matches.isEmpty && looksLikeURL(query) {
            rows = [.add(query: query.trimmingCharacters(in: .whitespaces))]
        }
        results = rows
        selected = 0
        loadVisibleFavicons()
    }

    /// The bookmark currently highlighted, if the selected row is a bookmark.
    var selectedBookmark: Bookmark? {
        guard results.indices.contains(selected),
            case .bookmark(let m) = results[selected]
        else { return nil }
        return m.bookmark
    }

    private func looksLikeURL(_ q: String) -> Bool {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    /// If the query is exactly an alias used by ≥2 bookmarks, returns them.
    private func sharedAliasGroup() -> (alias: String, bookmarks: [Bookmark])? {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        guard !q.isEmpty else { return nil }
        let qc = Array(q)
        let matches = bookmarks.filter { $0.aliasKeys.contains { $0.chars == qc } }
        return matches.count >= 2 ? (q, matches) : nil
    }

    /// Kick off favicon loads for the current results (no-op when disabled or
    /// already cached/in-flight).
    func loadVisibleFavicons() {
        guard showFavicons else { return }
        for r in results {
            switch r {
            case .bookmark(let m): favicons.load(forURL: m.bookmark.url)
            case .openAll(_, let bms): bms.forEach { favicons.load(forURL: $0.url) }
            case .add: break
            }
        }
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
        refilter()  // pick up any changed toggle
    }

    /// Called when the search-in-links toggle flips (from the view's onChange).
    func searchInLinksChanged() {
        refilter()
    }

    /// Persist a new bookmarks file path and reload. Empty resets to the default.
    func setBookmarkFile(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        bookmarkFilePath = trimmed.isEmpty ? BookmarkParser.filePath : trimmed
        UserDefaults.standard.set(trimmed, forKey: BookmarkParser.fileDefaultsKey)
        reloadBookmarks()
    }

    private func reloadBookmarks() {
        bookmarks = BookmarkParser.load()
        bookmarkCount = bookmarks.count
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
        pendingDeleteID = nil
        guard !results.isEmpty else { return }
        selected = min(selected + 1, results.count - 1)
    }

    func moveUp() {
        pendingDeleteID = nil
        guard !results.isEmpty else { return }
        selected = max(selected - 1, 0)
    }

    // MARK: - Actions

    /// Substitute a %s value into a URL, percent-encoding it so spaces / reserved
    /// characters don't break the URL (the %s may sit in a path or a query value).
    static func fill(_ url: String, param: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/ ")
        let encoded = param.addingPercentEncoding(withAllowedCharacters: allowed) ?? param
        return url.replacingOccurrences(of: "%s", with: encoded)
    }

    /// Enter pressed. Opens (or copies) the selected bookmark, handling %s params.
    func activate(copy: Bool) {
        if paramMode {
            guard let bm = pendingBookmark else { return }
            finish(url: Self.fill(bm.url, param: query), title: bm.title, sourceURL: bm.url, copy: copy)
            return
        }

        // A pending delete is confirmed by the next Enter.
        if pendingDeleteID != nil {
            confirmDelete()
            return
        }

        guard results.indices.contains(selected) else { return }
        switch results[selected] {
        case .add(let q):
            openAddForm(seed: q)
        case .openAll(_, let bms):
            openAll(bms, copy: copy)
        case .bookmark(let result):
            let bm = result.bookmark
            if let param = result.param {
                // Inline "@alias value" — value already supplied, open directly.
                finish(url: Self.fill(bm.url, param: param), title: bm.title, sourceURL: bm.url, copy: copy)
            } else if bm.needsParam {
                // Switch to parameter-entry mode instead of opening immediately.
                pendingBookmark = bm
                paramMode = true
                query = ""
            } else {
                finish(url: bm.url, title: bm.title, sourceURL: bm.url, copy: copy)
            }
        }
    }

    /// Open every bookmark in a shared-alias group (skips %s ones), then quit.
    private func openAll(_ bms: [Bookmark], copy: Bool) {
        let usable = bms.filter { !$0.needsParam }
        if copy {
            let pb = NSPasteboard.general
            pb.clearContents()
            let html = usable.map { Self.htmlLink(url: $0.url, title: $0.title) }.joined(separator: "<br>")
            pb.setString(html, forType: .html)
            pb.setString(usable.map { $0.url }.joined(separator: "\n"), forType: .string)
        } else {
            for bm in usable {
                frecency.record(url: bm.url)
                if let url = URL(string: bm.url) { NSWorkspace.shared.open(url) }
            }
        }
        NSApp.terminate(nil)
    }

    private func finish(url: String, title: String, sourceURL: String, copy: Bool) {
        frecency.record(url: sourceURL)
        if copy {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Self.htmlLink(url: url, title: title), forType: .html)
            pb.setString(url, forType: .string)
        } else if let u = URL(string: url)
            ?? url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        {
            NSWorkspace.shared.open(u)
        }
        NSApp.terminate(nil)
    }

    /// Builds an `<a>` tag for the HTML pasteboard representation so pasting
    /// into rich-text targets (Mail, Notes, Teams, …) yields a titled link.
    private static func htmlLink(url: String, title: String) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        return "<a href=\"\(escape(url))\">\(escape(title))</a>"
    }

    /// Escape pressed. Backs out of whatever mode is active, else quits.
    func cancel() {
        if showForm {
            closeForm()
        } else if pendingDeleteID != nil {
            pendingDeleteID = nil
        } else if showSettings {
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

    // MARK: - Navigation overrides for delete-confirm

    func cancelPendingDelete() { pendingDeleteID = nil }

    // MARK: - Add / edit / delete

    /// Open the add form. If `seed` looks like a URL it fills the URL field,
    /// otherwise the title field (per the query-seeding rule).
    func openAddForm(seed: String = "") {
        editingLine = nil
        let s = seed.trimmingCharacters(in: .whitespaces)
        if looksLikeURL(s) {
            formSeed = FormSeed(url: s, title: "", tags: "", aliases: "")
        } else {
            formSeed = FormSeed(url: "", title: s, tags: "", aliases: "")
        }
        showForm = true
    }

    /// Open the form pre-filled to edit the selected bookmark.
    func openEditForm() {
        guard let bm = selectedBookmark else { return }
        editingLine = bm.line
        formSeed = FormSeed(
            url: bm.url,
            title: bm.title,
            tags: bm.tags.joined(separator: " "),
            aliases: bm.aliases.joined(separator: " "))
        showForm = true
    }

    var isEditing: Bool { editingLine != nil }

    func closeForm() {
        showForm = false
        refilter()
    }

    /// Existing bookmark with this exact URL (for the dedupe warning).
    func existingBookmark(url: String) -> Bookmark? {
        let u = url.trimmingCharacters(in: .whitespaces)
        return bookmarks.first { $0.url == u && $0.line != editingLine }
    }

    /// Most-used tags among bookmarks sharing the URL's host (suggestions).
    func suggestedTags(url: String) -> [String] {
        guard let host = FaviconStore.host(url) else { return [] }
        var counts: [String: Int] = [:]
        for bm in bookmarks where bm.url.contains(host) {
            for t in bm.tags { counts[t, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    /// Aliases already used by other bookmarks (for the collision warning).
    func aliasesInUse(_ aliases: [String]) -> [String] {
        let others = Set(bookmarks.filter { $0.line != editingLine }.flatMap { $0.aliases.map { $0.lowercased() } })
        return aliases.filter { others.contains($0.lowercased()) }
    }

    /// Save the form. Title and URL are required. Appends, or rewrites the line
    /// when editing. Returns false if invalid.
    @discardableResult
    func saveBookmark(
        url formURL: String, title formTitle: String, tags formTags: String,
        aliases formAliases: String, generate formGenerate: Bool, genEnabled: Set<String>
    ) -> Bool {
        let title = formTitle.trimmingCharacters(in: .whitespaces)
        let url = formURL.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !url.isEmpty else { return false }
        let tags = formTags.split(separator: " ").map { $0.replacingOccurrences(of: "#", with: "") }
        let aliases = formAliases.split(separator: " ").map { $0.replacingOccurrences(of: "@", with: "") }
        let line = BookmarkParser.format(title: title, url: url, tags: tags, aliases: aliases)

        let canGenerateShortcuts = !isEditing && Github.repoSlug(url) != nil
        let baseAlias = formAliases.split(separator: " ").first
            .map { $0.replacingOccurrences(of: "@", with: "") }
            .flatMap { $0.isEmpty ? nil : $0 }

        func generatedLines() -> [String] {
            guard formGenerate, canGenerateShortcuts,
                let slug = Github.repoSlug(url), let base = baseAlias
            else { return [] }
            let repoURL = "https://github.com/\(slug)"
            return Github.shortcuts
                .filter { genEnabled.contains($0.aliasSuffix) }
                .map { sc in
                    BookmarkParser.format(
                        title: "\(title) · \(sc.titleSuffix)",
                        url: repoURL + sc.path,
                        tags: tags,
                        aliases: [base + sc.aliasSuffix])
                }
        }

        do {
            if let editingLine = editingLine {
                try BookmarkParser.replaceLine(at: editingLine, with: line)
            } else {
                try BookmarkParser.append(line)
                for extra in generatedLines() {
                    try BookmarkParser.append(extra)
                }
            }
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return false
        }
        if editingLine == nil {
            NSApp.terminate(nil)
        }
        showForm = false
        query = ""
        reloadBookmarks()
        return true
    }

    /// First ⌘⌫ arms the confirm; the actual delete happens on confirm.
    func requestDeleteSelected() {
        guard let bm = selectedBookmark else { return }
        pendingDeleteID = bm.id
    }

    func confirmDelete() {
        guard let id = pendingDeleteID,
            let bm = bookmarks.first(where: { $0.id == id })
        else { return }
        pendingDeleteID = nil
        do {
            try BookmarkParser.deleteLine(at: bm.line)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return
        }
        reloadBookmarks()
    }
}
