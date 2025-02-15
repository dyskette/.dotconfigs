local utils = require("dyskette.utils")

local fzf_config = function()
	local fzf_lua = require("fzf-lua")

	fzf_lua.setup({
		"fzf-native",
		oldfiles = {
			cwd_only = true,
			include_current_session = true,
		},
		grep = {
			-- filter results in grep by adding " --<path-filter>"
			-- e.g. > catch --*/utils/*
			rg_glob = true, -- enable glob parsing
			glob_flag = "--iglob", -- case insensitive globs
			glob_separator = "%s%-%-", -- query separator pattern (lua): ' --'
		},
	})

	fzf_lua.register_ui_select()

	local config = require("fzf-lua.config")
	local actions = require("trouble.sources.fzf").actions
	config.defaults.actions.files["ctrl-t"] = actions.open

	require("dyskette.keymaps").fzf()
end

return {
	{
		"ibhagwan/fzf-lua",
		event = { utils.events.VeryLazy },
		dependencies = { "nvim-tree/nvim-web-devicons", "folke/trouble.nvim" },
		config = fzf_config,
	},
}
