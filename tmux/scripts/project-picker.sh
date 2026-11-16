#!/usr/bin/env bash
# Project picker for tmux and psmux (run by Git Bash on Windows). Lists, in
# this order and without repeats:
#
#   ★  the folders declared in tmux/projects.conf
#   ▸  the folders inside its roots
#   z  zoxide's 30 most frecent folders (not $HOME, not a root itself)
#
# and marks with ● the ones a session already runs in. Enter switches to that
# session, or opens one there named as session_for (mux-lib.sh) decides.
#
#   project-picker.sh [--print] [DIR]  pick a folder (or take DIR) and open
#                                      its session; with --print, only create
#                                      it and print its name, for callers that
#                                      attach themselves (pwsh's tm)
#   project-picker.sh list             called back by fzf to load the list
#   project-picker.sh preview N        called back by fzf for item N
#
# fzf opens empty and loads the list itself (start:reload), which streams in
# as each source answers; see the switchers.
set -u
export LC_ALL=C.UTF-8
# Trimmed without dirname, which would fork (see mux-lib.sh); fzf calls back
# with a Windows path (backslashes) on psmux.
here="${BASH_SOURCE[0]%[\\/]*}"
# shellcheck source=mux-lib.sh
source "$here/mux-lib.sh"

# PROJECTS_CONF: another file to read, for trying one out.
conf="${PROJECTS_CONF:-$here/../projects.conf}"
zoxide_max=30
prompt='project ❯ '

# REPLY: a projects.conf path (~ expanded, / or \) as normdir gives it.
expand_path() {
    local p="$1"
    [[ "$p" == "~" || "$p" == "~/"* || "$p" == "~\\"* ]] && p="$home${p:1}"
    normdir "$p"
}

# Print one row and add it to the items file, unless the folder was listed
# already or is skipped. $1 folder (normdir form), $2 source, $3 declared
# name. Fields: folder, declared name, shown text. Fails when not printed.
emit() {
    local dir="$1" key="$1" label="${3:-}" short mark dot=""
    ((win)) && key="${key,,}"
    [[ -n "${seen[$key]:-}" || -n "${skip[$key]:-}" ]] && return 1
    seen["$key"]=1

    if [[ -z "$label" ]]; then
        label="${dir%"$sep"}"
        label="${label##*[\\/]}"
    fi
    short="${dir%"$sep"}"
    if [[ "${short,,}" == "${home,,}"* ]]; then
        short="~${short:${#home}}"
    fi
    case "$2" in
        project) mark=$'\e[33m★\e[0m' ;;
        root) mark=$'\e[34m▸\e[0m' ;;
        *) mark=$'\e[2mz\e[0m' ;;
    esac
    [[ -n "${open[$key]:-}" ]] && dot=$'  \e[33m●\e[0m'

    local row
    printf -v row '%s\t%s\t%s %-24s \e[2m%s\e[0m%s' "$dir" "${3:-}" "$mark" "$label" "$short" "$dot"
    printf '%s\n' "$row"
    printf '%s\n' "$row" >&3
}

cmd_list() {
    local -A seen=() skip=() open=()
    local -a roots=() depths=()
    local line kind path arg _ key depth i n=0
    exec 3>"$PICK_ITEMS"

    # Folders sessions run in, for the ● mark.
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        normdir "$path"
        key="$REPLY"
        ((win)) && key="${key,,}"
        open["$key"]=1
    done < <("$mux" list-sessions -F '#{session_path}' 2>/dev/null)

    # zoxide knows $HOME and the roots themselves, which are not projects.
    normdir "$home"
    key="$REPLY"
    ((win)) && key="${key,,}"
    skip["$key"]=1

    # Declared projects are printed as they are read; roots are walked after.
    if [[ -r "$conf" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            read -r kind path arg _ <<<"${line%$'\r'}"
            case "$kind" in
                project | root) ;;
                *) continue ;;
            esac
            [[ -n "${path:-}" ]] || continue
            expand_path "$path"
            [[ -d "$REPLY" ]] || continue
            if [[ "$kind" == project ]]; then
                emit "$REPLY" project "${arg:-}"
            else
                roots+=("$REPLY")
                depth="${arg#depth=}"
                [[ "$depth" =~ ^[1-9][0-9]*$ ]] || depth=1
                depths+=("$depth")
                key="$REPLY"
                ((win)) && key="${key,,}"
                skip["$key"]=1
            fi
        done <"$conf"
    fi

    # --format '{}' (fd 10.1+, which both setups install): without the
    # trailing separator fd gives folders, which would sort "app-2\" ahead of
    # "app\".
    for i in "${!roots[@]}"; do
        while IFS= read -r path; do
            normdir "$path"
            emit "$REPLY" root
        done < <(fd --type directory --max-depth "${depths[i]}" --color never --format '{}' . "${roots[i]}" 2>/dev/null |
            sort -f)
    done

    if command -v zoxide >/dev/null; then
        while IFS= read -r path; do
            path="${path%$'\r'}"
            [[ -n "$path" && -d "$path" ]] || continue
            normdir "$path"
            emit "$REPLY" zoxide || continue
            ((++n >= zoxide_max)) && break
        done < <(zoxide query -l 2>/dev/null)
    fi
    exec 3>&-
}

# REPLY: the folder of item $1.
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
    done <"$PICK_ITEMS"
    return 1
}

cmd_preview() {
    item "${1:-}" || return 0
    eza --tree --git-ignore --level 2 --colour=always --icons=always "$REPLY" 2>/dev/null ||
        ls -la "$REPLY" 2>/dev/null
}

run() {
    local print=0 out path rest name=""
    if [[ "${1:-}" == --print ]]; then
        print=1
        shift
    fi

    if [[ -n "${1:-}" ]]; then
        if [[ ! -d "$1" ]]; then
            printf 'Not a folder: %s\n' "$1" >&2
            return 1
        fi
        if ((win)); then
            path="$(cygpath -w -a "$1")"
        else
            path="$(cd "$1" && pwd -P)"
        fi
        normdir "$path"
        path="$REPLY"
    else
        new_state_file project-picker || return 1
        export PICK_ITEMS="$REPLY"
        trap 'rm -f "$PICK_ITEMS"' EXIT
        fzf_callbacks "$0"

        out="$(fzf </dev/null \
            --with-shell "$FZF_SHELL" \
            --bind "start:reload($SELF list)" \
            --ansi --reverse --border none --info inline-right \
            --delimiter $'\t' --with-nth 3 --tiebreak index \
            --header '★ project · ▸ root · z zoxide · ● session open' \
            --prompt "$prompt" \
            --preview "$SELF preview {n}" \
            --preview-window 'right:50%:border-left')"
        [[ -n "$out" ]] || return 0
        path="${out%%$'\t'*}"
        rest="${out#*$'\t'}"
        name="${rest%%$'\t'*}"
    fi

    if ((print)); then
        ensure_session "$path" "$name" && printf '%s\n' "$REPLY"
    else
        open_session "$path" "$name"
    fi
}

case "${1:-}" in
    list) cmd_list ;;
    preview) cmd_preview "${2:-}" ;;
    *) run "$@" ;;
esac
