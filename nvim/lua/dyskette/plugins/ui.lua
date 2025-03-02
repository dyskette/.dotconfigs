local utils = require("dyskette.utils")

local vanilla_config = function()
	vim.fn.sign_define("DiagnosticSignError", { texthl = "DiagnosticSignError", text = "󰅚" })
	vim.fn.sign_define("DiagnosticSignWarn", { texthl = "DiagnosticSignWarn", text = "󰀪" })
	vim.fn.sign_define("DiagnosticSignInfo", { texthl = "DiagnosticSignInfo", text = "󰋽" })
	vim.fn.sign_define("DiagnosticSignHint", { texthl = "DiagnosticSignHint", text = "󰌶" })

	vim.lsp.handlers["textDocument/hover"] =
		vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded", title = " Information " })

	vim.diagnostic.config({
		virtual_text = {
			prefix = "󰄮",
		},
		float = { border = "rounded", title = " Diagnostic " },
	})

	local get_hl_name = function()
		if vim.fn.hlexists("HighlightedyankRegion") == 1 then
			return "HighlightedyankRegion"
		end

		return "IncSearch"
	end

	local group = vim.api.nvim_create_augroup("dyskette_text_yank_highlight", { clear = true })
	vim.api.nvim_create_autocmd("TextYankPost", {
		desc = "Text yank highlight",
		group = group,
		callback = function()
			vim.highlight.on_yank({ higroup = get_hl_name(), timeout = 200 })
		end,
	})
end

vanilla_config()

local template_onlyname = function(filetype, name)
	return {
		filetypes = { filetype },
		sections = {
			lualine_a = { {
				function()
					return name
				end,
				color = "white",
			} },
		},
	}
end

local auto_dark_config = function()
	require("auto-dark-mode").setup({
		update_interval = 1000,
		fallback = "light",
		set_dark_mode = function()
			vim.api.nvim_set_option_value("background", "dark", {})
			vim.cmd.colorscheme("everforest")
			vim.env.BAT_THEME = "everforest"
		end,
		set_light_mode = function()
			vim.api.nvim_set_option_value("background", "light", {})
			vim.cmd.colorscheme("rose-pine-dawn")
			vim.env.BAT_THEME = "rose-pine-dawn"
		end,
	})
end

local luatab_config = function()
	require("luatab").setup({})
end

local lualine_config = function()
	local diffview_files = template_onlyname("DiffviewFiles", "Diffview Files")
	local diffview_file_history = template_onlyname("DiffviewFileHistory", "Diffview File History")

	require("lualine").setup({
		extensions = { "lazy", "mason", "oil", "trouble", diffview_files, diffview_file_history },
		options = {
			component_separators = { left = "|", right = "|" },
			section_separators = { left = "", right = "" },
		},
	})
end

local fidget_config = function()
	require("fidget").setup({
		notification = {
			override_vim_notify = true,
		},
	})
end

local zen_mode_config = function()
	require("dyskette.keymaps").zen_mode()
end

return {
	-- Color scheme
	{
		"f-person/auto-dark-mode.nvim",
		config = auto_dark_config,
	},
	{
		"neanias/everforest-nvim",
	},
	{
		"rose-pine/neovim",
		name = "rose-pine",
	},
	-- tab bar
	{
		"alvarosevilla95/luatab.nvim",
		event = utils.events.VeryLazy,
		config = luatab_config,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
	},
	-- Status bar
	{
		"nvim-lualine/lualine.nvim",
		event = utils.events.VeryLazy,
		config = lualine_config,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
	},
	-- LSP progress/vim.notify
	{
		"j-hui/fidget.nvim",
		event = utils.events.VeryLazy,
		config = fidget_config,
	},
	-- Zen mode
	{
		"folke/zen-mode.nvim",
		keys = { { "<leader>Z", modes = { "n" } } },
		config = zen_mode_config,
	},
}
