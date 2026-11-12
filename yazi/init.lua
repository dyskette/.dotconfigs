require("session"):setup({
  sync_yanked = true,
})

-- Borders around all three panes, square like nvim's and lazygit's.
require("full-border"):setup({
  type = ui.Border.PLAIN,
})

-- MIME types from the file name instead of reading each file with `file`:
-- on Windows that is one file.exe per entry. Names it does not know still go
-- to `file`, so rules that match on MIME keep working for them.
require("mime-ext.local"):setup({
  fallback_file1 = true,
})
require("mime-ext"):setup()

-- `l` and Enter open every selected file, not only the hovered one.
require("smart-enter"):setup({
  open_multi = true,
})

-- Per-file git status, rendered by the fetchers registered in yazi.toml.
-- `order` is the Linemode:children_add priority, deciding where the sign sits
-- relative to other linemode children; 1500 is the plugin's own default.
require("git"):setup({
  order = 1500,
})

-- Diagnostic counts pushed in from Neovim over DDS. Renders to the right of
-- the git sign, so `order` sits above git.yazi's 1500.
require("nvim-diag"):setup({
  order = 1600,
})
