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
		vim.keymap.set("t", "<C-|><C-n>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })

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
	end,

	fzf = function()
		local fzf = require("fzf-lua")

		vim.keymap.set("n", "<leader>sf", fzf.files, { desc = "Search files" })
		vim.keymap.set("n", "<leader>sr", fzf.oldfiles, { desc = "Search recent files" })
		vim.keymap.set("n", "<leader>si", fzf.git_files, { desc = "Search git files" })
		vim.keymap.set("n", "<leader>sg", fzf.live_grep_native, { desc = "Search by grep" })
		vim.keymap.set("n", "<leader>sw", fzf.grep_cword, { desc = "Search current word" })
		vim.keymap.set("x", "<leader>sw", fzf.grep_visual, { desc = "Search current selection" })
		vim.keymap.set("n", "<leader>sb", fzf.buffers, { desc = "Search buffers" })
		vim.keymap.set("n", "<leacer>so", fzf.lsp_workspace_symbols, { desc = "Search workspace symbols" })

		vim.keymap.set("n", "<leader>sd", fzf.dap_commands, { desc = "Search dap commands" })
	end,

	lsp = function(client, buffer)
		local fzf = require("fzf-lua")
		local live_rename = require("live-rename")

		local opts = function(description)
			return {
				buffer = buffer,
				desc = description,
				silent = true,
			}
		end

		vim.keymap.set("n", "K", function()
			print("Executing hover...")
			vim.lsp.buf.hover({ border = "rounded", title = " Information " })
		end, opts("Open symbol information"))
		vim.keymap.set("n", "<leader>rn", live_rename.rename, opts("Rename symbol"))
		vim.keymap.set({ "n", "x" }, "<leader>fl", function()
			vim.lsp.buf.format({ async = true })
		end, opts("Format document using LSP"))

		vim.keymap.set("n", "gd", fzf.lsp_definitions, opts("Go to definition"))
		vim.keymap.set("n", "gD", fzf.lsp_declarations, opts("Go to declaration"))
		vim.keymap.set("n", "gi", fzf.lsp_implementations, opts("Go to implementation"))
		vim.keymap.set("n", "go", fzf.lsp_typedefs, opts("Go to definition of the type"))
		vim.keymap.set("n", "gr", fzf.lsp_references, opts("Go to references"))
		vim.keymap.set("n", "<leader>so", fzf.lsp_workspace_symbols, { desc = "Search symbols" })
		vim.keymap.set({ "n", "x" }, "<leader>va", fzf.lsp_code_actions, opts("View code action"))

		vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts("View diagnostic"))
		vim.keymap.set("n", "<leader>dk", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, opts("Previous diagnostic"))
		vim.keymap.set("n", "<leader>dj", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, opts("Next diagnostic"))
	end,

	lsp_signature = function(bufnr)
		vim.keymap.set("i", "<A-s>", vim.cmd.LspOverloadsSignature, { noremap = true, silent = true, buffer = bufnr })
		return {
			keymaps = {
				next_signature = "<C-j>",
				previous_signature = "<C-k>",
				next_parameter = "<C-l>",
				previous_parameter = "<C-h>",
				close_signature = "<A-s>",
			},
		}
	end,

	conform = function()
		local conform = require("conform")

		vim.keymap.set({ "n", "x" }, "<leader>ff", function()
			local bufnr = vim.api.nvim_get_current_buf()
			conform.format({ bufnr = bufnr, async = true, lsp_format = "fallback" })
		end, { desc = "Format buffer using conform" })
	end,

	yazi = function()
		local yazi = require("yazi")
		vim.keymap.set({ "n", "x" }, "<leader>e", yazi.yazi, { desc = "Open parent directory" })
	end,

	neogen = function()
		local neogen_plugin = require("neogen")
		vim.keymap.set("n", "<leader>nf", neogen_plugin.generate, { desc = "Generate code documentation" })
	end,

	imgclip = function()
		local imgclip = require("img-clip")
		vim.keymap.set({ "n", "x" }, "<leader>ii", imgclip.pasteImage, { desc = "Paste image from clipbard" })
	end,

	dap = function()
		local dap = require("dap")
		local dapui = require("dapui")
		local widgets = require("dap.ui.widgets")

		vim.keymap.set("n", "<leader>di", function()
			dapui.eval(nil, { enter = true })
		end, { desc = "Debug inspect value" })

		-- TODO: When pressing F5 and if there it is not stopped then offer the option to restart to the user
		vim.keymap.set("n", "<F5>", dap.continue, { desc = "Debug start or continue" })
		vim.keymap.set("n", "<S-F5>", dap.terminate, { desc = "Terminate the debug session" })
		vim.keymap.set("n", "<F9>", dap.toggle_breakpoint, { desc = "Debug toggle breakpoint" })
		vim.keymap.set("n", "<F10>", dap.step_over, { desc = "Debug step over" })
		vim.keymap.set("n", "<F11>", dap.step_into, { desc = "Debug step into" })
		vim.keymap.set("n", "<F12>", dap.step_out, { desc = "Debug step out" })

		vim.keymap.set("n", "<Leader>dw", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
		end, { desc = "Debug write output message" })
		vim.keymap.set("n", "<Leader>dr", dap.repl.open, { desc = "Debug, use REPL to evaluate sentences" })
		vim.keymap.set("n", "<Leader>dl", dap.run_last, { desc = "Debug run the last session again" })
		vim.keymap.set(
			{ "n", "v" },
			"<Leader>dh",
			widgets.hover,
			{ desc = "Debug evaluate expression and display in floating window" }
		)
		vim.keymap.set(
			{ "n", "v" },
			"<Leader>dp",
			widgets.preview,
			{ desc = "Debug evaluate expression and display in preview window" }
		)
		vim.keymap.set("n", "<Leader>df", function()
			widgets.centered_float(widgets.frames)
		end, { desc = "Debug show the stack frames in a floating window" })
		vim.keymap.set("n", "<Leader>ds", function()
			widgets.centered_float(widgets.scopes)
		end, { desc = "Debug show the variables of current scope in a floating window" })
	end,

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

	gitsigns = function()
		local gitsigns = require("gitsigns")
		vim.keymap.set("n", "<leader>gb", function()
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
				gitsigns.blame()
			end
		end, { desc = "Show git blame" })
	end,

	neogit = function(neogit_setup)
		local neogit = require("neogit")
		vim.keymap.set("n", "<leader>gg", function()
			neogit_setup()
			neogit.open()
		end, { desc = "Git status open" })
	end,

	zen_mode = function()
		local zen_mode = require("zen-mode")
		vim.keymap.set("n", "<leader>Z", zen_mode.toggle, { desc = "Toggle zen mode" })
	end,
}
