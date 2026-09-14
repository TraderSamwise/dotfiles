-- Vim skill-building plugins
return {
  -- hardtime.nvim: Blocks bad habits and suggests better motions
  -- e.g., warns you when spamming jjjj instead of using 5j or a search
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    opts = {
      -- OFF until the normal-editor baseline is comfortable. Nagging about hjkl
      -- before you have a way to move around that isn't a fight is why this
      -- didn't stick last time. Flip to true, then walk max_count 3 -> 2 -> 1.
      enabled = false,
      max_count = 3, -- allow up to 3 repeated keys before warning
      disable_mouse = false, -- keep mouse for now
      hint = true, -- show hints for better motions
      notification = true, -- show notifications
      restricted_keys = {
        ["h"] = { "n", "x" },
        ["j"] = { "n", "x" },
        ["k"] = { "n", "x" },
        ["l"] = { "n", "x" },
        ["-"] = { "n", "x" },
        ["+"] = { "n", "x" },
        ["gj"] = { "n", "x" },
        ["gk"] = { "n", "x" },
        ["<CR>"] = { "n", "x" },
        ["<C-M>"] = { "n", "x" },
        ["<C-N>"] = { "n", "x" },
        ["<C-P>"] = { "n", "x" },
      },
    },
  },

  -- precognition.nvim: Shows available motions as virtual text
  -- Displays w, b, e, ^, $, gg, G, {, } etc. so you can see efficient jumps
  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = {
      startVisible = false, -- off by default; <leader>uP when you want the hints
      showBlankVirtLine = false,
      highlightColor = { link = "Comment" },
    },
    keys = {
      {
        "<leader>uP",
        function()
          require("precognition").toggle()
        end,
        desc = "Toggle Precognition",
      },
    },
  },

  -- Tip.nvim: Shows a random Vim tip on startup
  {
    "TobinPalmer/Tip.nvim",
    event = "VimEnter",
    init = function()
      require("tip").setup({
        title = "Tip!",
        url = "https://vtip.43z.one",
      })
    end,
  },

  -- vim-be-good: ThePrimeagen's mini-games for practicing Vim motions
  -- Launch with :VimBeGood
  {
    "ThePrimeagen/vim-be-good",
    cmd = "VimBeGood",
  },
}
