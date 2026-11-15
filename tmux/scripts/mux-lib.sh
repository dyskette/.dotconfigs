# Platform bits shared by the popup scripts that run on both tmux (Linux) and
# psmux (Windows, under Git Bash). Source it; it defines:
#
#   win        1 under Git Bash on Windows, 0 elsewhere
#   sep        the path separator
#   mux        the multiplexer CLI: psmux or tmux
#   home       the user's home folder, in the platform's own form
#   us         the unit separator (\x1f) between fields of a -F format: a tab
#              is IFS whitespace, so read would merge the empty fields around it
#
#   fzf_callbacks SCRIPT   set FZF_SHELL (for --with-shell) and SELF (the
#                          command that runs SCRIPT from an fzf binding)
#   new_state_file NAME    REPLY: a new empty file for a popup's state
#
# Everything a popup runs before fzf draws delays the popup, and under Git Bash
# each fork costs 20-40 ms, so the helpers here fork as little as they can.
#   in_client              true when running inside a tmux/psmux client
#   current_session        REPLY: the session the popup was opened from
#   ago SECONDS_SINCE_EPOCH  print "now", "5m", "3h" or "2d" ("new" when
#                          empty: a session never attached)

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
    # psmux runs a server per session, and a session's server keeps the
    # environment of whoever started it: one created from inside another
    # session (tm, prefix a, prefix S) carries that session's TMUX, which the
    # CLI follows ahead of the PSMUX_TARGET_SESSION psmux sets for each popup.
    # "switch-client" would then move the other session's client instead, so
    # in a popup only PSMUX_TARGET_SESSION is left to route the CLI.
    if [[ -n "${PSMUX_POPUP:-}" && -n "${PSMUX_TARGET_SESSION:-}" ]]; then
        unset TMUX TMUX_PANE
    fi
else
    win=0
    sep=/
    mux=tmux
    home="$HOME"
fi

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

in_client() {
    [[ -n "${TMUX:-}" || -n "${PSMUX_POPUP:-}" ]]
}

# psmux runs a server per session, and a CLI call without -t from a popup
# can answer for another session (the most recently attached), so psmux's
# own note of the popup's session is used instead.
current_session() {
    if ((win)) && [[ -n "${PSMUX_SESSION:-}" ]]; then
        REPLY="$PSMUX_SESSION"
    else
        REPLY="$("$mux" display-message -p '#S' 2>/dev/null)"
    fi
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
