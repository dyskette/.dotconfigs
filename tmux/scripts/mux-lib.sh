# Sessions for tmux (Linux) and psmux (Windows, run by Git Bash), shared by
# every script in this folder. Source it.
#
# Platform
#   win          1 under Git Bash on Windows, 0 elsewhere
#   sep          the path separator
#   mux          the multiplexer CLI: psmux or tmux
#   home         the user's home folder, in the platform's own form
#   us           the unit separator (\x1f) between fields of a -F format: a
#                tab is IFS whitespace, so read would merge empty fields
#
# Helpers
#   fzf_callbacks SCRIPT     FZF_SHELL (for --with-shell) and SELF (the
#                            command that runs SCRIPT from an fzf binding)
#   new_state_file NAME      REPLY: a new empty file for a popup's state
#   ago SECONDS_SINCE_EPOCH  print "now", "5m", "3h" or "2d" ("new" when
#                            empty: a session never attached)
#   normdir DIR              REPLY: DIR with one trailing separator
#   parent DIR               REPLY: the folder above DIR
#   command_line WORD...     REPLY: the words as one line for a pane's shell
#
# Sessions
#   in_client                true inside a tmux/psmux client
#   current_session          REPLY: the session this process belongs to
#   session_for DIR [NAME]   REPLY: the session for DIR; session_kind:
#                            existing or new
#   ensure_session DIR [NAME]  REPLY: that session, built when new
#   open_session DIR [NAME]    ensure_session, then switch or attach to it
#
# Slots: the windows every session is built with (see build_session)
#   slot_window SESSION NAME   REPLY: the index of SESSION's window NAME
#   slot_start SESSION INDEX [COMMAND]  start a slot's tool, or COMMAND
#   editor_address SESSION     REPLY: where SESSION's nvim listens
#
# Everything a popup runs before fzf draws delays the popup, and under Git Bash
# each fork costs 20-40 ms, so the helpers here fork as little as they can.

us=$'\x1f'

if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    win=1
    # Started as usr\bin\bash.exe (psmux.conf) rather than through Git's
    # bin\bash.exe launcher, nothing puts /usr/bin ahead of System32, and
    # sort or find would be Windows' own.
    [[ "$PATH" == /usr/bin:* ]] || PATH="/usr/bin:$PATH"
    sep='\'
    mux=psmux
    home="$USERPROFILE"
    # Keep MSYS from rewriting the Windows paths and targets handed to psmux.
    export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
    # psmux runs a server per session, and a server keeps the environment of
    # whoever started it: TMUX and PSMUX_SESSION in a session created from
    # inside another one (tm, prefix s, prefix a), or in a run-shell job,
    # name that other session, and the CLI follows TMUX first. psmux sets
    # PSMUX_TARGET_SESSION right in panes, popups and jobs alike, so it is
    # the one to trust: the CLI routes by it once TMUX is gone.
    if [[ -n "${PSMUX_TARGET_SESSION:-}" ]]; then
        export PSMUX_SESSION="$PSMUX_TARGET_SESSION"
        unset TMUX TMUX_PANE
    fi
else
    win=0
    sep=/
    mux=tmux
    home="$HOME"
fi

# --- Helpers -----------------------------------------------------------------

# fzf.exe on Windows would try $SHELL (/usr/bin/bash, an MSYS path it cannot
# start), so its child commands go through cmd, which starts Git Bash by its
# 8.3 path: quotes do not survive fzf handing the line to cmd, and 8.3 paths
# have no spaces to quote. One cygpath converts both paths.
fzf_callbacks() {
    if ((win)); then
        local short=()
        FZF_SHELL='cmd.exe /d /c'
        mapfile -t short < <(cygpath -d "$BASH" "$1")
        SELF="${short[0]} ${short[1]}"
    else
        FZF_SHELL='bash -c'
        printf -v SELF 'bash %q' "$1"
    fi
}

# Without mktemp, which would fork: noclobber makes bash create the file with
# O_EXCL, so an existing file, or a symlink planted under a guessed name, is
# never written through; a taken name just draws another.
new_state_file() {
    local i noclobber=0
    [[ $- == *C* ]] && noclobber=1
    set -C
    for ((i = 0; i < 16; i++)); do
        REPLY="${TMPDIR:-/tmp}/$1.$$.$RANDOM"
        if { : >"$REPLY"; } 2>/dev/null; then
            ((noclobber)) || set +C
            return 0
        fi
    done
    ((noclobber)) || set +C
    REPLY=""
    return 1
}

ago() {
    if [[ -z "${1:-}" || "$1" == 0 ]]; then
        printf 'new'
        return
    fi
    local d=$((EPOCHSECONDS - $1))
    if ((d < 60)); then
        printf 'now'
    elif ((d < 3600)); then
        printf '%dm' $((d / 60))
    elif ((d < 86400)); then
        printf '%dh' $((d / 3600))
    else
        printf '%dd' $((d / 86400))
    fi
}

