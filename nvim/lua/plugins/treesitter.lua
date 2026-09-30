local utils = require("config.utils")

-- Highlighting runs on core vim.treesitter: installed parsers and their queries
-- live under stdpath("data")/site, which is already on 'runtimepath'. The
-- plugin still loads at startup, because its plugin/ files map filetypes to
-- parser names (cs -> c_sharp, ps1 -> powershell, ...) and register query
-- predicates, but nothing below calls into its Lua modules unless a parser
-- has to be installed or a line indented.

local function start_treesitter(buf, lang)
  if not vim.treesitter.language.add(lang) then
    vim.notify("Cannot load treesitter parser for language " .. lang, vim.log.levels.WARN)
    return
  end
  vim.treesitter.start(buf)
  if vim.treesitter.query.get(lang, "indents") then
    -- Evaluated on first indent, which is what loads nvim-treesitter.
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

-- Parsers required for core editor features (LSP hover, help, treesitter queries)
local essential_parsers = {
  "markdown",
  "markdown_inline",
  "vim",
  "vimdoc",
  "query",
  "lua",
  "luadoc",
}

--- Install any essential parser that is missing. Checked through core, so the
--- plugin is only loaded when something actually has to be installed.
local function ensure_essential_parsers()
  local missing = vim.tbl_filter(function(lang)
    return not vim.treesitter.language.add(lang)
  end, essential_parsers)
  if #missing > 0 then
    require("nvim-treesitter").install(missing)
  end
end

local function treesitter_init()
  -- lazy.nvim runs `init` even for specs its `cond` disabled, so this has to
  -- bail out itself: inside VS Code the host does the highlighting, and turning
  -- syntax off here would only strip what the extension renders.
  if vim.g.vscode then
    return
  end

  vim.cmd.syntax("off")

  vim.api.nvim_create_autocmd("User", {
    pattern = utils.events.VeryLazy,
    once = true,
    callback = ensure_essential_parsers,
  })

  vim.api.nvim_create_autocmd(utils.events.FileType, {
    callback = function(ev)
      local lang = vim.treesitter.language.get_lang(ev.match)
      if not lang then
        return
      end
      local buf = ev.buf
      if vim.treesitter.language.add(lang) then
        start_treesitter(buf, lang)
      elseif vim.tbl_contains(require("nvim-treesitter").get_available(), lang) then
        require("nvim-treesitter").install({ lang }):await(function()
          start_treesitter(buf, lang)
        end)
      end
    end,
  })
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    cond = not vim.g.vscode,
    lazy = false,
    branch = "main",
    build = ":TSUpdate",
    init = treesitter_init,
  },
  {
    -- Sticky header with the enclosing function/class/block; replaces the
    -- LSP symbol breadcrumb that used to sit in the status line.
    "nvim-treesitter/nvim-treesitter-context",
    cond = not vim.g.vscode,
    event = utils.events.LazyFile,
    keys = require("config.keymaps").treesitter_context,
    opts = {
      -- Cap the header so deeply nested code does not eat the window.
      max_lines = 3,
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    cond = not vim.g.vscode,
    main = "ibl",
    event = utils.events.LazyFile,
    opts = {
      scope = {
        show_start = false,
      },
    },
  },
}
