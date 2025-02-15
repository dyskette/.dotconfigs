local utils = require("dyskette.utils")

local treesitter_build = function()
	require("nvim-treesitter.install").update({ with_sync = true })()
end

---@param lang string
---@param buffer_number number
local treesitter_disable = function(lang, buffer_number)
	return vim.api.nvim_buf_line_count(buffer_number) > 8000
end

local treesitterconfig_config = function()
	-- Disable default vim syntax highlighting
	vim.cmd.syntax("off")

	require("nvim-treesitter.configs").setup({
		highlight = {
			enable = true,
			disable = treesitter_disable,
			additional_vim_regex_highlighting = false,
		},
		indent = {
			enable = true,
		},
		auto_install = true,
		sync_install = true,
		modules = {},
		ignore_install = {},
		ensure_installed = {
			-- The following parsers should always be installed
			"c",
			"lua",
			"markdown",
			"markdown_inline",
			"vim",
			"vimdoc",
			"query",
			-- Other parsers
			"javascript",
			"typescript",
			"c_sharp",
			"python",
			"gitcommit",
			"sql",
			"css",
			"vue",
		},
	})

	local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
	parser_config.fsharp = {
		install_info = {
			url = "https://github.com/ionide/tree-sitter-fsharp",
			branch = "main",
			files = { "src/scanner.c", "src/parser.c" },
		},
		filetype = "fsharp",
	}

	--- HACK: Override `vim.lsp.util.stylize_markdown` to use Treesitter.
	-- <https://github.com/hrsh7th/nvim-cmp/issues/1699#issuecomment-1738132283>
	---@param bufnr integer
	---@param contents string[]
	---@param opts table
	---@return string[]
	---@diagnostic disable-next-line: duplicate-set-field
	vim.lsp.util.stylize_markdown = function(bufnr, contents, opts)
		contents = vim.lsp.util._normalize_markdown(contents, {
			width = vim.lsp.util._make_floating_popup_size(contents, opts),
		})
		vim.bo[bufnr].filetype = "markdown"
		vim.treesitter.start(bufnr)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)

		return contents
	end
end

local indent_blankline_config = function()
	require("ibl").setup({
		scope = {
			show_start = false,
		},
	})
end

return {
	{
		"nvim-treesitter/nvim-treesitter",
		event = utils.events.BufEnter,
		build = treesitter_build,
		config = treesitterconfig_config,
		dependencies = {
			{ "windwp/nvim-ts-autotag" },
		},
	},
	{
		"lukas-reineke/indent-blankline.nvim",
		event = utils.events.BufEnter,
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = indent_blankline_config,
	},
}