# REPLY: $1 with exactly one trailing separator, in the platform's style.
normdir() {
    REPLY="$1"
    ((win)) && REPLY="${REPLY//\//\\}"
    while [[ "$REPLY" == *"$sep$sep" ]]; do REPLY="${REPLY%"$sep"}"; done
    [[ "$REPLY" == *"$sep" ]] || REPLY="$REPLY$sep"
}

# REPLY: the parent folder of $1; a root is its own parent.
parent() {
    local d="${1%"$sep"}" p
    if [[ -z "$d" ]]; then REPLY=/; return; fi
    p="${d%"$sep"*}"
    if [[ "$p" == "$d" ]]; then
        normdir "$d"
    elif [[ -z "$p" ]]; then
        REPLY=/
    else
        normdir "$p"
    fi
}

# REPLY: the words as one command line for the shell a pane runs, which is
# what send-keys types into and new-window hands a command to: pwsh under
# psmux (each word single-quoted, ' doubled, behind the call operator, or
# pwsh would print a quoted program name rather than run it), a POSIX shell
# under tmux.
command_line() {
    local w
    REPLY=""
    ((win)) && REPLY="&"
    for w in "$@"; do
        if ((win)); then
            w="'${w//\'/\'\'}'"
        else
            printf -v w '%q' "$w"
        fi
        REPLY+="${REPLY:+ }$w"
    done
}

# --- Sessions ----------------------------------------------------------------

in_client() {
    [[ -n "${TMUX:-}" || -n "${PSMUX_TARGET_SESSION:-}" ]]
}

current_session() {
    if ((win)) && [[ -n "${PSMUX_SESSION:-}" ]]; then
        REPLY="$PSMUX_SESSION"
    else
        REPLY="$("$mux" display-message -p '#S' 2>/dev/null)"
    fi
}

# The session for folder $1. When one already runs there, REPLY is its name
# and session_kind is "existing". Otherwise session_kind is "new" and REPLY a
# name no other folder's session uses: $2 (a declared name) or the folder's
# own name, then parent_name, parent_name_2, ... Folders compare
# case-insensitively on Windows.
session_for() {
    local dir="${1%"$sep"}" base name prefix n path key
    [[ -z "$dir" ]] && dir=/
    if [[ -n "${2:-}" ]]; then
        base="$2"
    else
        base="${dir##*[\\/]}"
        [[ -z "$base" || "$dir" == / ]] && base=root
    fi
    base="${base//[.: ]/_}"
    normdir "$1"
    key="$REPLY"
    ((win)) && key="${key,,}"

    local -A taken=()
    while IFS=$'\t' read -r n path; do
        [[ -z "$n" ]] && continue
        normdir "$path"
        path="$REPLY"
        ((win)) && path="${path,,}"
        if [[ "$path" == "$key" ]]; then
            session_kind=existing
            REPLY="$n"
            return
        fi
        taken["$n"]=1
    done < <("$mux" list-sessions -F "#{session_name}"$'\t'"#{session_path}" 2>/dev/null)

    name="$base"
    if [[ -n "${taken[$name]:-}" ]]; then
        parent "$1"
        prefix="${REPLY%"$sep"}"
        prefix="${prefix##*[\\/]}"
        prefix="${prefix//[.: ]/_}"
        name="${prefix}_$base"
        n=2
        while [[ -n "${taken[$name]:-}" ]]; do
            name="${prefix}_${base}_$n"
            n=$((n + 1))
        done
    fi
    session_kind=new
    REPLY="$name"
}

# REPLY: the session for folder $1, built when it was not running. Held in a
# local meanwhile: building one sets REPLY on the way.
ensure_session() {
    session_for "$1" "${2:-}"
    local name="$REPLY"
    if [[ "$session_kind" == new ]]; then
        build_session "$name" "$1" || return 1
    fi
    REPLY="$name"
}

# "=" makes -t match the name exactly instead of by prefix.
open_session() {
    ensure_session "$1" "${2:-}" || return
    if in_client; then
        "$mux" switch-client -t "=$REPLY"
    else
        "$mux" attach -t "=$REPLY"
    fi
}

# --- Slots -------------------------------------------------------------------
#
# Every session gets the same windows, in this order, so prefix 1..5 is the
# only binding needed: a tool keeps its number in every session.
#
#   1 yazi   2 nvim   3 lazygit   4 agent   5 shell
#
# Each tool is typed into a shell rather than run in its place, so quitting
# the tool leaves the shell, the window and its number. When it is typed:
#
#   psmux  as the session is built (build_session): every tool starts
#          right away.
#   tmux   on the window's first visit: build_session sets the session
#          option @slot_N (N the window's index) for each tool window, and
#          @slots while any is set; the session-window-changed hook
#          (tmux.conf) runs lazy-slot.sh, whose slot_start types the command
#          and clears @slot_N. The hook only forks while @slots is set.
#
# User options are per session, not per window, because psmux 3.4.0 keeps
# them so; and the numbers hold because common.conf turns renumbering off.
#
# yazi is a window rather than a popup because a popup attaches a second
# client, and yazi wraps its terminal probe in one layer of tmux passthrough:
# the popup's own tmux unwraps it, the outer one swallows it, and yazi falls
# back from the kitty graphics protocol to chafa. In a plain window it talks
# to the terminal and shows images.
slots=(yazi nvim lazygit agent shell)

