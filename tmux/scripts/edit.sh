#!/usr/bin/env bash
# Open files in the session's nvim, from any window of it: lazygit's e, yazi,
# the shell, an agent.
#
#   edit.sh FILE[:LINE[:COL]]...   open the files, at the line when given
#   edit.sh -l LINE FILE...        the same, with the line apart (lazygit)
#   edit.sh socket                 print this session's nvim address
#
# One editor per session: the nvim window listens on the session's socket
# (session_socket, mux-lib.sh), so a file opened anywhere in the session
# lands there instead of starting a second nvim, and that window comes
# forward. In order:
#
#   $NVIM set    the nvim this terminal runs in -- yazi in nvim's float, or
#                anything started from :terminal; it opens there, as
#                flatten.nvim does for a nested `nvim`
#   socket live  the session's editor
#   no editor    the nvim window is told to start one and the files follow;
#                with no such window (outside the slot layout, psmux,
#                outside tmux) nvim runs here, in the pane that asked
#
# Blocking edits -- a commit message, an agent's prompt file -- must not come
# through here: the caller waits for the editor to exit, and a remote open
# returns at once. Those keep plain `nvim` ($EDITOR, lazygit's editPreset).
set -u
here="${BASH_SOURCE[0]%[\\/]*}"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

line=""
if [[ "${1:-}" == -l ]]; then
    line="${2:-}"
    shift 2
fi

# The session the pane belongs to; popup.sh's sessions (psmux) share the
# editor of the session they were opened from.
session_sock() {
    local name
    current_session
    name="$REPLY"
    [[ -z "$name" ]] && return 1
    [[ "$name" =~ ^popup_[^_]+_(.+)$ ]] && name="${BASH_REMATCH[1]}"
    session_socket "$name"
}

if [[ "${1:-}" == socket ]]; then
    session_sock && printf '%s\n' "$REPLY"
    exit $?
fi

files=("$@")
# One argument carrying its position (grep, stack traces, tmux hint plugins).
if [[ ${#files[@]} -eq 1 && "${files[0]}" =~ ^(.+):([0-9]+)(:[0-9]+)?$ && -e "${BASH_REMATCH[1]}" ]]; then
    [[ -z "$line" ]] && line="${BASH_REMATCH[2]}"
    files=("${BASH_REMATCH[1]}")
fi

# Absolute, because the editor resolves a relative name against its own
# folder -- the session's -- and the caller is somewhere else more often
# than not (yazi in a subfolder, lazygit at the repo root).
for i in "${!files[@]}"; do
    files[i]="$(readlink -f -- "${files[i]}" 2>/dev/null)" || files[i]="${files[i]}"
done

# The command line that starts the session's editor on the files.
editor_command() {
    printf -v REPLY 'nvim --listen %q' "${sock:?}"
    [[ -n "$line" ]] && REPLY+=" +$line"
    local f
    for f in "${files[@]}"; do
        printf -v REPLY '%s %q' "$REPLY" "$f"
    done
}

# Run nvim here, when there is a terminal to run it in: called from a shell,
# or from a tool that hands its terminal over while it waits.
run_here() {
    local args=()
    [[ -n "$line" ]] && args+=("+$line")
    [[ -n "${sock:-}" ]] && args+=(--listen "$sock")
    exec nvim "${args[@]}" ${files[0]+--} "${files[@]}"
}

# Nowhere to put an editor and no terminal to be one in.
give_up() {
    printf 'edit.sh: no editor to open %s in\n' "${files[*]:-the file}" >&2
    exit 1
}

sock=""
target="${NVIM:-}"
if [[ -z "$target" ]] && ((!win)) && [[ -n "${TMUX:-}" ]] && session_sock; then
    sock="$REPLY"
    [[ -S "$sock" ]] && target="$sock"
fi
# Outside tmux there is no session editor to reach: be one, when whoever
# called left a terminal to be it in.
if [[ -z "$target" && -z "$sock" ]]; then
    [[ -t 0 ]] && run_here
    give_up
fi

# REPLY: the window the editor lives in, by the name the layout gives it
# (mux-lib.sh). Asking nvim where it runs would be more general, but a
# remote nvim client with a terminal on its stdout writes the terminal's
# setup there -- harmless noise that is not a pane id.
editor_window() {
    REPLY="$("$mux" list-windows -F '#{window_id}' -f '#{==:#{window_name},nvim}' 2>/dev/null | head -1)"
    [[ -n "$REPLY" ]]
}

# Show the editor's window.
focus_editor() {
    if ((!win)) && [[ -n "${TMUX:-}" ]] && editor_window; then
        "$mux" select-window -t "$REPLY"
    fi
}

# No editor yet: start one in the nvim window, with the files on its command
# line. The window is a shell at this point (lazy-slot.sh has not been
# there), so the command is simply typed into it -- and the files go with
# it rather than being sent after, because an editor still working through
# its plugins takes the request and then moves the cursor itself, leaving
# the file open at line 1.
if [[ -z "$target" ]]; then
    editor_command
    cmd="$REPLY"
    if [[ -n "${sock:-}" ]] && editor_window; then
        win_id="$REPLY"
        "$mux" set-option -wu -t "$win_id" @lazy 2>/dev/null
        "$mux" send-keys -t "$win_id" "$cmd" Enter
    elif [[ -n "${sock:-}" ]]; then
        # In a session without the layout's nvim window: give it one, which
        # the rest of the session then opens its files in too.
        "$mux" new-window -d -n nvim -c "$PWD" "$cmd" || run_here
    elif [[ -t 0 ]]; then
        run_here
    else
        give_up
    fi
    focus_editor
    exit 0
fi

# --remote drops the file into the editor's current window, which may be a
# terminal or a float (toggleterm's <C-\>, plugins/terminal.lua): move to an
# ordinary window first, when the editor has one.
# The terminal belongs to whoever called (yazi hands it over while it waits),
# and a remote nvim client that finds one on its stdout draws on it: these
# are RPC calls, so they get no terminal at all.
remote() {
    nvim --server "$target" "$@" </dev/null >/dev/null 2>&1
}

to_normal_window='for w in range(1,winnr("$")) | if getbufvar(winbufnr(w),"&buftype") == "" | exe w."wincmd w" | break | endif | endfor'
remote --remote-expr "execute('$to_normal_window')"

# No "--" here: --remote-silent takes everything after it as file names, and
# would open a file called "--".
[[ ${#files[@]} -gt 0 ]] && remote --remote-silent "${files[@]}"
# --remote takes the rest of the command line as files, so the line is a
# second call: nvim's own "+LINE" is not implemented for --remote. An
# expression, not --remote-send: sent keys go through the editor's mappings,
# where <C-\> belongs to toggleterm (plugins/terminal.lua).
[[ -n "$line" ]] && remote --remote-expr "execute('normal! ${line}Gzz')"

# Bring the editor forward, unless it is the nvim this terminal runs in --
# there the file is already in front of whoever asked.
[[ "$target" != "${NVIM:-}" ]] && focus_editor
exit 0
