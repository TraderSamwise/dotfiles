-- Extra snacks explorer keybindings
-- zC: recursively close folder under cursor (like vim fold zC)

return {
  {
    "snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            actions = {
              explorer_close_recursive = function(picker, item)
                if not item or not item.dir then return end
                local Tree = require("snacks.explorer.tree")
                Tree:close_all(item.file)
                local Actions = require("snacks.explorer.actions")
                Actions.update(picker, { target = item.file, refresh = true })
              end,
            },
            win = {
              list = {
                keys = {
                  ["zC"] = "explorer_close_recursive",
                },
              },
            },
          },
        },
      },
    },
  },
}
