#!/usr/bin/env bash
# Open files in the session's nvim, from any window of it: lazygit's e, yazi,
# the shell, an agent. tmux and psmux alike; edit.cmd is the way in for
# Windows programs, which run commands through cmd.exe.
#
#   edit.sh FILE[:LINE[:COL]]...
#
# One editor per session: the nvim window listens on the session's address
# (editor_address, mux-lib.sh), so a file opened anywhere in the session
# lands there instead of starting a second nvim, and that window comes
# forward. Where the files go:
#
#   $NVIM set        the nvim this terminal runs in (yazi in nvim's float,
#                    anything started from :terminal), as flatten.nvim does
#                    for a nested `nvim`
#   nvim window      the session's editor; when that window is at its shell
#                    prompt (never started, or nvim was quit) the editor is
#                    started there on the files
#   no nvim window   one is opened for the editor (a session not built by
#                    build_session)
#   outside a session  nvim runs here, when there is a terminal to run in
#
# Blocking edits -- a commit message, an agent's prompt file -- must not come
# through here: the caller waits for the editor to exit, and a remote open
# returns at once. Those keep plain `nvim` ($EDITOR, lazygit's editPreset).
set -u
# shellcheck source=mux-lib.sh
source "${BASH_SOURCE[0]%[\\/]*}/mux-lib.sh"

line=""
files=("$@")
# One argument carrying its position (lazygit's editAtLine, grep, stack
# traces). Greedy, so C:\x.txt:12 keeps its drive.
if [[ ${#files[@]} -eq 1 && "${files[0]}" =~ ^(.+):([0-9]+)(:[0-9]+)?$ && -e "${BASH_REMATCH[1]}" ]]; then
    line="${BASH_REMATCH[2]}"
    files=("${BASH_REMATCH[1]}")
fi

# Absolute, because the editor resolves a relative name against its own
# folder -- the session's -- and the caller is somewhere else more often than
# not (yazi in a subfolder, lazygit at the repo root). In the platform's own
# form: nvim on Windows is a Windows program.
if ((${#files[@]})); then
    if ((win)); then
        mapfile -t files < <(cygpath -w -a -- "${files[@]}")
    else
        for i in "${!files[@]}"; do
            files[i]="$(readlink -f -- "${files[i]}" 2>/dev/null)" || files[i]="${files[i]}"
        done
    fi
fi

# Open the files in the nvim listening at $1, with one client: --remote-expr
# rather than --remote-silent, so moving off a terminal or float window, the
# files and the line all go in one call (--remote drops the file into the
# editor's current window, and has no +LINE). --headless, or the client sets
# up a terminal UI of its own before connecting -- a second, and escape codes
# on whatever terminal it finds. An expression, not --remote-send: sent keys
# go through the editor's mappings, where <C-\> belongs to toggleterm.
remote_open() {
    local f list="" expr
    expr="execute(['for w in range(1,winnr(\"\$\")) | if getbufvar(winbufnr(w),\"&buftype\") == \"\" | exe w.\"wincmd w\" | break | endif | endfor'"
    for f in "${files[@]}"; do
        list+="${list:+,}'${f//\'/\'\'}'"
    done
    [[ -n "$list" ]] && expr+=", 'drop ' . join(map([$list], 'fnameescape(v:val)'))"
    [[ -n "$line" ]] && expr+=", 'normal! ${line}Gzz'"
    expr+="])"
    nvim --headless --server "$1" --remote-expr "$expr" </dev/null >/dev/null 2>&1
}

# Run nvim here, when whoever called left a terminal to run it in.
run_here() {
    [[ -t 0 ]] || give_up
    exec nvim ${line:+"+$line"} ${files[0]+--} "${files[@]}"
}

give_up() {
    printf 'edit.sh: no editor to open %s in\n' "${files[*]:-the file}" >&2
    exit 1
}

# Inside an nvim terminal: that nvim. Its address is \\.\pipe\... on
# Windows, which needs forward slashes on the way out of bash.
if [[ -n "${NVIM:-}" ]]; then
    addr="$NVIM"
    ((win)) && addr="${addr//\\//}"
    remote_open "$addr" || give_up
    exit 0
fi

# Outside a client, display-message would answer for whichever server it
# reaches.
in_client || run_here
current_session
s="$REPLY"
[[ -n "$s" ]] || run_here

editor_address "$s"
addr="$REPLY"
command_line nvim --listen "$addr" ${line:+"+$line"} ${files[0]+--} "${files[@]}"
start="$REPLY"

if slot_window "$s" nvim; then
    w="$REPLY"
    # Its nvim takes the files; with none running (never started, or quit)
    # the editor is started there on them: sent with it rather than after,
    # because an editor still working through its plugins takes the request
    # and then moves the cursor itself, leaving the file open at line 1.
    remote_open "$addr" || run_in_slot "$s" "$w" "$start" || give_up
else
    w="$("$mux" new-window -dP -F '#{window_index}' -t "=$s:" -n nvim -c "$PWD" "$start")" || run_here
fi
"$mux" select-window -t "=$s:$w"
