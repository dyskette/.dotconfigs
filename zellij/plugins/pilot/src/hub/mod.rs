//! The session hub: one list of running sessions, saved sessions and
//! projects, with modal vim keys. It is the same view when Windows Terminal
//! opens (full screen, in a lobby session) and inside a session (floating).
//!
//! This module is the hub's logic only: it turns keys into state changes and
//! `Effect`s, and knows nothing about Zellij. The plugin shell feeds it
//! snapshots and keys, draws `rows()`, and carries the effects out.
//!
//! Keys (zellij/README.md has the full table):
//!
//! - insert (the mode it opens in): type to filter, Ctrl-n/p or Ctrl-j/k to
//!   move, Enter opens, Esc goes to normal mode and keeps the filter.
//! - normal: j/k, gg/G, Ctrl-d/u move; l expands or descends and opens only
//!   a leaf; h collapses or goes to the parent; Enter always opens; o new;
//!   r rename; dd demotes one step (running -> saved -> gone, tab -> closed);
//!   / or i filter; p preview; ? help; q or Esc close.

pub mod fuzzy;
pub mod model;
pub mod target;

use std::collections::BTreeSet;

use model::{OpenPlan, Row, RowId, RowKind, Snapshot};

/// A key as the hub sees it; the shell maps Zellij's key events to these.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Ctrl(char),
    Enter,
    Esc,
    Backspace,
    Up,
    Down,
    /// Anything the hub has no use for.
    Other,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Typing filters the list.
    Insert,
    /// Keys are commands.
    Normal,
}

/// What the shell has to do after a key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Effect {
    /// Go there, then close the hub.
    Open(OpenPlan),
    /// Stop a running session; it stays saved.
    Kill { session: String },
    /// Stop the session the hub is in, after moving the client to
    /// `switch_to` (or back to the lobby when there is none).
    KillCurrent { session: String, switch_to: Option<String> },
    /// Delete a saved session for good.
    Forget { session: String },
    CloseTab { session: String, id: usize },
    RenameSession { from: String, to: String },
    RenameTab { session: String, id: usize, to: String },
    /// Close the hub and return to the pane it was opened from.
    Close,
    /// In the lobby: leave Zellij for a plain shell.
    Quit,
}

/// What a text prompt is for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Purpose {
    /// A folder to open or a name for an empty session.
    New,
    RenameSession { from: String },
    RenameTab { session: String, id: usize },
}

/// Something drawn over the list that takes the keys.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Overlay {
    Help,
    /// y or Enter runs the effects; anything else cancels.
    Confirm { message: String, effects: Vec<Effect> },
    Prompt { purpose: Purpose, text: String },
}

pub struct Hub {
    snapshot: Snapshot,
    rows: Vec<Row>,
    query: String,
    mode: Mode,
    cursor: Option<RowId>,
    expanded: BTreeSet<String>,
    overlay: Option<Overlay>,
    /// First key of a two-key command (g, d, z).
    pending: Option<char>,
    preview: bool,
    /// A one-line message, cleared by the next key.
    notice: Option<String>,
    /// Rows a half-page move covers; the shell sets it from the list height.
    half_page: usize,
    /// Whether this hub is the lobby (no session to return to).
    lobby: bool,
    /// Whether the starting cursor position was chosen yet.
    placed: bool,
}

impl Hub {
    pub fn new(lobby: bool) -> Self {
        Hub {
            snapshot: Snapshot::default(),
            rows: Vec::new(),
            query: String::new(),
            mode: Mode::Insert,
            cursor: None,
            expanded: BTreeSet::new(),
            overlay: None,
            pending: None,
            preview: true,
            notice: None,
            half_page: 5,
            lobby,
            placed: false,
        }
    }

    // --- State the shell draws -------------------------------------------------

    pub fn rows(&self) -> &[Row] {
        &self.rows
    }
    pub fn query(&self) -> &str {
        &self.query
    }
    pub fn mode(&self) -> Mode {
        self.mode
    }
    pub fn overlay(&self) -> Option<&Overlay> {
        self.overlay.as_ref()
    }
    pub fn notice(&self) -> Option<&str> {
        self.notice.as_deref()
    }
    pub fn preview_enabled(&self) -> bool {
        self.preview
    }
    pub fn is_lobby(&self) -> bool {
        self.lobby
    }
    pub fn set_half_page(&mut self, rows: usize) {
        self.half_page = rows.max(1);
    }

