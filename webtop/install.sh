#!/bin/bash

# =============================================================================
# Webtop Installation Script
# Installs GNOME Flashback (X11) for Selkies — full classic GNOME stack on Xvfb.
# =============================================================================

set -euo pipefail

# Set non-interactive mode globally to prevent apt hangs
export DEBIAN_FRONTEND=noninteractive

# Configure needrestart to prevent interactive prompts
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# DEPENDENCY VALIDATION
# =============================================================================

check_dependencies() {
    info "Checking dependencies..."
    
    # Check if selkies is installed by checking for selkies systemd service
    if [[ ! -f /etc/systemd/system/selkies.service ]]; then
        error "Selkies base framework not found. Please install selkies first."
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check if appbox user exists
    if ! id -u appbox &>/dev/null; then
        error "User 'appbox' not found. Please install selkies first."
        exit 1
    fi
    
    success "✓ Dependencies checked"
}

# =============================================================================
# REPOSITORY SETUP
# =============================================================================

setup_repositories() {
    info "Setting up repositories..."
    
    local ubuntu_codename
    if command -v lsb_release &>/dev/null; then
        ubuntu_codename=$(lsb_release -cs)
    else
        # shellcheck source=/dev/null
        . /etc/os-release
        ubuntu_codename="${VERSION_CODENAME:?VERSION_CODENAME unset}"
    fi
    
    # Add xtradeb PPA repository (noble, resolute, etc.)
    info "Adding xtradeb PPA repository for ${ubuntu_codename}..."
    install -d /usr/share/keyrings
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5301FA4FD93244FBC6F6149982BB6851C64F6880" \
        | gpg --dearmor -o /usr/share/keyrings/xtradeb-apps.gpg
    echo "deb [signed-by=/usr/share/keyrings/xtradeb-apps.gpg] https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu ${ubuntu_codename} main" > \
        /etc/apt/sources.list.d/xtradeb.list
    
    # Update package lists
    apt-get update
    
    success "✓ Repository setup completed"
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

install_gnome_packages() {
    info "Installing GNOME Flashback and applications..."
    
    apt-get install --no-install-recommends -y \
        chromium \
        mousepad \
        gnome-session-flashback \
        gnome-terminal \
        nautilus \
        yaru-theme-gtk \
        yaru-theme-icon
    
    success "✓ GNOME desktop packages installed"
}

# =============================================================================
# WEBTOP ICON DOWNLOAD
# =============================================================================

download_webtop_icon() {
    info "Downloading webtop icon..."
    
    # Download the webtop icon
    curl -o /usr/share/selkies/www/icon.png \
        https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png
    
    success "✓ Webtop icon downloaded"
}

# =============================================================================
# GNOME / CHROMIUM TWEAKS
# =============================================================================

apply_gnome_tweaks() {
    info "Applying GNOME and browser tweaks..."
    
    for desktop in /usr/share/applications/chromium.desktop /usr/share/applications/chromium-browser.desktop; do
        if [[ -f "$desktop" ]]; then
            sed -i 's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' "$desktop"
        fi
    done
    
    if [[ -f /usr/bin/chromium ]] && [[ ! -f /usr/bin/chromium-browser ]]; then
        info "Renaming chromium to chromium-browser for wrapper compatibility..."
        mv /usr/bin/chromium /usr/bin/chromium-browser
    elif [[ -f /usr/bin/chromium-browser ]]; then
        info "chromium-browser already present"
    fi
    
    rm -f /etc/xdg/autostart/xscreensaver.desktop 2>/dev/null || true
    
    success "✓ GNOME tweaks applied"
}

# =============================================================================
# ROOTFS INSTALLATION
# =============================================================================

install_rootfs_files() {
    info "Installing webtop rootfs files..."
    
    if [[ ! -d "$SCRIPT_DIR/rootfs" ]]; then
        error "Rootfs directory not found: $SCRIPT_DIR/rootfs"
        exit 1
    fi
    
    info "Copying defaults and GNOME resources..."
    rm -rf /defaults/xfce
    cp -a "$SCRIPT_DIR/rootfs/defaults" /
    chown -R appbox:appbox /defaults
    
    mkdir -p /etc/selkies
    
    if [[ -f /usr/bin/chromium-browser ]]; then
        cp "$SCRIPT_DIR/rootfs/usr/bin/chromium" /usr/bin/
        chmod +x /usr/bin/chromium
    else
        warning "chromium-browser not found, skipping chromium wrapper installation"
    fi
    
    cp "$SCRIPT_DIR/rootfs/usr/local/bin/wrapped-chromium" /usr/local/bin/
    chmod +x /usr/local/bin/wrapped-chromium
    
    chmod +x /defaults/startwm.sh
    
    success "✓ Rootfs files installed"
}

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

configure_environment() {
    info "Configuring webtop environment..."
    
    if [[ -f /etc/environment ]] && [[ -n "$(tail -c1 /etc/environment)" ]]; then
        echo >> /etc/environment
    fi
    
    cat "$SCRIPT_DIR/rootfs/etc/environment" >> /etc/environment
    
    sort /etc/environment | uniq > /tmp/environment.tmp
    mv /tmp/environment.tmp /etc/environment
    
    success "✓ Environment configuration completed"
}

# =============================================================================
# DESKTOP SERVICE INTEGRATION
# =============================================================================

integrate_with_selkies() {
    info "Integrating webtop with selkies desktop service..."
    
    if [[ ! -f /etc/systemd/system/selkies-desktop.service ]]; then
        error "selkies-desktop.service not found. Please install selkies first."
        exit 1
    fi
    
    touch /etc/selkies/webtop-installed
    
    success "✓ Webtop integrated with selkies"
}

# =============================================================================
# SYSTEM CLEANUP
# =============================================================================

cleanup_installation() {
    info "Cleaning up installation..."
    
    apt-get autoclean
    
    rm -rf \
        /config/.cache \
        /config/.launchpadlib \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*
    
    success "✓ Cleanup completed"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_installation() {
    info "Validating webtop installation..."
    
    # chromium is the xtradeb .deb; apply_gnome_tweaks moves /usr/bin/chromium -> chromium-browser for the wrapper.
    local packages=("gnome-session-flashback" "gnome-terminal" "chromium" "mousepad" "metacity")
    for package in "${packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            error "Package $package not properly installed"
            exit 1
        fi
    done
    
    if [[ ! -f /usr/bin/chromium ]]; then
        error "Chromium wrapper not found at /usr/bin/chromium"
        exit 1
    fi
    
    if [[ ! -f /defaults/startwm.sh ]] || [[ ! -d /defaults/gnome ]]; then
        error "GNOME defaults or startwm.sh missing under /defaults"
        exit 1
    fi
    
    if [[ -f /etc/environment ]] && ! grep -q 'TITLE="Ubuntu GNOME"' /etc/environment; then
        warning 'Environment TITLE not set to Ubuntu GNOME'
    fi
    
    success "✓ Webtop installation validated"
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

main() {
    info "Starting webtop installation process..."
    
    check_dependencies
    setup_repositories
    install_gnome_packages
    download_webtop_icon
    apply_gnome_tweaks
    install_rootfs_files
    configure_environment
    integrate_with_selkies
    cleanup_installation
    validate_installation
    
    success "✅ Webtop installation completed successfully!"
    info ""
    info "Webtop (GNOME Flashback on X11) is installed for Selkies."
    info "Start the stack with: systemctl start selkies-desktop"
    info "Web UI: https://localhost:443 — Title: Ubuntu GNOME"
}

main "$@"
