return {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.8",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "Telescope" },
  keys = {
    { "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "Search files" },
    {
      "<leader>sr",
      "<cmd>lua require('telescope.builtin').oldfiles({ only_cwd = true })<cr>",
      desc = "Search recent files",
    },
    { "<leader>si", "<cmd>Telescope git_files<cr>", desc = "Search git files" },
    { "<leader>sg", "<cmd>Telescope live_grep<cr>", desc = "Search by grep" },
    { "<leader>sw", "<cmd>Telescope grep_string<cr>", desc = "Search help", mode = { "n", "x" } },
    { "<leader>sb", "<cmd>Telescope buffers<cr>", desc = "Search buffers" },
    { "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
    { "<leader>so", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Search help" },

    { "gd", "<cmd>Telescope lsp_definitions<cr>", desc = "Search definitions" },
    { "gi", "<cmd>Telescope lsp_implementations<cr>", desc = "Search implementations" },
    { "go", "<cmd>Telescope lsp_type_definitions<cr>", desc = "Search type definitions" },
    { "gr", "<cmd>Telescope lsp_references<cr>", desc = "Search references" },
  },
  opts = {
    defaults = {
      layout_strategy = "horizontal",
      sorting_strategy = "ascending",
      layout_config = {
        prompt_position = "top",
        width = 0.5
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
