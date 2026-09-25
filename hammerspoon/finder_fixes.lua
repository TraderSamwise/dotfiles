-- Finder keyboard fixes. One eventtap, three behaviours, all scoped to Finder.
--
-- 1. Cmd+Shift+N — macOS always creates the new folder in the window's own
--    folder and ignores the selection. Here: if exactly one folder is selected,
--    navigate into it first, then fire Finder's own New Folder (so the inline
--    rename field still opens natively).
-- 2. Cmd+C during inline rename — Finder's Edit > Copy stays bound to the file
--    object even while the rename text field holds focus, so the name never
--    reaches the pasteboard as text. Here: copy the field's text.
-- 3. Cmd+Shift+C / Cmd+Opt+C — copy the POSIX path of the selection (newline
--    separated for multiple items), falling back to the window's own folder.
--    Cmd+Shift+C is natively "Go to Computer"; that is what it is replaced with.

local M = {}

local FINDER_BUNDLE = "com.apple.finder"
local KEY_N = hs.keycodes.map.n
local KEY_C = hs.keycodes.map.c

-- Set _G.finderFixesDebug = true to trace decisions into ~/.hammerspoon/finder_fixes.log
local LOG = os.getenv("HOME") .. "/.hammerspoon/finder_fixes.log"
local function dbg(fmt, ...)
    if not _G.finderFixesDebug then return end
    local f = io.open(LOG, "a")
    if f then
        f:write(os.date("%H:%M:%S ") .. string.format(fmt, ...) .. "\n")
        f:close()
    end
end

local function finderFrontmost()
    local app = hs.application.frontmostApplication()
    if app and app:bundleID() == FINDER_BUNDLE then return app end
    return nil
end

local function flash(text)
    local shown = #text > 90 and ("…" .. text:sub(-89)) or text
    hs.alert.show(shown, { textSize = 14 }, 1.2)
end

-- 1. New Folder in the selected folder -----------------------------------

-- Returns "entered" only when it actually moved the window into a selected
-- folder; every other outcome means "behave exactly like stock Cmd+Shift+N".
local ENTER_SELECTED_FOLDER = [[
tell application "Finder"
  if (count of Finder windows) is 0 then return "no-window"
  set sel to selection
  if (count of sel) is not 1 then return "passthrough"
  set theItem to item 1 of sel
  if class of theItem is not folder then return "passthrough"
  set target of front Finder window to theItem
  return "entered"
end tell
]]

local function newFolder(app)
    local ok, result = hs.osascript.applescript(ENTER_SELECTED_FOLDER)
    dbg("newFolder: enter ok=%s result=%s", tostring(ok), tostring(result))
    -- Entering changes the window's location; Finder needs a beat to load it
    -- before File > New Folder targets the right place.
    local delay = (ok and result == "entered") and 0.15 or 0
    hs.timer.doAfter(delay, function()
        local picked = app:selectMenuItem({ "File", "New Folder" })
        dbg("newFolder: selectMenuItem=%s", tostring(picked))
    end)
end

-- 2. Copy the inline rename field's text ---------------------------------

local function focusedTextField(app)
    local axApp = hs.axuielement.applicationElement(app)
    if not axApp then return nil end
    local focused = axApp:attributeValue("AXFocusedUIElement")
    if not focused then return nil end
    local role = focused:attributeValue("AXRole")
    if role ~= "AXTextField" and role ~= "AXTextArea" then return nil end
    return focused
end

local function copyFieldText(field)
    local selected = field:attributeValue("AXSelectedText")
    local text = (type(selected) == "string" and selected ~= "")
        and selected
        or field:attributeValue("AXValue")
    if type(text) ~= "string" or text == "" then return false end
    hs.pasteboard.setContents(text)
    flash(text)
    return true
end

-- 3. Copy the selection's path -------------------------------------------

local COPY_PATHS = [[
tell application "Finder"
  set sel to selection
  set out to {}
  if sel is {} then
    if (count of Finder windows) is 0 then return ""
    try
      set end of out to POSIX path of (target of front Finder window as alias)
    end try
  else
    repeat with anItem in sel
      try
        set end of out to POSIX path of (anItem as alias)
      end try
    end repeat
  end if
  set {oldDelims, AppleScript's text item delimiters} to {AppleScript's text item delimiters, linefeed}
  set joined to out as text
  set AppleScript's text item delimiters to oldDelims
  return joined
end tell
]]

local function copyPaths()
    local ok, result = hs.osascript.applescript(COPY_PATHS)
    dbg("copyPaths: ok=%s type=%s result=%q", tostring(ok), type(result), tostring(result))
    if not ok or type(result) ~= "string" or result == "" then
        hs.alert.show("Nothing selected", { textSize = 14 }, 1.0)
        return
    end
    -- AppleScript's POSIX path appends "/" to directories; Copy as Pathname
    -- does not, and a trailing slash breaks pasting into `cp a b`.
    local paths = {}
    for line in (result .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            paths[#paths + 1] = (#line > 1) and line:gsub("/$", "") or line
        end
    end
    if #paths == 0 then return end
    local joined = table.concat(paths, "\n")
    hs.pasteboard.setContents(joined)
    flash(#paths > 1 and (#paths .. " paths copied") or joined)
end

-- Tap --------------------------------------------------------------------

-- Assigned to _G so a Hammerspoon reload doesn't GC the tap.
_G.finderFixesTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    -- Fast bail: only Cmd+N / Cmd+C ever pay for the app + AX lookups.
    local code = e:getKeyCode()
    if code ~= KEY_N and code ~= KEY_C then return false end
    local flags = e:getFlags()
    if not flags.cmd or flags.fn then return false end

    local app = finderFrontmost()
    dbg("tap: code=%d cmd=%s shift=%s alt=%s ctrl=%s finder=%s",
        code, tostring(flags.cmd), tostring(flags.shift), tostring(flags.alt),
        tostring(flags.ctrl), tostring(app ~= nil))
    if not app then return false end

    if code == KEY_N then
        if not flags.shift or flags.alt or flags.ctrl then return false end
        -- Swallow first, work later: AppleScript inside a tap callback can run
        -- long enough for the system to disable the tap.
        hs.timer.doAfter(0, function() newFolder(app) end)
        return true
    end

    -- Cmd+Opt+C or Cmd+Shift+C -> copy path.
    if (flags.shift or flags.alt) and not flags.ctrl then
        hs.timer.doAfter(0, copyPaths)
        return true
    end

    -- Plain Cmd+C -> only intercept while the rename field has focus.
    if flags.shift or flags.alt or flags.ctrl then return false end
    local field = focusedTextField(app)
    if not field then return false end
    return copyFieldText(field)
end)
_G.finderFixesTap:start()

-- Debug helper: focus something in Finder, then
--   hs -c 'require("finder_fixes").inspectFocus()'
function M.inspectFocus()
    local app = finderFrontmost()
    if not app then print("Finder is not frontmost") return end
    local axApp = hs.axuielement.applicationElement(app)
    local f = axApp and axApp:attributeValue("AXFocusedUIElement")
    if not f then print("no focused element") return end
    print(string.format("AXRole=%s AXValue=%q AXSelectedText=%q",
        tostring(f:attributeValue("AXRole")),
        tostring(f:attributeValue("AXValue")),
        tostring(f:attributeValue("AXSelectedText"))))
end

return M
