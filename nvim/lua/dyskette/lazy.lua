local lazy_install = function()
	local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
	local pluginspath = "dyskette.plugins"
	local options = {
		ui = {
			border = "rounded",
			backdrop = 100,
		},
	}

	if not vim.loop.fs_stat(lazypath) then
		vim.notify("Installing lazy.nvim...")

		vim.fn.system({
			"git",
			"clone",
			"--filter=blob:none",
			"https://github.com/folke/lazy.nvim.git",
			"--branch=stable", -- latest stable release
			lazypath,
		})
	end

	vim.opt.rtp:prepend(lazypath)
	require("lazy").setup(pluginspath, options)
end

lazy_install()
