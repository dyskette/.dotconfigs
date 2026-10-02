#!/usr/bin/env bash
# Window switcher for tmux and psmux (run by Git Bash on Windows).
#
#   window-switcher.sh               run the switcher (from a popup)
#   window-switcher.sh preview N     called back by fzf for item N
#   window-switcher.sh kill N
#
# Rows show what the status bar shows: each window's title (or its name when
# renamed by hand under tmux), its folder, and markers only when they say
# something. Ordered like Alt-Tab: the previous window first, so Enter right
# away flips back to it; then the session's other windows; the current window
# last; then other sessions' windows, labelled "session ▸ title".
# The preview is the window's actual screen.
set -u
export LC_ALL=C.UTF-8
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

prompt='window ❯ '

# Longest label shown in full; longer ones are cut with an ellipsis.
label_width=40

# REPLY: what the status bar shows for a window: its name when renamed by hand
# (tmux turns automatic-rename off), otherwise its pane title, or its name
# when nothing set a title.
window_label() {
    local auto="$1" name="$2" title="$3"
    if [[ "$auto" == off || "$auto" == 0 || -z "$title" ]]; then
        REPLY="$name"
    else
        REPLY="$title"
    fi
}

# REPLY: $1 cut or padded to exactly $2 characters.
fit() {
    local s="$1" w="$2"
    if ((${#s} > w)); then
        s="${s:0:w-1}…"
    fi
    printf -v REPLY '%s%*s' "$s" $((w - ${#s})) ''
}

# Write the items file and print it. Fields: target (session:index), shown
# text. Order: previous window, other windows, current window, then other
# sessions (most recently attached first), each in index order.
cmd_list() {
    local cur sess idx active last panes flags auto name title dir
    local -a keys=() targets=() heads=() tails=()
    local -A order=()
    current_session
    cur="$REPLY"

    local i=0 s
    while IFS= read -r s; do order["$s"]=$((i++)); done < <(
        "$mux" list-sessions -F '#{session_last_attached} #{session_name}' 2>/dev/null |
            sort -rn | cut -d' ' -f2-)

    local width=0 head tail home_name="${home##*[\\/]}"
    while IFS=$us read -r sess idx active last panes flags auto name title dir; do
        [[ -z "$sess" ]] && continue
        window_label "$auto" "$name" "$title"
        # The folder only when it adds something: a shell's title already is
        # its folder (~ for home), and a session is usually named after its
        # folder.
        if [[ "$dir" == "$REPLY" || "$dir" == "$sess" || ("$REPLY" == "~" && "$dir" == "$home_name") ]]; then
            dir=""
        fi
        tail="${dir:+$'\e[2m'$dir$'\e[0m'}"$'\e[33m'
        ((panes > 1)) && tail+=" ⧉$panes"
        flags="${flags//[*-]/}"
        [[ -n "$flags" ]] && tail+=" $flags"
        if [[ "$sess" == "$cur" ]]; then
            head="$idx  $REPLY"
            if [[ "$active" == 1 ]]; then
                keys+=(2) tail+=" ●"
            elif [[ "$last" == 1 ]]; then
                keys+=(0)
            else
                keys+=(1)
            fi
        else
            head="$sess ▸ $idx  $REPLY"
            keys+=($((3 + ${order[$sess]:-99})))
        fi
        targets+=("$sess:$idx") heads+=("$head") tails+=("${tail# }"$'\e[0m')
        ((${#head} > width)) && width=${#head}
    done < <("$mux" list-windows -a -F "#{session_name}${us}#{window_index}${us}#{window_active}${us}#{window_last_flag}${us}#{window_panes}${us}#{window_flags}${us}#{automatic-rename}${us}#{window_name}${us}#{pane_title}${us}#{b:pane_current_path}" 2>/dev/null)
    ((width > label_width)) && width=$label_width

    for i in "${!targets[@]}"; do
        fit "${heads[i]}" "$width"
        printf '%s\x1f%s\t%s  %s\n' "${keys[i]}" "${targets[i]}" "$REPLY" "${tails[i]}"
    done | sort -t$'\x1f' -k1,1n -s | cut -d$'\x1f' -f2- >"$SWITCH_STATE/items"
    cat "$SWITCH_STATE/items"
}

# REPLY: the target of item $1.
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

# The window's title and panes, then what is on its screen.
cmd_preview() {
    item "${1:-}" || return 0
    local target="$REPLY" auto name title panes dir
    IFS=$us read -r auto name title panes dir < <("$mux" display-message -t "$target" -p \
        "#{automatic-rename}${us}#{window_name}${us}#{pane_title}${us}#{window_panes}${us}#{pane_current_path}" 2>/dev/null)
    window_label "$auto" "$name" "$title"
    printf '\e[1m%s\e[0m \e[2m─ %s pane%s · %s\e[0m\n\n' "$REPLY" "$panes" "$( ((panes == 1)) || printf s)" "$dir"
    "$mux" capture-pane -p -e -t "$target" 2>/dev/null
}

# Pressed twice, as in session-switcher.sh: the first ctrl-x asks in the
# prompt, the second closes the window; moving the cursor cancels.
cmd_kill() {
    item "${1:-}" || return 0
    local target="$REPLY"
    if [[ "${FZF_PROMPT:-}" != close* ]]; then
        printf 'change-prompt:close %s? ctrl-x again ❯ ' "$target"
        return 0
    fi
    "$mux" kill-window -t "$target" 2>/dev/null
    printf 'reload-sync(%s list)+change-prompt:%s' "$SWITCH_SELF" "$prompt"
}

# Report a refused switch instead of closing as if nothing happened.
fail() {
    printf '\e[31m%s\e[0m\n' "$*"
    read -r -p 'Press Enter to close' _
}

run() {
    local out target sess idx cur err
    SWITCH_STATE="$(mktemp -d)"
    export SWITCH_STATE
    trap 'rm -rf "$SWITCH_STATE"' EXIT
    fzf_callbacks "$0"
    export SWITCH_SELF="$SELF"

    out="$(cmd_list | fzf \
        --with-shell "$FZF_SHELL" \
        --ansi --reverse --border none --info inline-right \
        --delimiter $'\t' --with-nth 2 \
        --header 'enter switch · ctrl-x twice: close' \
        --prompt "$prompt" \
        --bind "ctrl-x:transform($SELF kill {n})" \
        --bind "focus:change-prompt($prompt)" \
        --preview "$SELF preview {n}" \
        --preview-window 'right:60%:border-left')"
    [[ -n "$out" ]] || return 0

    target="${out%%$'\t'*}"
    sess="${target%:*}"
    idx="${target##*:}"
    current_session
    cur="$REPLY"

    if ! err="$("$mux" select-window -t "$sess:$idx" 2>&1)"; then
        fail "Could not select window $target: $err"
        return 0
    fi
    if [[ "$sess" != "$cur" ]] && ! err="$("$mux" switch-client -t "=$sess" 2>&1)"; then
        fail "Could not switch to session $sess: $err"
    fi
}

case "${1:-}" in
    list) cmd_list ;;
    preview) cmd_preview "${2:-}" ;;
    kill) cmd_kill "${2:-}" ;;
    *) run ;;
esac
