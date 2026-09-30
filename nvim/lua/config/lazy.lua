--- Define `User LazyFile`, the event file-related plugins load on.
---
--- It fires with the first BufReadPost/BufNewFile/BufWritePre, except that a
--- file opened from the command line fires it after the first screen
--- (VeryLazy) rather than while nvim is still starting. So `nvim` alone never
--- loads those plugins, and `nvim file` draws the file before loading them;
--- each plugin catches up on the buffers that are already open.
local define_lazy_file_event = function()
  local group = vim.api.nvim_create_augroup("dyskette_lazy_file", { clear = true })
  local pending = false

  local fire = function()
    vim.api.nvim_del_augroup_by_id(group)
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyFile", modeline = false })
  end

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePre" }, {
    group = group,
    callback = function()
      if vim.v.vim_did_enter == 0 then
        pending = true
      else
        fire()
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VeryLazy",
    once = true,
    callback = function()
      if pending then
        fire()
      end
    end,
  })
end

local lazy_install = function()
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.notify("Installing lazy.nvim...")

    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })

    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
        { out, "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end

  vim.opt.rtp:prepend(lazypath)

  require("lazy").setup({
    spec = {
      { import = "plugins" },
    },
    ui = {
      border = "single",
      backdrop = 100,
    },
    performance = {
      rtp = {
        -- Built-in runtime plugins nothing here uses: archives are not browsed
        -- in nvim, yazi.nvim replaces netrw, and :TOhtml and :Tutor go unused.
        disabled_plugins = {
          "gzip",
          "tarPlugin",
          "zipPlugin",
          "netrwPlugin",
          "tohtml",
          "tutor",
        },
      },
    },
  })
end

define_lazy_file_event()
lazy_install()
