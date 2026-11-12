# Files, search and git through fd, fzf, ripgrep, bat, eza, yazi, lazygit and
# delta. fzf.sh (loaded first) sets their defaults and FZF_PREVIEW_FILE/DIR.
#
#   sf [query]    pick files, open them in nvim
#   sd [query]    pick a folder below this one, cd into it
#   sdf [query]   pick a file, cd into its folder
#   sg [pattern]  live ripgrep; Enter opens the hit in nvim at its line,
#                 several (Tab) open as nvim's quickfix list
#   y             yazi, cd-ing to where it was left
#   lg            lazygit, cd-ing to the repository it was left in
#   gsw           switch branch, log preview
#   glo [args]    browse git log with delta diffs, prints the picked hashes
#   ls ll la lt   eza;  cat: bat;  help CMD: CMD --help, coloured
#   e [dir]       open a folder in Windows File Explorer (WSL, Git Bash)

# Open a directory (default: the current one) in Windows File Explorer, from
# WSL or Git Bash. From WSL it opens as \\wsl.localhost\<distro>\..., so files
# can be dragged in and out of Linux folders.
function e() {
  local dir="${1:-.}"

  if [ -n "$WSL_DISTRO_NAME" ]; then
    explorer.exe "$(wslpath -w "$dir")"
  elif command -v cygpath &>/dev/null; then
    explorer.exe "$(cygpath -w "$dir")"
  else
    echo "e: Windows File Explorer is only reachable from WSL or Git Bash" >&2
    return 1
  fi
  # explorer.exe exits with 1 even when it opens the window.
  return 0
}

# --- eza and bat -------------------------------------------------------------

if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first --icons=auto --hyperlink'
  alias ll='eza --long --all --group-directories-first --icons=auto --git --header --time-style=relative --hyperlink'
  alias la='eza --all --group-directories-first --icons=auto --hyperlink'
  # lt [level] [path]: tree, two levels by default, gitignored files left out.
  lt() {
    local level=2
    if [[ "$1" =~ ^[0-9]+$ ]]; then
      level=$1
      shift
    fi
    eza --tree --level="$level" --group-directories-first --icons=auto --git-ignore "$@"
  }
fi

if command -v bat &>/dev/null; then
  # bat prints plain text by itself when piped, so `cat x | ...` is unchanged.
  alias cat='bat --paging=never --style=plain'
  # man pages through bat, with its theme; col strips man's backspace bold.
  export MANPAGER="sh -c 'col -bx | bat --language=man --plain'"
  export MANROFFOPT="-c"

  # help CMD [SUBCOMMAND...]: CMD's --help, coloured and paged.
  help() {
    "$@" --help 2>&1 | bat --plain --language=help
  }
fi

# --- Pickers -----------------------------------------------------------------

sf() {
  local files
  mapfile -t files < <(fd --type file --hidden --follow --strip-cwd-prefix |
    fzf --multi --scheme=path --query="$*" --border-label=' files ' --preview="$FZF_PREVIEW_FILE")
  ((${#files[@]})) && nvim "${files[@]}"
}

sd() {
  local dir
  dir="$(fd --type directory --hidden --follow --strip-cwd-prefix |
    fzf --scheme=path --query="$*" --preview="$FZF_PREVIEW_DIR")" && cd "$dir" || return
}

sdf() {
  local file
  file="$(fd --type file --hidden --follow --strip-cwd-prefix |
    fzf --scheme=path --query="$*" --preview="$FZF_PREVIEW_FILE")" && cd "$(dirname "$file")" || return
}

# Ctrl+f freezes the ripgrep results and fuzzy-filters them with fzf; Ctrl+r
# goes back to ripgrep. Inside a nvim terminal the files open in that nvim
# (flatten.nvim).
sg() {
  local rg='rg --column --line-number --no-heading --color=always -- {q}'
  local hits
  mapfile -t hits < <(fzf --ansi --disabled --multi --query="$*" \
    --delimiter=: --prompt='rg ❯ ' --border-label=' ripgrep ' \
    --header='ctrl-f fuzzy-filter these · ctrl-r back to ripgrep · tab select' \
    --bind="start:reload($rg)+unbind(ctrl-r)" \
    --bind="change:reload($rg)" \
    --bind='ctrl-f:unbind(change,ctrl-f)+change-prompt(fzf ❯ )+enable-search+clear-query+rebind(ctrl-r)' \
    --bind="ctrl-r:unbind(ctrl-r)+change-prompt(rg ❯ )+disable-search+reload($rg)+rebind(change,ctrl-f)" \
    --preview='bat --color=always --style=numbers,changes,header-filename --highlight-line={2} {1}' \
    --preview-window='+{2}/2' </dev/null)

  if ((${#hits[@]} == 1)); then
    local file="${hits[0]%%:*}" rest="${hits[0]#*:}"
    nvim "$file" "+${rest%%:*}"
  elif ((${#hits[@]} > 1)); then
    # :QuickfixLoad (nvim/lua/config/terminals.lua) reads file:line:col:text
    # and opens the list. Not `nvim -q`, which flatten.nvim hands to the outer
    # nvim without showing it. Read before nvim returns, so rm is safe.
    local list
    list="$(mktemp)"
    printf '%s\n' "${hits[@]}" >"$list"
    nvim "+QuickfixLoad $list"
    rm -f "$list"
  fi
}

# --- yazi and lazygit ----------------------------------------------------------

y() {
  local tmp cwd
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd <"$tmp"
  [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

lg() {
  local tmp dir
  tmp="$(mktemp -t "lazygit-dir.XXXXXX")"
  LAZYGIT_NEW_DIR_FILE="$tmp" lazygit "$@"
  dir="$(<"$tmp")"
  [[ -n "$dir" && "$dir" != "$PWD" ]] && builtin cd -- "$dir"
  rm -f -- "$tmp"
}

# --- Git -----------------------------------------------------------------------

alias glog="git log --decorate=full --oneline --graph"

gsw() {
  local branch
  branch="$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads refs/remotes |
    fzf --scheme=history --no-multi --border-label=' branches ' \
      --preview='git log --oneline --graph --color=always --decorate -n 50 {}')" || return
  # origin/feature -> a local feature tracking it, when there is none yet.
  if [[ "$branch" == */* ]] && ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git switch "${branch#*/}" 2>/dev/null && return
  fi
  git switch "$branch"
}

glo() {
  git log --color=always --date=short \
    --format='%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %s%C(auto)%d %C(blue)%an' "$@" |
    fzf --ansi --multi --no-sort --scheme=history --border-label=' log ' \
      --preview="git show --color=always {1} | delta --width=$FZF_PREVIEW_COLUMNS_REF" \
      --preview-window='down,70%,border-top' |
    cut -d' ' -f1
}
