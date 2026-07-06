---
name: screenshot-test
description: "Visually test the booker macOS GUI by rendering its window to a PNG (no screen-recording permission needed) and inspecting it. Use when verifying booker layout/UI changes, reproducing rendering bugs, or checking live-typing behavior in the SwiftUI picker."
user_invocable: true
---

# booker GUI screenshot testing

`screencapture` fails in the agent sandbox ("could not create image from
display" — no screen-recording permission). Instead booker renders **its own
window to a PNG** from inside the process (`BOOKER_SHOT` env), which needs no
permission. This skill wraps the build → launch → type → render loop.

## Usage

```sh
.claude/skills/screenshot-test/shot.sh                 # initial list (empty query)
.claude/skills/screenshot-test/shot.sh '@a'            # type "@a" live, then render
.claude/skills/screenshot-test/shot.sh 'git' /tmp/g.png
```

The script builds the debug binary, launches it with `BOOKER_SHOT`, optionally
types the query via System Events, waits for the render, and prints the PNG
path. Then **`Read` the PNG** to inspect the actual rendered layout.

## Why live typing matters

Pre-filling the query (`booker '@a'`) renders the correct result once and hides
state-update bugs. Typing via System Events exercises the real update path —
that's how the `LazyVStack` stale-render bug (list kept showing old results
while `body` had new data) was caught. Prefer live typing when checking
filtering/selection behavior; the initial-list form is fine for pure layout.

## Knobs

- `BOOKER_SHOT_DELAY` (default 4s) — total wait before the shot fires. Increase
  if you send many keystrokes.
- Keystrokes go to the frontmost app; booker grabs focus on launch, so don't
  click away during the run.

## When to use what

- **Logic / ranking / parsing** → headless `booker rank <q>` and `booker list`
  (no window, deterministic, faster).
- **Layout / colors / live-typing UI** → this skill (render to PNG + Read).

See `AGENTS.md` for the full project map.
