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

/// A searchable field, precomputed once per bookmark: the lowercased text split
/// into characters, plus the boundary bonus for a match landing on each
/// position (string start, after a separator, or a camelCase hump taken from
/// the original casing, e.g. the `H` in `GitHub`).
struct SearchKey {
    let chars: [Character]
    let bonus: [Double]

    init(_ text: String) {
        let lower = Array(text.lowercased())
        let orig = Array(text)
        // Lowercasing can (rarely) change the character count; only use the
        // original casing for camelCase humps when positions still line up.
        let sameShape = orig.count == lower.count
        var bonus = [Double](repeating: 0, count: lower.count)
        for i in lower.indices {
            if i == 0 {
                bonus[i] = Matcher.startBonus
            } else if Matcher.separators.contains(lower[i - 1]) {
                bonus[i] = Matcher.boundaryBonus
            } else if sameShape, orig[i].isUppercase, orig[i - 1].isLowercase {
                bonus[i] = Matcher.boundaryBonus
            }
        }
        self.chars = lower
        self.bonus = bonus
    }
}

enum Matcher {
    private enum Mode {
        case general
        case alias
        case tag
    }

    // Scoring weights. Each matched character scores 1 plus its position's
    // boundary bonus; consecutive matches add `consecutiveBonus`; every text
    // character skipped between two matches costs `gapPenalty`. A contiguous
    // (exact substring) match adds `contiguousBonus`, which is large enough
    // that it always outranks a scattered alignment of the same query.
    static let startBonus = 4.0
    static let boundaryBonus = 2.0
    static let consecutiveBonus = 3.0
    static let gapPenalty = 0.1
    static let contiguousBonus = 8.0
    static let separators: Set<Character> = [" ", "/", "-", "_", ".", ":", "?", "=", "&", "#"]

