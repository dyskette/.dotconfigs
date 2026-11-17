#!/usr/bin/env bash
# For a session started from a plain terminal (a numeric default name): pick a
# project the way prefix s does (project-picker.sh), move to its session, and
# drop the numbered one. tmux runs this from the after-new-session hook
# (tmux.conf); psmux from its client-attached hook, through
# first-session-directory.ps1 (psmux.conf).
set -u
here="${BASH_SOURCE[0]%[\\/]*}"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

current_session
cur="$REPLY"
[[ "$cur" =~ ^[0-9]+$ ]] || exit 0

name="$("$BASH" "$here/project-picker.sh" --print)"
[[ -n "$name" ]] || exit 0

# "=": exact names, so session 0 never matches 01.
switch_to "$name"
if [[ "$name" != "$cur" ]]; then
    "$mux" kill-session -t "=$cur"
fi
