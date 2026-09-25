-- Finder keyboard fixes. One eventtap, four behaviours, all scoped to Finder.
--
-- The theme: Finder's File and Edit commands act on the WINDOW's folder and
-- ignore which folder is highlighted. Each fix below retargets one command at
-- the selected folder, and falls through to stock behaviour when nothing
-- suitable is selected.
--
-- 1. Cmd+Shift+N       new folder inside the selected folder, without leaving
--                      the current one (asks for the name, since an unseen
--                      folder cannot be renamed inline).
-- 2. Cmd+C             during inline rename, copies the name as text. Finder's
--                      Edit > Copy stays bound to the file object even while
--                      the rename field holds focus.
-- 3. Cmd+Shift+C       copy the POSIX path of the selection. Natively "Go to
--    Cmd+Opt+C         Computer" and "Copy as Pathname" respectively; the
--                      latter silently no-ops when focus is off.
-- 4. Cmd+V / Cmd+Opt+V paste (copy / move) into the selected folder.

local M = {}

local FINDER_BUNDLE = "com.apple.finder"
local KEY_N = hs.keycodes.map.n
local KEY_C = hs.keycodes.map.c
local KEY_V = hs.keycodes.map.v

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

local function fail(text)
    hs.alert.show(text, { textSize = 15 }, 2.5)
end

-- AppleScript string literal.
local function asStr(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function basename(path)
    return path:gsub("/$", ""):match("[^/]+$") or path
end

-- Shared: the one selected folder ----------------------------------------

-- Empty string means "nothing we should retarget" — zero, several, or a
-- non-folder selected. Callers fall through to Finder's own behaviour.
local SELECTED_FOLDER = [[
tell application "Finder"
  set sel to selection
  if (count of sel) is not 1 then return ""
  set theItem to item 1 of sel
  if class of theItem is not folder then return ""
  return POSIX path of (theItem as alias)
end tell]]

local function selectedFolder()
    local ok, result = hs.osascript.applescript(SELECTED_FOLDER)
    if not ok or type(result) ~= "string" or result == "" then return nil end
    return (result:gsub("/$", ""))
end

-- 1. New folder inside the selected folder -------------------------------

local function newFolder(app)
    local dest = selectedFolder()
    dbg("newFolder: dest=%s", tostring(dest))
    if not dest then
        -- Nothing highlighted to retarget: stock New Folder, inline rename and all.
        app:selectMenuItem({ "File", "New Folder" })
        return
    end

    local button, name = hs.dialog.textPrompt(
        "New Folder in “" .. basename(dest) .. "”",
        "The window stays where it is, so name it here.",
        "untitled folder", "Create", "Cancel")
    if button ~= "Create" then return end
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    if name:find("/") then fail("A folder name cannot contain “/”") return end

    local ok, _, raw = hs.osascript.applescript(string.format([[
tell application "Finder"
  make new folder at (POSIX file %s as alias) with properties {name:%s}
end tell
return "ok"]], asStr(dest), asStr(name)))
    dbg("newFolder: create ok=%s", tostring(ok))
    if ok then
        flash("“" .. name .. "” → " .. basename(dest))
    else
        fail("Could not create “" .. name .. "”: " ..
            tostring(raw and raw.NSLocalizedDescription or "Finder refused"))
    end
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
    if (count of Finder windows) is 0 then return {}
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
  return out
end tell]]

local function copyPaths()
    local ok, result = hs.osascript.applescript(COPY_PATHS)
    dbg("copyPaths: ok=%s type=%s", tostring(ok), type(result))
    if not ok or type(result) ~= "table" or #result == 0 then
        fail("Nothing selected")
        return
    end
    -- AppleScript's POSIX path appends "/" to directories; Copy as Pathname
    -- does not, and a trailing slash breaks pasting into `cp a b`.
    local paths = {}
    for _, p in ipairs(result) do
        paths[#paths + 1] = (#p > 1) and p:gsub("/$", "") or p
    end
    local joined = table.concat(paths, "\n")
    hs.pasteboard.setContents(joined)
    flash(#paths > 1 and (#paths .. " paths copied") or joined)
end

-- 4. Paste into the selected folder --------------------------------------

-- Finder writes file URLs, not paths, and hs.pasteboard.readURL() only ever
-- returns the first. readObjectsForClasses: is the only route that gets them
-- all, so this drops into AppleScript-ObjC.
local PASTEBOARD_FILES = [[
use framework "Foundation"
use scripting additions
set pb to current application's NSPasteboard's generalPasteboard()
set theURLs to pb's readObjectsForClasses:({current application's NSURL}) options:(missing value)
set out to {}
if theURLs is missing value then return out
repeat with u in theURLs
  if (u's isFileURL()) as boolean then set end of out to (u's |path|()) as text
end repeat
return out]]

