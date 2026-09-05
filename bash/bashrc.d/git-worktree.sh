# Git worktree <-> zellij session manager
#
# One zellij session per worktree. New worktrees are created in the same layout
# Zed uses for its agent worktrees, so both tools operate on one tree:
#
#   $GW_ROOT/<repo>/<slug>/<repo>
#   ~/Projects/worktrees/time-pro/feature-starting/time-pro
#
# Discovery always goes through `git worktree list`, never through directory
# naming, so worktrees made by Zed, by plain git, or by `gw new` all show up
# here whatever their layout.
#
# Session names: "<repo>" for the main worktree, "<repo>--<slug>" for the rest.
# The main worktree therefore lands in the same session `zj` would create.

GW_ROOT="${GW_ROOT:-$HOME/Projects/worktrees}"

# --- helpers ----------------------------------------------------------------

# Safe for a directory name: keeps dots, collapses everything else.
__gw_dir_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }

# Safe for a zellij session name. Dots are replaced because zellij derives
# on-disk cache/socket paths from the session name.
__gw_session_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

# Repo name for any worktree, taken from the shared git dir so that every
# worktree of a repo agrees on it (leaf basenames do not - Zed's layout repeats
# the repo name at the leaf).
__gw_repo_name() {
  local common base
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  base=$(basename "$common")
  if [[ "$base" == ".git" || "$base" == ".bare" ]]; then
    basename "$(dirname "$common")"
  else
    basename "${base%.git}"
  fi
}

# The part of a worktree path that distinguishes it from its siblings: the
# parent directory in Zed's <slug>/<repo> layout, the leaf otherwise.
__gw_slug() {
  local path="$1" repo="$2" leaf
  leaf=$(basename "$path")
  if [[ "$leaf" == "$repo" ]]; then
    basename "$(dirname "$path")"
  else
    printf '%s' "$leaf"
  fi
}

__gw_session() {
  local repo="$1" slug="$2"
  if [[ -z "$slug" ]]; then
    __gw_session_slug "$repo"
  else
    printf '%s--%s' "$(__gw_session_slug "$repo")" "$(__gw_session_slug "$slug")"
  fi
}

# Emit every known worktree as: <display>\t<path>\t<session>
__gw_enumerate() {
  local -A seen=()
  local -a roots=()
  local top d root repo main path branch line label slug

  # The repo we are standing in, plus every worktree parked under GW_ROOT.
  # One worktree per repo is enough - `git worktree list` yields the siblings.
  top=$(git rev-parse --show-toplevel 2>/dev/null) && roots+=("$top")
  for d in "$GW_ROOT"/*/*/*; do
    [[ -e "$d/.git" ]] && roots+=("$d")
  done
  (( ${#roots[@]} )) || return 0

  for root in "${roots[@]}"; do
    repo=$(__gw_repo_name "$root") || continue
    main=""
    path=""
    branch=""
    while IFS= read -r line; do
      case "$line" in
        'worktree '*) path="${line#worktree }" ;;
        'branch '*) branch="${line#branch refs/heads/}" ;;
        detached) branch="(detached)" ;;
        bare) path="" ;;
        "")
          if [[ -n "$path" ]]; then
            [[ -z "$main" ]] && main="$path"
            if [[ -z "${seen[$path]}" ]]; then
              seen["$path"]=1
              if [[ "$path" == "$main" ]]; then
                slug=""
                label="$repo"
              else
                slug=$(__gw_slug "$path" "$repo")
                label="$repo/$slug"
              fi
              printf '%-34s  %-30s\t%s\t%s\n' \
                "$label" "$branch" "$path" "$(__gw_session "$repo" "$slug")"
            fi
          fi
          path=""
          branch=""
          ;;
      esac
    done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
  done
}

__gw_pick() {
  __gw_enumerate | fzf --reverse --height=50% \
    --border=none \
    --delimiter=$'\t' \
    --with-nth=1 \
    --header="${1:-select worktree}" \
    --preview-window=border-left \
    --preview 'git -C {2} -c color.status=always status --short --branch 2>/dev/null; echo; git -C {2} log --oneline --decorate --color=always -8 2>/dev/null'
}

# Switch into a session from inside zellij, attach from outside.
__gw_attach() {
  local name="$1" dir="$2"
  if [[ -n "$ZELLIJ" ]]; then
    zellij action switch-session "$name" --cwd "$dir"
  else
    zellij attach --create "$name" options --default-cwd "$dir"
  fi
}

