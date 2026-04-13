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

if ! ss -ap 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
    rm -f "$SSH_AUTH_SOCK"
    mkdir -p "$(dirname "$SSH_AUTH_SOCK")"
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
