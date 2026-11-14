# shellcheck shell=bash
# Shared helpers for the Zellij workspace commands on Linux: zj (projects),
# zja (agent), zjr (dev/test/build) and zj-hub-projects (the hub's project
# list). Sourced by the scripts beside this file, never run on its own.
#
# The PowerShell half is powershell/Zellij.psm1 and the plugin they talk to is
# zellij/plugins/pilot; both follow the same rules, so keep them in step
# (zellij/README.md has the whole workflow).
#
# Projects live under $ZJ_PROJECTS as <client>/<service> (or
# <client>/<group>/<service>). Each client is one Zellij session and each
# service one tab in it, so `zj acme/cerberus` lands in session "acme", tab
# "cerberus". A project directly under the root is its own session with one
# tab.

# Files whose presence makes a folder a project: the hub lists it and stops
# descending, and zjr knows what to run in it.
ZJ_PROJECT_MARKERS=(
  .git '*.sln' '*.slnx' '*.csproj' package.json pyproject.toml
  requirements.txt Cargo.toml go.mod pom.xml build.gradle build.gradle.kts
)

# Folder names the project scan never enters or lists.
ZJ_SKIP_DIRS='node_modules|bin|obj|dist|target|__MACOSX'

# --- Paths and names ----------------------------------------------------------

# The folder that holds the client folders: $ZJ_PROJECTS, else whichever of
# ~/Projects and ~/Proyectos holds folders (this machine keeps them in the
# Spanish one; Windows uses ~/Projects). ~/Projects is the answer when neither
# does, so a fresh machine has a root to create.
zj_project_root() {
  local root="${ZJ_PROJECTS:-}" candidate
  if [[ -z $root ]]; then
    root="$HOME/Projects"
    for candidate in "$HOME/Projects" "$HOME/Proyectos"; do
      if compgen -G "$candidate/*/" >/dev/null; then
        root=$candidate
        break
      fi
    done
  fi
  printf '%s\n' "${root%/}"
}

# An absolute, normalised path (the folder need not exist). Symlinks are
# resolved so a folder reached two ways is one session.
zj_abs_path() {
  realpath -m -- "$1"
}

# A Zellij session name from a folder name: anything but letters, digits,
# '-', '_' and '.' becomes '_' (session names end up in socket and file
# paths), and leading or trailing dots go.
#
# Zellij 0.46 cannot list or reach a session whose name starts or ends with a
# dot, so ~/.dotconfigs becomes session "dotconfigs". The rule is Windows's
# (powershell/Zellij.psm1) and is kept here so both machines name the same
# folder the same way.
zj_session_name() {
  local clean
  clean=$(printf '%s' "$1" | sed -e 's/[^[:alnum:]._-]/_/g' -e 's/^\.*//' -e 's/\.*$//')
  printf '%s\n' "${clean:-_}"
}

