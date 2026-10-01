local utils = require("config.utils")

-- Remove Neovim 0.11+ default LSP keymaps that conflict with custom mappings
-- These are global mappings, not buffer-local, so we delete them once at startup.
-- Runs from the spec's `init` rather than at file scope, so that importing this
-- file inside VS Code changes nothing. lazy.nvim runs `init` even for specs its
-- `cond` disabled, so the guard has to live here rather than on the spec:
-- `config.vscode` has already dropped these by the time this would run, and
-- `vim.keymap.del` throws on a mapping that is no longer there.
local function clear_default_lsp_keymaps()
  if vim.g.vscode then
    return
  end

  vim.keymap.del("n", "grn")
  vim.keymap.del("n", "gra")
  vim.keymap.del("x", "gra")
  vim.keymap.del("n", "grx")
  vim.keymap.del("n", "grr")
  vim.keymap.del("n", "gri")
  vim.keymap.del("n", "grt")
  vim.keymap.del("n", "gO")
end

-- Configure global LSP settings that apply to all language servers
local function setup_global_lsp_config()
  -- Set default configuration for all LSP clients
  -- This uses the new vim.lsp.config() API with the '*' wildcard
  -- Completion capabilities are not set here: blink.cmp (a dependency, so
  -- loaded first) registers them on "*" from its own plugin/ file.
  vim.lsp.config("*", {
    -- Client behavior flags
    flags = {
      -- Reduce debounce for faster responsiveness
      debounce_text_changes = 150, -- milliseconds
    },

    -- Position encoding for LSP communication (fixes position_encoding warnings)
    offset_encoding = "utf-16",

    -- Default root directory markers for workspace detection
    -- Nested lists indicate equal priority
    root_markers = { ".git", ".gitignore" },
  })
end

-- Handler called when an LSP client attaches to a buffer
-- This is where we configure buffer-local LSP behavior
local function on_lsp_attach()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("dyskette_lsp_attach", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client then
        return
      end

      -- Disable semantic tokens from LSP servers
      -- Let Treesitter handle syntax highlighting for better performance
      client.server_capabilities.semanticTokensProvider = nil

      -- Ruff and basedpyright both attach to python buffers. Ruff has nothing
      -- to say on hover that the type checker does not say better, and two
      -- providers means two popups, so it yields.
      if client.name == "ruff" then
        client.server_capabilities.hoverProvider = false
      end

      -- Browser preview, on demand only (mpls runs with --no-auto).
      if client.name == "mpls" then
        vim.keymap.set("n", "<leader>mp", "<cmd>LspMplsOpenPreview<cr>", {
          buffer = args.buf,
          desc = "Open markdown preview in the browser",
        })
      end
    end,
  })
end

