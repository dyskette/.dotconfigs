local fzf_opts = function()
  local fzf = require("fzf-lua")

  return {
    fzf_opts = {
      ["--cycle"] = true,
    },
    -- winopts = { preview = { default = "bat" } },
    oldfiles = { cwd_only = true, include_current_session = true },
    files = {
      actions = { ["ctrl-q"] = { fn = fzf.actions.file_sel_to_qf, prefix = "select-all" } },
    },
    grep = {
      actions = { ["ctrl-q"] = { fn = fzf.actions.file_sel_to_qf, prefix = "select-all" } },
    },
  }
end

local fzf_lua_config = function(_, opts)
  local fzf = require("fzf-lua")

  fzf.setup(opts)
  fzf.register_ui_select()
end

return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = require("dyskette.keymaps").fzf,
  opts = fzf_opts,
  config = fzf_lua_config,
}
