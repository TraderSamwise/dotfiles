-- TypeScript / Web Development extras for LazyVim
return {
  -- TypeScript LSP, treesitter, formatting (LazyVim extra)
  { import = "lazyvim.plugins.extras.lang.typescript" },

  -- JSON support with SchemaStore
  { import = "lazyvim.plugins.extras.lang.json" },

  -- Tailwind CSS support (autocomplete, color hints)
  { import = "lazyvim.plugins.extras.lang.tailwind" },

  -- Additional treesitter parsers for web dev
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "tsx",
        "typescript",
        "javascript",
        "html",
        "css",
        "json",
        "json5",
        "yaml",
        "toml",
        "markdown",
        "markdown_inline",
        "graphql",
        "bash",
        "regex",
        "rust",
        "sql",
      })
    end,
  },

  -- Format on save with prettierd
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "prettierd" },
        javascriptreact = { "prettierd" },
        typescript = { "prettierd" },
        typescriptreact = { "prettierd" },
        css = { "prettierd" },
        html = { "prettierd" },
        json = { "prettierd" },
        jsonc = { "prettierd" },
        yaml = { "prettierd" },
        markdown = { "prettierd" },
        graphql = { "prettierd" },
      },
    },
  },

  -- Mason: ensure useful tools are installed
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "typescript-language-server",
        "eslint-lsp",
        "prettierd",
        "css-lsp",
        "html-lsp",
        "json-lsp",
        "lua-language-server",
        "stylua",
        "shellcheck",
        "shfmt",
      },
    },
  },
}
