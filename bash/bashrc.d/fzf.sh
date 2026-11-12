# fzf, fd, ripgrep and bat wired into bash: fzf's own key bindings and **
# completion, fed by fd and previewed by bat and eza, plus the zj/tm session
# pickers. The pickers with their own names (sf, sg, ...) live in files.sh.
#
#   Ctrl+t   insert files picked with fzf at the cursor
#   Alt+c    cd into a folder picked with fzf
#   Ctrl+r   search history (Ctrl+y in it copies the command)
#   **<Tab>  fuzzy completion: vim **<Tab>, cd **<Tab>, kill **<Tab>, ...
command -v fzf &>/dev/null || return 0

export FZF_DEFAULT_OPTS_FILE="$HOME/.dotconfigs/fzf/fzfrc"
export RIPGREP_CONFIG_PATH="$HOME/.dotconfigs/ripgrep/config"
export FZF_DEFAULT_COMMAND='fd --type file --hidden --follow --strip-cwd-prefix'

# Git Bash: fzf.exe cannot start $SHELL (/usr/bin/bash, an MSYS path), so its
# previews and reloads go through cmd.exe, as in tmux/scripts/mux-lib.sh. The
# commands below are written to work in both.
# FZF_PREVIEW_COLUMNS_REF is how a preview command reads its width there.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
  export FZF_DEFAULT_OPTS="--with-shell='cmd.exe /d /s /c'"
  FZF_PREVIEW_COLUMNS_REF='%FZF_PREVIEW_COLUMNS%'
  __fzf_via_cmd=1
else
  FZF_PREVIEW_COLUMNS_REF='$FZF_PREVIEW_COLUMNS'
  __fzf_via_cmd=0
fi

# Previews shared with files.sh.
FZF_PREVIEW_FILE='bat --color=always --style=numbers,changes --line-range=:500 {}'
FZF_PREVIEW_DIR='eza --tree --level=2 --color=always --icons=always --group-directories-first --git-ignore {}'

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--multi --scheme=path --border-label=' files ' --preview='$FZF_PREVIEW_FILE'"
export FZF_ALT_C_COMMAND='fd --type directory --hidden --follow --strip-cwd-prefix'
export FZF_ALT_C_OPTS="--scheme=path --border-label=' cd ' --preview='$FZF_PREVIEW_DIR'"

# Ctrl+y copies the highlighted command instead of running it. Whichever
# clipboard tool this machine has; none in Git Bash, where fzf's commands run
# in cmd.exe and `echo -n` does not exist.
__fzf_clip=""
if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy &>/dev/null; then
  __fzf_clip='wl-copy'
elif [[ -n "$DISPLAY" ]] && command -v xclip &>/dev/null; then
  __fzf_clip='xclip -selection clipboard'
elif [[ -n "$WSL_DISTRO_NAME" ]]; then
  __fzf_clip='clip.exe'
fi
export FZF_CTRL_R_OPTS="--border-label=' history '"
if [[ -n "$__fzf_clip" ]] && ((!__fzf_via_cmd)); then
  FZF_CTRL_R_OPTS+=" --bind='ctrl-y:execute-silent(echo -n {2..} | $__fzf_clip)+abort' --header='ctrl-y copy'"
fi
unset __fzf_clip __fzf_via_cmd

# ** completion lists through fd, so it skips what .gitignore and fd/ignore
# skip, and previews what it lists.
_fzf_compgen_path() {
  fd --hidden --follow . "$1"
}
_fzf_compgen_dir() {
  fd --type directory --hidden --follow . "$1"
}
_fzf_comprun() {
  local command=$1
  shift
  case "$command" in
    cd | pushd | rmdir | tree) fzf --preview "$FZF_PREVIEW_DIR" "$@" ;;
    export | unset)            fzf --preview "eval 'echo \${}'" "$@" ;;

    *)                         fzf --preview "$FZF_PREVIEW_FILE" "$@" ;;
  esac
}

# Key bindings and completion, from the fzf binary itself so they always
# match its version (0.48+).
if [[ $- == *i* ]]; then
  eval "$(fzf --bash)"
fi

# Resolve the project directory for zj/tm: the argument if given,
# otherwise an fzf pick from directories under ~, searched $2 levels deep
# (default 3). Fails when cancelled.
__pick_project_dir() {
  if [[ -n "$1" ]]; then
    # -e: fail on a missing directory instead of resolving it anyway
    realpath -e "$1"
  else
    local dir
    dir=$(fd --type directory --max-depth "${2:-3}" --hidden . ~ |
      fzf --scheme=path --border-label=' project ' --preview "$FZF_PREVIEW_DIR")
    [[ -n "$dir" ]] && echo "$dir"
  fi
}

# Zellij session manager
# Always uses sessions — switch-session from inside, attach --create from outside
# With no args: fzf pick from project directories
zj() {
  local dir name

  dir="$(__pick_project_dir "$1")" || return

  name="$(basename "$dir" | tr '.' '_')"

  if [[ -n "$ZELLIJ" ]]; then
    zellij action switch-session "$name" --cwd "$dir"
  else
    zellij attach --create "$name" options --default-cwd "$dir"
  fi
}

# Tmux session manager, the tmux twin of zj
# switch-client from inside, new-session -A (attach or create) from outside
# With no args: fzf pick from project directories
tm() {
  local dir name

  # Five levels, like the tmux popups (tmux/scripts), two more than zj
  dir="$(__pick_project_dir "$1" 5)" || return

  name="$(basename "$dir" | tr '.' '_')"

  # "=" makes -t match the name exactly instead of by prefix
  if [[ -n "$TMUX" ]]; then
    tmux has-session -t "=$name" 2>/dev/null || tmux new-session -d -s "$name" -c "$dir"
    tmux switch-client -t "=$name"
  else
    tmux new-session -A -s "$name" -c "$dir"
  fi
}
