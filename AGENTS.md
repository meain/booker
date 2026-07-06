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
open time. Parser handles all of this — see `Bookmark.swift`.

## Layout

- `Sources/booker/Bookmark.swift` — markdown parser (greedy metadata split).
- `Sources/booker/Frecency.swift` — usage store at `~/.local/share/booker/frecency.json` (count + decaying recency).
- `Sources/booker/Matcher.swift` — fuzzy scorer. General-mode priority bands: **alias > title > tag > url**. `@foo` scopes to aliases, `#foo` to tags.
- `Sources/booker/AppState.swift` — query/results/selection + open/copy/`%s`. Refilter is driven from the view's `.onChange`, NOT a `didSet` (mutating published state mid-view-update renders stale).
- `Sources/booker/PickerView.swift` — SwiftUI UI. Uses a plain `VStack` (not `LazyVStack` — the latter cached stale rows when the result set changed wholesale).
- `Sources/booker/main.swift` — borderless+resizable key window (drag-to-move, edge-resize), key monitor, headless `list`/`rank` modes, `BOOKER_SHOT` render helper. Window frame is persisted via `setFrameAutosaveName("BookerMain")` (UserDefaults) and only centered on first launch. Note: the raw debug binary and `Booker.app` use different UserDefaults domains, so persistence is per-artifact.

## Build & run

```sh
swift build                      # dev binary at ./.build/debug/booker
./build-app.sh                   # release -> ./Booker.app (LSUIElement, ad-hoc signed)
```

Headless debug modes (no GUI window — safe to run in an agent session):

```sh
./.build/debug/booker list       # dump parsed bookmarks: url<TAB>title | tags | aliases
./.build/debug/booker rank <q>   # print ranked results for a query (verify matcher/search)
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

## Hotkey

Launches fresh, grabs focus, quits on select/escape. Point a launcher at the
app: `open -n .../Booker.app` (skhd/Raycast/Alfred). `open -n` forces a fresh
instance.
