import SwiftUI

struct PickerView: View {
    @ObservedObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onChange(of: state.query) { _ in state.refilter() }
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
                            Row(bookmark: bm, selected: idx == state.selected)
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

    /// URL without the scheme, for a cleaner secondary line.
    private var displayURL: String {
        var u = bookmark.url
        for prefix in ["https://", "http://"] where u.hasPrefix(prefix) {
            u.removeFirst(prefix.count)
        }
        return u
    }

    var body: some View {
        HStack(spacing: 8) {
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
