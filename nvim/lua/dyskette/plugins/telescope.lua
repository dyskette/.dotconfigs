local ts_select_dir_for_grep = function(prompt_bufnr)
	local action_state = require("telescope.actions.state")
	local file_browser = require("telescope").extensions.file_browser.file_browser
	local live_grep = require("telescope").extensions.live_grep_args.live_grep_args
	local current_line = action_state.get_current_line()

	file_browser({
		files = false,
		depth = false,
		attach_mappings = function(prompt_bufnr)
			require("telescope.actions").select_default:replace(function()
				local entry_path = action_state.get_selected_entry().Path
				local dir = entry_path:is_dir() and entry_path or entry_path:parent()
				local relative = dir:make_relative(vim.fn.getcwd())
				local absolute = dir:absolute()

				live_grep({
					results_title = relative .. "/",
					cwd = absolute,
					default_text = current_line,
				})
			end)

			return true
		end,
	})
end

local telescope_config = function()
	local telescope = require("telescope")
	local actions = require("telescope.actions")

	telescope.setup({
		defaults = {
			file_previewer = require("telescope.previewers").cat.new,
			grep_previewer = require("telescope.previewers").vimgrep.new,
			path_display = { "truncate" },
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
		extensions = {
			live_grep_args = {
				mappings = {
					i = {
						["<C-f>"] = ts_select_dir_for_grep,
					},
					n = {
						["<C-f>"] = ts_select_dir_for_grep,
					},
				},
			},
		},
	})
	telescope.load_extension("live_grep_args")
	telescope.load_extension("file_browser")

	require("dyskette.keymaps").telescope()
end

return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "nvim-telescope/telescope-live-grep-args.nvim", version = "^1.0.0" },
		"nvim-telescope/telescope-file-browser.nvim",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
	},
	config = telescope_config,
	enabled = false
}