    pub fn selected_index(&self) -> Option<usize> {
        let cursor = self.cursor.as_ref()?;
        self.rows.iter().position(|row| row.id().as_ref() == Some(cursor))
    }

    pub fn selected(&self) -> Option<&Row> {
        self.selected_index().map(|index| &self.rows[index])
    }

    /// What Enter does on the selected row, for the hint line.
    pub fn enter_hint(&self) -> Option<String> {
        self.selected().and_then(model::plan_for).map(|plan| plan.hint())
    }

    // --- Data ----------------------------------------------------------------------

    /// Replace what is listed. The cursor stays on its row when the row is
    /// still there; the first time there is something to show it starts on
    /// the previous session, so opening the hub and pressing Enter toggles
    /// between the last two sessions.
    pub fn set_snapshot(&mut self, snapshot: Snapshot) {
        self.snapshot = snapshot;
        self.rebuild();
        if !self.placed && self.rows.iter().any(Row::selectable) {
            self.placed = true;
            if self.query.is_empty() {
                let previous = self.rows.iter().find(|row| {
                    matches!(row.kind, RowKind::Session { running: true, current: false, .. })
                });
                if let Some(id) = previous.and_then(Row::id) {
                    self.cursor = Some(id);
                }
            }
        }
    }

    /// Rebuild the rows and keep the cursor valid: on its row if it is still
    /// listed, else on the nearest selectable row.
    fn rebuild(&mut self) {
        let old_index = self.selected_index();
        self.rows = model::build_rows(&self.snapshot, &self.query, &self.expanded);
        if self.selected_index().is_some() {
            return;
        }
        let near = old_index.unwrap_or(0).min(self.rows.len().saturating_sub(1));
        self.cursor = (near..self.rows.len())
            .chain((0..near).rev())
            .find(|&i| self.rows[i].selectable())
            .and_then(|i| self.rows[i].id());
    }

    /// After the filter changed: the best match, which is the first row. The
    /// "create" row is only chosen when it is all there is.
    fn select_best(&mut self) {
        let first = |rows: &[Row], wanted: fn(&Row) -> bool| rows.iter().find(|r| wanted(r)).and_then(Row::id);
        self.cursor = first(&self.rows, |r| r.selectable() && !matches!(r.kind, RowKind::Create { .. }))
            .or_else(|| first(&self.rows, Row::selectable));
    }

    fn query_changed(&mut self) {
        self.rebuild();
        self.select_best();
    }

    // --- Movement ------------------------------------------------------------------

    /// Move the cursor by `delta` selectable rows, stopping at the ends.
    fn move_by(&mut self, delta: isize) {
        let selectable: Vec<usize> = (0..self.rows.len()).filter(|&i| self.rows[i].selectable()).collect();
        if selectable.is_empty() {
            return;
        }
        let at = self.selected_index().and_then(|index| selectable.iter().position(|&i| i == index)).unwrap_or(0);
        let to = (at as isize + delta).clamp(0, selectable.len() as isize - 1) as usize;
        self.cursor = self.rows[selectable[to]].id();
    }

    fn move_to_end(&mut self, last: bool) {
        self.move_by(if last { isize::MAX / 2 } else { isize::MIN / 2 });
    }

    // --- Keys ----------------------------------------------------------------------

    pub fn handle_key(&mut self, key: Key) -> Vec<Effect> {
        self.notice = None;
        if self.overlay.is_some() {
            return self.overlay_key(key);
        }
        match self.mode {
            Mode::Insert => self.insert_key(key),
            Mode::Normal => self.normal_key(key),
        }
    }

    fn insert_key(&mut self, key: Key) -> Vec<Effect> {
        match key {
            Key::Char(c) => {
                self.query.push(c);
                self.query_changed();
            }
            Key::Backspace => {
                if self.query.pop().is_some() {
                    self.query_changed();
                }
            }
            Key::Ctrl('w') => {
                let kept = self.query.trim_end().rsplit_once(' ').map(|(head, _)| format!("{head} ")).unwrap_or_default();
                if kept != self.query {
                    self.query = kept;
                    self.query_changed();
                }
            }
            Key::Ctrl('u') => {
                if !self.query.is_empty() {
                    self.query.clear();
                    self.query_changed();
                }
            }
            Key::Ctrl('n' | 'j') | Key::Down => self.move_by(1),
            Key::Ctrl('p' | 'k') | Key::Up => self.move_by(-1),
            Key::Enter => return self.open(),
            // The filter stays: normal mode acts on the filtered list.
            Key::Esc => self.mode = Mode::Normal,
            _ => {}
        }
        Vec::new()
    }

