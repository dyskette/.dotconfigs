#!/usr/bin/env bash
# build-pilot.sh [--test]
#
# Builds the pilot Zellij plugin and installs it where config.kdl loads it:
# compiles plugins/pilot for wasm32-wasip1 (adding the target through rustup
# when it is missing) and copies the result to plugins/pilot.wasm, which the
# Linux config loads as file:~/.config/zellij/plugins/pilot.wasm. The .wasm is
# a build output and is not committed.
#
# Running sessions keep the plugin they loaded. Restart a session, or run
# `zellij action start-or-reload-plugin pilot` in it, to pick up a new build.
#
# --test also runs the plugin's unit tests on the host target first.
#
# The Windows twin is Build-Pilot.ps1; keep the two in step.
set -euo pipefail

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
crate="$here/pilot"
target=wasm32-wasip1
output="$here/pilot.wasm"
run_tests=0

for argument in "$@"; do
  case $argument in
    --test | -Test) run_tests=1 ;;
    *)
      printf "build-pilot.sh: unknown argument '%s'; expected --test.\n" "$argument" >&2
      exit 2
      ;;
  esac
done

for tool in cargo rustup; do
  if ! command -v "$tool" >/dev/null; then
    printf '%s is not on PATH. Install Rust with rustup (linux/tasks/bin/rust.yml).\n' "$tool" >&2
    exit 1
  fi
done

if ! rustup target list --installed | grep -Fxq "$target"; then
  rustup target add "$target"
fi

if ((run_tests)); then
  # The tests only touch pure helpers, so they run natively; the host triple
  # overrides the wasm default in .cargo/config.toml.
  host=$(rustc -vV | sed -n 's/^host: //p')
  cargo test --manifest-path "$crate/Cargo.toml" --target "$host"
fi

cargo build --release --manifest-path "$crate/Cargo.toml" --target "$target"
install -m 644 "$crate/target/$target/release/pilot.wasm" "$output"
printf 'pilot.wasm: %s KB -> %s\n' "$(($(stat -c %s "$output") / 1024))" "$output"

# Grant the permissions pilot asks for, as answering Zellij's prompt once
# would. pilot runs in the background (load_plugins), and a session started
# with `zellij attach -b` has no client to show that prompt to, so without
# this the plugin stays inert until a session is opened by hand.
#
# Zellij keys the cache by the plugin path with ~ expanded and no file:
# prefix, as it writes it when you answer the prompt yourself (checked on
# 0.46.0).
cache="${XDG_CACHE_HOME:-$HOME/.cache}/zellij/permissions.kdl"
location="$HOME/.config/zellij/plugins/pilot.wasm"
# Keep this list in step with PERMISSIONS in pilot/src/main.rs: Zellij prompts
# again when the plugin asks for one that is not cached.
permissions=(
  ReadApplicationState ChangeApplicationState WriteToStdin RunCommands
  OpenTerminalsOrPlugins RunActionsAsUser ReadPaneContents
)

key="\"$location\" {"

# pilot's entry as it stands, written by this script or by Zellij's prompt
# (one node, its permissions as children, in any order).
granted=''
if [[ -f $cache ]]; then
  granted=$(awk -v key="$key" '
    index($0, key) == 1 { inside = 1; next }
    inside && $0 ~ /^}/ { inside = 0; next }
    inside { print }
  ' "$cache")
fi

missing=0
for permission in "${permissions[@]}"; do
  grep -qE "^[[:space:]]*${permission}[[:space:]]*$" <<<"$granted" || missing=1
done

if ((!missing)); then
  printf 'Permissions already granted in %s\n' "$cache"
  exit 0
fi

# Rewrite the file with pilot's node replaced, leaving every other plugin's
# alone.
mkdir -p "$(dirname "$cache")"
scratch=$(mktemp)
if [[ -f $cache ]]; then
  awk -v key="$key" '
    index($0, key) == 1 { inside = 1; next }
    inside && $0 ~ /^}/ { inside = 0; next }
    !inside { print }
  ' "$cache" >"$scratch"
fi
{
  printf '%s\n' "$key"
  printf '    %s\n' "${permissions[@]}"
  printf '}\n'
} >>"$scratch"
mv "$scratch" "$cache"
printf "Granted pilot's permissions in %s\n" "$cache"
