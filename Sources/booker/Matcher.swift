import Foundation

/// Lightweight fuzzy matcher + ranker. Combines a fzf-style subsequence match
/// score with frecency so that both relevance and habit drive the ordering.
enum Matcher {
    /// Returns bookmarks that match `query`, best first.
    /// When `query` is empty, everything is returned sorted purely by frecency.
    static func rank(_ bookmarks: [Bookmark], query: String, frecency: Frecency) -> [Bookmark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        if q.isEmpty {
            return bookmarks.sorted { frecency.score(for: $0.url) > frecency.score(for: $1.url) }
        }

        var scored: [(bm: Bookmark, score: Double)] = []
        for bm in bookmarks {
            guard let base = matchScore(query: q, in: bm) else { continue }
            let combined = base + frecency.score(for: bm.url) * 2.0
            scored.append((bm, combined))
        }
        return scored
            .sorted { $0.score > $1.score }
            .map { $0.bm }
    }

    /// Best match score for a bookmark, or nil if the query doesn't match at all.
    /// Considers exact/prefix alias hits (large boost) and fuzzy title/tag hits.
    private static func matchScore(query: String, in bm: Bookmark) -> Double? {
        var best: Double? = nil

        // Alias matches — typing an alias is the fastest path, so weight it heavily.
        for alias in bm.aliases {
            let a = alias.lowercased()
            if a == query {
                best = max(best ?? 0, 1000)
            } else if a.hasPrefix(query) {
                best = max(best ?? 0, 500)
            } else if let s = fuzzy(query, a) {
                best = max(best ?? 0, s + 100)   // still favour alias hits over body text
            }
        }

        // Fuzzy match against the combined haystack (title + aliases + tags).
        if let s = fuzzy(query, bm.haystack) {
            best = max(best ?? 0, s)
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