-- Configure individual language servers using the modern vim.lsp.config() API
local function setup_language_servers()
  -- Scripting Languages
  -- ==================

  -- Lua Language Server
  vim.lsp.config.lua_ls = {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_markers = { ".luarc.json", ".luarc.jsonc", ".stylua.toml" },
  }

  -- Bash Language Server
  vim.lsp.config.bashls = {
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash" },
    root_markers = { ".git" },
  }

  -- PowerShell Editor Services
  vim.lsp.config.powershell_es = {
    bundle_path = vim.fn.expand("$MASON/packages/powershell-editor-services/PowerShellEditorServices"),
    cmd = {
      "pwsh",
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      vim.fn.expand("$MASON/packages/powershell-editor-services/PowerShellEditorServices/Start-EditorServices.ps1"),
      "-HostName",
      "nvim",
      "-HostProfileId",
      "0",
      "-HostVersion",
      "1.0.0",
      "-LogLevel",
      "Warning",
      "-Stdio",
    },
    filetypes = { "ps1", "psm1", "psd1" },
    root_markers = { ".git" },
    settings = {
      powershell = {
        codeFormatting = { preset = "OTBS" },
      },
    },
  }

  -- Python Language Servers
  --
  -- basedpyright rather than pyright because it resolves a `.venv` at the
  -- project root by itself. No shell activation, no pythonPath wiring, and the
  -- result is the same whether Neovim was started from an activated shell or
  -- not -- which plain pyright is not, since it falls back to whatever python
  -- is on PATH. That only holds if the root it picks is the repository, hence
  -- the marker list ending in .git.
  --
  -- typeCheckingMode is pinned to "standard" to match what pyright reported.
  -- basedpyright's own default is "recommended", which is considerably
  -- stricter and would light up existing code on day one. Raise it when you
  -- want to, per project or here.
  --
  -- cmd, filetypes and the rest of the settings come from nvim-lspconfig's
  -- lsp/basedpyright.lua; this only adds to them.
  vim.lsp.config("basedpyright", {
    -- Replaces nvim-lspconfig's list rather than extending it: its markers
    -- plus .venv, so a uv project without a pyproject.toml still roots there.
    root_markers = {
      "pyrightconfig.json",
      "pyproject.toml",
      "setup.py",
      "setup.cfg",
      "requirements.txt",
      "Pipfile",
      ".venv",
      ".git",
    },
    settings = {
      basedpyright = {
        -- Ruff sorts imports (its code action, and conform's
        -- ruff_organize_imports on format), so only one organize-imports
        -- action is offered.
        disableOrganizeImports = true,
        analysis = {
          typeCheckingMode = "standard",
        },
      },
    },
  })

  -- Ruff supplies the diagnostics pylint used to, and the formatting isort and
  -- black used to. It matters here that it is a single static binary: pylint
  -- had to be installed into each project's virtual environment to be found on
  -- PATH, which is why linting only worked in a shell that had activated one.
  -- nvim-lspconfig's lsp/ruff.lua is used as is.
  --
  -- Both servers attach to python buffers. on_lsp_attach drops ruff's hover so
  -- the type checker answers it alone.

  -- Markdown
  -- ========

  -- Markdown Preview Language Server: a live browser preview with mermaid,
  -- images, tables and math. nvim-lspconfig's lsp/mpls.lua already passes
  -- --no-auto (without it the browser opens for every markdown file) and
  -- defines :LspMplsOpenPreview; only the theme is set here, to match the
  -- current background when the server starts.
  vim.lsp.config("mpls", {
    cmd = { "mpls", "--theme", vim.o.background, "--enable-emoji", "--enable-footnotes", "--no-auto" },
  })

  -- JavaScript/TypeScript
  -- ====================

  -- VTSLS - Modern TypeScript Language Server with Vue support
  vim.lsp.config.vtsls = {
    cmd = { "vtsls", "--stdio" },
    filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue" },
    root_markers = { "tsconfig.json", "package.json", "jsconfig.json", ".git" },
    settings = {
      vtsls = {
        tsserver = {
          globalPlugins = {
            {
              name = "@vue/typescript-plugin",
              location = vim.fn.expand("$MASON/packages/vue-language-server/node_modules/@vue/language-server"),
              languages = { "vue" },
              configNamespace = "typescript",
            },
          },
        },
      },
    },
  }
  -- ESLint Language Server
  vim.lsp.config.eslint = {
    cmd = { "vscode-eslint-language-server", "--stdio" },
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
    root_markers = { ".eslintrc.js", ".eslintrc.json", "eslint.config.js" },
  }

  -- Vue Language Server (using vue_ls instead of deprecated volar)
  vim.lsp.config.vue_ls = {
    cmd = { "vue-language-server", "--stdio" },
    filetypes = { "vue" },
    root_markers = { "package.json", "vue.config.js", "nuxt.config.js" },
    init_options = {
      typescript = {
        -- Path to TypeScript SDK for Vue TypeScript support
        tsdk = vim.fn.expand("$MASON/packages/typescript-language-server/node_modules/typescript/lib"),
      },
    },
  }

  -- Web Technologies
  -- ===============

  -- HTML Language Server
  vim.lsp.config.html = {
    cmd = { "vscode-html-language-server", "--stdio" },
    filetypes = { "html", "templ" },
    root_markers = { "package.json", ".git" },
  }

  -- CSS Language Server
  vim.lsp.config.cssls = {
    cmd = { "vscode-css-language-server", "--stdio" },
    filetypes = { "css", "scss", "less" },
    root_markers = { "package.json", ".git" },
  }

  -- JSON Language Server with schema support
  vim.lsp.config.jsonls = {
    cmd = { "vscode-json-language-server", "--stdio" },
    filetypes = { "json", "jsonc" },
    root_markers = { "package.json", ".git" },
    settings = {
      json = {
        validate = { enable = true },
      },
    },
    -- The schema catalog is resolved when the server starts, not at startup.
    before_init = function(_, config)
      -- Use external schema store for better JSON validation
      config.settings.json.schemas = require("schemastore").json.schemas()
    end,
  }

  -- YAML Language Server with schema support
  vim.lsp.config.yamlls = {
    cmd = { "yaml-language-server", "--stdio" },
    filetypes = { "yaml", "yml" },
    root_markers = { ".git" },
    settings = {
      yaml = {
        schemaStore = {
          -- Disable built-in schema store in favor of external one
          enable = false,
          url = "",
        },
      },
    },
    -- The schema catalog is resolved when the server starts, not at startup.
    before_init = function(_, config)
      -- Use external schema store for better YAML validation
      config.settings.yaml.schemas = require("schemastore").yaml.schemas()
    end,
  }

  -- XML Language Server
  vim.lsp.config.lemminx = {
    cmd = { "lemminx" },
    filetypes = { "xml", "xsd", "xsl", "xslt", "svg" },
    root_markers = { ".git" },
  }

  -- TOML Language Server
  vim.lsp.config.taplo = {
    cmd = { "taplo", "lsp", "stdio" },
    filetypes = { "toml" },
    root_markers = { ".git" },
  }

  -- Other Languages
  -- ==============

  -- Dart Language Server
  vim.lsp.config.dartls = {
    cmd = { "dart", "language-server", "--protocol=lsp" },
    filetypes = { "dart" },
    root_markers = { "pubspec.yaml" },
  }

  -- Rust Analyzer
  vim.lsp.config.rust_analyzer = {
    cmd = { "rust-analyzer" },
    filetypes = { "rust" },
    root_markers = { "Cargo.toml", "rust-project.json" },
  }
