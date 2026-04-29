#!/bin/bash
set -euo pipefail

# Ubuntu VM Images - Master installer (KDE Plasma on Selkies)
# Version: 3.1.0

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-vm-kde-install.log"
VERBOSE=false
DRY_RUN=false
COMPONENT_ONLY=""
SKIP_KERNEL_UPDATE=false

if [[ $EUID -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        LOG_FILE="$SCRIPT_DIR/ubuntu-vm-kde-install.log"
    fi
else
    LOG_FILE="$SCRIPT_DIR/ubuntu-vm-kde-install.log"
fi

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }
debug() { log "DEBUG" "$@"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"; }

show_progress() {
    local current=$1
    local total=$2
    local description=$3
    local percentage=$((current * 100 / total))

    printf "\r${BLUE}Progress: [%d/%d] (%d%%) %s${NC}" "$current" "$total" "$percentage" "$description"
    [[ $current -eq $total ]] && echo
}

validate_system() {
    info "Validating system requirements..."

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    local ubuntu_version=""
    local ubuntu_codename=""

    if command -v lsb_release &> /dev/null; then
        ubuntu_version=$(lsb_release -rs)
        ubuntu_codename=$(lsb_release -cs)
    elif [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        ubuntu_version="${VERSION_ID:-}"
        ubuntu_codename="${VERSION_CODENAME:-}"
    else
        error "Cannot detect OS version (missing lsb_release and /etc/os-release)"
        exit 1
    fi

    case "$ubuntu_codename" in
        noble|resolute)
            info "Ubuntu ${ubuntu_version} (${ubuntu_codename}) detected"
            ;;
        *)
            error "This script supports Ubuntu 24.04 LTS (noble) or 26.04 LTS (resolute). Found: ${ubuntu_version:-unknown} (${ubuntu_codename:-unknown})"
            exit 1
            ;;
    esac

    local mem_total
    mem_total=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
    local disk_free
    disk_free=$(df / | awk 'NR==2 {print int($4/1024/1024)}')

    if [[ $mem_total -lt 2 ]]; then
        warn "System has ${mem_total}GB RAM. Minimum 2GB recommended."
    else
        info "Memory: ${mem_total}GB available"
    fi

    if [[ $disk_free -lt 10 ]]; then
        warn "System has ${disk_free}GB free disk space. Minimum 10GB recommended."
    else
        info "Disk space: ${disk_free}GB available"
    fi

    if ! ping -c 1 google.com &> /dev/null; then
        error "No internet connectivity. Please check your network connection."
        exit 1
    fi

    info "Internet connectivity verified"

    if ! systemctl is-system-running --quiet; then
        warn "Systemd is not in running state. Some services may not start correctly."
    else
        info "Systemd is running"
    fi

    info "System validation completed successfully"
}

reload_systemd() {
    debug "Reloading systemd daemon..."
    if [[ "$DRY_RUN" == false ]]; then
        systemctl daemon-reload
    fi
}

install_packages() {
    local -a packages=("$@")
    debug "Installing packages: ${packages[*]}"
    if [[ "$DRY_RUN" == false ]]; then
        apt-get install -y "${packages[@]}"
    fi
}

update_package_cache() {
    debug "Updating package cache..."
    if [[ "$DRY_RUN" == false ]]; then
        apt-get update -qq
    fi
}

install_component() {
    local component_name="$1"
    local component_dir="$SCRIPT_DIR/$component_name"
    local install_script="$component_dir/install.sh"

    info "Installing component: $component_name"

    if [[ ! -d "$component_dir" ]]; then
        error "Component directory not found: $component_dir"
        return 1
    fi

    if [[ ! -f "$install_script" ]]; then
        error "Install script not found: $install_script"
        return 1
    fi

    if [[ ! -x "$install_script" ]]; then
        chmod +x "$install_script"
    fi

    if [[ "$DRY_RUN" == false ]]; then
        cd "$component_dir"
        debug "Running component installer for $component_name"
        if ./install.sh; then
            debug "Component installer completed successfully"
            cd "$SCRIPT_DIR" || cd /
            return 0
        else
            local exit_code=$?
            error "Component installer failed with exit code: $exit_code"
            cd "$SCRIPT_DIR" || cd /
            return 1
        fi
    else
        debug "Component $component_name would be installed (dry run)"
        return 0
    fi
}

update_kernel() {
    info "Checking kernel for virtiofs execv() fix (needs Linux >= 6.11)..."

    local current_kernel
    current_kernel=$(uname -r)
    info "Current kernel: $current_kernel"

    local kernel_major kernel_minor kernel_version
    kernel_major=$(echo "$current_kernel" | cut -d. -f1)
    kernel_minor=$(echo "$current_kernel" | cut -d. -f2)
    kernel_version="${kernel_major}.${kernel_minor}"

    if [[ "$kernel_major" -gt 6 ]] || [[ "$kernel_major" -eq 6 && "$kernel_minor" -ge 11 ]]; then
        info "Current kernel $kernel_version is sufficient; skipping linux-image-generic-6.14 install"
        return 0
    fi

    warn "Current kernel $kernel_version is affected by virtiofs execv() bug"
    warn "Installing linux-image-generic-6.14 to fix application execution on virtiofs mounts"

    if dpkg -l | grep -q "linux-image-6.14"; then
        info "Kernel 6.14 is already installed"
        if [[ "$current_kernel" == *"6.14"* ]]; then
            info "Already running kernel 6.14"
            return 0
        else
            warn "Kernel 6.14 is installed but not active. Reboot required after installation."
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] Would install linux-image-generic-6.14"
        return 0
    fi

    update_package_cache

    info "Installing linux-image-generic-6.14 (fixes virtiofs execv bug)..."
    update_package_cache

    install_packages \
        linux-image-generic-6.14 \
        linux-headers-generic-6.14

    local kv
    kv=$(apt-cache policy linux-image-generic-6.14 | grep Installed | awk '{print $2}' | cut -d: -f2)
    if [[ -n "$kv" ]]; then
        local specific_version
        specific_version=$(echo "$kv" | cut -d. -f1-3 | sed 's/~.*$//')
        info "Installing modules-extra for kernel version: $specific_version"
        if apt-cache search "linux-modules-extra-${specific_version}-generic" | grep -q "linux-modules-extra-${specific_version}-generic"; then
            install_packages "linux-modules-extra-${specific_version}-generic"
        else
            warn "Modules-extra package for $specific_version not found, skipping"
        fi
    else
        warn "Could not determine installed kernel version for modules-extra"
    fi

    info "Updating GRUB configuration..."
    update-grub

    info "Kernel 6.14 installed successfully - virtiofs execv bug fixed"
    warn "IMPORTANT: System reboot required to use the new kernel"

    return 0
}

