# claude-board

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
   cp claude-board.lua ~/.hammerspoon/init.lua
   ```

   Already have an `init.lua`? Append the contents of `claude-board.lua` to it
   instead of overwriting.

3. Launch Hammerspoon, grant it **Accessibility** permission when prompted
   (System Settings → Privacy & Security → Accessibility). It needs this to move
   windows — nothing else. No network, no data access.

   The first time you re-tile or close the board, macOS also asks to let
   Hammerspoon **control your browser** (Automation permission). This lets the
   board ask Chrome/Edge which windows are on `claude.ai`, so surfaces like
   `claude.ai/code` and `claude.ai/design` are recognized regardless of how
   their tab is titled. If you decline, the board still works — it just falls
   back to matching windows by title (`… - Claude`).

4. Reload the config from the Hammerspoon menu-bar icon (**Reload Config**). You
   should see a "Claude board loaded" alert.

## Usage

| Hotkey | Action |
| --- | --- |
| **⌥⌘C** | Open another board batch and tile it |
| **⌥⌘R** | Re-tile all Claude board windows currently open |
| **⌥⌘X** | Close Claude board windows |

## Configuration

All knobs live at the top of `claude-board.lua`:

- `CLAUDE_URLS` — your standing set of chats. Use `https://claude.ai/new` for a
  fresh chat, or paste a specific conversation as `https://claude.ai/chat/<id>`.
  Add or remove freely; **⌥⌘C** uses as many as needed to fill `BOARD_TILE_LIMIT`.
- `BOARD_TILE_LIMIT` — how many tiles each **⌥⌘C** press should create. Defaults
  to `4`, which gives each new batch a steady 2x2. If the desktop app is already
  open and included, it counts as one of those tiles, so the default batch is
  either four web chats or three web chats plus the desktop app.
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

Want the board isolated from your everyday browsing? Give it a dedicated profile
by adding `--user-data-dir="$HOME/.claude-board-chrome"` to the `open` command in
`openAppWindow` (you'll log into claude.ai once inside that profile).

## The desktop app tile

With `INCLUDE_DESKTOP = true`, **⌥⌘C** places the Claude desktop app as the
top-left tile alongside your browser chats, and **⌥⌘R** includes it when
re-tiling, but only when the desktop app is already open. If the desktop app is
closed, the board uses that slot for another browser chat so the default fresh
open stays at four tiles. If the desktop app is minimized, the script
reserves one of those four slots, unminimizes it, and includes it in the grid.

Each **⌥⌘C** press is capped by `BOARD_TILE_LIMIT`. With the default settings,
that means each press opens either three browser chats plus the desktop app, or
four browser chats when the desktop app is not open. Whenever the desktop app is
open, every **⌥⌘C** press reserves its slot and places it — unminimizing it first
if needed — so it is always included in the grid regardless of window state, even
on later presses. Pressing **⌥⌘C** again adds another batch; **⌥⌘R** then lays out
the full board.

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

The grid uses a square board surface: 2x2, 3x3, 4x4, 5x5, and so on. Each fresh
batch is capped by `BOARD_TILE_LIMIT`; when re-tiling existing windows, the
script lays out every remembered or discovered Claude board window and ignores
non-Claude browser windows. Browser tiles open as app-mode windows
(`open -na <browser> --args --app='<url>'`) for clean frames with no tabs or
toolbar, then get moved into their cells. The board snapshots browser windows
before each open and remembers the newly created Claude window, so unrelated
Chrome tabs are not added just because they were focused. **⌥⌘R** re-tiles that
growing remembered set, then scans every running Chrome instance as a fallback.
The close hotkey uses the same Claude-window filter, so unrelated Chrome windows
are left alone.

To decide whether a browser window belongs to the board, the script asks the
browser (via AppleScript) which windows have a `claude.ai` tab in front, and
matches on that. This recognizes every claude.ai surface — `/new`, `/code`,
`/design`, `/chat` — no matter how the tab is titled, while leaving non-claude.ai
pages (say, a GitHub repo called `claude-board`) alone. Windows found this way
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
