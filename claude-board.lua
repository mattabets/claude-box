-- ~/.hammerspoon/init.lua
-- Claude board: open a set of claude.ai chats as app-mode windows and tile them.
-- Optionally include the Claude desktop app as one of the tiles.
-- Layout only — no status, no notifications (by design).
--
-- Hotkeys:
--   Opt+Cmd+C  -> open your standing set of chats and tile them into a grid
--   Opt+Cmd+R  -> re-tile Claude windows that are already open

hs.window.animationDuration = 0  -- instant snap, no slide animation

------------------------------------------------------------------------
-- 1) Your standing set of chats.
--    Use "https://claude.ai/new" for a fresh chat, or paste a specific
--    ongoing chat as "https://claude.ai/chat/<id>". Add/remove freely.
--    (There's no API to auto-discover your chats, so this is a manual list.)
------------------------------------------------------------------------
local CLAUDE_URLS = {
  "https://claude.ai/new",
  "https://claude.ai/new",
  "https://claude.ai/new",
  "https://claude.ai/new",
}

------------------------------------------------------------------------
-- 2) Include the Claude desktop app as a tile?
--    true  -> the desktop app takes the top-left cell, chats fill the rest.
--    false -> browser windows only (original behavior).
--
--    The desktop app is single-window: its Chat / Code / Cowork tabs live
--    inside that one pane, so it's exactly one tile — whichever tab is
--    active is what shows. Tiling can't split the tabs into separate cells.
--
--    DESKTOP_APP must match the app's name. If the tile doesn't move, focus
--    the app and run this in the Hammerspoon console:
--      hs.application.frontmostApplication():name()
--    then set DESKTOP_APP to whatever it reports.
------------------------------------------------------------------------
local INCLUDE_DESKTOP = true
local DESKTOP_APP     = "Claude"

------------------------------------------------------------------------
-- 3) How to open a clean app-mode window.
--    Chrome/Edge support --app. Safari cannot do CLI app-mode.
--    For Edge: replace "Google Chrome" with "Microsoft Edge".
--
--    Want the board isolated from your everyday browsing? Add a dedicated
--    profile dir (you'll log into claude.ai once inside it):
--      ... --args --user-data-dir="$HOME/.claude-board-chrome" --app='%s'
------------------------------------------------------------------------
local BROWSER = "Google Chrome"

local function openAppWindow(url)
  hs.execute(string.format(
    [[/usr/bin/open -na "%s" --args --app='%s']], BROWSER, url))
end

------------------------------------------------------------------------
-- Timing — bump these if windows don't reliably land in their cells.
------------------------------------------------------------------------
local SPAWN_STAGGER = 0.6   -- seconds between opening each window
local PLACE_DELAY   = 0.45  -- seconds to wait for a window before moving it
local COLD_LAUNCH   = 1.5   -- extra wait when the desktop app has to launch

-- Even-ish grid (cols x rows) for n windows.
local function gridDims(n)
  local cols = math.ceil(math.sqrt(n))
  local rows = math.ceil(n / cols)
  return cols, rows
end

-- Frame for cell index i (0-based) on the given screen.
local function cellFrame(i, n, screen)
  local f = screen:frame()          -- usable area, excludes menu bar + Dock
  local cols, rows = gridDims(n)
  local col = i % cols
  local row = math.floor(i / cols)
  local w = f.w / cols
  local h = f.h / rows
  return { x = f.x + col * w, y = f.y + row * h, w = w, h = h }
end

-- Place the desktop app into cell `idx`, launching it first if needed.
local function placeDesktopApp(idx, n, screen)
  local running = hs.application.get(DESKTOP_APP) ~= nil
  hs.application.open(DESKTOP_APP)  -- launches if closed, focuses if already open
  local wait = running and PLACE_DELAY or COLD_LAUNCH
  hs.timer.doAfter(wait, function()
    local app = hs.application.get(DESKTOP_APP)
    local win = app and app:mainWindow()
    if win then win:setFrame(cellFrame(idx, n, screen)) end
  end)
end

-- Open the whole set and tile each window as it appears.
local function openBoard()
  local screen = hs.screen.mainScreen()
  local offset = INCLUDE_DESKTOP and 1 or 0
  local n = #CLAUDE_URLS + offset

  if INCLUDE_DESKTOP then
    placeDesktopApp(0, n, screen)   -- desktop app = top-left tile
  end

  for i, url in ipairs(CLAUDE_URLS) do
    local idx = (i - 1) + offset
    hs.timer.doAfter((i - 1) * SPAWN_STAGGER, function()
      openAppWindow(url)
      hs.timer.doAfter(PLACE_DELAY, function()
        local app = hs.application.get(BROWSER)
        local win = app and app:focusedWindow()
        if win then win:setFrame(cellFrame(idx, n, screen)) end
      end)
    end)
  end
end

-- Re-tile Claude windows already open (desktop app first, then browser).
local function retileExisting()
  local screen = hs.screen.mainScreen()
  local wins = {}

  if INCLUDE_DESKTOP then
    local dapp = hs.application.get(DESKTOP_APP)
    local dwin = dapp and dapp:mainWindow()
    if dwin then wins[#wins + 1] = dwin end
  end

  local app = hs.application.get(BROWSER)
  if app then
    for _, w in ipairs(app:allWindows()) do
      local t = (w:title() or ""):lower()
      if t:find("claude") then wins[#wins + 1] = w end
    end
  end

  for i, w in ipairs(wins) do
    w:setFrame(cellFrame(i - 1, #wins, screen))
  end
end

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
hs.hotkey.bind({ "alt", "cmd" }, "C", openBoard)
hs.hotkey.bind({ "alt", "cmd" }, "R", retileExisting)

hs.alert.show("Claude board loaded")
