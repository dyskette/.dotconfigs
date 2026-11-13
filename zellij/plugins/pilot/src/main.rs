//! pilot: a headless Zellij plugin that makes the editor and the agent feel
//! like one workspace.
//!
//! It is loaded in the background (`load_plugins` in config.kdl) and driven by
//! keybindings through `MessagePlugin "pilot" { name "<command>"; ... }`:
//!
//! - `nav` (payload `left|right|up|down`): if the focused pane runs Neovim,
//!   the Alt+h/j/k/l key is written to it, so Neovim moves between its own
//!   windows (nvim/lua/config/zellij.lua). Neovim calls back into Zellij with
//!   `zellij action move-focus-or-tab` when it is already at its edge. Any
//!   other pane moves Zellij's focus directly, crossing into the next tab at
//!   the left and right screen edges.
//! - `nav-pane`: the same move without the Neovim check, sent by Neovim when it
//!   is at its own edge (`zellij action move-focus` from a pane has no client
//!   to move).
//! - `agent` (payload `toggle`): jumps to the pane named `agent` in the current tab, or back to
//!   the previous pane when the agent already has focus. A tab without one
//!   gets a new agent pane, started in the focused pane's directory with the
//!   command from the `agent_command` setting.
//! - `resize` (payload `left|right|up|down`): Alt+Shift+h/j/k/l. Neovim gets
//!   the key and moves its window divider; other panes move a Zellij pane
//!   divider. `resize-pane` skips the Neovim check (Neovim's fallback when
//!   it has no divider in that direction).
//! - `focus` (payload: a terminal pane id): focuses that pane for the user.
//!   `zellij action focus-pane-id` from a pane exits 0 but leaves the user's
//!   client where it was, as `switch-session` does; Neovim uses this to bring
//!   its pane forward when a file arrives and to give focus back afterwards.
//! - `switch` (payload: a KDL layout or `-`; args `session`, `tab`, `cwd`,
//!   `pane`): moves the user's client to another session, used by `zj`
//!   (powershell/Zellij.psm1). See `switch_session` for why it lives here.
//!
//! Why a plugin instead of plain keybindings: a keybinding cannot ask which
//! program a pane runs, and the plugin API answers that synchronously
//! (`get_pane_running_command`), so there is no title matching and no lag.

use std::collections::BTreeMap;
use std::path::PathBuf;

use zellij_tile::prelude::*;

/// Program names (lower case, without `.exe`) that receive the navigation key
/// instead of Zellij.
const EDITORS: &[&str] = &["nvim", "vim", "vi"];

/// Name given to agent panes; layouts use the same one (layouts/*.kdl).
const AGENT_PANE: &str = "agent";

#[derive(Default)]
struct Pilot {
    /// Panes per tab position, kept current by `PaneUpdate`.
    panes: PaneManifest,
    /// Tabs by position, kept current by `TabUpdate`: their viewport size
    /// tells which pane edges are dividers.
    tabs: Vec<TabInfo>,
    /// The agent launcher, split on whitespace (`agent_command` setting).
    agent_command: Vec<String>,
    /// Set once the user granted the permissions; commands before that would
    /// fail silently.
    ready: bool,
    /// `debug "true"`: log each decision to the Zellij log
    /// (%TEMP%\zellij\zellij-log\zellij.log on Windows).
    debug: bool,
}

impl Pilot {
    fn log(&self, message: impl FnOnce() -> String) {
        if self.debug {
            eprintln!("pilot: {}", message());
        }
    }
}

register_plugin!(Pilot);

impl ZellijPlugin for Pilot {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        self.agent_command = configuration
            .get("agent_command")
            .map(|c| c.split_whitespace().map(str::to_owned).collect())
            .unwrap_or_default();
        self.debug = configuration.get("debug").is_some_and(|v| v == "true");

        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::WriteToStdin,
            PermissionType::RunCommands,
            PermissionType::OpenTerminalsOrPlugins,
        ]);
        subscribe(&[EventType::PaneUpdate, EventType::TabUpdate, EventType::PermissionRequestResult]);
        // Headless: never take focus or space.
        set_selectable(false);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PaneUpdate(manifest) => self.panes = manifest,
            Event::TabUpdate(tabs) => self.tabs = tabs,
            Event::PermissionRequestResult(PermissionStatus::Granted) => self.ready = true,
            Event::PermissionRequestResult(PermissionStatus::Denied) => {
                eprintln!("pilot: permissions denied; navigation and agent keys are disabled");
            }
            _ => {}
        }
        false
    }

    fn pipe(&mut self, message: PipeMessage) -> bool {
        self.log(|| format!("pipe {} {:?} (ready: {})", message.name, message.payload, self.ready));
        // A CLI pipe (`zellij pipe`) ends with a message without payload;
        // every command carries one, so that one is skipped instead of
        // running the command twice.
        let (true, Some(payload)) = (self.ready, message.payload.as_deref()) else {
            return false;
        };
        match message.name.as_str() {
            "nav" | "nav-pane" => match parse_direction(payload) {
                Some(direction) => self.navigate(direction, message.name == "nav"),
                None => eprintln!("pilot: nav expects left, right, up or down, not '{payload}'"),
            },
            "agent" => self.toggle_agent(),
            "resize" | "resize-pane" => match parse_direction(payload) {
                Some(direction) => self.resize(direction, message.name == "resize"),
                None => eprintln!("pilot: resize expects left, right, up or down, not '{payload}'"),
            },
            "focus" => match payload.trim().parse::<u32>() {
                Ok(id) => focus_terminal_pane(id, false, false),
                Err(_) => eprintln!("pilot: focus expects a terminal pane id, not '{payload}'"),
            },
            "switch" => self.switch_session(&message.args, payload),
            other => eprintln!("pilot: unknown command '{other}'"),
        }
        false
    }
}

