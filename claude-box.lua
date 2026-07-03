-- ~/.hammerspoon/init.lua
-- Claude Box: open a set of claude.ai chats as app-mode windows and tile them.
-- Optionally include the Claude desktop app as one of the tiles.
-- Layout only — no status, no notifications (by design).
--
-- Hotkeys:
--   Opt+Cmd+C  -> open your standing set of chats and tile them into a grid
--   Opt+Cmd+R  -> re-tile Claude windows that are already open
--   Opt+Cmd+X  -> close Claude Box windows

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

-- How many tiles a fresh (cold-start) Opt+Cmd+C should create.
-- The default 4 keeps the box in a steady 2x2. If the desktop app is
-- already open and included, it counts as one of these tiles (1 desktop +
-- 3 chats = 4). Keep this even so the box starts even.
local BOX_TILE_LIMIT = 4

-- How many new chats each later Opt+Cmd+C press adds once a box already
-- exists. Keep this even so the box stays even as it grows: 4 -> 8 -> 12.
local ADD_BATCH = 4

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
--    Want the box isolated from your everyday browsing? Add a dedicated
--    profile dir (you'll log into claude.ai once inside it):
--      ... --args --user-data-dir="$HOME/.claude-box-chrome" --app='%s'
------------------------------------------------------------------------
local BROWSER = "Google Chrome"
local BROWSER_BUNDLE_IDS = {
  ["Google Chrome"] = "com.google.Chrome",
  ["Microsoft Edge"] = "com.microsoft.edgemac",
}

local BOX_WINDOWS = {}

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

-- Balanced grid surface (cols x rows) for n windows. The box always tiles an
-- even number of windows (see evenCount + the open/retile logic), and this packs
-- an even count into a filled rectangle rather than a square with a gap:
-- 4 -> 2x2, 6 -> 3x2, 8 -> 4x2, 12 -> 4x3, 16 -> 4x4. Wider than tall, which
-- suits typical widescreen displays.
local function gridDims(n)
  if n <= 0 then return 1, 1 end
  local rows = math.floor(math.sqrt(n))
  if rows < 1 then rows = 1 end
  local cols = math.ceil(n / rows)
  return cols, rows
end

-- Round a tile count up to the nearest even number so the grid is always even.
local function evenCount(n)
  if n <= 0 then return 0 end
  if n % 2 == 1 then return n + 1 end
  return n
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

-- Does the desktop app actually have a window we could tile? This is a pure
-- check with no side effects — it does NOT activate or unhide the app.
--
-- The distinction matters: the Claude desktop app keeps its process running in
-- the background after you close its window, so desktopApp() (which only reports
-- whether the process is alive) stays truthy even when there is nothing to
-- place. A minimized window still counts as present here — it lives in
-- allWindows() and gets unminimized when placed — matching "reserve the slot
-- when minimized".
local function desktopHasWindow()
  if not INCLUDE_DESKTOP then return false end

  local app = desktopApp()
  if not app then return false end

  return #app:allWindows() > 0
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
-- narrow so a page like a GitHub repo titled "claude-box" is not swept in, but
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
-- github.com repo called "claude-box" is not matched).
--
-- Requires Hammerspoon to hold Automation permission for the browser (macOS
-- prompts once). If that is denied, or the browser isn't running, this returns
-- an empty set and detection falls back to matchesClaudeTitleHeuristic. We skip
-- the query entirely when no browser is running so we never launch one just to
-- ask. Only the active tab of each window is inspected, which is exactly right
-- for the box's single-tab app-mode windows.
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

-- Is this browser window a Claude Box window? Prefer the URL signal: if the
-- browser reported a claude.ai window with this title, it counts whatever the
-- title text is. Otherwise fall back to the title heuristic.
local function isClaudeBrowserWindow(win, urlTitles)
  local raw = win:title() or ""

  if urlTitles and urlTitles[stripBrowserSuffix(raw):lower()] then
    return true
  end

  return matchesClaudeTitleHeuristic(raw:lower())
end

