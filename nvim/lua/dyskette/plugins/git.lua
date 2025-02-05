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
	{ "lewis6991/gitsigns.nvim", event = "BufEnter", config = gitsigns_config },
	{ "sindrets/diffview.nvim", event = "BufEnter", config = diffview_config },
	{
		"NeogitOrg/neogit",
		event = "VeryLazy",
		dependencies = {
			"nvim-lua/plenary.nvim", -- required
			"sindrets/diffview.nvim", -- optional - Diff integration
			"ibhagwan/fzf-lua", -- optional
		},
		config = neogit_config,
	},
}