impl Pilot {
    /// Hand the key to an editor pane, or move Zellij's focus.
    fn navigate(&self, direction: Direction, editor_first: bool) {
        let focused = get_focused_pane_info();
        self.log(|| format!("nav {direction:?}, focused {focused:?}"));
        let Ok((_, pane)) = focused else {
            return;
        };

        let editor = editor_first && is_editor(pane);
        self.log(|| format!("{pane:?} runs an editor: {editor}"));
        if editor {
            // Alt+<key> in legacy encoding: ESC followed by the key. Neovim
            // reads it as <M-key> (config/zellij.lua maps those).
            write_to_pane_id(vec![0x1b, key_for(direction)], pane);
            return;
        }

        match direction {
            Direction::Left | Direction::Right => move_focus_or_tab(direction),
            Direction::Up | Direction::Down => move_focus(direction),
        }
    }

    /// Move a divider in a direction: the focused pane's right (or bottom)
    /// one when it has one, else its left (or top) one; nvim's <M-H/J/K/L>
    /// follow the same rule (nvim/lua/config/zellij.lua). With `editor_first`
    /// an nvim pane gets Alt+Shift+key instead, and calls back with
    /// `resize-pane` when it has no window divider in that direction.
    fn resize(&self, direction: Direction, editor_first: bool) {
        let Ok((tab, pane)) = get_focused_pane_info() else {
            return;
        };
        if editor_first && is_editor(pane) {
            write_to_pane_id(vec![0x1b, key_for(direction).to_ascii_uppercase()], pane);
            return;
        }

        let info = self.panes.panes.get(&tab).and_then(|panes| {
            panes.iter().find(|p| match pane {
                PaneId::Terminal(id) => !p.is_plugin && p.id == id,
                PaneId::Plugin(id) => p.is_plugin && p.id == id,
            })
        });
        let viewport = self.tabs.iter().find(|t| t.position == tab);
        let (Some(info), Some(viewport)) = (info, viewport) else {
            // Unknown geometry: Zellij's own rule for the key.
            resize_focused_pane_with_direction(Resize::Increase, direction);
            return;
        };

        let (resize, edge) = divider_move(
            direction,
            info.pane_x + info.pane_columns < viewport.viewport_columns,
            info.pane_y + info.pane_rows < viewport.viewport_rows,
        );
        self.log(|| format!("resize {direction:?}: {resize:?} {edge:?}"));
        resize_focused_pane_with_direction(resize, edge);
    }

    /// Focus the tab's agent pane, return from it, or start one.
    fn toggle_agent(&self) {
        let Ok((tab, focused)) = get_focused_pane_info() else {
            return;
        };

        let agent = self
            .panes
            .panes
            .get(&tab)
            .and_then(|panes| panes.iter().find(|p| !p.is_plugin && p.title == AGENT_PANE));

        match agent {
            Some(agent) if PaneId::Terminal(agent.id) == focused => focus_last_pane(),
            Some(agent) => focus_terminal_pane(agent.id, false, false),
            None => self.start_agent(focused),
        }
    }

    /// Move this client to another session, creating it or adding a tab to it
    /// from the layout in the payload (`-` for none).
    ///
    /// `zellij action switch-session` cannot do this from inside a pane: the
    /// server switches the client that sent the action, which for the CLI is
    /// its own short-lived connection, not the user's. A plugin instance
    /// belongs to the user's client, so `zj` sends the request here.
    ///
    /// Every client's instance gets the broadcast; only the one whose client
    /// is focused on the requesting pane (`pane` argument) acts.
    fn switch_session(&self, args: &BTreeMap<String, String>, payload: &str) {
        if let Some(origin) = args.get("pane").and_then(|p| p.parse::<u32>().ok()) {
            match get_focused_pane_info() {
                Ok((_, PaneId::Terminal(id))) if id == origin => {}
                _ => return,
            }
        }
        let Some(session) = args.get("session") else {
            eprintln!("pilot: switch needs a session argument");
            return;
        };

        let request = ConnectToSession {
            name: Some(session.clone()),
            tab_position: args.get("tab").and_then(|t| t.parse().ok()),
            layout: (payload != "-").then(|| LayoutInfo::Stringified(payload.to_owned())),
            cwd: args.get("cwd").map(PathBuf::from),
            ..Default::default()
        };
        self.log(|| format!("switch to {request:?}"));
        switch_session_with_options(request);
    }

