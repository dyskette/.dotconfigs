local utils = require("config.utils")

local blink_opts = {
  completion = {
    keyword = { range = "full" },
    ghost_text = {
      enabled = true,
    },
    list = { selection = { preselect = true, auto_insert = false } },
    documentation = {
      auto_show = true,
      auto_show_delay_ms = 500,
    },
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
    per_filetype = {
      sql = { "dadbod", "buffer" },
      mysql = { "dadbod", "buffer" },
      plsql = { "dadbod", "buffer" },
    },
    providers = {
      dadbod = {
        name = "Dadbod",
        module = "vim_dadbod_completion.blink",
      },
    },
  },
  cmdline = {
    enabled = true,
    completion = {
      menu = {
        auto_show = true,
      },
    },
  },
  snippets = {
    preset = "default",
  },
  -- The Lua matcher rather than the Rust one: on every start the Rust one
  -- checks its prebuilt binary against the plugin version, which is two git
  -- processes and a certutil hash (~125 ms of process starts on Windows),
  -- download or not. The Lua one has no typo tolerance or frecency, which
  -- matters little at completion-list sizes.
  fuzzy = {
    implementation = "lua",
  },
}

return {
  "saghen/blink.cmp",
  event = { utils.events.CmdlineEnter, utils.events.InsertEnter },
  dependencies = "rafamadriz/friendly-snippets",
  version = "*",
  opts = blink_opts,
}