end

-- Enable language servers dynamically based on file type
local function enable_language_servers()
  -- Track which servers have already been enabled
  local enabled_servers = {}
  local group = vim.api.nvim_create_augroup("dyskette_lsp_filetype", { clear = true })

  local function enable_for(ft)
    local server_map = {
      lua = "lua_ls",
      sh = "bashls",
      bash = "bashls",
      ps1 = "powershell_es",
      python = { "basedpyright", "ruff" },
      javascript = "vtsls",
      typescript = "vtsls",
      javascriptreact = "vtsls",
      typescriptreact = "vtsls",
      vue = { "vtsls", "vue_ls" },
      html = "html",
      css = "cssls",
      scss = "cssls",
      less = "cssls",
      json = "jsonls",
      jsonc = "jsonls",
      yaml = "yamlls",
      yml = "yamlls",
      xml = "lemminx",
      toml = "taplo",
      markdown = "mpls",
      dart = "dartls",
      rust = "rust_analyzer",
      -- cs and razor: roslyn.nvim enables its server itself.
    }

    local servers = server_map[ft]
    if servers then
      if type(servers) == "table" then
        for _, server in ipairs(servers) do
          if not enabled_servers[server] then
            vim.lsp.enable(server)
            enabled_servers[server] = true
          end
        end
      else
        if not enabled_servers[servers] then
          vim.lsp.enable(servers)
          enabled_servers[servers] = true
        end
      end

      -- Also enable eslint for JS/TS files
      if
        ft == "javascript"
        or ft == "typescript"
        or ft == "javascriptreact"
        or ft == "typescriptreact"
        or ft == "vue"
      then
        if not enabled_servers["eslint"] then
          vim.lsp.enable("eslint")
          enabled_servers["eslint"] = true
        end
      end
    end
  end

  vim.api.nvim_create_autocmd("FileType", {
    desc = "Enable LSP servers per filetype",
    group = group,
    callback = function(args)
      enable_for(args.match)
    end,
  })

  -- The plugin loads on LazyFile, after the FileType event of the buffer that
  -- triggered it (or of files opened from the command line) has already
  -- fired. vim.lsp.enable() re-runs FileType for existing buffers itself, so
  -- enabling is enough.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
      enable_for(vim.bo[buf].filetype)
    end
  end
