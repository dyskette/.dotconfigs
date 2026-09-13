--- User-tunable settings for the workflow system.
---
--- Everything a person is expected to edit lives here; the other wf_* modules
--- read from this table so day-to-day tuning never means touching logic.

local M = {}

--- WSL distribution hosting the development environment on Windows.
M.wsl_distro = "Ubuntu-24.04"

--- Roots scanned for git repositories, in WSL/Linux path terms.
--- Paths that do not exist are skipped silently.
M.repo_roots = { "~/code", "~/work", "~/dev" }

--- Maximum directory depth of the repository scan.
M.scan_depth = 4

--- Per-project notes live at <notes_root>/<client>/<repo>.md
M.notes_root = "~/notes"

--- Command launched in the left pane of the "agent" tab.
M.agent_cmd = "claude"

--- Editor used by the "edit" and "notes" tabs.
M.editor = "nvim"

--- The leader key.
---
--- Ctrl+b rather than the ergonomically nicer Ctrl+Space, for two reasons
--- specific to this machine:
---   - Ctrl+Space is the Japanese IME input toggle on Windows, and the
---     Japanese layout (00000411) is installed here, so Windows can swallow
---     the key before WezTerm ever sees it.
---   - Ctrl+a is the tmux prefix (tmux/tmux.conf), and the local multiplexer
---     must not collide with the remote one.
--- The cost is readline backward-char and Neovim's page-up, both of which have
--- arrow and PageUp equivalents. Change these two fields to move the leader.
M.leader = { key = "b", mods = "CTRL" }

--- Leader arm time: long enough to think, short enough not to eat a keystroke.
M.leader_timeout_ms = 1500

--- Pane resize step, in cells.
M.resize_step = 3

