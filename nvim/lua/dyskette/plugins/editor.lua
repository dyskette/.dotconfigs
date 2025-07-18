local utils = require("dyskette.utils")

local indent_config = function()
	require("guess-indent").setup({})
end

local surround_config = function()
	require("nvim-surround").setup({})
end

local comment_config = function()
	---@diagnostic disable-next-line: missing-fields
	require("Comment").setup({})
end

local autopairs_config = function()
	require("nvim-autopairs").setup({})
end

local autotag_config = function()
	---@diagnostic disable-next-line: missing-fields
	require("nvim-ts-autotag").setup({})
end

local imgclip_config = function()
	require("dyskette.keymaps").imgclip()
end

local nvim_highlight_colors_config = function()
	require("nvim-highlight-colors").setup({})
end

local live_rename_config = function()
	require("live-rename").setup({})
end

return {
	-- Detect expandtab, tabstop, softtabstop and shiftwidth automatically
	{
		"nmac427/guess-indent.nvim",
		event = { utils.events.BufReadPre, utils.events.BufNew },
		config = indent_config,
	},
	-- Add parenthesis, tags, quotes with vim motions
	{
		"kylechui/nvim-surround",
		version = "*", -- Use for stability; omit to use `main` branch for the latest features
		event = utils.events.VeryLazy,
		config = surround_config,
	},
	-- Close parenthesis, tags, quotes on insert
	{
		"windwp/nvim-autopairs",
		event = utils.events.InsertEnter,
		config = autopairs_config,
	},
	-- Close tags e.g. <div></div> on insert
	{
		"windwp/nvim-ts-autotag",
		event = utils.events.InsertEnter,
		config = autotag_config,
	},
	{ "saecki/live-rename.nvim", event = utils.events.VeryLazy, config = live_rename_config },
	-- Code commenting with vim motions
	{
		"numToStr/Comment.nvim",
		event = utils.events.BufEnter,
		config = comment_config,
	},
	-- Paste image as a file in cwd/assets/ and get the path
	{
		"HakonHarnes/img-clip.nvim",
		keys = { { "<leader>ii", mode = { "n", "x" } } },
		config = imgclip_config,
	},
	-- Show colors like #eb6f92 with a background of its own color
	{
		"brenoprata10/nvim-highlight-colors",
		event = utils.events.BufReadPost,
		config = nvim_highlight_colors_config,
	},
	-- Json tools
	{
		"VPavliashvili/json-nvim",
		ft = "json", -- only load for json filetype
	},
}
