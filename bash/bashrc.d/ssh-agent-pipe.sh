# SSH in WSL through the Windows OpenSSH agent.
#
# Windows' ~/.ssh is the single source of truth: private keys live only there,
# loaded into the Windows agent. WSL gets
#   1. a relay from $SSH_AUTH_SOCK to the agent's named pipe (socat +
#      npiperelay.exe), and
#   2. a copy of the non-secret files -- config, *.pub, known_hosts --
#      refreshed on every shell start, so each host alias picks the same key
#      on both sides. With the agent holding the keys, ssh only needs an
#      alias's IdentityFile .pub to ask for the matching private key.
#
# The relay runs Windows programs, so it depends on WSL interop; the
# wsl-interop-guard service (linux/tasks/wsl.yml) restores interop when
# another distro removes it. The file copy does not depend on interop.

if [ -z "$WSL_DISTRO_NAME" ]; then
    return 0
fi

# Windows' .ssh without asking cmd.exe for %USERPROFILE%, which would itself
# need interop: the Windows and Linux user names match here. Set WIN_SSH_DIR
# if they ever differ.
_win_ssh_dir="${WIN_SSH_DIR:-/mnt/c/Users/$USER/.ssh}"

# Copy config, known_hosts and public keys from Windows. Only files whose
# Windows copy is newer are copied, unless called with "force".
_ssh_sync_public() {
    local force="${1:-}" src dst name
    [ -d "$_win_ssh_dir" ] || return 0

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    for src in "$_win_ssh_dir/config" "$_win_ssh_dir/known_hosts" "$_win_ssh_dir"/*.pub; do
        [ -f "$src" ] || continue
        name="${src##*/}"
        dst="$HOME/.ssh/$name"
        if [ "$force" = force ] || [ ! -e "$dst" ] || [ "$src" -nt "$dst" ]; then
            # Strip CRLF: OpenSSH on Linux would keep the \r in every value.
            tr -d '\r' <"$src" >"$dst.tmp" && mv -f "$dst.tmp" "$dst"
            # Keep Windows' mtime, so the next -nt compares against Windows edits.
            touch -r "$src" "$dst"
            case "$name" in
                *.pub) chmod 644 "$dst" ;;
                *) chmod 600 "$dst" ;;
            esac
        fi
    done

    # A key removed on Windows goes away here too.
    for dst in "$HOME/.ssh"/*.pub; do
        [ -f "$dst" ] && [ ! -e "$_win_ssh_dir/${dst##*/}" ] && rm -f "$dst"
    done
}

_ssh_sync_public

if ! command -v socat &>/dev/null || ! command -v npiperelay.exe &>/dev/null; then
    [[ $- == *i* ]] && echo "ssh-agent-pipe: socat or npiperelay.exe missing; the Windows SSH agent is not reachable" >&2
    return 0
fi

export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

_ssh_agent_start() {
    rm -f "$SSH_AUTH_SOCK"
    mkdir -p "$(dirname "$SSH_AUTH_SOCK")"
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
}

_ssh_agent_stop() {
    local pid
    pid=$(ss -ap 2>/dev/null | grep "$SSH_AUTH_SOCK" | grep -oP 'pid=\K[0-9]+')
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$SSH_AUTH_SOCK"
}

# Re-copy the public files from Windows and restart the relay.
ssh-sync() {
    if [ ! -d "$_win_ssh_dir" ]; then
        echo "Windows .ssh directory not found: $_win_ssh_dir" >&2
        return 1
    fi
    _ssh_sync_public force
    _ssh_agent_stop
    _ssh_agent_start
    echo "SSH config and public keys synced from Windows, agent relay restarted"
}

if ! ss -ap 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
    _ssh_agent_start
fi

# Say so up front rather than failing later as "communication with agent
# failed" in the middle of a push.
if [[ $- == *i* ]] && [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    printf '\033[33m%s\033[0m\n' \
        "ssh-agent-pipe: WSL interop is off, so the Windows SSH agent is unreachable." \
        "  Fix: sudo systemctl restart wsl-interop-guard   (or from Windows: wsl --shutdown)" >&2
fi
