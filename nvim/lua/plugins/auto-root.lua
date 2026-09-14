-- Override LazyVim root detection to be git-worktree-aware
-- Uses `git rev-parse --show-toplevel` which correctly returns
-- the worktree root, not the main repo root.
-- Also auto-changes cwd to match the detected root.

return {
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.g.root_spec = {
        function(buf)
          local bufname = vim.api.nvim_buf_get_name(buf)
          if bufname == "" then return {} end
          local dir = vim.fn.fnamemodify(bufname, ":h")
          local result = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
          local root = result and result[1]
          if root and root ~= "" and not root:match("^fatal") then
            return { root }
          end
          return {}
        end,
        "lsp",
        "cwd",
      }

      -- Auto-cd to the detected root on buffer enter
      vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("auto_root_cd", { clear = true }),
        callback = function()
          local root = LazyVim.root.get()
          if root and root ~= vim.fn.getcwd() then
            vim.fn.chdir(root)
          end
        end,
      })
    end,
  },
}
