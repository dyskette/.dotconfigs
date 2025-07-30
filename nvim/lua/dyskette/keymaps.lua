return {
	-- Also check ":help normal-index" and ":help visual-index" for default key mappings
	vanilla = function()
		vim.g.mapleader = " "

		vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
		vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })

		vim.keymap.set("n", "<leader>a", ":keepjumps normal! ggVG<cr>", { desc = "Select all text in buffer" })

		vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up in visual mode" })
		vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down in visual mode" })

		vim.keymap.set(
			"n",
			"<leader>O",
			'<Cmd>call append(line(".") - 1, repeat([""], v:count1))<CR>',
			{ desc = "Enter a new line without entering insert mode" }
		)
		vim.keymap.set(
			"n",
			"<leader>o",
			'<Cmd>call append(line("."),     repeat([""], v:count1))<CR>',
			{ desc = "Enter a new line without entering insert mode" }
		)

		-- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
		vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
		vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

		-- Indent while remaining in visual mode
		vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
		vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

		-- Terminal
		vim.keymap.set("t", "<C-|>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })

		-- Quickfix
		local function toggle_quickfix()
			local wins = vim.fn.getwininfo()
			local qf_win = vim.iter(wins)
				:filter(function(win)
					return win.quickfix == 1
				end)
				:totable()
			if #qf_win == 0 then
				vim.cmd.copen()
			else
				vim.cmd.cclose()
			end
		end
		vim.keymap.set("n", "<leader>q", toggle_quickfix, { desc = "Toggle quickfix" })

		-- LSP
		vim.keymap.set("n", "K", function()
			vim.lsp.buf.hover({ border = "rounded", title = " Information " })
		end, { desc = "Open symbol information" })
		vim.keymap.set({ "n", "x" }, "<leader>fl", function()
			vim.lsp.buf.format({ async = true })
		end, { desc = "Format document using LSP" })

		-- Diagnostic
		vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { desc = "View diagnostic" })
		vim.keymap.set("n", "<leader>dk", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, { desc = "Previous diagnostic" })
		vim.keymap.set("n", "<leader>dj", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, { desc = "Next diagnostic" })
	end,

	fzf = {
		{ "<leader>sf", function() require("fzf-lua").files() end, desc = "Search files" },
		{ "<leader>sr", function() require("fzf-lua").oldfiles() end, desc = "Search recent files" },
		{ "<leader>si", function() require("fzf-lua").git_files() end, desc = "Search git files" },
		{ "<leader>sg", function() require("fzf-lua").live_grep_native() end, desc = "Search by grep" },
		{ "<leader>sw", function() require("fzf-lua").grep_cword() end, desc = "Search current word" },
		{ "<leader>sw", function() require("fzf-lua").grep_visual() end, mode = "x", desc = "Search current selection" },
		{ "<leader>sb", function() require("fzf-lua").buffers() end, desc = "Search buffers" },
		{ "<leader>so", function() require("fzf-lua").lsp_workspace_symbols() end, desc = "Search workspace symbols" },
		{ "<leader>sd", function() require("fzf-lua").dap_commands() end, desc = "Search dap commands" },
		{ "gd", function() require("fzf-lua").lsp_definitions() end, desc = "Go to definition" },
		{ "gD", function() require("fzf-lua").lsp_declarations() end, desc = "Go to declaration" },
		{ "gi", function() require("fzf-lua").lsp_implementations() end, desc = "Go to implementation" },
		{ "go", function() require("fzf-lua").lsp_typedefs() end, desc = "Go to definition of the type" },
		{ "gr", function() require("fzf-lua").lsp_references() end, desc = "Go to references" },
		{ "<leader>va", function() require("fzf-lua").lsp_code_actions() end, mode = { "n", "x" }, desc = "View code action" },
	},

	live_rename = {
		{ "<leader>rn", function() require("live-rename").rename() end, desc = "Rename symbol" },
	},

	conform = {
		{
			"<leader>ff",
			function()
				require("conform").format({ async = true, lsp_format = "fallback" })
			end,
			mode = { "n", "x" },
			desc = "Format buffer using conform",
		},
	},

	yazi = {
		{ "<leader>e", "<cmd>Yazi<cr>", mode = { "n", "x" }, desc = "Open parent directory" },
	},

	imgclip = function()
		local imgclip = require("img-clip")
		vim.keymap.set({ "n", "x" }, "<leader>ii", imgclip.pasteImage, { desc = "Paste image from clipbard" })
	end,

	dap = {
		{ "<leader>di", function() require("dapui").eval(nil, { enter = true }) end, desc = "Debug inspect value" },
		{ "<F5>", function() require("dap").continue() end, desc = "Debug start or continue" },
		{ "<S-F5>", function() require("dap").terminate() end, desc = "Terminate the debug session" },
		{ "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug toggle breakpoint" },
		{ "<F10>", function() require("dap").step_over() end, desc = "Debug step over" },
		{ "<F11>", function() require("dap").step_into() end, desc = "Debug step into" },
		{ "<F12>", function() require("dap").step_out() end, desc = "Debug step out" },
		{ "<Leader>dw", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: ")) end, desc = "Debug write output message" },
		{ "<Leader>dr", function() require("dap").repl.open() end, desc = "Debug, use REPL to evaluate sentences" },
		{ "<Leader>dl", function() require("dap").run_last() end, desc = "Debug run the last session again" },
		{ "<Leader>dh", function() require("dap.ui.widgets").hover() end, mode = { "n", "v" }, desc = "Debug evaluate expression and display in floating window" },
		{ "<Leader>dp", function() require("dap.ui.widgets").preview() end, mode = { "n", "v" }, desc = "Debug evaluate expression and display in preview window" },
		{ "<Leader>df", function() require("dap.ui.widgets").centered_float(require("dap.ui.widgets").frames) end, desc = "Debug show the stack frames in a floating window" },
		{ "<Leader>ds", function() require("dap.ui.widgets").centered_float(require("dap.ui.widgets").scopes) end, desc = "Debug show the variables of current scope in a floating window" },
	},

	git_diffview = function()
		vim.keymap.set("n", "<leader>gh", function()
			if next(require("diffview.lib").views) == nil then
				vim.cmd.DiffviewFileHistory('"' .. vim.api.nvim_buf_get_name(0) .. '"')
			else
				vim.cmd.DiffviewClose()
			end
		end, { desc = "Git file history (current buffer)" })
		vim.keymap.set("n", "<leader>gd", function()
			if next(require("diffview.lib").views) == nil then
				vim.cmd.DiffviewOpen()
			else
				vim.cmd.DiffviewClose()
			end
		end, { desc = "Git diff open" })
	end,

	gitsigns = {
		{
			"<leader>gb",
			function()
				local blame_buffer = nil
				for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "gitsigns-blame" then
						blame_buffer = bufnr
						break
					end
				end

				if blame_buffer ~= nil then
					vim.api.nvim_buf_delete(blame_buffer, {})
				else
					require("gitsigns").blame()
				end
			end,
			desc = "Show git blame",
		},
	},

	neogit = {
		{ "<leader>gg", function() require("neogit").open() end, desc = "Git status open" },
	},
}
