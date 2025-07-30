local utils = require("dyskette.utils")

local conform_config = function()
	local conform = require("conform")

	conform.setup({
		formatters_by_ft = {
			lua = { "stylua" },
			sh = { "beautysh" },
			python = { "isort", "black" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			typescriptreact = { "prettier" },
			svelte = { "prettier" },
			vue = { "prettier" },
			css = { "prettier" },
			html = { "prettier" },
			json = { "prettier" },
			yaml = { "prettier" },
			markdown = { "prettier" },
		},
		formatters = {},
	})

	require("dyskette.keymaps").conform()
end

local nvim_lint_config = function()
	local lint = require("lint")

	lint.linters_by_ft = {
		python = { "pylint" },
		-- javascript = { "eslint_d" },
		-- typescript = { "eslint_d" },
		-- javascriptreact = { "eslint_d" },
		-- typescriptreact = { "eslint_d" },
		-- svelte = { "eslint_d" },
	}

	local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = lint_augroup,
		callback = function()
			lint.try_lint()
		end,
	})
end

return {
	{
		"mfussenegger/nvim-lint",
		event = utils.events.BufEnter,
		config = nvim_lint_config,
	},
	{
		"stevearc/conform.nvim",
		config = conform_config,
		keys = require("dyskette.keymaps").conform,
	},
}