configure_apt_release_verification() {
    local f="/etc/apt/apt.conf.d/01ubuntu-vm-webtop-apt-sandbox.conf"
    if [[ ! -f "$f" ]]; then
        info "Configuring apt sandbox for Release signature verification..."
        mkdir -p /etc/apt/apt.conf.d
        printf '%s\n' \
            '// Added by ubuntu-vm-kde install (gpgv + _apt sandbox compatibility)' \
            'APT::Sandbox::User "root";' > "$f"
    fi
}

setup_environment() {
    info "Setting up installation environment..."

    configure_apt_release_verification

    if [[ "$SKIP_KERNEL_UPDATE" == false ]]; then
        update_kernel
    else
        info "Kernel update skipped (--skip-kernel-update flag used)"
    fi

    create_directories \
        "/opt/ubuntu-vm-kde" \
        "/etc/ubuntu-vm-kde" \
        "/var/lib/ubuntu-vm-kde" \
        "/var/log/ubuntu-vm-kde"

    update_package_cache
    install_packages \
        curl \
        wget \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        rsync

    info "Environment setup completed"
}

create_directories() {
    local -a dirs=("$@")
    debug "Creating directories: ${dirs[*]}"
    if [[ "$DRY_RUN" == false ]]; then
        for dir in "${dirs[@]}"; do
            mkdir -p "$dir"
        done
    fi
}

set_permissions() {
    local path="$1"
    local owner="$2"
    local permissions="$3"
    debug "Setting permissions on $path: $owner:$permissions"
    if [[ "$DRY_RUN" == false ]]; then
        if [[ -e "$path" ]]; then
            chown -R "$owner" "$path"
            chmod -R "$permissions" "$path"
        fi
    fi
}

