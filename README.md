# booker

A fast, native macOS spotlight-style picker for your plaintext bookmarks — a
GUI companion to the [`,bm`](https://en.wikipedia.org/wiki/Bookmark) bash script.

Reads the same file (`$BM_FILE`, default `~/.local/share/bookmarks.md`) in the
format:

```
- [Title](url) #tag1 #tag2 @alias1 @alias2
```

URLs may contain a `%s` placeholder that is prompted for at open time
(e.g. `Jira DP Issue` → prompts for the ticket number).

## Features

- **Fuzzy search** over titles, tags, and aliases. In general search the
  priority is **alias > title > tag** — an alias hit always floats above a
  title-only hit, which floats above a tag-only hit.
- **Scoped search by prefix**:
  - `@foo` — search **aliases** only
  - `#foo` — search **tags** only
  - bare `@` or `#` — list everything that has any alias / tag, by frecency
- **Aliases highlighted** as orange chips; tags shown in cyan.
- **Frecency ranking** — bookmarks you open often (and recently) float to the
  top. With an empty query the list is ordered purely by frecency.
- **`%s` parameters** — selecting a bookmark with `%s` switches to an inline
  prompt for the value before opening.
- **Resizable & draggable** — drag anywhere on the window to move it, drag an
  edge to resize. The size and position are remembered across launches.
- **Read-only** — adding/removing/editing bookmarks stays in the `,bm` script.

## Keybindings

| Key | Action |
| --- | --- |
| type | filter |
| `↓` / `Ctrl-n` | next result |
| `↑` / `Ctrl-p` | previous result |
| `Enter` | open selected in browser |
| `⌘ Enter` | copy selected URL to clipboard |
| click | open that row |
| `Esc` | back out of param mode / quit |

## Build

Requires the Swift toolchain (`swift --version`).

```sh
# Dev binary
swift build
./.build/debug/booker            # launch the picker
./.build/debug/booker list       # headless: dump parsed bookmarks (debug)

# Release .app bundle (recommended for a hotkey launcher)
./build-app.sh                   # produces ./Booker.app
open ./Booker.app
```

## Wiring up a hotkey

Booker launches fresh, grabs focus, and quits on select/escape, so it works
well as a hotkey target. Point your launcher at the `.app` bundle:

- **skhd**: `cmd + shift - b : open -n /path/to/booker/Booker.app`
- **Raycast / Alfred**: add a script/hotkey that runs `open -n .../Booker.app`.

(`open -n` forces a fresh instance each time.)

## Layout

- `Sources/booker/Bookmark.swift` — markdown parser (handles URLs containing
  `)` and `#` fragments).
- `Sources/booker/Frecency.swift` — usage store at `~/.local/share/booker/frecency.json`.
- `Sources/booker/Matcher.swift` — fuzzy scorer + frecency ranking.
- `Sources/booker/AppState.swift` — query/results/selection + actions.
- `Sources/booker/PickerView.swift` — SwiftUI UI.
- `Sources/booker/main.swift` — window setup + key handling (`list` mode too).
