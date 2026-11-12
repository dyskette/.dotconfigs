local yazi_diagnostics = require("config.yazi_diagnostics")
local terminals = require("config.terminals")

local oil_opts = {}

--- Lay the yazi window out like the toggleterm floats (lazygit, the shell):
--- same border, size, position, centred title, and a border drawn in Normal
--- as toggleterm draws its own.
--- Changes `win_config` in place: yazi.nvim ignores the hook's return value.
---@param win_config vim.api.keyset.win_config
local function style_yazi_window(win_config)
  for key, value in pairs(terminals.float_geometry()) do
    win_config[key] = value
  end
  win_config.border = terminals.float_border
  win_config.title = "yazi " .. vim.fs.basename(vim.fn.getcwd())
  win_config.title_pos = "center"
  -- yazi.nvim links YaziFloatBorder with default = true after this hook, so
  -- setting it here wins, and survives a :colorscheme clearing it.
  vim.api.nvim_set_hl(0, "YaziFloatBorder", { link = "Normal" })
end

--- yazi.nvim re-sizes its window on VimResized from its own scaling factor;
--- this runs after it (registered later) and puts the shared geometry back,
--- resizing the yazi process to match.
---@param bufnr integer the yazi terminal buffer
local function keep_yazi_geometry(bufnr)
  vim.api.nvim_create_autocmd("VimResized", {
    buffer = bufnr,
    desc = "Keep the yazi float in the toggleterm float geometry",
    callback = function()
      local win = vim.fn.bufwinid(bufnr)
      if win == -1 then
        return
      end
      local geometry = terminals.float_geometry()
      vim.api.nvim_win_set_config(win, vim.tbl_extend("force", geometry, { relative = "editor" }))
      local job = vim.b[bufnr].terminal_job_id
      if job then
        pcall(vim.fn.jobresize, job, geometry.width, geometry.height)
      end
    end,
  })
end

local yazi_opts = {
  -- if you want to open yazi instead of netrw, see below for more info
  open_for_directories = true,
  keymaps = {
    show_help = "<f1>",
  },
  hooks = {
    before_opening_window = style_yazi_window,
    yazi_opened = function(_, bufnr)
      keep_yazi_geometry(bufnr)
    end,
    ---@param process_api YaziProcessApi
    on_yazi_ready = function(_, _, process_api)
      yazi_diagnostics.attach(process_api.yazi_id)
    end,
    yazi_closed_successfully = function()
      yazi_diagnostics.detach()
    end,
  },
}

return {
  {
    "stevearc/oil.nvim",
    opts = oil_opts,
    keys = require("config.keymaps").oil,
  },
  ---@type LazySpec
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = require("config.keymaps").yazi,
    ---@type YaziConfig | {}
    opts = yazi_opts,
    -- 👇 if you use `open_for_directories=true`, this is recommended
    init = function()
      -- mark netrw as loaded so it's not loaded at all.
      --
      -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
      vim.g.loaded_netrwPlugin = 1
      yazi_diagnostics.setup()
    end,
  },
}
