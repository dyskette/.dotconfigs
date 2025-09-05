local utils = require("config.utils")

-- Configure global LSP settings that apply to all language servers
local function setup_global_lsp_config()
  -- Set default configuration for all LSP clients
  -- This uses the new vim.lsp.config() API with the '*' wildcard
  vim.lsp.config("*", {
    -- LSP client capabilities (what the editor can do)
    capabilities = require("blink.cmp").get_lsp_capabilities(),

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

  -- Python Language Server
  vim.lsp.config.pyright = {
    cmd = { "pyright-langserver", "--stdio" },
    filetypes = { "python" },
    root_markers = { "pyproject.toml", "setup.py", "requirements.txt" },
  }

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
        -- Use external schema store for better JSON validation
        schemas = require("schemastore").json.schemas(),
        validate = { enable = true },
      },
    },
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
        -- Use external schema store for better YAML validation
        schemas = require("schemastore").yaml.schemas(),
      },
    },
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

  vim.api.nvim_create_autocmd("FileType", {
    desc = "Enable LSP servers per filetype",
    group = group,
    callback = function(args)
      local ft = args.match
      local server_map = {
        lua = "lua_ls",
        sh = "bashls",
        bash = "bashls",
        ps1 = "powershell_es",
        python = "pyright",
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
        dart = "dartls",
        rust = "rust_analyzer",
        cs = "roslyn",
        razor = "roslyn",
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
    end,
  })
end

-- Main function that sets up the entire LSP configuration
local function lsp_config()
  setup_global_lsp_config()
  on_lsp_attach()
  setup_language_servers()
  enable_language_servers()
end

-- Configuration for C# development using Roslyn language server
local roslyn_config = function(_, opts)
  require("roslyn").setup(opts)

  -- Configure Razor support paths
  local rzls_path = vim.fn.expand("$MASON/packages/rzls/libexec")
  local cmd = {
    "roslyn",
    "--stdio",
    "--logLevel=Information",
    "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
    "--razorSourceGenerator=" .. vim.fs.joinpath(rzls_path, "Microsoft.CodeAnalysis.Razor.Compiler.dll"),
    "--razorDesignTimePath=" .. vim.fs.joinpath(rzls_path, "Targets", "Microsoft.NET.Sdk.Razor.DesignTime.targets"),
    "--extension",
    vim.fs.joinpath(rzls_path, "RazorExtension", "Microsoft.VisualStudioCode.RazorExtension.dll"),
  }

  -- Configure Roslyn using modern vim.lsp.config() API
  vim.lsp.config.roslyn = {
    cmd = cmd,
    filetypes = { "cs" },
    root_markers = { "*.sln", "*.csproj", "omnisharp.json" },
    handlers = require("rzls.roslyn_handlers"),
  }

  vim.lsp.enable("roslyn")
end

-- Initialize Razor file type detection
local function roslyn_init()
  vim.filetype.add({
    extension = {
      razor = "razor",
      cshtml = "razor",
    },
  })
end

return {
  -- Main LSP configuration plugin
  {
    "neovim/nvim-lspconfig",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
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
    -- Only load for C# and Razor files
    ft = { "cs", "razor" },
    opts = {
      broad_search = true,
      lock_target = true,
    },
    config = roslyn_config,
    init = roslyn_init,
    dependencies = {
      -- Razor LSP support
      { "tris203/rzls.nvim", config = true },
    },
  },
}
