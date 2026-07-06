# booker

Native macOS (SwiftUI/AppKit) spotlight-style picker for plaintext bookmarks.
Companion to the `,bm` bash script (`~/.local/bin/random/,bm`), reading the same
file. Read-only: add/remove/edit stays in `,bm`.

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

- `Sources/booker/Bookmark.swift` — markdown parser (greedy metadata split).
- `Sources/booker/Frecency.swift` — usage store at `~/.local/share/booker/frecency.json` (count + decaying recency).
- `Sources/booker/Favicon.swift` — `FaviconStore`: per-host favicon fetch (DuckDuckGo `icons.duckduckgo.com/ip3/<host>.ico`) + disk cache at `~/.local/share/booker/favicons/<host>.png`. Async off the main thread; publishes arrivals so rows refresh. Gated by the `showFavicons` setting.
- `Sources/booker/Matcher.swift` — fuzzy scorer, returns `[MatchResult]` (bookmark + optional inline `param`). General-mode priority bands: **alias > title > tag > url**. `@foo` scopes to aliases, `#foo` to tags. The url band is gated by the `searchInLinks` setting. Multi-word queries are order-independent: single word = fuzzy subsequence; multiple words = each word must be a contiguous substring (avoids scattered-subsequence noise), with an in-order bonus so straightforward matches rank higher. **Inline `%s`**: `<alias> <value…>` (e.g. `dp 123`) where the first word matches an alias of a `%s` bookmark sets `MatchResult.param`, shown pre-filled and opened directly (value case preserved from the raw query).
- `Sources/booker/AppState.swift` — query/results/selection + open/copy/`%s`. Refilter is driven from the view's `.onChange`, NOT a `didSet` (mutating published state mid-view-update renders stale).
- `Sources/booker/PickerView.swift` — SwiftUI UI + `SettingsView` (`⌘,`/gear: bookmarks-file path + Choose… panel, search-in-links toggle, favicon toggle, match-highlight ColorPicker, reset frecency, clear favicon cache, link to `docs/format.md`). Rows highlight matched query words with a configurable colour (`highlightColorHex`, default grey `#808080`; `Color(hex:)`/`hexString` helpers). Settings content scrolls under a fixed header. Uses a plain `VStack` (not `LazyVStack` — the latter cached stale rows when the result set changed wholesale). `screenshotMode` swaps the translucent `VisualEffect` for a solid `windowBackgroundColor` (see screenshot note below).
- `Sources/booker/main.swift` — borderless+resizable key window (drag-to-move, edge-resize), key monitor, headless `list`/`rank` modes, `BOOKER_SHOT` render helper. Window frame is persisted via `setFrameAutosaveName("BookerMain")` (UserDefaults) and only centered on first launch. Note: the raw debug binary and `Booker.app` use different UserDefaults domains, so persistence is per-artifact.

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
live-typing behavior.

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

## Hotkey

Launches fresh, grabs focus, quits on select/escape. Point a launcher at the
app: `open -n .../Booker.app` (skhd/Raycast/Alfred). `open -n` forces a fresh
instance.
