#!/usr/bin/env bash

# Install ansible
if grep -qi "silverblue" /etc/os-release; then
    echo "You are using Fedora Silverblue"
    # A venv in $HOME keeps Ansible off the host image. Only ansible-core is
    # installed: the `ansible` bundle pins an older ansible-core that can lag
    # behind Fedora's Python (14.x pins 2.21, which breaks on Python 3.15).
    # The collections it would bundle come from linux/requirements.yml below.
    # jmespath backs the json_query filter. Upgraded on every run, as a
    # layered package would be with the image.
    ANSIBLE_VENV="$HOME/.local/opt/ansible"
    if [ ! -x "$ANSIBLE_VENV/bin/ansible-playbook" ]; then
        echo "Ansible not found. Creating venv in $ANSIBLE_VENV..."
        python3 -m venv "$ANSIBLE_VENV" || exit 1
    fi
    echo "Installing or upgrading Ansible in $ANSIBLE_VENV..."
    "$ANSIBLE_VENV/bin/pip" install --quiet --upgrade ansible-core jmespath || exit 1
    export PATH="$ANSIBLE_VENV/bin:$PATH"
    INSTALL_COLLECTIONS=1
elif grep -qi "fedora" /etc/os-release; then
    echo "You are using Fedora"
    if ! command -v ansible &>/dev/null; then
        echo "Ansible not found. Installing..."
        sudo dnf install --assumeyes ansible python3-jmespath
    else
        echo "Ansible is already installed."
    fi
elif grep -qi "ubuntu" /etc/os-release; then
    echo "You are using Ubuntu"
    if ! command -v ansible &>/dev/null; then
        echo "Ansible not found. Installing..."
        sudo apt install --assume-yes ansible
    else
        echo "Ansible is already installed."
    fi
fi

# Clone the repository
REPO_URL="https://github.com/dyskette/.dotconfigs.git"
DEST_DIR="$HOME/.dotconfigs"

if [ -d "$DEST_DIR" ]; then
    echo "Repository already exists. Pulling latest changes..."
    git -C "$DEST_DIR" pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$DEST_DIR"
fi

cd "$DEST_DIR" || exit 1

# The distro ansible packages bundle their collections; the venv does not.
if [ -n "$INSTALL_COLLECTIONS" ]; then
    echo "Installing or upgrading Ansible collections..."
    ansible-galaxy collection install --upgrade -r linux/requirements.yml || exit 1
fi

# Run Ansible playbook
ansible-playbook -i linux/inventory.yml linux/playbook.yml --ask-become-pass $@
