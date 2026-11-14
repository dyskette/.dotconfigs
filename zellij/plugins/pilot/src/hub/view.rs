//! What the hub looks like: a `Frame` of styled lines computed from the
//! hub's state and the size of its pane. Pure, so it is tested without
//! Zellij; the plugin shell only prints the frame.
//!
//! Layout, top to bottom: title, prompt, the list (with the preview to its
//! right when the pane is wide, below it when it is tall and narrow, or not
//! at all), a notice line and the hint line.

use super::model::{self, Row, RowKind, SessionState};
use super::{Hub, Mode, Overlay, Purpose};

/// How a span is drawn; the shell maps these to the theme's colours.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Style {
    Plain,
    Dim,
    /// The theme's emphasis colours, 0 to 3.
    Accent(u8),
    Good,
    Bad,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Span {
    pub text: String,
    pub style: Style,
}

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Line {
    pub x: usize,
    pub y: usize,
    pub spans: Vec<Span>,
    /// Drawn as the selected row, across `width` columns.
    pub selected: bool,
    pub width: usize,
}

impl Line {
    fn new(x: usize, y: usize, width: usize) -> Self {
        Line { x, y, width, ..Default::default() }
    }
    fn push(mut self, text: impl Into<String>, style: Style) -> Self {
        let text = text.into();
        if !text.is_empty() {
            self.spans.push(Span { text, style });
        }
        self
    }
    pub fn text(&self) -> String {
        self.spans.iter().map(|s| s.text.as_str()).collect()
    }
    fn len(&self) -> usize {
        self.spans.iter().map(|s| s.text.chars().count()).sum()
    }
    /// Cut the line to its width, ending in an ellipsis when it was longer.
    fn fit(mut self) -> Self {
        if self.len() <= self.width {
            return self;
        }
        let mut room = self.width.saturating_sub(1);
        let mut kept = Vec::new();
        for span in self.spans {
            let chars = span.text.chars().count();
            if chars <= room {
                room -= chars;
                kept.push(span);
            } else {
                kept.push(Span { text: span.text.chars().take(room).collect(), style: span.style });
                break;
            }
        }
        kept.push(Span { text: "…".to_owned(), style: Style::Dim });
        self.spans = kept;
        self
    }
    /// Put `right` at the right edge, when both parts fit with a gap.
    fn with_right(mut self, right: Vec<Span>) -> Self {
        let right_len: usize = right.iter().map(|s| s.text.chars().count()).sum();
        if right_len > 0 && self.len() + 2 + right_len <= self.width {
            let gap = self.width - self.len() - right_len;
            self.spans.push(Span { text: " ".repeat(gap), style: Style::Plain });
            self.spans.extend(right);
        }
        self
    }
}

/// What the preview area shows for the selected row.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Preview {
    /// A heading, such as "acme › cerberus".
    pub title: String,
    /// Screen contents or a description, one entry per line.
    pub lines: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Frame {
    pub lines: Vec<Line>,
    /// Where the text cursor goes (insert mode and prompts); hidden when None.
    pub cursor: Option<(usize, usize)>,
    /// Rows of the list area, for half-page moves.
    pub list_height: usize,
}

/// Where the preview goes for a pane of this size.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PreviewPlace {
    Right,
    Below,
    Hidden,
}

/// The list needs about 44 columns; beside it the preview is worth showing
/// from 40 more. A narrow pane shows it below when it is tall enough.
pub fn preview_place(cols: usize, rows: usize, enabled: bool) -> PreviewPlace {
    if !enabled {
        PreviewPlace::Hidden
    } else if cols >= 88 {
        PreviewPlace::Right
    } else if rows >= 26 {
        PreviewPlace::Below
    } else {
        PreviewPlace::Hidden
    }
}

/// The first visible row so that `selected` is on screen, moving the window
/// as little as possible from `scroll`. A section header right above the
/// first row is kept visible with it.
pub fn scroll_for(rows: &[Row], selected: Option<usize>, scroll: usize, height: usize) -> usize {
    let Some(selected) = selected else { return 0 };
    if height == 0 {
        return selected;
    }
    let mut scroll = scroll.min(rows.len().saturating_sub(1));
    if selected < scroll {
        scroll = selected;
    } else if selected >= scroll + height {
        scroll = selected + 1 - height;
    }
    if scroll > 0 && scroll == selected && matches!(rows[scroll - 1].kind, RowKind::Header(_)) && height > 1 {
        scroll -= 1;
    }
    scroll
}

