import AppKit
import SwiftUI

/// Where the format documentation lives (opened from settings).
let formatDocsURL = "https://github.com/meain/booker/blob/main/docs/format.md"

extension Color {
    init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

struct PickerView: View {
    @ObservedObject var state: AppState
    @ObservedObject var favicons: FaviconStore
    /// Offscreen PNG capture can't render the behind-window blur, so use a solid
    /// window-background color for screenshots instead of the translucent effect.
    var screenshotMode: Bool = false
    @FocusState private var searchFocused: Bool

    /// Query words (minus any @/# scope prefix) used to highlight matches in rows.
    private var matchTokens: [String] {
        var q = state.query.trimmingCharacters(in: .whitespaces)
        if q.hasPrefix("@") || q.hasPrefix("#") { q.removeFirst() }
        return q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Group {
            if state.showForm {
                BookmarkFormView(state: state)
            } else if state.showSettings {
                SettingsView(state: state)
            } else {
                VStack(spacing: 0) {
                    searchField
                    Divider()
                    resultsList
                }
                .onChange(of: state.query) { _ in state.refilter() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if screenshotMode {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffect()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: state.paramMode ? "chevron.right.circle" : "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))
            TextField(state.placeholder, text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
                .onAppear { searchFocused = true }
            Button(action: { state.toggleSettings() }) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if state.paramMode {
                        Text("Press Enter to open · ⌘Enter to copy")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    } else if state.results.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(state.results.enumerated()), id: \.element.id) { idx, row in
                            resultRow(row, idx: idx)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.selected = idx
                                    state.activate(copy: false)
                                }
                        }
                    }
                }
                .padding(6)
                .overlay(alignment: .topLeading) {
                    AlwaysOnScroller().frame(width: 0, height: 0)
                }
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: state.selected) { newValue in
                guard state.results.indices.contains(newValue) else { return }
                let targetID = state.results[newValue].id
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ row: ResultRow, idx: Int) -> some View {
        let sel = idx == state.selected
        switch row {
        case .bookmark(let m):
            Row(bookmark: m.bookmark,
                param: m.param,
                selected: sel,
                showFavicon: state.showFavicons,
                favicon: state.showFavicons ? favicons.image(forURL: m.bookmark.url) : nil,
                matchTokens: matchTokens,
                highlightColor: Color(hex: state.highlightColorHex) ?? .gray,
                pendingDelete: state.pendingDeleteID == m.bookmark.id)
        case .openAll(let alias, let bms):
            ActionRow(icon: "square.on.square",
                      title: "Open all \(bms.filter { !$0.needsParam }.count) · @\(alias)",
                      subtitle: bms.map { $0.title }.joined(separator: " · "),
                      selected: sel)
        case .add(let q):
            ActionRow(icon: "plus.circle",
                      title: "Add bookmark",
                      subtitle: q,
                      selected: sel)
        }
    }
}

private struct Row: View {
    let bookmark: Bookmark
    var param: String? = nil
    let selected: Bool
    var showFavicon: Bool = false
    var favicon: NSImage? = nil
    var matchTokens: [String] = []
    var highlightColor: Color = .gray
    var pendingDelete: Bool = false

    private var light: Bool { selected || pendingDelete }

    /// URL without the scheme, for a cleaner secondary line. When an inline
    /// param is present the %s is filled in so the row shows the real target.
    private var displayURL: String {
        var u = param.map { bookmark.url.replacingOccurrences(of: "%s", with: $0) } ?? bookmark.url
        for prefix in ["https://", "http://"] where u.hasPrefix(prefix) {
            u.removeFirst(prefix.count)
        }
        return u
    }

    /// Text with a subtle grey highlight behind each case-insensitive match of
    /// the query words.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !matchTokens.isEmpty else { return attr }
        let color = selected ? Color.white.opacity(0.30) : highlightColor.opacity(0.55)
        for token in matchTokens {
            var start = text.startIndex
            while let r = text.range(of: token, options: .caseInsensitive, range: start..<text.endIndex) {
                if let lo = AttributedString.Index(r.lowerBound, within: attr),
                   let hi = AttributedString.Index(r.upperBound, within: attr) {
                    attr[lo..<hi].backgroundColor = color
                }
                if r.upperBound == text.endIndex { break }
                start = r.upperBound
            }
        }
        return attr
    }