--- Latin American ISO keyboard (Windows KLID 0000080a, xkb `latam(basic)`).
---
--- Relevant key costs, read from /usr/share/X11/xkb/symbols/latam, where the
--- four columns are [plain, shift, altgr, shift+altgr]:
---
---   <TLDE>  |  °  ¬      → "|" is UNSHIFTED, left of 1
---   <AE11>  '  ?  \      → "\" needs AltGr; "?" is Shift
---   <AC11>  {  [  ^      → "{" is UNSHIFTED, "[" is Shift
---   <BKSL>  }  ]  `      → "}" is UNSHIFTED, "]" is Shift
---   <AD12>  +  *  ~      → "+" is UNSHIFTED
---   <AE07>  7  /         → "/" is Shift+7
---   <AE10>  0  =         → "=" is Shift+0
---   <LSGT>  <  >  \      → the extra ISO key left of Z
---
--- Consequences encoded in the keymap:
---   - "\" is a poor split key here, so "|" is the primary one.
---   - "{" and "}" being unshifted makes the prompt-jump keys cheaper than
---     the tab keys, which is the opposite of a US layout but works out: both
---     pairs sit on the same two physical keys.
---   - "+" is an unshifted alias for the "=" rebalance.
M.latam_layout = true

--- Split proportions of the template tabs, as the fraction given to the
--- primary pane. Read both when a workspace is built and when panes are
--- rebalanced, so the two can never drift apart.
M.template_splits = {
  run = { direction = "Bottom", primary = 0.7 },
  agent = { direction = "Right", primary = 0.6 },
}

--- Shells offered by the startup picker and by LEADER Enter.
---
--- Consulting work is not all on one platform: some clients are Windows top to
--- bottom, others are mixed and covered through WSL. Rather than pick one
--- default and fight it, the choice is presented when a window opens.
---
--- `domain` names a WezTerm domain. "local" is WezTerm's built-in domain for
--- native processes; "WSL:<distro>" entries come from config.wsl_domains. The
--- name is resolved when the shell is spawned, and an unknown one reports the
--- domains that do exist rather than failing quietly.
--- `default = true` marks the shell the window already runs, so choosing it at
--- startup costs nothing.
M.shells_windows = {
  { label = "WSL · Ubuntu-24.04", short = "wsl", domain = "WSL:Ubuntu-24.04", default = true },
  { label = "PowerShell 7", short = "pwsh", domain = "local", args = { "pwsh.exe", "-NoLogo" } },
  { label = "Windows PowerShell", short = "posh", domain = "local", args = { "powershell.exe", "-NoLogo" } },
  { label = "Command Prompt", short = "cmd", domain = "local", args = { "cmd.exe" } },
  { label = "Git Bash", short = "git-bash", domain = "local", args = { "C:\\Program Files\\Git\\bin\\bash.exe", "-i", "-l" } },
}

M.shells_unix = {
  -- Toolbox is marked default because config.default_prog starts it, so
  -- choosing it at the startup picker is correctly a no-op.
  { label = "Toolbox", short = "toolbox", default = true },
  { label = "Login shell", short = "bash", args = { "bash", "-l" } },
}

--- Show the shell picker when a window opens. Escape keeps the default shell.
--- Set to false to go straight to the default and use LEADER Enter instead.
M.startup_shell_picker = true

--- Special workspaces. The "@" prefix sorts them to the top of every picker.
M.notes_workspace = "@notes"
M.scratch_workspace = "@scratch"

--- Lua patterns matched case-insensitively against a pane's cwd and title to
--- flag production context. Deliberately broad: a false positive costs a red
--- frame, a false negative costs an incident.
M.prod_patterns = { "prod", "%-prd", "%-prod", "live" }

--- Accent palettes, indexed deterministically by client name.
---
--- A given client keeps the same slot forever, so identity is stable across
--- restarts and machines. There is one palette per appearance and the entries
--- line up by hue, so a client reads as "the blue one" in both: the colour is
--- drawn from the active theme rather than imposed on it, which is what keeps
--- the tab bar from looking like a warning label.
M.client_colors_dark = {
  "#458588", -- blue
  "#d79921", -- gold
  "#689d6a", -- teal
  "#b16286", -- purple
  "#cc241d", -- red
  "#d65d0e", -- orange
  "#98971a", -- green
  "#83a598", -- sky
}

M.client_colors_light = {
  "#286983", -- pine
  "#ea9d34", -- gold
  "#56949f", -- foam
  "#907aa9", -- iris
  "#b4637a", -- love
  "#d7827e", -- rose
  "#5b7a6a", -- sage
  "#6e6a86", -- slate
}

--- Frame colour for a workspace that looks like production. Overrides the
--- client accent, and is the only thing that recolours the whole bar, so the
--- alarm cannot be confused with ordinary client colouring.
M.prod_color_dark = "#cc241d"
M.prod_color_light = "#b4232a"

--- QuickSelect patterns beyond WezTerm's defaults (URLs, paths, hashes).
--- Tuned for consulting work: ticket keys, file:line, k8s and cloud IDs.
M.quick_select_patterns = {
  "[A-Z][A-Z0-9]{1,9}-\\d+",                 -- JIRA / Azure DevOps ticket keys
  "[\\w./-]+:\\d+(:\\d+)?",                  -- file:line:col from compilers
  "v?\\d+\\.\\d+\\.\\d+(-[\\w.]+)?",         -- semver
  "[a-z0-9-]+-[a-f0-9]{8,10}-[a-z0-9]{5}",   -- kubernetes pod names
  "[0-9a-f]{12,64}",                         -- container / image IDs
  "[A-Z][A-Z0-9_]{3,}",                      -- environment variable names
  "[\\w.+-]+@[\\w-]+\\.[\\w.]+",             -- email addresses
  "/subscriptions/[0-9a-f-]+/[\\w/.-]+",     -- Azure resource IDs
  "arn:aws:[\\w-]+:[\\w-]*:\\d*:[\\w/:-]+",  -- AWS ARNs
}

return M
