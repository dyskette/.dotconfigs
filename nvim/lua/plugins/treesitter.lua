local function is_parser_installed(lang)
  local installed = require("nvim-treesitter").get_installed()
  return vim.tbl_contains(installed, lang)
end

local function is_parser_available(lang)
  local available = require("nvim-treesitter").get_available()
  return vim.tbl_contains(available, lang)
end

local function start_treesitter(buf, lang)
  if not vim.treesitter.language.add(lang) then
    vim.notify("Cannot load treesitter parser for language " .. lang, vim.log.levels.WARN)
    return
  end
  vim.treesitter.start(buf)
  vim.bo[buf].syntax = "ON"
  if vim.treesitter.query.get(lang, "indents") then
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

local function ensure_essential_parsers()
  local ts = require("nvim-treesitter")
  local installed = ts.get_installed()
  local missing = vim.tbl_filter(function(lang)
    return not vim.tbl_contains(installed, lang)
  end, essential_parsers)
  if #missing > 0 then
    ts.install(missing)
  end
end

local function treesitter_init()
  vim.cmd.syntax("off")

  vim.schedule(ensure_essential_parsers)

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(ev)
      local lang = vim.treesitter.language.get_lang(ev.match)
      if not lang then
        return
      end
      local buf = ev.buf
      if is_parser_installed(lang) then
        start_treesitter(buf, lang)
      elseif is_parser_available(lang) then
        require("nvim-treesitter").install({ lang }):await(function()
          start_treesitter(buf, lang)
        end)
      end
    end,
  })
end

return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  branch = "main",
  build = ":TSUpdate",
  init = treesitter_init,
  dependencies = {
    { "windwp/nvim-ts-autotag" },
    {
      "lukas-reineke/indent-blankline.nvim",
      main = "ibl",
      opts = {
        scope = {
          show_start = false,
        },
      },
    },
  },
}
