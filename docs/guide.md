# Booker guide — format, search & shortcuts

Booker reads a plain-text Markdown file. Every bookmark is one line.

## Line format

```
- [Title](url) #tag1 #tag2 @alias1 @alias2
```

- **`- [Title](url)`** — a Markdown link. The title is free text (no `]`); the
  URL is everything in the parentheses. Required.
- **`#tag`** — zero or more space-separated tags.
- **`@alias`** — zero or more space-separated aliases (short handles you can
  jump to directly).

Tags and aliases are optional and may appear in any order after the link. Lines
that don't start with `- [` are ignored, so you can keep comments or headings in
the file.

The URL may itself contain `)` and `#` (fragments) — the parser finds the tags
and aliases at the end of the line, so complex URLs work fine.

Example:

```
- [GitHub](https://github.com/) #dev #git @gh
- [Rust std docs](https://doc.rust-lang.org/std/) #dev #docs @rust
- [Hacker News](https://news.ycombinator.com/) #news @hn
```

## Parameterized bookmarks (`%s`)

A URL may contain a `%s` placeholder. When you pick such a bookmark, booker
prompts for a value, substitutes it into the URL (percent-encoding it so spaces
and reserved characters are safe), and opens the result.

```
- [Wikipedia Article](https://en.wikipedia.org/wiki/%s) #reference @w
- [Hacker News Search](https://hn.algolia.com/?q=%s) #search @hns
- [GitHub Issue](https://github.com/owner/repo/issues/%s) #dev @gi
- [Jira Issue](https://your-org.atlassian.net/browse/PROJ-%s) #work @jira
```

Picking `@w` and typing `Bookmark` opens `https://en.wikipedia.org/wiki/Bookmark`.
Typing `foo bar` opens `.../wiki/foo%20bar`.

There are two ways to supply the value:

- **Inline** — type the alias then the value, e.g. `dp 123`. The bookmark shows
  up with the URL already filled in (`…/browse/DP-123`); Enter opens it directly.
- **Prompted** — pick the bookmark with no value (Enter), type the value at the
  prompt, then Enter to open (or ⌘Enter to copy the filled URL). Esc backs out.

The value is percent-encoded, so `w hello world` opens `…/wiki/hello%20world`.

## Search syntax

- **Fuzzy** — type any part of a title, tag, or alias.
- **Priority** — matches rank in the order **alias → title → tag → url**. An
  alias hit always outranks a title-only hit, and so on.
- **Order-independent multi-word** — `task work` matches "Workday Tasks". Every
  word must match (in any order); each word matches as a substring. A
  straightforward in-order match ranks higher than a shuffled one.
- **Scoped prefixes**:
  - `@foo` — search aliases only
  - `#foo` — search tags only
  - a bare `@` or `#` — list everything that has any alias / tag
- **Frecency** — bookmarks you open often (and recently) float up. With an empty
  query the list is ordered purely by frecency.

## Shared aliases (open multiple)

Giving several bookmarks the **same alias** is intentional — it groups them.
When you type that alias, booker shows an **"Open all N · @alias"** row at the
top; selecting it opens every bookmark in the group at once (bookmarks with a
`%s` are skipped). Individual rows still open one at a time.

```
- [Dashboard EU](https://…/eu) #dash @dash
- [Dashboard US](https://…/us) #dash @dash
- [Dashboard APJ](https://…/apj) #dash @dash
```

Typing `@dash` → "Open all 3 · @dash".

## Adding, editing & deleting

booker can modify the file directly:

- **⌘N** — add. Seeded from the current query (a `http(s)` query fills the URL,
  otherwise the title). Auto-fetches the page title, suggests tags from other
  bookmarks on the same domain, warns on duplicate URLs, shows the favicon.
- **⌘E** — edit the selected bookmark (same form, pre-filled).
- **⌘⌫** — delete the selected bookmark (confirm with `↩`).
- **⌘I** — usage stats for the selected bookmark: open count, last opened,
  share of all opens, frecency rank/score. `↩` opens it, `Esc` closes.

Title and URL are required. Edits rewrite exactly that one line; comments, blank
lines, and everything else in the file are preserved.

## GitHub shortcuts

When the URL you're adding is a GitHub repo root (`github.com/owner/repo`), the
add form shows an **Also create GitHub shortcuts** toggle. Turn it on to also
create a set of derived bookmarks for the repo, each ticked individually:

- **Issues** — `<alias>i`
- **Issues by me** — `<alias>im`
- **Pull requests** — `<alias>p`
- **PRs by me** — `<alias>pm`
- **PRs by me, merged** — `<alias>pmm`
- **PRs to review** — `<alias>pr`
- **Actions** — `<alias>a`
- **Releases** — `<alias>rel`

Each shortcut's alias is your first alias plus the suffix above, its title is the
repo title plus a suffix (e.g. `booker · Issues`), and it inherits the repo's
tags. The "by me" / "to review" searches use GitHub's `@me` token, so they
resolve to whoever is signed in. You need to enter at least one alias for the
repo — it's the prefix the shortcut aliases are built from.

## File location

booker resolves the bookmarks file in this order:

1. The path set in **Settings → Bookmarks file** (stored in UserDefaults).
2. The `$BM_FILE` environment variable.
3. The default: `~/.local/share/bookmarks.md`.

A leading `~` in the settings path is expanded. Leaving the setting empty falls
back to `$BM_FILE` / the default.

## Data & caches

- **Frecency** — usage counts at `~/.local/share/booker/frecency.json`
  (reset from settings).
- **Favicons** — cached per host at `~/.local/share/booker/favicons/`
  (toggle / clear from settings).
