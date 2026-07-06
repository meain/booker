import Foundation

/// Lightweight fuzzy matcher + ranker. Combines a fzf-style subsequence match
/// score with frecency so that both relevance and habit drive the ordering.
///
/// Search modes, chosen by the query prefix:
///   - `@foo`  → search aliases only
///   - `#foo`  → search tags only
///   - `foo`   → general search (title + aliases + tags), aliases weighted highest
enum Matcher {
    private enum Mode {
        case general
        case alias
        case tag
    }

    /// Returns bookmarks that match `query`, best first.
    /// When the (post-prefix) term is empty, results are ordered purely by frecency.
    /// `searchInLinks` gates whether general search also matches against URLs.
    static func rank(_ bookmarks: [Bookmark], query: String, frecency: Frecency, searchInLinks: Bool = true) -> [Bookmark] {
        let (mode, term) = parse(query)

        if term.isEmpty {
            let pool: [Bookmark]
            switch mode {
            case .general: pool = bookmarks
            case .alias:   pool = bookmarks.filter { !$0.aliases.isEmpty }
            case .tag:     pool = bookmarks.filter { !$0.tags.isEmpty }
            }
            return pool.sorted { frecency.score(for: $0.url) > frecency.score(for: $1.url) }
        }

        var scored: [(bm: Bookmark, score: Double)] = []
        for bm in bookmarks {
            guard let base = matchScore(mode: mode, term: term, in: bm, searchInLinks: searchInLinks) else { continue }
            let combined = base + frecency.score(for: bm.url) * 2.0
            scored.append((bm, combined))
        }
        return scored
            .sorted { $0.score > $1.score }
            .map { $0.bm }
    }

    /// Splits the raw query into a search mode and a lowercased term.
    private static func parse(_ query: String) -> (Mode, String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.hasPrefix("@") {
            return (.alias, String(q.dropFirst()).lowercased())
        }
        if q.hasPrefix("#") {
            return (.tag, String(q.dropFirst()).lowercased())
        }
        return (.general, q.lowercased())
    }

    /// Best match score for a bookmark under the given mode, or nil if no match.
    private static func matchScore(mode: Mode, term: String, in bm: Bookmark, searchInLinks: Bool) -> Double? {
        switch mode {
        case .alias:
            return fieldScore(term, bm.aliases)
        case .tag:
            return fieldScore(term, bm.tags)
        case .general:
            // Priority bands: alias > title > tag > url. The offsets guarantee a
            // hit in a higher band always outranks any hit in a lower one,
            // regardless of the within-band fuzzy score.
            var best: Double? = nil
            if let s = fieldScore(term, bm.aliases) {
                best = max(best ?? 0, 30_000 + s)
            }
            if let s = fuzzy(term, bm.title.lowercased()) {
                best = max(best ?? 0, 20_000 + s)
            }
            if let s = fieldScore(term, bm.tags) {
                best = max(best ?? 0, 10_000 + s)
            }
            if searchInLinks, let s = fuzzy(term, bm.url.lowercased()) {
                best = max(best ?? 0, s)   // lowest band: URLs match many things
            }
            return best
        }
    }

    /// Scores `term` against a set of fields (aliases or tags), rewarding
    /// exact and prefix hits over loose fuzzy ones. Returns the best, or nil.
    private static func fieldScore(_ term: String, _ fields: [String]) -> Double? {
        var best: Double? = nil
        for field in fields {
            let f = field.lowercased()
            if f == term {
                best = max(best ?? 0, 1000)
            } else if f.hasPrefix(term) {
                best = max(best ?? 0, 500)
            } else if let s = fuzzy(term, f) {
                best = max(best ?? 0, 200 + s)
            }
        }
        return best
    }

    /// fzf-style subsequence scorer. Rewards matches at word starts and
    /// consecutive runs. Returns nil if `query` is not a subsequence of `text`.
    private static func fuzzy(_ query: String, _ text: String) -> Double? {
        let q = Array(query)
        let t = Array(text)
        guard !q.isEmpty else { return 0 }

        var score = 0.0
        var qi = 0
        var prevMatched = false
        var prevChar: Character = " "

        for ti in 0..<t.count {
            guard qi < q.count else { break }
            if t[ti] == q[qi] {
                var bonus = 1.0
                if prevMatched { bonus += 3.0 }                       // consecutive run
                if prevChar == " " || prevChar == "/" || prevChar == "-" {
                    bonus += 2.0                                      // word/segment start
                }
                if ti == 0 { bonus += 2.0 }                          // very start
                score += bonus
                qi += 1
                prevMatched = true
            } else {
                prevMatched = false
            }
            prevChar = t[ti]
        }

        guard qi == q.count else { return nil }
        // Slight penalty for long haystacks so tight matches win ties.
        return score - Double(t.count) * 0.01
    }
}
