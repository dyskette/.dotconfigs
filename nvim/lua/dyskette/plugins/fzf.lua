local utils = require("dyskette.utils")

local fzf_lua_config = function()
	require("fzf-lua").setup({
		winopts = { preview = { default = "bat" } },
		oldfiles = { cwd_only = true },
	})
	require("dyskette.keymaps").fzf()
end

return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = fzf_lua_config,
	event = utils.events.VeryLazy,
}
