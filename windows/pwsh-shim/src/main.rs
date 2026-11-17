//! A `pwsh.exe` stand-in for psmux 3.4.0, which runs every popup command as
//! `pwsh -NoProfile -Command <cmd>` (about 400 ms of PowerShell startup before
//! anything shows). Built and installed in ~/.local/opt/pwsh-shim by
//! windows/Install-PwshShim.ps1; the PowerShell profile puts that folder first
//! on PATH, so psmux servers started from it find this pwsh first.
//!
//! When `<cmd>` is a plain program call, `& "program" args...`, the program is
//! started directly as a child of this process, so it inherits the popup's
//! console, and this process waits for it and returns its exit code.
//! Everything else is handed, unchanged, to the real pwsh found further down
//! PATH.
//!
//! What counts as a plain call: the call operator `&`, then words that are
//! bare (no PowerShell metacharacters), 'single-quoted' (literal, '' for '),
//! or "double-quoted" with no backtick and no `$` other than `$env:NAME`,
//! `${env:NAME}` and `$HOME`. The program must resolve to an .exe or .com.
//!
//! PWSH_SHIM_LOG=<file> appends one line per run: the decision and timings.

use std::env;
use std::ffi::OsString;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::Instant;

#[link(name = "kernel32")]
extern "system" {
    fn SetConsoleCtrlHandler(handler: *const core::ffi::c_void, add: i32) -> i32;
}

fn main() -> ExitCode {
    let t0 = Instant::now();
    let args: Vec<OsString> = env::args_os().skip(1).collect();

    let plan = command_text(&args).and_then(|cmd| parse_call(&cmd).map(|c| (cmd, c)));
    // Ctrl+C belongs to the program in the console; this process only waits.
    unsafe {
        SetConsoleCtrlHandler(std::ptr::null(), 1);
    }

    match plan {
        Some((cmd, (program, rest))) => match resolve_program(&program) {
            Some(exe) => {
                let mut child = match Command::new(&exe).args(&rest).spawn() {
                    Ok(c) => c,
                    Err(e) => {
                        log(&format!("direct-spawn-failed {e}: {cmd}"));
                        return forward(&args, t0, "after a failed direct spawn");
                    }
                };
                log(&format!("direct spawned-after={}us exe={} cmd={cmd}", t0.elapsed().as_micros(), exe.display()));
                let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(1);
                ExitCode::from(code as u8)
            }
            None => forward(&args, t0, &format!("program not found: {program}")),
        },
        None => forward(&args, t0, "not a plain call"),
    }
}

/// The text after -Command, when the arguments are only the flags psmux and
/// its run-shell use before it.
fn command_text(args: &[OsString]) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        let a = args[i].to_str()?;
        match a.to_ascii_lowercase().as_str() {
            "-noprofile" | "-nologo" | "-noninteractive" => i += 1,
            "-command" | "-c" => {
                let rest: Vec<&str> = args[i + 1..].iter().map(|s| s.to_str()).collect::<Option<_>>()?;
                return if rest.is_empty() { None } else { Some(rest.join(" ")) };
            }
            _ => return None,
        }
    }
    None
}

/// `& word word...` into the program and its arguments; None for anything
/// that is not a plain call.
fn parse_call(cmd: &str) -> Option<(String, Vec<String>)> {
    let words = split_words(cmd.trim())?;
    let mut it = words.into_iter();
    if it.next()?.as_str() != "&" {
        return None;
    }
    let program = it.next()?;
    Some((program, it.collect()))
}

fn split_words(s: &str) -> Option<Vec<String>> {
    let chars: Vec<char> = s.chars().collect();
    let mut words = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_whitespace() {
            i += 1;
            continue;
        }
        let mut word = String::new();
        while i < chars.len() && !chars[i].is_whitespace() {
            match chars[i] {
                '\'' => {
                    i += 1;
                    loop {
                        let c = *chars.get(i)?;
                        if c == '\'' {
                            if chars.get(i + 1) == Some(&'\'') {
                                word.push('\'');
                                i += 2;
                                continue;
                            }
                            i += 1;
                            break;
                        }
                        word.push(c);
                        i += 1;
                    }
                }
                '"' => {
                    i += 1;
                    let mut raw = String::new();
                    loop {
                        let c = *chars.get(i)?;
                        if c == '"' {
                            i += 1;
                            break;
                        }
                        if c == '`' {
                            return None;
                        }
                        raw.push(c);
                        i += 1;
                    }
                    word.push_str(&expand(&raw)?);
                }
                '&' if word.is_empty() && words.is_empty() => {
                    word.push('&');
                    i += 1;
                    if i < chars.len() && !chars[i].is_whitespace() {
                        return None;
                    }
                }
                c if "$(){}@;|<>,`#&".contains(c) => return None,
                c => {
                    word.push(c);
                    i += 1;
                }
            }
        }
        words.push(word);
    }
    Some(words)
}

