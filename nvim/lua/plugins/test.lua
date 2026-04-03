return {
  "mr-u0b0dy/crazy-coverage.nvim",
  config = function()
    require("crazy-coverage").setup({
      summary = {
        max_files = 700, -- Limit file list length
        max_height = 700,
      },
    })
  end,
}
