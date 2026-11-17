#!/usr/bin/env bash
# Window switcher for tmux and psmux (run by Git Bash on Windows).
#
#   window-switcher.sh               run the switcher (from a popup)
#   window-switcher.sh list          called back by fzf to load the list
#   window-switcher.sh preview N     called back by fzf for item N
#   window-switcher.sh kill N        ctrl-x: close item N (asks first)
#   window-switcher.sh open N        Enter: go to item N
#
# On psmux the popup starts fzf itself (psmux.conf) and everything here is a
# callback.
#
# Rows show what the status bar shows: each window's title (or its name when
# renamed by hand under tmux), its folder, and markers only when they say
# something. Ordered like Alt-Tab: the previous window first, so Enter right
# away flips back to it; then the session's other windows; the current window
# last; then other sessions' windows, labelled "session ▸ title".
# The preview is the window's actual screen.
set -u
export LC_ALL=C.UTF-8
# Trimmed without dirname, which would fork (see mux-lib.sh); fzf calls back
# with a Windows path (backslashes) on psmux.
# shellcheck source=mux-lib.sh
source "${BASH_SOURCE[0]%[\\/]*}/mux-lib.sh"

prompt='window ❯ '

# items: the list as fzf shows it, in this session's state folder.
picker_state window-switcher
items="$REPLY/items"

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
    done | sort -t$'\x1f' -k1,1n -s | cut -d$'\x1f' -f2- >"$items"
    cat "$items"
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
    done <"$items"
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

# Bound with transform, and pressed twice, since a window can hold hours of
# work: the first ctrl-x only turns the prompt into the question, the second,
# with the prompt still asking, closes the window. The focus binding restores
# the prompt when the cursor moves, so both presses are always on the same
# window. (A y/N read would need a console, which fzf.exe does not give
# execute.)
cmd_kill() {
    item "${1:-}" || return 0
    local target="$REPLY"
    if [[ "${FZF_PROMPT:-}" != close* ]]; then
        printf 'change-prompt:close %s? ctrl-x again ❯ ' "$target"
        return 0
    fi
    "$mux" kill-window -t "$target" 2>/dev/null
    callback window-switcher
    printf 'reload-sync(%s list)+change-prompt:%s' "$REPLY" "$prompt"
}

# Report a refused switch instead of closing as if nothing happened.
fail() {
    printf '\e[31m%s\e[0m\n' "$*"
    read -r -p 'Press Enter to close' _
}

# Go to window $1 (session:index), switching session when it is another's.
go_to() {
    local target="$1" sess idx err
    sess="${target%:*}"
    idx="${target##*:}"
    current_session
    if ! err="$("$mux" select-window -t "$sess:$idx" 2>&1)"; then
        fail "Could not select window $target: $err"
        return 0
    fi
    if [[ "$sess" != "$REPLY" ]] && ! err="$(switch_to "$sess" 2>&1)"; then
        fail "Could not switch to session $sess: $err"
    fi
}

# Enter: go to item $1 (fzf's become, which psmux's popup uses).
cmd_open() {
    item "${1:-}" || return 0
    go_to "$REPLY"
}

run() {
    local out self
    callback window-switcher
    self="$REPLY"
    # fzf opens empty and loads the list itself (start:reload), so the popup
    # draws at once instead of after list-windows and sort. The Alt-Tab order
    # stays.
    out="$(fzf </dev/null \
        --with-shell "$FZF_SHELL" \
        --bind "start:reload($self list)" \
        --ansi --reverse --border none --info inline-right \
        --delimiter $'\t' --with-nth 2 \
        --header 'enter switch · ctrl-x twice: close' \
        --prompt "$prompt" \
        --bind "ctrl-x:transform($self kill {n})" \
        --bind "focus:change-prompt($prompt)" \
        --preview "$self preview {n}" \
        --preview-window 'right:60%:border-left')"
    [[ -n "$out" ]] || return 0
    go_to "${out%%$'\t'*}"
}

case "${1:-}" in
    list) cmd_list ;;
    preview) cmd_preview "${2:-}" ;;
    kill) cmd_kill "${2:-}" ;;
    open) cmd_open "${2:-}" ;;
    *) run ;;
esac
