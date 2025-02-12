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

	require("dyskette.keymaps").fzf()
end

return {
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = fzf_config,
	},
}