install_all_components() {
    info "Starting installation of all components..."

    local components=("desktop" "selkies")
    local total_components=${#components[@]}
    local current=0
    local failed_components=()

    for component in "${components[@]}"; do
        ((current++))
        show_progress "$current" "$total_components" "Installing $component"

        info "Installing component: $component"

        set +e
        install_component "$component"
        local component_exit_code=$?
        set -e

        if [[ $component_exit_code -eq 0 ]]; then
            info "Component $component installed successfully"
        else
            error "Component $component failed to install (exit code: $component_exit_code)"
            failed_components+=("$component")
        fi
    done

    if [[ ${#failed_components[@]} -eq 0 ]]; then
        info "All components installed successfully"
        return 0
    else
        warn "Some components failed to install: ${failed_components[*]}"
        return 1
    fi
}

copy_custom_rootfs() {
    local custom_rootfs_dir="$SCRIPT_DIR/custom-rootfs"

    if [[ ! -d "$custom_rootfs_dir" ]]; then
        debug "No custom-rootfs directory found, skipping custom rootfs copy"
        return 0
    fi

    local file_count
    file_count=$(find "$custom_rootfs_dir" -type f ! -name "README.md" | wc -l)
    if [[ $file_count -eq 0 ]]; then
        info "No custom rootfs files found in $custom_rootfs_dir"
        return 0
    fi

    info "Found $file_count custom rootfs file(s) to copy"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] Would copy custom rootfs files from $custom_rootfs_dir to system root"
        return 0
    fi

    info "Copying custom rootfs files to system..."
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --exclude="README.md" "$custom_rootfs_dir/" / || {
            error "Failed to copy custom rootfs files using rsync"
            return 1
        }
    else
        find "$custom_rootfs_dir" -type f ! -name "README.md" | while read -r file; do
            local relative_path="${file#$custom_rootfs_dir/}"
            local target_path="/$relative_path"
            local target_dir
            target_dir=$(dirname "$target_path")
            mkdir -p "$target_dir"
            cp "$file" "$target_path" || {
                error "Failed to copy $file to $target_path"
                return 1
            }
        done
    fi

    if [[ -d "/usr/local/bin" ]]; then
        find "/usr/local/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
    fi

    if [[ -d "/etc/systemd/system" ]]; then
        find "/etc/systemd/system" -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true
        find "/etc/systemd/system" -name "*.target" -exec chmod 644 {} \; 2>/dev/null || true
        find "/etc/systemd/system" -name "*.timer" -exec chmod 644 {} \; 2>/dev/null || true
    fi

    if [[ -d "/home/appbox" ]] && id appbox >/dev/null 2>&1; then
        chown -R appbox:appbox /home/appbox/ 2>/dev/null || true
    fi

    local custom_services=()
    if [[ -d "$custom_rootfs_dir/etc/systemd/system" ]]; then
        while IFS= read -r -d '' service_file; do
            local service_name
            service_name=$(basename "$service_file")
            if [[ "$service_name" == *.service ]]; then
                custom_services+=("$service_name")
            fi
        done < <(find "$custom_rootfs_dir/etc/systemd/system" -name "*.service" -print0 2>/dev/null)
    fi

    if [[ ${#custom_services[@]} -gt 0 ]]; then
        info "Enabling ${#custom_services[@]} custom systemd service(s)..."
        systemctl daemon-reload
        for service in "${custom_services[@]}"; do
            info "Enabling custom service: $service"
            systemctl enable "$service" || warn "Failed to enable $service"
        done
    fi

    success "Custom rootfs files copied and configured successfully"
    return 0
}

execute_custom_scripts() {
    local custom_scripts_dir="$SCRIPT_DIR/custom-scripts"

    if [[ ! -d "$custom_scripts_dir" ]]; then
        debug "No custom-scripts directory found, skipping custom scripts"
        return 0
    fi

    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("$script")
    done < <(find "$custom_scripts_dir" -maxdepth 1 -type f -executable ! -name "README.md" -print0 | sort -z)

    if [[ ${#scripts[@]} -eq 0 ]]; then
        info "No custom scripts found in $custom_scripts_dir"
        return 0
    fi

    info "Found ${#scripts[@]} custom script(s) to execute"

    local failed_scripts=()
    for script in "${scripts[@]}"; do
        local script_name
        script_name=$(basename "$script")
        info "Executing custom script: $script_name"

        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY RUN] Would execute: $script"
            continue
        fi

        set +e
        "$script"
        local script_exit_code=$?
        set -e

        if [[ $script_exit_code -eq 0 ]]; then
            success "Custom script $script_name completed successfully"
        else
            error "Custom script $script_name failed (exit code: $script_exit_code)"
            failed_scripts+=("$script_name")
        fi
    done

    if [[ ${#failed_scripts[@]} -eq 0 ]]; then
        info "All custom scripts executed successfully"
        return 0
    else
        error "Some custom scripts failed: ${failed_scripts[*]}"
        return 1
    fi
}

cleanup() {
    info "Performing cleanup..."
    if [[ "$DRY_RUN" == false ]]; then
        apt-get autoremove -y
        apt-get autoclean
    fi
    set_permissions "/opt/ubuntu-vm-kde" "root:root" "755"
    set_permissions "/etc/ubuntu-vm-kde" "root:root" "644"
    info "Cleanup completed"
}

show_help() {
    cat << EOF
Ubuntu VM Images - KDE Plasma on Selkies installer
Supported: Ubuntu 24.04 LTS (noble) and 26.04 LTS (resolute).

Usage: $0 [OPTIONS]

Options:
    --component <name>       Install only specified component (desktop or selkies)
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --skip-kernel-update    Skip kernel update to linux-image-generic-6.14
    --help                  Show this help message

Examples:
    $0                           # Install all components with kernel update
    $0 --component desktop       # Install only the KDE desktop payload
    $0 --component selkies       # Install only Selkies remote access
    $0 --dry-run --verbose       # Show installation plan with details
    $0 --skip-kernel-update      # Install without updating kernel

Components:
    desktop    - KDE Plasma desktop packages and first-boot provisioning
    selkies    - Browser-based WebRTC remote desktop (runs Plasma inside Xvfb)

Kernel Update:
    By default, the script updates to linux-image-generic-6.14 to fix a critical
    bug in kernels < 6.11 where execv() fails on virtiofs mounts. This is
    essential for proper application execution in VM environments.
    Use --skip-kernel-update to disable (not recommended for virtiofs setups).

Customization:
    custom-scripts/    - Add executable scripts (run after installation)
    custom-rootfs/     - Add files to copy to system (mirrors filesystem)

For more information, see ARCHITECTURE.md
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --component)
                COMPONENT_ONLY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-kernel-update)
                SKIP_KERNEL_UPDATE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    echo -e "${BLUE}"
    echo "========================================"
    echo "Ubuntu VM Images - KDE Plasma on Selkies"
    echo "Version: 3.1.0"
    echo "========================================"
    echo -e "${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        warn "DRY RUN MODE - No changes will be made"
    fi

    validate_system

    if [[ -n "$COMPONENT_ONLY" && "$COMPONENT_ONLY" != "desktop" && "$COMPONENT_ONLY" != "selkies" ]]; then
        error "Unknown component: $COMPONENT_ONLY (supported: desktop, selkies)"
        exit 1
    fi

    setup_environment

    if [[ -n "$COMPONENT_ONLY" ]]; then
        info "Installing single component: $COMPONENT_ONLY"
        set +e
        install_component "$COMPONENT_ONLY"
        local component_exit_code=$?
        set -e
        if [[ $component_exit_code -eq 0 ]]; then
            info "Component $COMPONENT_ONLY installed successfully"
        else
            error "Component $COMPONENT_ONLY failed to install (exit code: $component_exit_code)"
            exit 1
        fi
    else
        set +e
        install_all_components
        local all_components_exit_code=$?
        set -e
        if [[ $all_components_exit_code -ne 0 ]]; then
            error "Some components failed to install. Check the log for details."
            exit 1
        fi
    fi

    copy_custom_rootfs
    execute_custom_scripts
    cleanup

    info "Installation completed successfully!"
    info "Log file: $LOG_FILE"

    if [[ "$DRY_RUN" == false ]]; then
        echo -e "${GREEN}"
        echo "========================================"
        echo "Installation Complete!"
        echo "========================================"

        local current_kernel
        current_kernel=$(uname -r)
        if [[ "$SKIP_KERNEL_UPDATE" == false ]] && [[ "$current_kernel" != *"6.14"* ]] && dpkg -l | grep -q "linux-image-6.14"; then
            echo -e "${YELLOW}"
            echo "IMPORTANT: Kernel 6.14 was installed but not active"
            echo "Please reboot the system to use the new kernel:"
            echo "  sudo reboot"
            echo ""
            echo "After reboot, open the Selkies web desktop on HTTPS port 443"
            echo "(or the port configured for selkies-nginx.service)."
            echo -e "${GREEN}"
        else
            echo "Open the Selkies web desktop on HTTPS port 443."
        fi

        echo "  Remote desktop: Selkies WebRTC over HTTPS"
        echo "  Desktop session: KDE Plasma inside Xvfb (:1)"
        echo ""
        echo "To check service status:"
        echo "  systemctl status selkies"
        echo "  systemctl status selkies-desktop"
        echo "  systemctl status xvfb"
        echo ""
        echo "For troubleshooting, check:"
        echo "  journalctl -u selkies -f"
        echo "  journalctl -u selkies-desktop -f"
        echo ""
        echo "Additional features:"
        echo "  - KDE Discover (Flatpak + Snap backends)"
        echo "  - Flatpak: flathub configured for user appbox"
        echo "  - Chromium (snap), Kate, Konsole, Dolphin, Spectacle"
        echo "========================================"
        echo -e "${NC}"
    fi
}

main "$@"
