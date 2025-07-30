local utils = require("dyskette.utils")

local gitsigns_config = function()
	require("gitsigns").setup({})
end

local neogit_config = function()
	require("neogit").setup({
		integrations = {
			diffview = true,
			fzf = true,
		},
		sections = {
			recent = {
				folded = false,
				hidden = false,
			},
		},
	})
end

return {
	{
		"lewis6991/gitsigns.nvim",
		keys = require("dyskette.keymaps").gitsigns,
		config = gitsigns_config,
	},
	{
		"NeogitOrg/neogit",
		keys = require("dyskette.keymaps").neogit,
		config = neogit_config,
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"sindrets/diffview.nvim",
				keys = require("dyskette.keymaps").git_diffview,
			},
			"ibhagwan/fzf-lua",
		},
	},
}
