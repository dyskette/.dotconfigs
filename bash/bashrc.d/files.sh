function sd() {
  local directory_path

  directory_path="$(fd --type directory | \
    fzf \
      --layout=reverse \
      --height=50% \
      --min-height=20 \
      --preview 'eza --tree --git-ignore --level 2 --colour=always --icons=always {}')" \
  && cd $directory_path
}

function sf() {
  local file_path

  file_path="$(fd --type file | \
    fzf \
      --layout=reverse \
      --height=50% \
      --min-height=20 \
      --preview 'bat --color=always --style=plain {}')" \
  && nvim $file_path
}

function sg() {
  local search_query="$*"
  
  if [ -z "$search_query" ]; then
    search_query=""
  fi
  
  local exec_ripgrep='rg --column --color=always --smart-case {q} || :'
  local exec_nvim='nvim {1} +{2}'
  local exec_bat='bat --style=numbers --color=always --highlight-line {2} {1}'
  
  fzf \
    --disabled \
    --ansi \
    --bind "start:reload:$exec_ripgrep" \
    --bind "change:reload:$exec_ripgrep" \
    --bind "enter:become:$exec_nvim" \
    --layout reverse \
    --height 50% \
    --min-height 20 \
    --delimiter : \
    --preview "$exec_bat" \
    --preview-window "+{2}/2" \
    --query "$search_query"
}