# Where a folder opens. Prints three lines: the session (its client), the tab
# (its own name) and the folder itself. A folder outside the projects root is
# its own session.
#
#   zj_target <folder> [root]
zj_target() {
  local dir root leaf client rel
  dir=$(zj_abs_path "$1")
  root=$(zj_abs_path "${2:-$(zj_project_root)}")
  dir=${dir%/}
  root=${root%/}
  leaf=${dir##*/}

  client=$leaf
  if [[ $dir == "$root"/* ]]; then
    rel=${dir#"$root"/}
    client=${rel%%/*}
  fi

  printf '%s\n%s\n%s\n' "$(zj_session_name "$client")" "$leaf" "$dir"
}

# Zellij's own config folder: where layouts/service.kdl is read from.
zj_config_dir() {
  printf '%s\n' "${ZELLIJ_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zellij}"
}

# Zellij's temp folder, which the hub plugin sees as /tmp.
zj_tmp_dir() {
  printf '%s\n' "${ZELLIJ_TMP_DIR:-${TMPDIR:-/tmp}/zellij-$(id -u)}"
}

# Quote a string for a KDL document.
zj_kdl_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

# The service layout for one tab, with its name and folder filled in.
#
# layouts/service.kdl names its tab "service" and has no cwd, so it also works
# as a plain layout file. Zellij's --cwd is ignored for sessions started in the
# background, and a layout passed to an existing session cannot be renamed
# afterwards, so the name and folder go into the KDL.
#
#   zj_service_layout <tab name> <folder>
zj_service_layout() {
  local name=$1 dir=$2 file template
  local anchor='ui name="service" focus=true'

  file="$(zj_config_dir)/layouts/service.kdl"
  if [[ ! -r $file ]]; then
    printf 'zj: cannot read %s\n' "$file" >&2
    return 1
  fi
  template=$(<"$file")
  if [[ $template != *"$anchor"* ]]; then
    printf "zj: %s no longer contains '%s'; update zj_service_layout to match it\n" "$file" "$anchor" >&2
    return 1
  fi

  local tab
  tab="ui name=$(zj_kdl_string "$name") cwd=$(zj_kdl_string "$dir") focus=true"
  printf '%s\n' "${template/"$anchor"/"$tab"}"
}

# --- Zellij calls -------------------------------------------------------------

# The sessions Zellij knows, one per line: name, 1/0 exited, 1/0 current,
# tab separated. Exited sessions are the resurrectable ones.
zj_sessions() {
  zellij list-sessions --no-formatting 2>/dev/null |
    awk '/^[^ ]+ \[Created /{
      printf "%s\t%d\t%d\n", $1, (index($0, "(EXITED") ? 1 : 0), (index($0, "(current)") ? 1 : 0)
    }'
}

# Whether a session is running or resurrectable.
zj_session_exists() {
  zj_sessions | cut -f1 | grep -Fxq -- "$1"
}

# A session's tabs, one per line: id, position, name, tab separated.
zj_tabs() {
  zellij --session "$1" action list-tabs 2>/dev/null |
    awk 'match($0, /^[0-9]+[ \t]+[0-9]+[ \t]+/) {
      id = $1; position = $2;
      name = substr($0, RLENGTH + 1); sub(/[ \t]+$/, "", name);
      printf "%s\t%s\t%s\n", id, position, name
    }'
}

# Wait until a session has a client attached, so a tab added to it gets a real
# size (a session nobody looks at is too small for the layout).
#
#   zj_wait_client <session> [timeout seconds]
zj_wait_client() {
  local session=$1 timeout=${2:-15} waited=0
  while ((waited < timeout * 10)); do
    if zellij --session "$session" action list-clients 2>/dev/null | grep -qE '^[0-9]+[ \t]'; then
      return 0
    fi
    sleep 0.1
    ((waited++))
  done
  return 1
}

# In a session with a client, focus the target's tab, adding it first if it is
# missing.
#
#   zj_open_tab <session> <tab> <folder>
zj_open_tab() {
  local session=$1 tab=$2 dir=$3 layout
  if zj_tabs "$session" | cut -f3 | grep -Fxq -- "$tab"; then
    zellij --session "$session" action go-to-tab-name "$tab" >/dev/null 2>&1
    return
  fi
  # With --session, --layout-string adds the tab to that session and focuses
  # it for the clients in it.
  layout=$(zj_service_layout "$tab" "$dir") || return 1
  zellij --session "$session" --layout-string "$layout" >/dev/null 2>&1
}

# Open a target: its session, then its tab, from inside Zellij or outside.
#
#   zj_open_target <session> <tab> <folder>
zj_open_target() {
  local session=$1 tab=$2 dir=$3 exists=0 payload file waiter

  zj_session_exists "$session" && exists=1

  if [[ -n ${ZELLIJ:-} ]]; then
    if [[ ${ZELLIJ_SESSION_NAME:-} == "$session" ]]; then
      zj_open_tab "$session" "$tab" "$dir"
      return
    fi
    # `zellij action switch-session` would move the CLI's own connection, not
    # this client; the pilot plugin moves the client focused on this pane
    # (zellij/plugins/pilot, "switch").
    payload='-'
    if ((!exists)); then
      payload=$(zj_service_layout "$tab" "$dir") || return 1
    fi
    zellij pipe --name switch --args "session=$session,pane=${ZELLIJ_PANE_ID:-}" -- "$payload" >/dev/null
    if ((exists)) && zj_wait_client "$session"; then
      zj_open_tab "$session" "$tab" "$dir"
    fi
    return
  fi

  if ((!exists)); then
    # --new-session-with-layout reads a file, and only at start-up, so the
    # file can go when the client returns (detach or quit).
    file=$(mktemp --tmpdir "zj-$session-XXXXXXXX.kdl") || return 1
    if ! zj_service_layout "$tab" "$dir" >"$file"; then
      rm -f "$file"
      return 1
    fi
    zellij --session "$session" --new-session-with-layout "$file"
    rm -f "$file"
    return
  fi

  # An existing (or resurrectable) session: the tab is added or focused once
  # this client is in, from the background, because attaching holds the
  # terminal until detach.
  (zj_wait_client "$session" 30 && zj_open_tab "$session" "$tab" "$dir") &
  waiter=$!
  zellij attach "$session"
  kill "$waiter" 2>/dev/null
  wait "$waiter" 2>/dev/null
  return 0
}

# --- The lobby ----------------------------------------------------------------

# Start the session hub's lobby: Zellij showing the hub full screen, until it
# is quit there with q.
#
# Each round starts a throwaway session named lobby-<id> with the lobby layout
# (zellij/layouts/lobby.kdl). Picking something in the hub moves this client to
# that session; when the client later detaches or the session ends, the hub
# comes back. Quitting the hub with q leaves a marker file, which ends the
# loop. Lobbies are deleted by the pilot plugin once nobody is in them.
zj_lobby() {
  local name marker started code

  while true; do
    printf -v name 'lobby-%04x%04x' "$RANDOM" "$RANDOM"
    marker="$(zj_tmp_dir)/hub-quit-$name"
    started=$SECONDS

    zellij --session "$name" --new-session-with-layout lobby
    code=$?

    if [[ -e $marker ]]; then
      rm -f "$marker"
      return 0
    fi
    # Zellij failing to start (a config error, say) must not spin.
    if ((code != 0 || SECONDS - started < 2)); then
      printf 'zj: Zellij ended right away (exit code %d); not starting the hub again.\n' "$code" >&2
      return "$code"
    fi
  done
}

# --- Projects -----------------------------------------------------------------

# Whether a folder is a project (any of the marker files).
zj_is_project() {
  local dir=$1 marker
  for marker in "${ZJ_PROJECT_MARKERS[@]}"; do
    compgen -G "$dir/$marker" >/dev/null && return 0
  done
  return 1
}

# The folders the hub offers, relative to the root: every folder down to
# <depth>, without descending into projects (their src/ and docs/ are not
# services) or hidden and dependency folders.
#
#   zj_project_list [root] [depth]
zj_project_list() {
  local root=${1:-$(zj_project_root)} depth=${2:-3}
  _zj_walk_projects "$root" '' 0 "$depth"
}

# One level of zj_project_list; the glob sorts each level by name.
_zj_walk_projects() {
  local base=$1 prefix=$2 level=$3 depth=$4 entry name rel
  for entry in "$base"/*/; do
    [[ -d $entry ]] || continue
    name=${entry%/}
    name=${name##*/}
    [[ $name == .* ]] && continue
    [[ $name =~ ^($ZJ_SKIP_DIRS)$ ]] && continue

    rel="${prefix}${name}"
    printf '%s\n' "$rel"
    if ((level + 1 < depth)) && ! zj_is_project "$base/$name"; then
      _zj_walk_projects "$base/$name" "$rel/" $((level + 1)) "$depth"
    fi
  done
}

# --- Agents -------------------------------------------------------------------

# Claude Code's folder name for a project: every character that is not a letter
# or digit becomes '-' (/home/me/.app -> -home-me--app).
zj_claude_project_key() {
  printf '%s' "$(zj_abs_path "$1")" | sed 's/[^A-Za-z0-9]/-/g'
}

# Whether an agent has a conversation to continue in a folder. Only OpenCode
# and Claude Code are known; any other agent answers no.
#
# OpenCode: `opencode session list` lists the folder's project sessions
# (~120 ms through its background service); nothing listed, or an error, means
# start fresh. Claude Code: a transcript in ~/.claude/projects.
#
#   zj_agent_has_conversation <agent> <folder>
zj_agent_has_conversation() {
  local agent=$1 dir=$2 config

  case $agent in
    opencode)
      (cd "$dir" && opencode session list --max-count 1 2>/dev/null) | grep -q '^ses_'
      ;;
    claude)
      config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
      compgen -G "$config/projects/$(zj_claude_project_key "$dir")/*.jsonl" >/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# --- The inbox ----------------------------------------------------------------

# Write the OSC 7501 sequence that tells Zellij's inbox what a program is
# doing: idle, working, done, blocked, error or clear (removes the status).
#
#   zj_status <state> [message] [app]
#
# https://zellij.dev/documentation/inbox-integrations.html
zj_status() {
  local message=${2:-} app=${3:-} fields="state=$1"
  [[ -n $message ]] && fields+=":msg=$(printf '%s' "$message" | base64 -w0)"
  [[ -n $app ]] && fields+=":app=$app"
  printf '\033]7501;%s\033\\' "$fields"
}

# --- What zjr runs ------------------------------------------------------------

# What zjr runs for a task in a project folder. Sets ZJ_TASK_KIND and the
# ZJ_TASK_CMD array (the program and its arguments); returns 1 when there is no
# command for the task.
#
# A .zjr.json in the folder wins ({"dev": "...", "test": "...", "build": "..."},
# each a shell command line). Otherwise the project kind decides:
#
#   dotnet  Aspire AppHost: aspire run (or dotnet run --project); else
#           dotnet watch on the web project (or the only project);
#           dotnet test / dotnet build at the root
#   node    the lockfile picks pnpm, bun, yarn or npm; dev runs the "dev"
#           script (or "start"), test and build their scripts
#   python  uv run (python without uv): manage.py runserver, main.py or
#           app.py; pytest
#   rust    cargo run / test / build
#   go      go run . / go test ./... / go build ./...
#   maven   (./mvnw or mvn) spring-boot:run / test / package
#   gradle  (./gradlew or gradle) bootRun / test / build
#
# A folder with none of those (a monorepo) still gets a dev command: its Aspire
# AppHost up to three levels down, else docker compose up.
#
#   zj_project_task <folder> <dev|test|build>

# Record the answer of zj_project_task: its kind, then the command. Both are
# read by the caller (zjr), not here.
# shellcheck disable=SC2034
_zj_task() {
  ZJ_TASK_KIND=$1
  shift
  ZJ_TASK_CMD=("$@")
}

zj_project_task() {
  local dir=$1 task=$2
  # Both are the answer, read by the caller (zjr), not here.
  # shellcheck disable=SC2034
  ZJ_TASK_KIND=''
  # shellcheck disable=SC2034
  ZJ_TASK_CMD=()

  # .zjr.json: the folder says what to run, as a shell command line.
  local override="$dir/.zjr.json" line
  if [[ -f $override ]] && command -v jq >/dev/null; then
    line=$(jq -r --arg task "$task" 'if has($task) then .[$task] else empty end' "$override" 2>/dev/null)
    if [[ -n $line ]]; then
      _zj_task custom bash -c "$line"
      return 0
    fi
  fi

  if compgen -G "$dir/*.sln" >/dev/null || compgen -G "$dir/*.slnx" >/dev/null ||
    compgen -G "$dir/*.csproj" >/dev/null; then
    _zj_dotnet_task "$dir" "$task"
    return
  fi

  if [[ -f "$dir/package.json" ]]; then
    _zj_node_task "$dir" "$task"
    return
  fi

  if [[ -f "$dir/pyproject.toml" || -f "$dir/requirements.txt" ]]; then
    _zj_python_task "$dir" "$task"
    return
  fi

  if [[ -f "$dir/Cargo.toml" ]]; then
    _zj_task rust cargo "$([[ $task == dev ]] && echo run || echo "$task")"
    return 0
  fi

  if [[ -f "$dir/go.mod" ]]; then
    case $task in
      dev) _zj_task go go run . ;;
      test) _zj_task go go test ./... ;;
      build) _zj_task go go build ./... ;;
    esac
    return 0
  fi

  if [[ -f "$dir/pom.xml" ]]; then
    local mvn=mvn
    [[ -x "$dir/mvnw" ]] && mvn=./mvnw
    case $task in
      dev) _zj_task maven "$mvn" spring-boot:run ;;
      test) _zj_task maven "$mvn" test ;;
      build) _zj_task maven "$mvn" package ;;
    esac
    return 0
  fi

  if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]]; then
    local gradle=gradle
    [[ -x "$dir/gradlew" ]] && gradle=./gradlew
    case $task in
      dev) _zj_task gradle "$gradle" bootRun ;;
      *) _zj_task gradle "$gradle" "$task" ;;
    esac
    return 0
  fi

  _zj_monorepo_task "$dir" "$task"
}

