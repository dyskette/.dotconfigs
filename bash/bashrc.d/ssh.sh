if [ "$(systemd-detect-virt)" == "wsl" ] && ! [ $(ps ax | grep [s]sh-agent | wc -l) -gt 0 ]; then
    eval $(ssh-agent -s)
    if [ "$(ssh-add -l)" == "The agent has no identities." ] ; then
        ssh-add ~/.ssh/id_rsa
    fi

    # Don't leave extra agents around: kill it on exit. You may not want this part.
    trap "ssh-agent -k" exit
fi
