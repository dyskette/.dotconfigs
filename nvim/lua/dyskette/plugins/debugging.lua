local dap_config = function()
	local dap = require("dap")
	local dapui = require("dapui")

	---@diagnostic disable-next-line: missing-fields
	dapui.setup({
		---@diagnostic disable-next-line: missing-fields
		floating = {
			border = "rounded",
		},
	})

	-- Automatically open and close the nvim-dap-ui windows
	dap.listeners.before.attach.dapui_config = function()
		dapui.open({ reset = true })
	end
	dap.listeners.before.launch.dapui_config = function()
		dapui.open({ reset = true })
	end
	dap.listeners.before.event_terminated.dapui_config = function()
		dapui.close()
	end
	dap.listeners.before.event_exited.dapui_config = function()
		dapui.close()
	end

	---@diagnostic disable-next-line: missing-fields
	require("mason-nvim-dap").setup({
		handlers = {},
	})
	require("dyskette.keymaps").dap()
end

local virtual_text_config = function()
	---@diagnostic disable-next-line: missing-fields
	require("nvim-dap-virtual-text").setup({})
end

return {
	{
		"mfussenegger/nvim-dap",
		config = dap_config,
		keys = { { "<leader>5", mode = { "n" } } },
		dependencies = {
			-- Async library
			{ "nvim-neotest/nvim-nio" },
			-- UI for debugging
			{ "rcarriga/nvim-dap-ui" },
			-- Virtual text with variable values while debugging
			{
				"theHamsta/nvim-dap-virtual-text",
				config = virtual_text_config,
				dependencies = { "nvim-treesitter/nvim-treesitter" },
			},
			-- Dependency downloader
			{ "williamboman/mason.nvim" },
			-- Adapt mason to dap to download debuggers
			{ "jay-babu/mason-nvim-dap.nvim" },
		},
	},
}