    fn normal_key(&mut self, key: Key) -> Vec<Effect> {
        if let Some(first) = self.pending.take() {
            match (first, key) {
                ('g', Key::Char('g')) => self.move_to_end(false),
                ('d', Key::Char('d')) => return self.demote(),
                ('z', Key::Char('o')) => self.expand(false),
                ('z', Key::Char('c')) => self.collapse(false),
                _ => {} // an unfinished command is dropped, as in vim
            }
            return Vec::new();
        }

        match key {
            Key::Char('j') | Key::Down | Key::Ctrl('n') => self.move_by(1),
            Key::Char('k') | Key::Up | Key::Ctrl('p') => self.move_by(-1),
            Key::Char('G') => self.move_to_end(true),
            Key::Ctrl('d') => self.move_by(self.half_page as isize),
            Key::Ctrl('u') => self.move_by(-(self.half_page as isize)),
            Key::Char(c @ ('g' | 'd' | 'z')) => self.pending = Some(c),

            Key::Char('l') => {
                if self.selected().is_some_and(Row::is_leaf) {
                    return self.open();
                }
                self.expand(true);
            }
            Key::Char('h') => self.collapse(true),
            Key::Enter => return self.open(),

            Key::Char('o') => {
                self.overlay = Some(Overlay::Prompt { purpose: Purpose::New, text: String::new() });
            }
            Key::Char('r') => self.start_rename(),
            Key::Char('/' | 'i') => self.mode = Mode::Insert,
            Key::Char('p') => self.preview = !self.preview,
            Key::Char('?') => self.overlay = Some(Overlay::Help),
            Key::Char('q') | Key::Esc => return vec![if self.lobby { Effect::Quit } else { Effect::Close }],
            _ => {}
        }
        Vec::new()
    }

    fn overlay_key(&mut self, key: Key) -> Vec<Effect> {
        match self.overlay.take() {
            Some(Overlay::Help) | None => Vec::new(), // any key closes the help
            Some(Overlay::Confirm { effects, .. }) => match key {
                Key::Char('y' | 'Y') | Key::Enter => effects,
                _ => Vec::new(),
            },
            Some(Overlay::Prompt { purpose, mut text }) => match key {
                Key::Esc => Vec::new(),
                Key::Enter => self.submit_prompt(purpose, text.trim()),
                key => {
                    match key {
                        Key::Char(c) => text.push(c),
                        Key::Backspace => {
                            text.pop();
                        }
                        Key::Ctrl('u') => text.clear(),
                        _ => {}
                    }
                    self.overlay = Some(Overlay::Prompt { purpose, text });
                    Vec::new()
                }
            },
        }
    }

    // --- Commands ------------------------------------------------------------------

    fn open(&mut self) -> Vec<Effect> {
        match self.selected().and_then(model::plan_for) {
            Some(OpenPlan::Stay) => vec![Effect::Close],
            Some(plan) => vec![Effect::Open(plan)],
            None => Vec::new(),
        }
    }

    /// The session a row belongs to: itself, or its tab's.
    fn session_of(row: &Row) -> Option<&str> {
        match &row.kind {
            RowKind::Session { name, .. } => Some(name),
            RowKind::Tab { session, .. } => Some(session),
            _ => None,
        }
    }

    /// `l` on a session with tabs: unfold it, or step onto its first tab when
    /// it is unfolded already (`descend`). `zo` only unfolds.
    fn expand(&mut self, descend: bool) {
        let Some(row) = self.selected() else { return };
        let RowKind::Session { name, running: true, tabs, .. } = &row.kind else { return };
        if *tabs == 0 {
            return;
        }
        // Newly unfolded: also when a filter was showing its matching tabs
        // only, since the user asks for all of them.
        if self.expanded.insert(name.clone()) {
            self.rebuild();
            return;
        }
        if descend
            && let Some(index) = self.selected_index()
            && matches!(self.rows.get(index + 1).map(|r| &r.kind), Some(RowKind::Tab { .. }))
        {
            self.cursor = self.rows[index + 1].id();
        }
    }

