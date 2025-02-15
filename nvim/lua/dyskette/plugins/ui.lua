local utils = require "dyskette.utils"
local vanilla_config = function()
	vim.fn.sign_define("DiagnosticSignError", { texthl = "DiagnosticSignError", text = "󰅚" })
	vim.fn.sign_define("DiagnosticSignWarn", { texthl = "DiagnosticSignWarn", text = "󰀪" })
	vim.fn.sign_define("DiagnosticSignInfo", { texthl = "DiagnosticSignInfo", text = "󰋽" })
	vim.fn.sign_define("DiagnosticSignHint", { texthl = "DiagnosticSignHint", text = "󰌶" })

	vim.diagnostic.config({
		virtual_text = {
			prefix = "󰄮",
		},
		float = { border = "rounded", header = "" },
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

local kanagawa_config = function()
	require("kanagawa").setup({
		compile = true,
		dimInactive = true,
		background = {
			dark = "wave",
			light = "lotus",
		},
	})
	vim.cmd.colorscheme("kanagawa")
end

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
			window = {
				max_height = 6
			},
		},
	})
end

local zen_mode_config = function()
	require("dyskette.keymaps").zen_mode()
end

return {
	{
		"f-person/auto-dark-mode.nvim",
		event = utils.events.VeryLazy,
		config = true,
	},
	-- Color scheme
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		config = kanagawa_config,
	},
	-- tab bar
	{
		"alvarosevilla95/luatab.nvim",
		config = luatab_config,
		event = utils.events.VeryLazy,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
	},
	-- Status bar
	{
		"nvim-lualine/lualine.nvim",
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
		event = utils.events.VeryLazy,
		config = zen_mode_config,
	},
}
