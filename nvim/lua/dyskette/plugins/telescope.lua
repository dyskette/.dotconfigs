return {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.8",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "Telescope" },
  keys = require("dyskette.keymaps").telescope,
  opts = {
    defaults = {
      layout_strategy = "horizontal",
      sorting_strategy = "ascending",
      layout_config = {
        prompt_position = "top",
        width = 0.5,
      },
      preview = {
        filesize_limit = 0.1, -- MB
      },
    },
    pickers = {
      find_files = {
        previewer = false,
      },
      oldfiles = {
        previewer = false,
      },
      git_files = {
        previewer = false,
      },
      buffers = {
        previewer = false,
      },
    },
  },
}
