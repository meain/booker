import Foundation

/// Persists how often / how recently each bookmark URL is opened, so the
/// picker can float frequently-used bookmarks to the top.
final class Frecency {
    private struct Entry: Codable {
        var count: Int
        var last: TimeInterval   // epoch seconds of last access
    }

    private var entries: [String: Entry]
    private let path: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = home + "/.local/share/booker"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.path = dir + "/frecency.json"

        if let data = FileManager.default.contents(atPath: path),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    /// Ranking weight for a URL. Higher = show earlier. Combines raw use count
    /// with a recency bonus that decays over days.
    func score(for url: String) -> Double {
        guard let e = entries[url] else { return 0 }
        let days = max(0, (Date().timeIntervalSince1970 - e.last) / 86_400)
        let recencyBonus = 6.0 / (1.0 + days)      // ~6 today, ~3 yesterday, tapering off
        return Double(e.count) + recencyBonus
    }

    /// Record that a URL was opened, and persist immediately.
    func record(url: String) {
        var e = entries[url] ?? Entry(count: 0, last: 0)
        e.count += 1
        e.last = Date().timeIntervalSince1970
        entries[url] = e
        save()
    }

    /// Clears all recorded usage and removes the on-disk store.
    func reset() {
        entries = [:]
        try? FileManager.default.removeItem(atPath: path)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
