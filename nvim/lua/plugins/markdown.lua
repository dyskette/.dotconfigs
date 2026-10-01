-- Markdown rendered in the buffer: headings, tables, code blocks, checkboxes,
-- callouts and links, drawn with text and highlights, so it works in any
-- terminal and through tmux/psmux. Raw text while inserting, rendered
-- otherwise. Images and mermaid are left to the on-demand browser preview
-- (<leader>mp, mpls in lspconfig.lua): inline images need the Kitty graphics
-- protocol, which Windows Terminal does not implement.
return {
  "MeanderingProgrammer/render-markdown.nvim",
  cond = not vim.g.vscode,
  ft = { "markdown" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", ft = "markdown", desc = "Toggle rendered markdown" },
  },
  opts = {},
}