/// Expand `$env:NAME`, `${env:NAME}` and `$HOME` in double-quoted text; None
/// for any other `$`.
fn expand(raw: &str) -> Option<String> {
    let mut out = String::new();
    let mut rest = raw;
    while let Some(pos) = rest.find('$') {
        out.push_str(&rest[..pos]);
        let tail = &rest[pos..];
        let (name, used) = if let Some(t) = tail.strip_prefix("${env:") {
            let end = t.find('}')?;
            (t[..end].to_string(), 6 + end + 1)
        } else if let Some(t) = tail.strip_prefix("$env:") {
            let end = t.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).unwrap_or(t.len());
            if end == 0 {
                return None;
            }
            (t[..end].to_string(), 5 + end)
        } else if tail.len() >= 5 && tail[..5].eq_ignore_ascii_case("$HOME")
            && !tail[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_')
        {
            ("USERPROFILE".to_string(), 5)
        } else {
            return None;
        };
        out.push_str(&env::var(&name).unwrap_or_default());
        rest = &tail[used..];
    }
    out.push_str(rest);
    Some(out)
}

/// The .exe or .com the program names: a path, or a name searched on PATH.
fn resolve_program(program: &str) -> Option<PathBuf> {
    let p = Path::new(program);
    let has_dir = program.contains('\\') || program.contains('/');
    let candidates = |base: &Path| -> Option<PathBuf> {
        let ext = base.extension().map(|e| e.to_ascii_lowercase());
        if matches!(ext.as_deref().and_then(|e| e.to_str()), Some("exe") | Some("com")) {
            return base.is_file().then(|| base.to_path_buf());
        }
        if ext.is_some() {
            return None; // .ps1, .cmd, ...: PowerShell's business
        }
        for e in ["exe", "com"] {
            let c = base.with_extension(e);
            if c.is_file() {
                return Some(c);
            }
        }
        None
    };
    if has_dir {
        return candidates(p);
    }
    let me = env::current_exe().ok().and_then(|m| m.parent().map(Path::to_path_buf));
    for dir in env::split_paths(&env::var_os("PATH")?) {
        if me.as_deref() == Some(dir.as_path()) {
            continue;
        }
        if let Some(found) = candidates(&dir.join(program)) {
            return Some(found);
        }
    }
    None
}

/// Run the real pwsh with the same arguments: the next pwsh.exe on PATH after
/// this one's folder, or PWSH_SHIM_REAL.
fn forward(args: &[OsString], t0: Instant, why: &str) -> ExitCode {
    let real = env::var_os("PWSH_SHIM_REAL").map(PathBuf::from).or_else(|| {
        let me = env::current_exe().ok()?;
        let me_dir = me.parent()?.to_path_buf();
        env::split_paths(&env::var_os("PATH")?)
            .filter(|d| *d != me_dir)
            .map(|d| d.join("pwsh.exe"))
            .find(|c| c.is_file())
    });
    let Some(real) = real else {
        log(&format!("forward FAILED (no real pwsh found), {why}"));
        return ExitCode::from(1);
    };
    log(&format!("forward after={}us ({why}) to {} args={:?}", t0.elapsed().as_micros(), real.display(), args));
    match Command::new(&real).args(args).status() {
        Ok(s) => ExitCode::from(s.code().unwrap_or(1) as u8),
        Err(_) => ExitCode::from(1),
    }
}

fn log(line: &str) {
    let Some(path) = env::var_os("PWSH_SHIM_LOG") else { return };
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);
        let _ = writeln!(f, "{now:.3} pid={} {line}", std::process::id());
    }
}