fn age(secs: u64) -> String {
    match secs {
        s if s < 3600 => format!("{}m", (s / 60).max(1)),
        s if s < 86_400 => format!("{}h", s / 3600),
        s => format!("{}d", s / 86_400),
    }
}

/// Attention and activity markers, for the right edge of a row.
fn markers(row: &Row) -> Vec<Span> {
    let mut spans = Vec::new();
    if row.working {
        spans.push(Span { text: "⟳ ".to_owned(), style: Style::Accent(2) });
    }
    if row.attention > 0 {
        spans.push(Span { text: format!("⚑{} ", row.attention), style: Style::Bad });
    }
    spans
}

fn row_line(row: &Row, x: usize, y: usize, width: usize, selected: bool, saved_ages: &dyn Fn(&str) -> Option<u64>) -> Line {
    let line = Line { selected, ..Line::new(x, y, width) };
    let line = match &row.kind {
        RowKind::Header(title) => line.push(format!(" {title}"), Style::Dim),
        RowKind::Session { name, running, current, stale, expanded, tabs } => {
            let fold = match (*running && *tabs > 0, *expanded) {
                (true, true) => "▾",
                (true, false) => "▸",
                _ => " ",
            };
            let quiet = *stale || *current;
            let glyph = if *running { ("●", Style::Good) } else { ("○", Style::Dim) };
            let mut right = markers(row);
            if *running {
                let count = if *tabs == 1 { "1 tab".to_owned() } else { format!("{tabs} tabs") };
                right.push(Span { text: format!("{count} "), style: Style::Dim });
            } else if let Some(secs) = saved_ages(name) {
                right.push(Span { text: format!("saved {} ", age(secs)), style: Style::Dim });
            }
            let line = line
                .push(format!(" {fold} "), Style::Dim)
                .push(glyph.0, if quiet { Style::Dim } else { glyph.1 })
                .push(format!(" {name}"), if quiet { Style::Dim } else { Style::Plain });
            let line = if *current { line.push("  you are here", Style::Dim) } else { line };
            line.with_right(right)
        }
        RowKind::Tab { name, .. } => line.push(format!("       {name}"), Style::Plain).with_right(markers(row)),
        RowKind::Project { rel, session, .. } => {
            let note = match session {
                SessionState::Running => "tab ",
                SessionState::Saved => "saved ",
                SessionState::Missing => "",
            };
            line.push("   · ", Style::Dim)
                .push(rel.clone(), Style::Plain)
                .with_right(vec![Span { text: note.to_owned(), style: Style::Dim }])
        }
        RowKind::Create { name } => line.push("   + ", Style::Accent(1)).push(format!("create \"{name}\""), Style::Accent(1)),
    };
    line.fit()
}

const INSERT_KEYS: &str = "esc normal · ^n ^p move";
const NORMAL_KEYS: &str = "l/h tree · o new · r rename · dd remove · / filter · ? keys";

const HELP: &[(&str, &str)] = &[
    ("Filter (insert mode)", ""),
    ("type", "filter sessions, tabs and projects"),
    ("Ctrl-n Ctrl-p / Ctrl-j Ctrl-k", "move"),
    ("Ctrl-w  Ctrl-u", "delete a word, clear"),
    ("Enter", "open"),
    ("Esc", "normal mode (the filter stays)"),
    ("", ""),
    ("Normal mode", ""),
    ("j k  gg G  Ctrl-d Ctrl-u", "move"),
    ("l", "unfold, step into the tabs; opens a leaf"),
    ("h", "to the session, then fold it"),
    ("zo zc", "unfold, fold"),
    ("Enter", "open (the hint line says how)"),
    ("o", "new: a folder to open, or a name"),
    ("r", "rename the session or tab"),
    ("dd", "one step down: running → saved → gone; closes a tab"),
    ("/ i", "filter"),
    ("p", "preview on or off"),
    ("q Esc", "close"),
];

