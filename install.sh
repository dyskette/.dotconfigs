#!/usr/bin/env bash

# Install ansible
if ! command -v ansible &>/dev/null; then
    echo "Ansible not found. Installing..."
    rpm-ostree install --apply-live --idempotent ansible
else
    echo "Ansible is already installed."
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

# Run Ansible playbook
cd "$DEST_DIR" || exit 1
ansible-playbook playbook.yml --ask-become-pass
