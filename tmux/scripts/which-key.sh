#!/usr/bin/env bash
# which-key for tmux and psmux (run by Git Bash on Windows), in the popup
# prefix Space opens: shows the keys of tmux/which-key.conf one level at a
# time, like nvim's which-key, and runs the one typed.
#
#   which-key.sh
#
# A key that opens a group shows the group's keys; Backspace goes back up a
# level and Esc closes. An action is either a script from this folder, run in
# this same popup (a picker), or a tmux command sent with the tmux or psmux
# CLI. See which-key.conf for the format.
set -u
here="${BASH_SOURCE[0]%[\\/]*}"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

# WHICH_KEY_CONF: another file to read, for trying one out.
conf="${WHICH_KEY_CONF:-$here/../which-key.conf}"

keys=() descs=() acts=()

# Fill keys, descs and acts from the definition file.
load() {
    local line k rest
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        k="${line%%[[:space:]]*}"
        rest="${line#"$k"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        keys+=("$k")
        if [[ "$rest" =~ ^(.*[^[:space:]])[[:space:]]{2,}([^[:space:]].*)$ ]]; then
            descs+=("${BASH_REMATCH[1]}")
            acts+=("${BASH_REMATCH[2]}")
        else
            descs+=("$rest")
            acts+=("")
        fi
    done <"$conf"
}

# Draw the keys one level below prefix $1, in columns, with $2 as a message.
draw() {
    local prefix="$1" msg="${2:-}" i k d n=0 cols=80 width=34 per row="" trail=""
    read -r _ cols < <(stty size 2>/dev/null) || cols=80
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    per=$((cols / width))
    ((per < 1)) && per=1

    printf '\e[H\e[2J'
    for i in "${!keys[@]}"; do
        [[ "${keys[i]}" == "$prefix"* ]] || continue
        if [[ -n "$prefix" && "${keys[i]}" == "$prefix" ]]; then
            trail="${descs[i]}"
        fi
    done
    printf ' \e[1mprefix Space\e[0m'
    [[ -n "$prefix" ]] && printf ' \e[2m❯\e[0m \e[33m%s\e[0m \e[34m%s\e[0m' "$prefix" "$trail"
    printf '\n\n'

    for i in "${!keys[@]}"; do
        k="${keys[i]}"
        [[ "$k" == "$prefix"? ]] || continue
        d="${descs[i]}"
        if [[ "$d" == +* ]]; then
            printf -v d '\e[34m%-*.*s\e[0m' $((width - 5)) $((width - 5)) "$d"
        else
            printf -v d '%-*.*s' $((width - 5)) $((width - 5)) "$d"
        fi
        row+=$(printf ' \e[33m%s\e[0m \e[2m→\e[0m %s' "${k: -1}" "$d")
        if ((++n % per == 0)); then
            printf '%s\n' "$row"
            row=""
        fi
    done
    [[ -n "$row" ]] && printf '%s\n' "$row"

    printf '\n \e[2m%s\e[0m' "${msg:-esc close · ⌫ back}"
}

# Run action $1: a script in this popup, or a tmux command.
act() {
    local a="$1" s dir file
    if [[ "$a" == "run "* ]]; then
        exec "$BASH" "$here/${a#run }"
    fi
    current_session
    s="$REPLY"
    dir="$("$mux" display-message -p '#{pane_current_path}' 2>/dev/null)"
    if ((win)); then
        # Forward slashes: psmux drops the backslashes of a Windows path in
        # some commands' arguments (split-window -c), and Windows takes both.
        dir="${dir//\\//}"
        file="${home//\\//}/.dotconfigs/tmux/psmux.conf"
    else
        file="$HOME/.config/tmux/tmux.conf"
    fi
    printf -v s '%q' "$s"
    printf -v dir '%q' "$dir"
    printf -v file '%q' "$file"
    a="${a//\{s\}/$s}"
    a="${a//\{dir\}/$dir}"
    a="${a//\{conf\}/$file}"
    local err
    if ! err="$(eval "\"\$mux\" $a" 2>&1)"; then
        printf '\e[H\e[2J\e[31m%s\e[0m\n%s\n\npress a key' "$a" "$err"
        IFS= read -rsN1 _
    fi
    exit 0
}

load
prefix=""
msg=""
while :; do
    draw "$prefix" "$msg"
    msg=""
    IFS= read -rsN1 c || exit 0
    case "$c" in
        $'\e')
            # A lone Esc closes; the rest of an escape sequence (an arrow
            # key) is read away and ignored.
            if IFS= read -rsN1 -t 0.02 _; then
                while IFS= read -rsN1 -t 0.02 _; do :; done
                continue
            fi
            exit 0
            ;;
        $'\x7f' | $'\b')
            prefix="${prefix%?}"
            continue
            ;;
    esac
    found=""
    for i in "${!keys[@]}"; do
        if [[ "${keys[i]}" == "$prefix$c" ]]; then
            found="$i"
            break
        fi
    done
    if [[ -z "$found" ]]; then
        msg="nothing on $prefix$c"
    elif [[ "${descs[found]}" == +* ]]; then
        prefix+="$c"
    else
        act "${acts[found]}"
    fi
done
