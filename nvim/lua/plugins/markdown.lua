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
      local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
      local is_wsl = vim.fn.filereadable("/proc/version") == 1
        and vim.fn.readfile("/proc/version")[1]:find("microsoft") ~= nil

      if is_windows then
        -- Windows: try common browser executables
        if vim.fn.executable("firefox.exe") == 1 then
          cmd = "start firefox.exe"
        elseif vim.fn.executable("chrome.exe") == 1 then
          cmd = "start chrome.exe"
        elseif vim.fn.executable("msedge.exe") == 1 then
          cmd = "start msedge.exe"
        else
          cmd = "cmd.exe /c start"
        end
      elseif is_wsl then
        -- WSL: use wslview or Windows browsers via PowerShell
        if vim.fn.executable("wslview") == 1 then
          cmd = "wslview"
        elseif vim.fn.executable("pwsh.exe") == 1 then
          -- Prefer PowerShell Core (works better than cmd.exe from UNC paths)
          cmd = "pwsh.exe -Command Start-Process"
        else
          -- Fallback to PowerShell (works better than cmd.exe from UNC paths)
          cmd = "powershell.exe -Command Start-Process"
        end
      else
        -- Linux: check if flatpak command is available
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
              return
            end
          end
        end
      end

      vim.api.nvim_exec2(
        string.gsub(
          [[
        function! MkdpBrowserFn(url)
          execute '!# ' . shellescape(a:url)
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
