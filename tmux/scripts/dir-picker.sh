#!/usr/bin/env bash
# Folder picker for new tmux/psmux sessions: walk the tree one level at a
# time, the way a shell completes a path, then open a session in the folder.
#
#   dir-picker.sh                     run the picker (from a tmux/psmux popup)
#   dir-picker.sh descend tab|sep N   called back by fzf's key bindings
#   dir-picker.sh up | preview N
#
# The prompt shows the folder you are in; the query only filters its
# children, so typing is filtered by fzf itself and only moving between
# folders runs anything: one bash process that decides where to go, lists it
# with a glob and writes the listing, which fzf then reloads from the file.
# On Windows (psmux) this runs under Git Bash, where every fork is expensive,
# so nothing on that path uses $( ) or pipelines; helpers set REPLY instead.
#
# fzf's bindings pass nothing but {n}, the highlighted item's index, so no path
# has to survive fzf's quoting rules on either platform.
set -u
shopt -s nullglob dotglob
export LC_COLLATE=en_US.UTF-8

if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    win=1
    sep='\'
    mux=psmux
    home="$USERPROFILE"
    # Keep MSYS from rewriting the Windows paths handed to psmux.
    export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
else
    win=0
    sep=/
    mux=tmux
    home="$HOME"
fi

hints='tab enter folder · ⌫ up · ↵ new session · type c/ ~/ ../ to jump'

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

