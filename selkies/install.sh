#!/bin/bash
# Selkies Component Installation Script - Phase 3
# Based on docker-baseimage-selkies Dockerfile
# Converts s6-overlay services to systemd

set -euo pipefail

# Set non-interactive mode globally to prevent apt hangs
export DEBIAN_FRONTEND=noninteractive

# Configure needrestart to prevent interactive prompts
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
LOG_FILE="/var/log/ubuntu-vm-webtop-install.log"
VERBOSE=false
DRY_RUN=false

# Ensure log directory exists and is writable
if [[ $EUID -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
    fi
else
    LOG_FILE="$SCRIPT_DIR/ubuntu-vm-webtop-install.log"
fi

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

# Package management functions
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

# File operations functions
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

# Systemd functions
reload_systemd() {
    debug "Reloading systemd daemon..."
    if [[ "$DRY_RUN" == false ]]; then
        systemctl daemon-reload
    fi
}

enable_service() {
    local service_name="$1"
    debug "Enabling systemd service: $service_name"
    if [[ "$DRY_RUN" == false ]]; then
        systemctl enable "$service_name"
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

# Docker utility functions
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

info "Starting Selkies Framework with Xvfb installation (Phase 3)"
info "This will install Selkies GStreamer remote desktop framework"

# =============================================================================
# DEVELOPMENT DEPENDENCIES
# =============================================================================

install_dev_dependencies() {
    info "Installing development dependencies..."
    
    update_package_cache
    
    # Install packages in smaller groups for better organization
    info "Installing build tools..."
    install_packages \
        cmake \
        git \
        gcc \
        g++ \
        make
    
    info "Installing development libraries..."
    install_packages \
        libopus-dev \
        libpulse-dev
    
    info "Installing Python development tools..."
    install_packages \
        python3-dev \
        python3-pip
}

# =============================================================================
# REPOSITORY SETUP
# =============================================================================

setup_repositories() {
    info "Setting up Docker and Node.js repositories..."
    
    # Docker repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /usr/share/keyrings/docker.asc >/dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
    
    # Node.js repository
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    
    update_package_cache
}

# =============================================================================
# MAIN PACKAGE INSTALLATION
# =============================================================================

install_main_packages() {
    info "Installing main packages in groups for better organization..."
    
    # Group 1: Core system packages
    info "Installing core system packages..."
    install_packages \
        ca-certificates \
        console-data \
        dbus-x11 \
        file \
        kbd \
        locales-all \
        openssh-client \
        openssl \
        pciutils \
        procps \
        software-properties-common \
        ssl-cert \
        sudo \
        tar \
        util-linux \
        zlib1g
    
    # Group 2: Docker packages
    info "Installing Docker packages..."
    install_packages \
        containerd.io \
        docker-buildx-plugin \
        docker-ce \
        docker-ce-cli \
        docker-compose-plugin \
        fuse-overlayfs
    
    # Group 3: Development tools
    info "Installing development tools..."
    install_packages \
        cmake \
        g++ \
        gcc \
        git \
        make \
        nodejs \
        python3 \
        python3-distutils-extra
    
    # Group 4: Basic X11 libraries
    info "Installing basic X11 libraries..."
    install_packages \
        libev4 \
        libfontenc1 \
        libfreetype6 \
        libgbm1 \
        libgcrypt20 \
        libgirepository-1.0-1 \
        libgnutls30 \
        libjpeg-turbo8 \
        libnotify-bin \
        libopus0 \
        libp11-kit0 \
        libpam0g \
        libtasn1-6 \
        libvulkan1 \
        libx11-6 \
        libx264-164 \
        libxau6 \
        libxcb1 \
        libxcursor1 \
        libxdmcp6 \
        libxext6 \
        libxfconf-0-3 \
        libxfixes3 \
        libxfont2 \
        libxinerama1 \
        libxshmfence1 \
        libxtst6
    
    # Group 5: Mesa and graphics drivers
    info "Installing Mesa and graphics drivers..."
    install_packages \
        intel-media-va-driver \
        libgl1-mesa-dri \
        libglu1-mesa \
        mesa-libgallium \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        vulkan-tools
    
    # Group 6: Fonts and themes
    info "Installing fonts and themes..."
    install_packages \
        breeze-cursor-theme \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        fonts-noto-core \
        xfonts-base
    
    # Group 7: Desktop environment and utilities
    info "Installing desktop environment and utilities..."
    install_packages \
        dunst \
        libnginx-mod-http-fancyindex \
        nginx-extras \
        openbox \
        pavucontrol \
        pulseaudio \
        pulseaudio-utils \
        stterm \
        xdg-utils \
        xdotool \
        xfconf
    
    # Group 8: X11 utilities and tools
    info "Installing X11 utilities and tools..."
    install_packages \
        x11-apps \
        x11-common \
        x11-utils \
        x11-xkb-utils \
        x11-xserver-utils \
        xauth \
        xcvt \
        xkb-data \
        xsel \
        xterm \
        xutils \
        xvfb
    
    # Group 9: X server and drivers
    info "Installing X server and graphics drivers..."
    install_packages \
        xserver-common \
        xserver-xorg-core \
        xserver-xorg-video-amdgpu \
        xserver-xorg-video-ati \
        xserver-xorg-video-intel \
        xserver-xorg-video-nouveau \
        xserver-xorg-video-qxl
    
    info "✓ Main packages installed successfully"
}

# =============================================================================
# DOCKER IMAGE EXTRACTIONS
# =============================================================================

extract_docker_images() {
    info "Extracting pre-built components from Docker images..."
    
    # Extract Xvfb binary from xvfb image
    info "Extracting custom Xvfb binary..."
    pull_docker_image "lscr.io/linuxserver/xvfb:ubuntunoble"
    
    # Create temporary directory for extraction
    local temp_dir=$(mktemp -d)
    
    # Extract Xvfb binary
    extract_from_docker_image "lscr.io/linuxserver/xvfb:ubuntunoble" "/usr/bin/Xvfb" "$temp_dir/Xvfb"
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/bin"
    cp "$temp_dir/Xvfb" "$SCRIPT_DIR/rootfs/usr/bin/Xvfb"
    chmod +x "$SCRIPT_DIR/rootfs/usr/bin/Xvfb"
    
    # Extract Selkies frontend from Alpine image
    info "Extracting pre-built Selkies frontend..."
    pull_docker_image "ghcr.io/linuxserver/baseimage-alpine:3.21"
    
    # This will be extracted during the frontend build process in the multi-stage build
    # For now, we'll handle this in the source build section
    
    # Cleanup
    rm -rf "$temp_dir"
    
    info "✓ Docker image extraction completed"
}

# =============================================================================
# SOURCE BUILDS
# =============================================================================

build_selkies_from_source() {
    info "Building Selkies from source..."
    
    # Install Python packages
    pip3 install pixelflux pcmflux --break-system-packages
    
    # Download and build selkies
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    curl -o selkies.tar.gz -L "https://github.com/selkies-project/selkies/archive/e1adbd8c5213fcc00b56d05337cf62d5701b2ed7.tar.gz"
    tar xf selkies.tar.gz
    cd selkies-*
    
    # Install main selkies package
    pip3 install . --break-system-packages
    
    # Build joystick interposer
    info "Building joystick interposer..."
    cd addons/js-interposer
    gcc -shared -fPIC -ldl -o selkies_joystick_interposer.so joystick_interposer.c
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/lib"
    cp selkies_joystick_interposer.so "$SCRIPT_DIR/rootfs/usr/lib/selkies_joystick_interposer.so"
    
    # Build fake udev
    info "Building fake udev library..."
    cd ../fake-udev
    make
    
    # Copy to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/opt/lib"
    cp libudev.so.1.0.0-fake "$SCRIPT_DIR/rootfs/opt/lib/libudev.so.1.0.0-fake"
    
    # Frontend build (simulating the multi-stage build)
    info "Building frontend components..."
    cd ../gst-web-core
    npm install
    npm run build
    
    cd ../selkies-dashboard
    npm install
    npm run build
    
    # Create frontend directory structure
    mkdir -p dist/src dist/nginx
    cp ../gst-web-core/dist/selkies-core.js dist/src/
    cp ../universal-touch-gamepad/universalTouchGamepad.js dist/src/
    cp ../gst-web-core/nginx/* dist/nginx/
    
    # Copy frontend to rootfs
    mkdir -p "$SCRIPT_DIR/rootfs/usr/share/selkies/www"
    cp -ar dist/* "$SCRIPT_DIR/rootfs/usr/share/selkies/www/"
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    info "✓ Source builds completed successfully"
}

# =============================================================================
# ICONS AND ASSETS
# =============================================================================

setup_icons() {
    info "Setting up icons and assets..."
    
    # Download selkies icons
    mkdir -p "$SCRIPT_DIR/rootfs/usr/share/selkies/www"
    curl -o "$SCRIPT_DIR/rootfs/usr/share/selkies/www/icon.png" \
        "https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/selkies-logo.png"
    curl -o "$SCRIPT_DIR/rootfs/usr/share/selkies/www/favicon.ico" \
        "https://raw.githubusercontent.com/linuxserver/docker-templates/refs/heads/master/linuxserver.io/img/selkies-icon.ico"
    
    info "✓ Icons and assets setup completed"
}

# =============================================================================
# OPENBOX CONFIGURATION
# =============================================================================

configure_openbox() {
    info "Configuring OpenBox window manager..."
    
    # Apply OpenBox tweaks from Dockerfile
    sed -i \
        -e 's/NLIMC/NLMC/g' \
        -e '/debian-menu/d' \
        -e 's|</applications>|  <application class="*"><maximized>yes</maximized><position force="yes"><x>0</x><y>0</y></position></application>\n</applications>|' \
        -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
        /etc/xdg/openbox/rc.xml
    
    info "✓ OpenBox configuration completed"
}

# =============================================================================
# USER SETUP
# =============================================================================

setup_users() {
    info "Setting up users and permissions..."
    
    # Configure sudo for abc user
    sed -e 's/%sudo	ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' -i /etc/sudoers
    
    # Create abc user if it doesn't exist
    if ! id abc &>/dev/null; then
        useradd -m -s /bin/bash abc
    fi
    
    # Set password and groups
    echo "abc:abc" | chpasswd
    usermod -s /bin/bash abc
    usermod -aG sudo abc
    
    # Docker-in-Docker support
    useradd -U dockremap || true
    usermod -G dockremap dockremap
    echo 'dockremap:165536:65536' >> /etc/subuid
    echo 'dockremap:165536:65536' >> /etc/subgid
    
    # Add abc to docker group
    usermod -aG docker abc
    
    info "✓ User setup completed"
}

# =============================================================================
# PROOT-APPS SETUP
# =============================================================================

setup_proot_apps() {
    info "Setting up proot-apps..."
    
    mkdir -p /proot-apps/
    local papps_release=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]')
    
    curl -L "https://github.com/linuxserver/proot-apps/releases/download/${papps_release}/proot-apps-x86_64.tar.gz" \
        | tar -xzf - -C /proot-apps/
    
    echo "${papps_release}" > /proot-apps/pversion
    
    info "✓ proot-apps setup completed"
}

# =============================================================================
# DOCKER-IN-DOCKER SETUP
# =============================================================================

setup_docker_in_docker() {
    info "Setting up Docker-in-Docker support..."
    
    # Download dind script
    curl -o /usr/local/bin/dind -L "https://raw.githubusercontent.com/moby/moby/master/hack/dind"
    chmod +x /usr/local/bin/dind
    
    # Configure nsswitch
    echo 'hosts: files dns' > /etc/nsswitch.conf
    
    info "✓ Docker-in-Docker setup completed"
}

# =============================================================================
# LOCALE SETUP
# =============================================================================

setup_locales() {
    info "Setting up locales..."
    
    # Enable locales (only if excludes file exists - LinuxServer.io specific)
    if [[ -f /etc/dpkg/dpkg.cfg.d/excludes ]]; then
        debug "Found dpkg excludes file, enabling locales"
        sed -i '/locale/d' /etc/dpkg/dpkg.cfg.d/excludes
    else
        debug "No dpkg excludes file found, skipping locale exclusion removal"
    fi
    
    # Install locales from lang-stash
    debug "Installing locales from lang-stash..."
    for locale in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs 2>/dev/null || echo ""); do
        if [[ -n "$locale" ]]; then
            debug "Installing locale: $locale"
            localedef -i "$locale" -f UTF-8 "$locale".UTF-8 || warn "Failed to install locale: $locale"
        fi
    done
    
    # Ensure basic locales are available
    if ! locale -a | grep -q "en_US.utf8"; then
        debug "Installing basic en_US.UTF-8 locale"
        localedef -i en_US -f UTF-8 en_US.UTF-8 || warn "Failed to install en_US.UTF-8 locale"
    fi
    
    info "✓ Locale setup completed"
}

# =============================================================================
# THEME SETUP
# =============================================================================

setup_theme() {
    info "Setting up themes..."
    
    # Download and install theme
    curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
        | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/
    
    info "✓ Theme setup completed"
}

# =============================================================================
# CONFIGURATION FILES
# =============================================================================

setup_configuration_files() {
    info "Setting up configuration files..."
    
    # Configuration files are already in rootfs structure
    # Just verify they exist
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/autostart" ]]; then
        error "Missing autostart file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/menu.xml" ]]; then
        error "Missing menu.xml file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/startwm.sh" ]]; then
        error "Missing startwm.sh file in rootfs"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/rootfs/defaults/default.conf" ]]; then
        error "Missing default.conf file in rootfs"
        return 1
    fi
    
    info "✓ Configuration files verified in rootfs"
}

# =============================================================================
# SYSTEMD SERVICES
# =============================================================================

create_systemd_services() {
    info "Verifying systemd services in rootfs..."
    
    # Verify all systemd service files exist in rootfs
    local services=("selkies-setup.service" "xvfb.service" "selkies-pulseaudio.service" "selkies-nginx.service" "selkies.service" "selkies-desktop.service")
    
    for service in "${services[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/rootfs/etc/systemd/system/$service" ]]; then
            error "Missing systemd service file: $service"
            return 1
        fi
    done
    
    info "✓ All systemd service files verified in rootfs"
}

# =============================================================================
# SYSTEMD SCRIPTS
# =============================================================================

create_systemd_scripts() {
    info "Verifying systemd helper scripts in rootfs..."
    
    # Verify all helper scripts exist in rootfs
    local scripts=("init-nginx.sh" "init-selkies-config.sh" "init-video.sh" "svc-de.sh")
    
    for script in "${scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/rootfs/etc/selkies/$script" ]]; then
            error "Missing systemd helper script: $script"
            return 1
        fi
        if [[ ! -x "$SCRIPT_DIR/rootfs/etc/selkies/$script" ]]; then
            error "Helper script not executable: $script"
            return 1
        fi
    done
    
    info "✓ All systemd helper scripts verified in rootfs"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    info "Verifying environment configuration..."
    
    # Verify environment file exists in rootfs
    if [[ ! -f "$SCRIPT_DIR/rootfs/etc/environment" ]]; then
        error "Missing environment file in rootfs"
        return 1
    fi
    
    # Verify /config directory exists in rootfs
    if [[ ! -d "$SCRIPT_DIR/rootfs/config" ]]; then
        mkdir -p "$SCRIPT_DIR/rootfs/config"
        info "Created /config directory in rootfs"
    fi
    
    info "✓ Environment configuration verified"
}

# =============================================================================
# CLEANUP
# =============================================================================

cleanup_installation() {
    info "Cleaning up installation..."
    
    # Remove development dependencies
    apt-get purge -y --autoremove \
        libopus-dev \
        libpulse-dev \
        python3-dev \
        python3-pip || true
    
    # Clean package cache
    apt-get autoclean
    
    # Remove temporary files
    rm -rf \
        /config/.cache \
        /config/.npm \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*
    
    info "✓ Cleanup completed"
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

main() {
    info "Starting Selkies installation process..."
    
    # Update TODO status
    # Phase 3 tasks
    install_dev_dependencies
    setup_repositories
    install_main_packages
    extract_docker_images
    build_selkies_from_source
    setup_icons
    configure_openbox
    setup_users
    setup_proot_apps
    setup_docker_in_docker
    setup_locales
    setup_theme
    setup_configuration_files
    create_systemd_services
    create_systemd_scripts
    setup_environment
    
    # Copy rootfs to system
    info "Copying rootfs files to system..."
    copy_rootfs "$SCRIPT_DIR/rootfs"
    
    # Create /config directory and set permissions
    mkdir -p /config
    chown abc:abc /config
    chmod 755 /config
    
    # Create /defaults directory and copy files
    mkdir -p /defaults
    cp "$SCRIPT_DIR/rootfs/defaults"/* /defaults/
    chown -R abc:abc /defaults
    
    # Disable system nginx service to prevent port conflicts with selkies-nginx
    info "Disabling system nginx service to prevent conflicts..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    
    # Enable systemd services (only top-level services with WantedBy directives)
    info "Enabling systemd services..."
    enable_service "selkies-setup"
    enable_service "selkies"
    enable_service "selkies-desktop"
    
    # Note: xvfb, selkies-pulseaudio, and selkies-nginx services
    # are started automatically by dependency chains and should not be enabled directly
    # This prevents circular dependencies that caused services to be skipped at boot
    
    # Start Docker service
    systemctl start docker
    systemctl enable docker
    
    # Cleanup
    cleanup_installation
    
    info "✅ Selkies installation completed successfully!"
    info "Services enabled:"
    info "  - selkies-setup.service (Device and permission setup)"
    info "  - selkies.service (Main selkies process)"
    info "  - selkies-desktop.service (Desktop environment)"
    info ""
    info "Dependency services (started automatically):"
    info "  - xvfb.service (Virtual display server)"
    info "  - selkies-pulseaudio.service (Audio server)"
    info "  - selkies-nginx.service (Web server)"
    info "  - docker.service (System Docker daemon)"
    info ""
    info "To start all services: systemctl start selkies-desktop"
    info "To check status: systemctl status selkies"
    info "Web interface will be available at: https://localhost:443"
}

# Run main installation
main "$@" 