local peek_opts = {
	app = "browser",
}

local peek_config = function(_, opts)
	require("peek").setup(opts)
	vim.api.nvim_create_user_command("PeekOpen", require("peek").open, {})
	vim.api.nvim_create_user_command("PeekClose", require("peek").close, {})
end

return {
	"toppair/peek.nvim",
	ft = "markdown",
	build = "deno task --quiet build:fast",
	opts = peek_opts,
	config = peek_config,
}
