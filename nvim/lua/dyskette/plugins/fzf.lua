local utils = require("dyskette.utils")

local fzf_lua_config = function()
	local fzf = require("fzf-lua")

	fzf.setup({
		winopts = { preview = { default = "bat" } },
		oldfiles = { cwd_only = true, include_current_session = true },
		files = {
			actions = { ["ctrl-q"] = { fn = fzf.actions.file_sel_to_qf, prefix = "select-all" } },
		},
		grep = {
			actions = { ["ctrl-q"] = { fn = fzf.actions.file_sel_to_qf, prefix = "select-all" } },
		},
	})

	fzf.register_ui_select()

	require("dyskette.keymaps").fzf()
end

return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = fzf_lua_config,
	event = utils.events.VeryLazy,
}
