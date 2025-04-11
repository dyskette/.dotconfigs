local utils = require("dyskette.utils")

--- Things to do when the LSP has attached to the buffer
--- @param client vim.lsp.Client
--- @param bufnr integer
local on_lsp_attach = function(client, bufnr)
	if client == nil then
		return
	end

	-- Disable syntax highlighting from lsp server, and let treesitter do it
	client.server_capabilities.semanticTokensProvider = {}

	-- Enable keymaps
	require("dyskette.keymaps").lsp(client, bufnr)
end

--- Default configuration for language servers
--- @return lspconfig.Config
local default_config = function()
	return {
		capabilities = require("blink.cmp").get_lsp_capabilities(),
		---@diagnostic disable-next-line: missing-fields
		flags = {
			debounce_text_changes = 300, -- miliseconds
		},
		on_attach = on_lsp_attach,
	}
end

--- Configuration for typescript server
--- @return lspconfig.Config
local ts_ls_config = function()
	local vue_typescript_plugin = require("mason-registry").get_package("vue-language-server"):get_install_path()
		.. "/node_modules/@vue/language-server"
		.. "/node_modules/@vue/typescript-plugin"
	--- @type lspconfig.Config
	local config = vim.tbl_deep_extend("force", default_config(), {
		init_options = {
			plugins = {
				{
					name = "@vue/typescript-plugin",
					location = vue_typescript_plugin,
					languages = { "javascript", "typescript", "vue" },
				},
			},
		},
		filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue" },
	})

	return config
end

local language_servers_configuration = function()
	local lspconfig = require("lspconfig")

	lspconfig.util.default_config = vim.tbl_deep_extend("force", lspconfig.util.default_config, default_config())

	-- scripting
	lspconfig.lua_ls.setup({})
	lspconfig.bashls.setup({})
	lspconfig.powershell_es.setup({
		bundle_path = require("mason-registry").get_package("powershell-editor-services"):get_install_path(),
	})
	lspconfig.pyright.setup({})

	-- javascript and typescript
	lspconfig.ts_ls.setup(ts_ls_config())
	lspconfig.eslint.setup({})
	lspconfig.volar.setup({})

	-- web common
	lspconfig.html.setup({})
	lspconfig.cssls.setup({})
	lspconfig.jsonls.setup({
		settings = {
			json = {
				schemas = require("schemastore").json.schemas(),
				validate = { enable = true },
			},
		},
	})
	lspconfig.yamlls.setup({
		settings = {
			yaml = {
				schemaStore = {
					-- Disable built-in schemaStore support in favor of b0o/schemastore.nvim
					enable = false,
					-- Avoid TypeError: Cannot read properties of undefined (reading 'length')
					url = "",
				},
				schemas = require("schemastore").yaml.schemas(),
			},
		},
	})
	lspconfig.lemminx.setup({}) -- XML language server

	-- other languages
	lspconfig.dartls.setup({})
	lspconfig.rust_analyzer.setup({})
end

local lspconfig_config = function()
	require("lspconfig.ui.windows").default_options = {
		border = "rounded",
	}

	language_servers_configuration()
end

local lazydev_config = function()
	require("lazydev").setup({
		library = {
			-- Load luvit types when the `vim.uv` word is found
			{ path = "luvit-meta/library", words = { "vim%.uv" } },
		},
	})
end

local roslyn_config = function()
	require("roslyn").setup({
		args = {
			"--stdio",
			"--logLevel=Information",
			"--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
			"--razorSourceGenerator=" .. vim.fs.joinpath(
				vim.fn.stdpath("data") --[[@as string]],
				"mason",
				"packages",
				"roslyn",
				"libexec",
				"Microsoft.CodeAnalysis.Razor.Compiler.dll"
			),
			"--razorDesignTimePath=" .. vim.fs.joinpath(
				vim.fn.stdpath("data") --[[@as string]],
				"mason",
				"packages",
				"rzls",
				"libexec",
				"Targets",
				"Microsoft.NET.Sdk.Razor.DesignTime.targets"
			),
		},
		config = vim.tbl_deep_extend("force", default_config(), {
			handlers = require("rzls.roslyn_handlers"),
		}),
		broad_search = true,
		lock_target = true,
	})

	vim.filetype.add({
		extension = {
			razor = "razor",
			cshtml = "razor",
		},
	})
end

return {
	{
		"neovim/nvim-lspconfig",
		event = utils.events.VeryLazy,
		config = lspconfig_config,
		dependencies = {
			-- Servers
			{ "williamboman/mason.nvim" },

			-- Completion
			{ "saghen/blink.cmp" },

			-- lua
			{
				"folke/lazydev.nvim",
				config = lazydev_config,
				dependencies = {
					"Bilal2453/luvit-meta", -- `vim.uv` typings
				},
			},

			-- Roslyn C#
			{
				"seblyng/roslyn.nvim",
				config = roslyn_config,
				dependencies = {
					"tris203/rzls.nvim",
				},
			},

			-- JSON and YAML schemas
			{ "b0o/schemastore.nvim" },
		},
	},
}
