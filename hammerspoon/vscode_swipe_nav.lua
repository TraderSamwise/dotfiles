-- Three-finger trackpad swipe -> Back/Forward in VS Code.
-- VS Code (Electron) doesn't handle the macOS 3-finger swipe gesture natively
-- the way JetBrains does, so we recognize it from the raw gesture touch stream
-- and post cmd+[ / cmd+] (which are bound to navigateBack/Forward).
--   swipe right -> Forward (cmd+])   swipe left -> Back (cmd+[)
-- Only fires when VS Code is frontmost, so other apps keep their native gesture.

local M = {}

local VSCODE = "com.microsoft.VSCode"
local THRESH = 0.05      -- fraction of trackpad width before it triggers
local FIN = 0.10         -- seconds without a 3-finger sample = gesture ended
local st = { active = false, x0 = 0, y0 = 0, fired = false, last = 0 }

-- The touch count flickers (2/3 fingers) mid-swipe, so we don't reset on dips;
-- instead a timer ends the gesture once 3-finger samples stop arriving.
M.finTimer = hs.timer.doEvery(0.04, function()
  if st.active and (hs.timer.secondsSinceEpoch() - st.last) > FIN then
    st.active = false
    st.fired = false
  end
end)

M.tap = hs.eventtap.new({ hs.eventtap.event.types.gesture }, function(e)
  local ok, touches = pcall(function() return e:getTouches() end)
  if not ok or not touches or #touches ~= 3 then return false end
  local sx, sy = 0, 0
  for _, t in ipairs(touches) do
    local np = t.normalizedPosition
    if np then sx = sx + np.x; sy = sy + np.y end
  end
  local ax, ay = sx / 3, sy / 3
  st.last = hs.timer.secondsSinceEpoch()
  if not st.active then
    st.active = true; st.x0 = ax; st.y0 = ay; st.fired = false
    return false
  end
  if st.fired then return false end
  local dx, dy = ax - st.x0, ay - st.y0
  if math.abs(dx) >= THRESH and math.abs(dx) > math.abs(dy) * 1.1 then
    st.fired = true
    local f = hs.application.frontmostApplication()
    if f and f:bundleID() == VSCODE then
      hs.eventtap.keyStroke({ "cmd" }, dx > 0 and "]" or "[", 1000)
    end
  end
  return false
end)
M.tap:start()

return M
