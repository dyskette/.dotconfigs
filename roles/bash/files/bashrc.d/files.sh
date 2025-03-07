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
