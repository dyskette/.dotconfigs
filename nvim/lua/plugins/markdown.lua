return {
  -- Markdown preview
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  },
  -- Paste image as a file in cwd/assets/ and get the path
  {
    "HakonHarnes/img-clip.nvim",
    keys = require("config.keymaps").imgclip,
    ft = { "markdown" },
  },
}