# REPLY: a typed path resolved (c/, c:, C:\..., ~, ~/..., and on WSL c/ for
# /mnt/c), or empty when the text is not a path.
resolve() {
    local q="${1//\\//}" rest
    REPLY=""
    if [[ "$q" == "~" || "$q" == "~/"* ]]; then
        rest="${q#\~}"
        normdir "$home${rest//\//$sep}"
    elif [[ "$q" =~ ^([A-Za-z]):?(/.*)?$ ]]; then
        rest="${BASH_REMATCH[2]}"
        if ((win)); then
            normdir "${BASH_REMATCH[1]^^}:${rest//\//\\}"
        elif [[ -d "/mnt/${BASH_REMATCH[1],,}" ]]; then
            normdir "/mnt/${BASH_REMATCH[1],,}$rest"
        fi
    elif [[ "$q" == /* ]] && ! ((win)); then
        normdir "$q"
    fi
}

# Names of the folders in $1 into the array `names`, in name order.
#
# A */ glob lists them without starting a process, but has to check the type
# of every entry, and under Git Bash each check is slow: System32's ~5000
# files take seconds. So on Windows a folder with many entries (counted with
# a plain * glob, which checks nothing) goes to fd instead, which takes about
# a tenth of a second whatever the size; one thread keeps NTFS's own name
# order, so nothing needs sorting.
list_names() {
    local glob="$1" p name entries
    ((win)) && glob="${glob//\\//}"
    names=()
    if ((win)); then
        entries=("$glob"*)
        if ((${#entries[@]} > 300)); then
            mapfile -t names < <(fd --threads 1 -L --type directory --max-depth 1 --hidden \
                --color never . "$1" 2>/dev/null)
            for p in "${!names[@]}"; do
                name="${names[p]%[\\/]}"
                names[p]="${name##*[\\/]}"
            done
            return
        fi
    fi
    for p in "$glob"*/; do
        p="${p%/}"
        names+=("${p##*/}")
    done
}

# Write the listing of $1 to the items file. Fields: full path, name (the
# only searched field), label. Folders sort case-insensitively, dot-folders
# last; .git is left out.
write_items() {
    local dir="$1" name out dots=() names
    list_names "$dir"
    out="$dir"$'\t\t./  open this folder\n'
    for name in "${names[@]}"; do
        [[ "$name" == .git ]] && continue
        if [[ "$name" == .* ]]; then
            dots+=("$name")
        else
            out+="$dir$name$sep"$'\t'"$name$sep"$'\t\n'
        fi
    done
    for name in "${dots[@]}"; do
        out+="$dir$name$sep"$'\t'"$name$sep"$'\t\n'
    done
    printf '%s' "$out" >"$DIRPICK_STATE/items"
}

# REPLY: the full path of item $1 in the current listing.
item() {
    local i=0 line
    REPLY=""
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    while IFS= read -r line; do
        if ((i == $1)); then
            REPLY="${line%%$'\t'*}"
            return 0
        fi
        i=$((i + 1))
    done <"$DIRPICK_STATE/items"
    return 1
}

# REPLY: $1 shortened for the prompt, which only displays the folder (the
# state file holds the real one): the root plus as many trailing segments as
# fit, so a deep path does not push the query off screen.
shorten() {
    local p="$1" max=48 root rest
    if ((${#p} <= max)); then REPLY="$p"; return; fi
    if ((win)); then root="${p:0:3}"; else root=/; fi
    rest="${p: -$((max - ${#root} - 2))}"
    rest="${rest#*[\\/]}"
    REPLY="$root…$sep$rest"
}

# Print fzf actions that move to $1, or a header explaining why not.
go() {
    local target="$1"
    if [[ ! -d "$target" || ! -x "$target" ]]; then
        printf 'change-header|Cannot open %s  ·  %s|' "$target" "$hints"
        return
    fi
    printf '%s' "$target" >"$DIRPICK_STATE/cwd"
    write_items "$target"
    shorten "$target"
    printf 'change-prompt|%s ❯ |+change-header|%s|+clear-query+reload-sync|%s|+first' \
        "$REPLY" "$hints" "$DIRPICK_RELOAD"
}

# Tab: enter the highlighted folder.
# / or \: like typing a path, so the query decides first:
#   1. the query is exactly a child's name: enter that child;
#   2. it is a path that exists (c/, c:, ~, .., /abs): jump there;
#   3. otherwise enter the highlighted folder, as Tab does.
# The order keeps "s/" meaning the child "s" or the highlighted "src", and only
# jumps to drive S: when nothing here is called "s".
cmd_descend() {
    local mode="$1" n="${2:-}" cwd target="" query="${FZF_QUERY:-}" path name _
    read -r cwd <"$DIRPICK_STATE/cwd"
    if [[ "$mode" == sep && -n "$query" ]]; then
        while IFS=$'\t' read -r path name _; do
            name="${name%"$sep"}"
            if [[ "$name" == "$query" ]] || { ((win)) && [[ "${name,,}" == "${query,,}" ]]; }; then
                target="$path"
                break
            fi
        done <"$DIRPICK_STATE/items"
        if [[ -z "$target" ]]; then
            if [[ "$query" == ".." ]]; then
                parent "$cwd"
            else
                resolve "$query"
                [[ -n "$REPLY" && -d "$REPLY" ]] || REPLY=""
            fi
            target="$REPLY"
        fi
    fi
    if [[ -z "$target" ]]; then
        item "$n" || return 0
        target="$REPLY"
        [[ -n "$target" && "$target" != "$cwd" ]] || return 0
    fi
    go "$target"
}

# Backspace on an empty query: go to the parent folder.
cmd_up() {
    local cwd
    read -r cwd <"$DIRPICK_STATE/cwd"
    parent "$cwd"
    [[ "$REPLY" != "$cwd" ]] && go "$REPLY"
}

cmd_preview() {
    item "${1:-}" || return 0
    eza --tree --git-ignore --level 2 --colour=always --icons=always "$REPLY" 2>/dev/null ||
        ls -la "$REPLY" 2>/dev/null
}

# Print "existing<TAB>name" when a session already runs in folder $1,
# otherwise "new<TAB>name" with a name no other folder's session uses.
session_for() {
    local dir="${1%"$sep"}" base name prefix n path key
    [[ -z "$dir" ]] && dir=/
    base="${dir##*[\\/]}"
    [[ -z "$base" || "$dir" == / ]] && base=root
    base="${base//[.: ]/_}"
    normdir "$1"
    key="$REPLY"
    ((win)) && key="${key,,}"

    declare -A taken=()
    while IFS=$'\t' read -r n path; do
        [[ -z "$n" ]] && continue
        normdir "$path"
        path="$REPLY"
        ((win)) && path="${path,,}"
        if [[ "$path" == "$key" ]]; then
            printf 'existing\t%s' "$n"
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
    printf 'new\t%s' "$name"
}

open_session() {
    local kind name
    IFS=$'\t' read -r kind name < <(session_for "$1")
    [[ "$kind" == new ]] && "$mux" new-session -d -s "$name" -c "$1"
    if [[ -n "${TMUX:-}" || -n "${PSMUX_POPUP:-}" ]]; then
        "$mux" switch-client -t "=$name"
    else
        "$mux" attach -t "=$name"
    fi
}

run() {
    local start self shell out query selection
    start="$("$mux" display-message -p '#{pane_current_path}' 2>/dev/null)"
    [[ -d "$start" ]] || start="$home"
    normdir "$start"
    start="$REPLY"

    DIRPICK_STATE="$(mktemp -d)"
    export DIRPICK_STATE
    trap 'rm -rf "$DIRPICK_STATE"' EXIT
    printf '%s' "$start" >"$DIRPICK_STATE/cwd"
    write_items "$start"

    if ((win)); then
        # fzf.exe would try $SHELL (/usr/bin/bash, an MSYS path it cannot
        # start), so its child commands go through cmd: the reload is a plain
        # `type`, and the callbacks start Git Bash. Every path is in 8.3 form,
        # which has no spaces, because quotes do not survive fzf handing the
        # command line to cmd.
        shell='cmd.exe /d /c'
        self="$(cygpath -d "$BASH") $(cygpath -d "$0")"
        export DIRPICK_RELOAD="type $(cygpath -d "$DIRPICK_STATE/items")"
    else
        shell='bash -c'
        printf -v self 'bash %q' "$0"
        printf -v DIRPICK_RELOAD 'cat %q' "$DIRPICK_STATE/items"
        export DIRPICK_RELOAD
    fi

    shorten "$start"
    out="$(fzf <"$DIRPICK_STATE/items" \
        --with-shell "$shell" \
        --prompt "$REPLY ❯ " \
        --header "$hints" \
        --delimiter $'\t' --with-nth 2,3 --nth 1 \
        --tiebreak begin,length,index \
        --reverse --border none --info inline-right \
        --print-query \
        --bind "tab:transform:$self descend tab {n}" \
        --bind "/:transform:$self descend sep {n}" \
        --bind "\\:transform:$self descend sep {n}" \
        --bind "backward-eof:transform:$self up" \
        --preview "$self preview {n}" \
        --preview-window right:50%:border-left)"
    query="${out%%$'\n'*}"
    selection=""
    [[ "$out" == *$'\n'* ]] && selection="${out#*$'\n'}"

    if [[ -n "$selection" ]]; then
        open_session "${selection%%$'\t'*}"
    elif [[ -n "$query" ]]; then
        # Enter with no match: a typed or pasted path that exists.
        resolve "$query"
        [[ -n "$REPLY" && -d "$REPLY" ]] && open_session "$REPLY"
    fi
    return 0
}

case "${1:-}" in
    descend) cmd_descend "${2:-}" "${3:-}" ;;
    up) cmd_up ;;
    preview) cmd_preview "${2:-}" ;;
    *) run ;;
esac
