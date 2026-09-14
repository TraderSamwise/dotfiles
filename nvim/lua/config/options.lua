-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Normal-editor input layer. Normal mode stays pure vim; this only changes how
-- selection and the mouse behave, so vim habits learned here still transfer.

-- shift+<motion> starts a selection, an unshifted motion ends it
vim.opt.keymodel = { "startsel", "stopsel" }

-- ...and that selection is Select mode, not Visual, so typing replaces it the
-- way every other editor does. <C-g> toggles Select -> Visual when you want
-- vim operators on the selection instead.
vim.opt.selectmode = { "key", "mouse" }

vim.opt.mouse = "a"
vim.opt.mousemodel = "popup_setpos"

-- clipboard is deliberately NOT set here. LazyVim owns it: it blanks it at
-- startup (pbcopy is slow) and restores "unnamedplus" on VeryLazy, and blanks
-- it over SSH so OSC 52 works. The copy/cut maps use the + register directly,
-- so they work either way.
