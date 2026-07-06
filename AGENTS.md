# booker

Native macOS (SwiftUI/AppKit) spotlight-style picker for plaintext bookmarks.
Companion to the `,bm` bash script (`~/.local/bin/random/,bm`), reading the same
file. Supports add (⌘N) / edit (⌘E) / delete (⌘⌫) — writes back to the file.

## Data format

`$BM_FILE` (default `~/.local/share/bookmarks.md`), one bookmark per line:

```
- [Title](url) #tag1 #tag2 @alias1 @alias2
```

URLs may contain `)` and `#` fragments, and a `%s` placeholder prompted for at
open time (the entered value is percent-encoded before substitution). Parser
handles all of this — see `Bookmark.swift`. Full format/search docs live in
`docs/format.md` (linked from the README and the settings page).

File path precedence (`BookmarkParser.filePath`): `$BOOKER_BM_FILE` (hard
override, always wins — used for screenshots/testing against `docs/demo-bookmarks.md`
so the real file is never touched) → settings value (UserDefaults `bookmarkFile`,
`~` expanded) → `$BM_FILE` → default. Changing it in settings reloads the list
live (`AppState.setBookmarkFile` → `reloadBookmarks`).

## Layout

- `Sources/booker/Bookmark.swift` — markdown parser (greedy metadata split); each `Bookmark` carries its 0-based source `line`. Also the file writer: `format`, `append`, `replaceLine(at:)`, `deleteLine(at:)` — line-precise rewrites that preserve comments/blank lines.
- `Sources/booker/Frecency.swift` — usage store at `~/.local/share/booker/frecency.json` (count + decaying recency).
- `Sources/booker/Favicon.swift` — `FaviconStore`: per-host favicon fetch (DuckDuckGo `icons.duckduckgo.com/ip3/<host>.ico`) + disk cache at `~/.local/share/booker/favicons/<host>.png`. Async off the main thread; publishes arrivals so rows refresh. Gated by the `showFavicons` setting.
- `Sources/booker/Matcher.swift` — fuzzy scorer, returns `[MatchResult]` (bookmark + optional inline `param`). General-mode priority bands: **alias > title > tag > url**. `@foo` scopes to aliases, `#foo` to tags. The url band is gated by the `searchInLinks` setting. Multi-word queries are order-independent: single word = fuzzy subsequence; multiple words = each word must be a contiguous substring (avoids scattered-subsequence noise), with an in-order bonus so straightforward matches rank higher. **Inline `%s`**: `<alias> <value…>` (e.g. `dp 123`) where the first word matches an alias of a `%s` bookmark sets `MatchResult.param`, shown pre-filled and opened directly (value case preserved from the raw query).
- `Sources/booker/AppState.swift` — query/`results`/selection + open/copy/`%s` + add-edit-delete. `results` is `[ResultRow]` (`.bookmark` / `.openAll(alias, bookmarks)` for a shared alias / `.add(query)` when a URL-looking query has no matches). Add/edit share one form (`showForm`, `form*` fields, `editingLine` nil=append else replace); delete is a two-step confirm (`pendingDeleteID`, confirmed by the next `↩`). Refilter is driven from the view's `.onChange`, NOT a `didSet` (mutating published state mid-view-update renders stale).
- `Sources/booker/PickerView.swift` — SwiftUI UI: `Row` (with delete-confirm state), `ActionRow` (open-all / add rows), `BookmarkFormView` (add/edit form — auto-fetch `<title>`, tag suggestions, dedupe + alias-collision warnings, favicon; focus set async after mount or keystrokes drop). Plus `SettingsView` (`⌘,`/gear: bookmarks-file path + Choose… panel, search-in-links toggle, favicon toggle, match-highlight ColorPicker, reset frecency, clear favicon cache, link to `docs/format.md`). Rows highlight matched query words with a configurable colour (`highlightColorHex`, default grey `#808080`; `Color(hex:)`/`hexString` helpers). Settings content scrolls under a fixed header. Results use a `LazyVStack` for fast first paint; identity is the bookmark id on both the `ForEach` and the row `.id()` / `scrollTo` (mixing a positional `.id(idx)` with `LazyVStack` previously caused stale rows). `AlwaysOnScroller` forces a persistent legacy scroller (configured in `viewDidMoveToWindow`) so the scrollbar doesn't pop in after launch. `screenshotMode` swaps the translucent `VisualEffect` for a solid `windowBackgroundColor` (see screenshot note below).
- `Sources/booker/main.swift` — borderless+resizable key window (drag-to-move, edge-resize), key monitor (arrows/Ctrl-n/p nav, ⌘N add, ⌘E edit, ⌘⌫ delete, ⌘, settings; in form/settings modes only Esc is intercepted so text fields work), headless `list`/`rank` modes, `BOOKER_SHOT` render helper. `installEditMenu()` builds a minimal Edit menu — a bare `NSApplication` has no menu bar, so without it the standard editing key equivalents (⌘V/⌘C/⌘X/⌘A/undo) don't reach text fields (paste silently fails). Window frame is persisted via `setFrameAutosaveName("BookerMain")` (UserDefaults) and only centered on first launch. Opening settings resizes to a default (640×500); opening the add/edit form resizes to the form's exact measured height (`AppState.formHeight`, read from a `GeometryReader` — measuring via `PreferenceKey` didn't fire, and `.fixedSize` caused a resize runaway); closing either restores the saved picker frame (`observeOverlaySize` via Combine). Note: the raw debug binary and `Booker.app` use different UserDefaults domains, so persistence is per-artifact.

## Keys

`↩` open · `⌘↩` copy URL (also Save in the form) · `↑↓` / `Ctrl-p`/`Ctrl-n` nav ·
`⌘N` add · `⌘E` edit selected · `⌘⌫` delete selected (confirm with `↩`) ·
`⌘,` settings · `Esc` close overlay / back out of `%s` prompt / quit.

## Build & run

```sh
swift build                      # dev binary at ./.build/debug/booker
./build-app.sh                   # release -> ./Booker.app (LSUIElement, ad-hoc signed)
```

Headless debug modes (no GUI window — safe to run in an agent session):

```sh
./.build/debug/booker list       # dump parsed bookmarks: url<TAB>title | tags | aliases
./.build/debug/booker rank <q>   # ranked results (honors searchInLinks; BOOKER_SEARCH_LINKS=0/1 overrides)
./.build/debug/booker <query>    # launch GUI with the search box pre-filled
```

## Safety: writes mutate the real file

Add/edit/delete **write to `BookmarkParser.filePath`**. Any test that might save
(⌘↩) or confirm a delete MUST point booker at a throwaway copy via
`BOOKER_BM_FILE=/tmp/whatever.md` (highest-precedence override) — never risk the
user's `~/.local/share/bookmarks.md`. After a test, verify the real file is
untouched (`md5`). Read-only checks (`list`, `rank`, plain search) are safe.

## Testing the GUI headlessly (screenshot-based)

`screencapture` fails in the agent sandbox ("could not create image from
display" — no screen-recording permission). Instead the app renders **its own
window to a PNG** from inside the process, which needs no permission:

```sh
# Render current UI to PNG after a delay, then quit.
BOOKER_SHOT=/tmp/shot.png BOOKER_SHOT_DELAY=4 ./.build/debug/booker &
sleep 1.2
# Drive live input (reproduces bugs that pre-filled state hides, e.g. the
# LazyVStack stale-render bug that only appeared while typing):
osascript -e 'tell application "System Events" to keystroke "@a"'
sleep 4                          # let the shot fire
```

Then `Read` `/tmp/shot.png` to inspect the actual rendered layout. This
render-to-PNG + System Events loop is the reliable way to verify SwiftUI/AppKit
UI here. Prefer `rank`/`list` for logic; use the screenshot loop for layout and
live-typing behavior. The `screenshot-test` skill
(`.agents/skills/screenshot-test/shot.sh`) wraps this loop.

`BOOKER_SHOT` uses `contentView.cacheDisplay(in:to:)` →
`bitmapImageRepForCachingDisplay` → PNG; it is gated behind the env var and has
no effect on normal launches.

Favicon fetching needs network; the agent Bash sandbox blocks it. To test a
cold favicon fetch, launch with `dangerouslyDisableSandbox: true` and a longer
`BOOKER_SHOT_DELAY` (~8s). Cached-icon rendering works sandboxed (disk only).

The offscreen `cacheDisplay` capture can't render the behind-window blur, so it
would show a grey background. When `BOOKER_SHOT` is set the app forces `.aqua`
appearance and a solid `windowBackgroundColor` (`screenshotMode`) so the PNG
matches the light look of real use. Point booker at demo data for screenshots
with `BOOKER_BM_FILE=docs/demo-bookmarks.md` — never edit the user's real
bookmarks file.

Driving the add/edit form via System Events is flaky: keystrokes into the form's
text fields sometimes don't land (focus/timing), so an automated "type a title
then ⌘↩" may save unchanged. Give ⌘N/⌘E ~1.5s to settle before typing; to prove
a write path, prefer asserting on the resulting file (delete is the most
reliable to drive). First launch after a build is slower — if `BOOKER_SHOT`
produces no PNG, the fixed `sleep` fired before render; retry with more delay.

## Hotkey

Launches fresh, grabs focus, quits on select/escape. Point a launcher at the
app: `open -n .../Booker.app` (skhd/Raycast/Alfred). `open -n` forces a fresh
instance.
