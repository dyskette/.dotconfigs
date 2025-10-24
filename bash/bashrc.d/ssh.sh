if [ "$(systemd-detect-virt)" == "wsl" ]; then
    SSH_ENV="$HOME/.ssh/agent-environment"

    function start_agent {
        echo "Initializing new SSH agent..."
        /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
        echo "succeeded"
        chmod 600 "${SSH_ENV}"
        . "${SSH_ENV}" > /dev/null

        # Auto-add SSH keys
        if [ "$(ssh-add -l 2>/dev/null)" == "The agent has no identities." ]; then
            for pubkey in ~/.ssh/*.pub; do
                privkey="${pubkey%.pub}"
                if [[ -f "$privkey" && ! "$privkey" =~ \.pub$ ]]; then
                    ssh-add "$privkey" 2>/dev/null
                fi
            done
        fi
    }

    # Source SSH settings, if applicable
    if [ -f "${SSH_ENV}" ]; then
        . "${SSH_ENV}" > /dev/null
        # Check if agent is still running
        /usr/bin/ssh-add -l &>/dev/null
        if [ "$?" == 2 ]; then
            # Agent is dead, start a new one
            start_agent
        fi
    else
        start_agent
    fi
fi
