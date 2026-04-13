# SSH agent forwarding from Windows to WSL via npiperelay + socat
# Only runs under WSL — requires socat (Linux) and npiperelay.exe (Windows)

if [ -z "$WSL_DISTRO_NAME" ]; then
    return 0
fi

if ! command -v socat &>/dev/null; then
    return 0
fi

if ! command -v npiperelay.exe &>/dev/null; then
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

ssh-sync() {
    local win_ssh
    win_ssh="$(wslpath "$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/.ssh"

    if [ ! -d "$win_ssh" ]; then
        echo "Windows .ssh directory not found: $win_ssh" >&2
        return 1
    fi

    mkdir -p "$HOME/.ssh"
    # Copy config, keys, and known_hosts — skip sockets and agent files
    for f in "$win_ssh"/*; do
        [ -f "$f" ] || continue
        cp -f "$f" "$HOME/.ssh/"
    done

    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh"/* 2>/dev/null
    [ -f "$HOME/.ssh/config" ] && chmod 644 "$HOME/.ssh/config"
    for pub in "$HOME/.ssh"/*.pub; do
        [ -f "$pub" ] && chmod 644 "$pub"
    done

    _ssh_agent_stop
    _ssh_agent_start
    echo "SSH files synced and agent restarted"
}

if ! ss -ap 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
    _ssh_agent_start
fi
