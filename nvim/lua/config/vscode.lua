--- VS Code integration for vscode-neovim.
---
--- Inside VS Code, Neovim is only the editing engine: the host owns the
--- viewport, the language servers, completion, the pickers, git and the file
--- tree. Everything in `lua/plugins` that provides one of those is switched off
--- there (see the `cond` on each spec), so this module re-points the keymaps
--- that drove them at the equivalent VS Code commands. The keys stay the same;
--- only what answers them changes.
---
--- vscode-neovim sources its own runtime through `--cmd`, i.e. before this
--- config, so anything mapped here wins over the extension's defaults. Those
--- defaults are deliberately left alone where they already match this config:
--- `gd`, `K`, `gc`, `gq`/`=`, the `<C-w>` split commands, `zz`/`H`/`M`/`L`,
--- `gt`/`gT`, `<C-o>`/`<C-i>`, and the whole explorer/list layer.
local M = {}

local vscode = require("vscode")

--- A keymap callback that fires a VS Code command.
---@param name string VS Code command id
---@param opts table|nil Forwarded to `vscode.action` (`args`, `range`, ...)
---@return function
local function action(name, opts)
  return function()
    vscode.action(name, opts)
  end
end

--- A keymap callback that fires a VS Code command from insert mode.
---
--- VS Code drops the selection when a command takes focus away from the editor,
--- so widgets that act on a range (the code action and refactor menus) come up
--- empty when invoked straight from visual mode. `with_insert` switches modes
--- first, which keeps the selection alive for the widget.
---@param name string VS Code command id
---@return function
local function insert_action(name)
  return function()
    vscode.with_insert(function()
      vscode.action(name)
    end)
  end
end

--- The text currently selected in visual mode, newline-joined.
---@return string
local function selection()
  local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  return table.concat(region, "\n")
end

--- Open VS Code's search panel pre-filled with `query`.
---@param query string
local function find_in_files(query)
  vscode.action("workbench.action.findInFiles", { args = { query = query } })
end

--- Drop the Neovim 0.11 default LSP maps that would shadow the ones below.
---
--- Outside VS Code `lua/plugins/lspconfig.lua` does this; that spec does not
--- load here, so `gr` would otherwise sit behind the `grn`/`gra`/`grr` prefix
--- and wait out 'timeoutlen' before firing.
local function clear_default_lsp_maps()
  for _, lhs in ipairs({ "grn", "gra", "grr", "gri", "grt" }) do
    pcall(vim.keymap.del, "n", lhs)
  end
  pcall(vim.keymap.del, "x", "gra")
end

--- Keymaps for oil.code, the VS Code port of oil.nvim.
---
--- The extension ships these itself, but only behind a VSCodeVim `when` clause
--- that never matches here; `oil-code.disableVimKeymaps` turns that layer off
--- and hands the keys to Neovim, which is the one holding them anyway. `-` is
--- global (open the parent of the current file) and rebound buffer-locally
--- inside a listing so it walks further up instead of reopening.
local function setup_oil()
  vim.keymap.set("n", "-", action("oil-code.open"), { desc = "Open parent directory" })

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("dyskette_vscode_oil", { clear = true }),
    pattern = "oil",
    desc = "oil.code keymaps, mirroring oil.nvim's defaults",
    callback = function(args)
      local map = function(lhs, command, desc)
        vim.keymap.set("n", lhs, action(command), { buffer = args.buf, desc = desc })
      end

      map("-", "oil-code.openParent", "Open parent directory")
      map("_", "oil-code.openCwd", "Open current working directory")
      map("<CR>", "oil-code.select", "Open the entry under the cursor")
      map("<C-t>", "oil-code.selectTab", "Open the entry in a new tab")
      map("<C-l>", "oil-code.refresh", "Reload the listing from disk")
      -- <C-p> (preview) and <C-s> (vertical split) are missing on purpose: `p`
      -- and `s` are not in vscode-neovim.ctrlKeysForNormalMode, so those chords
      -- are answered by VS Code and never reach nvim. oil.code binds ctrl+p
      -- itself, and ctrl+s is in vscode/keybindings.json.
      map("`", "oil-code.cd", "Change the working directory to this one")
      map("gd", "oil-code.toggleDetails", "Toggle the detail columns")
      map("g?", "oil-code.help", "Show the oil keymaps")
    end,
  })
