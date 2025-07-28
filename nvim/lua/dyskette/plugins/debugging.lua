local utils = require("dyskette.utils")

local dap_config = function()
  local dap = require("dap")
  local dapui = require("dapui")

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
end

return {
  "mfussenegger/nvim-dap",
  config = dap_config,
  cmd = { "DapNew", "DapContinue", "DapShowLog", "DapSetLogLevel", "DapToggleBreakpoint", "DapClearBreakpoints" },
  keys = require("dyskette.keymaps").dap,
  init = function()
    vim.fn.sign_define("DapBreakpoint", { text = "󰐱", texthl = "Debug", linehl = "", numhl = "" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "󱓓", texthl = "Debug", linehl = "", numhl = "" })
    vim.fn.sign_define("DapLogPoint", { text = "󰩦", texthl = "Debug", linehl = "", numhl = "" })
    vim.fn.sign_define("DapStopped", { text = "", texthl = "Debug", linehl = "", numhl = "" })
    vim.fn.sign_define("DapBreakpointRejected", { text = "󱓒", texthl = "Debug", linehl = "", numhl = "" })
  end,
  dependencies = {
    -- Async library
    { "nvim-neotest/nvim-nio" },

    -- UI for debugging
    { "rcarriga/nvim-dap-ui", opts = {} },

    -- Virtual text with variable values while debugging
    {
      "theHamsta/nvim-dap-virtual-text",
      opts = {},
      dependencies = { "nvim-treesitter/nvim-treesitter" },
    },

    -- Adapt mason to dap to download debuggers
    {
      "jay-babu/mason-nvim-dap.nvim",
      opts = {},
      dependencies = {
        { "mason.nvim" },
      },
    },

    -- Run pre and post tasks (e.g. building, cleaning)
    {
      "stevearc/overseer.nvim",
      opts = {},
    },
  },
}
