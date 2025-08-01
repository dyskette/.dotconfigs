local utils = require("config.utils")

return {
  {
    "christoomey/vim-tmux-navigator",
    event = utils.events.VeryLazy,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<C-w>h", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux/vim)" },
      { "<C-w>j", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (tmux/vim)" },
      { "<C-w>k", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (tmux/vim)" },
      { "<C-w>l", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (tmux/vim)" },
      { "<C-w>\\", "<cmd>TmuxNavigatePrevious<cr>", desc = "Navigate to previous (tmux/vim)" },
    },
  },
}