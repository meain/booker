import Foundation

/// A single bookmark parsed from the markdown file.
/// Line format: `- [Title](url) #tag1 #tag2 @alias1 @alias2`
/// URLs may contain a `%s` placeholder that is filled in at open time.
struct Bookmark: Identifiable {
    let id: Int  // stable index among parsed bookmarks (identity for the UI)
    let line: Int  // 0-based line number in the source file (for edit/delete)
    let title: String
    let url: String
    let tags: [String]
    let aliases: [String]

    var needsParam: Bool { url.contains("%s") }

    init(id: Int, line: Int, title: String, url: String, tags: [String], aliases: [String]) {
        self.id = id
        self.line = line
        self.title = title
        self.url = url
        self.tags = tags
        self.aliases = aliases
    }
}

enum BookmarkParser {
    static let fileDefaultsKey = "bookmarkFile"

    /// Path to the bookmarks file. Precedence (highest first):
    ///   1. `$BOOKER_BM_FILE` — hard override, always wins (used for
    ///      screenshots/testing against a demo file without touching the real one).
    ///   2. the path set in settings (UserDefaults).
    ///   3. `$BM_FILE` (matching the ,bm script).
    ///   4. the default `~/.local/share/bookmarks.md`.
    /// A leading `~` is expanded.
    static var filePath: String {
        if let env = ProcessInfo.processInfo.environment["BOOKER_BM_FILE"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        if let p = UserDefaults.standard.string(forKey: fileDefaultsKey), !p.isEmpty {
            return (p as NSString).expandingTildeInPath
        }
        if let env = ProcessInfo.processInfo.environment["BM_FILE"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/.local/share/bookmarks.md"
    }

    static func load() -> [Bookmark] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }
        var result: [Bookmark] = []
        var index = 0
        // Keep all lines (including blanks/comments) so `line` is the true file
        // line number, which edit/delete rewrite precisely.
        for (fileLine, rawLine) in content.components(separatedBy: "\n").enumerated() {
            if let bm = parse(line: rawLine, id: index, fileLine: fileLine) {
                result.append(bm)
                index += 1
            }
        }
        return result
    }

    /// Parses one line. Returns nil for non-bookmark lines.
    static func parse(line: String, id: Int, fileLine: Int = 0) -> Bookmark? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- [") else { return nil }

        // Title is between the first "[" and the "](" that introduces the URL.
        guard let openBracket = trimmed.range(of: "[") else { return nil }
        guard let titleEnd = trimmed.range(of: "](", range: openBracket.upperBound..<trimmed.endIndex) else {
            return nil
        }
        let title = String(trimmed[openBracket.upperBound..<titleEnd.lowerBound])

        // Everything after "](" holds the URL plus trailing " #tag @alias" metadata.
        // The URL itself may contain ')' and '#' (fragments), so we find the LAST
        // "){space}[#@]" split — matching the greedy regex used by the ,bm script.
        let rest = String(trimmed[titleEnd.upperBound...])

        var url = rest
        var meta = ""
        if let split = lastMetaSplit(in: rest) {
            url = String(rest[rest.startIndex..<split])
            // split points at the ')' ; metadata starts two chars later (") ")
            let metaStart = rest.index(split, offsetBy: 2)
            meta = String(rest[metaStart...])
        } else if rest.hasSuffix(")") {
            url = String(rest.dropLast())
        }

        var tags: [String] = []
        var aliases: [String] = []
        for token in meta.split(separator: " ") {
            if token.hasPrefix("#") {
                tags.append(String(token.dropFirst()))
            } else if token.hasPrefix("@") {
                aliases.append(String(token.dropFirst()))
            }
        }

        return Bookmark(id: id, line: fileLine, title: title, url: url, tags: tags, aliases: aliases)
    }

    // MARK: - Writing

    /// Renders a bookmark line: `- [Title](url) #tag @alias`.
    static func format(title: String, url: String, tags: [String], aliases: [String]) -> String {
        var s = "- [\(title)](\(url))"
        for t in tags { s += " #\(t)" }
        for a in aliases { s += " @\(a)" }
        return s
    }

    /// Append a new bookmark line to the file (creating/terminating newlines).
    static func append(_ line: String) {
        var text = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += line + "\n"
        try? text.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Replace the raw file line at `index` (leaves other lines untouched).
    static func replaceLine(at index: Int, with newLine: String) {
        rewrite { lines in
            guard lines.indices.contains(index) else { return }
            lines[index] = newLine
        }
    }

    /// Remove the raw file line at `index`.
    static func deleteLine(at index: Int) {
        rewrite { lines in
            guard lines.indices.contains(index) else { return }
            lines.remove(at: index)
        }
    }

    private static func rewrite(_ mutate: (inout [String]) -> Void) {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        mutate(&lines)
        try? lines.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Finds the index of the ')' in the last occurrence of ") #" or ") @",
    /// where everything after is valid metadata. Returns nil if there is none.
    private static func lastMetaSplit(in rest: String) -> String.Index? {
        var searchEnd = rest.endIndex
        while true {
            guard let r = rest.range(of: ") ", options: .backwards, range: rest.startIndex..<searchEnd) else {
                return nil
            }
            let afterSpace = rest.index(r.lowerBound, offsetBy: 2)
            if afterSpace < rest.endIndex {
                let firstMetaChar = rest[afterSpace]
                if firstMetaChar == "#" || firstMetaChar == "@" {
                    return r.lowerBound
                }
            }
            searchEnd = r.lowerBound
        }
    }
}
