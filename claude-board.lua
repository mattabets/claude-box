-- ~/.hammerspoon/init.lua
-- Claude board: open a set of claude.ai chats as app-mode windows and tile them.
-- Optionally include the Claude desktop app as one of the tiles.
-- Layout only — no status, no notifications (by design).
--
-- Hotkeys:
--   Opt+Cmd+C  -> open your standing set of chats and tile them into a grid
--   Opt+Cmd+R  -> re-tile Claude windows that are already open
--   Opt+Cmd+X  -> close Claude board windows

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

-- How many tiles Opt+Cmd+C should create on a fresh board open.
-- The default 4 keeps the board in a steady 2x2. If the desktop app is
-- already open and included, it counts as one of these tiles.
local BOARD_TILE_LIMIT = 4

------------------------------------------------------------------------
-- 2) Include the Claude desktop app as a tile?
--    true  -> the desktop app takes the top-left cell if it is already open;
--             otherwise that slot becomes another browser chat.
--    false -> browser windows only (original behavior).
--
--    The desktop app is single-window: its Chat / Code / Cowork tabs live
--    inside that one pane, so it's exactly one tile — whichever tab is
--    active is what shows. Tiling can't split the tabs into separate cells.
--
--    DESKTOP_BUNDLE_ID is the most reliable way to find the native app. If
--    Anthropic changes it, focus the app and run this in the Hammerspoon console:
--      hs.application.frontmostApplication():bundleID()
--
--    DESKTOP_APP is a fallback. If the tile still doesn't move, focus the app
--    and run:
--      hs.application.frontmostApplication():name()
------------------------------------------------------------------------
local INCLUDE_DESKTOP = true
local DESKTOP_BUNDLE_ID = "com.anthropic.claudefordesktop"
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
local BROWSER_BUNDLE_IDS = {
  ["Google Chrome"] = "com.google.Chrome",
  ["Microsoft Edge"] = "com.microsoft.edgemac",
}

local BOARD_WINDOWS = {}

local function openAppWindow(url)
  hs.execute(string.format(
    [[/usr/bin/open -na "%s" --args --app='%s']], BROWSER, url))
end

------------------------------------------------------------------------
-- Timing — bump these if windows don't reliably land in their cells.
------------------------------------------------------------------------
local SPAWN_STAGGER = 0.6   -- seconds between opening each window
local PLACE_DELAY   = 0.45  -- seconds to wait for a window before moving it
local OPEN_RETRY_INTERVAL = 0.25
local OPEN_MAX_WAIT       = 3.0

-- Square grid surface (cols x rows) for n windows. This keeps the board
-- visually even as it grows: 2x2, 3x3, 4x4, 5x5, etc.
local function gridDims(n)
  local side = math.ceil(math.sqrt(n))
  return side, side
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

local function desktopApp()
  return hs.application.get(DESKTOP_BUNDLE_ID) or hs.application.get(DESKTOP_APP)
end

local function windowKey(win)
  if not win then return nil end

  local ok, id = pcall(function() return win:id() end)
  if ok and id then return id end

  local titleOk, title = pcall(function() return win:title() end)
  local appOk, app = pcall(function() return win:application() end)
  local pid = appOk and app and app:pid() or "unknown"

  if titleOk and title and title ~= "" then return tostring(pid) .. ":" .. title end
  return tostring(win)
end

local function isLiveWindow(win)
  return windowKey(win) ~= nil
end

local function prepareWindow(win)
  if not win then return nil end

  local minimizedOk, minimized = pcall(function() return win:isMinimized() end)
  if minimizedOk and minimized then win:unminimize() end

  local visibleOk, visible = pcall(function() return win:isVisible() end)
  if visibleOk and not visible then win:unminimize() end

  pcall(function() win:raise() end)
  return win
end

local function firstUsableWindow(app)
  if not app then return nil end

  local main = app:mainWindow()
  if main and main:isStandard() then return prepareWindow(main) end

  local fallback = main

  for _, win in ipairs(app:visibleWindows()) do
    if win:isStandard() then return prepareWindow(win) end
    fallback = fallback or win
  end

  for _, win in ipairs(app:allWindows()) do
    if win:isStandard() then
      return prepareWindow(win)
    end
    fallback = fallback or win
  end

  return prepareWindow(fallback)
end

local function desktopWindow()
  if not INCLUDE_DESKTOP then return nil end

  local app = desktopApp()
  if not app then return nil end

  app:unhide()
  app:activate(true)

  local win = firstUsableWindow(app)
  if win then
    prepareWindow(win)
    pcall(function() win:focus() end)
  end

  return win
end

local function isBrowserApp(app)
  if not app then return false end
  if app:name() == BROWSER then return true end

  local expectedBundleID = BROWSER_BUNDLE_IDS[BROWSER]
  return expectedBundleID ~= nil and app:bundleID() == expectedBundleID
end

