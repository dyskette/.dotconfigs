//! Requests the hub leaves for the pilot of another session.
//!
//! Some of the hub's effects can only happen in the session the client
//! arrives in, after it arrived: adding a tab there (a session nobody is
//! attached to has no size to lay a tab out in), or stopping the session the
//! client just left. The hub's own instance stays behind in the old session,
//! so it writes the request to the plugin's cache folder, which every
//! session's instances share, and the pilot there carries it out when its
//! client shows up.

use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

/// Requests wait here, one file per target session.
const FOLDER: &str = "/cache/pending";

/// A request not picked up within this many seconds is dropped: the switch
/// it belonged to did not happen, and it must not fire on a later visit.
const MAX_AGE_SECS: u64 = 30;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Request {
    /// Add the tab this layout describes and focus it.
    NewTab { layout: String },
    /// Stop this session (it stays saved).
    Kill { session: String },
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// The file format: a header line `<unix seconds> tab` or `<unix seconds>
/// kill <session>`, and for a tab the layout on the lines after it.
fn encode(request: &Request, at: u64) -> String {
    match request {
        Request::NewTab { layout } => format!("{at} tab\n{layout}"),
        Request::Kill { session } => format!("{at} kill {session}\n"),
    }
}

/// The request in a file's text, unless it is malformed or was left more
/// than `MAX_AGE_SECS` before `at`.
fn decode(text: &str, at: u64) -> Option<Request> {
    let (header, body) = text.split_once('\n').unwrap_or((text, ""));
    let mut words = header.split_whitespace();
    let left_at: u64 = words.next()?.parse().ok()?;
    if at.saturating_sub(left_at) > MAX_AGE_SECS {
        return None;
    }
    match (words.next()?, words.next()) {
        ("tab", None) if !body.trim().is_empty() => Some(Request::NewTab { layout: body.to_owned() }),
        ("kill", Some(session)) => Some(Request::Kill { session: session.to_owned() }),
        _ => None,
    }
}

fn file_for(session: &str) -> String {
    format!("{FOLDER}/{session}")
}

/// Leave a request for the pilot of `session`, replacing an earlier one.
pub fn leave(session: &str, request: &Request) -> std::io::Result<()> {
    fs::create_dir_all(FOLDER)?;
    fs::write(file_for(session), encode(request, now()))
}

/// Take the request left for `session`, if there is a fresh one. The file
/// is removed either way, so a request runs at most once.
pub fn take(session: &str) -> Option<Request> {
    let file = file_for(session);
    let text = fs::read_to_string(&file).ok()?;
    let _ = fs::remove_file(&file);
    decode(&text, now())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requests_survive_the_round_trip() {
        let tab = Request::NewTab { layout: "layout {\n    tab name=\"x\"\n}\n".into() };
        assert_eq!(decode(&encode(&tab, 100), 105), Some(tab));

        let kill = Request::Kill { session: "acme".into() };
        assert_eq!(decode(&encode(&kill, 100), 100), Some(kill));
    }

    #[test]
    fn stale_requests_are_dropped() {
        let kill = Request::Kill { session: "acme".into() };
        assert_eq!(decode(&encode(&kill, 100), 100 + MAX_AGE_SECS + 1), None);
        assert!(decode(&encode(&kill, 100), 100 + MAX_AGE_SECS).is_some());
    }

    #[test]
    fn malformed_requests_are_ignored() {
        for text in ["", "tab\nlayout", "100", "100 tab\n", "100 tab\n   \n", "100 kill", "100 dance now", "x kill a"] {
            assert_eq!(decode(text, 100), None, "{text:?}");
        }
    }
}
