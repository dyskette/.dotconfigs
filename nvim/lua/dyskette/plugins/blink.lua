local utils = require("dyskette.utils")

return {
  "saghen/blink.cmp",
  event = { utils.events.InsertEnter, utils.events.CmdlineEnter },
  dependencies = {
    { "rafamadriz/friendly-snippets" },
  },
  version = "*",
  opts = {
    completion = {
      ghost_text = {
        enabled = true,
      },
      list = { selection = { preselect = true, auto_insert = false } },
    },
    keymap = {
      preset = "default",

      ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-|"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-e>"] = { "hide" },
      ["<C-y>"] = { "select_and_accept" },

      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-p>"] = { "select_prev", "fallback_to_mappings" },
      ["<C-n>"] = { "select_next", "fallback_to_mappings" },

      ["<C-b>"] = { "scroll_documentation_up", "fallback" },
      ["<C-f>"] = { "scroll_documentation_down", "fallback" },

      ["<Tab>"] = { "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },

      ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
    },
    appearance = {
      use_nvim_cmp_as_default = true,
      nerd_font_variant = "mono",
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
    },
    cmdline = {
      enabled = true,
      completion = {
        menu = {
          auto_show = true,
        },
      },
    },
  },
}