    /// Open an agent pane next to the focused one, in the same directory.
    fn start_agent(&self, focused: PaneId) {
        let Some((program, args)) = self.agent_command.split_first() else {
            eprintln!("pilot: no agent_command configured");
            return;
        };

        let command = CommandToRun {
            path: PathBuf::from(program),
            args: args.to_vec(),
            cwd: get_pane_cwd(focused).ok(),
            border_style: None,
        };
        if let Some(PaneId::Terminal(id)) = open_command_pane(command, BTreeMap::new()) {
            rename_terminal_pane(id, AGENT_PANE);
        }
    }
}

/// Whether the pane's foreground program is one of `EDITORS`.
fn is_editor(pane: PaneId) -> bool {
    let Ok(argv) = get_pane_running_command(pane) else {
        return false;
    };
    argv.first().is_some_and(|program| EDITORS.contains(&program_name(program).as_str()))
}

/// `C:\Program Files\Neovim\bin\nvim.exe` -> `nvim`.
fn program_name(program: &str) -> String {
    let file = program.rsplit(['/', '\\']).next().unwrap_or(program).to_lowercase();
    file.strip_suffix(".exe").map(str::to_owned).unwrap_or(file)
}

fn parse_direction(payload: &str) -> Option<Direction> {
    match payload.trim() {
        "left" => Some(Direction::Left),
        "right" => Some(Direction::Right),
        "up" => Some(Direction::Up),
        "down" => Some(Direction::Down),
        _ => None,
    }
}

/// The Zellij resize that moves a divider towards `direction`, given whether
/// the pane has a neighbour to its right and below. The right/bottom divider
/// is preferred: moving it towards the neighbour grows the pane, away
/// shrinks it. Without one, the left/top divider moves, which shrinks the
/// pane when it moves towards the far side.
fn divider_move(direction: Direction, has_right: bool, has_below: bool) -> (Resize, Direction) {
    match direction {
        Direction::Right if has_right => (Resize::Increase, Direction::Right),
        Direction::Right => (Resize::Decrease, Direction::Left),
        Direction::Left if has_right => (Resize::Decrease, Direction::Right),
        Direction::Left => (Resize::Increase, Direction::Left),
        Direction::Down if has_below => (Resize::Increase, Direction::Down),
        Direction::Down => (Resize::Decrease, Direction::Up),
        Direction::Up if has_below => (Resize::Decrease, Direction::Down),
        Direction::Up => (Resize::Increase, Direction::Up),
    }
}

/// The vi key Neovim maps for each direction.
fn key_for(direction: Direction) -> u8 {
    match direction {
        Direction::Left => b'h',
        Direction::Down => b'j',
        Direction::Up => b'k',
        Direction::Right => b'l',
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn program_name_strips_path_and_extension() {
        assert_eq!(program_name(r"C:\Program Files\Neovim\bin\nvim.exe"), "nvim");
        assert_eq!(program_name("/usr/bin/nvim"), "nvim");
        assert_eq!(program_name("NVIM.EXE"), "nvim");
        assert_eq!(program_name("pwsh"), "pwsh");
    }

    #[test]
    fn dividers_prefer_the_right_and_bottom_one() {
        // A left pane (neighbour on the right): Alt L grows it, Alt H shrinks it.
        assert_eq!(divider_move(Direction::Right, true, false), (Resize::Increase, Direction::Right));
        assert_eq!(divider_move(Direction::Left, true, false), (Resize::Decrease, Direction::Right));
        // A right pane: its left divider moves.
        assert_eq!(divider_move(Direction::Right, false, false), (Resize::Decrease, Direction::Left));
        assert_eq!(divider_move(Direction::Left, false, false), (Resize::Increase, Direction::Left));
        // A top pane grows downwards; a bottom pane's top divider moves.
        assert_eq!(divider_move(Direction::Down, false, true), (Resize::Increase, Direction::Down));
        assert_eq!(divider_move(Direction::Up, false, false), (Resize::Increase, Direction::Up));
    }

    #[test]
    fn directions_parse_and_map_to_vi_keys() {
        assert_eq!(parse_direction("left").map(key_for), Some(b'h'));
        assert_eq!(parse_direction(" down ").map(key_for), Some(b'j'));
        assert_eq!(parse_direction("sideways"), None);
    }
}
