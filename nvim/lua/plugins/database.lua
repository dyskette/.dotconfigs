local utils = require("config.utils")

local dadbod_ui_init = function()
  -- Map plsql filetype to use SQL treesitter parser for syntax highlighting
  vim.treesitter.language.register('sql', 'plsql')

  -- Database UI settings
  vim.g.db_ui_use_nerd_fonts = 1
  vim.g.db_ui_show_database_icon = 1
  vim.g.db_ui_win_position = "left"
  vim.g.db_ui_winwidth = 40

  -- Use notification popup instead of echo
  vim.g.db_ui_use_nvim_notify = 1

  -- Save location for queries
  vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui_queries"
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
