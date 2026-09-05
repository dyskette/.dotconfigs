require("session"):setup({
  sync_yanked = true,
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
