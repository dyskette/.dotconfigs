return {
  -- Markdown preview
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    config = function()
      local cmd
      -- check if flatpak command is available
      if vim.fn.executable("flatpak") == 1 then
        cmd = "flatpak firefox --new-tab"
      else
        -- check for running from container
        if vim.fn.executable("flatpak-spawn") == 1 then
          cmd = "flatpak-spawn --host flatpak run org.mozilla.firefox --new-tab"
        else
          -- native
          if vim.fn.executable("firefox") == 1 then
            cmd = "firefox --new-tab"
          else
            vim.notify("firefox not found", vim.log.levels.WARN)
          end
        end
      end
      vim.api.nvim_exec2(
        string.gsub(
          [[
        function MkdpBrowserFn(url)
          execute '!#' a:url
        endfunction
        ]],
          "#",
          cmd
        ),
        {}
      )
      vim.g.mkdp_browserfunc = "MkdpBrowserFn"
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
