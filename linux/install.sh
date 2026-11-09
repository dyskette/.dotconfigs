#!/usr/bin/env bash

# Prerequisites for a Python venv; Ansible itself is never a distro package.
if grep -qi "silverblue" /etc/os-release; then
    echo "You are using Fedora Silverblue"
    # python3 ships in the base image; nothing to layer.
elif grep -qi "fedora" /etc/os-release; then
    echo "You are using Fedora"
    # python3-libdnf5 lets ansible.builtin.dnf drive dnf5 from the system python
    # that runs the modules; the distro ansible package used to pull it in.
    sudo dnf install --assumeyes python3 python3-libdnf5 || exit 1
elif grep -qi "ubuntu" /etc/os-release; then
    echo "You are using Ubuntu"
    # Ubuntu splits venv/ensurepip out of python3.
    if ! python3 -c 'import ensurepip' &>/dev/null; then
        sudo apt install --assume-yes python3-venv || exit 1
    fi
fi

# A venv in $HOME on every distro: one code path, and nothing layered on
# Silverblue. Only ansible-core is installed: the `ansible` bundle pins an
# ansible-core that can lag behind the distro's Python (14.x pins 2.21, which
# breaks on Python 3.15). pip picks the newest ansible-core the local Python
# supports. The collections the bundle would add come from
# linux/requirements.yml below; jmespath backs the json_query filter.
# Upgraded on every run, as a distro package would be with system updates.
ANSIBLE_VENV="$HOME/.local/opt/ansible"
if [ ! -x "$ANSIBLE_VENV/bin/ansible-playbook" ]; then
    echo "Ansible not found. Creating venv in $ANSIBLE_VENV..."
    python3 -m venv "$ANSIBLE_VENV" || exit 1
fi
echo "Installing or upgrading Ansible in $ANSIBLE_VENV..."
"$ANSIBLE_VENV/bin/pip" install --quiet --upgrade ansible-core jmespath || exit 1
export PATH="$ANSIBLE_VENV/bin:$PATH"
# Lets ansible-playbook be run directly; the venv's shebang finds its own python.
mkdir -p "$HOME/.local/bin"
ln -sf "$ANSIBLE_VENV/bin/ansible-playbook" "$HOME/.local/bin/ansible-playbook"

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

echo "Installing or upgrading Ansible collections..."
ansible-galaxy collection install --upgrade -r linux/requirements.yml || exit 1

# Run Ansible playbook
ansible-playbook -i linux/inventory.yml linux/playbook.yml --ask-become-pass $@
