local utils = require("dyskette.utils")

local gitsigns_config = function()
	require("gitsigns").setup({})
	require("dyskette.keymaps").gitsigns()
end

local diffview_config = function()
	require("dyskette.keymaps").git_diffview()
end

local neogit_setup = function()
	require("neogit").setup({
		integrations = {
			diffview = true,
			telescope = true,
		},
		sections = {
			recent = {
				folded = false,
				hidden = false,
			},
		},
	})
end

local neogit_config = function()
	require("dyskette.keymaps").neogit(neogit_setup)
end

return {
	{
		"lewis6991/gitsigns.nvim",
		event = utils.events.VeryLazy,
		config = gitsigns_config,
	},
	{
		"NeogitOrg/neogit",
		event = utils.events.VeryLazy,
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"sindrets/diffview.nvim",
				config = diffview_config,
			},
			"ibhagwan/fzf-lua",
		},
		config = neogit_config,
	},
}
