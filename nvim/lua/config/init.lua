require("config.set")
require("config.keymaps").vanilla()
require("config.encoding").setup()

-- Inside VS Code the host owns the UI, the language servers, completion and the
-- pickers, so `config.vscode` re-points the keys that drove those onto VS Code
-- commands. It runs before lazy so that plugins still loaded there (surround,
-- and nothing else so far) keep the last word on their own keys.
if vim.g.vscode then
  require("config.vscode").setup()
end

require("config.lazy")
