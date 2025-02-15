#!/usr/bin/env bash
#
# Configuration script

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function run_startup_ansible() {
    if ! command -v ansible &>/dev/null;  then
        sudo apt update
        sudo apt upgrade --assume-yes
        sudo apt install --assume-yes ansible
    fi

    ansible-playbook --ask-become-pass $SCRIPT_DIR/configuration.playbook.yaml
}

function install_fnm() {
    # Install to /opt/fnm
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "/opt/fnm" --skip-shell
    # Change /opt/fnm group owner to 'users'
    chown -R :users /opt/fnm
    # Change /opt/fnm group permissions to 'rwx'
    find /opt/fnm/ -type d -exec chmod g+rwx {} +
    # Add initialization profile
    cat <<EOF > /etc/profile.d/fnm.sh
# FNM initialization script

FNM_PATH='/opt/fnm'
if [ -d "\$FNM_PATH" ]; then
    export PATH="\$FNM_PATH:\$PATH"
    if [ ! -t 0 ]; then
        # if running noninteractive only register the command
        eval "\`fnm env --fnm-dir=\"\$FNM_PATH\"\`"
    else
        eval "\`fnm env --fnm-dir=\"\$FNM_PATH\" --use-on-cd --version-file-strategy=recursive --resolve-engines\`"
        # register completions
        eval "\`fnm completions\`"
    fi
fi
EOF
    # Source the new profile
    source /etc/profile.d/fnm.sh
    # Install node
    fnm install --lts
    fnm use default
}

function show_help() {
    echo "Usage: $0 [-a|--run-ansible] [-f|--install-fnm] [-h|--help]"
    exit 0
}

opt_short="afh"
opt_long="run-ansible,install-fnm,help"
OPTS=$(getopt -o "$opt_short" -l "$opt_long" -- "$@")

if [ $? -ne 0 ]; then
    show_help
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -a|--run-ansible)
            run_startup_ansible
            break
            ;;
        -f|--install-fnm)
            install_fnm
            break
            ;;
        --)
            shift
            break
            ;;
    esac
done
