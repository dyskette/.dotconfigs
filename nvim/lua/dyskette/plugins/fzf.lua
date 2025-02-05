local fzf_config = function()
	local fzf_lua = require("fzf-lua")

	fzf_lua.setup({
		winopts = {
			split = "belowright new",
			preview = {
				default = "bat",
			},
		},
		oldfiles = {
			cwd_only = true,
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
		enabled = false,
	},
}
