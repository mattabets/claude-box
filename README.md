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

4. Reload the config from the Hammerspoon menu-bar icon (**Reload Config**). You
   should see a "Claude board loaded" alert.

## Usage

| Hotkey | Action |
| --- | --- |
| **⌥⌘C** | Open your standing set of chats and tile them into a grid |
| **⌥⌘R** | Re-tile Claude windows that are already open |

## Configuration

All knobs live at the top of `claude-board.lua`:

- `CLAUDE_URLS` — your standing set of chats. Use `https://claude.ai/new` for a
  fresh chat, or paste a specific conversation as `https://claude.ai/chat/<id>`.
  Add or remove freely; the grid resizes to fit.
- `INCLUDE_DESKTOP` — `true` puts the Claude desktop app in the top-left cell and
  lets the chats fill the rest; `false` is browser-only (the original behavior).
- `DESKTOP_APP` — the desktop app's name, `"Claude"` by default. See "The desktop
  app tile" below if that tile doesn't move.
- `BROWSER` — `"Google Chrome"` by default. Swap to `"Microsoft Edge"` for Edge.
- `SPAWN_STAGGER` (0.6s) — delay between opening each browser window.
- `PLACE_DELAY` (0.45s) — how long to wait for a window to appear before moving it.
- `COLD_LAUNCH` (1.5s) — extra wait when the desktop app has to launch from closed.

If windows don't reliably land in their cells, bump `SPAWN_STAGGER` and
`PLACE_DELAY` — the timing depends on your machine's speed.

Want the board isolated from your everyday browsing? Give it a dedicated profile
by adding `--user-data-dir="$HOME/.claude-board-chrome"` to the `open` command in
`openAppWindow` (you'll log into claude.ai once inside that profile).

## The desktop app tile

With `INCLUDE_DESKTOP = true`, **⌥⌘C** places the Claude desktop app as the
top-left tile alongside your browser chats, and **⌥⌘R** includes it when
re-tiling. If the app isn't already open, the script launches it (brief pause the
first time — that's what `COLD_LAUNCH` covers).

Two things to know:

- The desktop app is single-window, so it's exactly one tile. Its Chat / Code /
  Cowork tabs live inside that one pane; tiling can't split them into separate
  cells. Pick the tab you want up front — the tile shows whatever's active.
- It assumes the app is named `"Claude"`. If that tile doesn't move, focus the app
  and run `hs.application.frontmostApplication():name()` in the Hammerspoon
  console, then set `DESKTOP_APP` to whatever it reports.

## How it works

The grid is `cols = ceil(sqrt(n))`, `rows = ceil(n / cols)` for `n` tiles (chats
plus the desktop app if included), laid out on the focused screen's usable frame
(excludes the menu bar and Dock). Browser tiles open as app-mode windows
(`open -na <browser> --args --app='<url>'`) for clean frames with no tabs or
toolbar, then get moved into their cells.

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
