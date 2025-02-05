local telescope_config = function()
	local telescope = require("telescope")
	local open_with_trouble = require("trouble.sources.telescope").open

	telescope.setup({
		defaults = {
			file_previewer = require("telescope.previewers").cat.new,
			grep_previewer = require("telescope.previewers").vimgrep.new,
			layout_strategy = "bottom_pane",
			path_display = { "truncate" },
			sorting_strategy = "ascending",
			mappings = {
				i = { ["<c-t>"] = open_with_trouble },
				n = { ["<c-t>"] = open_with_trouble },
			},
		},
	})
	telescope.load_extension("fzf")
	telescope.load_extension("live_grep_args")
	require("dyskette.keymaps").telescope()
end

return {
	"nvim-telescope/telescope.nvim",
	config = telescope_config,
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
		{ "MunifTanjim/nui.nvim" },
		{
			"nvim-telescope/telescope-fzf-native.nvim",
			build = {
				"mkdir build",
				"zig cc -O3 -Wall -Werror -fpic -std=gnu99 -shared src/fzf.c -o build/libfzf.dll",
			},
			-- "zig cc -O3 -Wall -Werror -fpic -std=gnu99 -shared src/fzf.c -o build/libfzf.dll",
		},
		{ "nvim-telescope/telescope-live-grep-args.nvim", version = "^1.0.0" },
		{ "folke/trouble.nvim" },
	},
}