    /// Returns bookmarks that match `query`, best first.
    /// When the (post-prefix) term is empty, results are ordered purely by frecency.
    /// `searchInLinks` gates whether general search also matches against URLs.
    static func rank(_ bookmarks: [Bookmark], query: String, frecency: Frecency, searchInLinks: Bool = true) -> [MatchResult] {
        let (mode, term) = parse(query)

        if term.isEmpty {
            let pool: [Bookmark]
            switch mode {
            case .general: pool = bookmarks
            case .alias: pool = bookmarks.filter { !$0.aliases.isEmpty }
            case .tag: pool = bookmarks.filter { !$0.tags.isEmpty }
            }
            return
                pool
                .sorted { frecency.score(for: $0.url) > frecency.score(for: $1.url) }
                .map { MatchResult(bookmark: $0, param: nil) }
        }

        let tokens = term.split(separator: " ").map { Array($0) }
        let whole = Array(term)

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
                for alias in bm.aliasKeys {
                    let a = alias.chars
                    if a == first { s = max(s ?? 0, 1000) } else if a.starts(with: first) { s = max(s ?? 0, 500) }
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
            guard let base = matchScore(mode: mode, tokens: tokens, whole: whole, in: bm, searchInLinks: searchInLinks) else { continue }
            let combined = base + frecency.score(for: bm.url) * 2.0
            scored.append((MatchResult(bookmark: bm, param: nil), combined))
        }
        return
            scored
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
    /// `tokens` are the whitespace-split words of `whole` (the full term);
    /// every token must match.
    private static func matchScore(mode: Mode, tokens: [[Character]], whole: [Character], in bm: Bookmark, searchInLinks: Bool) -> Double? {
        switch mode {
        case .alias:
            return tokensFieldScore(tokens, bm.aliasKeys)
        case .tag:
            return tokensFieldScore(tokens, bm.tagKeys)
        case .general:
            // Priority bands: alias > title > tag > url. The offsets guarantee a
            // hit in a higher band always outranks any hit in a lower one,
            // regardless of the within-band fuzzy score.
            var best: Double? = nil
            if let s = tokensFieldScore(tokens, bm.aliasKeys) {
                best = max(best ?? 0, 30_000 + s)
            }
            if let s = multiFuzzy(tokens, whole: whole, bm.titleKey) {
                best = max(best ?? 0, 20_000 + s)
            }
            if let s = tokensFieldScore(tokens, bm.tagKeys) {
                best = max(best ?? 0, 10_000 + s)
            }
            if searchInLinks, let s = multiFuzzy(tokens, whole: whole, bm.urlKey) {
                best = max(best ?? 0, s)  // lowest band: URLs match many things
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
    private static func multiFuzzy(_ tokens: [[Character]], whole: [Character], _ key: SearchKey) -> Double? {
        if tokens.count <= 1 {
            return fuzzy(whole, key)
        }
        var total = 0.0
        for tok in tokens {
            guard let s = substringScore(tok, key) else { return nil }
            total += s
        }
        if let s = fuzzy(whole, key) {
            total += 1000 + s  // straightforward (in-order) match ranks higher
        }
        return total
    }

    /// Scores a token found as a contiguous substring of `key`, picking the
    /// best-placed occurrence (word-boundary starts win). Returns nil if the
    /// token is not a substring.
    private static func substringScore(_ token: [Character], _ key: SearchKey) -> Double? {
        guard let s = bestSubstring(token, key) else { return nil }
        return s - Double(key.chars.count) * 0.01
    }

    /// Every token must match some field in the set (aliases or tags), in any
    /// order; scores are summed. Returns nil if any token matches nothing.
    private static func tokensFieldScore(_ tokens: [[Character]], _ fields: [SearchKey]) -> Double? {
        var total = 0.0
        for tok in tokens {
            guard let s = fieldScore(tok, fields) else { return nil }
            total += s
        }
        return total
    }

    /// Scores a single token against a set of fields (aliases or tags), rewarding
    /// exact and prefix hits over loose fuzzy ones. Returns the best, or nil.
    private static func fieldScore(_ term: [Character], _ fields: [SearchKey]) -> Double? {
        var best: Double? = nil
        for field in fields {
            let f = field.chars
            if f == term {
                best = max(best ?? 0, 1000)
            } else if f.starts(with: term) {
                best = max(best ?? 0, 500)
            } else if let s = fuzzy(term, field) {
                best = max(best ?? 0, 200 + s)
            }
        }
        return best
    }

    /// Score of the best contiguous occurrence of `query` in `key`, before the
    /// length penalty, or nil if `query` is not a substring.
    private static func bestSubstring(_ query: [Character], _ key: SearchKey) -> Double? {
        let q = query
        let t = key.chars
        let m = q.count
        let n = t.count
        guard m > 0, m <= n else { return nil }

        var best: Double? = nil
        var i = 0
        while i <= n - m {
            var k = 0
            while k < m && t[i + k] == q[k] { k += 1 }
            if k == m {
                var s = Double(m) + consecutiveBonus * Double(m - 1) + contiguousBonus
                for j in i..<(i + m) { s += key.bonus[j] }
                best = max(best ?? s, s)
            }
            i += 1
        }
        return best
    }

    /// fzf-v2-style scorer: finds the best alignment of `query` as a
    /// subsequence of `key`, rewarding word-boundary and consecutive matches
    /// and penalising gaps. Contiguous (substring) matches take a fast path and
    /// get a strong bonus. Returns nil if `query` is not a subsequence.
    static func fuzzy(_ query: [Character], _ key: SearchKey) -> Double? {
        let q = query
        let t = key.chars
        let m = q.count
        let n = t.count
        guard m > 0 else { return 0 }
        guard m <= n else { return nil }
        // Slight penalty for long haystacks so tight matches win ties.
        let lengthPenalty = Double(n) * 0.01

        if let s = bestSubstring(q, key) {
            return s - lengthPenalty
        }

        // Cheap greedy subsequence check, which also bounds the DP window: the
        // first possible start of q[0] and the last possible end of q[m-1].
        var qi = 0
        var lo = -1
        for j in 0..<n where t[j] == q[qi] {
            if qi == 0 { lo = j }
            qi += 1
            if qi == m { break }
        }
        guard qi == m else { return nil }
        var hi = n - 1
        while t[hi] != q[m - 1] { hi -= 1 }

        // prev[j] / cur[j]: best score with the previous / current query char
        // matched at text position lo+j (-inf when impossible).
        let width = hi - lo + 1
        let none = -Double.infinity
        var prev = [Double](repeating: none, count: width)
        var cur = prev
        for i in 0..<m {
            // carry = best prev[k] - gapPenalty * (j-1-k) over k <= j-2, i.e.
            // arriving at j after skipping at least one character.
            var carry = none
            for j in 0..<width {
                if i > 0 && j >= 2 { carry = max(carry, prev[j - 2]) - gapPenalty }
                guard t[lo + j] == q[i] else {
                    cur[j] = none
                    continue
                }
                let s = 1 + key.bonus[lo + j]
                if i == 0 {
                    cur[j] = s
                } else {
                    let consecutive = j >= 1 ? prev[j - 1] + consecutiveBonus : none
                    cur[j] = s + max(consecutive, carry)
                }
            }
            swap(&prev, &cur)
        }

        guard let best = prev.max(), best > none else { return nil }
        return best - lengthPenalty
    }
}
