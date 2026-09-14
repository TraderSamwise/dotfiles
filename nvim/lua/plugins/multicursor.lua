-- Multiple cursors, driven by option+click.
return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      local set = vim.keymap.set

      -- Option+click adds a cursor; clicking an existing one removes it.
      -- Upstream documents ctrl+click; option is the macOS habit.
      set({ "n", "x" }, "<M-LeftMouse>", mc.handleMouse)
      set({ "n", "x" }, "<M-LeftDrag>", mc.handleMouseDrag)
      set({ "n", "x" }, "<M-LeftRelease>", mc.handleMouseRelease)

      -- A keymap layer only binds while multiple cursors exist, so <Esc> keeps
      -- its normal meaning the rest of the time.
      mc.addKeymapLayer(function(layerSet)
        layerSet({ "n", "x" }, "<Esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)

      local hl = vim.api.nvim_set_hl
      hl(0, "MultiCursorCursor", { reverse = true })
      hl(0, "MultiCursorVisual", { link = "Visual" })
      hl(0, "MultiCursorSign", { link = "SignColumn" })
      hl(0, "MultiCursorMatchPreview", { link = "Search" })
      hl(0, "MultiCursorDisabledCursor", { reverse = true })
      hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
      hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
    end,
  },
}