    /// `h`: from a tab to its session (`to_parent`), or fold the session.
    /// `zc` folds the session of the row it is on.
    fn collapse(&mut self, to_parent: bool) {
        let Some(row) = self.selected() else { return };
        let Some(session) = Self::session_of(row).map(str::to_owned) else { return };
        let on_tab = matches!(row.kind, RowKind::Tab { .. });
        if on_tab && to_parent {
            self.cursor = Some(RowId::Session(session));
            return;
        }
        self.expanded.remove(&session);
        self.cursor = Some(RowId::Session(session));
        self.rebuild();
    }

    fn start_rename(&mut self) {
        let Some(row) = self.selected() else { return };
        self.overlay = match &row.kind {
            RowKind::Session { name, .. } => {
                Some(Overlay::Prompt { purpose: Purpose::RenameSession { from: name.clone() }, text: name.clone() })
            }
            RowKind::Tab { session, id, name, .. } => Some(Overlay::Prompt {
                purpose: Purpose::RenameTab { session: session.clone(), id: *id },
                text: name.clone(),
            }),
            _ => {
                self.notice = Some("Only sessions and tabs can be renamed".to_owned());
                None
            }
        };
    }

    fn submit_prompt(&mut self, purpose: Purpose, text: &str) -> Vec<Effect> {
        if text.is_empty() {
            return Vec::new();
        }
        match purpose {
            Purpose::New if target::looks_like_path(text) => {
                vec![Effect::Open(OpenPlan::Path { text: text.to_owned() })]
            }
            Purpose::New => {
                let name = target::session_name(text);
                // A name that exists opens that session instead of failing.
                let plan = match self.snapshot.sessions.iter().find(|s| s.name == name) {
                    Some(s) if s.current => return vec![Effect::Close],
                    Some(s) if s.running => OpenPlan::Attach { session: name, tab: None },
                    Some(_) => OpenPlan::Resurrect { session: name },
                    None => OpenPlan::Scratch { session: name },
                };
                vec![Effect::Open(plan)]
            }
            Purpose::RenameSession { from } => {
                let to = target::session_name(text);
                if to == from {
                    return Vec::new();
                }
                if self.snapshot.sessions.iter().any(|s| s.name == to) {
                    self.notice = Some(format!("A session named {to} already exists"));
                    return Vec::new();
                }
                vec![Effect::RenameSession { from, to }]
            }
            Purpose::RenameTab { session, id } => vec![Effect::RenameTab { session, id, to: text.to_owned() }],
        }
    }

    /// `dd`: one step down. A running session is stopped and stays saved, a
    /// saved one is deleted, a tab is closed. Only what cannot be undone, or
    /// would interrupt work, asks first.
    fn demote(&mut self) -> Vec<Effect> {
        let Some(row) = self.selected() else { return Vec::new() };
        let busy = row.working || row.attention > 0;
        let why = if row.working { "an agent is working in it" } else { "something in it needs you" };

        let (effect, question) = match &row.kind {
            RowKind::Session { name, running: true, current: true, .. } => {
                let switch_to = self
                    .rows
                    .iter()
                    .find_map(|r| match &r.kind {
                        RowKind::Session { name, running: true, current: false, .. } => Some(name.clone()),
                        _ => None,
                    });
                let after = match &switch_to {
                    Some(next) => format!("you move to {next}"),
                    None => "you return to the hub".to_owned(),
                };
                (
                    Effect::KillCurrent { session: name.clone(), switch_to },
                    Some(format!("Stop {name}, the session you are in? It stays saved; {after}.")),
                )
            }
            RowKind::Session { name, running: true, .. } => (
                Effect::Kill { session: name.clone() },
                busy.then(|| format!("Stop {name}? It stays saved, but {why}.")),
            ),
            RowKind::Session { name, .. } => (
                Effect::Forget { session: name.clone() },
                Some(format!("Delete the saved session {name} for good?")),
            ),
            RowKind::Tab { session, id, name, .. } => (
                Effect::CloseTab { session: session.clone(), id: *id },
                busy.then(|| format!("Close tab {name} of {session}? {}.", capitalize(why))),
            ),
            RowKind::Project { .. } => {
                self.notice = Some("A project is a folder, not a session: nothing to remove".to_owned());
                return Vec::new();
            }
            RowKind::Create { .. } | RowKind::Header(_) => return Vec::new(),
        };

        match question {
            Some(message) => {
                self.overlay = Some(Overlay::Confirm { message, effects: vec![effect] });
                Vec::new()
            }
            None => vec![effect],
        }
    }
}