end

local function setup_keymaps()
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
  end

  -- ── Splits and panes ──────────────────────────────────────────────────────
  -- smart-splits.nvim's job outside VS Code. `navigate*` crosses workbench
  -- parts as well as editor groups, which is the closest the host has to "move
  -- one window over, and keep going past the edge of the editor".
  map({ "n", "x" }, "<C-h>", action("workbench.action.navigateLeft"), "Go to left split or pane")
  map({ "n", "x" }, "<C-j>", action("workbench.action.navigateDown"), "Go to below split or pane")
  map({ "n", "x" }, "<C-k>", action("workbench.action.navigateUp"), "Go to above split or pane")
  map({ "n", "x" }, "<C-l>", action("workbench.action.navigateRight"), "Go to right split or pane")

  -- The extension maps the rest of the <C-w> family onto VS Code's window
  -- commands, but a side-by-side diff is a single editor group, so none of them
  -- can cross it. <C-w>d is free (its vim meaning, "split and go to definition",
  -- is <C-w>gd here) and takes that job.
  map({ "n", "x" }, "<C-w>d", action("workbench.action.compareEditor.focusOtherSide"), "Focus the other diff side")

  map("n", "<leader><leader>", function()
    vscode.action("workbench.action.closeSidebar")
    vscode.action("workbench.action.closePanel")
    vscode.action("workbench.action.closeAuxiliaryBar")
  end, "Close every side bar and panel")

  -- ── LSP navigation ────────────────────────────────────────────────────────
  -- `gd` and `K` already do what this config wants, so they stay with the
  -- extension. The rest of the `g` family peeks by default there, and is pulled
  -- back onto the jumping variants fzf-lua gives these keys outside VS Code.
  map("n", "gD", action("editor.action.revealDeclaration"), "Go to declaration")
  map("n", "gi", action("editor.action.goToImplementation"), "Go to implementation")
  map("n", "go", action("editor.action.goToTypeDefinition"), "Go to definition of the type")
  map("n", "gr", action("editor.action.goToReferences"), "Go to references")

  map("n", "<leader>rn", action("editor.action.rename"), "Rename symbol")
  map({ "n", "x" }, "<leader>rm", insert_action("editor.action.refactor"), "Refactor")
  map("n", "<leader>va", action("editor.action.quickFix"), "View LSP code actions")
  map("x", "<leader>va", insert_action("editor.action.quickFix"), "View LSP code actions")

  -- ── Formatting ────────────────────────────────────────────────────────────
  -- Two keys onto one command on purpose: outside VS Code `<leader>ff` runs
  -- conform and `<leader>fl` the language server, and the host draws no such
  -- line.
  map("n", "<leader>ff", action("editor.action.formatDocument"), "Format buffer")
  map("x", "<leader>ff", action("editor.action.formatSelection"), "Format selection")
  map("n", "<leader>fl", action("editor.action.formatDocument"), "Format document using LSP")
  map("x", "<leader>fl", action("editor.action.formatSelection"), "Format selection using LSP")

  -- ── Diagnostics ───────────────────────────────────────────────────────────
  -- VS Code folds diagnostics into the hover, so there is no separate float to
  -- open. Jumping stays inside the file, to match `vim.diagnostic.jump`.
  map("n", "<leader>vd", action("editor.action.showHover"), "View diagnostic")
  map("n", "<leader>dk", action("editor.action.marker.prev"), "Previous diagnostic")
  map("n", "<leader>dj", action("editor.action.marker.next"), "Next diagnostic")
  map("n", "<leader>q", action("workbench.actions.view.problems"), "Toggle problems")

  -- ── Pickers ───────────────────────────────────────────────────────────────
  -- fzf-lua's keys, answered by the quick open widget. `sf` and `si` land on
  -- the same picker because quick open already honours .gitignore.
  map("n", "<leader>sf", action("workbench.action.quickOpen"), "Search files")
  map("n", "<leader>si", action("workbench.action.quickOpen"), "Search git files")
  map("n", "<leader>sr", action("workbench.action.openRecent"), "Search recent files")
  map("n", "<leader>sg", action("workbench.action.findInFiles"), "Search by grep")
  map("n", "<leader>sb", action("workbench.action.showAllEditorsByMostRecentlyUsed"), "Search buffers")
  map("n", "<leader>so", action("workbench.action.showAllSymbols"), "Search workspace symbols")

  map("n", "<leader>sw", function()
    find_in_files(vim.fn.expand("<cword>"))
  end, "Search current word")
  map("x", "<leader>sw", function()
    find_in_files(selection())
  end, "Search current selection")

  -- ── Diagnostic and symbol lists ───────────────────────────────────────────
  -- trouble.nvim's keys. The problems view has no per-buffer mode, so `xX`
  -- focuses it for its own filter box rather than pretending to scope itself.
  map("n", "<leader>xx", action("workbench.actions.view.problems"), "Diagnostics (Problems)")
  map("n", "<leader>xX", action("workbench.panel.markers.view.focus"), "Focus problems to filter them")
  map("n", "<leader>cs", action("outline.focus"), "Symbols (Outline)")
  map("n", "<leader>cl", action("references-view.findReferences"), "LSP references (References view)")

  -- ── Git ───────────────────────────────────────────────────────────────────
  -- neogit maps onto the built-in Source Control view: the extension already
  -- makes its tree vim-navigable, and vscode/keybindings.json adds the verbs, so
  -- it reaches the same status -> stage -> commit loop without a git extension
  -- of its own. The gitsigns hunk verbs map onto the SCM "selected ranges"
  -- commands, which fall back to the hunk under the cursor when nothing is
  -- selected, so hunk staging stays in the editor where neogit also allows it.
  map("n", "<leader>gg", action("workbench.view.scm"), "Git status open")
  map("n", "<leader>gd", action("git.openChange"), "Git diff open")
  -- VS Code has no file-history view of its own; the Timeline is where the git
  -- extension publishes a file's commits, and it already follows the active editor.
  map("n", "<leader>gh", action("timeline.focus"), "Git file history (current buffer)")
  map("n", "<leader>gb", action("git.blame.toggleEditorDecoration"), "Show git blame")
  map({ "n", "x" }, "<leader>gs", action("git.stageSelectedRanges"), "Stage hunk")
  map({ "n", "x" }, "<leader>gx", action("git.revertSelectedRanges"), "Reset hunk")
  map("n", "<leader>gS", action("git.stage"), "Stage buffer")
  map("n", "<leader>gX", action("git.clean"), "Reset buffer")

  -- ── Files ─────────────────────────────────────────────────────────────────
  map("n", "<leader>e", action("workbench.files.action.focusFilesExplorer"), "Open the file tree")

  -- ── Help ──────────────────────────────────────────────────────────────────
  map("n", "<leader>?", action("workbench.action.openGlobalKeybindings"), "Keymaps")
end

function M.setup()
  -- Route `vim.notify` -- and everything built on it, such as the yank-location
  -- maps -- through VS Code's notifications instead of the hidden message area.
  vim.notify = vscode.notify

  -- Under WSL the Windows clipboard is not reachable from the Linux nvim, so
  -- the extension offers to proxy `"+`/`"*` through VS Code instead.
  if vim.env.WSL_DISTRO_NAME and vim.g.vscode_clipboard then
    vim.g.clipboard = vim.g.vscode_clipboard
  end

  clear_default_lsp_maps()
  setup_keymaps()
  setup_oil()
end

return M