local function pasteboardFiles()
    local ok, result = hs.osascript.applescript(PASTEBOARD_FILES)
    if not ok or type(result) ~= "table" then return {} end
    return result
end

local function pasteInto(dest, move)
    local srcs = pasteboardFiles()
    dbg("pasteInto: dest=%s move=%s srcs=%d", tostring(dest), tostring(move), #srcs)
    if #srcs == 0 then
        fail("Clipboard has no files")
        return
    end
    local literals = {}
    for i, p in ipairs(srcs) do literals[i] = asStr(p) end

    local ok, _, raw = hs.osascript.applescript(string.format([[
set srcPaths to {%s}
set srcs to {}
repeat with p in srcPaths
  set end of srcs to (POSIX file (p as text) as alias)
end repeat
tell application "Finder"
  %s srcs to (POSIX file %s as alias)
end tell
return "ok"]], table.concat(literals, ", "), move and "move" or "duplicate", asStr(dest)))

    dbg("pasteInto: ok=%s", tostring(ok))
    if ok then
        flash(string.format("%s %d item%s → %s",
            move and "Moved" or "Copied", #srcs, #srcs == 1 and "" or "s", basename(dest)))
    else
        -- Finder refuses rather than offering Keep Both / Replace when a name
        -- already exists, so say which folder it was and why.
        fail("Paste into “" .. basename(dest) .. "” failed: " ..
            tostring(raw and raw.NSLocalizedDescription or "Finder refused"))
    end
end

-- Tap --------------------------------------------------------------------

-- Events this module posts itself, so the tap lets its own re-dispatch of a
-- key through instead of catching it again. Ordered delivery makes a counter
-- enough; a time window would misfire on a fast double press.
local synthetic = 0
local function passThrough(mods, key)
    synthetic = synthetic + 1
    hs.eventtap.keyStroke(mods, key, 0)
end

-- Assigned to _G so a Hammerspoon reload doesn't GC the tap.
_G.finderFixesTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    -- Fast bail: only Cmd+N / Cmd+C / Cmd+V pay for the app + AX lookups.
    local code = e:getKeyCode()
    if code ~= KEY_N and code ~= KEY_C and code ~= KEY_V then return false end
    local flags = e:getFlags()
    if not flags.cmd or flags.ctrl or flags.fn then return false end

    if synthetic > 0 then
        synthetic = synthetic - 1
        return false
    end

    local app = finderFrontmost()
    if not app then return false end
    dbg("tap: code=%d shift=%s alt=%s", code, tostring(flags.shift), tostring(flags.alt))

    if code == KEY_N then
        if not flags.shift or flags.alt then return false end
        -- Swallow first, work later: AppleScript inside a tap callback can run
        -- long enough for the system to disable the tap.
        hs.timer.doAfter(0, function() newFolder(app) end)
        return true
    end

    if code == KEY_V then
        if flags.shift then return false end
        -- Rename field open: that is a text paste, leave it alone.
        if focusedTextField(app) then return false end
        local move = flags.alt == true
        hs.timer.doAfter(0, function()
            local dest = selectedFolder()
            if dest then
                pasteInto(dest, move)
            else
                passThrough(move and { "cmd", "alt" } or { "cmd" }, "v")
            end
        end)
        return true
    end

    -- Cmd+Opt+C or Cmd+Shift+C -> copy path.
    if flags.shift or flags.alt then
        hs.timer.doAfter(0, copyPaths)
        return true
    end

    -- Plain Cmd+C -> only intercept while the rename field has focus.
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
