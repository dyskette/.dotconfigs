# Python virtual environments.
#
# Neovim no longer needs this: basedpyright finds a project's .venv on its own
# and ruff is a static binary, so the editor is correct in any shell. What
# still needs a real activation is *running* things -- pytest, python, the
# tools a project installs into its own environment.
#
# `venv` is that activation, on demand. It walks up from the current directory
# the way git does looking for .git, so it works from anywhere inside a repo
# rather than only at its root.
#
#   venv          activate the nearest environment
#   venv <path>   activate a specific one
#   venv off      deactivate

# Directory names treated as a virtual environment, tried in this order at each
# level. Override in ~/.secrets or before this file is sourced.
VENV_DIR_NAMES="${VENV_DIR_NAMES:-.venv venv .env}"

# Prints the activate script of the environment in $1, if it holds one.
# Handles both layouts: bin/ on Unix, Scripts/ for a venv created on Windows
# and reached through Git Bash.
__venv_activate_script() {
  local dir="$1"

  if [[ -f "$dir/bin/activate" ]]; then
    printf '%s' "$dir/bin/activate"
  elif [[ -f "$dir/Scripts/activate" ]]; then
    printf '%s' "$dir/Scripts/activate"
  else
    return 1
  fi
}

# Prints the nearest environment at or above $1.
__venv_find() {
  local dir="$1" name

  while true; do
    for name in $VENV_DIR_NAMES; do
      if __venv_activate_script "$dir/$name" >/dev/null; then
        printf '%s' "$dir/$name"
        return 0
      fi
    done

    [[ "$dir" == "/" ]] && return 1
    dir="${dir%/*}"
    [[ -z "$dir" ]] && dir="/"
  done
}

venv() {
  local target script

  case "${1-}" in
    off | -d | --deactivate)
      if ! declare -F deactivate >/dev/null; then
        echo "venv: nothing is active" >&2
        return 1
      fi
      deactivate
      return 0
      ;;
    -h | --help)
      echo "usage: venv [<path> | off]"
      echo "  no argument  activate the nearest environment ($VENV_DIR_NAMES)"
      echo "  <path>       activate the environment in <path>"
      echo "  off          deactivate the active environment"
      return 0
      ;;
    "")
      if ! target="$(__venv_find "$PWD")"; then
        echo "venv: no environment at or above $PWD" >&2
        return 1
      fi
      ;;
    *)
      target="${1%/}"
      ;;
  esac

  if ! script="$(__venv_activate_script "$target")"; then
    echo "venv: $target is not a virtual environment" >&2
    return 1
  fi

  # Leaving the current one first is what makes this "switch to that project's
  # environment" rather than stacking another PATH entry on top of the last.
  declare -F deactivate >/dev/null && deactivate

  # shellcheck disable=SC1090
  . "$script"

  echo "venv: ${VIRTUAL_ENV:-$target}"
}
