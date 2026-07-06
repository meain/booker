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
            if state.showSettings {
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
                VStack(spacing: 0) {
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
                        ForEach(Array(state.results.enumerated()), id: \.element.bookmark.id) { idx, result in
                            Row(bookmark: result.bookmark,
                                param: result.param,
                                selected: idx == state.selected,
                                showFavicon: state.showFavicons,
                                favicon: state.showFavicons ? favicons.image(forURL: result.bookmark.url) : nil,
                                matchTokens: matchTokens,
                                highlightColor: Color(hex: state.highlightColorHex) ?? .gray)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.selected = idx
                                    state.activate(copy: false)
                                }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: state.selected) { newValue in
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
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
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Text(highlighted(displayURL))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }

            Spacer(minLength: 8)

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
