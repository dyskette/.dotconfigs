local telescope_config = function()
	local telescope = require("telescope")
	local actions = require("telescope.actions")

	telescope.setup({
		defaults = {
			file_previewer = require("telescope.previewers").cat.new,
			grep_previewer = require("telescope.previewers").vimgrep.new,
		},
		mappings = {
			i = {
				["<C-q>"] = function(prompt_bufnr)
					actions.smart_send_to_qflist(prompt_bufnr)
					actions.open_qflist(prompt_bufnr)
				end,
			},
			n = {
				["<C-q>"] = function(prompt_bufnr)
					actions.smart_send_to_qflist(prompt_bufnr)
					actions.open_qflist(prompt_bufnr)
				end,
			},
		},
	})
	telescope.load_extension("live_grep_args")

	require("dyskette.keymaps").telescope()
end
return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "nvim-telescope/telescope-live-grep-args.nvim", version = "^1.0.0" },
	},
	config = telescope_config,
}
