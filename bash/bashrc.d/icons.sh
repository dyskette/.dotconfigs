# Point locally installed apps at icon theme names. Their installers write an
# absolute path into Icon=, which bypasses the icon theme entirely. Zed's
# installer and JetBrains Toolbox rewrite these files on update, so rerun this
# afterwards.
function fix-icons() {
  local apps_dir="$HOME/.local/share/applications"
  local -A icons=(
    ["dev.zed.Zed.desktop"]="dev.zed.Zed"
    ["jetbrains-toolbox.desktop"]="jetbrains-toolbox"
    ["jetbrains-rider-*.desktop"]="jetbrains-rider"
    ["jetbrains-studio-*.desktop"]="android-studio"
  )
  local pattern file

  for pattern in "${!icons[@]}"; do
    for file in "$apps_dir"/$pattern; do
      [ -f "$file" ] || continue
      if grep -qx "Icon=${icons[$pattern]}" "$file"; then
        echo "ok      $(basename "$file")"
      else
        sed -i "s|^Icon=.*|Icon=${icons[$pattern]}|" "$file"
        echo "fixed   $(basename "$file") -> ${icons[$pattern]}"
      fi
    done
  done

  update-desktop-database "$apps_dir" 2>/dev/null
}
