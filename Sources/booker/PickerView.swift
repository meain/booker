import SwiftUI

struct PickerView: View {
    @ObservedObject var state: AppState
    @ObservedObject var favicons: FaviconStore
    @FocusState private var searchFocused: Bool

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
        .background(VisualEffect())
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
                        ForEach(Array(state.results.enumerated()), id: \.element.id) { idx, bm in
                            Row(bookmark: bm,
                                selected: idx == state.selected,
                                showFavicon: state.showFavicons,
                                favicon: state.showFavicons ? favicons.image(forURL: bm.url) : nil)
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
    let selected: Bool
    var showFavicon: Bool = false
    var favicon: NSImage? = nil

    /// URL without the scheme, for a cleaner secondary line.
    private var displayURL: String {
        var u = bookmark.url
        for prefix in ["https://", "http://"] where u.hasPrefix(prefix) {
            u.removeFirst(prefix.count)
        }
        return u
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
                Text(bookmark.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Text(displayURL)
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
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.cyan)
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
              }
              .padding(16)
            }
        }
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
