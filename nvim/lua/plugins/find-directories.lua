-- Find directories picker via Telescope
-- Usage: <leader>fd — fuzzy search folder names, scopes explorer to selection
-- Fuzzy matches against the directory name only (not full path)

return {
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>fd",
        function()
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          local finders = require("telescope.finders")
          local pickers = require("telescope.pickers")
          local conf = require("telescope.config").values

          -- Always search from git root
          local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1] or vim.fn.getcwd()
          local cmd = "fd --type d --max-depth 3 --no-ignore --exclude node_modules . " .. vim.fn.shellescape(git_root)
          local dirs = vim.fn.systemlist(cmd)

          pickers.new({ layout_config = { prompt_position = "top" }, sorting_strategy = "ascending" }, {
            prompt_title = "Find Directories",
            previewer = false,
            finder = finders.new_table({
              results = dirs,
              entry_maker = function(path)
                -- Strip trailing slash, then match against last component only
                path = path:gsub("/$", "")
                local name = vim.fn.fnamemodify(path, ":t")
                local rel = path
                if path:sub(1, #git_root) == git_root then
                  rel = path:sub(#git_root + 2)
                end
                return {
                  value = path,
                  display = rel,
                  ordinal = name,
                }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
              actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                  local dir = entry.value
                  local explorer = Snacks.picker.get({ source = "explorer" })[1]
                  if explorer then
                    explorer:close()
                  end
                  vim.schedule(function()
                    Snacks.explorer.open({ cwd = dir })
                  end)
                end
              end)
              return true
            end,
          }):find()
        end,
        desc = "Find directories",
      },
    },
  },
}
