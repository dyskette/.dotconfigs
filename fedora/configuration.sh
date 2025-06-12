#!/usr/bin/env bash
#
# Setup applications and configurations for Fedora

# Exit immediately if a command exits with a non-zero status
set -e

# Update system packages
echo "Updating system packages..."
sudo dnf update -y

# Install Ansible
echo "Installing Ansible..."
sudo dnf install -y ansible

# Run the Ansible playbook
echo "Executing the Ansible playbook..."
ansible-playbook --ask-become-pass configuration.yaml

echo "Ansible playbook executed successfully!"
