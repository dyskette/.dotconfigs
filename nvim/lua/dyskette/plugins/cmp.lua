local utils = require("dyskette.utils")

local completion_config = function()
	local keymaps = require("dyskette.keymaps")
	local cmp = require("cmp")
	local luasnip = require("luasnip")

	cmp.setup({
		---@diagnostic disable-next-line: missing-fields
		performance = {
			-- Sources will use this quantity as default for max_item_count, I don't really need 200 entries
			max_view_entries = 60,
			-- 240 ms between keys is my average so let's not hit the sources so much
			debounce = 240,
			-- Delay filtering and displaying completions
			throttle = 30,
			-- Time to wait for the most prioritized source
			fetching_timeout = 500,
			confirm_resolve_timeout = 80,
			async_budget = 1,
		},
		sources = cmp.config.sources({
			{
				name = "nvim_lsp",
				-- Some servers are slow
				-- so let's not fetch so much info from them
				-- 30 entries is enough I think
				max_item_count = 30,
			},
			{ name = "luasnip" },
			{ name = "buffer" },
			-- { name = "codeium" },
		}),
		mapping = keymaps.cmp(),
		snippet = {
			expand = function(args)
				luasnip.lsp_expand(args.body)
			end,
		},
		window = {
			completion = cmp.config.window.bordered({
				winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None",
			}),
			documentation = cmp.config.window.bordered({
				winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None",
			}),
		},
		completion = {
			-- Autoselect first option
			completeopt = "menu,menuone,noinsert",
			-- autocomplete = true,
		},
	})

	cmp.setup.filetype({ "gitcommit", "NeogitCommitMessage" }, {
		sources = cmp.config.sources({
			{ name = "git" },
			{ name = "luasnip" },
			{ name = "buffer" },
		}),
	})

	cmp.setup.cmdline({ "/", "?" }, {
		mapping = cmp.mapping.preset.cmdline(),
		sources = {
			{ name = "buffer" },
		},
		completion = {
			-- Do not autoselect first option in cmdline
			-- because it doesn't work
			completeopt = "menu,menuone,noselect",
		},
	})

	cmp.setup.cmdline(":", {
		mapping = cmp.mapping.preset.cmdline(),
		sources = cmp.config.sources({
			{ name = "path" },
			{ name = "cmdline" },
		}),
		completion = {
			-- Do not autoselect first option in cmdline
			-- because it doesn't work
			completeopt = "menu,menuone,noselect",
		},
	})

	-- Insert `(` after select function or method item
	local cmp_autopairs = require("nvim-autopairs.completion.cmp")
	cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
end

local snippets_config = function()
	-- Configure completion for vscode-like snippets packages
	require("luasnip.loaders.from_vscode").lazy_load()

	-- Enable standardized code comment snippets
	require("luasnip").filetype_extend("typescript", { "tsdoc" })
	require("luasnip").filetype_extend("javascript", { "jsdoc" })
	require("luasnip").filetype_extend("lua", { "luadoc" })
	require("luasnip").filetype_extend("python", { "pydoc" })
	require("luasnip").filetype_extend("rust", { "rustdoc" })
	require("luasnip").filetype_extend("cs", { "csharpdoc" })
	require("luasnip").filetype_extend("sh", { "shelldoc" })
end

local cmp_git_config = function()
	require("cmp_git").setup({
		filetypes = { "gitcommit", "NeogitCommitMessage" },
	})
end

return {
	{
		"hrsh7th/nvim-cmp",
		config = completion_config,
		event = { utils.events.InsertEnter, utils.events.CmdlineEnter },
		dependencies = {
			-- Sources
			{ "hrsh7th/cmp-nvim-lsp" },
			{ "hrsh7th/cmp-buffer" },
			{ "hrsh7th/cmp-path" },
			{ "hrsh7th/cmp-cmdline" },
			{
				"petertriho/cmp-git",
				config = cmp_git_config,
				dependencies = {
					"nvim-lua/plenary.nvim",
				},
			},
			{ "saadparwaiz1/cmp_luasnip" },
			{ "Exafunction/codeium.nvim" },

			-- Snippet engine
			{
				"L3MON4D3/LuaSnip",
				build = "make install_jsregexp",
				config = snippets_config,
				dependencies = {
					-- vscode-like snippets packages
					{ "rafamadriz/friendly-snippets" },
				},
			},

			-- Insert brackets after method completion
			{ "windwp/nvim-autopairs" },
		},
	},
}
