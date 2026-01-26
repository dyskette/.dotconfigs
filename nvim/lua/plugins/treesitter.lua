local utils = require("config.utils")

-- Install parsers on plugin build/update
local treesitter_build = ":TSUpdate"

-- Setup function for nvim-treesitter (main branch)
local treesitter_setup = function()
  -- Map of languages with their related variants
  -- Each key is a base language, and the value is a list of related treesitter parsers
  local language_families = {
    -- Scripting languages
    lua = { "lua", "luadoc", "luap" },
    bash = { "bash" },
    sh = { "bash" }, -- alias for bash
    powershell = { "powershell" },
    python = { "python" },

    -- JavaScript/TypeScript family
    javascript = { "javascript", "jsdoc" },
    typescript = { "typescript", "tsx" },
    javascriptreact = { "javascript", "tsx", "jsdoc" },
    typescriptreact = { "typescript", "tsx", "jsdoc" },
    vue = { "vue", "javascript", "typescript" },

    -- Web technologies
    html = { "html" },
    css = { "css", "scss" },

    -- Data formats
    json = { "json", "json5" },
    yaml = { "yaml" },
    xml = { "xml" },
    toml = { "toml" },
    http = { "http" },

    -- Compiled languages
    cs = { "c_sharp" },
    razor = { "razor", "c_sharp", "html" },
    dart = { "dart" },
    rust = { "rust" },

    -- Editor/Neovim specific
    vim = { "vim", "vimdoc" },
    markdown = { "markdown", "markdown_inline" },
    query = { "query" },
    gitcommit = { "gitcommit", "git_rebase", "gitignore", "gitattributes" },

    -- System
    c = { "c" },
    sql = { "sql" },
  }

  -- Collect all unique parsers from language families
  local parser_set = {}
  for _, parsers in pairs(language_families) do
    for _, parser in ipairs(parsers) do
      parser_set[parser] = true
    end
  end

  -- Convert set to list
  local parsers = {}
  for parser, _ in pairs(parser_set) do
    table.insert(parsers, parser)
  end

  -- Schedule parser installation to run after startup
  vim.schedule(function()
    local ok, ts = pcall(require, "nvim-treesitter")
    if ok and ts.install then
      ts.install(parsers)
    end
  end)
end

-- Enable treesitter highlighting for supported languages
local treesitter_init = function()
  -- Disable default vim syntax highlighting
  vim.cmd.syntax("off")

  -- Define all filetypes that have treesitter support
  -- This matches the languages configured in LSP plus their variants
  local supported_filetypes = {
    -- Scripting
    "lua",
    "sh",
    "bash",
    "ps1",
    "psm1",
    "psd1",
    "python",
    "http",

    -- JavaScript/TypeScript ecosystem
    "javascript",
    "typescript",
    "javascriptreact",
    "typescriptreact",
    "vue",

    -- Web technologies
    "html",
    "css",
    "scss",
    "sass",
    "less",

    -- Data formats
    "json",
    "jsonc",
    "yaml",
    "yml",
    "xml",
    "toml",

    -- Compiled languages
    "cs",
    "dart",
    "rust",

    -- Editor/Git
    "vim",
    "vimdoc",
    "query",
    "markdown",
    "gitcommit",
    "gitrebase",
    "gitignore",
    "gitattributes",

    -- System
    "c",
    "sql",
  }

  -- Enable treesitter highlighting for supported filetypes
  vim.api.nvim_create_autocmd("FileType", {
    pattern = supported_filetypes,
    callback = function()
      vim.treesitter.start()
    end,
  })

  -- Razor highlighting is handled by rzls.nvim plugin
  -- Don't auto-start treesitter for razor files to avoid conflicts
end

local indent_blankline_opts = {
  scope = {
    show_start = false,
  },
}

return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  branch = "main",
  build = treesitter_build,
  init = treesitter_init,
  config = treesitter_setup,
  dependencies = {
    { "windwp/nvim-ts-autotag" },
    {
      "lukas-reineke/indent-blankline.nvim",
      main = "ibl",
      opts = indent_blankline_opts,
    },
  },
}
