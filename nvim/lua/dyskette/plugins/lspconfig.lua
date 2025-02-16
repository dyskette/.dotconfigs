local utils = require("dyskette.utils")

-- Configure signature floating window on insert mode that shows overloads
local enable_lsp_signature_overloads = function(client, bufnr)
	if not client.server_capabilities.signatureHelpProvider then
		return
	end

	require("lsp-overloads").setup(client, {
		ui = {
			close_events = { "CursorMoved", "CursorMovedI", "InsertCharPre" },
			floating_window_above_cur_line = true,
			border = "rounded",
			silent = true,
			title = " Overloads ",
		},
		keymaps = require("dyskette.keymaps").lsp_signature(bufnr),
		display_automatically = false,
		silent = true,
	})
end

--- Things to do when the LSP has attached to the buffer
--- @param client vim.lsp.Client
--- @param bufnr integer
local on_lsp_attach = function(client, bufnr)
	if client == nil then
		return
	end

	-- Disable syntax LSP's highlighting (let tree-sitter do it)
	client.server_capabilities.semanticTokensProvider = {}
	-- Enable keymaps
	require("dyskette.keymaps").lsp(client, bufnr)

	enable_lsp_signature_overloads(client, bufnr)
end

--- Format markdown information of signatures
--- @param client vim.lsp.Client|nil
--- @param contents string
local format_markdown_info = function(client, contents)
	local is_pyright = client and client.name == "pyright"
	local is_omnisharp = client and client.name == "omnisharp"
	local is_jsonls = client and client.name == "jsonls"
	local is_yamlls = client and client.name == "yamlls"
	local is_roslyn = client and client.name == "roslyn"

	if is_pyright or is_omnisharp or is_jsonls or is_yamlls or is_roslyn then
		contents = string.gsub(contents, "&nbsp;", " ")
		contents = string.gsub(contents, "&gt;", ">")
		contents = string.gsub(contents, "&lt;", "<")
		contents = string.gsub(contents, "\\", "")
	end

	contents = string.gsub(contents, "^(```)%w+\n?(.-)\n?(```)", "%1 %2 %3\n---", 1)
	contents = string.gsub(contents, "---$", "")

	contents = string.gsub(contents, "\r", "")

	return contents
end

--- Custom lsp hover method to customize its content
--- @param err lsp.ResponseError?
--- @param result lsp.Hover
--- @param ctx lsp.HandlerContext
--- @param config table
local lsp_hover = function(err, result, ctx, config)
	if vim.fn.has("nvim-0.11") == 1 then -- TODO: Delete when dropping 0.10 support
		return
	end

	local client = vim.lsp.get_client_by_id(ctx.client_id)

	if result then
		if type(result.contents) == "string" then
			local contents = tostring(result.contents or "")
			result.contents = format_markdown_info(client, contents)
		elseif type(result.contents) == "table" then
			local contents = result.contents.value or ""
			result.contents.value = format_markdown_info(client, contents)
		end
	end

	return vim.lsp.with(vim.lsp.handlers.hover(err, result, ctx, {
		border = "rounded",
		title = " Information ",
		silent = true,
	}))
end

--- Custom lsp signature help method to customize its content
--- Currently not in use because of lsp-overloads.
--- This is manually triggered by vim.lsp.buf.signature_help()
--- @param err lsp.ResponseError?
--- @param result lsp.SignatureHelp
--- @param ctx lsp.HandlerContext
--- @param config table
local lsp_signature_help = function(err, result, ctx, config)
	if vim.fn.has("nvim-0.11") == 1 then -- TODO: Delete when dropping 0.10 support
		return
	end

	if result then
		local client = vim.lsp.get_client_by_id(ctx.client_id)
		local documentation = result.signatures[1].documentation
		local signatures_label = result.signatures[1].label

		if documentation then
			-- TODO: Add extra line string.format("---%s---", content)
			if type(documentation) == "string" then
				local contents = tostring(documentation or "")
				documentation = format_markdown_info(client, contents)
			elseif type(documentation) == "table" then
				local contents = documentation.value or ""
				documentation.value = format_markdown_info(client, contents)
			end
		else
			signatures_label = format_markdown_info(client, signatures_label)
		end
	end

	return vim.lsp.with(vim.lsp.handlers.signature_help(err, result, ctx, {
		border = "rounded",
		title = " Signature ",
	}))
end

--- Default configuration for language servers
--- @type lspconfig.Config
local default_config = function()
	return {
		capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities()),
		---@diagnostic disable-next-line: missing-fields
		flags = {
			debounce_text_changes = 500, -- miliseconds
		},
		on_attach = on_lsp_attach,
		handlers = {
			-- Appearance of floating window for hover information
			[vim.lsp.protocol.Methods.textDocument_hover] = lsp_hover,
			-- Appearance of floating window for signature information
			[vim.lsp.protocol.Methods.textDocument_signatureHelp] = lsp_signature_help,
		},
	}
end

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
		config = vim.tbl_deep_extend("force", default_config(), {}),
		broad_search = true,
		lock_target = true,
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

			-- Autocompletion
			{ "hrsh7th/cmp-nvim-lsp" },

			-- lua
			{
				"folke/lazydev.nvim",
				config = lazydev_config,
				dependencies = {
					"Bilal2453/luvit-meta", -- `vim.uv` typings
				},
			},

			-- Ionide F#
			{ "ionide/Ionide-vim" },

			-- Roslyn C#
			{
				"seblyng/roslyn.nvim",
				config = roslyn_config,
			},

			-- JSON and YAML schemas
			{ "b0o/schemastore.nvim" },

			-- Method signature when writing
			{ "Issafalcon/lsp-overloads.nvim" },

			-- Rename inline
			{
				"saecki/live-rename.nvim",
			},
		},
	},
}
