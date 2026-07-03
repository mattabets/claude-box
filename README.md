# claude-box

Tile several claude.ai chats into a grid on macOS, so you can watch multiple
conversations at once instead of clicking through the sidebar. Optionally include
the Claude desktop app as one of the tiles. Layout only — no status tracking, no
notifications, no custom client. Just windows, placed.

It's a single [Hammerspoon](https://www.hammerspoon.org/) config that opens a
standing set of chats as clean app-mode browser windows and snaps them into an
even grid on your focused screen, driven by two hotkeys.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/) — `brew install --cask hammerspoon`
- Google Chrome or Microsoft Edge (Safari can't do CLI app-mode windows)

## Install

1. Install Hammerspoon:

   ```sh
   brew install --cask hammerspoon
   ```

2. Copy the config into place. Hammerspoon loads `~/.hammerspoon/init.lua`:

   ```sh
   cp claude-box.lua ~/.hammerspoon/init.lua
   ```

   Already have an `init.lua`? Append the contents of `claude-box.lua` to it
   instead of overwriting.

3. Launch Hammerspoon, grant it **Accessibility** permission when prompted
   (System Settings → Privacy & Security → Accessibility). It needs this to move
   windows — nothing else. No network, no data access.

   The first time you re-tile or close the box, macOS also asks to let
   Hammerspoon **control your browser** (Automation permission). This lets the
   box ask Chrome/Edge which windows are on `claude.ai`, so surfaces like
   `claude.ai/code` and `claude.ai/design` are recognized regardless of how
   their tab is titled. If you decline, the box still works — it just falls
   back to matching windows by title (`… - Claude`).

4. Reload the config from the Hammerspoon menu-bar icon (**Reload Config**). You
   should see a "Claude Box loaded" alert.

## Usage

| Hotkey | Action |
| --- | --- |
| **⌥⌘C** | Open a batch of chats and tile the whole box into an even grid |
| **⌥⌘R** | Re-tile all Claude Box windows currently open (into an even grid) |
| **⌥⌘X** | Close Claude Box windows |

## Configuration

All knobs live at the top of `claude-box.lua`:

- `CLAUDE_URLS` — your standing set of chats. Use `https://claude.ai/new` for a
  fresh chat, or paste a specific conversation as `https://claude.ai/chat/<id>`.
  Add or remove freely; the list is cycled as needed to fill each batch.
- `BOX_TILE_LIMIT` — how many tiles a fresh (cold-start) **⌥⌘C** creates.
  Defaults to `4`, a steady 2x2. If the desktop app is already open and included,
  it counts as one of those tiles, so the cold-start batch is either four web
  chats or the desktop app plus three web chats (1 + 3 = 4). Keep it even.
- `ADD_BATCH` — how many new chats each later **⌥⌘C** press adds once a box
  already exists. Defaults to `4`, so the box grows 4 → 8 → 12. Keep it even so
  the box stays even. If a batch would ever leave an odd total, the box opens
  one extra chat so the grid is always even.
- `INCLUDE_DESKTOP` — `true` puts the Claude desktop app in the top-left cell and
  lets the chats fill the rest; `false` is browser-only (the original behavior).
- `DESKTOP_BUNDLE_ID` — the native app's bundle id,
  `com.anthropic.claudefordesktop` by default. This is the most reliable way to
  find the app.
- `DESKTOP_APP` — the desktop app's name, `"Claude"` by default. Used as a
  fallback if the bundle id changes.
- `BROWSER` — `"Google Chrome"` by default. Swap to `"Microsoft Edge"` for Edge.
- `SPAWN_STAGGER` (0.6s) — delay between opening each browser window.
- `PLACE_DELAY` (0.45s) — how long to wait for a window to appear before moving it.
- `OPEN_RETRY_INTERVAL` (0.25s) and `OPEN_MAX_WAIT` (3.0s) — how long to retry
  when waiting for a newly opened browser window to appear.

If windows don't reliably land in their cells, bump `SPAWN_STAGGER` and
`PLACE_DELAY` — the timing depends on your machine's speed.

Want the box isolated from your everyday browsing? Give it a dedicated profile
by adding `--user-data-dir="$HOME/.claude-box-chrome"` to the `open` command in
`openAppWindow` (you'll log into claude.ai once inside that profile).

## The desktop app tile

With `INCLUDE_DESKTOP = true`, **⌥⌘C** places the Claude desktop app as the
top-left tile alongside your browser chats, and **⌥⌘R** includes it when
re-tiling, but only when the desktop app has a window open. If the desktop app
has no window — whether it is fully quit or just idling in the background with
its window closed — the box uses that slot for another browser chat, so a fresh
open stays at four tiles. If the desktop app is minimized, its window still
counts: the script reserves one of those four slots, unminimizes it, and includes
it in the grid.

A cold-start **⌥⌘C** fills up to `BOX_TILE_LIMIT`. With the default settings,
that means either the desktop app plus three browser chats (1 + 3 = 4), or four
browser chats when the desktop app has no window open. Once a box already
exists, each **⌥⌘C** stacks another `ADD_BATCH` of chats on top and re-tiles the
whole box, so it grows 4 → 8 → 12. Whenever the desktop app has a window, every
retile reserves its slot and places it — unminimizing it first if needed — so it
is always included in the grid, even on later presses.

Because the desktop app is a single (odd) tile, the box counts it in and tops
the batch up when needed so the total stays even: 1 desktop + 3 chats = 4, then
+4 each press. If a batch or a manual close ever leaves an odd number of windows,
**⌥⌘C** and **⌥⌘R** open one extra chat so the grid is always even.

Two things to know:

- The desktop app is single-window, so it's exactly one tile. Its Chat / Code /
  Cowork tabs live inside that one pane; tiling can't split them into separate
  cells. Pick the tab you want up front — the tile shows whatever's active.
- It finds the app by `DESKTOP_BUNDLE_ID` first, then falls back to the app name.
  If that tile doesn't move, focus the app and run
  `hs.application.frontmostApplication():bundleID()` in the Hammerspoon console,
  then set `DESKTOP_BUNDLE_ID` to whatever it reports. You can also run
  `hs.application.frontmostApplication():name()` and adjust `DESKTOP_APP`.

## How it works

The box always tiles an even number of windows, packed into a filled
rectangle: 4 → 2x2, 6 → 3x2, 8 → 4x2, 12 → 4x3, 16 → 4x4 (wider than tall, to
suit widescreen displays). A cold-start batch is sized by `BOX_TILE_LIMIT` and
later presses add `ADD_BATCH` chats each; either way the count is rounded up to
even before tiling. When re-tiling existing windows, the script lays out every
remembered or discovered Claude Box window and ignores non-Claude browser
windows. Browser tiles open as app-mode windows
(`open -na <browser> --args --app='<url>'`) for clean frames with no tabs or
toolbar, then get moved into their cells. The box snapshots browser windows
before each open and remembers the newly created Claude window, so unrelated
Chrome tabs are not added just because they were focused. **⌥⌘R** re-tiles that
growing remembered set, then scans every running Chrome instance as a fallback.
The close hotkey uses the same Claude-window filter, so unrelated Chrome windows
are left alone.

To decide whether a browser window belongs to the box, the script asks the
browser (via AppleScript) which windows have a `claude.ai` tab in front, and
matches on that. This recognizes every claude.ai surface — `/new`, `/code`,
`/design`, `/chat` — no matter how the tab is titled, while leaving non-claude.ai
pages (say, a GitHub repo called `claude-box`) alone. Windows found this way
are unminimized before they're tiled, so a minimized or backgrounded chat still
lands in the grid. If Hammerspoon lacks Automation permission for the browser,
detection falls back to matching window titles that end in `- Claude`.

## Why this approach

- **Chrome/Edge windows for chats, desktop app as an optional single tile.** The
  native Claude desktop app is single-window and can't detach chats into separate
  OS-level windows, so it can only ever be one tile — hence the browser windows
  for everything you want side by side.
- **Manual URL list.** There's no API to read or discover your claude.ai
  conversations, so the standing set is hand-maintained.
- **Hammerspoon over yabai.** Hammerspoon needs only Accessibility permission;
  yabai requires partially disabling SIP.

## License

MIT — see [LICENSE](LICENSE).