end

-- Main function that sets up the entire LSP configuration
local function lsp_config()
  setup_global_lsp_config()
  on_lsp_attach()
  setup_language_servers()
  enable_language_servers()
end

-- C# and Razor through roslyn.nvim. Razor is co-hosted by the Roslyn server
-- itself, so there is no separate Razor server or plugin.
--
-- Only settings are configured here. They merge onto the plugin's own
-- lsp/roslyn.lua, which supplies the command (the Mason binary, in daemon
-- mode, tied to this nvim's process id), the filetypes and solution-based
-- root detection, and the plugin enables the server itself.
local roslyn_settings = {
  ["csharp|inlay_hints"] = {
    csharp_enable_inlay_hints_for_implicit_object_creation = true,
    csharp_enable_inlay_hints_for_implicit_variable_types = true,
    csharp_enable_inlay_hints_for_lambda_parameter_types = true,
    csharp_enable_inlay_hints_for_types = true,
    dotnet_enable_inlay_hints_for_indexer_parameters = true,
    dotnet_enable_inlay_hints_for_literal_parameters = true,
    dotnet_enable_inlay_hints_for_object_creation_parameters = true,
    dotnet_enable_inlay_hints_for_other_parameters = true,
    dotnet_enable_inlay_hints_for_parameters = true,
    dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
    dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
    dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
  },
  ["csharp|code_lens"] = {
    dotnet_enable_references_code_lens = true,
    dotnet_enable_tests_code_lens = true,
  },
  ["csharp|background_analysis"] = {
    -- "openFiles" is much lighter if large solutions feel slow.
    dotnet_analyzer_diagnostics_scope = "fullSolution",
    dotnet_compiler_diagnostics_scope = "fullSolution",
  },
  ["csharp|completion"] = {
    dotnet_provide_regex_completions = true,
    dotnet_show_completion_items_from_unimported_namespaces = true,
    dotnet_show_name_completion_suggestions = true,
  },
  ["csharp|symbol_search"] = {
    dotnet_search_reference_assemblies = true,
  },
}

-- Runs at startup, before the plugin loads on its filetypes.
local function roslyn_init()
  -- lazy.nvim runs `init` even for specs its `cond` disabled.
  if vim.g.vscode then
    return
  end

  -- The plugin is loaded by these filetypes, so it cannot be what detects them.
  vim.filetype.add({
    extension = {
      razor = "razor",
      cshtml = "razor",
    },
  })

  -- Registered before the plugin loads: its plugin/ file enables the server
  -- as it loads, so settings added any later would miss the first client.
  vim.lsp.config("roslyn", { settings = roslyn_settings })
end

return {
  -- Main LSP configuration plugin
  {
    "neovim/nvim-lspconfig",
    cond = not vim.g.vscode,
    -- Never before the first screen: servers take far longer to initialise
    -- than this delay, and enable_language_servers() catches up on open
    -- buffers.
    event = utils.events.LazyFile,
    init = clear_default_lsp_keymaps,
    config = lsp_config,
    dependencies = {
      -- Mason for automatic LSP server installation
      { "williamboman/mason.nvim" },

      -- Blink completion engine
      { "saghen/blink.cmp" },

      -- Enhanced Lua development with proper LSP setup
      {
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
          library = {
            -- Load luvit types when vim.uv is detected
            { path = "luvit-meta/library", words = { "vim%.uv" } },
          },
        },
        dependencies = {
          -- Luvit meta types for vim.uv
          { "Bilal2453/luvit-meta", lazy = true },
        },
      },

      -- JSON and YAML schema support
      { "b0o/schemastore.nvim", lazy = true },
    },
  },

  -- C# Roslyn language server
  {
    "seblyng/roslyn.nvim",
    cond = not vim.g.vscode,
    -- Only load for C# and Razor files
    ft = { "cs", "razor" },
    opts = {
      broad_search = true,
      lock_target = true,
    },
    init = roslyn_init,
  },
}
