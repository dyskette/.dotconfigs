local utils = require("dyskette.utils")

local hide_quickfix_and_show_trouble = function(ev)
	local trouble = require("trouble")

	-- Check whether we deal with a quickfix or location list buffer, close the window and open the
	-- corresponding Trouble window instead.
	if vim.fn.getloclist(0, { filewinid = 1 }).filewinid ~= 0 then
		vim.defer_fn(function()
			vim.cmd.lclose()
			trouble.open("loclist")
		end, 0)
	elseif vim.bo[ev.buf].buftype == "quickfix" then
		vim.defer_fn(function()
			vim.cmd.cclose()
			trouble.open("quickfix")
		end, 0)
	end
end

local trouble_config = function()
	require("trouble").setup({})

	local group = vim.api.nvim_create_augroup("dyskette_replace_quickfix_with_trouble", { clear = true })
	vim.api.nvim_create_autocmd("BufRead", {
		desc = "Replace quickfix with Trouble",
		pattern = "quickfix",
		group = group,
		callback = hide_quickfix_and_show_trouble,
	})

	require("dyskette.keymaps").trouble()
end

return {
	"folke/trouble.nvim",
	event = utils.events.VeryLazy,
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = trouble_config,
}
