import Foundation

/// A single bookmark parsed from the markdown file.
/// Line format: `- [Title](url) #tag1 #tag2 @alias1 @alias2`
/// URLs may contain a `%s` placeholder that is filled in at open time.
struct Bookmark: Identifiable {
    let id: Int          // stable index into the source file (used as identity)
    let title: String
    let url: String
    let tags: [String]
    let aliases: [String]

    var needsParam: Bool { url.contains("%s") }

    init(id: Int, title: String, url: String, tags: [String], aliases: [String]) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
        self.aliases = aliases
    }
}

enum BookmarkParser {
    /// Path to the bookmarks file (respects $BM_FILE, matching the ,bm script).
    static var filePath: String {
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
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if let bm = parse(line: line, id: index) {
                result.append(bm)
                index += 1
            }
        }
        return result
    }

    /// Parses one line. Returns nil for non-bookmark lines.
    static func parse(line: String, id: Int) -> Bookmark? {
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

        return Bookmark(id: id, title: title, url: url, tags: tags, aliases: aliases)
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
