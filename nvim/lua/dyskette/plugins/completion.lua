local utils = require("dyskette.utils")

local blink_config = function()
	require("blink.cmp").setup({
		keymap = { preset = "default" },
		appearance = {
			use_nvim_cmp_as_default = true,
			nerd_font_variant = "mono",
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	})
end

return {
	"saghen/blink.cmp",
	event = { utils.events.VeryLazy },
	dependencies = "rafamadriz/friendly-snippets",
	version = "*",
	config = blink_config,
}
