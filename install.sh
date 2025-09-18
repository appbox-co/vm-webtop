#!/bin/bash
set -euo pipefail

# Ubuntu VM Webtop Environment - Master Installation Script
# Phase 2: Foundation
# Version: 1.0.0

# Set non-interactive mode globally to prevent apt hangs
export DEBIAN_FRONTEND=noninteractive

# Configure needrestart to prevent interactive prompts
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-vm-webtop-install.log"
VERBOSE=false
DRY_RUN=false
COMPONENT_ONLY=""

# Ensure log directory exists and is writable
if [[ $EUID -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
    fi
else
    LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
fi

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
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

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local description=$3
    local percentage=$((current * 100 / total))
    
    printf "\r${BLUE}Progress: [%d/%d] (%d%%) %s${NC}" "$current" "$total" "$percentage" "$description"
    [[ $current -eq $total ]] && echo
}

# =============================================================================
# SYSTEM VALIDATION FUNCTIONS
# =============================================================================

validate_system() {
    info "Validating system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check Ubuntu version
    if ! command -v lsb_release &> /dev/null; then
        error "lsb_release command not found. Are you running Ubuntu?"
        exit 1
    fi
    
    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)
    
    if [[ "$ubuntu_codename" != "noble" ]]; then
        error "This script requires Ubuntu Noble (24.04 LTS). Found: $ubuntu_version ($ubuntu_codename)"
        exit 1
    fi
    
    info "✓ Ubuntu Noble (24.04 LTS) detected"
    
    # Check system resources
    local mem_total=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
    local disk_free=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [[ $mem_total -lt 2 ]]; then
        warn "System has ${mem_total}GB RAM. Minimum 2GB recommended."
    else
        info "✓ Memory: ${mem_total}GB available"
    fi
    
    if [[ $disk_free -lt 10 ]]; then
        warn "System has ${disk_free}GB free disk space. Minimum 10GB recommended."
    else
        info "✓ Disk space: ${disk_free}GB available"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error "No internet connectivity. Please check your network connection."
        exit 1
    fi
    
    info "✓ Internet connectivity verified"
    
    # Check if systemd is running
    if ! systemctl is-system-running --quiet; then
        warn "Systemd is not in running state. Some services may not start correctly."
    else
        info "✓ Systemd is running"
    fi
    
    info "System validation completed successfully"
}

# =============================================================================
# SYSTEMD MANAGEMENT FUNCTIONS
# =============================================================================

reload_systemd() {
    debug "Reloading systemd daemon..."
    if [[ "$DRY_RUN" == false ]]; then
        systemctl daemon-reload
    fi
}

create_systemd_service() {
    local service_name="$1"
    local service_content="$2"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    debug "Creating systemd service: $service_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "$service_content" > "$service_file"
        chmod 644 "$service_file"
        reload_systemd
    fi
}

enable_service() {
    local service_name="$1"
    debug "Enabling systemd service: $service_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        systemctl enable "$service_name"
    fi
}

start_service() {
    local service_name="$1"
    debug "Starting systemd service: $service_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        systemctl start "$service_name"
    fi
}

stop_service() {
    local service_name="$1"
    debug "Stopping systemd service: $service_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        systemctl stop "$service_name" || true
    fi
}

restart_service() {
    local service_name="$1"
    debug "Restarting systemd service: $service_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        systemctl restart "$service_name"
    fi
}

service_status() {
    local service_name="$1"
    systemctl is-active "$service_name" 2>/dev/null || echo "inactive"
}

# =============================================================================
# USER MANAGEMENT FUNCTIONS
# =============================================================================

create_system_user() {
    local username="$1"
    local home_dir="$2"
    local shell="${3:-/bin/bash}"
    local create_home="${4:-true}"
    
    debug "Creating system user: $username"
    
    if id "$username" &>/dev/null; then
        debug "User $username already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        local useradd_opts=("-r" "-s" "$shell")
        
        if [[ "$create_home" == true ]]; then
            useradd_opts+=("-m" "-d" "$home_dir")
        else
            useradd_opts+=("-M")
        fi
        
        useradd "${useradd_opts[@]}" "$username"
        
        if [[ "$create_home" == true && ! -d "$home_dir" ]]; then
            mkdir -p "$home_dir"
            chown "$username:$username" "$home_dir"
        fi
    fi
}