fn capitalize(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::model::tests::{sample, session};
    use super::*;

    fn hub() -> Hub {
        let mut hub = Hub::new(false);
        hub.set_snapshot(sample());
        hub
    }

    fn keys(hub: &mut Hub, text: &str) -> Vec<Effect> {
        text.chars().flat_map(|c| hub.handle_key(Key::Char(c))).collect()
    }

    fn normal() -> Hub {
        let mut hub = hub();
        hub.handle_key(Key::Esc);
        hub
    }

    fn label(hub: &Hub) -> String {
        match hub.selected().map(|row| &row.kind) {
            Some(RowKind::Session { name, .. }) => name.clone(),
            Some(RowKind::Tab { name, .. }) => format!("tab {name}"),
            Some(RowKind::Project { rel, .. }) => format!("project {rel}"),
            Some(RowKind::Create { name }) => format!("create {name}"),
            _ => "nothing".to_owned(),
        }
    }

    // --- Opening ---------------------------------------------------------------

    #[test]
    fn it_opens_in_insert_mode_on_the_previous_session() {
        let mut hub = hub();
        assert_eq!(hub.mode(), Mode::Insert);
        assert_eq!(label(&hub), "globex", "the previous session, not the current one");
        assert_eq!(hub.enter_hint().as_deref(), Some("attach globex"));
        assert_eq!(hub.handle_key(Key::Enter), [Effect::Open(OpenPlan::Attach { session: "globex".into(), tab: None })]);
    }

    #[test]
    fn with_no_previous_session_it_starts_on_the_first_row() {
        let mut hub = Hub::new(true);
        hub.set_snapshot(Snapshot { sessions: vec![], projects: vec![model::tests::project("sentinel")] });
        assert_eq!(label(&hub), "project sentinel");
    }

    #[test]
    fn the_cursor_is_placed_once_and_then_follows_its_row() {
        let mut hub = normal();
        keys(&mut hub, "j"); // onto initech
        assert_eq!(label(&hub), "initech");
        let mut changed = sample();
        changed.sessions.push(session("another", &["x"], 70)); // sorts above globex
        hub.set_snapshot(changed);
        assert_eq!(label(&hub), "initech", "a refresh does not move the cursor");
    }

    #[test]
    fn when_its_row_disappears_the_cursor_takes_the_nearest() {
        let mut hub = normal();
        keys(&mut hub, "j");
        let mut changed = sample();
        changed.sessions.retain(|s| s.name != "initech");
        hub.set_snapshot(changed);
        assert_eq!(label(&hub), "old-client");
    }

    // --- Insert mode -------------------------------------------------------------

    #[test]
    fn typing_filters_and_selects_the_best_match() {
        let mut hub = hub();
        keys(&mut hub, "sen");
        assert_eq!(hub.query(), "sen");
        assert_eq!(label(&hub), "project sentinel");
        assert_eq!(hub.enter_hint().as_deref(), Some("new session \"sentinel\""));
    }

    #[test]
    fn the_create_row_is_selected_only_when_nothing_else_matches() {
        let mut hub = hub();
        keys(&mut hub, "to");
        assert_ne!(label(&hub), "create to");
        keys(&mut hub, "zzz");
        assert_eq!(label(&hub), "create tozzz");
        assert_eq!(hub.enter_hint().as_deref(), Some("create \"tozzz\""));
        assert_eq!(hub.handle_key(Key::Enter), [Effect::Open(OpenPlan::Scratch { session: "tozzz".into() })]);
    }

    #[test]
    fn control_keys_move_and_edit_in_insert_mode() {
        let mut hub = hub();
        hub.handle_key(Key::Ctrl('j'));
        assert_eq!(label(&hub), "initech");
        hub.handle_key(Key::Ctrl('k'));
        hub.handle_key(Key::Ctrl('p'));
        assert_eq!(label(&hub), "acme");
        hub.handle_key(Key::Ctrl('n'));
        assert_eq!(label(&hub), "globex");

        keys(&mut hub, "acm too");
        hub.handle_key(Key::Ctrl('w'));
        assert_eq!(hub.query(), "acm ");
        hub.handle_key(Key::Backspace);
        assert_eq!(hub.query(), "acm");
        hub.handle_key(Key::Ctrl('u'));
        assert_eq!(hub.query(), "");
    }

    #[test]
    fn letters_are_text_in_insert_mode() {
        let mut hub = hub();
        assert!(keys(&mut hub, "qdd").is_empty(), "q and dd are only commands in normal mode");
        assert_eq!(hub.query(), "qdd");
    }

    #[test]
    fn escape_keeps_the_filter() {
        let mut hub = hub();
        keys(&mut hub, "cer");
        hub.handle_key(Key::Esc);
        assert_eq!(hub.mode(), Mode::Normal);
        assert_eq!(hub.query(), "cer");
        assert_eq!(hub.rows().len(), 3, "session, its matching tab, create");
        keys(&mut hub, "i");
        assert_eq!(hub.mode(), Mode::Insert);
        assert_eq!(hub.query(), "cer");
    }

    // --- Normal mode: movement ------------------------------------------------------

    #[test]
    fn j_and_k_skip_headers_and_stop_at_the_ends() {
        let mut hub = normal();
        keys(&mut hub, "kkkk");
        assert_eq!(label(&hub), "acme");
        keys(&mut hub, "jj");
        assert_eq!(label(&hub), "initech", "over the Saved header");
        keys(&mut hub, "jjjjjjjjjj");
        assert_eq!(label(&hub), "project sentinel");
    }

    #[test]
    fn gg_and_capital_g_jump_to_the_ends() {
        let mut hub = normal();
        keys(&mut hub, "G");
        assert_eq!(label(&hub), "project sentinel");
        keys(&mut hub, "gg");
        assert_eq!(label(&hub), "acme");
    }

    #[test]
    fn half_page_moves_by_the_height_the_shell_reports() {
        let mut hub = normal();
        hub.set_half_page(3);
        keys(&mut hub, "gg");
        hub.handle_key(Key::Ctrl('d'));
        assert_eq!(label(&hub), "old-client");
        hub.handle_key(Key::Ctrl('u'));
        assert_eq!(label(&hub), "acme");
    }

    #[test]
    fn an_unfinished_two_key_command_is_dropped() {
        let mut hub = normal();
        assert!(keys(&mut hub, "dj").is_empty());
        assert_eq!(label(&hub), "globex", "d then j does nothing, not even the move");
        assert!(keys(&mut hub, "gx").is_empty());
    }

    // --- Normal mode: the tree --------------------------------------------------------

    #[test]
    fn l_expands_then_descends_and_opens_only_a_leaf() {
        let mut hub = normal();
        assert!(keys(&mut hub, "l").is_empty(), "first l unfolds");
        assert_eq!(label(&hub), "globex");
        assert!(matches!(hub.selected().unwrap().kind, RowKind::Session { expanded: true, .. }));
        assert!(keys(&mut hub, "l").is_empty(), "second l steps onto the first tab");
        assert_eq!(label(&hub), "tab globex-time");
        assert_eq!(
            keys(&mut hub, "l"),
            [Effect::Open(OpenPlan::Attach { session: "globex".into(), tab: Some((0, "globex-time".into())) })],
            "a tab is a leaf"
        );
    }

    #[test]
    fn l_opens_saved_sessions_and_projects_directly() {
        let mut hub = normal();
        keys(&mut hub, "j");
        assert_eq!(keys(&mut hub, "l"), [Effect::Open(OpenPlan::Resurrect { session: "initech".into() })]);
        keys(&mut hub, "G");
        assert!(matches!(keys(&mut hub, "l")[..], [Effect::Open(OpenPlan::NewSession(_))]));
    }

    #[test]
    fn h_goes_to_the_parent_then_collapses() {
        let mut hub = normal();
        keys(&mut hub, "ll");
        assert_eq!(label(&hub), "tab globex-time");
        keys(&mut hub, "h");
        assert_eq!(label(&hub), "globex");
        assert!(matches!(hub.selected().unwrap().kind, RowKind::Session { expanded: true, .. }));
        keys(&mut hub, "h");
        assert!(matches!(hub.selected().unwrap().kind, RowKind::Session { expanded: false, .. }));
    }

    #[test]
    fn zo_and_zc_fold_without_moving_or_opening() {
        let mut hub = normal();
        keys(&mut hub, "zo");
        assert_eq!(label(&hub), "globex");
        assert!(matches!(hub.selected().unwrap().kind, RowKind::Session { expanded: true, .. }));
        keys(&mut hub, "j");
        assert_eq!(label(&hub), "tab globex-time");
        keys(&mut hub, "zc");
        assert_eq!(label(&hub), "globex", "zc on a tab folds its session");
        assert!(matches!(hub.selected().unwrap().kind, RowKind::Session { expanded: false, .. }));
    }

    #[test]
    fn enter_always_opens_even_a_folded_session() {
        let mut hub = normal();
        assert_eq!(hub.handle_key(Key::Enter), [Effect::Open(OpenPlan::Attach { session: "globex".into(), tab: None })]);
    }

    #[test]
    fn enter_on_the_current_session_just_closes() {
        let mut hub = normal();
        keys(&mut hub, "gg");
        assert_eq!(hub.enter_hint().as_deref(), Some("stay here"));
        assert_eq!(hub.handle_key(Key::Enter), [Effect::Close]);
    }

    #[test]
    fn l_on_a_filtered_session_shows_all_its_tabs() {
        let mut hub = hub();
        keys(&mut hub, "cer");
        hub.handle_key(Key::Esc);
        assert_eq!(label(&hub), "acme");
        keys(&mut hub, "l");
        assert_eq!(hub.rows().iter().filter(|r| matches!(r.kind, RowKind::Tab { .. })).count(), 2);
    }

    // --- Normal mode: commands ----------------------------------------------------------

    #[test]
    fn q_closes_the_popup_and_quits_the_lobby() {
        assert_eq!(keys(&mut normal(), "q"), [Effect::Close]);
        assert_eq!(normal().handle_key(Key::Esc), [Effect::Close]);

        let mut lobby = Hub::new(true);
        lobby.set_snapshot(sample());
        lobby.handle_key(Key::Esc);
        assert_eq!(keys(&mut lobby, "q"), [Effect::Quit]);
    }

    #[test]
    fn p_toggles_the_preview_and_question_mark_the_help() {
        let mut hub = normal();
        assert!(hub.preview_enabled());
        keys(&mut hub, "p");
        assert!(!hub.preview_enabled());
        keys(&mut hub, "?");
        assert_eq!(hub.overlay(), Some(&Overlay::Help));
        assert!(keys(&mut hub, "q").is_empty(), "the key that closes the help does nothing else");
        assert_eq!(hub.overlay(), None);
    }

    #[test]
    fn n_is_left_unbound() {
        let mut hub = normal();
        assert!(keys(&mut hub, "nN").is_empty());
        assert_eq!(label(&hub), "globex");
        assert_eq!(hub.overlay(), None);
    }

    // --- dd ---------------------------------------------------------------------------------

    #[test]
    fn dd_stops_an_idle_running_session_without_asking() {
        let mut hub = normal();
        assert_eq!(keys(&mut hub, "dd"), [Effect::Kill { session: "globex".into() }]);
    }

    #[test]
    fn dd_asks_before_interrupting_work() {
        let mut snapshot = sample();
        snapshot.sessions[0].tabs[0].working = true;
        let mut hub = Hub::new(false);
        hub.set_snapshot(snapshot);
        hub.handle_key(Key::Esc);

        assert!(keys(&mut hub, "dd").is_empty());
        let Some(Overlay::Confirm { message, .. }) = hub.overlay() else { panic!("expected a question") };
        assert!(message.contains("an agent is working"), "{message}");
        assert!(keys(&mut hub, "n").is_empty(), "n cancels");
        assert_eq!(hub.overlay(), None);

        keys(&mut hub, "dd");
        assert_eq!(keys(&mut hub, "y"), [Effect::Kill { session: "globex".into() }]);
    }

    #[test]
    fn dd_always_asks_before_deleting_a_saved_session() {
        let mut hub = normal();
        keys(&mut hub, "j");
        assert!(keys(&mut hub, "dd").is_empty());
        assert!(matches!(hub.overlay(), Some(Overlay::Confirm { .. })));
        assert_eq!(hub.handle_key(Key::Enter), [Effect::Forget { session: "initech".into() }]);
    }

    #[test]
    fn a_double_dd_cannot_wipe_a_session() {
        // The first stops it; once it is listed as saved, the second asks.
        let mut hub = normal();
        assert_eq!(keys(&mut hub, "dd"), [Effect::Kill { session: "globex".into() }]);
        let mut after = sample();
        after.sessions[0] = model::tests::saved_session("globex", 1);
        hub.set_snapshot(after);
        assert_eq!(label(&hub), "globex");
        assert!(keys(&mut hub, "dd").is_empty());
        assert!(matches!(hub.overlay(), Some(Overlay::Confirm { .. })));
    }

    #[test]
    fn dd_on_the_current_session_asks_and_moves_to_the_previous_one() {
        let mut hub = normal();
        keys(&mut hub, "gg");
        assert!(keys(&mut hub, "dd").is_empty());
        assert_eq!(
            keys(&mut hub, "y"),
            [Effect::KillCurrent { session: "acme".into(), switch_to: Some("globex".into()) }]
        );
    }

    #[test]
    fn dd_closes_a_tab_and_does_nothing_on_a_project() {
        let mut hub = normal();
        keys(&mut hub, "ll");
        assert_eq!(keys(&mut hub, "dd"), [Effect::CloseTab { session: "globex".into(), id: 0 }]);

        keys(&mut hub, "G");
        assert!(keys(&mut hub, "dd").is_empty());
        assert!(hub.notice().unwrap().contains("not a session"));
        assert_eq!(hub.overlay(), None);
        keys(&mut hub, "k");
        assert_eq!(hub.notice(), None, "the next key clears the notice");
    }

    // --- Prompts --------------------------------------------------------------------------------

    fn type_and_submit(hub: &mut Hub, text: &str) -> Vec<Effect> {
        keys(hub, text);
        hub.handle_key(Key::Enter)
    }

    #[test]
    fn o_opens_a_folder_or_creates_a_named_session() {
        let mut hub = normal();
        keys(&mut hub, "o");
        assert_eq!(
            type_and_submit(&mut hub, "~/Documents/scratch"),
            [Effect::Open(OpenPlan::Path { text: "~/Documents/scratch".into() })]
        );

        keys(&mut hub, "o");
        assert_eq!(type_and_submit(&mut hub, "my notes"), [Effect::Open(OpenPlan::Scratch { session: "my_notes".into() })]);
    }

    #[test]
    fn o_with_an_existing_name_opens_that_session() {
        let mut hub = normal();
        keys(&mut hub, "o");
        assert_eq!(type_and_submit(&mut hub, "initech"), [Effect::Open(OpenPlan::Resurrect { session: "initech".into() })]);
    }

    #[test]
    fn prompts_edit_and_cancel() {
        let mut hub = normal();
        keys(&mut hub, "o");
        keys(&mut hub, "abc");
        hub.handle_key(Key::Backspace);
        assert!(matches!(hub.overlay(), Some(Overlay::Prompt { text, .. }) if text == "ab"));
        assert!(hub.handle_key(Key::Esc).is_empty());
        assert_eq!(hub.overlay(), None);

        keys(&mut hub, "o");
        assert!(hub.handle_key(Key::Enter).is_empty(), "an empty prompt does nothing");
    }

    #[test]
    fn r_renames_a_session_starting_from_its_name() {
        let mut hub = normal();
        keys(&mut hub, "r");
        assert!(matches!(hub.overlay(), Some(Overlay::Prompt { text, .. }) if text == "globex"));
        assert_eq!(
            type_and_submit(&mut hub, "-mx"),
            [Effect::RenameSession { from: "globex".into(), to: "globex-mx".into() }]
        );
    }

    #[test]
    fn r_refuses_a_name_that_is_taken() {
        let mut hub = normal();
        keys(&mut hub, "r");
        hub.handle_key(Key::Ctrl('u'));
        assert!(type_and_submit(&mut hub, "initech").is_empty());
        assert!(hub.notice().unwrap().contains("already exists"));
    }

    #[test]
    fn r_renames_a_tab_and_explains_itself_on_a_project() {
        let mut hub = normal();
        keys(&mut hub, "llr");
        hub.handle_key(Key::Ctrl('u'));
        assert_eq!(
            type_and_submit(&mut hub, "time"),
            [Effect::RenameTab { session: "globex".into(), id: 0, to: "time".into() }]
        );

        keys(&mut hub, "Gr");
        assert_eq!(hub.overlay(), None);
        assert!(hub.notice().unwrap().contains("Only sessions and tabs"));
    }
}
