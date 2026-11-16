#!/usr/bin/env bash
# Project picker for tmux and psmux (run by Git Bash on Windows). Lists, in
# this order and without repeats:
#
#   ●  the folders sessions run in, most recently used first, the current
#      one last; any folder, listed or not, under its usual marker or ·
#   ★  the folders declared in tmux/projects.conf
#   ▸  the folders inside its roots
#   z  zoxide's 30 most frecent folders (not $HOME, not a root itself)
#
# Enter switches to the folder's session, or opens one there named as
# session_for (mux-lib.sh) decides.
#
#   project-picker.sh [--print] [DIR]  pick a folder (or take DIR) and open
#                                      its session; with --print, only create
#                                      it and print its name, for callers that
#                                      attach themselves (pwsh's tm)
#   project-picker.sh list             called back by fzf to load the list
#   project-picker.sh preview N        called back by fzf for item N
#   project-picker.sh kill N           ctrl-x: kill item N's session (asks
#                                      first)
#
# fzf opens empty and loads the list itself (start:reload), which streams in
# as each source answers, as in window-switcher.sh.
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
# already (or, from zoxide, is skipped). $1 folder (normdir form), $2 source:
# project, root, zoxide or other; $3 declared name. Fields: folder, declared
# name, shown text, open session's name (empty when none). Fails when not
# printed.
emit() {
    local dir="$1" key="$1" label="${3:-}" short mark dot="" sname
    ((win)) && key="${key,,}"
    [[ -n "${seen[$key]:-}" ]] && return 1
    [[ "$2" == zoxide && -n "${skip[$key]:-}" ]] && return 1
    seen["$key"]=1

    if [[ -z "$label" ]]; then
        label="${dir%"$sep"}"
        label="${label##*[\\/]}"
    fi
    # An open session shows its own name when that is not just the label made
    # session-safe (a clash renamed it, or it predates a declared name): it is
    # the session Enter switches to.
    sname="${open[$key]:-}"
    if [[ -n "$sname" ]]; then
        [[ "$sname" != "${label//[.: ]/_}" ]] && label="$sname"
        dot=$'  \e[33m●\e[0m'
        [[ "$key" == "$cur_key" ]] && dot+=$' \e[2mhere\e[0m'
    fi
    short="${dir%"$sep"}"
    if [[ "${short,,}" == "${home,,}"* ]]; then
        short="~${short:${#home}}"
    fi
    case "$2" in
        project) mark=$'\e[33m★\e[0m' ;;
        root) mark=$'\e[34m▸\e[0m' ;;
        zoxide) mark=$'\e[2mz\e[0m' ;;
        *) mark=$'\e[2m·\e[0m' ;;
    esac

    local row
    printf -v row '%s\t%s\t%s %-24s \e[2m%s\e[0m%s\t%s' "$dir" "${3:-}" "$mark" "$label" "$short" "$dot" "$sname"
    printf '%s\n' "$row"
    printf '%s\n' "$row" >&3
}

