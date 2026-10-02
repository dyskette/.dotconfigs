#!/usr/bin/env bash
# Session switcher for tmux and psmux (run by Git Bash on Windows).
#
#   session-switcher.sh              run the switcher (from a popup)
#   session-switcher.sh preview N    called back by fzf for item N
#   session-switcher.sh kill N
#
# Lists the other sessions, most recently used first, so Enter right away
# flips back to the previous one. The preview names each window by its title
# and shows the active window's screen.
set -u
export LC_ALL=C.UTF-8
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

prompt='session ❯ '

# Write the items file and print it. Fields: name, shown text.
cmd_list() {
    local cur last name windows attached width=0 row
    local -a rows=()
    current_session
    cur="$REPLY"

    while IFS=$us read -r last name windows attached; do
        [[ -z "$name" || "$name" == "$cur" ]] && continue
        ((${#name} > width)) && width=${#name}
        rows+=("$last$us$name$us$windows$us$attached")
    done < <("$mux" list-sessions -F "#{session_last_attached}${us}#{session_name}${us}#{session_windows}${us}#{session_attached}" 2>/dev/null |
        sort -t"$us" -k1,1rn)

    : >"$SWITCH_STATE/items"
    for row in "${rows[@]}"; do
        IFS=$us read -r last name windows attached <<<"$row"
        local mark=""
        ((attached > 0)) && mark=$' \e[33m● attached\e[0m'
        printf '%s\t%-*s  \e[2m%2d window%s · %s\e[0m%s\n' "$name" "$width" "$name" \
            "$windows" "$( ((windows == 1)) && printf ' ' || printf s)" "$(ago "$last")" "$mark" \
            >>"$SWITCH_STATE/items"
    done
    cat "$SWITCH_STATE/items"
}

# REPLY: the session name of item $1.
item() {
    local i=0 line
    REPLY=""
    [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
    while IFS= read -r line; do
        if ((i == $1)); then
            REPLY="${line%%$'\t'*}"
            return 0
        fi
        i=$((i + 1))
    done <"$SWITCH_STATE/items"
    return 1
}

# The session's folder and windows (by title, as the status bar shows them),
# then the active window's screen.
cmd_preview() {
    item "${1:-}" || return 0
    local name="$REPLY" path idx active auto wname title
    read -r path < <("$mux" display-message -t "=$name:" -p '#{session_path}' 2>/dev/null)
    printf '\e[1m%s\e[0m \e[2m· %s\e[0m\n' "$name" "$path"
    while IFS=$us read -r idx active auto wname title; do
        [[ "$auto" == off || "$auto" == 0 || -z "$title" ]] && title="$wname"
        if [[ "$active" == 1 ]]; then
            printf '  \e[33m%s ● %s\e[0m\n' "$idx" "$title"
        else
            printf '  \e[2m%s\e[0m   %s\n' "$idx" "$title"
        fi
    done < <("$mux" list-windows -t "=$name" -F "#{window_index}${us}#{window_active}${us}#{automatic-rename}${us}#{window_name}${us}#{pane_title}" 2>/dev/null)
    printf '\e[2m%*s\e[0m\n' "${FZF_PREVIEW_COLUMNS:-40}" '' | tr ' ' '─'
    "$mux" capture-pane -p -e -t "=$name:" 2>/dev/null
}

# Bound with transform, and pressed twice, since a session can hold hours of
# work: the first ctrl-x only turns the prompt into the question, the second,
# with the prompt still asking, kills. The focus binding restores the prompt
# when the cursor moves, so both presses are always on the same session.
# (A y/N read would need a console, which fzf.exe does not give execute.)
cmd_kill() {
    item "${1:-}" || return 0
    local name="$REPLY"
    if [[ "${FZF_PROMPT:-}" != kill* ]]; then
        printf 'change-prompt:kill %s? ctrl-x again ❯ ' "$name"
        return 0
    fi
    "$mux" kill-session -t "=$name" 2>/dev/null
    printf 'reload-sync(%s list)+change-prompt:%s' "$SWITCH_SELF" "$prompt"
}

fail() {
    printf '\e[31m%s\e[0m\n' "$*"
    read -r -p 'Press Enter to close' _
}

run() {
    local out name err
    SWITCH_STATE="$(mktemp -d)"
    export SWITCH_STATE
    trap 'rm -rf "$SWITCH_STATE"' EXIT
    fzf_callbacks "$0"
    export SWITCH_SELF="$SELF"

    out="$(cmd_list | fzf \
        --with-shell "$FZF_SHELL" \
        --ansi --reverse --border none --info inline-right \
        --delimiter $'\t' --with-nth 2 \
        --header 'enter switch · ctrl-x twice: kill' \
        --prompt "$prompt" \
        --bind "ctrl-x:transform($SELF kill {n})" \
        --bind "focus:change-prompt($prompt)" \
        --preview "$SELF preview {n}" \
        --preview-window 'right:60%:border-left')"
    [[ -n "$out" ]] || return 0

    name="${out%%$'\t'*}"
    if ! err="$("$mux" switch-client -t "=$name" 2>&1)"; then
        fail "Could not switch to session $name: $err"
    fi
}

case "${1:-}" in
    list) cmd_list ;;
    preview) cmd_preview "${2:-}" ;;
    kill) cmd_kill "${2:-}" ;;
    *) run ;;
esac
