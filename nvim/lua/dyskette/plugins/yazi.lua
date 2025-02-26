local utils = require("dyskette.utils")

local yazi_config = function()
	require("yazi").setup({
		open_for_directories = true,
		keymaps = {
			show_help = "<f1>",
		},
	})

	require("dyskette.keymaps").yazi()
end

return {
	"mikavilpas/yazi.nvim",
	event = utils.events.VeryLazy,
	keys = {
		{ "<leader>e", mode = { "n", "v" } },
	},
	config = yazi_config,
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
		{ "folke/snacks.nvim", lazy = true },
	},
}
