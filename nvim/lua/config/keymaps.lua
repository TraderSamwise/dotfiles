-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Normal-editor keys, bound ONLY in insert/select mode. Normal mode is left
-- alone on purpose: <C-a> stays increment, <C-v> stays blockwise-visual,
-- <C-c> stays interrupt, so nothing here has to be unlearned later.

local map = vim.keymap.set

-- Save. nvim doesn't use <C-s> in any mode, so it's safe everywhere.
map({ "n", "i", "v" }, "<C-s>", "<Cmd>silent! update<CR>", { desc = "Save file" })

-- Undo / select-all from insert mode
map("i", "<C-z>", "<C-o>u", { desc = "Undo" })
map("i", "<C-a>", "<Esc>ggVG", { desc = "Select all" })

-- Copy / cut a selection (works in both Visual and Select)
map("v", "<C-c>", '"+y', { desc = "Copy" })
map("v", "<C-x>", '"+d', { desc = "Cut" })

-- Option+arrows. ghostty ships `alt+arrow_left=esc:b` / `alt+arrow_right=esc:f`,
-- so opt+left/right arrive as <M-b>/<M-f> -- NOT <M-Left>. Map what's actually
-- sent; the <M-Left> pair is kept in case that binding is ever removed.
map("i", "<M-b>", "<C-Left>", { desc = "Word left" })
map("i", "<M-f>", "<C-Right>", { desc = "Word right" })
map("i", "<M-Left>", "<C-Left>", { desc = "Word left" })
map("i", "<M-Right>", "<C-Right>", { desc = "Word right" })
map("i", "<M-BS>", "<C-w>", { desc = "Delete word left" })

-- Option+shift+arrows are unbound in ghostty, so they pass through as
-- <M-S-...>. Route them to the built-in shifted motions, which keymodel turns
-- into a Select-mode selection (verified to work from insert mode).
map({ "i", "n", "v", "s" }, "<M-S-Left>", "<C-S-Left>", { desc = "Select word left" })
map({ "i", "n", "v", "s" }, "<M-S-Right>", "<C-S-Right>", { desc = "Select word right" })

-- Move the cursor's line, or every line the selection touches (even partially),
-- as one group. A function rather than a key sequence so it works identically
-- from normal, insert, visual and select mode without dropping out of any.
local function move_lines(dir)
  local mode = vim.fn.mode()
  local visual = mode:find("[vV\22sS\19]") ~= nil
  local was_select = mode:find("[sS\19]") ~= nil
  if visual then
    vim.cmd("normal! \27") -- close the selection so '< and '> are set
    local first, last = vim.fn.line("'<"), vim.fn.line("'>")
    local target = dir < 0 and first - 2 or last + 1
    if target < 0 or target > vim.fn.line("$") then
      vim.cmd("normal! gv")
      if was_select then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-g>", true, false, true), "n", false)
      end
      return
    end
    vim.cmd(("silent %d,%dmove %d"):format(first, last, target))
    vim.cmd("normal! gv=gv")
    if was_select then -- came from Select mode, so go back to it, not Visual
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-g>", true, false, true), "n", false)
    end
  else
    local line = vim.fn.line(".")
    local target = dir < 0 and line - 2 or line + 1
    if target < 0 or target > vim.fn.line("$") then
      return
    end
    vim.cmd(("silent move %d"):format(target))
    vim.cmd("normal! ==")
  end
end

local move_modes = { "n", "i", "v", "s" }
map(move_modes, "<M-S-Up>", function() move_lines(-1) end, { desc = "Move line(s) up" })
map(move_modes, "<M-S-Down>", function() move_lines(1) end, { desc = "Move line(s) down" })
map(move_modes, "<M-Up>", function() move_lines(-1) end, { desc = "Move line(s) up" })
map(move_modes, "<M-Down>", function() move_lines(1) end, { desc = "Move line(s) down" })