    @ViewBuilder private var faviconView: some View {
        if let favicon = favicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary)
                .frame(width: 16, height: 16)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if showFavicon {
                faviconView
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(bookmark.title))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 14))
                    .foregroundStyle(light ? Color.white : Color.primary)
                Text(highlighted(displayURL))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 11))
                    .foregroundStyle(light ? Color.white.opacity(0.85) : Color.secondary)
            }

            Spacer(minLength: 8)

            if pendingDelete {
                Text("Delete?  ↩ confirm · esc cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                ForEach(bookmark.aliases, id: \.self) { alias in
                    Text("@\(alias)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected ? Color.white : Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.orange.opacity(selected ? 0.45 : 0.18))
                        )
                }
                ForEach(bookmark.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(pendingDelete ? Color.red.opacity(0.9) : (selected ? Color.accentColor : Color.clear))
        )
    }
}

/// A non-bookmark action row (e.g. "Open all …", "Add bookmark").
private struct ActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor : Color.clear)
        )
    }
}

private struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var editPath: String = ""

    private var highlightBinding: Binding<Color> {
        Binding(get: { Color(hex: state.highlightColorHex) ?? .gray },
                set: { state.highlightColorHex = $0.hexString })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("⌘,  or  Esc to close")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            ScrollView {
              VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmarks file")
                        .font(.system(size: 14))
                    Text("\(state.bookmarkCount) bookmarks loaded · leave empty to use $BM_FILE or the default")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("~/.local/share/bookmarks.md", text: $editPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { apply() }
                        Button("Choose…") { chooseFile() }
                        Button("Apply") { apply() }
                    }
                }

                Divider()

                Toggle(isOn: $state.searchInLinks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search in links")
                            .font(.system(size: 14))
                        Text("Also match the URL, not just title, tags, and aliases")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: state.searchInLinks) { _ in state.searchInLinksChanged() }

                Divider()

                Toggle(isOn: $state.showFavicons) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show favicons")
                            .font(.system(size: 14))
                        Text("Fetch and cache each site's icon (cached at ~/.local/share/booker/favicons)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: state.showFavicons) { _ in state.loadVisibleFavicons() }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match highlight color")
                            .font(.system(size: 14))
                        Text("Behind matched text in results")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ColorPicker("", selection: highlightBinding, supportsOpacity: false)
                        .labelsHidden()
                    Button("Reset") { state.highlightColorHex = AppState.defaultHighlightHex }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frecency index")
                            .font(.system(size: 14))
                        Text("Usage ranking stored at ~/.local/share/booker/frecency.json")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { state.resetFrecency() }) {
                        Text(state.frecencyCleared ? "Cleared ✓" : "Reset")
                    }
                    .disabled(state.frecencyCleared)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favicon cache")
                            .font(.system(size: 14))
                        Text("Remove all cached icons; they re-download on next use")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { state.clearFaviconCache() }) {
                        Text(state.faviconsCleared ? "Cleared ✓" : "Clear")
                    }
                    .disabled(state.faviconsCleared)
                }

                Divider()

                Button(action: { openDocs() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                        Text("Bookmark file format & search syntax")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(.link)
              }
              .padding(16)
            }
        }
        .onAppear { editPath = state.bookmarkFilePath }
    }

    private func apply() {
        state.setBookmarkFile(editPath)
        editPath = state.bookmarkFilePath
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !editPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (editPath as NSString).expandingTildeInPath)
                .deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            editPath = url.path
            apply()
        }
    }

    private func openDocs() {
        if let u = URL(string: formatDocsURL) { NSWorkspace.shared.open(u) }
    }
}

/// Add / edit a bookmark. Same panel for both; save appends or rewrites a line.
private struct BookmarkFormView: View {
    @ObservedObject var state: AppState
    @FocusState private var focus: Field?
    @State private var dupTitle: String?
    @State private var aliasWarning: String?
    @State private var fetching = false
    @State private var debounce: DispatchWorkItem?

    private enum Field { case url, title, tags, aliases }

