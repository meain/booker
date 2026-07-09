import Foundation

/// A derived bookmark suggested for a GitHub repository, e.g. its issues or PRs
/// page. When enabled in the add form it is written as its own bookmark line,
/// with the repo's URL/title/alias extended by these suffixes.
struct GithubShortcut: Identifiable {
    let label: String  // checkbox label in the form
    let titleSuffix: String  // appended to the repo title: "<title> · <suffix>"
    let aliasSuffix: String  // appended to the base alias: "<alias><suffix>"
    let path: String  // appended to the repo URL

    var id: String { aliasSuffix }
}

enum Github {
    /// If `url` points at a GitHub repo root (`github.com/owner/repo`), returns
    /// "owner/repo". Deeper paths (issues, blob, …), the site root, and reserved
    /// first segments (orgs, settings, …) return nil.
    static func repoSlug(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespaces).strippingURLScheme()
        guard s.hasPrefix("github.com/") else { return nil }
        s.removeFirst("github.com/".count)
        if s.hasSuffix("/") { s.removeLast() }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let reserved: Set<String> = [
            "orgs", "settings", "marketplace", "features", "sponsors",
            "topics", "collections", "notifications", "issues", "pulls",
            "explore", "about", "pricing", "login", "join",
        ]
        guard !reserved.contains(parts[0].lowercased()) else { return nil }
        return parts.joined(separator: "/")
    }

    /// Ordered list of derived-bookmark templates offered for a repo. `%40me` is
    /// an encoded `@me`, GitHub's search token for the signed-in user.
    static let shortcuts: [GithubShortcut] = [
        .init(label: "Issues", titleSuffix: "Issues", aliasSuffix: "i", path: "/issues"),
        .init(
            label: "Issues by me", titleSuffix: "Issues by me", aliasSuffix: "im",
            path: "/issues?q=is%3Aissue+author%3A%40me"),
        .init(label: "Pull requests", titleSuffix: "PRs", aliasSuffix: "p", path: "/pulls"),
        .init(
            label: "PRs by me", titleSuffix: "PRs by me", aliasSuffix: "pm",
            path: "/pulls?q=is%3Apr+author%3A%40me"),
        .init(
            label: "PRs by me, merged", titleSuffix: "PRs by me, merged", aliasSuffix: "pmm",
            path: "/pulls?q=is%3Apr+author%3A%40me+is%3Amerged"),
        .init(
            label: "PRs to review", titleSuffix: "PRs to review", aliasSuffix: "pr",
            path: "/pulls?q=is%3Apr+review-requested%3A%40me"),
        .init(label: "Actions", titleSuffix: "Actions", aliasSuffix: "a", path: "/actions"),
        .init(label: "Releases", titleSuffix: "Releases", aliasSuffix: "rel", path: "/releases"),
    ]
}