local function browserApps()
  local apps = {}
  local seen = {}

  for _, app in ipairs(hs.application.runningApplications()) do
    if isBrowserApp(app) then
      local key = app:pid() or tostring(app)
      if not seen[key] then
        apps[#apps + 1] = app
        seen[key] = true
      end
    end
  end

  return apps
end

local function browserWindowIds()
  local ids = {}

  for _, app in ipairs(browserApps()) do
    for _, win in ipairs(app:allWindows()) do
      local id = win:id()
      if id then ids[id] = true end
    end
  end

  for _, win in ipairs(hs.window.allWindows()) do
    local app = win:application()
    local id = win:id()
    if id and isBrowserApp(app) then ids[id] = true end
  end

  return ids
end

local function newBrowserWindow(previousIds)
  local seen = {}

  for _, app in ipairs(browserApps()) do
    for _, win in ipairs(app:allWindows()) do
      local id = win:id()
      if id and not previousIds[id] and not seen[id] then
        return win
      end
      if id then seen[id] = true end
    end
  end

  for _, win in ipairs(hs.window.allWindows()) do
    local app = win:application()
    local id = win:id()
    if id and isBrowserApp(app) and not previousIds[id] and not seen[id] then
      return win
    end
  end

  return nil
end

-- Strip a trailing " - <Browser>" (e.g. " - Google Chrome") that some builds
-- append to window titles, so a title reported by the browser's AppleScript
-- lines up with the one Hammerspoon reports for the same window.
local function stripBrowserSuffix(title)
  local suffix = " - " .. BROWSER
  if #title >= #suffix and title:sub(-#suffix):lower() == suffix:lower() then
    return title:sub(1, #title - #suffix)
  end
  return title
end

-- Conservative title match for the common chat windows ("New chat - Claude").
-- This is the fallback signal when the browser can't be queried for URLs. Kept
-- narrow so a page like a GitHub repo titled "claude-board" is not swept in, but
-- it does NOT catch surfaces whose tab is titled "Claude Code" / "Claude Design"
-- — the URL check below is what covers those.
local function matchesClaudeTitleHeuristic(title)
  return title == "claude"
    or title:match("%s%-%sclaude$") ~= nil
    or title:match("%s%-%sclaude%s%-%s") ~= nil
    or title:match("^claude%s%-%s") ~= nil
end

-- Ask the configured browser which of its windows have a claude.ai tab in front
-- and return their (normalized) titles as a set. This is the URL-based signal:
-- it recognizes any claude.ai surface — /new, /code, /design, /chat — regardless
-- of how the tab is titled, and naturally ignores non-claude.ai pages (a
-- github.com repo called "claude-board" is not matched).
--
-- Requires Hammerspoon to hold Automation permission for the browser (macOS
-- prompts once). If that is denied, or the browser isn't running, this returns
-- an empty set and detection falls back to matchesClaudeTitleHeuristic. We skip
-- the query entirely when no browser is running so we never launch one just to
-- ask. Only the active tab of each window is inspected, which is exactly right
-- for the board's single-tab app-mode windows.
local function claudeUrlTitleSet()
  if #browserApps() == 0 then return {} end

  local script = string.format([[
tell application "%s"
  set outText to ""
  repeat with w in windows
    try
      if (URL of active tab of w) contains "claude.ai" then
        set outText to outText & (title of w) & linefeed
      end if
    end try
  end repeat
  return outText
end tell
]], BROWSER)

  local ok, result = hs.osascript.applescript(script)
  local titles = {}
  if ok and type(result) == "string" then
    for line in result:gmatch("[^\r\n]+") do
      titles[stripBrowserSuffix(line):lower()] = true
    end
  end

  return titles
end

-- Is this browser window a Claude board window? Prefer the URL signal: if the
-- browser reported a claude.ai window with this title, it counts whatever the
-- title text is. Otherwise fall back to the title heuristic.
local function isClaudeBrowserWindow(win, urlTitles)
  local raw = win:title() or ""

  if urlTitles and urlTitles[stripBrowserSuffix(raw):lower()] then
    return true
  end

  return matchesClaudeTitleHeuristic(raw:lower())
end

local function rememberBoardWindow(win)
  if not isLiveWindow(win) then return end

  local key = windowKey(win)
  for _, existing in ipairs(BOARD_WINDOWS) do
    if isLiveWindow(existing) and windowKey(existing) == key then return end
  end

  BOARD_WINDOWS[#BOARD_WINDOWS + 1] = win
end

local function activeBoardWindows(limit)
  local wins = {}
  local seen = {}

  for _, win in ipairs(BOARD_WINDOWS) do
    local key = isLiveWindow(win) and windowKey(win) or nil
    if key and not seen[key] then
      wins[#wins + 1] = prepareWindow(win)
      seen[key] = true
      if limit and #wins >= limit then return wins end
    end
  end

  BOARD_WINDOWS = wins
  return wins
end

local function claudeBrowserWindows(limit)
  local wins = {}
  local seen = {}
  local urlTitles = claudeUrlTitleSet()

  for _, app in ipairs(browserApps()) do
    for _, win in ipairs(app:allWindows()) do
      local key = win:id() or tostring(win)
      if not seen[key] and isClaudeBrowserWindow(win, urlTitles) then
        wins[#wins + 1] = prepareWindow(win)
        seen[key] = true
        if limit and #wins >= limit then return wins end
      end
    end
  end

  for _, win in ipairs(hs.window.allWindows()) do
    local app = win:application()
    local key = win:id() or tostring(win)
    if isBrowserApp(app) and not seen[key] and isClaudeBrowserWindow(win, urlTitles) then
      wins[#wins + 1] = prepareWindow(win)
      seen[key] = true
      if limit and #wins >= limit then return wins end
    end
  end

  return wins
end

local function openBrowserTile(url, idx, n, screen)
  local previousIds = browserWindowIds()
  openAppWindow(url)

  local function placeOpenedWindow(attemptsLeft)
    local win = newBrowserWindow(previousIds)
    if win then
      win:setFrame(cellFrame(idx, n, screen))
      rememberBoardWindow(win)
      return
    end

    if attemptsLeft > 0 then
      hs.timer.doAfter(OPEN_RETRY_INTERVAL, function()
        placeOpenedWindow(attemptsLeft - 1)
      end)
    else
      hs.alert.show("Claude browser window not found")
    end
  end

  hs.timer.doAfter(PLACE_DELAY, function()
    placeOpenedWindow(math.ceil(OPEN_MAX_WAIT / OPEN_RETRY_INTERVAL))
  end)
end

local function placeDesktopTile(idx, n, screen, attemptsLeft)
  attemptsLeft = attemptsLeft or math.ceil(OPEN_MAX_WAIT / OPEN_RETRY_INTERVAL)

  local win = desktopWindow()
  if win then
    win:setFrame(cellFrame(idx, n, screen))
    rememberBoardWindow(win)
    return
  end

  if attemptsLeft > 0 then
    hs.timer.doAfter(OPEN_RETRY_INTERVAL, function()
      placeDesktopTile(idx, n, screen, attemptsLeft - 1)
    end)
  else
    hs.alert.show("Claude desktop window not found")
  end
end

-- Open a fresh board and tile each window as it appears.
local function openBoard()
  local screen = hs.screen.mainScreen()
  -- Include the desktop app whenever it is open, regardless of window state.
  -- placeDesktopTile unminimizes it if needed, so a minimized app still claims
  -- its slot. Only when the app is not running does the board fall back to
  -- filling every slot with browser chats.
  local dapp = INCLUDE_DESKTOP and desktopApp() or nil
  local wantsDesktop = dapp ~= nil and BOARD_TILE_LIMIT > 0
  local offset = wantsDesktop and 1 or 0
  local browserCount = math.min(#CLAUDE_URLS, math.max(BOARD_TILE_LIMIT - offset, 0))
  local n = browserCount + offset

  if n == 0 then return end

  if wantsDesktop then
    placeDesktopTile(0, n, screen)
  end

  for i = 1, browserCount do
    local url = CLAUDE_URLS[i]
    local idx = (i - 1) + offset
    hs.timer.doAfter((i - 1) * SPAWN_STAGGER, function()
      openBrowserTile(url, idx, n, screen)
    end)
  end
end

-- Re-tile Claude windows already open (desktop app first, then browser).
local function retileExisting()
  local screen = hs.screen.mainScreen()
  local wins = {}
  local seen = {}

  local function addWindow(win)
    local key = isLiveWindow(win) and windowKey(win) or nil
    if key and not seen[key] then
      wins[#wins + 1] = win
      seen[key] = true
    end
  end

  addWindow(desktopWindow())

  for _, win in ipairs(activeBoardWindows()) do
    addWindow(win)
  end

  for _, win in ipairs(claudeBrowserWindows()) do
    addWindow(win)
  end

  if #wins == 0 then
    hs.alert.show("No Claude board windows found")
    return
  end

  for i, w in ipairs(wins) do
    w:setFrame(cellFrame(i - 1, #wins, screen))
    rememberBoardWindow(w)
  end

  hs.alert.show(string.format("Retiled %d Claude board window%s", #wins, #wins == 1 and "" or "s"))
end

-- Close Claude board windows without touching unrelated browser windows.
local function closeBoard()
  local closed = 0
  local seen = {}

  for _, win in ipairs(activeBoardWindows()) do
    local key = windowKey(win)
    if key and not seen[key] then
      win:close()
      closed = closed + 1
      seen[key] = true
    end
  end

  local dwin = desktopWindow()
  local dkey = windowKey(dwin)
  if dwin and dkey and not seen[dkey] then
    dwin:close()
    closed = closed + 1
    seen[dkey] = true
  end

  for _, win in ipairs(claudeBrowserWindows()) do
    local key = windowKey(win)
    if key and not seen[key] then
      win:close()
      closed = closed + 1
      seen[key] = true
    end
  end

  BOARD_WINDOWS = {}
  hs.alert.show(string.format("Closed %d Claude board window%s", closed, closed == 1 and "" or "s"))
end

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
hs.hotkey.bind({ "alt", "cmd" }, "C", openBoard)
hs.hotkey.bind({ "alt", "cmd" }, "R", retileExisting)
hs.hotkey.bind({ "alt", "cmd" }, "X", closeBoard)

hs.alert.show("Claude board loaded")