    private var canSave: Bool {
        !state.formURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.formTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: state.isEditing ? "pencil" : "plus.circle")
                    .foregroundStyle(.secondary)
                Text(state.isEditing ? "Edit bookmark" : "Add bookmark")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("⌘↩ save · esc cancel")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                labeled("URL") {
                    HStack(spacing: 6) {
                        if let img = state.favicons.image(forURL: state.formURL) {
                            Image(nsImage: img).resizable().interpolation(.high)
                                .frame(width: 16, height: 16)
                        }
                        field("https://…", text: $state.formURL, field: .url)
                    }
                }
                if let dup = dupTitle { warn("Already saved as “\(dup)”") }

                labeled("Title") {
                    field(fetching ? "Fetching title…" : "Page title", text: $state.formTitle, field: .title)
                }
                labeled("Tags") {
                    field("space separated", text: $state.formTags, field: .tags)
                }
                labeled("Aliases") {
                    field("optional, space separated", text: $state.formAliases, field: .aliases)
                }
                if let aw = aliasWarning { warn(aw) }

                HStack {
                    Spacer()
                    Button(state.isEditing ? "Save" : "Add") { state.saveBookmark() }
                        .controlSize(.large)
                        .disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(16)
        }
        .background(GeometryReader { g -> Color in
            let h = g.size.height
            DispatchQueue.main.async {
                if abs(state.formHeight - h) > 0.5 { state.formHeight = h }
            }
            return Color.clear
        })
        .onAppear {
            evaluate()
            updateAliasWarning()
            // Focus after the fields are mounted, else the first responder
            // doesn't take and keystrokes are dropped.
            DispatchQueue.main.async { focus = state.formURL.isEmpty ? .url : .title }
        }
        .onChange(of: state.formURL) { _ in scheduleEvaluate() }
        .onChange(of: state.formAliases) { _ in updateAliasWarning() }
    }

    private func field(_ prompt: String, text: Binding<String>, field: Field) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .font(.system(size: 14))
            .focused($focus, equals: field)
    }

    @ViewBuilder private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            content()
        }
    }

    private func warn(_ msg: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(msg)
        }
        .font(.system(size: 12))
        .foregroundStyle(.orange)
    }

    private func scheduleEvaluate() {
        debounce?.cancel()
        let work = DispatchWorkItem { evaluate() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func evaluate() {
        let url = state.formURL.trimmingCharacters(in: .whitespaces)
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { dupTitle = nil; return }
        dupTitle = state.existingBookmark(url: url)?.title
        state.favicons.load(forURL: url)
        if state.formTags.trimmingCharacters(in: .whitespaces).isEmpty {
            let sug = state.suggestedTags(url: url)
            if !sug.isEmpty { state.formTags = sug.joined(separator: " ") }
        }
        if state.formTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            fetchTitle(url)
        }
    }

    private func updateAliasWarning() {
        let aliases = state.formAliases.split(separator: " ").map { $0.replacingOccurrences(of: "@", with: "") }
        let used = state.aliasesInUse(aliases)
        aliasWarning = used.isEmpty ? nil
            : "\(used.map { "@\($0)" }.joined(separator: ", ")) already used — will open together"
    }

    private func fetchTitle(_ urlStr: String) {
        guard let u = URL(string: urlStr) else { return }
        fetching = true
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let title = data.flatMap { Self.extractTitle($0) }
            DispatchQueue.main.async {
                fetching = false
                if let title, state.formTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    state.formTitle = title
                }
            }
        }.resume()
    }

    private static func extractTitle(_ data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let re = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let gr = Range(m.range(at: 1), in: html) else { return nil }
        var t = String(html[gr])
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Forces the enclosing `NSScrollView` to keep a persistent (non-autohiding)
/// scroller so the scrollbar is present from the first frame instead of fading
/// in after load. Configures as the view enters the window (pre-display).
private final class ScrollerConfigView: NSView {
    private func configure() {
        guard let sv = enclosingScrollView else { return }
        sv.scrollerStyle = .legacy
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = false
        sv.verticalScroller?.alphaValue = 1
    }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configure() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func layout() { super.layout(); configure() }
}

private struct AlwaysOnScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ScrollerConfigView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollerConfigView)?.needsLayout = true
    }
}

/// Native translucent background for the window.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