local function rememberBoxWindow(win)
  if not isLiveWindow(win) then return end

  local key = windowKey(win)
  for _, existing in ipairs(BOX_WINDOWS) do
    if isLiveWindow(existing) and windowKey(existing) == key then return end
  end

  BOX_WINDOWS[#BOX_WINDOWS + 1] = win
end

local function activeBoxWindows(limit)
  local wins = {}
  local seen = {}

  for _, win in ipairs(BOX_WINDOWS) do
    local key = isLiveWindow(win) and windowKey(win) or nil
    if key and not seen[key] then
      wins[#wins + 1] = prepareWindow(win)
      seen[key] = true
      if limit and #wins >= limit then return wins end
    end
  end

  BOX_WINDOWS = wins
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

-- Open one app-mode chat window, remember it as a box window, and invoke
-- callback(win) once it appears (callback(nil) if it never does). Every new tile
-- is created here, so openBox and retileExisting share one "open, remember,
-- then retile" shape.
local function openChatWindow(url, callback)
  local previousIds = browserWindowIds()
  openAppWindow(url)

  local function grab(attemptsLeft)
    local win = newBrowserWindow(previousIds)
    if win then
      rememberBoxWindow(win)
      if callback then callback(win) end
      return
    end

    if attemptsLeft > 0 then
      hs.timer.doAfter(OPEN_RETRY_INTERVAL, function()
        grab(attemptsLeft - 1)
      end)
    else
      hs.alert.show("Claude browser window not found")
      if callback then callback(nil) end
    end
  end

  hs.timer.doAfter(PLACE_DELAY, function()
    grab(math.ceil(OPEN_MAX_WAIT / OPEN_RETRY_INTERVAL))
  end)
end

-- Every Claude Box window right now, deduped and ordered desktop-first: the
-- desktop app (only when it actually has a window to tile), then the remembered
-- box set, then any discovered claude.ai browser windows. Used both to count
-- the box before growing it and to gather the full set for a retile.
local function currentBoxWindows()
  local wins = {}
  local seen = {}

  local function add(win)
    local key = isLiveWindow(win) and windowKey(win) or nil
    if key and not seen[key] then
      wins[#wins + 1] = prepareWindow(win)
      seen[key] = true
    end
  end

  if desktopHasWindow() then add(desktopWindow()) end

  for _, win in ipairs(activeBoxWindows()) do add(win) end
  for _, win in ipairs(claudeBrowserWindows()) do add(win) end

  return wins
end

-- Lay a set of windows into the grid and (re)remember them. gridDims packs an
-- even count into a filled rectangle.
local function tileWindows(wins, screen)
  screen = screen or hs.screen.mainScreen()
  for i, w in ipairs(wins) do
    w:setFrame(cellFrame(i - 1, #wins, screen))
    rememberBoxWindow(w)
  end
end

-- Gather the whole box and tile it into an EVEN grid: if the count is odd,
-- open one extra chat first, then tile. Shared by openBox's finalization and
-- the retile hotkey so "the grid is always even" holds however we got here.
local function tileBoxEven(screen, announce)
  screen = screen or hs.screen.mainScreen()
  local wins = currentBoxWindows()

  local function report(all)
    if announce then
      hs.alert.show(string.format(
        "Retiled %d Claude Box window%s", #all, #all == 1 and "" or "s"))
    end
  end

  if #wins == 0 then
    if announce then hs.alert.show("No Claude Box windows found") end
    return
  end

  if #wins % 2 == 1 then
    openChatWindow(CLAUDE_URLS[1], function()
      hs.timer.doAfter(PLACE_DELAY, function()
        local all = currentBoxWindows()
        tileWindows(all, screen)
        report(all)
      end)
    end)
    return
  end

  tileWindows(wins, screen)
  report(wins)
end

-- Open a box and tile it into an even grid.
--
-- Cold start (no box windows yet, or only the desktop app holding a slot):
-- fill up to BOX_TILE_LIMIT, so with the desktop app open you get 1 desktop +
-- 3 chats = 4. Once a box already exists, each press stacks another ADD_BATCH
-- of chats on top (4 -> 8 -> 12). Either way the batch is topped up so the final
-- count is even before tiling, and the closing retile enforces even once more in
-- case a window failed to open — the grid is always even.
local function openBox()
  local screen = hs.screen.mainScreen()
  local haveCount = #currentBoxWindows()

  local newCount
  if haveCount <= 1 then
    newCount = math.max(BOX_TILE_LIMIT - haveCount, 0)
  else
    newCount = ADD_BATCH
  end

  -- Keep the grid even: if this batch would leave an odd total, open one more.
  newCount = evenCount(haveCount + newCount) - haveCount

  if newCount <= 0 then
    tileBoxEven(screen, false)
    return
  end

  -- Open chats one at a time (each recomputes the "new window" baseline), then
  -- retile the whole box once the last one has landed.
  local function openNext(i)
    if i > newCount then
      hs.timer.doAfter(PLACE_DELAY, function()
        tileBoxEven(screen, false)
      end)
      return
    end

    local url = CLAUDE_URLS[((i - 1) % #CLAUDE_URLS) + 1]
    openChatWindow(url, function()
      hs.timer.doAfter(SPAWN_STAGGER, function()
        openNext(i + 1)
      end)
    end)
  end

  openNext(1)
end

-- Re-tile Claude windows already open (desktop app first, then browser) into an
-- even grid. If the box holds an odd number of windows, one more chat is
-- opened first so the grid stays even.
local function retileExisting()
  tileBoxEven(hs.screen.mainScreen(), true)
end

-- Close Claude Box windows without touching unrelated browser windows.
local function closeBox()
  local closed = 0
  local seen = {}

  for _, win in ipairs(activeBoxWindows()) do
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

  BOX_WINDOWS = {}
  hs.alert.show(string.format("Closed %d Claude Box window%s", closed, closed == 1 and "" or "s"))
end

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
hs.hotkey.bind({ "alt", "cmd" }, "C", openBox)
hs.hotkey.bind({ "alt", "cmd" }, "R", retileExisting)
hs.hotkey.bind({ "alt", "cmd" }, "X", closeBox)

hs.alert.show("Claude Box loaded")
