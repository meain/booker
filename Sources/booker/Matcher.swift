import Foundation

/// Lightweight fuzzy matcher + ranker. Combines a fzf-style subsequence match
/// score with frecency so that both relevance and habit drive the ordering.
///
/// Search modes, chosen by the query prefix:
///   - `@foo`  → search aliases only
///   - `#foo`  → search tags only
///   - `foo`   → general search (title + aliases + tags), aliases weighted highest
///
/// Multi-word queries are order-independent: every word must match a field, in
/// any order (so "task work" finds "Workday Tasks"). A straightforward in-order
/// match earns a bonus so it ranks above a shuffled one.
/// A ranked result. `param` is set when the query supplied an inline `%s` value
/// (e.g. `dp 123` → the `@dp` bookmark with param `123`), meaning the URL is
/// ready to open without the interactive prompt.
struct MatchResult {
    let bookmark: Bookmark
    let param: String?
}

enum Matcher {
    private enum Mode {
        case general
        case alias
        case tag
    }

    /// Returns bookmarks that match `query`, best first.
    /// When the (post-prefix) term is empty, results are ordered purely by frecency.
    /// `searchInLinks` gates whether general search also matches against URLs.
    static func rank(_ bookmarks: [Bookmark], query: String, frecency: Frecency, searchInLinks: Bool = true) -> [MatchResult] {
        let (mode, term) = parse(query)

        if term.isEmpty {
            let pool: [Bookmark]
            switch mode {
            case .general: pool = bookmarks
            case .alias:   pool = bookmarks.filter { !$0.aliases.isEmpty }
            case .tag:     pool = bookmarks.filter { !$0.tags.isEmpty }
            }
            return pool
                .sorted { frecency.score(for: $0.url) > frecency.score(for: $1.url) }
                .map { MatchResult(bookmark: $0, param: nil) }
        }

        let tokens = term.split(separator: " ").map(String.init)

        // Inline %s parameter: `<alias> <param…>` where the first word matches an
        // alias of a bookmark whose URL contains %s. The rest becomes the value,
        // shown pre-filled and opened directly (no prompt). Original case of the
        // param is preserved from the raw query.
        let rawTokens = query.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var inline: [(MatchResult, Double)] = []
        var inlineIDs = Set<Int>()
        if mode == .general, tokens.count >= 2, rawTokens.count >= 2 {
            let first = tokens[0]
            let param = rawTokens.dropFirst().joined(separator: " ")
            for bm in bookmarks where bm.needsParam {
                var s: Double?
                for alias in bm.aliases {
                    let a = alias.lowercased()
                    if a == first { s = max(s ?? 0, 1000) }
                    else if a.hasPrefix(first) { s = max(s ?? 0, 500) }
                }
                if let s = s {
                    let score = 30_000 + s + frecency.score(for: bm.url) * 2.0
                    inline.append((MatchResult(bookmark: bm, param: param), score))
                    inlineIDs.insert(bm.id)
                }
            }
        }

        var scored: [(MatchResult, Double)] = inline
        for bm in bookmarks where !inlineIDs.contains(bm.id) {
            guard let base = matchScore(mode: mode, tokens: tokens, term: term, in: bm, searchInLinks: searchInLinks) else { continue }
            let combined = base + frecency.score(for: bm.url) * 2.0
            scored.append((MatchResult(bookmark: bm, param: nil), combined))
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
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
    /// `tokens` are the whitespace-split words of `term`; every token must match.
    private static func matchScore(mode: Mode, tokens: [String], term: String, in bm: Bookmark, searchInLinks: Bool) -> Double? {
        switch mode {
        case .alias:
            return tokensFieldScore(tokens, bm.aliases)
        case .tag:
            return tokensFieldScore(tokens, bm.tags)
        case .general:
            // Priority bands: alias > title > tag > url. The offsets guarantee a
            // hit in a higher band always outranks any hit in a lower one,
            // regardless of the within-band fuzzy score.
            var best: Double? = nil
            if let s = tokensFieldScore(tokens, bm.aliases) {
                best = max(best ?? 0, 30_000 + s)
            }
            if let s = multiFuzzy(tokens, whole: term, bm.title.lowercased()) {
                best = max(best ?? 0, 20_000 + s)
            }
            if let s = tokensFieldScore(tokens, bm.tags) {
                best = max(best ?? 0, 10_000 + s)
            }
            if searchInLinks, let s = multiFuzzy(tokens, whole: term, bm.url.lowercased()) {
                best = max(best ?? 0, s)   // lowest band: URLs match many things
            }
            return best
        }
    }

    /// Matches `tokens` against a single text (title or url).
    /// - Single word: fzf-style fuzzy subsequence (forgiving, for quick typing).
    /// - Multiple words: each word must appear as a contiguous substring, in any
    ///   order (avoids the scattered-subsequence noise that plagues loose
    ///   multi-word fuzzy). A whole-term in-order match adds a bonus so
    ///   straightforward matches rank above shuffled ones.
    /// Returns nil if the match fails.
    private static func multiFuzzy(_ tokens: [String], whole: String, _ text: String) -> Double? {
        if tokens.count <= 1 {
            return fuzzy(whole, text)
        }
        var total = 0.0
        for tok in tokens {
            guard let s = substringScore(tok, text) else { return nil }
            total += s
        }
        if let s = fuzzy(whole, text) {
            total += 1000 + s   // straightforward (in-order) match ranks higher
        }
        return total
    }

    /// Scores a token found as a contiguous substring of `text`, rewarding
    /// word-boundary starts. Returns nil if the token is not a substring.
    private static func substringScore(_ token: String, _ text: String) -> Double? {
        guard let r = text.range(of: token) else { return nil }
        var score = Double(token.count) * 4.0
        if r.lowerBound == text.startIndex {
            score += 4.0
        } else {
            let before = text[text.index(before: r.lowerBound)]
            if before == " " || before == "/" || before == "-" || before == "." {
                score += 3.0
            }
        }
        return score - Double(text.count) * 0.01
    }

    /// Every token must match some field in the set (aliases or tags), in any
    /// order; scores are summed. Returns nil if any token matches nothing.
    private static func tokensFieldScore(_ tokens: [String], _ fields: [String]) -> Double? {
        var total = 0.0
        for tok in tokens {
            guard let s = fieldScore(tok, fields) else { return nil }
            total += s
        }
        return total
    }

    /// Scores a single token against a set of fields (aliases or tags), rewarding
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
