import AppKit
import SwiftUI

/// Fetches and caches favicons per host. Icons are cached in memory and on disk
/// (`~/.local/share/booker/favicons/<host>.png`) so subsequent launches show
/// them instantly. Fetches happen off the main thread; arrivals are published
/// so observing views refresh.
final class FaviconStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]  // keyed by host
    private var inFlight: Set<String> = []  // main-thread only
    private let dir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dir = home + "/.local/share/booker/favicons"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    /// Host portion of a bookmark URL (handles `%s` placeholders and fragments).
    static func host(_ urlString: String) -> String? {
        var t = urlString
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        let end = t.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? t.endIndex
        let host = String(t[t.startIndex..<end])
        return host.isEmpty ? nil : host
    }

    func image(forURL urlString: String) -> NSImage? {
        guard let host = Self.host(urlString) else { return nil }
        return images[host]
    }

    /// Ensure the favicon for a URL is loaded (from disk or network). Call from
    /// the main thread. Cheap no-op if already loaded or in flight.
    func load(forURL urlString: String) {
        guard let host = Self.host(urlString), images[host] == nil, !inFlight.contains(host) else { return }
        inFlight.insert(host)
        let path = cachePath(host)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let data = FileManager.default.contents(atPath: path), let img = NSImage(data: data) {
                self?.publish(host: host, image: img)
            } else {
                self?.remoteFetch(host: host, savePath: path)
            }
        }
    }

    func clearCache() {
        images = [:]
        inFlight = []
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func cachePath(_ host: String) -> String { "\(dir)/\(host).png" }

    private func remoteFetch(host: String, savePath: String) {
        // DuckDuckGo's icon service (privacy-friendlier than Google's) resolves
        // the site's favicon server-side and returns an image for the host.
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") else {
            publish(host: host, image: nil)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            var image: NSImage?
            if let data = data, !data.isEmpty, let img = NSImage(data: data) {
                image = img
                if let png = Self.pngData(img) {
                    try? png.write(to: URL(fileURLWithPath: savePath))
                }
            }
            self?.publish(host: host, image: image)
        }.resume()
    }

    private func publish(host: String, image: NSImage?) {
        DispatchQueue.main.async {
            self.inFlight.remove(host)
            if let image = image { self.images[host] = image }
        }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