# Seed a fresh worktree with the things git leaves behind: ignored env files,
# local settings, certs. Both files live in the shared git dir, so they are
# written once per repo and are never committed.
#
#   .git/info/worktree-copy  - newline-separated paths (globs ok), relative to
#                              the main worktree, copied into the new one
#   .git/info/worktree-init  - executable hook, run inside the new worktree
#                              with GW_REPO / GW_BRANCH / GW_MAIN / GW_WORKTREE
__gw_seed() {
  local main="$1" new="$2" repo="$3" branch="$4"
  local common list hook entry src

  common=$(git -C "$new" rev-parse --path-format=absolute --git-common-dir) || return 1
  list="$common/info/worktree-copy"
  hook="$common/info/worktree-init"

  if [[ -f "$list" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      for src in "$main"/$entry; do
        [[ -e "$src" ]] || continue
        mkdir -p "$new/$(dirname "${src#$main/}")"
        cp -a "$src" "$new/${src#$main/}"
        printf 'seeded %s\n' "${src#$main/}"
      done
    done < "$list"
  fi

  if [[ -x "$hook" ]]; then
    ( cd "$new" && GW_REPO="$repo" GW_BRANCH="$branch" GW_MAIN="$main" GW_WORKTREE="$new" "$hook" )
  fi
}

# --- subcommands ------------------------------------------------------------

__gw_switch() {
  local selected dir session
  selected=$(__gw_pick "switch to worktree") || return
  [[ -z "$selected" ]] && return
  dir=$(printf '%s' "$selected" | cut -f2)
  session=$(printf '%s' "$selected" | cut -f3)
  __gw_attach "$session" "$dir"
}

__gw_new() {
  local branch="" slug="" from="" repo main path session

  while (( $# )); do
    case "$1" in
      -n | --name)
        slug="$2"
        shift 2
        ;;
      -f | --from)
        from="$2"
        shift 2
        ;;
      -*)
        printf 'gw new: unknown option %s\n' "$1" >&2
        return 2
        ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$1"
        else
          printf 'gw new: unexpected argument %s\n' "$1" >&2
          return 2
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    printf 'usage: gw new <branch> [-n <slug>] [-f <ref>]\n' >&2
    return 2
  fi

  main=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    printf 'gw new: not inside a git repository\n' >&2
    return 1
  }
  main=$(dirname "$main")
  repo=$(__gw_repo_name .) || return 1
  [[ -z "$slug" ]] && slug=$(__gw_dir_slug "$branch")
  path="$GW_ROOT/$repo/$slug/$repo"

  if [[ -e "$path" ]]; then
    printf 'gw new: %s already exists\n' "$path" >&2
    return 1
  fi

  # Reuse a local branch, track a remote one, or cut a new branch - in that order.
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$path" "$branch" || return 1
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add --track -b "$branch" "$path" "origin/$branch" || return 1
  else
    git worktree add -b "$branch" "$path" ${from:+"$from"} || return 1
  fi

  __gw_seed "$main" "$path" "$repo" "$branch"

  session=$(__gw_session "$repo" "$slug")
  __gw_attach "$session" "$path"
}

__gw_rm() {
  local selected dir session label reply

  selected=$(__gw_pick "remove worktree") || return
  [[ -z "$selected" ]] && return
  label=$(printf '%s' "$selected" | cut -f1 | xargs)
  dir=$(printf '%s' "$selected" | cut -f2)
  session=$(printf '%s' "$selected" | cut -f3)

  if [[ "$dir" == "$PWD" || "$PWD" == "$dir"/* ]]; then
    printf 'gw rm: you are inside %s\n' "$dir" >&2
    return 1
  fi

  read -r -p "remove worktree $label ($dir)? [y/N] " reply
  [[ "$reply" == [yY]* ]] || return

  # `git worktree remove` refuses to drop a worktree holding uncommitted or
  # untracked work. Seeding puts ignored files in every worktree we create, so
  # that refusal is the normal case here, not the exception - report why and
  # ask once more rather than dead-ending.
  if ! git -C "$dir" worktree remove "$dir" 2>&1; then
    read -r -p "force remove $label, discarding uncommitted and untracked files? [y/N] " reply
    [[ "$reply" == [yY]* ]] || return 1
    git -C "$dir" worktree remove --force "$dir" || return 1
  fi

  # Drop the now-empty <slug> level of Zed's layout, if that is what this was.
  rmdir "$(dirname "$dir")" 2>/dev/null

  if zellij list-sessions -s -n 2>/dev/null | grep -qx "$session"; then
    zellij delete-session "$session" --force 2>/dev/null
  fi

  git worktree prune 2>/dev/null
}

# --- entrypoint -------------------------------------------------------------

# gw            - fzf-pick a worktree and switch to its zellij session
# gw new <br>   - create a worktree for <br>, seed it, open its session
# gw rm         - fzf-pick a worktree, remove it and its session
# gw list       - print known worktrees
gw() {
  local cmd="${1:-switch}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    switch | sw | s) __gw_switch "$@" ;;
    new | add | n) __gw_new "$@" ;;
    rm | remove | del) __gw_rm "$@" ;;
    list | ls | l) __gw_enumerate | cut -f1 ;;
    -h | --help | help)
      printf 'usage: gw [switch] | new <branch> [-n slug] [-f ref] | rm | list\n'
      ;;
    *)
      printf 'gw: unknown subcommand %s (try: gw --help)\n' "$cmd" >&2
      return 2
      ;;
  esac
}

if [[ $- == *i* ]]; then
  complete -W "switch new rm list help" gw
fi