/// Draw the hub for a pane of `cols` by `rows`. `scroll` is the list's first
/// visible row (see `scroll_for`); `saved_ages` gives a saved session's age.
pub fn frame(
    hub: &Hub,
    preview: &Preview,
    cols: usize,
    rows: usize,
    scroll: usize,
    saved_ages: &dyn Fn(&str) -> Option<u64>,
) -> Frame {
    let mut frame = Frame::default();
    if cols < 20 || rows < 6 {
        frame.lines.push(Line::new(0, 0, cols).push("Too small", Style::Dim).fit());
        return frame;
    }

    // Title and prompt.
    let title = if hub.is_lobby() { " Sessions & projects — pick where to work" } else { " Sessions & projects" };
    frame.lines.push(Line::new(0, 0, cols).push(title, Style::Accent(0)).fit());

    let prompt_y = 1;
    match hub.overlay() {
        Some(Overlay::Prompt { purpose, text }) => {
            let label = match purpose {
                Purpose::New => " New (a folder, or a name): ",
                Purpose::RenameSession { .. } => " Rename session: ",
                Purpose::RenameTab { .. } => " Rename tab: ",
            };
            frame.cursor = Some((label.chars().count() + text.chars().count(), prompt_y));
            frame.lines.push(Line::new(0, prompt_y, cols).push(label, Style::Accent(1)).push(text.clone(), Style::Plain).fit());
        }
        _ => match hub.mode() {
            Mode::Insert => {
                frame.cursor = Some((3 + hub.query().chars().count(), prompt_y));
                frame.lines.push(Line::new(0, prompt_y, cols).push(" ❯ ", Style::Accent(2)).push(hub.query(), Style::Plain).fit());
            }
            Mode::Normal => {
                frame.lines.push(
                    Line::new(0, prompt_y, cols).push(" NORMAL ", Style::Accent(3)).push("› ", Style::Dim).push(hub.query(), Style::Dim).fit(),
                );
            }
        },
    }

    // The body: list and preview, between the prompt and the two bottom lines.
    let body_y = 3;
    let body_height = rows.saturating_sub(body_y + 2);
    let place = preview_place(cols, rows, hub.preview_enabled() && hub.overlay() != Some(&Overlay::Help));
    let (list_width, list_height) = match place {
        PreviewPlace::Right => ((cols * 45 / 100).max(44), body_height),
        PreviewPlace::Below => (cols, body_height * 55 / 100),
        PreviewPlace::Hidden => (cols, body_height),
    };
    frame.list_height = list_height;

    if hub.overlay() == Some(&Overlay::Help) {
        for (i, (keys, what)) in HELP.iter().enumerate().take(body_height) {
            let line = Line::new(0, body_y + i, cols);
            let line = if what.is_empty() {
                line.push(format!(" {keys}"), Style::Accent(0))
            } else {
                line.push(format!("   {keys:<30}"), Style::Accent(2)).push(*what, Style::Plain)
            };
            frame.lines.push(line.fit());
        }
    } else {
        let selected = hub.selected_index();
        for (offset, row) in hub.rows().iter().enumerate().skip(scroll).take(list_height) {
            frame.lines.push(row_line(row, 0, body_y + offset - scroll, list_width, selected == Some(offset), saved_ages));
        }
        if hub.rows().is_empty() {
            frame.lines.push(Line::new(0, body_y, list_width).push("   Nothing here yet: type a name to create a session", Style::Dim).fit());
        }

        // The preview.
        let (px, py, pw, ph) = match place {
            PreviewPlace::Right => (list_width + 1, body_y, cols - list_width - 1, body_height),
            PreviewPlace::Below => (0, body_y + list_height + 1, cols, body_height.saturating_sub(list_height + 1)),
            PreviewPlace::Hidden => (0, 0, 0, 0),
        };
        if ph > 1 {
            frame.lines.push(Line::new(px, py, pw).push(format!(" {}", preview.title), Style::Accent(0)).fit());
            for (i, text) in preview.lines.iter().take(ph - 1).enumerate() {
                frame.lines.push(Line::new(px, py + 1 + i, pw).push(format!(" {text}"), Style::Dim).fit());
            }
        }
    }

    // Notice (or a question), then the hint line.
    let notice_y = rows - 2;
    match hub.overlay() {
        Some(Overlay::Confirm { message, .. }) => {
            frame.lines.push(Line::new(0, notice_y, cols).push(format!(" {message}"), Style::Bad).fit());
        }
        _ => {
            if let Some(notice) = hub.notice() {
                frame.lines.push(Line::new(0, notice_y, cols).push(format!(" {notice}"), Style::Accent(1)).fit());
            }
        }
    }

    let hint = Line::new(0, rows - 1, cols);
    let hint = match hub.overlay() {
        Some(Overlay::Help) => hint.push(" any key closes this", Style::Dim),
        Some(Overlay::Confirm { .. }) => hint.push(" y", Style::Accent(2)).push(" yes · any other key cancels", Style::Dim),
        Some(Overlay::Prompt { .. }) => hint.push(" ⏎", Style::Accent(2)).push(" confirm · esc cancel", Style::Dim),
        None => {
            let action = hub.enter_hint().unwrap_or_else(|| "nothing selected".to_owned());
            let keys = if hub.mode() == Mode::Insert { INSERT_KEYS } else { NORMAL_KEYS };
            hint.push(" ⏎ ", Style::Accent(2)).push(action, Style::Plain).push(format!("   {keys}"), Style::Dim)
        }
    };
    frame.lines.push(hint.fit());
    frame
}

