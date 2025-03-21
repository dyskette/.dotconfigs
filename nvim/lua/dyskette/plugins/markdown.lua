local utils = require("dyskette.utils")

local peek_config = function()
	require("peek").setup({
		app = "browser",
	})
	vim.api.nvim_create_user_command("PeekOpen", require("peek").open, {})
	vim.api.nvim_create_user_command("PeekClose", require("peek").close, {})
end

return {
	"toppair/peek.nvim",
	event = utils.events.VeryLazy,
	build = "deno task --quiet build:fast",
	config = peek_config,
}
