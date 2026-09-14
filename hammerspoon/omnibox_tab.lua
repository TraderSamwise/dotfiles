-- Omnibox Tab remap for Chromium-based browsers.
--
-- Problem: in Chrome's / Ghost Browser's address bar, Tab walks focus into
-- the "switch to this tab" pill and the "remove suggestion (X)" button, so
-- Enter can silently delete a history entry. The goal is arrow-key
-- style suggestion navigation.
--
-- Fix: remap Tab -> Down and Shift+Tab -> Up, but ONLY when a Chromium
-- browser is frontmost AND its omnibox text field is the AXFocusedUIElement.
-- Page form fields, DevTools, everything else stays untouched.

local M = {}

-- Chromium apps whose omnibox we handle. Bundle-id match, not process name.
local TARGET_BUNDLES = {
    ["com.google.Chrome"]     = true,
    ["com.ghostbrowser.gb1"]  = true,
}

local TAB_KEYCODE = hs.keycodes.map.tab

local function isOmniboxFocused()
    local app = hs.application.frontmostApplication()
    if not app then return false end
    if not TARGET_BUNDLES[app:bundleID()] then return false end

    local axApp = hs.axuielement.applicationElement(app)
    if not axApp then return false end
    local focused = axApp:attributeValue("AXFocusedUIElement")
    if not focused then return false end

    if focused:attributeValue("AXRole") ~= "AXTextField" then return false end

    -- Match on the accessibility LABEL, not tree position. Chrome labels it
    -- "Address and search bar" (varies slightly by version/locale). Both
    -- AXDescription and AXTitle can carry it; check both, lowercase.
    local desc  = (focused:attributeValue("AXDescription") or ""):lower()
    local title = (focused:attributeValue("AXTitle")       or ""):lower()
    return desc:find("address", 1, true) ~= nil
        or title:find("address", 1, true) ~= nil
end

-- Assign to _G so a Hammerspoon reload doesn't GC the tap.
_G.omniboxTabTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    -- Fast bail: only Tab presses pay for the AX walk.
    if e:getKeyCode() ~= TAB_KEYCODE then return false end

    -- Any of cmd/alt/ctrl => user is asking for Chrome's own Tab-with-mod
    -- behaviour (Cmd+Tab is macOS's, Ctrl+Tab / Cmd+Alt+->/<- switch tabs);
    -- shift is the only mod we handle (Shift+Tab -> Up).
    local flags = e:getFlags()
    if flags.cmd or flags.alt or flags.ctrl then return false end

    if not isOmniboxFocused() then return false end

    local target = flags.shift and "up" or "down"
    hs.eventtap.event.newKeyEvent(target, true):post()
    hs.eventtap.event.newKeyEvent(target, false):post()
    return true  -- swallow original Tab
end)
_G.omniboxTabTap:start()

-- Debug helper. If Chrome ever changes the omnibox label and the match
-- breaks, focus the omnibox and run:  hs -c 'require("omnibox_tab").inspectFocus()'
function M.inspectFocus()
    local app = hs.application.frontmostApplication()
    if not app then print("no frontmost app") return end
    local axApp = hs.axuielement.applicationElement(app)
    if not axApp then print("no AX handle for " .. app:name()) return end
    local f = axApp:attributeValue("AXFocusedUIElement")
    if not f then print("no focused element") return end
    print(string.format(
        "app=%s bundle=%s\n  AXRole=%s\n  AXDescription=%q\n  AXTitle=%q",
        app:name(), app:bundleID() or "?",
        tostring(f:attributeValue("AXRole")),
        f:attributeValue("AXDescription") or "",
        f:attributeValue("AXTitle") or ""))
end

return M