/// The description shown in the preview for rows that have no screen: what
/// opening them does, in full.
pub fn describe(row: &Row) -> Preview {
    let Some(plan) = model::plan_for(row) else { return Preview::default() };
    let mut lines = vec![format!("Enter: {}", plan.hint()), String::new()];
    let title = match &row.kind {
        RowKind::Project { rel, target, session } => {
            let state = match session {
                SessionState::Running => "running",
                SessionState::Saved => "saved, will be resurrected",
                SessionState::Missing => "will be created",
            };
            lines.push(format!("Session  {} ({state})", target.session));
            lines.push(format!("Tab      {}", target.tab));
            lines.push(format!("Folder   {}", target.dir));
            lines.push(String::new());
            lines.push("A service tab: editor, agent, and a dev/test/shell stack.".to_owned());
            rel.clone()
        }
        RowKind::Create { name } => {
            lines.push("An empty session with one shell, in your home folder.".to_owned());
            lines.push("For a project folder, press o in normal mode and type its path.".to_owned());
            format!("new session {name}")
        }
        RowKind::Session { name, current: true, .. } => {
            lines.push("The session you are in. r renames it, dd stops it.".to_owned());
            name.clone()
        }
        RowKind::Session { name, .. } => name.clone(),
        RowKind::Tab { session, name, .. } => format!("{session} › {name}"),
        RowKind::Header(_) => String::new(),
    };
    Preview { title, lines }
}

#[cfg(test)]
mod tests {
    use super::super::model::tests::sample;
    use super::super::{Hub, Key};
    use super::*;
    use std::collections::BTreeSet;

    fn hub() -> Hub {
        let mut hub = Hub::new(false);
        hub.set_snapshot(sample());
        hub
    }

    fn no_ages(_: &str) -> Option<u64> {
        None
    }

    fn draw(hub: &Hub, cols: usize, rows: usize) -> Frame {
        frame(hub, &Preview { title: "preview".into(), lines: vec!["line".into()] }, cols, rows, 0, &no_ages)
    }

    fn texts(frame: &Frame) -> Vec<String> {
        frame.lines.iter().map(Line::text).collect()
    }

