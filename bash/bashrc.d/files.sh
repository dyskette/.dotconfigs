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

function sd() {
  local directory_path

  directory_path="$(fd --type directory | \
    fzf \
      --layout=reverse \
      --height=50% \
      --min-height=20 \
      --border=none \
      --preview-window=border-left \
      --preview 'eza --tree --git-ignore --level 2 --colour=always --icons=always {}')"
  
  if [ -n "$directory_path" ]; then
    cd "$directory_path"
  fi
}

function sf() {
  local file_path

  file_path="$(fd --type file | \
    fzf \
      --layout=reverse \
      --height=50% \
      --min-height=20 \
      --border=none \
      --preview-window=border-left \
      --preview 'echo -e "📄 Previewing: {}\n-----------------------------\n"; bat --color=always --style=numbers,changes,snip {}')"
  
  if [ -n "$file_path" ]; then
    nvim "$file_path"
  fi
}

function sg() {
  local search_query="$*"
  
  if [ -z "$search_query" ]; then
    search_query=""
  fi
  
  local exec_ripgrep='rg --column --color=always --smart-case {q} || :'
  local exec_nvim='nvim {1} +{2}'
  local exec_bat='bat --style=numbers,changes,snip --color=always --highlight-line {2} {1}'
  
  fzf \
    --disabled \
    --ansi \
    --bind "start:reload:$exec_ripgrep" \
    --bind "change:reload:$exec_ripgrep" \
    --bind "enter:become:$exec_nvim" \
    --layout reverse \
    --height 50% \
    --min-height 20 \
    --border=none \
    --preview-window=border-left,"+{2}/2" \
    --delimiter : \
    --preview "$exec_bat" \
    --query "$search_query"
}