add_user_to_groups() {
    local username="$1"
    shift
    local groups=("$@")
    
    debug "Adding user $username to groups: ${groups[*]}"
    
    if [[ "$DRY_RUN" == false ]]; then
        for group in "${groups[@]}"; do
            # Create group if it doesn't exist
            if ! getent group "$group" &>/dev/null; then
                groupadd "$group"
            fi
            usermod -aG "$group" "$username"
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

create_home_directory() {
    local username="$1"
    local home_dir="$2"
    
    debug "Creating home directory for $username: $home_dir"
    
    if [[ "$DRY_RUN" == false ]]; then
        if [[ ! -d "$home_dir" ]]; then
            mkdir -p "$home_dir"
            chown "$username:$username" "$home_dir"
            chmod 755 "$home_dir"
        fi
    fi
}

# =============================================================================
# CONFIGURATION MANAGEMENT FUNCTIONS
# =============================================================================

backup_config() {
    local config_file="$1"
    local backup_suffix="${2:-.bak}"
    
    if [[ -f "$config_file" ]]; then
        local backup_file="${config_file}${backup_suffix}"
        debug "Backing up $config_file to $backup_file"
        
        if [[ "$DRY_RUN" == false ]]; then
            cp "$config_file" "$backup_file"
        fi
    fi
}

merge_config() {
    local source_file="$1"
    local target_file="$2"
    local merge_mode="${3:-append}"  # append, replace, or merge
    
    debug "Merging config from $source_file to $target_file (mode: $merge_mode)"
    
    if [[ "$DRY_RUN" == false ]]; then
        case "$merge_mode" in
            "append")
                cat "$source_file" >> "$target_file"
                ;;
            "replace")
                cp "$source_file" "$target_file"
                ;;
            "merge")
                # Simple merge - append if content not already present
                if [[ -f "$target_file" ]]; then
                    while IFS= read -r line; do
                        if ! grep -Fxq "$line" "$target_file"; then
                            echo "$line" >> "$target_file"
                        fi
                    done < "$source_file"
                else
                    cp "$source_file" "$target_file"
                fi
                ;;
        esac
    fi
}

template_config() {
    local template_file="$1"
    local output_file="$2"
    local -A variables
    
    # Parse additional arguments as key=value pairs
    shift 2
    for arg in "$@"; do
        if [[ "$arg" == *"="* ]]; then
            local key="${arg%%=*}"
            local value="${arg#*=}"
            variables["$key"]="$value"
        fi
    done
    
    debug "Processing template $template_file to $output_file"
    
    if [[ "$DRY_RUN" == false ]]; then
        local content=$(cat "$template_file")
        
        # Replace variables in the format {{VAR_NAME}}
        for var_name in "${!variables[@]}"; do
            local var_value="${variables[$var_name]}"
            content="${content//\{\{$var_name\}\}/$var_value}"
        done
        
        echo "$content" > "$output_file"
    fi
}

validate_config() {
    local config_file="$1"
    local validation_type="${2:-syntax}"  # syntax, json, yaml, etc.
    
    debug "Validating config file: $config_file ($validation_type)"
    
    case "$validation_type" in
        "json")
            python3 -m json.tool "$config_file" > /dev/null
            ;;
        "yaml")
            python3 -c "import yaml; yaml.safe_load(open('$config_file'))"
            ;;
        "syntax")
            bash -n "$config_file" 2>/dev/null
            ;;
        *)
            debug "No validation available for type: $validation_type"
            return 0
            ;;
    esac
}

# =============================================================================
# FILE OPERATIONS FUNCTIONS
# =============================================================================

copy_rootfs() {
    local source_dir="$1"
    local target_dir="${2:-/}"
    
    debug "Copying rootfs from $source_dir to $target_dir"
    
    if [[ ! -d "$source_dir" ]]; then
        warn "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        # Use rsync for better handling of permissions and symlinks
        if command -v rsync &> /dev/null; then
            rsync -av --no-owner --no-group "$source_dir/" "$target_dir/"
        else
            # Fallback to cp
            cp -r "$source_dir/"* "$target_dir/"
        fi
    fi
}

