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

	telescope = function()
		local builtin = require("telescope.builtin")
		local live_grep_args = require("telescope").extensions.live_grep_args.live_grep_args
		local file_browser = require("telescope").extensions.file_browser.file_browser

		vim.keymap.set("n", "<leader>sd", function()
			file_browser({
				files = false,
				depth = false,
			})
		end, { desc = "Search directories" })
		vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "Search files" })
		vim.keymap.set("n", "<leader>sr", function()
			builtin.oldfiles({ only_cwd = true })
		end, { desc = "Search recent files" })
		vim.keymap.set("n", "<leader>si", builtin.git_files, { desc = "Search git files" })
		vim.keymap.set("n", "<leader>sg", live_grep_args, { desc = "Search by grep" })
		vim.keymap.set({ "x", "n" }, "<leader>sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
		vim.keymap.set("n", "<leader>sb", builtin.buffers, { desc = "Search buffers" })
		vim.keymap.set("n", "<leader>sh", function()
			builtin.find_files({ hidden = true })
		end, { desc = "Search files with hidden enabled" })
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
	end,

	lsp = function(client, buffer)
		local utils = require("dyskette.utils")
		local opts = function(description)
			return {
				buffer = buffer,
				desc = description,
				silent = true,
			}
		end

		vim.keymap.set("n", "K", vim.lsp.buf.hover, opts("Open symbol information"))

		vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts("Go to definition"))
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))
		vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts("Go to implementation"))
		vim.keymap.set("n", "go", vim.lsp.buf.type_definition, opts("Go to definition of the type"))
		vim.keymap.set("n", "gr", vim.lsp.buf.references, opts("Go to references"))
		vim.keymap.set("n", "<leader>so", vim.lsp.buf.document_symbol, { desc = "Search symbols" })

		vim.keymap.set({ "n", "x" }, "<leader>va", vim.lsp.buf.code_action, opts("View code action"))
		vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename symbol"))
		vim.keymap.set({ "n", "x" }, "<leader>fl", function()
			vim.lsp.buf.format({ async = true })
		end, opts("Format document using LSP"))

		vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts("View diagnostic"))
		vim.keymap.set("n", "<leader>dk", vim.diagnostic.goto_prev, opts("Previous diagnostic"))
		vim.keymap.set("n", "<leader>dj", vim.diagnostic.goto_next, opts("Next diagnostic"))
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
		vim.keymap.set("n", "<leader>5", dap.continue, { desc = "Start or resume the debug session" })
		vim.keymap.set("n", "<leader>%", dap.terminate, { desc = "Terminate the debug session" })
		vim.keymap.set("n", "<leader>9", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
		vim.keymap.set("n", "<leader>0", dap.step_over, { desc = "Step over" })
		vim.keymap.set("n", "<leader>'", dap.step_into, { desc = "Step into" })
		vim.keymap.set("n", "<leader>?", dap.step_out, { desc = "Step out" })
		vim.keymap.set("n", "<leader>dg", dap.goto_, { desc = "Go to line" })
		vim.keymap.set("n", "<leader>di", function()
			dapui.eval(nil, { enter = true })
		end, { desc = "Debug inspect value" })
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
