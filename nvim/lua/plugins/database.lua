local utils = require("config.utils")

local dadbod_ui_init = function()
  -- Database UI settings
  vim.g.db_ui_use_nerd_fonts = 1
  vim.g.db_ui_show_database_icon = 1
  vim.g.db_ui_force_echo_notifications = 0
  vim.g.db_ui_win_position = "left"
  vim.g.db_ui_winwidth = 40

  -- Use notification popup instead of echo
  vim.g.db_ui_use_nvim_notify = 1

  -- Auto-execute query on save
  vim.g.db_ui_auto_execute_table_helpers = 1

  -- Save location for queries
  vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui_queries"

  -- Icons
  vim.g.db_ui_icons = {
    expanded = {
      db = "▾ ",
      buffers = "▾ ",
      saved_queries = "▾ ",
      schemas = "▾ ",
      schema = "▾ 󰙅",
      tables = "▾ 󰓫",
      table = "▾ ",
    },
    collapsed = {
      db = "▸ ",
      buffers = "▸ ",
      saved_queries = "▸ ",
      schemas = "▸ ",
      schema = "▸ 󰙅",
      tables = "▸ 󰓫",
      table = "▸ ",
    },
    saved_query = "",
    new_query = "󰓰",
    tables = "󰓫",
    buffers = "󰈙",
    add_connection = "",
    connection_ok = "✓",
    connection_error = "✕",
  }
end

return {
  {
    "kristijanhusak/vim-dadbod-ui",
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    keys = require("config.keymaps").dadbod_ui,
    init = dadbod_ui_init,
    dependencies = {
      {
        "tpope/vim-dadbod",
        lazy = true,
      },
      {
        "kristijanhusak/vim-dadbod-completion",
        ft = { "sql", "mysql", "plsql" },
      },
    },
  },
}
