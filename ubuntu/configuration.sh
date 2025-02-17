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

function show_help() {
    echo "Usage: $0 [-a|--run-ansible] [-h|--help]"
    exit 0
}

opt_short="ah"
opt_long="run-ansible,help"
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
        --)
            shift
            break
            ;;
    esac
done
