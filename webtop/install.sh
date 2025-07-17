#!/bin/bash

# =============================================================================
# Webtop Installation Script
# Installs XFCE desktop environment for LinuxServer.io webtop functionality
# Based on docker-webtop Dockerfile
# =============================================================================

set -euo pipefail

# Set non-interactive mode globally to prevent apt hangs
export DEBIAN_FRONTEND=noninteractive

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
    
    # Check if abc user exists
    if ! id -u abc &>/dev/null; then
        error "User 'abc' not found. Please install selkies first."
        exit 1
    fi
    
    success "✓ Dependencies checked"
}

# =============================================================================
# REPOSITORY SETUP
# =============================================================================

setup_repositories() {
    info "Setting up repositories..."
    
    # Add xtradeb PPA repository
    info "Adding xtradeb PPA repository..."
    apt-key adv \
        --keyserver hkp://keyserver.ubuntu.com:80 \
        --recv-keys 5301FA4FD93244FBC6F6149982BB6851C64F6880
    
    echo "deb https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu noble main" > \
        /etc/apt/sources.list.d/xtradeb.list
    
    # Update package lists
    timeout 300 apt-get update
    
    success "✓ Repository setup completed"
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

install_xfce_packages() {
    info "Installing XFCE packages..."
    
    # Install XFCE desktop environment and related packages
    timeout 900 apt-get install --no-install-recommends -y \
        chromium \
        mousepad \
        xfce4-terminal \
        xfce4 \
        xubuntu-default-settings \
        xubuntu-icon-theme
    
    success "✓ XFCE packages installed"
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
# XFCE TWEAKS
# =============================================================================

apply_xfce_tweaks() {
    info "Applying XFCE tweaks..."
    
    # Modify chromium desktop entry to use wrapped chromium
    sed -i \
        's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
        /usr/share/applications/chromium.desktop
    
    # Move original binaries to backup names
    if [[ -f /usr/bin/exo-open ]]; then
        mv /usr/bin/exo-open /usr/bin/exo-open-real
    fi
    
    if [[ -f /usr/bin/thunar ]]; then
        mv /usr/bin/thunar /usr/bin/thunar-real
    fi
    
    if [[ -f /usr/bin/chromium ]]; then
        mv /usr/bin/chromium /usr/bin/chromium-browser
    fi
    
    # Remove xscreensaver autostart
    rm -f /etc/xdg/autostart/xscreensaver.desktop
    
    success "✓ XFCE tweaks applied"
}

# =============================================================================
# ROOTFS INSTALLATION
# =============================================================================

install_rootfs_files() {
    info "Installing webtop rootfs files..."
    
    # Verify rootfs structure exists
    if [[ ! -d "$SCRIPT_DIR/rootfs" ]]; then
        error "Rootfs directory not found: $SCRIPT_DIR/rootfs"
        exit 1
    fi
    
    # Copy configuration files
    info "Copying XFCE configuration files..."
    cp -r "$SCRIPT_DIR/rootfs/defaults" /
    chown -R abc:abc /defaults
    
    # Ensure webtop flag file directory exists
    mkdir -p /etc/selkies
    
    # Copy modified binaries
    info "Installing modified browser wrappers..."
    cp "$SCRIPT_DIR/rootfs/usr/bin/chromium" /usr/bin/
    cp "$SCRIPT_DIR/rootfs/usr/bin/exo-open" /usr/bin/
    cp "$SCRIPT_DIR/rootfs/usr/bin/thunar" /usr/bin/
    cp "$SCRIPT_DIR/rootfs/usr/local/bin/wrapped-chromium" /usr/local/bin/
    
    # Make scripts executable
    chmod +x /usr/bin/chromium /usr/bin/exo-open /usr/bin/thunar /usr/local/bin/wrapped-chromium
    chmod +x /defaults/startwm.sh
    
    success "✓ Rootfs files installed"
}

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

configure_environment() {
    info "Configuring webtop environment..."
    
    # Ensure /etc/environment ends with a newline if it exists
    if [[ -f /etc/environment ]] && [[ -n "$(tail -c1 /etc/environment)" ]]; then
        echo >> /etc/environment
    fi
    
    # Add webtop environment variables
    cat "$SCRIPT_DIR/rootfs/etc/environment" >> /etc/environment
    
    # Sort and remove any duplicates
    sort /etc/environment | uniq > /tmp/environment.tmp
    mv /tmp/environment.tmp /etc/environment
    
    success "✓ Environment configuration completed"
}

# =============================================================================
# DESKTOP SERVICE INTEGRATION
# =============================================================================

integrate_with_selkies() {
    info "Integrating webtop with selkies desktop service..."
    
    # Check if selkies desktop service exists
    if [[ ! -f /etc/systemd/system/selkies-desktop.service ]]; then
        error "selkies-desktop.service not found. Please install selkies first."
        exit 1
    fi
    
    # Create a flag file to indicate webtop is installed
    touch /etc/selkies/webtop-installed
    
    # The selkies desktop service will automatically detect and use webtop
    # configuration if this flag file exists
    
    success "✓ Webtop integrated with selkies"
}

# =============================================================================
# SYSTEM CLEANUP
# =============================================================================

cleanup_installation() {
    info "Cleaning up installation..."
    
    # Clean package cache
    timeout 60 apt-get autoclean
    
    # Remove temporary files
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
    
    # Check if XFCE packages are installed
    if ! dpkg -l | grep -q xfce4; then
        error "XFCE packages not found"
        exit 1
    fi
    
    # Check if modified binaries exist
    if [[ ! -f /usr/bin/chromium ]] || [[ ! -f /usr/bin/exo-open ]] || [[ ! -f /usr/bin/thunar ]]; then
        error "Modified binaries not found"
        exit 1
    fi
    
    # Check if configuration files exist
    if [[ ! -f /defaults/startwm.sh ]] || [[ ! -d /defaults/xfce ]]; then
        error "XFCE configuration files not found"
        exit 1
    fi
    
    # Check if icon exists
    if [[ ! -f /usr/share/selkies/www/icon.png ]]; then
        error "Webtop icon not found"
        exit 1
    fi
    
    success "✓ Installation validation completed"
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

main() {
    info "Starting webtop installation process..."
    
    # Installation phases
    check_dependencies
    setup_repositories
    install_xfce_packages
    download_webtop_icon
    apply_xfce_tweaks
    install_rootfs_files
    configure_environment
    integrate_with_selkies
    cleanup_installation
    validate_installation
    
    success "✅ Webtop installation completed successfully!"
    info ""
    info "Webtop (XFCE Desktop Environment) has been installed and integrated with selkies."
    info "The desktop service will automatically use XFCE when started."
    info ""
    info "To start the webtop environment:"
    info "  systemctl start selkies-desktop"
    info ""
    info "To check status:"
    info "  systemctl status selkies-desktop"
    info ""
    info "Web interface available at: http://localhost:3000"
    info "Title: Ubuntu XFCE"
}

# Run main installation
main "$@" 