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
#   in_client              true when running inside a tmux/psmux client
#   current_session        REPLY: the session the popup was opened from
#   ago SECONDS_SINCE_EPOCH  print "now", "5m", "3h" or "2d" ("new" when
#                          empty: a session never attached)

us=$'\x1f'

if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    win=1
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
# have no spaces to quote.
fzf_callbacks() {
    if ((win)); then
        FZF_SHELL='cmd.exe /d /c'
        SELF="$(cygpath -d "$BASH") $(cygpath -d "$1")"
    else
        FZF_SHELL='bash -c'
        printf -v SELF 'bash %q' "$1"
    fi
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
