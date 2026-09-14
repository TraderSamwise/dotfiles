-- Assign focused app to a specific desktop space
-- Hotkeys: Ctrl+Shift + [1-9]
-- Example: You're on Space 1 with Claude focused. Press Ctrl+Shift+2.
--   1. Remembers "Claude" is the focused app
--   2. Switches to Space 2 (via hyper+2 keystroke)
--   3. Waits for the space switch animation
--   4. Assigns Claude to Space 2 via Dock context menu

-- macOS's native "Switch to Desktop N" shortcuts live on hyper+N (moved off
-- ctrl+N so Hammerspoon can own ctrl+N — see the Space switching section below).
local HYPER = {"cmd", "alt", "ctrl", "shift"}

local function assignAppToDock(appName)
  local script = string.format([[
    tell application "System Events"
      tell UI element "%s" of list 1 of process "Dock"
        perform action "AXShowMenu"
        delay 0.06
      end tell

      tell process "Dock"
        click menu item "Options" of menu 1 of UI element "%s" of list 1
        delay 0.04
        click menu item "This Desktop" of menu 1 of menu item "Options" of menu 1 of UI element "%s" of list 1
      end tell
    end tell
  ]], appName, appName, appName)

  local ok, result = hs.osascript.applescript(script)
  if ok then
    hs.alert.show("\"" .. appName .. "\" assigned to Desktop")
  else
    hs.alert.show("Failed: " .. tostring(result))
  end
end

for i = 1, 9 do
  hs.hotkey.bind({"ctrl", "shift"}, tostring(i), function()
    -- Step 1: Remember the focused app
    local app = hs.application.frontmostApplication()
    if not app then
      hs.alert.show("No focused app found")
      return
    end
    local appName = app:name()
    hs.alert.show("Moving \"" .. appName .. "\" to Desktop " .. i)

    -- Step 2: Switch to the target space (hyper+N is the native Desktop-N key)
    hs.eventtap.keyStroke(HYPER, tostring(i))

    -- Step 3: Wait for space switch animation, then assign
    hs.timer.doAfter(0.1, function()
      assignAppToDock(appName)
    end)
  end)
end

-- Keep the standalone assign hotkey too (for manual use)
hs.hotkey.bind({"ctrl", "shift"}, "A", function()
  local app = hs.application.frontmostApplication()
  if not app then
    hs.alert.show("No focused app found")
    return
  end
  local appName = app:name()
  hs.alert.show("Assigning \"" .. appName .. "\" to this desktop...")
  assignAppToDock(appName)
end)

require("hs.ipc")  -- enable `hs -c "..."` CLI

-- Machine-private config (visor apps, NAS mounts, personal watchers) lives in the
-- untracked ~/.hammerspoon/init.local.lua, which returns { visors = { ... } }.
local localConfig = {}
local localConfigPath = hs.configdir .. "/init.local.lua"
if hs.fs.attributes(localConfigPath) then
    local ok, result = pcall(dofile, localConfigPath)
    if ok then
        localConfig = type(result) == "table" and result or {}
    else
        print("init.local.lua failed: " .. tostring(result))
        hs.alert.show("init.local.lua failed: " .. tostring(result), 10)
    end
end

-- Visor toggles: summon an app onto the current Space and focus it; press the
-- same hotkey again to hide it and return to where you were.
--
-- Each app must be set to "Assign To → All Desktops" (right-click its Dock icon
-- → Options) so its window follows you across Spaces. That native setting does
-- the Space-following — this script is just a dumb show/hide toggle.
-- To add an app or change a hotkey: edit `visors` in init.local.lua. One line each.
-- (Electron apps often report a different name than the .app, so use bundleID.)
local visorPrevApp = {}
local function toggleVisor(cfg)
    local key = cfg.bundleID or cfg.app
    local app = cfg.bundleID and hs.application.get(cfg.bundleID) or hs.application.get(cfg.app)
    local front = hs.application.frontmostApplication()
    if app and front and app:pid() == front:pid() then
        app:hide()
        local prev = visorPrevApp[key]
        if prev and prev:isRunning() then prev:activate() end
        return
    end
    visorPrevApp[key] = front
    if cfg.bundleID then
        hs.application.launchOrFocusByBundleID(cfg.bundleID)
    else
        hs.application.launchOrFocus(cfg.app)
    end
end


-- Without init.local.lua, only the Finder visor is bound.
local visors = localConfig.visors or {
    { app = "Finder", mods = {"alt"}, key = "`" },
}
for _, v in ipairs(visors) do
    hs.hotkey.bind(v.mods, v.key, function() toggleVisor(v) end)
end

-- Space switching. ctrl+N is Hammerspoon-owned so visor apps are hidden BEFORE
-- the switch — their sticky "All Desktops" windows otherwise smear through the
-- transition. The switch itself stays native: we synthesize hyper+N.
local function dismissVisors()
    local hidAny = false
    for _, cfg in ipairs(visors) do
        local app = not cfg.keepOnSpaceSwitch
            and (cfg.bundleID and hs.application.get(cfg.bundleID) or hs.application.get(cfg.app))
        -- Guard: rare race where hs.application.get() returns a userdata
        -- that lacks isHidden (stale handle just after app quit/relaunch).
        -- Would otherwise blow up dismissVisors and break ctrl+N.
        if app and app.isHidden and not app:isHidden() then
            app:hide()
            hidAny = true
        end
    end
    return hidAny
end

for i = 0, 9 do
    local key = tostring(i)
    hs.hotkey.bind({"ctrl"}, key, function()
        if dismissVisors() then
            hs.timer.doAfter(0.05, function() hs.eventtap.keyStroke(HYPER, key, 0) end)
        else
            hs.eventtap.keyStroke(HYPER, key, 0)
        end
    end)
end

-- vscode_swipe_nav: DISABLED 2026-08-31 — its gesture eventtap + 25 Hz finTimer
-- gum up input dispatch when Lua is busy (e.g. audio-guard chatter after AirPods
-- multipoint flap). Symptom: system-wide ~2 s input hitching that vanishes the
-- moment Hammerspoon quits.
-- require("vscode_swipe_nav")  -- 3-finger swipe -> back/forward in VS Code

-- Omnibox Tab remap for Chrome + Ghost Browser (Tab -> Down, Shift+Tab -> Up)
-- ONLY when the omnibox text field has focus. See omnibox_tab.lua.
require("omnibox_tab")

-- Auto-reload config on any .lua change in the Hammerspoon dir
hs.pathwatcher.new(hs.configdir, function(files)
    for _, f in ipairs(files) do
        if f:sub(-4) == ".lua" then hs.reload(); return end
    end
end):start()

hs.alert.show("Hammerspoon config loaded")