# REPLY: where session $1's nvim listens. One editor per session: the nvim
# window starts listening here, and edit.sh sends every file opened elsewhere
# in the session to it. On Windows a named pipe named after the session as it
# is, because psmux.conf's key spells the same name from
# $env:PSMUX_TARGET_SESSION; written with forward slashes, since MSYS strips
# one of the two leading backslashes of \\.\pipe\ on its way to a Windows
# program, and nvim takes either form. Elsewhere a socket in the runtime
# folder, so a login's sockets go when it does.
editor_address() {
    if ((win)); then
        REPLY="//./pipe/nvim-${1//[\\\/]/_}"
    else
        REPLY="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/nvim-${1//[^A-Za-z0-9_.-]/_}.sock"
    fi
}

# REPLY: the command slot $2 of session $1 starts, as a line for its shell;
# empty for the shell slot. psmux.conf spells the same commands for its keys.
slot_command() {
    case "$2" in
        yazi | lazygit) command_line "$2" ;;
        agent) command_line opencode ;;
        nvim)
            editor_address "$1"
            command_line nvim --listen "$REPLY"
            ;;
        *) REPLY="" ;;
    esac
}

# Session $1, with a window per slot, started in folder $2; it opens on the
# shell. On psmux every tool starts right away: its command is typed as the
# window is created (pwsh takes keys typed while it is still loading its
# profile). On tmux the windows wait for their first visit (@slot_N).
build_session() {
    local name="$1" dir="$2" i idx
    for i in "${!slots[@]}"; do
        if ((i == 0)); then
            idx="$("$mux" new-session -dP -F '#{window_index}' -s "$name" -c "$dir" -n "${slots[i]}")" || return 1
        else
            idx="$("$mux" new-window -dP -F '#{window_index}' -t "=$name:" -c "$dir" -n "${slots[i]}")" || return 1
        fi
        [[ "${slots[i]}" == shell ]] && continue
        if ((win)); then
            slot_command "$name" "${slots[i]}"
            "$mux" send-keys -t "=$name:$idx" "$REPLY" Enter
        else
            "$mux" set-option -t "=$name" "@slot_$idx" 1
        fi
    done
    ((win)) || "$mux" set-option -t "=$name" @slots 1
    "$mux" select-window -t "=$name:$idx"
}

# REPLY: the index of session $1's window named $2. Matched here rather than
# with list-windows -f, which psmux 3.4.0 ignores.
slot_window() {
    local idx n
    while IFS=$us read -r idx n; do
        if [[ "$n" == "$2" ]]; then
            REPLY="$idx"
            return 0
        fi
    done < <("$mux" list-windows -t "=$1" -F "#{window_index}${us}#{window_name}" 2>/dev/null)
    REPLY=""
    return 1
}

# Start window $2 (an index) of session $1: type its slot's command -- or $3
# -- into the shell there. Without $3 only a window still waiting for its
# first start, with $3 any window; either way it is not waiting any more.
# Fails when nothing was started.
#
# tmux's hook can run several of these at once, so the check and the start
# happen under a lock of the session's. Keys go only to a pane at a shell
# prompt: one still loading its profile shows its helpers (zoxide, fnm,
# cygpath under pwsh), so it is waited for, up to 15 s.
slot_start() {
    local s="$1" w="$2" cmd="${3:-}" i rc=1 lock
    lock="${TMPDIR:-/tmp}/slots-${s//[^A-Za-z0-9_.-]/_}.lock"
    slot_lock "$lock" || return 1
    if [[ -n "$cmd" || -n "$("$mux" show-options -t "=$s" -qv "@slot_$w" 2>/dev/null)" ]]; then
        "$mux" set-option -t "=$s" -u "@slot_$w"
        if [[ -z "$cmd" ]]; then
            slot_command "$s" "$("$mux" display-message -t "=$s:$w" -p '#{window_name}' 2>/dev/null)"
            cmd="$REPLY"
        fi
        for ((i = 0; i < 75; i++)); do
            case "$("$mux" display-message -t "=$s:$w" -p '#{pane_current_command}' 2>/dev/null)" in
                bash | sh | zsh | fish | pwsh | powershell | cmd) break ;;
                "") i=75 ;; # the window is gone
            esac
            sleep 0.2
        done
        ((i < 75)) && [[ -n "$cmd" ]] && "$mux" send-keys -t "=$s:$w" "$cmd" Enter && rc=0
        # The hook's filter: off once no window waits.
        "$mux" show-options -t "=$s" 2>/dev/null | grep -q '^@slot_' || "$mux" set-option -t "=$s" -u @slots
    fi
    rmdir "$lock" 2>/dev/null
    return "$rc"
}

# Take lock $1, a folder: mkdir is atomic. One left behind by a job that was
# killed is taken over after 10 s.
slot_lock() {
    local i
    for ((i = 0; i < 50; i++)); do
        mkdir "$1" 2>/dev/null && return 0
        sleep 0.2
    done
    rmdir "$1" 2>/dev/null
    mkdir "$1" 2>/dev/null
}