local utils = require("dyskette.utils")

local oil_config = function()
	require("oil").setup({
		default_file_explorer = true,
	})
	require("dyskette.keymaps").oil()
end

return {
	"stevearc/oil.nvim",
	event = utils.events.VeryLazy,
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = oil_config,
}
