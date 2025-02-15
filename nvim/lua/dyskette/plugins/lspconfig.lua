local utils = require("dyskette.utils")

-- LSP client capabilities with cmp (snippets, completion) if available
local make_client_capabilities = function()
	local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
	local capabilities = vim.lsp.protocol.make_client_capabilities()

	if has_cmp then
		capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
	end

	return capabilities
end

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

--- Enable reference count as virtual text via codelens
--- @param client vim.lsp.Client
--- @param bufnr integer
local enable_lsp_codelens_refresh = function(client, bufnr)
	if not client.server_capabilities.codeLensProvider then
		return
	end

	local group = "dyskette_lsp_codelens_refresh"
	local events = { "LspAttach", "InsertLeave", "BufReadPost" }
	local has_autocmds, autocmds = pcall(vim.api.nvim_get_autocmds, { group = group, buffer = bufnr, event = events })

	if has_autocmds and #autocmds > 0 then
		return
	end

	vim.defer_fn(vim.lsp.codelens.refresh, 1000)
	vim.api.nvim_create_augroup(group, { clear = false })
	vim.api.nvim_create_autocmd(events, {
		group = group,
		buffer = bufnr,
		callback = vim.lsp.codelens.refresh,
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

	-- Use symbol-usage.nvim instead of lspconfig's implementation
	-- enable_lsp_codelens_refresh(client, bufnr)
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
---@diagnostic disable-next-line: missing-fields
local default_config = {
	capabilities = make_client_capabilities(),
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

local language_servers_configuration = function()
	local lspconfig = require("lspconfig")

	local lua_ls_setup = function()
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
			-- Let lazydev do the actual setup, just configure codelens here
			settings = {
				Lua = {
					codeLens = {
						enable = true,
					},
				},
			},
		})

		lspconfig.lua_ls.setup(config)
	end

	local bashls_setup = function()
		lspconfig.bashls.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local powershell_es_setup = function()
		local bundle_path = require("mason-registry").get_package("powershell-editor-services"):get_install_path()
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
			bundle_path = bundle_path,
		})

		lspconfig.powershell_es.setup(config)
	end

	local pyright_setup = function()
		lspconfig.pyright.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local ts_ls_setup = function()
		local vue_typescript_plugin = require("mason-registry").get_package("vue-language-server"):get_install_path()
			.. "/node_modules/@vue/language-server"
			.. "/node_modules/@vue/typescript-plugin"
		-- This does not work. Typescript server does not support codelens in neovim.
		local common_language_settings = {
			implementationsCodeLens = {
				enabled = true,
			},
			referencesCodeLens = {
				enabled = true,
				showOnAllFunctions = true,
			},
		}
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
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
			settings = {
				typescript = common_language_settings,
				javascript = common_language_settings,
				javascriptreact = common_language_settings,
				typescriptreact = common_language_settings,
				vue = common_language_settings,
			},
		})

		lspconfig.ts_ls.setup(config)
	end

	local eslint_setup = function()
		lspconfig.eslint.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local volar_setup = function()
		lspconfig.volar.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local html_setup = function()
		lspconfig.html.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local cssls_setup = function()
		lspconfig.cssls.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local jsonls_setup = function()
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
			settings = {
				json = {
					schemas = require("schemastore").json.schemas(),
					validate = { enable = true },
				},
			},
		})

		lspconfig.jsonls.setup(config)
	end

	local yamlls_setup = function()
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
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

		lspconfig.yamlls.setup(config)
	end

	local lemminx_setup = function()
		lspconfig.lemminx.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local omnisharp_setup = function()
		---@type ProgressHandle
		local handle
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
			cmd = {
				"omnisharp",
			},
			on_new_config = function(new_config, new_root_dir)
				-- Show fidget spinning
				---@diagnostic disable-next-line: missing-fields
				handle = require("fidget.progress").handle.create({
					title = "Loading files",
					message = "In progress...",
					lsp_client = { name = "omnisharp" },
				})
				-- Execute default on_new_config()
				local lspconfig_omnisharp = require("lspconfig.server_configurations.omnisharp")
				lspconfig_omnisharp.default_config.on_new_config(new_config, new_root_dir)
			end,
			on_attach = function(client, bufnr)
				-- Hide fidget spinning after final message
				vim.defer_fn(function()
					---@diagnostic disable-next-line: missing-fields
					handle:report({
						title = "Loaded file",
						message = "Completed",
						done = true,
					})
					handle:finish()
				end, 3000)

				-- Execute default on_attach
				on_lsp_attach(client, bufnr)
			end,
			settings = {
				FormattingOptions = {
					-- Enables support for reading code style, naming convention and analyzer
					-- settings from .editorconfig.
					EnableEditorConfigSupport = true,
					-- Specifies whether 'using' directives should be grouped and sorted during
					-- document formatting.
					OrganizeImports = nil,
				},
				MsBuild = {
					-- If true, MSBuild project system will only load projects for files that
					-- were opened in the editor. This setting is useful for big C# codebases
					-- and allows for faster initialization of code navigation features only
					-- for projects that are relevant to code that is being edited. With this
					-- setting enabled OmniSharp may load fewer projects and may thus display
					-- incomplete reference lists for symbols.
					LoadProjectsOnDemand = nil,
				},
				RoslynExtensionsOptions = {
					-- Enables support for roslyn analyzers, code fixes and rulesets.
					EnableAnalyzersSupport = true,
					-- Enables support for showing unimported types and unimported extension
					-- methods in completion lists. When committed, the appropriate using
					-- directive will be added at the top of the current file. This option can
					-- have a negative impact on initial completion responsiveness,
					-- particularly for the first few completion sessions after opening a
					-- solution.
					EnableImportCompletion = nil,
					-- Only run analyzers against open files when 'enableRoslynAnalyzers' is
					-- true
					AnalyzeOpenDocumentsOnly = true,
				},
				Sdk = {
					-- Specifies whether to include preview versions of the .NET SDK when
					-- determining which version to use for project loading.
					IncludePrereleases = true,
				},
			},
			handlers = {
				-- Go to definition of external libraries
				[vim.lsp.protocol.Methods.textDocument_definition] = require("omnisharp_extended").handler,
			},
		})

		lspconfig.omnisharp.setup(config)
	end

	local csharp_ls_setup = function()
		--- @type lspconfig.Config
		local config = vim.tbl_deep_extend("force", default_config, {
			handlers = {
				[vim.lsp.protocol.Methods.textDocument_definition] = require("csharpls_extended").handler,
				[vim.lsp.protocol.Methods.textDocument_typeDefinition] = require("csharpls_extended").handler,
			},
		})

		lspconfig.csharp_ls.setup(config)
	end

	local dartls_setup = function()
		lspconfig.dartls.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	local rust_analyzer_setup = function()
		lspconfig.rust_analyzer.setup(vim.tbl_deep_extend("force", default_config, {}))
	end

	-- scripting
	lua_ls_setup()
	bashls_setup()
	powershell_es_setup()
	pyright_setup()

	-- javascript and typescript
	ts_ls_setup()
	eslint_setup()
	volar_setup()

	-- web common
	html_setup()
	cssls_setup()

	-- common file formats
	jsonls_setup()
	yamlls_setup()
	lemminx_setup()

	-- other languages
	-- omnisharp_setup()
	-- csharp_ls_setup()
	dartls_setup()
	rust_analyzer_setup()
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
		config = vim.tbl_deep_extend("force", default_config, {}),
		broad_search = true,
		lock_target = true,
	})

	local group = vim.api.nvim_create_augroup("dyskette_lsp_roslyn", { clear = true })
	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		pattern = "*",
		group = group,
		callback = function()
			local clients = vim.lsp.get_clients({ name = "roslyn" })
			if not clients or #clients == 0 then
				return
			end

			local buffers = vim.lsp.get_buffers_by_client_id(clients[1].id)
			for _, buf in ipairs(buffers) do
				vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
			end
		end,
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

			-- Ionide F#
			{ "ionide/Ionide-vim" },

			-- Omnisharp external libraries information on "go to definition"
			{ "Hoffs/omnisharp-extended-lsp.nvim" },

			-- csharp-language-server libraries information on "go to definition"
			{ "Decodetalkers/csharpls-extended-lsp.nvim" },

			-- Method signature when writing
			{ "Issafalcon/lsp-overloads.nvim" },

			-- JSON and YAML schemas
			{ "b0o/schemastore.nvim" },
		},
	},
	{
		"folke/lazydev.nvim",
		event = utils.events.VeryLazy,
		ft = "lua",
		config = lazydev_config,
	},
	{ 
		"Bilal2453/luvit-meta",
		event = utils.events.VeryLazy,
	}, -- `vim.uv` typings
	{ 
		"saecki/live-rename.nvim",
		event = utils.events.VeryLazy,
	},
	{
		"seblyng/roslyn.nvim",
		ft = "cs",
		config = roslyn_config,
		dependencies = {
			"neovim/nvim-lspconfig",
			"williamboman/mason.nvim",
		},
	},
}