# The .csproj files of a solution, three levels down at most, build output and
# dependencies left out.
_zj_dotnet_projects() {
  find "$1" -maxdepth 4 -name '*.csproj' -type f \
    -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null | sort
}

# Whether a project file is an Aspire AppHost.
_zj_is_apphost() {
  grep -qE 'Aspire\.AppHost\.Sdk|<IsAspireHost>[[:space:]]*true' "$1" 2>/dev/null
}

_zj_dotnet_task() {
  local dir=$1 task=$2 project web='' single='' count=0

  if [[ $task != dev ]]; then
    _zj_task dotnet dotnet "$task"
    return 0
  fi

  while IFS= read -r project; do
    [[ -n $project ]] || continue
    ((count++))
    single=$project
    if _zj_is_apphost "$project"; then
      if command -v aspire >/dev/null; then
        _zj_task dotnet aspire run
      else
        _zj_task dotnet dotnet run --project "$(realpath --relative-to="$dir" "$project")"
      fi
      return 0
    fi
    if [[ -z $web ]] && grep -q 'Sdk="Microsoft\.NET\.Sdk\.Web"' "$project" 2>/dev/null; then
      web=$project
    fi
  done < <(_zj_dotnet_projects "$dir")

  local target=${web:-}
  [[ -z $target && $count -eq 1 ]] && target=$single
  if [[ -n $target ]]; then
    _zj_task dotnet dotnet watch --project "$(realpath --relative-to="$dir" "$target")"
    return 0
  fi
  return 1
}

