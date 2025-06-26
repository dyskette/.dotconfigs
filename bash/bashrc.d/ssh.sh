if [ "$(systemd-detect-virt)" == "wsl" ] && ! [ $(ps ax | grep [s]sh-agent | wc -l) -gt 0 ]; then
    eval $(ssh-agent -s)
    if [ "$(ssh-add -l)" == "The agent has no identities." ] ; then
        for pubkey in ~/.ssh/*.pub; do
            privkey="${pubkey%.pub}"
            if [[ -f "$privkey" ]]; then
                ssh-add "$privkey" 2>/dev/null
            fi
        done
    fi

    # Don't leave extra agents around: kill it on exit. You may not want this part.
    trap "ssh-agent -k" exit
fi