set_file_permissions() {
    local file_path="$1"
    local owner="$2"
    local permissions="$3"
    
    debug "Setting file permissions: $file_path ($owner:$permissions)"
    
    if [[ "$DRY_RUN" == false ]]; then
        if [[ -e "$file_path" ]]; then
            chown "$owner" "$file_path"
            chmod "$permissions" "$file_path"
        fi
    fi
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

# =============================================================================
# PACKAGE MANAGEMENT FUNCTIONS
# =============================================================================

update_package_cache() {
    debug "Updating package cache..."
    
    if [[ "$DRY_RUN" == false ]]; then
        apt-get update -qq
    fi
}

install_packages() {
    local -a packages=("$@")
    
    debug "Installing packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == false ]]; then
        apt-get install -y "${packages[@]}"
    fi
}

add_repository() {
    local repo_line="$1"
    local keyserver="$2"
    local key_id="$3"
    
    debug "Adding repository: $repo_line"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Add GPG key if provided
        if [[ -n "$keyserver" && -n "$key_id" ]]; then
            apt-key adv --keyserver "$keyserver" --recv-keys "$key_id"
        fi
        
        # Add repository
        echo "$repo_line" >> /etc/apt/sources.list.d/ubuntu-vm-webtop.list
        update_package_cache
    fi
}

# =============================================================================
# DOCKER UTILITIES
# =============================================================================

extract_from_docker_image() {
    local image_name="$1"
    local source_path="$2"
    local dest_path="$3"
    
    debug "Extracting $source_path from $image_name to $dest_path"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check if Docker is running
        if ! docker info &>/dev/null; then
            warn "Docker is not running. Attempting to start..."
            systemctl start docker || service docker start || {
                error "Failed to start Docker service"
                return 1
            }
            sleep 2
        fi
        # Create container with dummy command since we only need to extract files
        local container_id=$(docker create "$image_name" /bin/true)
        if [[ -z "$container_id" ]]; then
            error "Failed to create container from image: $image_name"
            return 1
        fi
        
        # Extract the file/directory
        if ! docker cp "$container_id:$source_path" "$dest_path"; then
            error "Failed to extract $source_path from container"
            docker rm "$container_id" 2>/dev/null || true
            return 1
        fi
        
        # Clean up container
        docker rm "$container_id" || warn "Failed to remove container $container_id"
    fi
}

pull_docker_image() {
    local image_name="$1"
    
    debug "Pulling Docker image: $image_name"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check if Docker is running
        if ! docker info &>/dev/null; then
            warn "Docker is not running. Attempting to start..."
            systemctl start docker || service docker start || {
                error "Failed to start Docker service"
                return 1
            }
            sleep 2
        fi
        docker pull "$image_name"
    fi
}

# =============================================================================
# COMPONENT INSTALLATION FUNCTIONS
# =============================================================================

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
    
    # Execute component installer
    if [[ "$DRY_RUN" == false ]]; then
        local original_dir="$PWD"
        cd "$component_dir"
        
        debug "Running component installer for $component_name"
        if ./install.sh; then
            debug "Component installer completed successfully"
            cd "$original_dir"
            return 0
        else
            local exit_code=$?
            error "Component installer failed with exit code: $exit_code"
            cd "$original_dir"
            return 1
        fi
    else
        debug "Component $component_name would be installed (dry run)"
        return 0
    fi
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

setup_environment() {
    info "Setting up installation environment..."
    
    # Create necessary directories
    create_directories \
        "/opt/ubuntu-vm-webtop" \
        "/etc/ubuntu-vm-webtop" \
        "/var/lib/ubuntu-vm-webtop" \
        "/var/log/ubuntu-vm-webtop"
    
    # Install basic utilities needed for installation
    update_package_cache
    install_packages \
        curl \
        wget \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        rsync
    
    # Install Docker if not already present
    if ! command -v docker &> /dev/null; then
        info "Installing Docker..."
        install_packages docker.io
    else
        info "Docker is already installed"
    fi
    
    # Start Docker service for image extractions
    if systemctl is-system-running --quiet || systemctl is-system-running | grep -q "degraded"; then
        systemctl start docker || warn "Failed to start Docker service"
        systemctl enable docker || warn "Failed to enable Docker service"
    else
        warn "Systemd not running properly, Docker service management skipped"
        # Try to start Docker manually if possible
        service docker start 2>/dev/null || true
    fi
    
    info "✓ Environment setup completed"
}

install_all_components() {
    info "Starting installation of all components..."
    
    local components=("selkies" "webtop")
    local total_components=${#components[@]}
    local current=0
    local failed_components=()
    
    debug "Components to install: ${components[*]}"
    debug "Total components: $total_components"
    
    for component in "${components[@]}"; do
        ((current++))
        show_progress "$current" "$total_components" "Installing $component"
        
        info "Installing component: $component"
        debug "Component directory: $SCRIPT_DIR/$component"
        
        # Temporarily disable exit-on-error to handle component failures gracefully
        set +e
        install_component "$component"
        local component_exit_code=$?
        set -e
        
        debug "Component $component installation exit code: $component_exit_code"
        
        if [[ $component_exit_code -eq 0 ]]; then
            info "✓ Component $component installed successfully"
        else
            error "✗ Component $component failed to install (exit code: $component_exit_code)"
            failed_components+=("$component")
        fi
    done
    
    if [[ ${#failed_components[@]} -eq 0 ]]; then
        info "✓ All components installed successfully"
        return 0
    else
        warn "Some components failed to install: ${failed_components[*]}"
        warn "You can retry individual components with: ./install.sh --component <name>"
        return 1
    fi
}

copy_custom_rootfs() {
    local custom_rootfs_dir="$SCRIPT_DIR/custom-rootfs"
    
    # Check if custom-rootfs directory exists
    if [[ ! -d "$custom_rootfs_dir" ]]; then
        debug "No custom-rootfs directory found, skipping custom rootfs copy"
        return 0
    fi
    
    # Check if directory has any files (excluding README.md)
    local file_count=$(find "$custom_rootfs_dir" -type f ! -name "README.md" | wc -l)
    if [[ $file_count -eq 0 ]]; then
        info "No custom rootfs files found in $custom_rootfs_dir"
        return 0
    fi
    
    info "Found $file_count custom rootfs file(s) to copy"
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] Would copy custom rootfs files from $custom_rootfs_dir to system root"
        find "$custom_rootfs_dir" -type f ! -name "README.md" | while read -r file; do
            local relative_path="${file#$custom_rootfs_dir/}"
            info "[DRY RUN]   $relative_path -> /$relative_path"
        done
        return 0
    fi
    
    # Copy files recursively, preserving structure
    info "Copying custom rootfs files to system..."
    
    # Use rsync for better control over the copy process
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --exclude="README.md" "$custom_rootfs_dir/" / || {
            error "Failed to copy custom rootfs files using rsync"
            return 1
        }
    else
        # Fallback to cp if rsync not available
        find "$custom_rootfs_dir" -type f ! -name "README.md" | while read -r file; do
            local relative_path="${file#$custom_rootfs_dir/}"
            local target_path="/$relative_path"
            local target_dir=$(dirname "$target_path")
            
            # Create target directory if it doesn't exist
            mkdir -p "$target_dir"
            
            # Copy the file
            cp "$file" "$target_path" || {
                error "Failed to copy $file to $target_path"
                return 1
            }
            
            debug "Copied: $relative_path"
        done
    fi
    
    # Set proper permissions for common file types
    info "Setting permissions for custom rootfs files..."
    
    # Make scripts in /usr/local/bin executable
    if [[ -d "/usr/local/bin" ]]; then
        find "/usr/local/bin" -type f -name "*" -exec chmod 755 {} \; 2>/dev/null || true
    fi
    
    # Set proper permissions for systemd service files
    if [[ -d "/etc/systemd/system" ]]; then
        find "/etc/systemd/system" -name "*.service" -exec chmod 644 {} \; 2>/dev/null || true
        find "/etc/systemd/system" -name "*.target" -exec chmod 644 {} \; 2>/dev/null || true
        find "/etc/systemd/system" -name "*.timer" -exec chmod 644 {} \; 2>/dev/null || true
    fi
    
    # Set ownership for appbox user files
    if [[ -d "/home/appbox" ]] && id appbox >/dev/null 2>&1; then
        chown -R appbox:appbox /home/appbox/ 2>/dev/null || true
    fi
    
    # Enable any custom systemd services
    local custom_services=()
    if [[ -d "$custom_rootfs_dir/etc/systemd/system" ]]; then
        while IFS= read -r -d '' service_file; do
            local service_name=$(basename "$service_file")
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
    
    success "✓ Custom rootfs files copied and configured successfully"
    return 0
}

execute_custom_scripts() {
    local custom_scripts_dir="$SCRIPT_DIR/custom-scripts"
    
    # Check if custom-scripts directory exists
    if [[ ! -d "$custom_scripts_dir" ]]; then
        debug "No custom-scripts directory found, skipping custom scripts"
        return 0
    fi
    
    # Find all executable scripts (excluding README.md)
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("$script")
    done < <(find "$custom_scripts_dir" -maxdepth 1 -type f -executable ! -name "README.md" -print0 | sort -z)
    
    # If no scripts found, return
    if [[ ${#scripts[@]} -eq 0 ]]; then
        info "No custom scripts found in $custom_scripts_dir"
        return 0
    fi
    
    info "Found ${#scripts[@]} custom script(s) to execute"
    
    # Execute scripts in alphabetical order
    local failed_scripts=()
    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        info "Executing custom script: $script_name"
        
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY RUN] Would execute: $script"
            continue
        fi
        
        # Execute script and capture exit code
        set +e
        "$script"
        local script_exit_code=$?
        set -e
        
        if [[ $script_exit_code -eq 0 ]]; then
            success "✓ Custom script $script_name completed successfully"
        else
            error "✗ Custom script $script_name failed (exit code: $script_exit_code)"
            failed_scripts+=("$script_name")
        fi
    done
    
    # Report results
    if [[ ${#failed_scripts[@]} -eq 0 ]]; then
        info "✓ All custom scripts executed successfully"
        return 0
    else
        error "Some custom scripts failed: ${failed_scripts[*]}"
        error "Installation will continue, but custom scripts had issues"
        return 1
    fi
}

cleanup() {
    info "Performing cleanup..."
    
    # Clean up package cache
    if [[ "$DRY_RUN" == false ]]; then
        apt-get autoremove -y
        apt-get autoclean
    fi
    
    # Set final permissions
    set_permissions "/opt/ubuntu-vm-webtop" "root:root" "755"
    set_permissions "/etc/ubuntu-vm-webtop" "root:root" "644"
    
    info "✓ Cleanup completed"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Ubuntu VM Webtop Environment - Installation Script

Usage: $0 [OPTIONS]

Options:
    --component <name>    Install only specified component (selkies, webtop)
    --dry-run            Show what would be done without executing
    --verbose            Enable verbose output
    --help               Show this help message

Examples:
    $0                           # Install all components
    $0 --component selkies       # Install only selkies component
    $0 --dry-run --verbose       # Show installation plan with details

Components:
    selkies    - Selkies GStreamer framework with Xvfb
    webtop     - XFCE desktop environment

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
    
    # Show banner
    echo -e "${BLUE}"
    echo "========================================"
    echo "Ubuntu VM Webtop Environment Installer"
    echo "Version: 1.0.0"
    echo "========================================"
    echo -e "${NC}"
    
    if [[ "$DRY_RUN" == true ]]; then
        warn "DRY RUN MODE - No changes will be made"
    fi
    
    # Validate system
    validate_system
    
    # Setup environment
    setup_environment
    
    # Install components
    if [[ -n "$COMPONENT_ONLY" ]]; then
        info "Installing single component: $COMPONENT_ONLY"
        debug "Component directory: $SCRIPT_DIR/$COMPONENT_ONLY"
        
        # Temporarily disable exit-on-error to handle component failures gracefully
        set +e
        install_component "$COMPONENT_ONLY"
        local component_exit_code=$?
        set -e
        
        debug "Component installation exit code: $component_exit_code"
        
        if [[ $component_exit_code -eq 0 ]]; then
            info "✓ Component $COMPONENT_ONLY installed successfully"
        else
            error "✗ Component $COMPONENT_ONLY failed to install (exit code: $component_exit_code)"
            exit 1
        fi
    else
        # Temporarily disable exit-on-error to handle component failures gracefully
        set +e
        install_all_components
        local all_components_exit_code=$?
        set -e
        
        if [[ $all_components_exit_code -ne 0 ]]; then
            error "Some components failed to install. Check the log for details."
            exit 1
        fi
    fi
    
    # Copy custom rootfs files if any exist
    copy_custom_rootfs
    
    # Execute custom scripts if any exist
    execute_custom_scripts
    
    # Cleanup
    cleanup
    
    # Final status
    info "Installation completed successfully!"
    info "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == false ]]; then
        echo -e "${GREEN}"
        echo "========================================"
        echo "Installation Complete!"
        echo "========================================"
        echo "You can now access the webtop at:"
        echo "  https://localhost:443"
        echo ""
        echo "To check service status:"
        echo "  systemctl status selkies"
        echo "  systemctl status webtop-de"
        echo ""
        echo "For troubleshooting, check:"
        echo "  journalctl -u selkies -f"
        echo "  journalctl -u webtop-de -f"
        echo "========================================"
        echo -e "${NC}"
    fi
}

# Run main function with all arguments
main "$@" 