_zj_node_task() {
  local dir=$1 task=$2 manager=npm script=''

  if [[ -f "$dir/pnpm-lock.yaml" ]]; then
    manager=pnpm
  elif [[ -f "$dir/bun.lock" || -f "$dir/bun.lockb" ]]; then
    manager=bun
  elif [[ -f "$dir/yarn.lock" ]]; then
    manager=yarn
  fi

  if command -v jq >/dev/null; then
    local candidates=("$task")
    [[ $task == dev ]] && candidates=(dev start)
    local candidate
    for candidate in "${candidates[@]}"; do
      if jq -e --arg s "$candidate" '.scripts // {} | has($s)' "$dir/package.json" >/dev/null 2>&1; then
        script=$candidate
        break
      fi
    done
  else
    # Without jq the scripts cannot be read; dev is the usual one.
    script=$([[ $task == dev ]] && echo dev || echo "$task")
  fi

  [[ -n $script ]] || return 1
  _zj_task node "$manager" run "$script"
}

_zj_python_task() {
  local dir=$1 task=$2 run=(python) entry

  if [[ -f "$dir/uv.lock" ]] || command -v uv >/dev/null; then
    run=(uv run)
  fi

  case $task in
    test) _zj_task python "${run[@]}" pytest ;;
    build)
      command -v uv >/dev/null || return 1
      _zj_task python uv build
      ;;
    dev)
      if [[ -f "$dir/manage.py" ]]; then
        _zj_task python "${run[@]}" manage.py runserver
        return 0
      fi
      for entry in main.py app.py; do
        if [[ -f "$dir/$entry" ]]; then
          _zj_task python "${run[@]}" "$entry"
          return 0
        fi
      done
      return 1
      ;;
  esac
}

# Monorepos with nothing at the root: the whole stack through its Aspire
# AppHost (aspire run finds it), or through docker compose. AppHosts come as a
# project (Aspire.AppHost.Sdk) or, since Aspire 13, as a single apphost.cs.
_zj_monorepo_task() {
  local dir=$1 task=$2 candidate compose

  [[ $task == dev ]] || return 1

  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    if [[ $candidate == *.cs ]] || _zj_is_apphost "$candidate"; then
      if command -v aspire >/dev/null; then
        _zj_task aspire aspire run
      elif [[ $candidate == *.cs ]]; then
        _zj_task aspire dotnet run "$(realpath --relative-to="$dir" "$candidate")"
      else
        _zj_task aspire dotnet run --project "$(realpath --relative-to="$dir" "$candidate")"
      fi
      return 0
    fi
  done < <(find "$dir" -maxdepth 4 \( -name '*.csproj' -o -name 'apphost.cs' \) -type f \
    -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null | sort)

  for compose in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [[ -f "$dir/$compose" ]]; then
      _zj_task compose docker compose up
      return 0
    fi
  done
  return 1
}
