return {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.8",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-ui-select.nvim",
  },
  cmd = { "Telescope" },
  keys = require("config.keymaps").telescope,
  config = function(_, opts)
    require("telescope").setup(opts)
    require("telescope").load_extension("ui-select")
  end,
  opts = {
    defaults = {
      layout_strategy = "horizontal",
      sorting_strategy = "ascending",
      layout_config = {
        prompt_position = "top",
        width = 0.9,
      },
      preview = {
        filesize_limit = 0.1, -- MB
      },
      borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
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
    extensions = {
      ["ui-select"] = {
        require("telescope.themes").get_dropdown({
          layout_config = {
            width = 0.8,
            height = 0.9,
          },
        }),
      },
    },
  },
}