# REPLY: the source folder key $1 would be listed under, worked out without
# fd or zoxide so open sessions can lead the list with their real marker:
# project when declared, root when it lies inside a root within its depth,
# otherwise other.
source_of() {
    local i rk rest seps
    if [[ -n "${declared[$1]+set}" ]]; then
        REPLY=project
        return
    fi
    for i in "${!roots[@]}"; do
        rk="${roots[i]}"
        ((win)) && rk="${rk,,}"
        [[ "$1" == "$rk"?* ]] || continue
        rest="${1#"$rk"}"
        rest="${rest%"$sep"}"
        seps="${rest//[!\\\/]/}"
        if ((${#seps} < depths[i])); then
            REPLY=root
            return
        fi
    done
    REPLY=other
}

cmd_list() {
    local -A seen=() skip=() open=() declared=()
    local -a roots=() depths=() pdirs=() pnames=() okeys=() odirs=()
    local line kind path arg _ key depth i n=0 last name cur cur_key="" cur_dir=""
    exec 3>"$PICK_ITEMS"

    # projects.conf first: reading it starts no process, and the open
    # sessions need it to know their marker.
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
            key="$REPLY"
            ((win)) && key="${key,,}"
            if [[ "$kind" == project ]]; then
                pdirs+=("$REPLY")
                pnames+=("${arg:-}")
                declared["$key"]="${arg:-}"
            else
                roots+=("$REPLY")
                depth="${arg#depth=}"
                [[ "$depth" =~ ^[1-9][0-9]*$ ]] || depth=1
                depths+=("$depth")
                skip["$key"]=1
            fi
        done <"$conf"
    fi

    # zoxide knows $HOME and the roots themselves, which are not projects.
    normdir "$home"
    key="$REPLY"
    ((win)) && key="${key,,}"
    skip["$key"]=1

    # Open sessions lead, most recently used first, and the one this popup
    # was opened from last (prefix w puts the current window last the same
    # way). A folder with two sessions shows the more recent one.
    current_session
    cur="$REPLY"
    while IFS=$us read -r last name path; do
        [[ -z "$name" || -z "$path" ]] && continue
        # popup.sh's sessions (lazygit, yazi) belong to another session.
        [[ "$name" == popup_* ]] && continue
        normdir "$path"
        key="$REPLY"
        ((win)) && key="${key,,}"
        [[ -n "${open[$key]:-}" ]] && continue
        open["$key"]="$name"
        if [[ "$name" == "$cur" ]]; then
            cur_key="$key"
            cur_dir="$REPLY"
        else
            okeys+=("$key")
            odirs+=("$REPLY")
        fi
    done < <("$mux" list-sessions -F "#{session_last_attached}${us}#{session_name}${us}#{session_path}" 2>/dev/null |
        sort -t"$us" -k1,1rn)
    if [[ -n "$cur_key" ]]; then
        okeys+=("$cur_key")
        odirs+=("$cur_dir")
    fi
    for i in "${!odirs[@]}"; do
        source_of "${okeys[i]}"
        if [[ "$REPLY" == project ]]; then
            emit "${odirs[i]}" project "${declared[${okeys[i]}]}"
        else
            emit "${odirs[i]}" "$REPLY"
        fi
    done

    for i in "${!pdirs[@]}"; do
        emit "${pdirs[i]}" project "${pnames[i]}"
    done

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

# REPLY: the folder of item $1; item_session: the session open there, or
# empty.
item() {
    local i=0 line
    REPLY=""
    item_session=""
    [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
    while IFS= read -r line; do
        if ((i == $1)); then
            REPLY="${line%%$'\t'*}"
            item_session="${line##*$'\t'}"
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

# Bound with transform, and pressed twice, since a session can hold hours of
# work: the first ctrl-x only turns the prompt into the question, the second,
# with the prompt still asking, kills. The focus binding restores the prompt
# when the cursor moves, so both presses are always on the same session.
# (A y/N read would need a console, which fzf.exe does not give execute.)
# Rows without a session have nothing to kill, and the session the popup was
# opened from is refused: killing it would take the popup down mid-action.
cmd_kill() {
    item "${1:-}" || return 0
    local name="$item_session"
    if [[ -z "$name" ]]; then
        printf 'change-prompt:no session here ❯ '
        return 0
    fi
    current_session
    if [[ "$name" == "$REPLY" ]]; then
        printf "change-prompt:%s is the session you are in ❯ " "$name"
        return 0
    fi
    if [[ "${FZF_PROMPT:-}" != kill* ]]; then
        printf 'change-prompt:kill %s? ctrl-x again ❯ ' "$name"
        return 0
    fi
    "$mux" kill-session -t "=$name" 2>/dev/null
    printf 'reload-sync(%s list)+change-prompt:%s' "$PICK_SELF" "$prompt"
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
        export PICK_SELF="$SELF"

        out="$(fzf </dev/null \
            --with-shell "$FZF_SHELL" \
            --bind "start:reload($SELF list)" \
            --bind "ctrl-x:transform($SELF kill {n})" \
            --bind "focus:change-prompt($prompt)" \
            --ansi --reverse --border none --info inline-right \
            --delimiter $'\t' --with-nth 3 --tiebreak index \
            --header $'● open, recent first · ★ project · ▸ root · z zoxide\nenter open · ctrl-x twice: kill session' \
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
    kill) cmd_kill "${2:-}" ;;
    *) run "$@" ;;
esac
