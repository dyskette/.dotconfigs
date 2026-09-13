local smart_splits_opts = {
  -- Panes running these are skipped rather than resized, so a resize aimed at
  -- a split does not silently shrink a log pane instead.
  ignored_filetypes = { "nofile", "quickfix", "prompt" },
  ignored_buftypes = { "NvimTree" },
}

--- Tells WezTerm that Neovim owns this pane.
---
--- WezTerm forwards Ctrl+hjkl into a pane only when it knows Neovim is there.
--- Process-name detection cannot work on Windows, where the visible foreground
--- process of a WSL pane is wsl.exe, so the state is published explicitly over
--- OSC 1337. The same mechanism works over ssh.
local function set_is_nvim(value)
  io.stdout:write(("\027]1337;SetUserVar=IS_NVIM=%s\007"):format(vim.base64.encode(value)))
end

return {
  -- One set of keys that moves through both Neovim splits and WezTerm panes:
  -- Neovim yields at its split edges and focus leaves the editor.
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    opts = smart_splits_opts,
    config = function(_, opts)
      require("smart-splits").setup(opts)

      local augroup = vim.api.nvim_create_augroup("WeztermIsNvim", { clear = true })

      vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
        group = augroup,
        desc = "Announce Neovim to WezTerm so Ctrl+hjkl is forwarded here",
        callback = function()
          set_is_nvim("true")
        end,
      })

      vim.api.nvim_create_autocmd({ "VimLeave", "VimSuspend" }, {
        group = augroup,
        desc = "Hand Ctrl+hjkl back to WezTerm",
        callback = function()
          set_is_nvim("false")
        end,
      })
    end,
    keys = {
      { "<C-h>", function() require("smart-splits").move_cursor_left() end, desc = "Go to left split or pane" },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end, desc = "Go to below split or pane" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end, desc = "Go to above split or pane" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Go to right split or pane" },
    },
  },
}
