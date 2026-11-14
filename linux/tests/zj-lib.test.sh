#!/usr/bin/env bash
# Tests for the pure helpers of the Zellij workspace commands
# (zellij/bin/zj-lib.sh): names, targets, the KDL the layout is filled with,
# the project scan and what zjr runs. Nothing here talks to Zellij.
#
# The Windows twin is windows/tests/Zellij.Tests.ps1 (Pester); both check the
# same rules, so a change to one usually belongs in the other.
#
#   ./linux/tests/zj-lib.test.sh
set -uo pipefail

repository=$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")")
# shellcheck source=zellij/bin/zj-lib.sh
source "$repository/zellij/bin/zj-lib.sh"

passed=0
failed=0

# check <name> <expected> <actual>
check() {
  if [[ $2 == "$3" ]]; then
    ((passed++))
  else
    ((failed++))
    printf '✗ %s\n    expected: %s\n    actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

# check_true <name> <command...>
check_true() {
  local name=$1
  shift
  if "$@"; then
    ((passed++))
  else
    ((failed++))
    printf '✗ %s: %s was false\n' "$name" "$*" >&2
  fi
}

# check_false <name> <command...>
check_false() {
  local name=$1
  shift
  if "$@"; then
    ((failed++))
    printf '✗ %s: %s was true\n' "$name" "$*" >&2
  else
    ((passed++))
  fi
}

# The target of a folder as "session|tab|dir".
target_of() {
  local fields
  mapfile -t fields < <(zj_target "$1" "$2")
  printf '%s|%s|%s' "${fields[0]}" "${fields[1]}" "${fields[2]}"
}

# What zjr would run, as "kind: command".
task_of() {
  if zj_project_task "$1" "$2"; then
    printf '%s: %s' "$ZJ_TASK_KIND" "${ZJ_TASK_CMD[*]}"
  else
    printf 'none'
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- Session names ------------------------------------------------------------

check 'a plain name is kept' 'acme' "$(zj_session_name acme)"
check 'spaces become underscores' 'my_client' "$(zj_session_name 'my client')"
check 'inner dots stay' 'app.v2' "$(zj_session_name app.v2)"
check 'a leading dot goes' 'dotconfigs' "$(zj_session_name .dotconfigs)"
check 'dots at both ends go' 'hidden' "$(zj_session_name '..hidden..')"
check 'a name of dots is a placeholder' '_' "$(zj_session_name '...')"

# --- Targets ------------------------------------------------------------------

root="$work/Projects"
mkdir -p "$root/acme/cerberus" "$root/acme/group/orders" "$root/sentinel" "$work/elsewhere/.tool"

check 'client and service' \
  "acme|cerberus|$root/acme/cerberus" "$(target_of "$root/acme/cerberus" "$root")"
check 'a group keeps the client and the leaf' \
  "acme|orders|$root/acme/group/orders" "$(target_of "$root/acme/group/orders" "$root")"
check 'a project at the root is its own session' \
  "sentinel|sentinel|$root/sentinel" "$(target_of "$root/sentinel" "$root")"
check 'a trailing separator changes nothing' \
  "acme|cerberus|$root/acme/cerberus" "$(target_of "$root/acme/cerberus/" "$root")"
check 'a folder outside the root is its own session' \
  "tool|.tool|$work/elsewhere/.tool" "$(target_of "$work/elsewhere/.tool" "$root")"
check 'the root itself is not a project of itself' \
  "Projects|Projects|$root" "$(target_of "$root" "$root")"

# --- The service layout -------------------------------------------------------

check 'quotes and backslashes are escaped' \
  '"a\\b\"c"' "$(zj_kdl_string 'a\b"c')"

layout_dir="$work/config/layouts"
mkdir -p "$layout_dir"
cp "$repository/zellij/linux/layouts/service.kdl" "$layout_dir/service.kdl"
ZELLIJ_CONFIG_DIR="$work/config"

filled=$(zj_service_layout 'api "v2"' "$root/acme/api")
check_true 'the tab gets its name and folder' \
  grep -Fq "ui name=\"api \\\"v2\\\"\" cwd=\"$root/acme/api\" focus=true" <<<"$filled"
check 'the anchor is gone, exactly once' \
  '0' "$(grep -c 'ui name="service" focus=true' <<<"$filled")"

printf 'layout { }\n' >"$layout_dir/service.kdl"
check_false 'a layout without the anchor is refused' \
  zj_service_layout tab "$root" 2>/dev/null

# --- The project scan ---------------------------------------------------------

mkdir -p "$root/acme/cerberus/src" "$root/.hidden" "$root/vendor/node_modules" "$root/vendor/keep"
touch "$root/acme/cerberus/package.json"

listing=$(zj_project_list "$root" 3)
check_true 'a client is listed' grep -Fxq 'acme' <<<"$listing"
check_true 'a service is listed' grep -Fxq 'acme/cerberus' <<<"$listing"
check_false 'a project is not descended into' grep -Fxq 'acme/cerberus/src' <<<"$listing"
check_false 'hidden folders are left out' grep -Fxq '.hidden' <<<"$listing"
check_false 'dependency folders are left out' grep -Fxq 'vendor/node_modules' <<<"$listing"
check_true 'their siblings are kept' grep -Fxq 'vendor/keep' <<<"$listing"
check_false 'the depth is respected' grep -Fq 'acme/group/orders/' <<<"$listing"

check_true 'a folder with a marker is a project' zj_is_project "$root/acme/cerberus"
check_false 'a folder without one is not' zj_is_project "$root/acme"

# --- What zjr runs ------------------------------------------------------------

project="$work/kind"
new_project() {
  rm -rf "$project"
  mkdir -p "$project"
}

new_project
touch "$project/Cargo.toml"
check 'rust dev' 'rust: cargo run' "$(task_of "$project" dev)"
check 'rust test' 'rust: cargo test' "$(task_of "$project" test)"

new_project
touch "$project/go.mod"
check 'go dev' 'go: go run .' "$(task_of "$project" dev)"
check 'go test' 'go: go test ./...' "$(task_of "$project" test)"

new_project
printf '{ "scripts": { "dev": "vite", "test": "vitest" } }\n' >"$project/package.json"
touch "$project/pnpm-lock.yaml"
check 'the lockfile picks the manager' 'node: pnpm run dev' "$(task_of "$project" dev)"
check 'node test' 'node: pnpm run test' "$(task_of "$project" test)"

new_project
printf '{ "scripts": { "start": "node ." } }\n' >"$project/package.json"
check 'start stands in for dev' 'node: npm run start' "$(task_of "$project" dev)"
check 'a missing script has no command' 'none' "$(task_of "$project" build)"

new_project
touch "$project/pyproject.toml" "$project/manage.py" "$project/uv.lock"
check 'django through uv' 'python: uv run manage.py runserver' "$(task_of "$project" dev)"
check 'pytest through uv' 'python: uv run pytest' "$(task_of "$project" test)"

new_project
touch "$project/pom.xml"
check 'maven without a wrapper' 'maven: mvn spring-boot:run' "$(task_of "$project" dev)"
install -m 755 /dev/null "$project/mvnw"
check 'the wrapper wins' 'maven: ./mvnw spring-boot:run' "$(task_of "$project" dev)"

new_project
mkdir -p "$project/src/Web"
printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' >"$project/src/Web/Web.csproj"
touch "$project/App.sln"
check 'dotnet watches the web project' \
  'dotnet: dotnet watch --project src/Web/Web.csproj' "$(task_of "$project" dev)"
check 'dotnet test runs at the root' 'dotnet: dotnet test' "$(task_of "$project" test)"

new_project
printf 'services: {}\n' >"$project/compose.yaml"
check 'a monorepo falls back to compose' 'compose: docker compose up' "$(task_of "$project" dev)"
check 'and has nothing to test' 'none' "$(task_of "$project" test)"

new_project
printf '{ "dev": "make serve" }\n' >"$project/.zjr.json"
touch "$project/Cargo.toml"
check '.zjr.json wins over the project kind' \
  'custom: bash -c make serve' "$(task_of "$project" dev)"
check 'a task it does not name falls through' 'rust: cargo test' "$(task_of "$project" test)"

# --- The inbox ----------------------------------------------------------------

check 'a plain state' $'\033]7501;state=working\033\\' "$(zj_status working)"
check 'a message is base64' $'\033]7501;state=error:msg=b2s=:app=zjr\033\\' "$(zj_status error ok zjr)"

# --- Claude Code's folder key -------------------------------------------------

# /tmp and not /home: Claude Code keys the folder it is in, and so does this,
# so the path is resolved first (/home, /opt and /srv are symlinks into /var
# on Fedora Silverblue).
check 'every other character becomes a dash' \
  '-tmp-me--app' "$(zj_claude_project_key /tmp/me/.app)"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