    fn find<'a>(frame: &'a Frame, needle: &str) -> &'a Line {
        frame.lines.iter().find(|l| l.text().contains(needle)).unwrap_or_else(|| panic!("no line with {needle:?}"))
    }

    #[test]
    fn no_line_is_wider_than_its_area() {
        for (cols, rows) in [(160, 45), (100, 30), (70, 30), (50, 12), (24, 8)] {
            let mut hub = hub();
            for step in 0..3 {
                let frame = draw(&hub, cols, rows);
                for line in &frame.lines {
                    assert!(line.text().chars().count() <= line.width, "{cols}x{rows} step {step}: {:?}", line.text());
                    assert!(line.x + line.width <= cols, "{cols}x{rows}: line starts at {} with width {}", line.x, line.width);
                    assert!(line.y < rows, "{cols}x{rows}: line at row {}", line.y);
                }
                hub.handle_key(if step == 0 { Key::Esc } else { Key::Char('?') });
            }
        }
    }

    #[test]
    fn the_hint_names_what_enter_does_and_shows_only_this_modes_keys() {
        let mut hub = hub();
        let insert = draw(&hub, 120, 30);
        let hint = insert.lines.last().unwrap().text();
        assert!(hint.contains("⏎ attach globex"), "{hint}");
        assert!(hint.contains("esc normal") && !hint.contains("dd remove"), "{hint}");

        hub.handle_key(Key::Esc);
        let normal = draw(&hub, 120, 30);
        let hint = normal.lines.last().unwrap().text();
        assert!(hint.contains("dd remove") && !hint.contains("esc normal"), "{hint}");
    }

    #[test]
    fn the_prompt_and_cursor_signal_the_mode() {
        let mut hub = hub();
        hub.handle_key(Key::Char('c'));
        let insert = draw(&hub, 120, 30);
        assert_eq!(insert.lines[1].text(), " ❯ c");
        assert_eq!(insert.cursor, Some((4, 1)), "the cursor follows the text");

        hub.handle_key(Key::Esc);
        let normal = draw(&hub, 120, 30);
        assert_eq!(normal.lines[1].text(), " NORMAL › c", "the filter stays visible");
        assert_eq!(normal.cursor, None, "no text cursor in normal mode");
    }

    #[test]
    fn rows_show_sections_folds_and_where_you_are() {
        let hub = hub();
        let frame = draw(&hub, 120, 30);
        let lines = texts(&frame);
        assert!(lines.iter().any(|l| l == " Running"));
        assert!(lines.iter().any(|l| l == " Saved"));
        assert!(lines.iter().any(|l| l == " Projects"));
        assert!(find(&frame, "acme  you are here").text().starts_with(" ▸ ● acme"));
        assert!(find(&frame, "○ initech").text().starts_with("   ○ initech"), "saved sessions have no fold marker");
        assert!(find(&frame, "globex").selected, "the cursor row is marked");
        assert_eq!(frame.lines.iter().filter(|l| l.selected).count(), 1);
    }

    #[test]
    fn session_rows_carry_counts_ages_and_markers_at_the_right_edge() {
        let mut snapshot = sample();
        snapshot.sessions[0].tabs[0].attention = 2;
        snapshot.sessions[0].tabs[0].working = true;
        let mut hub = Hub::new(false);
        hub.set_snapshot(snapshot);
        let ages = |name: &str| (name == "initech").then_some(3 * 3600);
        let frame = frame(&hub, &Preview::default(), 120, 30, 0, &ages);

        let globex = find(&frame, "● globex").text();
        assert!(globex.trim_end().ends_with("⟳ ⚑2 1 tab"), "{globex:?}");
        assert!(find(&frame, "○ initech").text().trim_end().ends_with("saved 3h"));
        assert!(find(&frame, "acme  you").text().trim_end().ends_with("2 tabs"));
    }

    #[test]
    fn tab_rows_show_attention_too() {
        let mut snapshot = sample();
        snapshot.sessions[0].tabs[0].attention = 1;
        let mut hub = Hub::new(false);
        hub.set_snapshot(snapshot);
        hub.handle_key(Key::Esc);
        hub.handle_key(Key::Char('l'));
        let frame = draw(&hub, 120, 30);
        assert!(find(&frame, "globex-time").text().trim_end().ends_with("⚑1"));
    }

    #[test]
    fn the_preview_goes_right_below_or_away_with_the_size() {
        assert_eq!(preview_place(160, 40, true), PreviewPlace::Right);
        assert_eq!(preview_place(70, 40, true), PreviewPlace::Below);
        assert_eq!(preview_place(70, 20, true), PreviewPlace::Hidden);
        assert_eq!(preview_place(160, 40, false), PreviewPlace::Hidden);

        let hub = hub();
        let wide = draw(&hub, 160, 40);
        let title = find(&wide, "preview");
        assert!(title.x > 44 && title.y == 3, "to the right of the list");

        let narrow = draw(&hub, 70, 40);
        let title = find(&narrow, "preview");
        assert!(title.x == 0 && title.y > 3, "below the list");

        assert!(!texts(&draw(&hub, 70, 20)).iter().any(|l| l.contains("preview")));
    }

    #[test]
    fn overlays_take_over_the_prompt_notice_and_hint_lines() {
        let mut hub = hub();
        hub.handle_key(Key::Esc);

        hub.handle_key(Key::Char('o'));
        hub.handle_key(Key::Char('x'));
        let prompt = draw(&hub, 120, 30);
        assert_eq!(prompt.lines[1].text(), " New (a folder, or a name): x");
        assert_eq!(prompt.cursor, Some((29, 1)));
        assert!(prompt.lines.last().unwrap().text().contains("esc cancel"));
        hub.handle_key(Key::Esc);

        hub.handle_key(Key::Char('j'));
        hub.handle_key(Key::Char('d'));
        hub.handle_key(Key::Char('d'));
        let confirm = draw(&hub, 120, 30);
        assert!(find(&confirm, "Delete the saved session initech").y == 28);
        assert!(confirm.lines.last().unwrap().text().contains("any other key cancels"));
        hub.handle_key(Key::Char('n'));

        hub.handle_key(Key::Char('?'));
        let help = draw(&hub, 120, 30);
        assert!(texts(&help).iter().any(|l| l.contains("one step down")));
        assert!(!texts(&help).iter().any(|l| l.contains("● globex")), "the help replaces the list");
    }

    #[test]
    fn a_notice_shows_above_the_hint() {
        let mut hub = hub();
        hub.handle_key(Key::Esc);
        hub.handle_key(Key::Char('G'));
        hub.handle_key(Key::Char('d'));
        hub.handle_key(Key::Char('d'));
        assert_eq!(find(&draw(&hub, 120, 30), "not a session").y, 28);
    }

    #[test]
    fn scrolling_keeps_the_cursor_and_its_header_visible() {
        let rows = model::build_rows(&sample(), "", &BTreeSet::new());
        // 0 #Running 1 acme 2 globex 3 #Saved 4 initech 5 old-client 6 #Projects 7.. projects
        assert_eq!(scroll_for(&rows, Some(2), 0, 4), 0, "already visible");
        assert_eq!(scroll_for(&rows, Some(5), 0, 4), 2, "scrolls down just enough");
        assert_eq!(scroll_for(&rows, Some(4), 6, 4), 3, "scrolling up onto a section's first row shows its header");
        assert_eq!(scroll_for(&rows, None, 3, 4), 0);
    }

    #[test]
    fn the_list_scrolls_in_the_frame() {
        let mut hub = hub();
        hub.handle_key(Key::Esc);
        hub.handle_key(Key::Char('G'));
        let scroll = scroll_for(hub.rows(), hub.selected_index(), 0, 4);
        let frame = frame(&hub, &Preview::default(), 60, 9, scroll, &no_ages);
        assert_eq!(frame.list_height, 4);
        assert!(find(&frame, "sentinel").selected);
        assert!(!texts(&frame).iter().any(|l| l.contains("globex")), "rows above the window are not drawn");
    }

    #[test]
    fn tiny_panes_say_so_instead_of_breaking() {
        assert_eq!(texts(&draw(&hub(), 15, 4)), ["Too small"]);
    }

    #[test]
    fn projects_and_create_rows_are_described_in_full() {
        let rows = model::build_rows(&sample(), "", &BTreeSet::new());
        let project = rows.iter().find(|r| matches!(&r.kind, RowKind::Project { rel, .. } if rel == "acme/api-agent")).unwrap();
        let preview = describe(project);
        assert_eq!(preview.title, "acme/api-agent");
        assert_eq!(preview.lines[0], "Enter: new tab in acme");
        assert!(preview.lines.contains(&"Session  acme (running)".to_owned()));
        assert!(preview.lines.contains(&"Tab      api-agent".to_owned()));
        assert!(preview.lines.contains(&"Folder   C:/Projects/acme/api-agent".to_owned()));

        let create = Row { kind: RowKind::Create { name: "foo".into() }, attention: 0, working: false };
        assert_eq!(describe(&create).lines[0], "Enter: create \"foo\"");
    }
}
