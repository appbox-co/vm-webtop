# Custom Scripts Directory

This directory is for user-provided additional scripts that will be executed during the installation process.

## Usage

1. Place your custom scripts in this directory
2. Scripts will be executed in **alphabetical order** after the main installation completes
3. Make sure your scripts are executable (`chmod +x script-name.sh`)
4. Use descriptive names with prefixes for ordering (e.g., `01-setup-custom-app.sh`, `02-configure-settings.sh`)

## Script Requirements

- Scripts must be executable
- Scripts should handle their own error checking
- Scripts run as root during installation
- Scripts should be idempotent (safe to run multiple times)

## Environment

When your scripts run, they have access to:
- All functions from the main `install.sh` script
- Standard system environment
- The `appbox` user has been created and configured
- All main components (selkies, webtop) have been installed

## Examples

```bash
# 01-install-vscode.sh - Install Visual Studio Code
#!/bin/bash
set -e

info "Installing Visual Studio Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list

apt-get update
apt-get install -y code

success "Visual Studio Code installed successfully"
```

```bash
# 02-setup-development-tools.sh - Install development tools
#!/bin/bash
set -e

info "Installing development tools..."
apt-get update
apt-get install -y git curl wget nodejs npm python3-pip

# Configure for appbox user
sudo -u appbox git config --global user.name "Appbox User"
sudo -u appbox git config --global user.email "user@appbox.local"

success "Development tools configured"
```

## Notes

- This directory is ignored by git (see `.gitignore`)
- Scripts are optional - installation works without any custom scripts
- Failed scripts will stop the installation process
- Use the logging functions (`info`, `warn`, `error`, `success`) for consistent output
